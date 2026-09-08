import CryptoKit
import ARCCore
import Darwin
import Foundation

protocol ARCInstallationProtocol: Sendable {
    func ensureInstalled(rootURL: URL, force: Bool) throws
}

enum ARCInstallationError: LocalizedError, Equatable {
    case bundleIncomplete
    case manifestInvalid(String)
    case installedFilesUnsafe
    case publicationFailed

    var errorDescription: String? {
        switch self {
        case .bundleIncomplete:
            "ARC's signed installation files are incomplete. Reinstall ARC from the "
                + "verified disk image."
        case .manifestInvalid(let reason):
            "ARC's signed installation list is invalid (\(reason)). Reinstall ARC from "
                + "the verified disk image."
        case .installedFilesUnsafe:
            "ARC could not safely use its local installation folder. Check that it is "
                + "not a link, then try again."
        case .publicationFailed:
            "ARC could not finish installing its local files. Try again. Your rooms "
                + "were not changed."
        }
    }
}

enum ARCInstallStep: Sendable {
    case staged
    case currentPublished
    case currentDurable
}

/// Test-only crash injection. Production never supplies an installation
/// failpoint, so this cannot change normal app behavior.
enum ARCInstallAbruptStop: Error {
    case requested
}

private struct ARCInstallEntry: Codable {
    let kind: String
    let mode: Int
    let path: String
    let sha256: String
    let size: Int64
    let source: String
    let target: String?

    private enum CodingKeys: String, CodingKey {
        case kind, mode, path, sha256, size, source, target
    }

    func encode(to encoder: Encoder) throws {
        var values = encoder.container(keyedBy: CodingKeys.self)
        try values.encode(kind, forKey: .kind)
        try values.encode(mode, forKey: .mode)
        try values.encode(path, forKey: .path)
        try values.encode(sha256, forKey: .sha256)
        try values.encode(size, forKey: .size)
        try values.encode(source, forKey: .source)
        if let target {
            try values.encode(target, forKey: .target)
        } else {
            try values.encodeNil(forKey: .target)
        }
    }
}

private struct ARCInstallManifest: Codable {
    let schema: Int
    let product: String
    let version: String
    let knowledgeSha256: String
    let entries: [ARCInstallEntry]
}

/// Verifies and installs only ARC's native launcher and read-only support files.
/// It never enumerates, opens, moves, or removes a room file.
struct ARCInstallation: ARCInstallationProtocol, Sendable {
    typealias Failpoint = @Sendable (ARCInstallStep) throws -> Void

    private static let receiptPath = "current/ARC-INSTALL-MANIFEST.json"
    private let contentsURL: URL
    private let manifestURL: URL
    private let failpoint: Failpoint?
    private let developmentBypass: Bool

    init(
        bundleURL: URL = Bundle.main.bundleURL,
        failpoint: Failpoint? = nil,
        developmentBypass: Bool = true
    ) {
        contentsURL = bundleURL.appendingPathComponent("Contents", isDirectory: true)
        manifestURL = contentsURL.appendingPathComponent(
            "Resources/install/ARC-INSTALL-MANIFEST.json"
        )
        self.failpoint = failpoint
        self.developmentBypass = developmentBypass
    }

    func ensureInstalled(rootURL: URL, force: Bool = false) throws {
        do {
            try install(rootURL: rootURL, force: force)
        } catch let error as ARCInstallationError {
            throw error
        } catch {
            throw ARCInstallationError.publicationFailed
        }
    }

    private func install(rootURL: URL, force: Bool) throws {
        #if DEBUG
        if developmentBypass, Bundle.main.bundleURL.pathExtension != "app" { return }
        #endif

        let root = rootURL.standardized
        guard root.isFileURL, root.path.hasPrefix("/") else {
            throw ARCInstallationError.installedFilesUnsafe
        }
        try prepare(root)

        guard try kind(at: manifestURL) == .file else {
            throw ARCInstallationError.bundleIncomplete
        }
        let manifestData = try boundedData(at: manifestURL, maximum: 16 * 1_024 * 1_024)
        let manifest = try decodeCanonicalManifest(manifestData)
        try validate(manifest, appVersionMustMatch: true)
        let requiredTerse = Set([ARCCommunication.specificationRelativePath, ARCCommunication.digestRelativePath]
            .map { "current/" + $0 })
        guard requiredTerse.isSubset(of: Set(manifest.entries.map(\.path))) else {
            throw ARCInstallationError.bundleIncomplete
        }

        if !force, try installedFilesMatch(
            root: root,
            manifest: manifest,
            manifestData: manifestData
        ) {
            try synchronizeDirectory(root)
            return
        }

        try verifyExactBundleLeaves(manifest)
        try publish(root: root, manifest: manifest, manifestData: manifestData)
    }

