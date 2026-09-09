import CryptoKit
import Darwin
import Foundation

private struct ARCInstallManifest: Codable {
    let schema: Int
    let product: String
    let version: String
    let knowledgeSha256: String
    let entries: [ARCInstallEntry]
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

private struct ARCBrandManifest: Codable {
    let format: String
    let assets: [ARCBrandAsset]
}

private struct ARCBrandAsset: Codable {
    let path: String
    let mediaType: String
    let dimensions: String?
    let sha256: String
}

enum ARCReleaseSupport {
    static let terseSpecification = "languages/terse/001-terse-language-specification.txt"
    static let terseDigest = "languages/terse/TERSE.sha256"
    static let licenseSHA256 =
        "988a906412af48c37e35fc3272402818677d31572fb65ea931aa98f21e003c24"

    static func writeInstallManifest(
        contents: URL,
        version: String,
        knowledgeSHA256: String,
        output: URL
    ) throws {
        guard version.range(
            of: #"^[12]\.[0-9]+\.[0-9]+$"#,
            options: .regularExpression
        ) != nil, isSHA256(knowledgeSHA256) else {
            throw DevToolError.message("install manifest identity is invalid")
        }
        let install = contents.appending(path: "Resources/install", directoryHint: .isDirectory)
        try KnowledgeContainer.requireRealDirectory(install)
        let command = install.appending(path: "bin/arc")
        let current = install.appending(path: "current", directoryHint: .isDirectory)
        try KnowledgeContainer.requireRegularFile(command, below: install, maximum: 64 * 1_024 * 1_024)
        try KnowledgeContainer.requireRealDirectory(current)

        let requiredCurrent = Set([
            "ARC_AI.arc-kb",
            "ARC_AI.sha256",
            "legal/LICENSE",
            "legal/NOTICE.md",
            terseSpecification, terseDigest,
        ] + KnowledgeContainer.canonicalSources
            .filter { $0.logical.hasPrefix("specifications/") }
            .map(\.logical))

        let actualCurrent = try regularLeaves(in: current)
        guard actualCurrent == requiredCurrent else {
            let missing = requiredCurrent.subtracting(actualCurrent).sorted().joined(separator: ", ")
            let extra = actualCurrent.subtracting(requiredCurrent).sorted().joined(separator: ", ")
            throw DevToolError.message(
                "installed current tree differs (missing: \(missing); extra: \(extra))"
            )
        }

        let container = current.appending(path: "ARC_AI.arc-kb")
        let containerData = try KnowledgeContainer.readBounded(
            container,
            maximum: KnowledgeContainer.maxContainerBytes
        )
        let actualKnowledge = KnowledgeContainer.hex(KnowledgeContainer.sha256(containerData))
        guard actualKnowledge == knowledgeSHA256 else {
            throw DevToolError.message("knowledge digest does not match install-manifest input")
        }
        let digestFile = try KnowledgeContainer.readBounded(
            current.appending(path: "ARC_AI.sha256"),
            maximum: 65
        )
        guard digestFile == Data((knowledgeSHA256 + "\n").utf8) else {
            throw DevToolError.message("ARC_AI.sha256 is not the exact knowledge digest plus LF")
        }
        try checkTersePayload(current)

        var entries: [ARCInstallEntry] = []
        entries.append(try installEntry(
            file: command,
            path: "current/bin/arc",
            source: "Resources/install/bin/arc",
            mode: 0o755
        ))
        for relative in actualCurrent.sorted(by: bytewiseLess) {
            entries.append(try installEntry(
                file: current.appending(path: relative),
                path: "current/\(relative)",
                source: "Resources/install/current/\(relative)",
                mode: 0o644
            ))
        }
        entries.sort { bytewiseLess($0.path, $1.path) }
        let manifest = ARCInstallManifest(
            schema: 1,
            product: "ARC",
            version: version,
            knowledgeSha256: knowledgeSHA256,
            entries: entries
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var data = try encoder.encode(manifest)
        data.append(0x0A)
        try KnowledgeContainer.writeNew(data, to: output, mode: 0o644)
    }

    static func checkSource(_ root: URL) throws {
        try KnowledgeContainer.requireRealDirectory(root)
        let required = [
            "Package.swift", "Makefile", "README.md", "INSTALL.md",
            "ARCHITECTURE.md", "DEVELOPING.md", "LICENSE", "LICENSE-SUMMARY.md",
            "NOTICE.md", "CHANGELOG.md", "RELEASE_CHECKLIST.md", "SECURITY.md",
            "SUPPORT.md", "GOVERNANCE.md", "CONTRIBUTING.md", "CODE_OF_CONDUCT.md",
            "TRADEMARKS.md", "app/Info.plist", "app/Assets/arc-app-icon.svg",
            "app/Assets/arc-mark.svg", "app/Assets/ARC.icns", "app/Assets/README.txt",
            "app/Sources/ARCApp/PrivacyInfo.xcprivacy",
            "brand/ASSET-MANIFEST.json", "brand/README.md",
            "brand/arc-app-icon.svg", "brand/arc-mark.svg",
            "brand/arc-product-brief.html",
            "brand/arc-relay-artwork.png", "brand/arc-relay-artwork.prompt.txt",
            "brand/arc-social-preview.png",
            "docs/ARC_AI.md", "docs/USER_GUIDE.md", "docs/GETTING_STARTED.md",
            "docs/PRODUCT_BRIEF.md",
            "docs/CLI_REFERENCE.md", "docs/DURABLE_FORMAT.md", "docs/JSON_OUTPUT.md",
            "docs/MACOS_INSTALLER.md", "docs/PRIVACY.md", "docs/SECURITY_MODEL.md",
            "docs/RELEASING.md", "docs/DVT_GUIDE.md", "docs/DVT_REPORT_TEMPLATE.md",
            "docs/TRACEABILITY.md",
            "man/arc.1", "knowledge/include/arc_knowledge.h",
            "knowledge/src/arc_knowledge.c", "knowledge/tests/knowledge_api_test.c",
            "Sources/ARCDevTool/ARCDevToolMain.swift",
            "Sources/ARCDevTool/ReleaseEvidence.swift",
            "Sources/ARCDevTool/ReleaseSupport.swift",
            "Sources/ARCDevTool/KnowledgeContainer.swift",
            terseSpecification,
        ] + KnowledgeContainer.canonicalSources.map(\.source)
        for relative in Set(required) {
            try KnowledgeContainer.requireRegularFile(
                root.appending(path: relative),
                below: root,
                maximum: 16 * 1_024 * 1_024
            )
        }

        let forbiddenPaths = [
            "pyproject.toml", "requirements-release.txt", "MANIFEST.in",
            "THIRD_PARTY_NOTICES.md", "app/Package.swift", ".release-venv",
            "src/arc", "tools", "release",
        ]
        for relative in forbiddenPaths where FileManager.default.fileExists(
            atPath: root.appending(path: relative).path
        ) {
            throw DevToolError.message("obsolete source path remains: \(relative)")
        }

        let license = try KnowledgeContainer.readBounded(
            root.appending(path: "LICENSE"), maximum: 65_536
        )
        guard hex(license) == licenseSHA256 else {
            throw DevToolError.message("Hummingbird LICENSE digest differs")
        }
        let package = try String(
            decoding: KnowledgeContainer.readBounded(
                root.appending(path: "Package.swift"), maximum: 131_072
            ),
            as: UTF8.self
        )
        guard !package.contains(".package(") else {
            throw DevToolError.message("Package.swift has a remote package dependency")
        }

        let makefile = String(
            decoding: try KnowledgeContainer.readBounded(
                root.appending(path: "Makefile"), maximum: 131_072
            ),
            as: UTF8.self
        )
        guard makefile.contains("set -o pipefail"),
              makefile.contains("rev-parse --show-toplevel") else {
            throw DevToolError.message(
                "source-archive-test is not fail-closed outside a Git checkout"
            )
        }

        let specDuty = String(
            decoding: try KnowledgeContainer.readBounded(
                root.appending(
                    path: "10_specs/platform_support/005-arc-ai-instructions-qualification-duty-and-polling.txt"
                ),
                maximum: 1_048_576
            ),
            as: UTF8.self
        )
        guard specDuty.contains("remove every recurring, scheduled, and heartbeat"),
              specDuty.contains("or ARC has exited"),
              !specDuty.contains(
                "Carry forward next_after and stop immediately if ARC reports RETIRED."
              ) else {
            throw DevToolError.message(
                "qualification-duty handoff text is stale versus shipped retirement automation removal"
            )
        }

        let architecture = String(
            decoding: try KnowledgeContainer.readBounded(
                root.appending(path: "ARCHITECTURE.md"), maximum: 131_072
            ),
            as: UTF8.self
        )
        guard architecture.contains("never silently removes"),
              !architecture.contains("removal of oldest retained entries is observable")
        else {
            throw DevToolError.message(
                "ARCHITECTURE.md Activity retention text is stale versus DS-007"
            )
        }

        try checkTree(root)
        try checkDocumentation(root)
        try checkTraceability(root)
        try checkBrandAssets(root)
        try checkPrivacyManifest(root.appending(path: "app/Sources/ARCApp/PrivacyInfo.xcprivacy"))
        try checkInfoPlist(root.appending(path: "app/Info.plist"), version: "2.1.0")
    }

    static func checkApp(_ app: URL, version: String, release: Bool) throws {
        guard app.pathExtension == "app" else {
            throw DevToolError.message("app path must end in .app")
        }
        try KnowledgeContainer.requireRealDirectory(app)
        let contents = app.appending(path: "Contents", directoryHint: .isDirectory)
        let executable = contents.appending(path: "MacOS/ARC")
        let command = contents.appending(path: "Resources/install/bin/arc")
        try KnowledgeContainer.requireRegularFile(executable, below: app, maximum: 128 * 1_024 * 1_024)
        try KnowledgeContainer.requireRegularFile(command, below: app, maximum: 128 * 1_024 * 1_024)
        try checkInfoPlist(contents.appending(path: "Info.plist"), version: version)
        try checkPrivacyManifest(contents.appending(path: "Resources/PrivacyInfo.xcprivacy"))
        guard !FileManager.default.fileExists(atPath: contents.appending(path: "Frameworks").path)
        else { throw DevToolError.message("ARC.app contains a forbidden Frameworks directory") }

        if release {
            try requireArm64MachO(executable)
            try requireArm64MachO(command)
        } else {
            try requireMachO(executable)
            try requireMachO(command)
        }

        let executableBytes = try KnowledgeContainer.readBounded(
            executable, maximum: 128 * 1_024 * 1_024
        )
        let developmentRootMarker = Data("ARC_DEVELOPMENT_ROOT".utf8)
        let carriesDevelopmentRoot = executableBytes.range(of: developmentRootMarker) != nil
        guard release ? !carriesDevelopmentRoot : carriesDevelopmentRoot else {
            throw DevToolError.message(
                release
                    ? "release app admits ARC_DEVELOPMENT_ROOT"
                    : "development app does not admit ARC_DEVELOPMENT_ROOT"
            )
        }

        let manifestURL = contents.appending(path: "Resources/install/ARC-INSTALL-MANIFEST.json")
        let data = try KnowledgeContainer.readBounded(manifestURL, maximum: 16 * 1_024 * 1_024)
        let manifest = try decodeInstallManifest(data)
        guard manifest.version == version else {
            throw DevToolError.message("app and install-manifest versions differ")
        }
        let expectedCurrent = Set([
            "ARC_AI.arc-kb", "ARC_AI.sha256", "legal/LICENSE", "legal/NOTICE.md",
            terseSpecification, terseDigest,
        ] + KnowledgeContainer.canonicalSources
            .filter { $0.logical.hasPrefix("specifications/") }
            .map(\.logical))
        let expectedPaths = Set(["current/bin/arc"] + expectedCurrent.map { "current/\($0)" })
        guard Set(manifest.entries.map(\.path)) == expectedPaths,
              manifest.entries.count == expectedPaths.count else {
            throw DevToolError.message("install manifest does not name the exact native payload")
        }
        for entry in manifest.entries {
            let expectedSource = entry.path == "current/bin/arc"
                ? "Resources/install/bin/arc"
                : "Resources/install/\(entry.path)"
            guard entry.source == expectedSource,
                  entry.mode == (entry.path == "current/bin/arc" ? 0o755 : 0o644) else {
                throw DevToolError.message("install manifest path mapping or mode differs")
            }
            let source = contents.appending(path: entry.source)
            try KnowledgeContainer.requireRegularFile(source, below: contents, maximum: 128 * 1_024 * 1_024)
            let bytes = try Data(contentsOf: source, options: [.mappedIfSafe])
            guard Int64(bytes.count) == entry.size, hex(bytes) == entry.sha256 else {
                throw DevToolError.message("app install source differs: \(entry.source)")
            }
        }
        let actualInstall = try regularLeaves(
            in: contents.appending(path: "Resources/install", directoryHint: .isDirectory)
        )
        let sourcePrefix = "Resources/install/"
        let expectedInstall = Set(manifest.entries.map {
            String($0.source.dropFirst(sourcePrefix.count))
        } + ["ARC-INSTALL-MANIFEST.json"])
        guard actualInstall == expectedInstall else {
            throw DevToolError.message("app install directory contains missing or extra leaves")
        }
        let container = contents.appending(path: "Resources/install/current/ARC_AI.arc-kb")
        let containerBytes = try KnowledgeContainer.readBounded(
            container, maximum: KnowledgeContainer.maxContainerBytes
        )
        guard hex(containerBytes) == manifest.knowledgeSha256 else {
            throw DevToolError.message("app knowledge container differs from manifest identity")
        }
        let digestBytes = try KnowledgeContainer.readBounded(
            contents.appending(path: "Resources/install/current/ARC_AI.sha256"), maximum: 65
        )
        guard digestBytes == Data((manifest.knowledgeSha256 + "\n").utf8) else {
            throw DevToolError.message("app knowledge digest file differs")
        }
        try checkTersePayload(contents.appending(path: "Resources/install/current"))
    }

    static func checkTersePayload(_ current: URL) throws {
        let text = try KnowledgeContainer.readBounded(current.appending(path: terseSpecification), maximum: 524_288)
        try KnowledgeContainer.validateText(text)
        let digest = try KnowledgeContainer.readBounded(current.appending(path: terseDigest), maximum: 65)
        guard digest == Data((hex(text) + "\n").utf8) else {
            throw DevToolError.message("Terse specification and digest differ")
        }
    }

    private static func installEntry(
        file: URL,
        path: String,
        source: String,
        mode: Int
    ) throws -> ARCInstallEntry {
        guard safeRelative(path), safeRelative(source) else {
            throw DevToolError.message("unsafe install path")
        }
        let data = try Data(contentsOf: file, options: [.mappedIfSafe])
        var info = stat()
        guard lstat(file.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              Int(info.st_mode & 0o777) == mode else {
            throw DevToolError.message("install source has wrong type or mode: \(source)")
        }
        return ARCInstallEntry(
            kind: "file", mode: mode, path: path, sha256: hex(data),
            size: Int64(data.count), source: source, target: nil
        )
    }

    private static func regularLeaves(in root: URL) throws -> Set<String> {
        let rootPath = comparablePath(root)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in false }
        ) else { throw DevToolError.message("cannot enumerate \(root.path)") }
        var files = Set<String>()
        while let item = enumerator.nextObject() as? URL {
            let itemPath = comparablePath(item)
            guard itemPath.hasPrefix(rootPath + "/") else {
                throw DevToolError.message("install enumeration escaped its root")
            }
            let relative = String(itemPath.dropFirst(rootPath.count + 1))
            var info = stat()
            guard lstat(item.path, &info) == 0 else {
                throw DevToolError.message("install tree changed while reading")
            }
            switch info.st_mode & S_IFMT {
            case S_IFREG: files.insert(relative)
            case S_IFDIR: continue
            default: throw DevToolError.message("install tree contains a link or special file")
            }
        }
        return files
    }

