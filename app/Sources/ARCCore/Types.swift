import Foundation

public enum ARCConstants {
    public static let version = "2.3.0"
    public static let roomFormat = "arc.room/1"
    public static let roomProtocol = "arc.protocol/1"
    public static let maximumRoomBytes = 8 * 1_024 * 1_024
    public static let maximumParticipants = 64
    public static let maximumWorkItems = 256
    public static let maximumCurrentWorkItems = 50
    public static let maximumRecentCompletedWork = 16
    // A room keeps its complete Activity for its lifetime. The byte bound is
    // the single storage bound; Activity is never silently discarded.
    public static let maximumJSONStructuralItems = maximumRoomBytes
    public static let eventPageSize = 50
}

public enum ARCErrorCode: String, Codable, Sendable {
    case invalidArgument = "INVALID_ARGUMENT"
    case notFound = "NOT_FOUND"
    case roomIncompatible = "ROOM_INCOMPATIBLE"
    case roomCorrupt = "ROOM_CORRUPT"
    case knowledgeUnavailable = "KNOWLEDGE_UNAVAILABLE"
    case bindingInvalid = "BINDING_INVALID"
    case retired = "RETIRED"
    case operationStale = "OPERATION_STALE"
    case operationConflict = "OPERATION_CONFLICT"
    case wrongState = "WRONG_STATE"
    case notProducer = "NOT_PRODUCER"
    case clockUnavailable = "CLOCK_UNAVAILABLE"
    case limitExceeded = "LIMIT_EXCEEDED"
    case busy = "BUSY"
    case ioFailure = "IO_FAILURE"
}

public struct ARCError: Error, LocalizedError, Equatable, Sendable {
    public let code: ARCErrorCode
    public let message: String
    public let retryable: Bool

    public init(_ code: ARCErrorCode, _ message: String) {
        self.code = code
        self.message = message
        self.retryable = [.clockUnavailable, .busy, .ioFailure].contains(code)
    }

    public var errorDescription: String? { message }

    public var exitStatus: Int32 {
        switch code {
        case .roomIncompatible, .roomCorrupt, .knowledgeUnavailable: 3
        case .busy, .ioFailure: 4
        default: 2
        }
    }
}

public enum ARCRoomStatus: String, Codable, CaseIterable, Sendable {
    case timeUnavailable = "TIME_UNAVAILABLE"
    case needsTwoAIs = "NEEDS_TWO_AIS"
    case needsOneAI = "NEEDS_ONE_AI"
    case needsProducer = "NEEDS_PRODUCER"
    case active = "ACTIVE"

    public var plainText: String {
        switch self {
        case .timeUnavailable: "ARC cannot check time."
        case .needsTwoAIs: "Needs two available AIs."
        case .needsOneAI: "Needs one more available AI."
        case .needsProducer: "Choose a Producer."
        case .active: "Active."
        }
    }
}

public enum ARCParticipantPhase: String, Codable, CaseIterable, Sendable {
    case invited = "INVITED"
    case waitingForProducer = "WAITING_FOR_PRODUCER"
    case qualifying = "QUALIFYING"
    case qualified = "QUALIFIED"
    case failed = "FAILED"
    case retired = "RETIRED"
}

public enum ARCDuty: String, Codable, Sendable {
    case on = "ON"
    case working = "WORKING"
    case off = "OFF"
    case notApplicable = "NOT_APPLICABLE"
}

public enum ARCWorkState: String, Codable, Sendable {
    case open = "OPEN"
    case active = "ACTIVE"
    case blocked = "BLOCKED"
    case complete = "COMPLETE"
}

public enum ARCEvidenceMode: String, Codable, Sendable {
    case text = "TEXT"
    case visual = "VISUAL"
}

public enum ARCScheduleKind: String, Codable, Sendable {
    case qualification = "QUALIFICATION"
    case duty = "DUTY"
    case working = "WORKING"
    case none = "NONE"
}

public enum ARCScheduleStatus: String, Codable, Sendable {
    case unavailable = "UNAVAILABLE"
    case waiting = "WAITING"
    case ok = "OK"
    case request1 = "REQUEST_1"
    case request2 = "REQUEST_2"
    case request3 = "REQUEST_3"
    case expired = "EXPIRED"
    case none = "NONE"
}

