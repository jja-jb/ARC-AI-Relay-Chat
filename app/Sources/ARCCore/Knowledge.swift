import ARCKnowledge
import Foundation

#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

public final class ARCKnowledgeFile: @unchecked Sendable {
    public enum Member: Sendable {
        case specification(Int)
        case aiGuide
        case help
        case manPage
        case license
        case notice
        case releaseNotes
    }

    public let sha256: String
    public let containerURL: URL

    private let bytes: UnsafeMutablePointer<UInt8>
    private let byteCount: Int
    private let storage: UnsafeMutablePointer<ArcKnowledgeStorage>
    private let knowledge: OpaquePointer

    public static func openDefault(rootURL: URL) throws -> ARCKnowledgeFile {
        let current = rootURL.appendingPathComponent("current", isDirectory: true)
        var candidates = [current]
        if let resources = Bundle.main.resourceURL {
            candidates.append(resources)
        }
        if let executable = Bundle.main.executableURL {
            candidates.append(
                executable.deletingLastPathComponent().deletingLastPathComponent()
                    .appendingPathComponent("share/arc", isDirectory: true)
            )
        }
        for directory in candidates {
            let container = directory.appendingPathComponent("ARC_AI.arc-kb")
            let digest = directory.appendingPathComponent("ARC_AI.sha256")
            if regularPathExists(container.path) {
                return try ARCKnowledgeFile(containerURL: container, digestURL: digest)
            }
        }
        throw ARCError(
            .knowledgeUnavailable,
            "ARC's verified AI instructions are missing. Reinstall ARC."
        )
    }

    public init(containerURL: URL, digestURL: URL) throws {
        let digestData: Data
        let containerData: Data
        digestData = try readBoundedRegularFile(digestURL, maximumBytes: 256)
        containerData = try readBoundedRegularFile(
            containerURL, maximumBytes: ARCConstants.maximumRoomBytes
        )
        guard digestData.count <= 256,
              containerData.count > 0,
              containerData.count <= ARCConstants.maximumRoomBytes,
              let digestText = String(data: digestData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              ARCText.isSHA256(digestText) else {
            throw ARCError(.knowledgeUnavailable, "ARC's AI instruction digest is invalid.")
        }
        let actual = arcSHA256Hex(containerData)
        guard actual == digestText else {
            throw ARCError(.knowledgeUnavailable, "ARC's AI instructions failed verification.")
        }

        let byteBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: containerData.count)
        containerData.copyBytes(to: byteBuffer, count: containerData.count)
        let storageBuffer = UnsafeMutablePointer<ArcKnowledgeStorage>.allocate(capacity: 1)
        storageBuffer.initialize(to: ArcKnowledgeStorage())

        var digestBytes = [UInt8]()
        digestBytes.reserveCapacity(32)
        var cursor = digestText.startIndex
        for _ in 0..<32 {
            let next = digestText.index(cursor, offsetBy: 2)
            digestBytes.append(UInt8(digestText[cursor..<next], radix: 16)!)
            cursor = next
        }
        var opened: OpaquePointer?
        let status = digestBytes.withUnsafeBytes { digestRaw in
            arc_knowledge_open(
                byteBuffer,
                containerData.count,
                digestRaw.bindMemory(to: UInt8.self).baseAddress,
                storageBuffer,
                &opened
            )
        }
        guard status == ARC_KNOWLEDGE_OK, let opened else {
            storageBuffer.deinitialize(count: 1)
            storageBuffer.deallocate()
            byteBuffer.deallocate()
            throw ARCError(.knowledgeUnavailable, "ARC's AI instruction container is invalid.")
        }

        self.sha256 = digestText
        self.containerURL = containerURL
        self.bytes = byteBuffer
        self.byteCount = containerData.count
        self.storage = storageBuffer
        self.knowledge = opened
    }

    deinit {
        arc_knowledge_close(storage)
        storage.deinitialize(count: 1)
        storage.deallocate()
        bytes.deallocate()
    }

    public func text(_ member: Member) throws -> String? {
        let native = try nativeMember(member)
        var length = 0
        var memberDigest = [UInt8](repeating: 0, count: 32)
        let info = memberDigest.withUnsafeMutableBytes { digest in
            arc_knowledge_info(
                knowledge,
                native,
                &length,
                digest.bindMemory(to: UInt8.self).baseAddress
            )
        }
        if info == ARC_KNOWLEDGE_OMITTED { return nil }
        guard info == ARC_KNOWLEDGE_OK, length <= 524_288 else {
            throw ARCError(.knowledgeUnavailable, "ARC could not open that instruction member.")
        }

        var result = Data()
        result.reserveCapacity(length)
        var offset = 0
        var buffer = [UInt8](repeating: 0, count: 16_384)
        while offset < length {
            var written = 0
            var done: Int32 = 0
            let status = buffer.withUnsafeMutableBytes { destination in
                arc_knowledge_read_text(
                    knowledge,
                    native,
                    offset,
                    destination.bindMemory(to: UInt8.self).baseAddress,
                    destination.count,
                    &written,
                    &done
                )
            }
            guard status == ARC_KNOWLEDGE_OK, written > 0 || done != 0 else {
                throw ARCError(.knowledgeUnavailable, "ARC could not read that instruction member.")
            }
            result.append(buffer, count: written)
            offset += written
            if done != 0 { break }
        }
        guard result.count == length, let value = String(data: result, encoding: .utf8) else {
            throw ARCError(.knowledgeUnavailable, "An ARC instruction member is not valid text.")
        }
        return value
    }