    private func decodeCanonicalManifest(_ data: Data) throws -> ARCInstallManifest {
        guard data.last == 0x0A, !data.dropLast().contains(0x0A) else {
            throw ARCInstallationError.manifestInvalid("text is not one canonical line")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest: ARCInstallManifest
        do {
            manifest = try decoder.decode(ARCInstallManifest.self, from: Data(data.dropLast()))
        } catch {
            throw ARCInstallationError.manifestInvalid("JSON could not be read")
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var canonical = try encoder.encode(manifest)
        canonical.append(0x0A)
        guard canonical == data else {
            throw ARCInstallationError.manifestInvalid(
                "JSON is not canonical or contains extra fields"
            )
        }
        return manifest
    }

    private func validate(
        _ manifest: ARCInstallManifest,
        appVersionMustMatch: Bool
    ) throws {
        guard manifest.schema == 1,
              manifest.product == "ARC",
              manifest.version.range(
                  of: #"^1\.[0-9]+\.[0-9]+$"#,
                  options: .regularExpression
              ) != nil,
              isSHA256(manifest.knowledgeSha256),
              !manifest.entries.isEmpty,
              manifest.entries.count <= 10_000 else {
            throw ARCInstallationError.manifestInvalid("identity is unsupported")
        }
        if appVersionMustMatch,
           Bundle.main.bundleURL.pathExtension == "app",
           let appVersion = Bundle.main.object(
               forInfoDictionaryKey: "CFBundleShortVersionString"
           ) as? String,
           appVersion != manifest.version {
            throw ARCInstallationError.manifestInvalid(
                "app and installed-file versions differ"
            )
        }

        var priorPath: String?
        var paths = Set<String>()
        var foldedPaths = Set<String>()
        var sources = Set<String>()
        var totalBytes: Int64 = 0
        var launcher: ARCInstallEntry?
        var knowledge: ARCInstallEntry?

        for entry in manifest.entries {
            guard entry.kind == "file",
                  entry.target == nil,
                  entry.mode >= 0, entry.mode <= 0o777,
                  entry.size >= 0,
                  isSHA256(entry.sha256),
                  safeRelative(entry.path),
                  safeRelative(entry.source),
                  entry.path.hasPrefix("current/"),
                  entry.path != Self.receiptPath,
                  sourceMapsExactly(entry) else {
                throw ARCInstallationError.manifestInvalid("one file entry is unsafe")
            }
            if let priorPath,
               !Array(priorPath.utf8).lexicographicallyPrecedes(Array(entry.path.utf8)) {
                throw ARCInstallationError.manifestInvalid("entries are not strictly sorted")
            }
            priorPath = entry.path
            let folded = entry.path.folding(
                options: [.caseInsensitive, .diacriticInsensitive],
                locale: Locale(identifier: "en_US_POSIX")
            )
            guard paths.insert(entry.path).inserted,
                  foldedPaths.insert(folded).inserted,
                  sources.insert(entry.source).inserted,
                  totalBytes <= 4_294_967_296 - entry.size else {
                throw ARCInstallationError.manifestInvalid("entries collide or are too large")
            }
            totalBytes += entry.size
            if entry.path == "current/bin/arc" { launcher = entry }
            if entry.path == "current/ARC_AI.arc-kb" { knowledge = entry }
        }

        guard let launcher,
              launcher.mode & 0o111 != 0,
              let knowledge,
              knowledge.sha256 == manifest.knowledgeSha256 else {
            throw ARCInstallationError.manifestInvalid(
                "native launcher or knowledge container is missing"
            )
        }
    }

    private func verifyExactBundleLeaves(_ manifest: ARCInstallManifest) throws {
        var actual = Set<String>()
        try enumerateFiles(
            at: contentsURL.appendingPathComponent("Resources/install/current"),
            prefix: "Resources/install/current",
            into: &actual
        )
        let launcher = "Resources/install/bin/arc"
        guard try kind(at: contentsURL.appendingPathComponent(launcher)) == .file else {
            throw ARCInstallationError.bundleIncomplete
        }
        actual.insert(launcher)
        guard actual == Set(manifest.entries.map(\.source)) else {
            throw ARCInstallationError.bundleIncomplete
        }
        for entry in manifest.entries {
            try verify(entry, at: contentsURL.appendingPathComponent(entry.source))
        }
    }

    private func installedFilesMatch(
        root: URL,
        manifest: ARCInstallManifest,
        manifestData: Data
    ) throws -> Bool {
        let receipt = root.appendingPathComponent(Self.receiptPath)
        guard try kind(at: root.appendingPathComponent("current")) == .directory,
              let metadata = try metadata(at: receipt),
              metadata.kind == .file,
              metadata.mode == 0o644,
              (try? boundedData(at: receipt, maximum: 16 * 1_024 * 1_024))
                == manifestData else {
            return false
        }
        do {
            var actualCurrent = Set<String>()
            try enumerateFiles(
                at: root.appendingPathComponent("current", isDirectory: true),
                prefix: "current",
                into: &actualCurrent
            )
            let expectedCurrent = Set(
                manifest.entries.filter { $0.path.hasPrefix("current/") }.map(\.path)
            ).union([Self.receiptPath])
            guard actualCurrent == expectedCurrent else { return false }
            for entry in manifest.entries {
                try verify(entry, at: root.appendingPathComponent(entry.path))
            }
            return true
        } catch {
            return false
        }
    }

    private func publish(
        root: URL,
        manifest: ARCInstallManifest,
        manifestData: Data
    ) throws {
        let manager = FileManager.default
        let stage = root.appendingPathComponent(
            ".arc-install-stage-\(UUID().uuidString.lowercased())",
            isDirectory: true
        )
        try manager.createDirectory(
            at: stage,
            withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o700]
        )
        var cleanStage = true
        defer {
            if cleanStage {
                try? manager.removeItem(at: stage)
                try? synchronizeDirectory(root)
            }
        }

        let ownsCurrent = priorOwnership(root: root)
        var currentPublished = false
        var currentSwapped = false

        do {
            for entry in manifest.entries {
                let destination = stage.appendingPathComponent(entry.path)
                try manager.createDirectory(
                    at: destination.deletingLastPathComponent(),
                    withIntermediateDirectories: true,
                    attributes: [.posixPermissions: 0o755]
                )
                try manager.copyItem(
                    at: contentsURL.appendingPathComponent(entry.source),
                    to: destination
                )
                try removeTransitAttributes(destination)
                guard chmod(destination.path, mode_t(entry.mode)) == 0 else {
                    throw ARCInstallationError.publicationFailed
                }
                try verify(entry, at: destination)
                try synchronizeFile(destination)
            }
            let receipt = stage.appendingPathComponent(Self.receiptPath)
            try manifestData.write(to: receipt, options: [.atomic])
            guard chmod(receipt.path, 0o644) == 0 else {
                throw ARCInstallationError.publicationFailed
            }
            try synchronizeFile(receipt)
            let stagedCurrent = stage.appendingPathComponent(
                "current",
                isDirectory: true
            )
            try synchronizeDirectoryTree(stagedCurrent)
            try synchronizeDirectory(stage)
            try failpoint?(.staged)

            let current = root.appendingPathComponent("current", isDirectory: true)
            var replacedLegacy = false
            switch try kind(at: current) {
            case .directory:
                let replaceLegacy: Bool
                if ownsCurrent {
                    replaceLegacy = false
                } else {
                    replaceLegacy = try legacyInstallationCanBeReplaced(root: root)
                }
                guard (ownsCurrent || replaceLegacy), renameSwap(stagedCurrent, current) else {
                    throw ARCInstallationError.installedFilesUnsafe
                }
                currentPublished = true
                currentSwapped = true
                replacedLegacy = replaceLegacy
            case nil:
                guard renameExclusive(stagedCurrent, current) else {
                    throw ARCInstallationError.publicationFailed
                }
                currentPublished = true
            default:
                throw ARCInstallationError.installedFilesUnsafe
            }
            try failpoint?(.currentPublished)
            try synchronizeDirectory(root)
            if replacedLegacy {
                try? removeLegacyRootLauncher(root: root, legacyCurrent: stagedCurrent)
            }
            try failpoint?(.currentDurable)
        } catch {
            if error is ARCInstallAbruptStop {
                cleanStage = false
                throw error
            }
            if currentPublished {
                let current = root.appendingPathComponent("current")
                let stagedCurrent = stage.appendingPathComponent("current")
                if currentSwapped {
                    _ = renameSwap(stagedCurrent, current)
                } else if (try? kind(at: stagedCurrent)) == nil {
                    _ = renamePlain(current, stagedCurrent)
                }
                try? synchronizeDirectory(root)
            }
            if error is ARCInstallationError { throw error }
            throw ARCInstallationError.publicationFailed
        }
    }

    private func removeTransitAttributes(_ url: URL) throws {
        for name in ["com.apple.quarantine", "com.apple.provenance"] {
            let result = url.path.withCString { path in
                name.withCString { removexattr(path, $0, 0) }
            }
            if result != 0, errno != ENOATTR {
                throw ARCInstallationError.publicationFailed
            }
        }
    }

    private func priorOwnership(root: URL) -> Bool {
        let current = root.appendingPathComponent("current", isDirectory: true)
        let receipt = root.appendingPathComponent(Self.receiptPath)
        do {
            guard try kind(at: current) == .directory,
                  let receiptMetadata = try metadata(at: receipt),
                  receiptMetadata.kind == .file,
                  receiptMetadata.mode == 0o644 else { return false }
            let receiptData = try boundedData(at: receipt, maximum: 16 * 1_024 * 1_024)
            let prior = try decodeCanonicalManifest(receiptData)
            try validate(prior, appVersionMustMatch: false)

            var actualCurrent = Set<String>()
            try enumerateFiles(at: current, prefix: "current", into: &actualCurrent)
            let expectedCurrent = Set(
                prior.entries.map(\.path)
            ).union([Self.receiptPath])
            // A missing owned payload needs repair, not a loss of ownership.
            // Unknown leaves still prevent replacement of this directory.
            return actualCurrent.isSubset(of: expectedCurrent)
        } catch {
            return false
        }
    }

    /// ARC 1.0's early review installer used a Python runtime under `current/`
    /// and a separate root `bin/arc` launcher. The native installer never uses
    /// either location, but recognizes that exact, bounded layout so a person
    /// can move to the native build without deleting rooms by hand. Any other
    /// unowned current tree remains a refusal.
    private func legacyInstallationCanBeReplaced(root: URL) throws -> Bool {
        let current = root.appendingPathComponent("current", isDirectory: true)
        let receipt = current.appendingPathComponent("ARC-INSTALL-MANIFEST.json")
        guard try kind(at: current) == .directory,
              let metadata = try metadata(at: receipt),
              metadata.kind == .file,
              metadata.mode == 0o644 else { return false }
        let data = try boundedData(at: receipt, maximum: 16 * 1_024 * 1_024)
        let legacy = try decodeCanonicalManifest(data)
        guard legacy.schema == 1,
              legacy.product == "ARC",
              legacy.entries.count <= 10_000,
              legacy.entries.contains(where: {
                  $0.path == "bin/arc" && $0.kind == "file" && isSHA256($0.sha256)
              }),
              legacy.entries.contains(where: {
                  $0.path == "current/runtime/arc/core.py" && $0.kind == "file"
              }),
              !legacy.entries.contains(where: { $0.path == "current/bin/arc" }),
              legacy.entries.allSatisfy({ legacySafeRelative($0.path) }) else {
            return false
        }

        var expectedCurrent = Set([Self.receiptPath])
        var seen = Set<String>()
        for entry in legacy.entries {
            guard seen.insert(entry.path).inserted else { return false }
            let location = root.appendingPathComponent(entry.path)
            switch entry.kind {
            case "file":
                try verify(entry, at: location)
            case "link":
                guard try legacyLinkMatches(entry, at: location) else { return false }
            default:
                return false
            }
            if entry.path.hasPrefix("current/") {
                expectedCurrent.insert(entry.path)
            }
        }
        var actualCurrent = Set<String>()
        try enumerateLegacyLeaves(at: current, prefix: "current", into: &actualCurrent)
        return actualCurrent == expectedCurrent
    }

    private func removeLegacyRootLauncher(root: URL, legacyCurrent: URL) throws {
        let legacyBin = root.appendingPathComponent("bin", isDirectory: true)
        let legacyLauncher = legacyBin.appendingPathComponent("arc")
        let receipt = legacyCurrent.appendingPathComponent("ARC-INSTALL-MANIFEST.json")
        let data = try boundedData(at: receipt, maximum: 16 * 1_024 * 1_024)
        let manifest = try decodeCanonicalManifest(data)
        guard let launcher = manifest.entries.first(where: { $0.path == "bin/arc" }) else {
            return
        }
        guard try kind(at: legacyBin) == .directory,
              try kind(at: legacyLauncher) == .file,
              try FileManager.default.contentsOfDirectory(atPath: legacyBin.path) == ["arc"] else {
            return
        }
        try verify(launcher, at: legacyLauncher)
        try FileManager.default.removeItem(at: legacyBin)
        try synchronizeDirectory(root)
    }

    private func legacyLinkMatches(_ entry: ARCInstallEntry, at url: URL) throws -> Bool {
        guard entry.target != nil, try kind(at: url) == .link else { return false }
        var buffer = [CChar](repeating: 0, count: 4_097)
        let count = url.path.withCString { readlink($0, &buffer, buffer.count - 1) }
        guard count >= 0 else { return false }
        return String(decoding: buffer.prefix(Int(count)).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            == entry.target
    }

    private func enumerateLegacyLeaves(
        at directory: URL,
        prefix: String,
        into files: inout Set<String>
    ) throws {
        guard try kind(at: directory) == .directory else {
            throw ARCInstallationError.installedFilesUnsafe
        }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            let child = directory.appendingPathComponent(name)
            let relative = "\(prefix)/\(name)"
            switch try kind(at: child) {
            case .directory:
                try enumerateLegacyLeaves(at: child, prefix: relative, into: &files)
            case .file, .link:
                guard files.insert(relative).inserted, files.count <= 10_000 else {
                    throw ARCInstallationError.installedFilesUnsafe
                }
            default:
                throw ARCInstallationError.installedFilesUnsafe
            }
        }
    }

    private enum ItemKind: Equatable { case directory, file, link, other }

    private struct ItemMetadata {
        let kind: ItemKind
        let mode: Int
        let size: Int64
    }

    private func verify(_ entry: ARCInstallEntry, at url: URL) throws {
        guard let item = try metadata(at: url),
              item.kind == .file,
              item.mode == entry.mode,
              item.size == entry.size,
              try sha256(url) == entry.sha256 else {
            throw ARCInstallationError.bundleIncomplete
        }
    }

    private func enumerateFiles(
        at directory: URL,
        prefix: String,
        into files: inout Set<String>
    ) throws {
        guard try kind(at: directory) == .directory else {
            throw ARCInstallationError.bundleIncomplete
        }
        let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .sorted { Array($0.utf8).lexicographicallyPrecedes(Array($1.utf8)) }
        for name in names {
            let child = directory.appendingPathComponent(name)
            let relative = "\(prefix)/\(name)"
            switch try kind(at: child) {
            case .directory:
                try enumerateFiles(at: child, prefix: relative, into: &files)
            case .file:
                guard files.insert(relative).inserted, files.count <= 10_001 else {
                    throw ARCInstallationError.bundleIncomplete
                }
            default:
                throw ARCInstallationError.bundleIncomplete
            }
        }
    }

    private func prepare(_ root: URL) throws {
        try rejectLinkedPathComponents(root)
        switch try kind(at: root) {
        case .directory:
            break
        case nil:
            try FileManager.default.createDirectory(
                at: root,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        default:
            throw ARCInstallationError.installedFilesUnsafe
        }
        try rejectLinkedPathComponents(root)
        guard chmod(root.path, 0o700) == 0 else {
            throw ARCInstallationError.installedFilesUnsafe
        }
    }

    private func rejectLinkedPathComponents(_ url: URL) throws {
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in url.pathComponents.dropFirst() {
            current.appendPathComponent(component)
            var value = stat()
            if lstat(current.path, &value) != 0 {
                if errno == ENOENT { continue }
                throw ARCInstallationError.installedFilesUnsafe
            }
            guard value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR) else {
                throw ARCInstallationError.installedFilesUnsafe
            }
        }
    }

    private func metadata(at url: URL) throws -> ItemMetadata? {
        var value = stat()
        if lstat(url.path, &value) != 0 {
            if errno == ENOENT { return nil }
            throw ARCInstallationError.installedFilesUnsafe
        }
        let itemKind: ItemKind = switch value.st_mode & mode_t(S_IFMT) {
        case mode_t(S_IFDIR): .directory
        case mode_t(S_IFREG): .file
        case mode_t(S_IFLNK): .link
        default: .other
        }
        return ItemMetadata(
            kind: itemKind,
            mode: Int(value.st_mode & 0o777),
            size: Int64(value.st_size)
        )
    }

    private func kind(at url: URL) throws -> ItemKind? { try metadata(at: url)?.kind }

    private func boundedData(at url: URL, maximum: Int) throws -> Data {
        guard let item = try metadata(at: url),
              item.kind == .file,
              item.size >= 0,
              item.size <= maximum else {
            throw ARCInstallationError.bundleIncomplete
        }
        return try Data(contentsOf: url, options: [.mappedIfSafe])
    }

    private func sourceMapsExactly(_ entry: ARCInstallEntry) -> Bool {
        if entry.source == "Resources/install/bin/arc" {
            return entry.path == "current/bin/arc"
        }
        let prefix = "Resources/install/current/"
        return entry.source.hasPrefix(prefix)
            && entry.path == "current/" + entry.source.dropFirst(prefix.count)
    }

    private func safeRelative(_ path: String) -> Bool {
        guard !path.isEmpty,
              path == path.precomposedStringWithCanonicalMapping,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              path.utf8.count <= 4_096 else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { component in
                !component.isEmpty
                    && component != "."
                    && component != ".."
                    && !component.hasPrefix(".")
                    && !component.unicodeScalars.contains(
                        where: CharacterSet.controlCharacters.contains
                    )
            }
    }

    /// Historical ARC payloads contained ordinary dotfiles in bundled Python
    /// examples. They remain safe to identify by their canonical manifest as
    /// long as no component is empty, `.` or `..`; the new native payload
    /// retains the stricter no-hidden-component rule above.
    private func legacySafeRelative(_ path: String) -> Bool {
        guard !path.isEmpty,
              path == path.precomposedStringWithCanonicalMapping,
              !path.hasPrefix("/"),
              !path.contains("\\"),
              path.utf8.count <= 4_096 else { return false }
        return path.split(separator: "/", omittingEmptySubsequences: false)
            .allSatisfy { component in
                !component.isEmpty
                    && component != "."
                    && component != ".."
                    && !component.unicodeScalars.contains(
                        where: CharacterSet.controlCharacters.contains
                    )
            }
    }

    private func isSHA256(_ value: String) -> Bool {
        value.range(of: #"^[0-9a-f]{64}$"#, options: .regularExpression) != nil
    }

    private func synchronizeFile(_ url: URL) throws {
        try synchronize(url, requireDirectory: false)
    }

    private func synchronizeDirectory(_ url: URL) throws {
        try synchronize(url, requireDirectory: true)
    }

    private func synchronizeDirectoryTree(_ directory: URL) throws {
        guard try kind(at: directory) == .directory else {
            throw ARCInstallationError.publicationFailed
        }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) {
            let child = directory.appendingPathComponent(name)
            if try kind(at: child) == .directory {
                try synchronizeDirectoryTree(child)
            }
        }
        try synchronizeDirectory(directory)
    }

    private func synchronize(_ url: URL, requireDirectory: Bool) throws {
        let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw ARCInstallationError.publicationFailed
        }
        defer { close(descriptor) }
        var value = stat()
        guard fstat(descriptor, &value) == 0 else {
            throw ARCInstallationError.publicationFailed
        }
        let isDirectory = value.st_mode & mode_t(S_IFMT) == mode_t(S_IFDIR)
        guard isDirectory == requireDirectory, fsync(descriptor) == 0 else {
            throw ARCInstallationError.publicationFailed
        }
    }

    private func sha256(_ url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while true {
            let data = try handle.read(upToCount: 1_048_576) ?? Data()
            if data.isEmpty { break }
            hash.update(data: data)
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func renameExclusive(_ old: URL, _ new: URL) -> Bool {
        old.path.withCString { oldPath in
            new.path.withCString { newPath in
                renamex_np(oldPath, newPath, UInt32(RENAME_EXCL)) == 0
            }
        }
    }

    private func renamePlain(_ old: URL, _ new: URL) -> Bool {
        old.path.withCString { oldPath in
            new.path.withCString { newPath in rename(oldPath, newPath) == 0 }
        }
    }

    private func renameSwap(_ old: URL, _ new: URL) -> Bool {
        old.path.withCString { oldPath in
            new.path.withCString { newPath in
                renameatx_np(
                    AT_FDCWD,
                    oldPath,
                    AT_FDCWD,
                    newPath,
                    UInt32(RENAME_SWAP)
                ) == 0
            }
        }
    }
}
