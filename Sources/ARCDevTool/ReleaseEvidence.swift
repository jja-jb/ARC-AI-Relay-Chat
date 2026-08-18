import CryptoKit
import Darwin
import Foundation

private struct ARCCandidateAsset: Codable, Equatable {
    let mediaType: String
    let name: String
    let role: String
    let sha256: String
    let size: Int64

    enum CodingKeys: String, CodingKey {
        case mediaType = "media_type"
        case name, role, sha256, size
    }
}

private struct ARCCandidateManifest: Codable, Equatable {
    let architectures: [String]
    let assets: [ARCCandidateAsset]
    let knowledgeSha256: String
    let licenseSha256: String
    let minimumMacOS: String
    let product: String
    let revision: String
    let schema: String
    let tag: String
    let version: String

    enum CodingKeys: String, CodingKey {
        case architectures, assets
        case knowledgeSha256 = "knowledge_sha256"
        case licenseSha256 = "license_sha256"
        case minimumMacOS = "minimum_mac_os"
        case product, revision, schema, tag, version
    }
}

private struct ARCDVTReport {
    let version: String
    let tag: String
    let revision: String
    let candidateManifestSHA256: String
    let tester: String
    let testedAt: String
    let arm64Mac: String
    let dmgSHA256: String
    let literatureSHA256: String
    let sourceSHA256: String
}

private struct ARCReleaseMetadata: Codable {
    let appNotarizationId: String
    let architectures: [String]
    let bundleIdentifier: String
    let candidateManifestSha256: String
    let dmgNotarizationId: String
    let dvtReportSha256: String
    let knowledgeSha256: String
    let licenseSha256: String
    let minimumMacOS: String
    let product: String
    let result: String
    let revision: String
    let schema: String
    let signingIdentity: String
    let tag: String
    let testedAt: String
    let tester: String
    let version: String

    enum CodingKeys: String, CodingKey {
        case appNotarizationId = "app_notarization_id"
        case architectures
        case bundleIdentifier = "bundle_identifier"
        case candidateManifestSha256 = "candidate_manifest_sha256"
        case dmgNotarizationId = "dmg_notarization_id"
        case dvtReportSha256 = "dvt_report_sha256"
        case knowledgeSha256 = "knowledge_sha256"
        case licenseSha256 = "license_sha256"
        case minimumMacOS = "minimum_mac_os"
        case product, result, revision, schema
        case signingIdentity = "signing_identity"
        case tag
        case testedAt = "tested_at"
        case tester, version
    }
}

extension ARCReleaseSupport {
    static let requiredDVTTests = [
        "DVT-001-SOURCE",
        "DVT-002-NATIVE-BUILD",
        "DVT-003-INSTALL",
        "DVT-004-FIRST-ROOM",
        "DVT-005-TWO-AI-ACTIVE",
        "DVT-006-QUALIFICATION-FAILURE",
        "DVT-007-PRODUCER-CHANGE",
        "DVT-008-REPLACE-AND-RETIRE",
        "DVT-009-MESSAGES-AND-WORK",
        "DVT-010-POLLING-RECOVERY",
        "DVT-011-ROOM-INTEGRITY",
        "DVT-012-PRIVACY-AND-OFFLINE",
        "DVT-013-ACCESSIBILITY",
        "DVT-014-AGE-14-USABILITY",
        "DVT-015-SIGNING-NOTARIZATION",
    ]

    static func writeCandidateManifest(
        version: String,
        tag: String,
        revision: String,
        dmg: URL,
        literature: URL,
        source: URL,
        knowledgeSHA256: String,
        output: URL
    ) throws {
        try requireReleaseIdentity(
            version: version, tag: tag, revision: revision,
            knowledgeSHA256: knowledgeSHA256
        )
        let expectedDMG = "ARC-\(version).dmg"
        let expectedLiterature = "ARC_AI_Relay_Chat_Literature.pdf"
        let expectedSource = "ARC-\(version)-source.tar.gz"
        guard dmg.lastPathComponent == expectedDMG,
              literature.lastPathComponent == expectedLiterature,
              source.lastPathComponent == expectedSource else {
            throw DevToolError.message("candidate artifact names differ from the release identity")
        }
        let manifest = ARCCandidateManifest(
            architectures: ["arm64"],
            assets: [
                try candidateAsset(
                    dmg, mediaType: "application/x-apple-diskimage", role: "mac_distribution"
                ),
                try candidateAsset(
                    literature, mediaType: "application/pdf", role: "product_literature"
                ),
                try candidateAsset(
                    source, mediaType: "application/gzip", role: "complete_source"
                ),
            ].sorted { bytewiseLess($0.name, $1.name) },
            knowledgeSha256: knowledgeSHA256,
            licenseSha256: licenseSHA256,
            minimumMacOS: "15.0",
            product: "ARC",
            revision: revision,
            schema: "arc.release-candidate/1",
            tag: tag,
            version: version
        )
        try writeCanonicalJSON(manifest, to: output)
    }