    private func nativeMember(_ member: Member) throws -> ArcKnowledgeMember {
        switch member {
        case .specification(let id):
            let values: [ArcKnowledgeMember] = [
                ARC_KNOWLEDGE_SPEC_000, ARC_KNOWLEDGE_SPEC_001,
                ARC_KNOWLEDGE_SPEC_002, ARC_KNOWLEDGE_SPEC_003,
                ARC_KNOWLEDGE_SPEC_004, ARC_KNOWLEDGE_SPEC_005,
                ARC_KNOWLEDGE_SPEC_006, ARC_KNOWLEDGE_SPEC_007,
                ARC_KNOWLEDGE_SPEC_008, ARC_KNOWLEDGE_SPEC_009,
                ARC_KNOWLEDGE_SPEC_010, ARC_KNOWLEDGE_SPEC_011,
                ARC_KNOWLEDGE_SPEC_012,
            ]
            guard values.indices.contains(id) else {
                throw ARCError(.notFound, "ARC has no specification with that ID.")
            }
            return values[id]
        case .aiGuide: return ARC_KNOWLEDGE_AI_GUIDE
        case .help: return ARC_KNOWLEDGE_HELP
        case .manPage: return ARC_KNOWLEDGE_MAN_PAGE
        case .license: return ARC_KNOWLEDGE_LICENSE
        case .notice: return ARC_KNOWLEDGE_NOTICE
        case .releaseNotes: return ARC_KNOWLEDGE_RELEASE_NOTES
        }
    }
}

private func regularPathExists(_ path: String) -> Bool {
    var value = stat()
    return lstat(path, &value) == 0
}

private func readBoundedRegularFile(_ url: URL, maximumBytes: Int) throws -> Data {
    try rejectSymlinkComponents(url)
    let descriptor = open(url.path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW)
    guard descriptor >= 0 else {
        throw ARCError(.knowledgeUnavailable, "ARC could not read its AI instructions.")
    }
    defer { close(descriptor) }
    var before = stat()
    guard fstat(descriptor, &before) == 0,
          (before.st_mode & S_IFMT) == S_IFREG,
          before.st_nlink == 1,
          before.st_size > 0,
          before.st_size <= maximumBytes else {
        throw ARCError(
            .knowledgeUnavailable,
            "ARC refused an unsafe or oversized AI instruction file."
        )
    }
    var result = Data()
    result.reserveCapacity(Int(before.st_size))
    var buffer = [UInt8](repeating: 0, count: 65_536)
    while true {
        let count = buffer.withUnsafeMutableBytes {
            arcRead(descriptor, $0.baseAddress, $0.count)
        }
        if count == 0 { break }
        if count < 0 {
            if errno == EINTR { continue }
            throw ARCError(.knowledgeUnavailable, "ARC could not read its AI instructions.")
        }
        result.append(buffer, count: count)
        guard result.count <= maximumBytes else {
            throw ARCError(.knowledgeUnavailable, "ARC's AI instructions are too large.")
        }
    }
    var after = stat()
    var pathState = stat()
    guard fstat(descriptor, &after) == 0,
          lstat(url.path, &pathState) == 0,
          before.st_dev == after.st_dev,
          before.st_ino == after.st_ino,
          before.st_size == after.st_size,
          arcSameFileTimes(before, after),
          after.st_dev == pathState.st_dev,
          after.st_ino == pathState.st_ino,
          result.count == Int(after.st_size) else {
        throw ARCError(.knowledgeUnavailable, "ARC's AI instructions changed while opening.")
    }
    return result
}

private func rejectSymlinkComponents(_ url: URL) throws {
    guard url.isFileURL, url.path.hasPrefix("/") else {
        throw ARCError(.knowledgeUnavailable, "ARC's AI instruction path is invalid.")
    }
    let components = (url.path as NSString).pathComponents
    var path = "/"
    for component in components.dropFirst() {
        path = (path as NSString).appendingPathComponent(component)
        var value = stat()
        guard lstat(path, &value) == 0, (value.st_mode & S_IFMT) != S_IFLNK else {
            throw ARCError(
                .knowledgeUnavailable,
                "ARC refused a linked AI instruction path."
            )
        }
    }
}
