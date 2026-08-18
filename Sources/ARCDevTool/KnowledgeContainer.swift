import CryptoKit
import Darwin
import Foundation
import ARCKnowledge

enum DevToolError: Error, CustomStringConvertible {
    case message(String)

    var description: String {
        switch self {
        case .message(let text): text
        }
    }
}

struct KnowledgeMember: Equatable {
    let name: String
    let required: Bool
    let payload: Data
    let digest: Data
}

struct ParsedKnowledge {
    let digest: Data
    let members: [KnowledgeMember]
    let omitted: [String]
}

enum KnowledgeContainer {
    static let magic = Data("ARCKB001".utf8)
    static let formatVersion: UInt32 = 1
    static let profile: UInt32 = 1
    static let headerBytes = 64
    static let entryBytes = 160
    static let maxContainerBytes = 8_388_608
    static let maxMembers = 32
    static let maxNameBytes = 96
    static let maxMemberBytes = 524_288
    static let manifestName = "ARC-KNOWLEDGE-MANIFEST.txt"

    static let canonicalSources: [(logical: String, source: String, required: Bool)] = [
        ("ai/arc-ai.txt", "docs/ARC_AI.md", true),
        ("help/arc-help.txt", "docs/USER_GUIDE.md", true),
        ("legal/hummingbird-license.txt", "LICENSE", true),
        ("legal/notice.txt", "NOTICE.md", true),
        ("manual/arc-man-page.txt", "man/arc.1", true),
        ("specifications/000-shared-constitution.txt", "10_specs/platform_support/000-shared-constitution.txt", true),
        ("specifications/001-shared-how-to-read-these-specs.txt", "10_specs/platform_support/001-shared-how-to-read-these-specs.txt", true),
        ("specifications/002-arc-room-administrator-ai-and-producer.txt", "10_specs/platform_support/002-arc-room-administrator-ai-and-producer.txt", true),
        ("specifications/003-arc-durable-state-and-integrity.txt", "10_specs/platform_support/003-arc-durable-state-and-integrity.txt", true),
        ("specifications/004-arc-messaging-and-work-protocol.txt", "10_specs/platform_support/004-arc-messaging-and-work-protocol.txt", true),
        ("specifications/005-arc-ai-instructions-qualification-duty-and-polling.txt", "10_specs/platform_support/005-arc-ai-instructions-qualification-duty-and-polling.txt", true),
        ("specifications/006-arc-macos-application-contract.txt", "10_specs/platform_support/006-arc-macos-application-contract.txt", true),
        ("specifications/007-arc-cli-machine-interface.txt", "10_specs/platform_support/007-arc-cli-machine-interface.txt", true),
        ("specifications/008-arc-security-and-privacy.txt", "10_specs/platform_support/008-arc-security-and-privacy.txt", true),
        ("specifications/009-arc-installation-distribution-and-release.txt", "10_specs/platform_support/009-arc-installation-distribution-and-release.txt", true),
        ("specifications/010-arc-specification-traceability-and-dvt-readiness.txt", "10_specs/platform_support/010-arc-specification-traceability-and-dvt-readiness.txt", true),
        ("specifications/011-arc-durable-record-contract.txt", "10_specs/platform_support/011-arc-durable-record-contract.txt", true),
        ("specifications/012-arc-ai-knowledge-container.txt", "10_specs/platform_support/012-arc-ai-knowledge-container.txt", true),
    ]
    static let optionalRelease = (
        logical: "release/release-notes.txt",
        source: "CHANGELOG.md",
        required: false
    )

    static var requiredNames: Set<String> {
        Set(canonicalSources.map(\.logical))
    }

    static var profileNames: Set<String> {
        requiredNames.union([optionalRelease.logical])
    }

    static func sha256(_ data: Data) -> Data {
        Data(SHA256.hash(data: data))
    }

