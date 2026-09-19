import CryptoKit
import Darwin
import Foundation

/// An indexed append log. Each frame has lengths at both ends, so reads can
/// walk in either direction without a separate index or loading all history.
/// A frame's state is a bounded checkpoint, never a copy of the whole history.
/// Routine polls are not frames: presence lives in `presence.json` beside it.
final class QuinbyJournal {
    static let maximumFrame = 16 * 1_024 * 1_024
    static let recordHeader = Data("ARCQREC2\n".utf8)
    static let recordFooter = Data("ARCQEND2\n".utf8)
    static let legacyHeader = Data("ARCQREC1\n".utf8)
    let directory: URL
    private(set) var descriptor: Int32
    private let lock: Int32
    var end: Int64 = 0
    var latest: QuinbyFrame?
    var presence: QuinbyPresence?
    private(set) var unreadableForReset = false
    private var summaryCache: (start: Int64, text: String)?

    init(root: URL, allowUnreadableForReset: Bool = false) throws {
        try rejectLinkedPath(root, allowMissingTail: true)
        try ensureDirectory(root)
        directory = root.appendingPathComponent("quinby", isDirectory: true)
        try ensureDirectory(directory)
        try rejectLinkedPath(directory, allowMissingTail: false)
        lock = Darwin.open(directory.appendingPathComponent("record.lock").path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard lock >= 0 else { throw Self.failure() }
        var info = stat()
        guard fstat(lock, &info) == 0, info.st_nlink == 1,
              (info.st_mode & S_IFMT) == S_IFREG else {
            Darwin.close(lock); throw Self.failure()
        }
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        while flock(lock, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN,
                  ProcessInfo.processInfo.systemUptime < deadline else {
                Darwin.close(lock)
                throw ARCError(.busy, "Quinby's record is busy. Try again.")
            }
            usleep(20_000)
        }
        descriptor = Darwin.open(directory.appendingPathComponent("records.arcquinby").path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard descriptor >= 0 else {
            flock(lock, LOCK_UN); Darwin.close(lock); throw Self.failure()
        }
        do {
            guard fstat(descriptor, &info) == 0, info.st_nlink == 1,
                  (info.st_mode & S_IFMT) == S_IFREG else { throw Self.failure() }
            do {
                end = info.st_size
                if end >= 9, try read(0, count: 9) == Self.legacyHeader {
                    throw ARCError(.roomIncompatible, "Quinby's record was written by ARC 3.1 or earlier. Use Kill and Reincarnate to start this version's Corner.")
                }
                try recoverTail()
                if end > 0 { latest = try frameEnding(at: end).frame }
                presence = try loadPresence()
            } catch let error as ARCError where allowUnreadableForReset
                && (error.code == .roomCorrupt || error.code == .roomIncompatible) {
                // Only the explicitly confirmed reset path may use this handle.
                // Keep the same validated lock held through erasure. I/O failures,
                // links and unsafe paths are never converted into reset permission.
                unreadableForReset = true
            }
        } catch {
            Darwin.close(descriptor); flock(lock, LOCK_UN); Darwin.close(lock)
            throw error
        }
    }

    deinit { Darwin.close(descriptor); flock(lock, LOCK_UN); Darwin.close(lock) }

    static func encoder() -> JSONEncoder {
        let value = JSONEncoder()
        value.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return value
    }

    /// Byte offset the next appended frame will start at.
    var nextFrameStart: Int64 { end }

    func append(_ frame: QuinbyFrame) throws {
        let payload = try Self.encoder().encode(frame)
        guard payload.count <= Self.maximumFrame else {
            throw ARCError(.limitExceeded, "This individual Quinby entry is too large.")
        }
        let length = String(format: "%016llx", payload.count)
        let digest = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        var bytes = Self.recordHeader
        bytes.append(Data(length.utf8))
        bytes.append(payload)
        bytes.append(Data((length + digest).utf8))
        bytes.append(Self.recordFooter)
        guard end <= Int64.max - Int64(bytes.count) else { throw Self.failure() }
        try bytes.withUnsafeBytes { raw in
            var done = 0
            while done < raw.count {
                let n = pwrite(descriptor, raw.baseAddress!.advanced(by: done), raw.count - done, end + Int64(done))
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Self.failure() }
                done += n
            }
        }
        guard fsync(descriptor) == 0 else { throw Self.failure() }
        end += Int64(bytes.count)
        latest = frame
    }

    /// Backward page: up to `limit` conversation entries ending before `before`.
    /// Operational checkpoints are skipped without counting against the limit.
    func page(before: Int64?, limit: Int = 50) throws -> QuinbyPage {
        let stop = before ?? end
        guard stop >= 0, stop <= end else {
            throw ARCError(.invalidArgument, "The Quinby history position is invalid.")
        }
        var cursor = stop
        var entries: [QuinbyEntry] = []
        var scanned = 0
        while cursor > 0 && entries.count < limit && scanned < 4 * limit && stop - cursor < 4 * 1_024 * 1_024 {
            let item = try frameEnding(at: cursor)
            cursor = item.start
            scanned += 1
            if item.frame.isEntry { entries.append(item.frame.entry) }
        }
        return QuinbyPage(entries: entries.reversed(), nextBefore: cursor > 0 ? cursor : nil, nextAfter: nil, more: nil)
    }

    /// Forward delta: the oldest `limit` conversation entries with a sequence
    /// greater than `after`. The backward scan that finds them is bounded; a
    /// cursor beyond that bound receives an explicit backward catch-up window,
    /// never a cursor that silently skips unread entries.
    func entries(after: Int64, limit: Int = 50) throws -> QuinbyPage {
        var cursor = end
        var found: [(frame: QuinbyFrame, start: Int64)] = []
        var scanned = 0
        var reached = false
        while cursor > 0 && scanned < QuinbyLimits.forwardScanFrames && end - cursor < QuinbyLimits.forwardScanBytes {
            let item = try frameEnding(at: cursor)
            if item.frame.sequence <= after { reached = true; break }
            cursor = item.start
            scanned += 1
            if item.frame.isEntry { found.append(item) }
        }
        if cursor == 0 { reached = true }
        if !reached {
            return QuinbyPage(entries: [], nextBefore: end, nextAfter: after,
                             more: true, catchUpThrough: latest?.sequence)
        }
        let ordered = Array(found.reversed())
        // A delta is bounded by count and by bytes: a page never carries more
        // than about 64 KiB of entry text, so one delta never becomes a dump.
        var slice: [(frame: QuinbyFrame, start: Int64)] = []
        var bytes = 0
        for item in ordered.prefix(limit) {
            let size = item.frame.text.utf8.count + item.frame.observations.reduce(0) { $0 + $1.payload.displayText.utf8.count }
            if !slice.isEmpty && bytes + size > QuinbyLimits.deltaPageBytes { break }
            slice.append(item); bytes += size
        }
        let more = ordered.count > slice.count || !reached
        return QuinbyPage(entries: slice.map(\.frame.entry),
            nextBefore: slice.first.map(\.start),
            nextAfter: slice.last?.frame.sequence ?? (latest?.sequence ?? after),
            more: more)
    }

    func frameStarting(at start: Int64) throws -> QuinbyFrame {
        guard start >= 0, end >= 25, start <= end - 25 else { throw Self.corrupt() }
        let prefix = try read(start, count: 25)
        guard prefix.prefix(9) == Self.recordHeader,
              let length = Int(String(decoding: prefix.suffix(16), as: UTF8.self), radix: 16),
              length > 0, length <= Self.maximumFrame, start + Int64(length + 114) <= end else { throw Self.corrupt() }
        return try frameEnding(at: start + Int64(length + 114)).frame
    }

    /// The current summary text, read from the frame that recorded it.
    func summaryText(_ ref: QuinbySummaryRef) throws -> String {
        if let summaryCache, summaryCache.start == ref.frameStart { return summaryCache.text }
        let frame = try frameStarting(at: ref.frameStart)
        guard frame.sequence == ref.sequence else { throw Self.corrupt() }
        summaryCache = (ref.frameStart, frame.text)
        return frame.text
    }

    func summary(_ state: QuinbyState) throws -> QuinbySummary {
        QuinbySummary(incarnation: state.incarnation, revision: state.summary.revision,
            throughSequence: state.summary.throughSequence, text: try summaryText(state.summary))
    }

    func frameEnding(at position: Int64) throws -> (frame: QuinbyFrame, start: Int64) {
        guard position >= 114 else { throw Self.corrupt() }
        let footer = try read(position - 89, count: 89)
        guard footer.suffix(9) == Self.recordFooter,
              let length = Int(String(decoding: footer.prefix(16), as: UTF8.self), radix: 16),
              length > 0, length <= Self.maximumFrame,
              position >= Int64(length + 114) else { throw Self.corrupt() }
        let start = position - Int64(length + 114)
        let prefix = try read(start, count: 25)
        guard prefix.prefix(9) == Self.recordHeader, prefix.suffix(16) == footer.prefix(16) else {
            throw Self.corrupt()
        }
        let payload = try read(start + 25, count: length)
        let hash = SHA256.hash(data: payload).map { String(format: "%02x", $0) }.joined()
        guard Data(hash.utf8) == footer.dropFirst(16).prefix(64) else { throw Self.corrupt() }
        do {
            let frame = try JSONDecoder().decode(QuinbyFrame.self, from: payload)
            guard try Self.encoder().encode(frame) == payload,
                  frame.sequence > 0, frame.sequence < Int64.max,
                  ARCText.isLowerUUID(frame.state.incarnation),
                  frame.state.logical >= 0, frame.state.logical <= 253_402_300_799_999_999,
                  frame.state.participants.count <= 64, frame.state.assignments.count <= 50,
                  Set(frame.state.participants.map(\.id)).count == frame.state.participants.count,
                  Set(frame.state.assignments.map(\.id)).count == frame.state.assignments.count,
                  frame.state.summary.revision > 0, frame.state.summary.revision < Int64.max,
                  frame.state.summary.throughSequence <= frame.sequence,
                  frame.state.summary.sequence <= frame.sequence,
                  frame.state.summary.frameStart >= 0, frame.state.summary.frameStart <= start,
                  frame.text.utf8.count <= 65_536,
                  frame.state.assignments.allSatisfy({ $0.generation >= 0 && $0.generation < Int64.max
                      && $0.eligible.count <= 64 && $0.prompt.utf8.count <= 16_384 }),
                  frame.state.participants.allSatisfy({ ARCText.isSafeID($0.id, prefix: "ai-")
                      && ARCText.isLowerUUID($0.binding) && (0...2).contains($0.recoveryAttempts)
                      && ($0.firstPoll ?? 0) >= 0 && ($0.lastPoll ?? 0) >= 0
                      && $0.contributionTimes.count <= QuinbyLimits.contributionsPerHour
                      && $0.thoughtTimes.count <= QuinbyLimits.thoughtsPerHour }) else { throw Self.corrupt() }
            return (frame, start)
        } catch { throw Self.corrupt() }
    }

    private func recoverTail() throws {
        guard end > 0 else { return }
        if end >= 9, try read(end - 9, count: 9) == Self.recordFooter { return }
        let count = Int(min(end, Int64(Self.maximumFrame + 228)))
        let start = end - Int64(count)
        let tail = try read(start, count: count)
        let marker = Self.recordFooter
        var range = tail.startIndex..<tail.endIndex
        var committed: Int64 = 0
        while let found = tail.range(of: marker, options: .backwards, in: range) {
            let candidate = start + Int64(found.upperBound)
            if (try? frameEnding(at: candidate)) != nil { committed = candidate; break }
            range = tail.startIndex..<found.lowerBound
        }
        guard committed > 0 || start == 0 else { throw Self.corrupt() }
        let suffix = try read(committed, count: Int(end - committed))
        let header = Self.recordHeader
        guard suffix.prefix(min(9, suffix.count)) == header.prefix(min(9, suffix.count)) else { throw Self.corrupt() }
        // Only an incomplete, never-committed final append may be removed.
        // Complete frame checksum failures are errors, not grounds to truncate.
        if suffix.count >= 25 {
            guard let length = Int(String(decoding: suffix.dropFirst(9).prefix(16), as: UTF8.self), radix: 16),
                  length > 0, length <= Self.maximumFrame, suffix.count < length + 114 else { throw Self.corrupt() }
        }
        guard ftruncate(descriptor, committed) == 0, fsync(descriptor) == 0 else { throw Self.failure() }
        end = committed
    }

    private func read(_ offset: Int64, count: Int) throws -> Data {
        guard offset >= 0, count >= 0, count <= Self.maximumFrame + 228 else { throw Self.corrupt() }
        var data = Data(count: count)
        try data.withUnsafeMutableBytes { raw in
            var done = 0
            while done < count {
                let n = pread(descriptor, raw.baseAddress!.advanced(by: done), count - done, offset + Int64(done))
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Self.corrupt() }
                done += n
            }
        }
        return data
    }

