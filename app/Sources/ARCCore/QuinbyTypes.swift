import Foundation

public struct QuinbySummary: Codable, Sendable, Equatable {
    public var incarnation: String
    public var revision: Int64
    public var throughSequence: Int64
    public var text: String
}

/// Per-AI consumption counters. Polls, waits, reads and acts are counted;
/// bytes are the encoded result bytes ARC handed to that AI. The counters
/// describe what ARC served, not what a host spent on its own model.
public struct QuinbyUsage: Codable, Sendable, Equatable {
    public var pollsLastHour: Int
    public var waitsLastHour: Int
    public var readsLastHour: Int
    public var actsLastHour: Int
    public var bytesServedLastHour: Int64
    public var pollsTotal: Int64
    public var bytesServedTotal: Int64
    /// Logical time of the lane's last poll or wait, and of its last accepted act.
    public var lastPollLogicalUs: Int64?
    public var lastActLogicalUs: Int64?
    /// Polls and waits since the last accepted act. A lane that only checks in
    /// may be a poller running without its AI.
    public var pollsSinceLastAct: Int64

    /// The headless-lane signal: the lane has checked in at least ten times
    /// since it last acted, and its last act (or first check-in) is over an
    /// hour old. A fact about the record, not proof that the AI is gone.
    public func headless(now: Int64) -> Bool {
        guard pollsSinceLastAct >= 10, let last = lastPollLogicalUs else { return false }
        let since = lastActLogicalUs ?? firstPollLogicalUs ?? last
        return now - since >= 3_600_000_000
    }
    public var firstPollLogicalUs: Int64?
}

public struct QuinbyParticipant: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var name: String
    public var phase: ARCParticipantPhase
    public var duty: ARCDuty
    public var workingUntil: Int64?
    public var dutyUntil: Int64?
    public var recoveryAttempts: Int
    public var usage: QuinbyUsage
}

public struct QuinbyAssignment: Codable, Sendable, Identifiable, Equatable {
    public var id: String
    public var kind: String
    public var prompt: String
    public var selectedAI: String?
    public var generation: Int64
    public var eligible: [String]
}

public struct QuinbyObservation: Codable, Sendable, Equatable {
    public var room: String
    public var roomName: String
    public var sequence: Int64
    public var at: String
    public var kind: String
    public var actor: String
    public var actorName: String
    public var recipient: String?
    public var subject: String?
    public var payload: ARCJSONValue
}

public struct QuinbyEntry: Codable, Sendable, Identifiable, Equatable {
    public var sequence: Int64
    public var at: String
    public var kind: String
    public var author: String
    public var text: String
    public var observations: [QuinbyObservation]
    public var id: Int64 { sequence }
}

/// A bounded slice of the record. Backward pages (`read --before`) fill
/// `next_before`; forward deltas (`poll --after`) fill `next_after` and `more`.
public struct QuinbyPage: Codable, Sendable, Equatable {
    public var entries: [QuinbyEntry]
    public var nextBefore: Int64?
    public var nextAfter: Int64?
    public var more: Bool?
    /// A bounded delta could not reach the requested sequence. Keep the old
    /// nextAfter until backward paging has covered it; then resume at this
    /// frozen sequence. nextBefore starts that recovery at the frozen end.
    public var catchUpThrough: Int64? = nil
}

public struct QuinbySnapshot: Codable, Sendable, Equatable {
    public var incarnation: String
    public var enabled: Bool
    public var listening: Bool
    public var status: String
    public var sequence: Int64
    public var participants: [QuinbyParticipant]
    public var assignments: [QuinbyAssignment]
    public var summaryRevision: Int64
    public var summaryThroughSequence: Int64
    public var summarySequence: Int64
    /// Omitted from a delta poll whose cursor already covers the current summary.
    public var summary: QuinbySummary?
    public var page: QuinbyPage
}

public struct QuinbyInvitation: Codable, Sendable {
    public var incarnation: String
    public var participant: String
    public var binding: String
    public var arguments: [String]
    public var instructions: String
}

/// Compact communication status for polls. The full notice text is part of
/// the guide; a poll only needs the digest that decides whether to reread.
public struct QuinbyCommunicationStatus: Codable, Sendable, Equatable {
    public var status: String
    public var specificationSha256: String?
    public var operatorLanguage: ARCOperatorLanguage
}

public struct QuinbyPoll: Codable, Sendable {
    public var corner: QuinbySnapshot
    public var participant: String
    public var operation: String
    /// True when the cursor missed something worth the host's attention: a
    /// new entry, an assignment for this AI, a challenge, or the Corner off.
    public var changed: Bool
    public var nextAfter: Int64
    public var nextPollAfterSeconds: Int
    public var dutyUntilLogicalUs: Int64?
    public var waitedSeconds: Int?
    public var challenge: String?
    public var earliestCompletion: Int64?
    public var qualificationDeadline: Int64?
    public var communication: QuinbyCommunicationStatus
}