    static func hex(_ data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    static func canonicalText(_ raw: Data) throws -> Data {
        guard var text = String(data: raw, encoding: .utf8) else {
            throw DevToolError.message("text is not valid UTF-8")
        }
        text = text.replacingOccurrences(of: "\r\n", with: "\n")
        text = text.replacingOccurrences(of: "\r", with: "\n")
        let data = Data(text.utf8)
        try validateText(data)
        return data
    }

    static func validateText(_ data: Data) throws {
        guard (1...maxMemberBytes).contains(data.count) else {
            throw DevToolError.message("member length is outside the v1 bound")
        }
        guard !data.starts(with: [0xef, 0xbb, 0xbf]) else {
            throw DevToolError.message("member has a UTF-8 byte-order mark")
        }
        guard data.last == 0x0a else {
            throw DevToolError.message("member does not end with LF")
        }
        guard String(data: data, encoding: .utf8) != nil else {
            throw DevToolError.message("member is not valid UTF-8")
        }
        for byte in data {
            if byte == 0 || byte == 0x0d || (byte < 0x20 && byte != 0x09 && byte != 0x0a) {
                throw DevToolError.message("member contains a forbidden control byte")
            }
        }
    }

    static func validateName(_ name: String) throws -> Data {
        guard let encoded = name.data(using: .ascii),
              (1...maxNameBytes).contains(encoded.count) else {
            throw DevToolError.message("logical name is not bounded ASCII")
        }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789-_./")
        guard name.hasSuffix(".txt"),
              !name.hasPrefix("/"),
              !name.hasSuffix("/"),
              !name.contains("//"),
              name.unicodeScalars.allSatisfy(allowed.contains) else {
            throw DevToolError.message("logical name is not canonical and relative: \(name)")
        }
        for segment in name.split(separator: "/", omittingEmptySubsequences: false) {
            if segment.isEmpty || segment == "." || segment == ".." || segment.hasPrefix(".") {
                throw DevToolError.message("logical name has a forbidden segment: \(name)")
            }
        }
        return encoded
    }

    static func sourceMembers(root: URL, includeReleaseNotes: Bool) throws -> [KnowledgeMember] {
        try requireRealDirectory(root)
        var mapping = canonicalSources
        if includeReleaseNotes { mapping.append(optionalRelease) }
        return try mapping.map { item in
            let source = root.appending(path: item.source)
            try requireRegularFile(source, below: root, maximum: maxMemberBytes * 2)
            let raw = try Data(contentsOf: source, options: [.mappedIfSafe])
            let payload = try canonicalText(raw)
            return KnowledgeMember(
                name: item.logical,
                required: item.required,
                payload: payload,
                digest: sha256(payload)
            )
        }
    }

    static func build(_ supplied: [KnowledgeMember]) throws -> Data {
        let names = Set(supplied.map(\.name))
        guard requiredNames.isSubset(of: names), names.isSubset(of: profileNames),
              supplied.count == names.count, supplied.count == 18 || supplied.count == 19,
              supplied.count <= maxMembers else {
            throw DevToolError.message("Profile 1 requires its exact 18 or 19 unique members")
        }
        for member in supplied {
            _ = try validateName(member.name)
            try validateText(member.payload)
            guard member.required == requiredNames.contains(member.name),
                  member.digest == sha256(member.payload) else {
                throw DevToolError.message("member flags or digest differ: \(member.name)")
            }
        }
        let members = try supplied.sorted {
            let left = try validateName($0.name)
            let right = try validateName($1.name)
            return left.lexicographicallyPrecedes(right)
        }
        let directoryLength = members.count * entryBytes
        let payloadOffset = headerBytes + directoryLength
        let fileLength = payloadOffset + members.reduce(0) { $0 + $1.payload.count }
        guard fileLength <= maxContainerBytes else {
            throw DevToolError.message("container length is outside the v1 bound")
        }

        var result = Data()
        result.append(magic)
        result.appendBigEndian(formatVersion)
        result.appendBigEndian(profile)
        result.appendBigEndian(UInt32(members.count))
        result.appendBigEndian(UInt32(entryBytes))
        result.appendBigEndian(UInt64(headerBytes))
        result.appendBigEndian(UInt64(directoryLength))
        result.appendBigEndian(UInt64(payloadOffset))
        result.appendBigEndian(UInt64(fileLength))
        result.appendBigEndian(UInt64(0))
        guard result.count == headerBytes else {
            throw DevToolError.message("internal knowledge header length error")
        }

        var nextOffset = payloadOffset
        for member in members {
            let name = try validateName(member.name)
            result.appendBigEndian(UInt16(name.count))
            result.append(member.required ? 1 : 0)
            result.append(1)
            result.appendBigEndian(UInt32(0))
            result.appendBigEndian(UInt64(nextOffset))
            result.appendBigEndian(UInt64(member.payload.count))
            result.append(member.digest)
            result.append(name)
            result.append(Data(repeating: 0, count: maxNameBytes - name.count))
            result.appendBigEndian(UInt64(0))
            nextOffset += member.payload.count
        }
        for member in members { result.append(member.payload) }
        guard result.count == fileLength else {
            throw DevToolError.message("internal knowledge container length error")
        }
        return result
    }

    static func parse(_ data: Data, expectedDigest: Data? = nil) throws -> ParsedKnowledge {
        guard (1...maxContainerBytes).contains(data.count) else {
            throw DevToolError.message("container length is outside the v1 bound")
        }
        let actualDigest = sha256(data)
        if let expectedDigest, expectedDigest != actualDigest {
            throw DevToolError.message("container SHA-256 does not match")
        }
        var cursor = DataCursor(data)
        guard try cursor.read(8) == magic,
              try cursor.u32() == formatVersion,
              try cursor.u32() == profile else {
            throw DevToolError.message("invalid v1 magic or profile")
        }
        let memberCount = Int(try cursor.u32())
        let entrySize = Int(try cursor.u32())
        let directoryOffset = Int(try cursor.u64())
        let directoryLength = Int(try cursor.u64())
        let payloadOffset = Int(try cursor.u64())
        let fileLength = Int(try cursor.u64())
        let reserved = try cursor.u64()
        guard memberCount == 18 || memberCount == 19,
              memberCount <= maxMembers,
              entrySize == entryBytes,
              directoryOffset == headerBytes,
              directoryLength == memberCount * entryBytes,
              payloadOffset == headerBytes + directoryLength,
              fileLength == data.count,
              reserved == 0 else {
            throw DevToolError.message("invalid v1 header geometry")
        }

        struct Entry {
            let name: String
            let required: Bool
            let offset: Int
            let length: Int
            let digest: Data
        }
        var entries: [Entry] = []
        var priorName: Data?
        var expectedOffset = payloadOffset
        for _ in 0..<memberCount {
            let nameLength = Int(try cursor.u16())
            let required = try cursor.u8()
            let type = try cursor.u8()
            let entryReserved = try cursor.u32()
            let offset = Int(try cursor.u64())
            let length = Int(try cursor.u64())
            let digest = try cursor.read(32)
            let nameField = try cursor.read(maxNameBytes)
            let tail = try cursor.u64()
            guard (1...maxNameBytes).contains(nameLength), required <= 1, type == 1,
                  entryReserved == 0, tail == 0,
                  nameField.dropFirst(nameLength).allSatisfy({ $0 == 0 }),
                  let name = String(data: nameField.prefix(nameLength), encoding: .ascii) else {
                throw DevToolError.message("invalid knowledge directory entry")
            }
            let encoded = try validateName(name)
            if let priorName, !priorName.lexicographicallyPrecedes(encoded) {
                throw DevToolError.message("knowledge names are not strictly sorted")
            }
            guard (1...maxMemberBytes).contains(length), offset == expectedOffset,
                  offset <= data.count, length <= data.count - offset else {
                throw DevToolError.message("invalid knowledge payload partition")
            }
            priorName = encoded
            expectedOffset = offset + length
            entries.append(Entry(
                name: name,
                required: required == 1,
                offset: offset,
                length: length,
                digest: digest
            ))
        }
        guard expectedOffset == data.count,
              Set(entries.map(\.name)).count == entries.count,
              requiredNames.isSubset(of: Set(entries.map(\.name))),
              Set(entries.map(\.name)).isSubset(of: profileNames) else {
            throw DevToolError.message("knowledge profile or payload tail is invalid")
        }

        var admitted: [KnowledgeMember] = []
        var omitted: [String] = []
        for entry in entries {
            let payload = data.subdata(in: entry.offset..<(entry.offset + entry.length))
            let valid: Bool
            do {
                try validateText(payload)
                valid = sha256(payload) == entry.digest
            } catch {
                valid = false
            }
            if !valid {
                if entry.required {
                    throw DevToolError.message("invalid essential payload: \(entry.name)")
                }
                omitted.append(entry.name)
                continue
            }
            guard entry.required == requiredNames.contains(entry.name) else {
                throw DevToolError.message("wrong required flag: \(entry.name)")
            }
            admitted.append(KnowledgeMember(
                name: entry.name,
                required: entry.required,
                payload: payload,
                digest: entry.digest
            ))
        }
        return ParsedKnowledge(digest: actualDigest, members: admitted, omitted: omitted)
    }

    static func validateWithC(_ data: Data, digest: Data) throws {
        guard digest.count == 32 else {
            throw DevToolError.message("knowledge digest length is invalid")
        }
        var storage = ArcKnowledgeStorage()
        var knowledge: OpaquePointer?
        let status = data.withUnsafeBytes { source in
            digest.withUnsafeBytes { expected in
                arc_knowledge_open(
                    source.bindMemory(to: UInt8.self).baseAddress,
                    data.count,
                    expected.bindMemory(to: UInt8.self).baseAddress,
                    &storage,
                    &knowledge
                )
            }
        }
        guard status == ARC_KNOWLEDGE_OK, knowledge != nil else {
            arc_knowledge_close(&storage)
            throw DevToolError.message("the ARC-owned C reader rejected the knowledge container")
        }
        arc_knowledge_close(&storage)
    }

    static func manifest(_ parsed: ParsedKnowledge) -> Data {
        var lines = [
            "ARC knowledge text tree/1",
            "container_sha256: \(hex(parsed.digest))",
            "profile: 1",
            "member_count: \(parsed.members.count)",
        ]
        for member in parsed.members {
            lines.append(
                "member: \(member.name)\t\(member.required ? "required" : "optional")\t" +
                "\(member.payload.count)\t\(hex(member.digest))"
            )
        }
        for name in parsed.omitted.sorted() {
            lines.append("omitted: \(name)\tinvalid optional text")
        }
        return Data((lines.joined(separator: "\n") + "\n").utf8)
    }

    static func readTextTree(_ source: URL) throws -> ParsedKnowledge {
        try requireRealDirectory(source)
        let manifestURL = source.appending(path: manifestName)
        let manifestData = try readBounded(manifestURL, maximum: 65_536)
        try validateText(manifestData)
        guard let text = String(data: manifestData, encoding: .utf8) else {
            throw DevToolError.message("knowledge text-tree manifest is not UTF-8")
        }
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.count >= 5, lines.last == "",
              lines[0] == "ARC knowledge text tree/1",
              lines[1].hasPrefix("container_sha256: "),
              lines[2] == "profile: 1",
              lines[3].hasPrefix("member_count: ") else {
            throw DevToolError.message("knowledge text-tree manifest header is invalid")
        }
        let digestText = String(lines[1].dropFirst("container_sha256: ".count))
        guard let digest = decodeHex(digestText), digest.count == 32,
              let statedCount = Int(lines[3].dropFirst("member_count: ".count)),
              statedCount == lines.count - 5,
              statedCount == 18 || statedCount == 19 else {
            throw DevToolError.message("knowledge text-tree identity is invalid")
        }

        var members: [KnowledgeMember] = []
        var priorName: Data?
        for lineValue in lines[4..<(lines.count - 1)] {
            let fields = lineValue.split(separator: "\t", omittingEmptySubsequences: false)
            guard fields.count == 4, fields[0].hasPrefix("member: ") else {
                throw DevToolError.message("knowledge text-tree member row is invalid")
            }
            let name = String(fields[0].dropFirst("member: ".count))
            let encoded = try validateName(name)
            if let priorName, !priorName.lexicographicallyPrecedes(encoded) {
                throw DevToolError.message("knowledge text-tree names are not strictly sorted")
            }
            priorName = encoded
            let required: Bool
            switch fields[1] {
            case "required": required = true
            case "optional": required = false
            default: throw DevToolError.message("knowledge text-tree member flag is invalid")
            }
            guard required == requiredNames.contains(name),
                  profileNames.contains(name),
                  let length = Int(fields[2]),
                  (1...maxMemberBytes).contains(length),
                  let memberDigest = decodeHex(String(fields[3])),
                  memberDigest.count == 32 else {
                throw DevToolError.message("knowledge text-tree member identity is invalid")
            }
            let memberURL = name.split(separator: "/").reduce(source) {
                $0.appending(path: String($1))
            }
            let payload = try readBounded(memberURL, maximum: maxMemberBytes)
            try validateText(payload)
            guard payload.count == length, sha256(payload) == memberDigest else {
                throw DevToolError.message("knowledge text-tree member differs: \(name)")
            }
            members.append(KnowledgeMember(
                name: name,
                required: required,
                payload: payload,
                digest: memberDigest
            ))
        }
        guard Set(members.map(\.name)) == (statedCount == 19 ? profileNames : requiredNames) else {
            throw DevToolError.message("knowledge text-tree profile is incomplete")
        }
        try validateTextTreeShape(source, members: members)
        return ParsedKnowledge(digest: digest, members: members, omitted: [])
    }

    private static func decodeHex(_ text: String) -> Data? {
        guard text.utf8.count == 64, text.utf8.allSatisfy({
            (48...57).contains($0) || (97...102).contains($0)
        }) else {
            return nil
        }
        var result = Data()
        result.reserveCapacity(32)
        var index = text.startIndex
        for _ in 0..<32 {
            let next = text.index(index, offsetBy: 2)
            guard let byte = UInt8(text[index..<next], radix: 16) else { return nil }
            result.append(byte)
            index = next
        }
        return result
    }

    private static func validateTextTreeShape(
        _ source: URL,
        members: [KnowledgeMember]
    ) throws {
        func physicalTempAlias(_ path: String) -> String {
            path == "/tmp" || path.hasPrefix("/tmp/") ? "/private" + path : path
        }
        let sourcePath = physicalTempAlias(source.path)
        let expectedFiles = Set(members.map(\.name)).union([manifestName])
        let expectedDirectories = Set(expectedFiles.flatMap { name -> [String] in
            let components = name.split(separator: "/")
            guard components.count > 1 else { return [] }
            return (1..<components.count).map {
                components.prefix($0).joined(separator: "/")
            }
        })
        guard let enumerator = FileManager.default.enumerator(
            at: source,
            includingPropertiesForKeys: nil,
            options: [],
            errorHandler: { _, _ in false }
        ) else {
            throw DevToolError.message("cannot enumerate knowledge text tree")
        }
        var files = Set<String>()
        var directories = Set<String>()
        while let item = enumerator.nextObject() as? URL {
            let itemPath = physicalTempAlias(item.path)
            guard itemPath.hasPrefix(sourcePath + "/") else {
                throw DevToolError.message("knowledge text tree entry escapes its root")
            }
            let relative = String(itemPath.dropFirst(sourcePath.count + 1))
            var info = stat()
            guard !relative.isEmpty, lstat(item.path, &info) == 0 else {
                throw DevToolError.message("knowledge text tree changed while reading")
            }
            switch info.st_mode & S_IFMT {
            case S_IFREG: files.insert(relative)
            case S_IFDIR: directories.insert(relative)
            default: throw DevToolError.message("knowledge text tree contains a link or special file")
            }
        }
        guard files == expectedFiles, directories == expectedDirectories else {
            throw DevToolError.message("knowledge text tree has missing or unexpected members")
        }
    }

    static func deconstruct(_ parsed: ParsedKnowledge, destination: URL) throws {
        let parent = destination.deletingLastPathComponent()
        try requireRealDirectory(parent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw DevToolError.message("destination already exists: \(destination.path)")
        }
        let stage = parent.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: stage) }
        for member in parsed.members {
            let file = member.name.split(separator: "/").reduce(stage) { $0.appending(path: String($1)) }
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
            try writeNew(member.payload, to: file, mode: 0o600)
        }
        try writeNew(manifest(parsed), to: stage.appending(path: manifestName), mode: 0o600)
        guard rename(stage.path, destination.path) == 0 else {
            throw DevToolError.message("cannot publish text tree: \(String(cString: strerror(errno)))")
        }
    }

    static func writeNew(_ data: Data, to destination: URL, mode: mode_t = 0o600) throws {
        let parent = destination.deletingLastPathComponent()
        try requireRealDirectory(parent)
        guard !FileManager.default.fileExists(atPath: destination.path) else {
            throw DevToolError.message("output already exists: \(destination.path)")
        }
        let stage = parent.appending(path: ".\(destination.lastPathComponent).\(UUID().uuidString).stage")
        guard FileManager.default.createFile(atPath: stage.path, contents: nil, attributes: [.posixPermissions: Int(mode)]) else {
            throw DevToolError.message("cannot create output stage")
        }
        defer { try? FileManager.default.removeItem(at: stage) }
        let handle = try FileHandle(forWritingTo: stage)
        do {
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
        } catch {
            try? handle.close()
            throw error
        }
        guard link(stage.path, destination.path) == 0 else {
            throw DevToolError.message("cannot publish output: \(String(cString: strerror(errno)))")
        }
        guard chmod(destination.path, mode) == 0 else {
            try? FileManager.default.removeItem(at: destination)
            throw DevToolError.message("cannot set output mode")
        }
    }

    static func readBounded(_ url: URL, maximum: Int) throws -> Data {
        try requireRegularFile(url, maximum: maximum)
        let data = try Data(contentsOf: url, options: [.mappedIfSafe])
        guard !data.isEmpty, data.count <= maximum else {
            throw DevToolError.message("file length is outside its bound: \(url.path)")
        }
        return data
    }

    static func requireRealDirectory(_ url: URL) throws {
        // Foundation may present macOS's system `/private/tmp` directory as
        // its stable `/tmp` alias. Validate the real system target; no other
        // symbolic parent receives this exception.
        let presented = url.standardizedFileURL.path
        let checked = presented == "/tmp" || presented.hasPrefix("/tmp/")
            ? "/private" + presented
            : presented
        var current = URL(fileURLWithPath: "/", isDirectory: true)
        for component in URL(fileURLWithPath: checked).pathComponents.dropFirst() {
            current.append(path: component, directoryHint: .isDirectory)
            var info = stat()
            guard lstat(current.path, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFDIR else {
                throw DevToolError.message("path is not a real directory: \(current.path)")
            }
        }
    }

    static func requireRegularFile(_ url: URL, below root: URL? = nil, maximum: Int) throws {
        if let root {
            try requireRealDirectory(root)
            let standardizedRoot = root.standardizedFileURL.path
            let standardizedFile = url.standardizedFileURL.path
            guard standardizedFile.hasPrefix(standardizedRoot + "/") else {
                throw DevToolError.message("file escapes the selected root")
            }
            var current = root
            let suffix = standardizedFile.dropFirst(standardizedRoot.count + 1)
            for component in suffix.split(separator: "/").dropLast() {
                current.append(path: String(component), directoryHint: .isDirectory)
                var info = stat()
                guard lstat(current.path, &info) == 0,
                      (info.st_mode & S_IFMT) == S_IFDIR else {
                    throw DevToolError.message("source parent is not a real directory: \(current.path)")
                }
            }
        }
        var info = stat()
        guard lstat(url.path, &info) == 0,
              (info.st_mode & S_IFMT) == S_IFREG,
              info.st_size > 0,
              info.st_size <= maximum else {
            throw DevToolError.message("path is not a bounded regular file: \(url.path)")
        }
    }
}

private struct DataCursor {
    let data: Data
    var offset = 0

    init(_ data: Data) { self.data = data }

    mutating func read(_ count: Int) throws -> Data {
        guard count >= 0, offset <= data.count, count <= data.count - offset else {
            throw DevToolError.message("container ended unexpectedly")
        }
        defer { offset += count }
        return data.subdata(in: offset..<(offset + count))
    }

    mutating func u8() throws -> UInt8 { try read(1)[0] }
    mutating func u16() throws -> UInt16 { try readInteger(UInt16.self) }
    mutating func u32() throws -> UInt32 { try readInteger(UInt32.self) }
    mutating func u64() throws -> UInt64 { try readInteger(UInt64.self) }

    mutating func readInteger<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
        let bytes = try read(MemoryLayout<T>.size)
        return bytes.reduce(0) { ($0 << 8) | T($1) }
    }
}

private extension Data {
    mutating func appendBigEndian<T: FixedWidthInteger>(_ value: T) {
        var big = value.bigEndian
        Swift.withUnsafeBytes(of: &big) { append(contentsOf: $0) }
    }
}