    func publishSummary(_ summary: QuinbySummary) throws {
        try publish(try Self.encoder().encode(summary), name: "summary.json")
    }

    // MARK: Presence

    private func loadPresence() throws -> QuinbyPresence? {
        let target = directory.appendingPathComponent("presence.json")
        guard FileManager.default.fileExists(atPath: target.path) else { return nil }
        guard let data = try? readBoundedRegularFile(target, maximumBytes: 1_048_576),
              let value = try? JSONDecoder().decode(QuinbyPresence.self, from: data) else { return nil }
        return value
    }

    func savePresence(_ value: QuinbyPresence) throws {
        presence = value
        try publish(try Self.encoder().encode(value), name: "presence.json")
    }

    private func publish(_ bytes: Data, name: String) throws {
        let target = directory.appendingPathComponent(name)
        try rejectLinkedPath(target, allowMissingTail: true)
        var info = stat()
        if lstat(target.path, &info) == 0 {
            guard info.st_nlink == 1, (info.st_mode & S_IFMT) == S_IFREG else { throw Self.failure() }
        }
        let temp = directory.appendingPathComponent(".summary-\(UUID().uuidString).tmp")
        defer { try? FileManager.default.removeItem(at: temp) }
        let fd = Darwin.open(temp.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw Self.failure() }
        defer { Darwin.close(fd) }
        try bytes.withUnsafeBytes { raw in
            var done = 0
            while done < raw.count {
                let n = Darwin.write(fd, raw.baseAddress!.advanced(by: done), raw.count - done)
                if n < 0 && errno == EINTR { continue }
                guard n > 0 else { throw Self.failure() }
                done += n
            }
        }
        guard fsync(fd) == 0, rename(temp.path, target.path) == 0 else { throw Self.failure() }
        try syncDirectory()
    }