    static func checkDVT(report: URL, candidateManifest: URL) throws {
        let candidateBytes = try KnowledgeContainer.readBounded(
            candidateManifest, maximum: 1_048_576
        )
        let candidate = try decodeCandidate(candidateBytes)
        try verifyCandidateFiles(candidate, beside: candidateManifest)
        let dvt = try parseDVT(
            try KnowledgeContainer.readBounded(report, maximum: 1_048_576)
        )
        guard dvt.version == candidate.version,
              dvt.tag == candidate.tag,
              dvt.revision == candidate.revision,
              dvt.candidateManifestSHA256 == digest(candidateBytes),
              dvt.dmgSHA256 == candidate.assets.first(where: {
                  $0.role == "mac_distribution"
              })?.sha256,
              dvt.literatureSHA256 == candidate.assets.first(where: {
                  $0.role == "product_literature"
              })?.sha256,
              dvt.sourceSHA256 == candidate.assets.first(where: {
                  $0.role == "complete_source"
              })?.sha256 else {
            throw DevToolError.message("DVT report does not bind the exact candidate")
        }
    }

    static func writeReleaseMetadata(
        candidateManifest: URL,
        dvtReport: URL,
        signingIdentity: String,
        appNotarizationID: String,
        dmgNotarizationID: String,
        output: URL
    ) throws {
        try checkDVT(report: dvtReport, candidateManifest: candidateManifest)
        let candidateBytes = try KnowledgeContainer.readBounded(
            candidateManifest, maximum: 1_048_576
        )
        let reportBytes = try KnowledgeContainer.readBounded(
            dvtReport, maximum: 1_048_576
        )
        let candidate = try decodeCandidate(candidateBytes)
        let report = try parseDVT(reportBytes)
        let identity = try releaseText(signingIdentity, label: "signing identity", maximum: 512)
        guard isLowerUUID(appNotarizationID), isLowerUUID(dmgNotarizationID) else {
            throw DevToolError.message("notarization identifiers must be lowercase UUIDs")
        }
        let metadata = ARCReleaseMetadata(
            appNotarizationId: appNotarizationID,
            architectures: candidate.architectures,
            bundleIdentifier: "org.jonnybass.arc",
            candidateManifestSha256: digest(candidateBytes),
            dmgNotarizationId: dmgNotarizationID,
            dvtReportSha256: digest(reportBytes),
            knowledgeSha256: candidate.knowledgeSha256,
            licenseSha256: candidate.licenseSha256,
            minimumMacOS: candidate.minimumMacOS,
            product: candidate.product,
            result: "PASS",
            revision: candidate.revision,
            schema: "arc.release/1",
            signingIdentity: identity,
            tag: candidate.tag,
            testedAt: report.testedAt,
            tester: report.tester,
            version: candidate.version
        )
        try writeCanonicalJSON(metadata, to: output)
    }

    static func writeChecksums(directory: URL, version: String, output: URL) throws {
        try KnowledgeContainer.requireRealDirectory(directory)
        let expected = [
            "ARC-\(version).dmg",
            "ARC_AI_Relay_Chat_Literature.pdf",
            "ARC-\(version)-source.tar.gz",
            "ARC-\(version)-MANIFEST.json",
            "ARC-\(version)-DVT-REPORT.txt",
            "RELEASE-METADATA.json",
        ].sorted(by: bytewiseLess)
        guard output.deletingLastPathComponent().standardizedFileURL == directory.standardizedFileURL,
              output.lastPathComponent == "SHA256SUMS" else {
            throw DevToolError.message("SHA256SUMS must be new inside the release directory")
        }
        let actual = try regularLeaves(in: directory)
        guard actual == Set(expected) else {
            throw DevToolError.message("release directory has missing or extra files before checksums")
        }
        var text = ""
        for name in expected {
            let value = try fileIdentity(directory.appending(path: name))
            text += "\(value.sha256)  \(name)\n"
        }
        try KnowledgeContainer.writeNew(Data(text.utf8), to: output, mode: 0o644)
    }