public enum ARCJSONValue: Codable, Hashable, Sendable {
    case object([String: ARCJSONValue])
    case array([ARCJSONValue])
    case string(String)
    case integer(Int64)
    case boolean(Bool)
    case null

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([ARCJSONValue].self) { self = .array(value) }
        else if let value = try? container.decode([String: ARCJSONValue].self) {
            self = .object(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "ARC JSON contains an unsupported value."
            )
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }

    public var objectValue: [String: ARCJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    public var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    public var integerValue: Int64? {
        guard case .integer(let value) = self else { return nil }
        return value
    }

    public var boolValue: Bool? {
        guard case .boolean(let value) = self else { return nil }
        return value
    }

    public var displayText: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return (try? encoder.encode(self)).map { String(decoding: $0, as: UTF8.self) }
            ?? "Unavailable"
    }
}

public struct ARCRoomView: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let status: ARCRoomStatus
    public let revision: Int64
    public let `protocol`: String
    public let knowledgeSha256: String
    public let logicalUs: Int64

    public init(
        id: String, name: String, status: ARCRoomStatus, revision: Int64,
        protocol: String, knowledgeSha256: String, logicalUs: Int64
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.revision = revision
        self.protocol = `protocol`
        self.knowledgeSha256 = knowledgeSha256
        self.logicalUs = logicalUs
    }
}

public struct ARCProducerView: Codable, Hashable, Sendable {
    public let id: String?
    public let name: String?
    public let generation: Int64
    public let live: Bool

    public init(id: String?, name: String?, generation: Int64, live: Bool) {
        self.id = id
        self.name = name
        self.generation = generation
        self.live = live
    }

    enum CodingKeys: String, CodingKey { case id, name, generation, live }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(generation, forKey: .generation)
        try container.encode(live, forKey: .live)
    }
}

public struct ARCScheduleView: Codable, Hashable, Sendable {
    public let kind: ARCScheduleKind
    public let status: ARCScheduleStatus
    public let nextRequestLogicalUs: Int64?
    public let deadlineLogicalUs: Int64?

    public init(
        kind: ARCScheduleKind, status: ARCScheduleStatus,
        nextRequestLogicalUs: Int64?, deadlineLogicalUs: Int64?
    ) {
        self.kind = kind
        self.status = status
        self.nextRequestLogicalUs = nextRequestLogicalUs
        self.deadlineLogicalUs = deadlineLogicalUs
    }

    enum CodingKeys: String, CodingKey {
        case kind, status, nextRequestLogicalUs, deadlineLogicalUs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(kind, forKey: .kind)
        try container.encode(status, forKey: .status)
        try container.encode(nextRequestLogicalUs, forKey: .nextRequestLogicalUs)
        try container.encode(deadlineLogicalUs, forKey: .deadlineLogicalUs)
    }
}

public struct ARCInstructions: Hashable, Sendable {
    public let bindingGeneration: Int64
    public let bindingReference: String

    public init(bindingGeneration: Int64, bindingReference: String) {
        self.bindingGeneration = bindingGeneration
        self.bindingReference = bindingReference
    }
}