    func erase() throws {
        // The lock inode survives reset; old callers cannot acquire a different lock.
        guard ftruncate(descriptor, 0) == 0, fsync(descriptor) == 0 else { throw Self.failure() }
        end = 0; latest = nil; presence = nil; summaryCache = nil
        let record = directory.appendingPathComponent("records.arcquinby")
        guard unlink(record.path) == 0 else { throw Self.failure() }
        Darwin.close(descriptor)
        descriptor = Darwin.open(record.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { throw Self.failure() }
        for name in ["summary.json", "presence.json"] {
            let path = directory.appendingPathComponent(name).path
            if unlink(path) != 0 && errno != ENOENT { throw Self.failure() }
        }
        for name in try FileManager.default.contentsOfDirectory(atPath: directory.path)
        where name.hasPrefix(".summary-") && name.hasSuffix(".tmp") {
            let identifier = String(name.dropFirst(9).dropLast(4))
            guard UUID(uuidString: identifier) != nil else { continue }
            guard unlink(directory.appendingPathComponent(name).path) == 0 else { throw Self.failure() }
        }
        try syncDirectory()
    }

    func syncDirectory() throws {
        let fd = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard fd >= 0 else { throw Self.failure() }
        defer { Darwin.close(fd) }
        guard fsync(fd) == 0 else { throw Self.failure() }
    }

    static func failure() -> ARCError { ARCError(.ioFailure, "Quinby cannot record. Check the Mac's available storage and ARC's data folder.") }
    static func corrupt() -> ARCError { ARCError(.roomCorrupt, "Quinby's record failed its integrity check. Earlier history has not been erased.") }
}

/// Blocks until a file changes or a timeout passes, without holding any ARC
/// lock. Used by `wait` commands so an AI host needs no scheduled loop.
enum ARCFileWatch {
    /// Returns true when the file changed before `seconds` elapsed.
    static func waitForChange(at path: String, seconds: Double) -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        let fd = Darwin.open(path, O_EVTONLY | O_CLOEXEC)
        guard fd >= 0 else {
            usleep(UInt32(max(0, min(seconds, 2)) * 1_000_000))
            return false
        }
        defer { Darwin.close(fd) }
        let queue = kqueue()
        guard queue >= 0 else { usleep(UInt32(max(0, min(seconds, 2)) * 1_000_000)); return false }
        defer { Darwin.close(queue) }
        var change = kevent(ident: UInt(fd), filter: Int16(EVFILT_VNODE),
            flags: UInt16(EV_ADD | EV_ENABLE | EV_CLEAR),
            fflags: UInt32(NOTE_WRITE | NOTE_EXTEND | NOTE_DELETE | NOTE_RENAME | NOTE_ATTRIB), data: 0, udata: nil)
        var out = kevent()
        while true {
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard remaining > 0 else { return false }
            var spec = timespec(tv_sec: Int(remaining), tv_nsec: Int((remaining - Double(Int(remaining))) * 1_000_000_000))
            let n = kevent(queue, &change, 1, &out, 1, &spec)
            if n < 0 { if errno == EINTR { continue }; return false }
            if n == 0 { return false }
            return true
        }
    }
}