public struct QuinbyActionResult: Codable, Sendable {
    public var sequence: Int64
    public var nextOperation: String
}

/// Durable reference to the record frame that holds the current summary
/// text. The text itself is stored once, in that frame; checkpoints carry
/// only this reference so routine frames stay small.
struct QuinbySummaryRef: Codable, Sendable, Equatable {
    var revision: Int64
    var throughSequence: Int64
    var sequence: Int64
    var frameStart: Int64
    var at: Int64
}

struct QuinbyMember: Codable, Sendable {
    var id: String
    var name: String
    var binding: String
    var phase: ARCParticipantPhase = .invited
    var firstPoll: Int64?
    var answered = false
    var challenge: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
    var lastPoll: Int64?
    var dutyUntil: Int64?
    var workingUntil: Int64?
    var recoveryAttempts = 0
    var operation: String = UUID().uuidString.lowercased()
    var previousOperation: String?
    var previousDigest: String?
    var previousSequence: Int64?
    var contributionTimes: [Int64] = []
    var thoughtTimes: [Int64] = []

    func available(_ now: Int64) -> Bool {
        guard phase == .qualified, let lastPoll, now >= lastPoll else { return false }
        if let workingUntil { return now < workingUntil }
        return now < (dutyUntil ?? lastPoll + QuinbyLimits.minimumDutyUs)
    }
}

enum QuinbyLimits {
    static let minimumDutyUs: Int64 = 180_000_000
    static let maximumSummaryBytes = 16_384
    static let contributionsPerHour = 10
    static let thoughtsPerHour = 4
    static let summaryIntervalUs: Int64 = 900_000_000
    static let summaryMinimumNewEntries: Int64 = 10
    static let workingRedeclareWindowUs: Int64 = 300_000_000
    static let hourUs: Int64 = 3_600_000_000
    static let forwardScanFrames = 512
    static let forwardScanBytes: Int64 = 16 * 1_024 * 1_024
    static let deltaPageBytes = 65_536
}

struct QuinbyState: Codable, Sendable {
    var incarnation: String
    var enabled = false
    var logical: Int64
    var participants: [QuinbyMember] = []
    var assignments: [QuinbyAssignment] = []
    var summary: QuinbySummaryRef
    var lastActivity: Int64 = 0
    /// The last recorded answer to "is any Corner AI available?", so that
    /// only transitions are journaled. Presence itself is not in frames.
    var available = false
    var lastAdminOperation: String?
    var lastAdminDigest: String?
    var lastAdminParticipant: String?
    var resetting = false
}

struct QuinbyCapture: Codable, Sendable {
    var room: String
    var expectedSHA256: String
    var previousSHA256: String? = nil
    var observations: [QuinbyObservation]
}

struct QuinbyFrame: Codable, Sendable {
    var sequence: Int64
    var at: String
    var kind: String
    var author: String
    var text: String
    var state: QuinbyState
    var observations: [QuinbyObservation] = []
    var pending: QuinbyCapture?

    var entry: QuinbyEntry {
        QuinbyEntry(sequence: sequence, at: at, kind: kind, author: author,
                    text: text, observations: observations)
    }

    /// Operational frames are checkpoints, never conversation.
    static let operationalKinds: Set<String> = ["availability", "qualification", "capture.intent", "capture.cancel", "poll"]
    var isEntry: Bool { !Self.operationalKinds.contains(kind) }
}

/// Volatile presence and consumption counters kept beside the record in
/// `presence.json`. Losing the file only makes AIs appear Off Duty until they
/// poll again; it holds no conversation and is not a second content store.
struct QuinbyPresence: Codable, Sendable {
    struct Member: Codable, Sendable {
        var lastPoll: Int64?
        var dutyUntil: Int64?
        var buckets: [QuinbyUsageBucket] = []
        var pollsTotal: Int64 = 0
        var bytesServedTotal: Int64 = 0
        var firstCheckIn: Int64?
        var lastCheckIn: Int64?
        var lastAct: Int64?
        var pollsSinceLastAct: Int64 = 0
    }
    var incarnation: String
    /// Logical high-water mark of presence writes, so a clock rollback after
    /// a routine poll or read cannot move time backwards.
    var logical: Int64 = 0
    var members: [String: Member] = [:]
}

struct QuinbyUsageBucket: Codable, Sendable {
    var hour: Int64
    var polls = 0
    var waits = 0
    var reads = 0
    var acts = 0
    var bytes: Int64 = 0
}