    static func checkRelease(directory: URL, version: String) throws {
        try KnowledgeContainer.requireRealDirectory(directory)
        guard validVersion(version) else {
            throw DevToolError.message("release version is invalid")
        }
        let names = [
            "ARC-\(version).dmg",
            "ARC_AI_Relay_Chat_Literature.pdf",
            "ARC-\(version)-source.tar.gz",
            "ARC-\(version)-MANIFEST.json",
            "ARC-\(version)-DVT-REPORT.txt",
            "RELEASE-METADATA.json",
            "SHA256SUMS",
        ]
        guard try regularLeaves(in: directory) == Set(names) else {
            throw DevToolError.message("release directory has missing or extra files")
        }

        let manifestURL = directory.appending(path: "ARC-\(version)-MANIFEST.json")
        let reportURL = directory.appending(path: "ARC-\(version)-DVT-REPORT.txt")
        let manifestBytes = try KnowledgeContainer.readBounded(
            manifestURL, maximum: 1_048_576
        )
        let reportBytes = try KnowledgeContainer.readBounded(
            reportURL, maximum: 1_048_576
        )
        let candidate = try decodeCandidate(manifestBytes)
        try verifyCandidateFiles(candidate, beside: manifestURL)
        try checkDVT(report: reportURL, candidateManifest: manifestURL)
        let report = try parseDVT(reportBytes)

        let metadataURL = directory.appending(path: "RELEASE-METADATA.json")
        let metadataBytes = try KnowledgeContainer.readBounded(
            metadataURL, maximum: 1_048_576
        )
        guard metadataBytes.last == 0x0A,
              !metadataBytes.dropLast().contains(0x0A) else {
            throw DevToolError.message("release metadata is not one canonical line")
        }
        let decoder = JSONDecoder()
        let metadata = try decoder.decode(
            ARCReleaseMetadata.self, from: Data(metadataBytes.dropLast())
        )
        var canonicalMetadata = try canonicalJSON(metadata)
        canonicalMetadata.append(0x0A)
        guard canonicalMetadata == metadataBytes,
              metadata.schema == "arc.release/1",
              metadata.product == candidate.product,
              metadata.version == candidate.version,
              metadata.tag == candidate.tag,
              metadata.revision == candidate.revision,
              metadata.result == "PASS",
              metadata.minimumMacOS == candidate.minimumMacOS,
              metadata.architectures == candidate.architectures,
              metadata.bundleIdentifier == "org.jonnybass.arc",
              metadata.knowledgeSha256 == candidate.knowledgeSha256,
              metadata.licenseSha256 == candidate.licenseSha256,
              metadata.candidateManifestSha256 == digest(manifestBytes),
              metadata.dvtReportSha256 == digest(reportBytes),
              metadata.testedAt == report.testedAt,
              metadata.tester == report.tester,
              isLowerUUID(metadata.appNotarizationId),
              isLowerUUID(metadata.dmgNotarizationId) else {
            throw DevToolError.message("release metadata does not bind the candidate")
        }
        _ = try releaseText(
            metadata.signingIdentity, label: "signing identity", maximum: 512
        )

        let checksumNames = names.filter { $0 != "SHA256SUMS" }
            .sorted(by: bytewiseLess)
        var expectedChecksums = ""
        for name in checksumNames {
            let identity = try fileIdentity(directory.appending(path: name))
            expectedChecksums += "\(identity.sha256)  \(name)\n"
        }
        let actualChecksums = try KnowledgeContainer.readBounded(
            directory.appending(path: "SHA256SUMS"), maximum: 65_536
        )
        guard actualChecksums == Data(expectedChecksums.utf8) else {
            throw DevToolError.message("SHA256SUMS does not bind every release asset")
        }
    }