public struct ARCParticipantView: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let phase: ARCParticipantPhase
    public let duty: ARCDuty
    public let isProducer: Bool
    public let binding: String?
    public let bindingGeneration: Int64
    public let schedule: ARCScheduleView
    public let lastCheckIn: String?
    public let automaticRecoveryAttempts: Int

    public init(
        id: String, name: String, phase: ARCParticipantPhase, duty: ARCDuty,
        isProducer: Bool, binding: String?, bindingGeneration: Int64,
        schedule: ARCScheduleView, lastCheckIn: String?, automaticRecoveryAttempts: Int = 0
    ) {
        self.id = id
        self.name = name
        self.phase = phase
        self.duty = duty
        self.isProducer = isProducer
        self.binding = binding
        self.bindingGeneration = bindingGeneration
        self.schedule = schedule
        self.lastCheckIn = lastCheckIn
        self.automaticRecoveryAttempts = automaticRecoveryAttempts
    }

    enum CodingKeys: String, CodingKey {
        case id, name, phase, duty, isProducer, bindingGeneration
        case schedule, lastCheckIn, automaticRecoveryAttempts
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        phase = try container.decode(ARCParticipantPhase.self, forKey: .phase)
        duty = try container.decode(ARCDuty.self, forKey: .duty)
        isProducer = try container.decode(Bool.self, forKey: .isProducer)
        binding = nil
        bindingGeneration = try container.decode(Int64.self, forKey: .bindingGeneration)
        schedule = try container.decode(ARCScheduleView.self, forKey: .schedule)
        lastCheckIn = try container.decode(String?.self, forKey: .lastCheckIn)
        automaticRecoveryAttempts = try container.decodeIfPresent(Int.self, forKey: .automaticRecoveryAttempts) ?? 0
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(phase, forKey: .phase)
        try container.encode(duty, forKey: .duty)
        try container.encode(isProducer, forKey: .isProducer)
        // A binding is an Administrator-only capability. Machine views never
        // serialize it, even when the in-process Mac view carries one.
        try container.encode(bindingGeneration, forKey: .bindingGeneration)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(lastCheckIn, forKey: .lastCheckIn)
        try container.encode(automaticRecoveryAttempts, forKey: .automaticRecoveryAttempts)
    }

    public func plainState(roomStatus: ARCRoomStatus) -> String {
        if roomStatus == .timeUnavailable, phase == .qualified {
            return "Waiting for ARC's time check"
        }
        switch phase {
        case .invited: return "Waiting to connect"
        case .waitingForProducer: return "Waiting for the Producer"
        case .qualifying: return "Checking ARC access"
        case .failed: return automaticRecoveryAttempts < 2 ? "Waiting to reconnect" : "Connection needs your help"
        case .retired: return "Retired"
        case .qualified: return duty == .working ? "Working" : duty == .on ? "On Duty" : "Off Duty"
        }
    }

    public var isAvailable: Bool {
        phase == .qualified && (duty == .on || duty == .working)
    }
}

/// The current candidate's private, actionable qualification state. ARC returns
/// it only to that candidate's poll; it is deliberately not a roster field.
public struct ARCQualificationView: Codable, Hashable, Sendable {
    public let challenge: String
    public let earliestCompletionLogicalUs: Int64?
    public let deadlineLogicalUs: Int64?

    public init(
        challenge: String, earliestCompletionLogicalUs: Int64?,
        deadlineLogicalUs: Int64?
    ) {
        self.challenge = challenge
        self.earliestCompletionLogicalUs = earliestCompletionLogicalUs
        self.deadlineLogicalUs = deadlineLogicalUs
    }

    enum CodingKeys: String, CodingKey {
        case challenge, earliestCompletionLogicalUs, deadlineLogicalUs
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(challenge, forKey: .challenge)
        try container.encode(
            earliestCompletionLogicalUs, forKey: .earliestCompletionLogicalUs
        )
        try container.encode(deadlineLogicalUs, forKey: .deadlineLogicalUs)
    }
}

public struct ARCWorkView: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let owner: String
    public let state: ARCWorkState
    public let scope: String
    public let evidenceMode: ARCEvidenceMode
    public let evidence: ARCJSONValue
    public let assigningProducerGeneration: Int64
    public let revision: Int64
    public let createdAt: String
    public let updatedAt: String

    public init(
        id: String, owner: String, state: ARCWorkState, scope: String,
        evidenceMode: ARCEvidenceMode, evidence: ARCJSONValue,
        assigningProducerGeneration: Int64, revision: Int64,
        createdAt: String, updatedAt: String
    ) {
        self.id = id
        self.owner = owner
        self.state = state
        self.scope = scope
        self.evidenceMode = evidenceMode
        self.evidence = evidence
        self.assigningProducerGeneration = assigningProducerGeneration
        self.revision = revision
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct ARCEventView: Codable, Hashable, Identifiable, Sendable {
    public var id: Int64 { sequence }
    public let sequence: Int64
    public let at: String
    public let logicalUs: Int64
    public let kind: String
    public let actor: String
    public let recipient: String?
    public let subject: String?
    public let payload: ARCJSONValue
    public let operationId: String
    public let knowledgeSha256: String

    public init(
        sequence: Int64, at: String, logicalUs: Int64, kind: String,
        actor: String, recipient: String?, subject: String?,
        payload: ARCJSONValue, operationId: String,
        knowledgeSha256: String
    ) {
        self.sequence = sequence
        self.at = at
        self.logicalUs = logicalUs
        self.kind = kind
        self.actor = actor
        self.recipient = recipient
        self.subject = subject
        self.payload = payload
        self.operationId = operationId
        self.knowledgeSha256 = knowledgeSha256
    }

    enum CodingKeys: String, CodingKey {
        case sequence, at, logicalUs, kind, actor, recipient, subject, payload
        case operationId, knowledgeSha256
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(sequence, forKey: .sequence)
        try container.encode(at, forKey: .at)
        try container.encode(logicalUs, forKey: .logicalUs)
        try container.encode(kind, forKey: .kind)
        try container.encode(actor, forKey: .actor)
        try container.encode(recipient, forKey: .recipient)
        try container.encode(subject, forKey: .subject)
        try container.encode(payload, forKey: .payload)
        try container.encode(operationId, forKey: .operationId)
        try container.encode(knowledgeSha256, forKey: .knowledgeSha256)
    }

    public var timeIsVerified: Bool {
        payload.objectValue?["time_verified"]?.boolValue != false
    }
}

public enum ARCRoomHealth: String, Codable, Sendable {
    case current = "CURRENT"
    case busy = "BUSY"
    case recovery = "RECOVERY"
}

public struct ARCRoomListItem: Codable, Hashable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let health: ARCRoomHealth
    public let failure: String?

    public init(id: String, name: String, health: ARCRoomHealth, failure: String?) {
        self.id = id
        self.name = name
        self.health = health
        self.failure = failure
    }
}

