import Darwin
import Foundation

/// Per-AI consumption counters for rooms and the Corner: what ARC served a
/// lane, not what its host spent. The room meter is a volatile sidecar in
/// `meters/<room>.json` under the ARC root; the Corner keeps the same
/// counters in its presence file. Losing a meter loses only counts.
public typealias ARCLaneUsage = QuinbyUsage

struct ARCMeterFile: Codable, Sendable {
    var members: [String: QuinbyPresence.Member] = [:]
}

enum ARCMeter {
    static let bucketUs: Int64 = 600_000_000
    static let retainedBuckets: Int64 = 144

    static func usage(_ member: QuinbyPresence.Member?, now: Int64) -> QuinbyUsage {
        guard let member else {
            return QuinbyUsage(pollsLastHour: 0, waitsLastHour: 0, readsLastHour: 0, actsLastHour: 0,
                bytesServedLastHour: 0, pollsTotal: 0, bytesServedTotal: 0,
                lastPollLogicalUs: nil, lastActLogicalUs: nil, pollsSinceLastAct: 0, firstPollLogicalUs: nil)
        }
        let current = now / bucketUs
        let recent = member.buckets.filter { $0.hour > current - 6 }
        return QuinbyUsage(pollsLastHour: recent.reduce(0) { $0 + $1.polls }, waitsLastHour: recent.reduce(0) { $0 + $1.waits },
            readsLastHour: recent.reduce(0) { $0 + $1.reads }, actsLastHour: recent.reduce(0) { $0 + $1.acts },
            bytesServedLastHour: recent.reduce(0) { $0 + $1.bytes }, pollsTotal: member.pollsTotal, bytesServedTotal: member.bytesServedTotal,
            lastPollLogicalUs: member.lastCheckIn, lastActLogicalUs: member.lastAct,
            pollsSinceLastAct: member.pollsSinceLastAct, firstPollLogicalUs: member.firstCheckIn)
    }

    static func count(_ member: inout QuinbyPresence.Member, now: Int64,
                      polls: Int = 0, waits: Int = 0, reads: Int = 0, acts: Int = 0, bytes: Int64 = 0) {
        if polls > 0 || waits > 0 {
            member.lastCheckIn = now
            if member.firstCheckIn == nil { member.firstCheckIn = now }
            member.pollsSinceLastAct += Int64(polls + waits)
        }
        if acts > 0 { member.lastAct = now; member.pollsSinceLastAct = 0 }
        let current = now / bucketUs
        member.buckets = member.buckets.filter { $0.hour > current - retainedBuckets }
        if member.buckets.last?.hour != current { member.buckets.append(QuinbyUsageBucket(hour: current)) }
        member.buckets[member.buckets.count - 1].polls += polls
        member.buckets[member.buckets.count - 1].waits += waits
        member.buckets[member.buckets.count - 1].reads += reads
        member.buckets[member.buckets.count - 1].acts += acts
        member.buckets[member.buckets.count - 1].bytes += bytes
        member.pollsTotal += Int64(polls)
        member.bytesServedTotal += bytes
    }

    static func servedBytes<T: Encodable>(_ value: T) -> Int64 {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return Int64((try? encoder.encode(value))?.count ?? 0)
    }

    // MARK: Room meters

    private static func url(root: URL, room: String) -> URL {
        root.appendingPathComponent("meters", isDirectory: true).appendingPathComponent("\(room).json")
    }

    static func load(root: URL, room: String) -> ARCMeterFile {
        let target = url(root: root, room: room)
        guard let data = try? readBoundedRegularFile(target, maximumBytes: 4_194_304),
              let value = try? JSONDecoder().decode(ARCMeterFile.self, from: data) else { return ARCMeterFile() }
        return value
    }

    /// Best effort: a meter write never fails a poll.
    static func note(root: URL, room: String, participant: String, now: Int64,
                     polls: Int = 0, waits: Int = 0, acts: Int = 0, bytes: Int64 = 0) {
        withLock(root: root, room: room) {
            var file = load(root: root, room: room)
            var member = file.members[participant] ?? QuinbyPresence.Member()
            count(&member, now: now, polls: polls, waits: waits, acts: acts, bytes: bytes)
            file.members[participant] = member
            let directory = root.appendingPathComponent("meters", isDirectory: true)
            guard let data = try? QuinbyJournal.encoder().encode(file) else { return }
            let temp = directory.appendingPathComponent(".\(room)-\(UUID().uuidString).tmp")
            guard (try? data.write(to: temp, options: .atomic)) != nil else { return }
            if rename(temp.path, url(root: root, room: room).path) != 0 {
                try? FileManager.default.removeItem(at: temp)
            }
        }
    }

    static func usage(root: URL, room: String, now: Int64) -> [String: QuinbyUsage] {
        load(root: root, room: room).members.mapValues { usage($0, now: now) }
    }

    static func remove(root: URL, room: String) {
        withLock(root: root, room: room) {
            try? FileManager.default.removeItem(at: url(root: root, room: room))
        }
    }

    /// Serialize read-modify-write across host processes, not only threads.
    /// Meters remain best effort: unsafe paths or a busy meter never fail a
    /// room action. The lock inode survives removal, avoiding split locks.
    private static func withLock(root: URL, room: String, body: () -> Void) {
        guard ARCText.isSafeID(room, prefix: "room-") else { return }
        let directory = root.appendingPathComponent("meters", isDirectory: true)
        do {
            try rejectLinkedPath(root, allowMissingTail: false)
            try ensureDirectory(directory)
            try rejectLinkedPath(directory, allowMissingTail: false)
        } catch { return }
        let fd = Darwin.open(directory.appendingPathComponent("\(room).lock").path,
            O_RDWR | O_CREAT | O_CLOEXEC | O_NOFOLLOW, 0o600)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, info.st_nlink == 1,
              (info.st_mode & S_IFMT) == S_IFREG else { return }
        let deadline = ProcessInfo.processInfo.systemUptime + 1
        while flock(fd, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN,
                  ProcessInfo.processInfo.systemUptime < deadline else { return }
            usleep(1_000)
        }
        defer { flock(fd, LOCK_UN) }
        body()
    }
}