    private static func candidateAsset(
        _ url: URL, mediaType: String, role: String
    ) throws -> ARCCandidateAsset {
        let identity = try fileIdentity(url)
        return ARCCandidateAsset(
            mediaType: mediaType,
            name: url.lastPathComponent,
            role: role,
            sha256: identity.sha256,
            size: identity.size
        )
    }

    private static func fileIdentity(_ url: URL) throws -> (size: Int64, sha256: String) {
        let descriptor = Darwin.open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
        guard descriptor >= 0 else {
            throw DevToolError.message("release input is not one bounded regular file")
        }
        defer { Darwin.close(descriptor) }
        var before = stat()
        guard fstat(descriptor, &before) == 0,
              (before.st_mode & S_IFMT) == S_IFREG,
              before.st_nlink == 1,
              before.st_size > 0,
              before.st_size <= 4 * 1_024 * 1_024 * 1_024 else {
            throw DevToolError.message("release input is not one bounded regular file")
        }
        var hasher = SHA256()
        var count: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: 1_048_576)
        while true {
            let readCount = buffer.withUnsafeMutableBytes {
                Darwin.read(descriptor, $0.baseAddress, $0.count)
            }
            if readCount == 0 { break }
            if readCount < 0 {
                if errno == EINTR { continue }
                throw DevToolError.message("release input changed while hashing")
            }
            count += Int64(readCount)
            guard count <= before.st_size else {
                throw DevToolError.message("release input changed while hashing")
            }
            hasher.update(data: Data(buffer.prefix(readCount)))
        }
        var after = stat()
        var pathState = stat()
        guard fstat(descriptor, &after) == 0,
              lstat(url.path, &pathState) == 0,
              count == before.st_size,
              before.st_dev == after.st_dev,
              before.st_ino == after.st_ino,
              before.st_size == after.st_size,
              before.st_mtimespec.tv_sec == after.st_mtimespec.tv_sec,
              before.st_mtimespec.tv_nsec == after.st_mtimespec.tv_nsec,
              before.st_ctimespec.tv_sec == after.st_ctimespec.tv_sec,
              before.st_ctimespec.tv_nsec == after.st_ctimespec.tv_nsec,
              after.st_dev == pathState.st_dev,
              after.st_ino == pathState.st_ino else {
            throw DevToolError.message("release input changed while hashing")
        }
        return (count, hasher.finalize().map { String(format: "%02x", $0) }.joined())
    }

    private static func decodeCandidate(_ data: Data) throws -> ARCCandidateManifest {
        guard data.last == 0x0A, !data.dropLast().contains(0x0A) else {
            throw DevToolError.message("candidate manifest is not one canonical line")
        }
        let decoder = JSONDecoder()
        let value = try decoder.decode(ARCCandidateManifest.self, from: Data(data.dropLast()))
        var canonical = try canonicalJSON(value)
        canonical.append(0x0A)
        guard canonical == data,
              value.schema == "arc.release-candidate/1",
              value.product == "ARC",
              value.minimumMacOS == "15.0",
              value.architectures == ["arm64"],
              value.licenseSha256 == licenseSHA256,
              value.assets.count == 3 else {
            throw DevToolError.message("candidate manifest is invalid or noncanonical")
        }
        try requireReleaseIdentity(
            version: value.version, tag: value.tag, revision: value.revision,
            knowledgeSHA256: value.knowledgeSha256
        )
        let names = value.assets.map(\.name)
        guard names == names.sorted(by: bytewiseLess), Set(names).count == 3,
              Set(names) == [
                  "ARC-\(value.version).dmg",
                  "ARC-\(value.version)-source.tar.gz",
                  "ARC_AI_Relay_Chat_Literature.pdf",
              ],
              value.assets.allSatisfy({
                  isSHA256($0.sha256) && $0.size > 0 && !$0.name.contains("/")
              }) else {
            throw DevToolError.message("candidate asset list is invalid")
        }
        guard let dmg = value.assets.first(where: { $0.name.hasSuffix(".dmg") }),
              dmg.mediaType == "application/x-apple-diskimage",
              dmg.role == "mac_distribution",
              let literature = value.assets.first(where: { $0.name.hasSuffix(".pdf") }),
              literature.mediaType == "application/pdf",
              literature.role == "product_literature",
              let source = value.assets.first(where: { $0.name.hasSuffix("-source.tar.gz") }),
              source.mediaType == "application/gzip",
              source.role == "complete_source" else {
            throw DevToolError.message("candidate asset roles or media types differ")
        }
        return value
    }

    private static func verifyCandidateFiles(
        _ candidate: ARCCandidateManifest, beside manifest: URL
    ) throws {
        let directory = manifest.deletingLastPathComponent()
        for asset in candidate.assets {
            let actual = try fileIdentity(directory.appending(path: asset.name))
            guard actual.size == asset.size, actual.sha256 == asset.sha256 else {
                throw DevToolError.message(
                    "candidate asset differs from its manifest: \(asset.name)"
                )
            }
        }
    }

    private static func parseDVT(_ data: Data) throws -> ARCDVTReport {
        guard !data.isEmpty, data.count <= 1_048_576, !data.contains(0),
              !data.contains(0x0D), data.last == 0x0A,
              let text = String(data: data, encoding: .utf8) else {
            throw DevToolError.message("DVT report is not canonical UTF-8 text")
        }
        let lines = text.dropLast().split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
        guard lines.count == 18 + requiredDVTTests.count,
              lines[0] == "ARC 1.0 EXTERNAL DVT REPORT",
              lines[16] == "checks:" else {
            throw DevToolError.message("DVT report shape differs from the required template")
        }
        func field(_ index: Int, _ name: String) throws -> String {
            let prefix = "\(name): "
            guard lines[index].hasPrefix(prefix) else {
                throw DevToolError.message("DVT report field \(name) is missing")
            }
            return try releaseText(
                String(lines[index].dropFirst(prefix.count)), label: name, maximum: 1_024
            )
        }
        guard try field(1, "schema") == "arc.dvt/1",
              try field(15, "decision") == "PASS" else {
            throw DevToolError.message("DVT report schema or decision is not PASS")
        }
        let version = try field(2, "version")
        let tag = try field(3, "tag")
        let revision = try field(4, "revision")
        let manifestSHA = try field(5, "candidate_manifest_sha256")
        let tester = try field(6, "tester")
        _ = try field(7, "independence")
        let startedAt = try field(8, "started_at")
        let finishedAt = try field(9, "finished_at")
        let machines = try field(10, "machines")
        let systems = try field(11, "systems")
        let toolchains = try field(12, "toolchains")
        let preparedHashes = try field(13, "prepared_hashes")
        guard try field(14, "deviations") == "No deviations." else {
            throw DevToolError.message("DVT deviations must be resolved before PASS")
        }
        let machineParts = machines.components(separatedBy: " | ")
        let systemParts = systems.components(separatedBy: " | ")
        let toolchainParts = toolchains.components(separatedBy: " | ")
        let hashParts = preparedHashes.components(separatedBy: " | ")
        guard machineParts.count == 1, machineParts[0].hasPrefix("arm64="),
              systemParts.count == 1, systemParts[0].hasPrefix("arm64="),
              toolchainParts.count == 1, toolchainParts[0].hasPrefix("arm64="),
              hashParts.count == 4,
              hashParts[0].hasPrefix("dmg="), hashParts[1].hasPrefix("source="),
              hashParts[2].hasPrefix("literature="),
              hashParts[3] == "manifest=\(manifestSHA)",
              isSHA256(String(hashParts[0].dropFirst("dmg=".count))),
              isSHA256(String(hashParts[1].dropFirst("source=".count))),
              isSHA256(String(hashParts[2].dropFirst("literature=".count))),
              isSHA256(manifestSHA), isRevision(revision),
              tag == "v\(version)", validVersion(version),
              validTimestamp(startedAt), validTimestamp(finishedAt),
              startedAt <= finishedAt else {
            throw DevToolError.message("DVT identity, time, or machine evidence is invalid")
        }
        let arm64 = try releaseText(
            String(machineParts[0].dropFirst("arm64=".count)),
            label: "arm64 machine", maximum: 512
        )
        for (label, parts) in [("systems", systemParts), ("toolchains", toolchainParts)] {
            _ = try releaseText(
                String(parts[0].dropFirst("arm64=".count)),
                label: "arm64 \(label)", maximum: 512
            )
        }
        let dmgSHA = String(hashParts[0].dropFirst("dmg=".count))
        let sourceSHA = String(hashParts[1].dropFirst("source=".count))
        let literatureSHA = String(hashParts[2].dropFirst("literature=".count))
        for (offset, test) in requiredDVTTests.enumerated() {
            let line = lines[17 + offset]
            let prefix = "test: \(test) | PASS | "
            guard line.hasPrefix(prefix) else {
                throw DevToolError.message("DVT test \(test) is missing or not PASS")
            }
            _ = try releaseText(
                String(line.dropFirst(prefix.count)), label: "DVT evidence", maximum: 2_048
            )
        }
        guard lines.last == "end: arc.dvt/1" else {
            throw DevToolError.message("DVT report end marker is missing")
        }
        return ARCDVTReport(
            version: version, tag: tag, revision: revision,
            candidateManifestSHA256: manifestSHA, tester: tester,
            testedAt: finishedAt, arm64Mac: arm64,
            dmgSHA256: dmgSHA, literatureSHA256: literatureSHA,
            sourceSHA256: sourceSHA
        )
    }

    private static func writeCanonicalJSON<T: Encodable>(_ value: T, to url: URL) throws {
        var data = try canonicalJSON(value)
        data.append(0x0A)
        try KnowledgeContainer.writeNew(data, to: url, mode: 0o644)
    }

    private static func canonicalJSON<T: Encodable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }

    private static func requireReleaseIdentity(
        version: String, tag: String, revision: String, knowledgeSHA256: String
    ) throws {
        guard validVersion(version), tag == "v\(version)", isRevision(revision),
              isSHA256(knowledgeSHA256) else {
            throw DevToolError.message("release identity is invalid")
        }
    }

    private static func validVersion(_ value: String) -> Bool {
        value.range(of: #"^1\.[0-9]+\.[0-9]+$"#, options: .regularExpression) != nil
    }

    private static func isRevision(_ value: String) -> Bool {
        value.utf8.count == 40 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func isLowerUUID(_ value: String) -> Bool {
        value.count == 36 && value == value.lowercased()
            && UUID(uuidString: value)?.uuidString.lowercased() == value
    }

    private static func validTimestamp(_ value: String) -> Bool {
        guard value == value.trimmingCharacters(in: .whitespacesAndNewlines),
              value.hasSuffix("Z") else { return false }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: value) != nil
    }

    private static func releaseText(
        _ value: String, label: String, maximum: Int
    ) throws -> String {
        let normalized = value.precomposedStringWithCanonicalMapping
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let upper = value.uppercased()
        guard value == normalized, !value.isEmpty, value.utf8.count <= maximum,
              !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains),
              !["TODO", "TBD", "PLACEHOLDER", "NONE", "NOT RUN", "SKIPPED"]
                .contains(where: upper.contains),
              !value.contains("<"), !value.contains(">"),
              !value.contains("["), !value.contains("]") else {
            throw DevToolError.message("\(label) is empty, noncanonical, or unfinished")
        }
        return value
    }

    private static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static func bytewiseLess(_ left: String, _ right: String) -> Bool {
        Array(left.utf8).lexicographicallyPrecedes(Array(right.utf8))
    }

    private static func isSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    private static func regularLeaves(in root: URL) throws -> Set<String> {
        let rootPath = comparablePath(root)
        guard let enumerator = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: nil, options: [],
            errorHandler: { _, _ in false }
        ) else { throw DevToolError.message("cannot enumerate release directory") }
        var result = Set<String>()
        while let item = enumerator.nextObject() as? URL {
            let itemPath = comparablePath(item)
            guard itemPath.hasPrefix(rootPath + "/") else {
                throw DevToolError.message("release enumeration escaped its root")
            }
            let relative = String(itemPath.dropFirst(rootPath.count + 1))
            var info = stat()
            guard lstat(item.path, &info) == 0 else {
                throw DevToolError.message("release directory changed while reading")
            }
            switch info.st_mode & S_IFMT {
            case S_IFDIR: continue
            case S_IFREG: result.insert(relative)
            default: throw DevToolError.message("release directory contains a link or special file")
            }
        }
        return result
    }
}