public struct ARCRoomListPage: Codable, Sendable {
    public let rooms: [ARCRoomListItem]
    public let nextSafeId: String?

    public init(rooms: [ARCRoomListItem], nextSafeId: String?) {
        self.rooms = rooms
        self.nextSafeId = nextSafeId
    }
}

public struct ARCRoomOpenResult: Codable, Sendable {
    public let room: ARCRoomView
    public let producer: ARCProducerView
    public let participants: [ARCParticipantView]
    public let work: [ARCWorkView]
    public let canDeleteWithoutRetirement: Bool

    public init(
        room: ARCRoomView, producer: ARCProducerView,
        participants: [ARCParticipantView], work: [ARCWorkView],
        canDeleteWithoutRetirement: Bool = false
    ) {
        self.room = room
        self.producer = producer
        self.participants = participants
        self.work = work
        self.canDeleteWithoutRetirement = canDeleteWithoutRetirement
    }
}

public struct ARCRevisionResult: Codable, Sendable {
    public let roomRevision: Int64
    public init(roomRevision: Int64) { self.roomRevision = roomRevision }
}

public struct ARCRoomTickResult: Codable, Sendable {
    public let room: ARCRoomView
    public let producer: ARCProducerView

    public init(room: ARCRoomView, producer: ARCProducerView) {
        self.room = room
        self.producer = producer
    }
}

public struct ARCActivityPage: Codable, Sendable {
    public let events: [ARCEventView]
    public let nextBefore: Int64?

    public init(events: [ARCEventView], nextBefore: Int64?) {
        self.events = events
        self.nextBefore = nextBefore
    }
}

public struct ARCInstructionResult: Sendable {
    public let participant: ARCParticipantView
    public let instructions: ARCInstructions

    public init(participant: ARCParticipantView, instructions: ARCInstructions) {
        self.participant = participant
        self.instructions = instructions
    }
}

public struct ARCGuideContext: Codable, Sendable {
    public let room: ARCRoomView
    public let participant: ARCParticipantView

    public init(room: ARCRoomView, participant: ARCParticipantView) {
        self.room = room
        self.participant = participant
    }
}

public struct ARCDiagnosticFailure: Codable, Hashable, Sendable {
    public let check: String
    public let message: String
    public let nextAction: String

    public init(check: String, message: String, nextAction: String) {
        self.check = check
        self.message = message
        self.nextAction = nextAction
    }
}

public struct ARCDiagnosticFact: Codable, Hashable, Identifiable, Sendable {
    public var id: String { label }
    public let label: String
    public let value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct ARCDiagnosticResult: Codable, Sendable {
    public let valid: Bool
    public let failure: ARCDiagnosticFailure?
    public let context: [ARCDiagnosticFact]

    public init(
        valid: Bool, failure: ARCDiagnosticFailure?, context: [ARCDiagnosticFact]
    ) {
        self.valid = valid
        self.failure = failure
        self.context = context
    }

    enum CodingKeys: String, CodingKey { case valid, failure, context }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(valid, forKey: .valid)
        try container.encode(failure, forKey: .failure)
        try container.encode(context, forKey: .context)
    }
}