    static func comparablePath(_ url: URL) -> String {
        let path = url.standardizedFileURL.path
        return path == "/tmp" || path.hasPrefix("/tmp/") ? "/private" + path : path
    }

    private static func checkTree(_ root: URL) throws {
        let ignoredRoots = [".git/", ".build/", "build/", "output/"]
        let rootPath = comparablePath(root)
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in false }
        ) else { throw DevToolError.message("cannot enumerate source") }
        while let item = enumerator.nextObject() as? URL {
            let itemPath = comparablePath(item)
            guard itemPath.hasPrefix(rootPath + "/") else {
                throw DevToolError.message("source enumeration escaped its root")
            }
            let relative = String(itemPath.dropFirst(rootPath.count + 1))
            if ignoredRoots.contains(where: { relative == String($0.dropLast()) || relative.hasPrefix($0) }) {
                if relative == ".git" || relative == ".build" || relative == "build" || relative == "output" {
                    enumerator.skipDescendants()
                }
                continue
            }
            var info = stat()
            guard lstat(item.path, &info) == 0 else {
                throw DevToolError.message("source changed while reading")
            }
            guard (info.st_mode & S_IFMT) == S_IFREG || (info.st_mode & S_IFMT) == S_IFDIR else {
                throw DevToolError.message("source contains a link or special file: \(relative)")
            }
            if (info.st_mode & S_IFMT) == S_IFREG {
                let lower = relative.lowercased()
                guard !lower.hasSuffix(".py"), !lower.hasSuffix(".pyc"),
                      !lower.contains("/__pycache__/") else {
                    throw DevToolError.message("obsolete source-language artifact remains: \(relative)")
                }
            }
        }
    }

    private static func checkDocumentation(_ root: URL) throws {
        let forbidden = [
            "python", "sqlite", "sbom", "runtime-stage", "wheel",
            "import room", "export room", "room import", "room export",
            ".arcroom package", "public.file-url", "utexportedtypedeclarations",
            "arc-app-bridge", "arc-knowledge-export",
        ]
        let extensions = Set(["md", "txt", "1", "html"])
        let rootPath = comparablePath(root)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [],
            errorHandler: { _, _ in false }
        ) else { throw DevToolError.message("cannot enumerate documentation") }
        while let item = enumerator.nextObject() as? URL {
            let itemPath = comparablePath(item)
            guard itemPath.hasPrefix(rootPath + "/") else {
                throw DevToolError.message("documentation enumeration escaped its root")
            }
            let relative = String(itemPath.dropFirst(rootPath.count + 1))
            if relative == ".git" || relative == ".build" || relative == "build" || relative == "output" {
                enumerator.skipDescendants()
                continue
            }
            guard extensions.contains(item.pathExtension.lowercased()) else { continue }
            var info = stat()
            guard lstat(item.path, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
                  info.st_size <= 2 * 1_024 * 1_024 else { continue }
            let data = try Data(contentsOf: item)
            guard !data.starts(with: [0xef, 0xbb, 0xbf]), !data.contains(0),
                  !data.contains(0x0d), let text = String(data: data, encoding: .utf8) else {
                throw DevToolError.message("documentation is not canonical UTF-8/LF: \(relative)")
            }
            let lower = text.lowercased()
            if let word = forbidden.first(where: lower.contains) {
                throw DevToolError.message("obsolete documentation claim `\(word)` remains: \(relative)")
            }
        }
    }

    private static func checkTraceability(_ root: URL) throws {
        let traceURL = root.appending(path: "docs/TRACEABILITY.md")
        let trace = String(decoding: try KnowledgeContainer.readBounded(
            traceURL, maximum: 262_144
        ), as: UTF8.self)
        let expression = try NSRegularExpression(
            pattern: #"(?m)^([A-Z]{1,4}-[0-9]{3}) "#
        )
        var missing: [String] = []
        for source in KnowledgeContainer.canonicalSources
        where source.source.hasPrefix("10_specs/") {
            let text = String(decoding: try KnowledgeContainer.readBounded(
                root.appending(path: source.source), maximum: 1_048_576
            ), as: UTF8.self)
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in expression.matches(in: text, range: range) {
                guard let swiftRange = Range(match.range(at: 1), in: text) else { continue }
                let identifier = String(text[swiftRange])
                if !trace.contains("`\(identifier)`") { missing.append(identifier) }
            }
        }
        guard missing.isEmpty else {
            throw DevToolError.message(
                "traceability is missing: \(missing.sorted().joined(separator: ", "))"
            )
        }
    }

    private static func checkBrandAssets(_ root: URL) throws {
        let data = try KnowledgeContainer.readBounded(
            root.appending(path: "brand/ASSET-MANIFEST.json"), maximum: 65_536
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(ARCBrandManifest.self, from: data)
        let expected = Set([
            "arc-app-icon.svg", "arc-mark.svg", "arc-product-brief.html",
            "arc-relay-artwork.png",
            "arc-relay-artwork.prompt.txt", "arc-social-preview.png",
        ])
        let names = manifest.assets.map(\.path)
        guard manifest.format == "arc-brand-assets-1",
              names == names.sorted(by: bytewiseLess),
              names.count == expected.count, Set(names) == expected else {
            throw DevToolError.message("brand asset manifest identity differs")
        }
        for asset in manifest.assets {
            guard !asset.path.contains("/"), isSHA256(asset.sha256),
                  !asset.mediaType.isEmpty else {
                throw DevToolError.message("brand asset manifest entry is invalid")
            }
            let file = root.appending(path: "brand/\(asset.path)")
            try KnowledgeContainer.requireRegularFile(
                file, below: root, maximum: 16 * 1_024 * 1_024
            )
            let bytes = try Data(contentsOf: file, options: [.mappedIfSafe])
            guard hex(bytes) == asset.sha256 else {
                throw DevToolError.message("brand asset digest differs: \(asset.path)")
            }
        }
        for name in ["arc-app-icon.svg", "arc-mark.svg"] {
            let brand = try KnowledgeContainer.readBounded(
                root.appending(path: "brand/\(name)"), maximum: 1_048_576
            )
            let app = try KnowledgeContainer.readBounded(
                root.appending(path: "app/Assets/\(name)"), maximum: 1_048_576
            )
            guard brand == app else {
                throw DevToolError.message("app and public editable artwork differ: \(name)")
            }
        }
    }

    private static func checkInfoPlist(_ url: URL, version: String) throws {
        let data = try KnowledgeContainer.readBounded(url, maximum: 131_072)
        guard let value = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any],
        value["CFBundleIdentifier"] as? String == "org.jonnybass.arc",
        value["CFBundleExecutable"] as? String == "ARC",
        value["CFBundleShortVersionString"] as? String == version,
        value["CFBundleVersion"] as? String == version.split(separator: ".").joined(),
        value["LSMinimumSystemVersion"] as? String == "15.0",
        value["CFBundlePackageType"] as? String == "APPL",
        value["CFBundleDocumentTypes"] == nil,
        value["UTExportedTypeDeclarations"] == nil,
        value["UTImportedTypeDeclarations"] == nil else {
            throw DevToolError.message("ARC Info.plist identity or product surface is invalid")
        }
    }

    private static func checkPrivacyManifest(_ url: URL) throws {
        let data = try KnowledgeContainer.readBounded(url, maximum: 131_072)
        guard let value = try PropertyListSerialization.propertyList(
            from: data, options: [], format: nil
        ) as? [String: Any],
        value["NSPrivacyTracking"] as? Bool == false,
        let collected = value["NSPrivacyCollectedDataTypes"] as? [Any], collected.isEmpty,
        let rows = value["NSPrivacyAccessedAPITypes"] as? [[String: Any]], rows.count == 2 else {
            throw DevToolError.message("privacy manifest collection declaration is invalid")
        }
        var actual: [String: [String]] = [:]
        for row in rows {
            guard Set(row.keys) == ["NSPrivacyAccessedAPIType", "NSPrivacyAccessedAPITypeReasons"],
                  let type = row["NSPrivacyAccessedAPIType"] as? String,
                  let reasons = row["NSPrivacyAccessedAPITypeReasons"] as? [String],
                  actual[type] == nil
            else { throw DevToolError.message("privacy accessed-API row is invalid") }
            actual[type] = reasons
        }
        guard actual == [
            "NSPrivacyAccessedAPICategoryFileTimestamp": ["C617.1"],
            "NSPrivacyAccessedAPICategorySystemBootTime": ["35F9.1"],
        ] else { throw DevToolError.message("privacy required reasons differ") }
    }

    private static func decodeInstallManifest(_ data: Data) throws -> ARCInstallManifest {
        guard data.last == 0x0A, !data.dropLast().contains(0x0A) else {
            throw DevToolError.message("install manifest is not one canonical line")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let manifest = try decoder.decode(ARCInstallManifest.self, from: Data(data.dropLast()))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var canonical = try encoder.encode(manifest)
        canonical.append(0x0A)
        guard canonical == data, manifest.schema == 1, manifest.product == "ARC",
              isSHA256(manifest.knowledgeSha256), !manifest.entries.isEmpty else {
            throw DevToolError.message("install manifest is invalid or noncanonical")
        }
        var prior: String?
        for entry in manifest.entries {
            guard entry.kind == "file", entry.target == nil,
                  entry.mode == 0o644 || entry.mode == 0o755,
                  safeRelative(entry.path), safeRelative(entry.source),
                  isSHA256(entry.sha256), entry.size >= 0,
                  prior.map({ bytewiseLess($0, entry.path) }) ?? true else {
                throw DevToolError.message("install manifest entry is invalid")
            }
            prior = entry.path
        }
        return manifest
    }

    private static func requireMachO(_ url: URL) throws {
        let data = try KnowledgeContainer.readBounded(url, maximum: 128 * 1_024 * 1_024)
        guard data.count >= 4 else { throw DevToolError.message("shipping executable is empty") }
        let magic = data.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard [0xcafebabe, 0xcafebabf, 0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe]
            .contains(magic) else { throw DevToolError.message("shipping executable is not Mach-O") }
    }

    private static func requireArm64MachO(_ url: URL) throws {
        let data = try KnowledgeContainer.readBounded(url, maximum: 128 * 1_024 * 1_024)
        guard data.count >= 8 else {
            throw DevToolError.message("Apple silicon executable is truncated")
        }
        let bytes = Array(data.prefix(8))
        let magic = bytes[0...3].reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        let cpuType = bytes[4...7].enumerated().reduce(UInt32(0)) {
            $0 | (UInt32($1.element) << UInt32($1.offset * 8))
        }
        guard magic == 0xcffaedfe, cpuType == 0x0100000c else {
            throw DevToolError.message("release executable is not arm64-only Mach-O")
        }
    }

    private static func safeRelative(_ value: String) -> Bool {
        guard !value.isEmpty, !value.hasPrefix("/"), !value.hasSuffix("/"),
              !value.contains("//"), value.utf8.count <= 4_096 else { return false }
        return value.split(separator: "/", omittingEmptySubsequences: false).allSatisfy {
            !$0.isEmpty && $0 != "." && $0 != ".." && !$0.hasPrefix(".")
        }
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func bytewiseLess(_ left: String, _ right: String) -> Bool {
        Array(left.utf8).lexicographicallyPrecedes(Array(right.utf8))
    }

    private static func hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}