public struct ARCDeleteResult: Codable, Sendable {
    public let deleted: Bool
    public init(deleted: Bool) { self.deleted = deleted }
}

public struct ARCPollResult: Codable, Sendable {
    public let communication: ARCCommunicationNotice
    public let room: ARCRoomView
    public let participant: ARCParticipantView
    public let producer: ARCProducerView
    public let roster: [ARCParticipantView]
    public let schedule: ARCScheduleView
    public let qualification: ARCQualificationView?
    public let events: [ARCEventView]
    public let nextAfter: Int64
    public let more: Bool
    public let work: [ARCWorkView]
    public let operation: String
    public let earlierActivityUnavailable: Bool

    enum CodingKeys: String, CodingKey {
        case room, communication
        case participant = "self"
        case producer, roster, schedule, qualification, events, nextAfter, more, work, operation
        case earlierActivityUnavailable = "earlier_activity_unavailable"
    }

    public init(
        room: ARCRoomView, participant: ARCParticipantView,
        producer: ARCProducerView, roster: [ARCParticipantView],
        schedule: ARCScheduleView, qualification: ARCQualificationView?,
        events: [ARCEventView], nextAfter: Int64, more: Bool,
        work: [ARCWorkView], operation: String, earlierActivityUnavailable: Bool,
        communication: ARCCommunicationNotice
    ) {
        self.room = room
        self.participant = participant
        self.producer = producer
        self.roster = roster
        self.schedule = schedule
        self.qualification = qualification
        self.events = events
        self.nextAfter = nextAfter
        self.more = more
        self.work = work
        self.operation = operation
        self.earlierActivityUnavailable = earlierActivityUnavailable
        self.communication = communication
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(room, forKey: .room)
        try container.encode(communication, forKey: .communication)
        try container.encode(participant, forKey: .participant)
        try container.encode(producer, forKey: .producer)
        try container.encode(roster, forKey: .roster)
        try container.encode(schedule, forKey: .schedule)
        try container.encode(qualification, forKey: .qualification)
        try container.encode(events, forKey: .events)
        try container.encode(nextAfter, forKey: .nextAfter)
        try container.encode(more, forKey: .more)
        try container.encode(work, forKey: .work)
        try container.encode(operation, forKey: .operation)
        try container.encode(earlierActivityUnavailable, forKey: .earlierActivityUnavailable)
    }
}

public struct ARCActResult: Codable, Hashable, Sendable {
    public let eventSequences: [Int64]
    public let roomRevision: Int64
    public let participant: ARCParticipantView?
    public let work: ARCWorkView?
    public let nextOperation: String

    public init(
        eventSequences: [Int64], roomRevision: Int64,
        participant: ARCParticipantView?, work: ARCWorkView?,
        nextOperation: String
    ) {
        self.eventSequences = eventSequences
        self.roomRevision = roomRevision
        self.participant = participant
        self.work = work
        self.nextOperation = nextOperation
    }

    enum CodingKeys: String, CodingKey {
        case eventSequences, roomRevision, participant, work, nextOperation
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventSequences, forKey: .eventSequences)
        try container.encode(roomRevision, forKey: .roomRevision)
        try container.encode(participant, forKey: .participant)
        try container.encode(work, forKey: .work)
        try container.encode(nextOperation, forKey: .nextOperation)
    }
}

public enum ARCActionRequest: Hashable, Sendable {
    case terseSend(to: String, packet: ARCJSONValue)
    case working(untilLogicalUs: Int64)
    case message(to: String, text: String)
    case messageBroadcast(text: String)
    case qualificationStart(participant: String, producerGeneration: Int64)
    case qualificationAnswer(answer: String)
    case workAssign(
        owner: String, scope: String, evidenceMode: ARCEvidenceMode,
        producerGeneration: Int64
    )
    case workUpdate(
        work: String, revision: Int64, state: ARCWorkState, evidence: ARCJSONValue
    )
    case workCorrect(work: String, revision: Int64, reason: String, evidence: ARCJSONValue)
    case workReassign(
        work: String, revision: Int64, owner: String, reason: String,
        producerGeneration: Int64
    )
}

public struct ARCClock: Sendable {
    private let implementation: @Sendable () throws -> Date

    public init(_ implementation: @escaping @Sendable () throws -> Date) {
        self.implementation = implementation
    }

    public func now() throws -> Date { try implementation() }
    public static let system = ARCClock { Date() }
}
