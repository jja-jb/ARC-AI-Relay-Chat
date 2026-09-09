import Foundation

public final class ARCStore: @unchecked Sendable {
    public static var defaultRootURL: URL {
        FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0].appendingPathComponent("ARC", isDirectory: true)
    }

    public let rootURL: URL
    private let clock: ARCClock
    private let explicitKnowledgeSHA256: String?
    private let maximumEventBytes: Int
    public init(rootURL: URL = ARCStore.defaultRootURL, clock: ARCClock = .system) {
        self.rootURL = rootURL.standardized
        self.clock = clock
        self.explicitKnowledgeSHA256 = nil
        self.maximumEventBytes = 65_536
    }

    /// An explicit digest is for deterministic tests and ARC-owned tooling.
    public init(rootURL: URL, clock: ARCClock = .system, knowledgeSHA256: String) {
        self.rootURL = rootURL.standardized
        self.clock = clock
        self.explicitKnowledgeSHA256 = knowledgeSHA256
        self.maximumEventBytes = 65_536
    }

    init(
        testRootURL: URL, clock: ARCClock,
        knowledgeSHA256: String, maximumEventBytes: Int
    ) {
        self.rootURL = testRootURL.standardized
        self.clock = clock
        self.explicitKnowledgeSHA256 = knowledgeSHA256
        self.maximumEventBytes = maximumEventBytes
    }

    public func roomFileURL(room: String) throws -> URL {
        try files().roomURL(room)
    }

    public func roomList(afterSafeID: String? = nil) throws -> ARCRoomListPage {
        if let afterSafeID, !ARCText.isSafeID(afterSafeID, prefix: "room-") {
            throw ARCError(.invalidArgument, "The room paging value is invalid.")
        }
        let fileStore = try files()
        let eligible = try fileStore.roomIDs().filter { id in
            afterSafeID.map { id > $0 } ?? true
        }
        let selected = Array(eligible.prefix(51))
        let visible = selected.prefix(50)
        var rooms: [ARCRoomListItem] = []
        rooms.reserveCapacity(visible.count)
        for id in visible {
            do {
                let item = try fileStore.read(id) { document in
                    ARCRoomListItem(
                        id: id, name: document.room.name, health: .current, failure: nil
                    )
                }
                rooms.append(item)
            } catch let error as ARCError {
                if error.code == .busy {
                    rooms.append(ARCRoomListItem(
                        id: id,
                        name: id,
                        health: .busy,
                        failure: "The room is busy. ARC can try again."
                    ))
                    continue
                }
                rooms.append(ARCRoomListItem(
                    id: id,
                    name: id,
                    health: .recovery,
                    failure: error.message
                ))
            }
        }
        return ARCRoomListPage(
            rooms: rooms,
            nextSafeId: selected.count > 50 ? rooms.last?.id : nil
        )
    }

    public func roomOpen(room: String) throws -> ARCRoomOpenResult {
        let digest = try knowledgeSHA256()
        return try files().read(room) { document in
            self.openResult(document, now: self.readTime(document), knowledge: digest)
        }
    }

    public func roomCreate(
        displayName: String, operationID: UUID
    ) throws -> ARCRoomOpenResult {
        let name = try ARCText.require(
            displayName, label: "Room name", maximumBytes: 512,
            maximumCharacters: 80, allowPathSeparator: false
        )
        let knowledge = try knowledgeSHA256()
        let date = try clock.now()
        let logical = try ARCTime.logicalUS(date)
        let timestamp = ARCTime.timestamp(logical)
        let operation = operationID.uuidString.lowercased()

        for attempt in 0..<16 {
            // Stable candidates make a lost creation response safe to retry,
            // without adding another store or an unlocked directory scan.
            let suffix = ARCRoomCodec.digest("room.create\u{0}\(operation)\u{0}\(attempt)").prefix(12)
            let id = "room-\(suffix)"
            var document = ARCRoomDocument(
                format: ARCConstants.roomFormat,
                room: ARCRoomRecord(
                    id: id,
                    name: name,
                    createdAt: timestamp,
                    updatedAt: timestamp,
                    revision: 1,
                    nextSequence: 1,
                    producerId: nil,
                    producerGeneration: 0,
                    producerEverSelected: false,
                    lastClockLogicalUs: logical,
                    lastAdminOperation: ARCAdminOperationRecord(
                        id: operation,
                        requestDigest: ARCRoomCodec.digest("room.create\u{0}\(name)")
                    )
                ),
                participants: [],
                work: [],
                activity: []
            )
            try appendEvent(
                to: &document,
                logical: logical,
                kind: "ROOM_CREATED",
                actor: "administrator",
                payload: .object(["name": .string(name)]),
                operation: operation,
                knowledge: knowledge
            )
            do {
                return try files().create(document) {
                    self.openResult($0, now: logical, knowledge: knowledge)
                }
            } catch is ARCFileCollision {
                let replay: ARCRoomOpenResult? = try files().read(id) { existing in
                    guard let created = existing.activity.first,
                          created.kind == "ROOM_CREATED",
                          created.operationId == operation else { return nil }
                    guard created.payload == .object(["name": .string(name)]) else {
                        throw ARCError(.operationConflict, "That room creation retry changed its request.")
                    }
                    return self.openResult(
                        existing, now: max(logical, existing.room.lastClockLogicalUs),
                        knowledge: knowledge
                    )
                }
                if let replay { return replay }
                continue
            }
        }
        throw ARCError(.ioFailure, "ARC could not choose a unique Room ID.")
    }

    public func roomRename(
        room: String, displayName: String, operationID: UUID
    ) throws -> ARCRevisionResult {
        let name = try ARCText.require(
            displayName, label: "Room name", maximumBytes: 512,
            maximumCharacters: 80, allowPathSeparator: false
        )
        let knowledge = try knowledgeSHA256()
        let operation = operationID.uuidString.lowercased()
        let request = ARCRoomCodec.digest("room.rename\u{0}\(name)")
        return try files().update(room) { document in
            if try self.isAdminReplay(document, operation: operation, request: request) {
                return (ARCRevisionResult(roomRevision: document.room.revision), false)
            }
            if document.room.name == name {
                return (ARCRevisionResult(roomRevision: document.room.revision), false)
            }
            let time = self.administrativeMutationTime(&document)
            let logical = time.logical
            document.room.name = name
            try self.appendEvent(
                to: &document, logical: logical, kind: "ROOM_RENAMED",
                actor: "administrator", payload: .object([
                    "name": .string(name),
                    "time_verified": .boolean(time.verified),
                ]),
                operation: operation, knowledge: knowledge
            )
            self.finishAdminMutation(
                &document, logical: logical, operation: operation, request: request
            )
            return (ARCRevisionResult(roomRevision: document.room.revision), true)
        }
    }

    public func participantInvite(
        room: String, name rawName: String, operationID: UUID
    ) throws -> ARCInstructionResult {
        let name = try ARCText.require(
            rawName, label: "AI name", maximumBytes: 512,
            maximumCharacters: 80, allowPathSeparator: false
        )
        let knowledge = try knowledgeSHA256()
        let operation = operationID.uuidString.lowercased()
        let request = ARCRoomCodec.digest("participant.invite\u{0}\(name)")
        return try files().update(room) { document in
            if try self.isAdminReplay(document, operation: operation, request: request),
               let prior = document.participants.last(where: {
                   $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
               }) {
                return (self.instructionResult(prior, document: document,
                                               now: self.readTime(document)), false)
            }
            if document.participants.count >= ARCConstants.maximumParticipants,
               let retired = document.participants.firstIndex(where: { $0.phase == .retired }) {
                document.participants.remove(at: retired)
            }
            guard document.participants.count < ARCConstants.maximumParticipants else {
                throw ARCError(
                    .limitExceeded,
                    "This room already has \(ARCConstants.maximumParticipants) "
                        + "current AI participants."
                )
            }
            guard !document.participants.contains(where: {
                $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
            }) else {
                throw ARCError(.invalidArgument, "That AI name is already used in this room.")
            }
            var id: String
            repeat { id = ARCText.randomID(prefix: "ai-") }
            while document.participants.contains(where: { $0.id == id })
            let participant = ARCParticipantRecord(
                id: id,
                name: name,
                phase: .invited,
                binding: ARCText.randomUUID(),
                bindingGeneration: 1,
                qualification: nil,
                lastPollLogicalUs: nil,
                nextOperation: ARCText.randomUUID(),
                lastOperation: nil
            )
            let time = self.administrativeMutationTime(&document)
            let logical = time.logical
            document.participants.append(participant)
            document.participants.sort { $0.id < $1.id }
            try self.appendEvent(
                to: &document, logical: logical, kind: "AI_INVITED",
                actor: "administrator", recipient: id, subject: id,
                payload: .object([
                    "name": .string(name),
                    "time_verified": .boolean(time.verified),
                ]),
                operation: operation, knowledge: knowledge
            )
            self.finishAdminMutation(
                &document, logical: logical, operation: operation, request: request
            )
            let stored = document.participants.first { $0.id == id }!
            return (self.instructionResult(
                stored, document: document, now: time.verified ? logical : nil
            ), true)
        }
    }

    public func participantReplaceInstructions(
        room: String, participant id: String, operationID: UUID
    ) throws -> ARCInstructionResult {
        try requireParticipantID(id)
        let knowledge = try knowledgeSHA256()
        let operation = operationID.uuidString.lowercased()
        let request = ARCRoomCodec.digest("participant.replace\u{0}\(id)")
        return try files().update(room) { document in
            guard let index = document.participants.firstIndex(where: { $0.id == id }) else {
                throw ARCError(.notFound, "ARC could not find that AI participant.")
            }
            if try self.isAdminReplay(document, operation: operation, request: request) {
                return (self.instructionResult(
                    document.participants[index], document: document,
                    now: self.readTime(document)
                ), false)
            }
            guard document.participants[index].phase != .retired else {
                throw ARCError(.retired, "That AI participant is retired.")
            }
            let time = self.administrativeMutationTime(&document)
            let logical = time.logical
            var value = document.participants[index]
            value.binding = ARCText.randomUUID()
            value.bindingGeneration += 1
            value.phase = .invited
            value.automaticRecoveryAttempts = nil
            value.qualification = nil
            value.lastPollLogicalUs = nil
            value.workingUntilLogicalUs = nil
            value.nextOperation = ARCText.randomUUID()
            value.lastOperation = nil
            document.participants[index] = value
            let wasProducer = document.room.producerId == id
            if wasProducer {
                document.room.producerId = nil
                document.room.producerGeneration += 1
            }
            try self.appendEvent(
                to: &document, logical: logical, kind: "INSTRUCTIONS_REPLACED",
                actor: "administrator", recipient: id, subject: id,
                payload: .object([
                    "binding_generation": .integer(value.bindingGeneration),
                    "producer_cleared": .boolean(wasProducer),
                    "time_verified": .boolean(time.verified),
                ]), operation: operation, knowledge: knowledge
            )
            self.finishAdminMutation(
                &document, logical: logical, operation: operation, request: request
            )
            return (self.instructionResult(
                value, document: document, now: time.verified ? logical : nil
            ), true)
        }
    }

    public func participantTryAgain(
        room: String, participant id: String, operationID: UUID
    ) throws -> ARCRevisionResult {
        try requireParticipantID(id)
        let knowledge = try knowledgeSHA256()
        let operation = operationID.uuidString.lowercased()
        let request = ARCRoomCodec.digest("participant.retry\u{0}\(id)")
        return try files().update(room) { document in
            guard let index = document.participants.firstIndex(where: { $0.id == id }) else {
                throw ARCError(.notFound, "ARC could not find that AI participant.")
            }
            if try self.isAdminReplay(document, operation: operation, request: request) {
                return (ARCRevisionResult(roomRevision: document.room.revision), false)
            }
            guard document.participants[index].phase == .failed else {
                throw ARCError(.wrongState, "Reconnect AI is available after an expired access check.")
            }
            let logical = try self.mutationTime(&document)
            document.participants[index].phase = .qualifying
            document.participants[index].automaticRecoveryAttempts = nil
            document.participants[index].qualification = ARCQualificationRecord(
                challenge: ARCText.challenge(), startedLogicalUs: logical,
                firstPollLogicalUs: nil, answerLogicalUs: nil
            )
            try self.appendQualificationStart(
                to: &document, participantIndex: index, logical: logical,
                kind: "QUALIFICATION_RETRIED", actor: "administrator",
                operation: operation, knowledge: knowledge
            )
            self.finishAdminMutation(
                &document, logical: logical, operation: operation, request: request
            )
            return (ARCRevisionResult(roomRevision: document.room.revision), true)
        }
    }

    public func participantRetire(
        room: String, participant id: String, operationID: UUID
    ) throws -> ARCRevisionResult {
        try requireParticipantID(id)
        let knowledge = try knowledgeSHA256()
        let operation = operationID.uuidString.lowercased()
        let request = ARCRoomCodec.digest("participant.retire\u{0}\(id)")
        return try files().update(room, reservingRecoverySpace: false) { document in
            guard let index = document.participants.firstIndex(where: { $0.id == id }) else {
                throw ARCError(.notFound, "ARC could not find that AI participant.")
            }
            if try self.isAdminReplay(document, operation: operation, request: request) {
                return (ARCRevisionResult(roomRevision: document.room.revision), false)
            }
            guard document.participants[index].phase != .retired else {
                return (ARCRevisionResult(roomRevision: document.room.revision), false)
            }
            let time = self.administrativeMutationTime(&document)
            try self.applyRetirement(
                &document, index: index, logical: time.logical, verified: time.verified,
                operation: operation, knowledge: knowledge
            )
            return (ARCRevisionResult(roomRevision: document.room.revision), true)
        }
    }

    public func producerSelect(
        room: String, participant id: String, operationID: UUID
    ) throws -> ARCRevisionResult {
        try requireParticipantID(id)
        let knowledge = try knowledgeSHA256()
        let operation = operationID.uuidString.lowercased()
        let request = ARCRoomCodec.digest("producer.select\u{0}\(id)")
        return try files().update(room) { document in
            guard let index = document.participants.firstIndex(where: { $0.id == id }) else {
                throw ARCError(.notFound, "ARC could not find that AI participant.")
            }
            if try self.isAdminReplay(document, operation: operation, request: request) {
                return (ARCRevisionResult(roomRevision: document.room.revision), false)
            }
            let logical = try self.mutationTime(&document)
            guard self.isAvailable(document.participants[index], now: logical) else {
                throw ARCError(.wrongState, "Choose a qualified AI that is On Duty.")
            }
            if document.room.producerId == id {
                return (ARCRevisionResult(roomRevision: document.room.revision), false)
            }
            document.room.producerId = id
            document.room.producerGeneration += 1
            document.room.producerEverSelected = true
            try self.appendEvent(
                to: &document, logical: logical, kind: "PRODUCER_CHANGED",
                actor: "administrator", subject: id,
                payload: .object([
                    "participant": .string(id),
                    "generation": .integer(document.room.producerGeneration),
                ]), operation: operation, knowledge: knowledge
            )
            self.finishAdminMutation(
                &document, logical: logical, operation: operation, request: request
            )
            return (ARCRevisionResult(roomRevision: document.room.revision), true)
        }
    }

    public func roomTick(room: String) throws -> ARCRoomTickResult {
        let knowledge = try knowledgeSHA256()
        return try files().update(room, reservingRecoverySpace: false) { document in
            let previousClock = document.room.lastClockLogicalUs
            let logical = try self.mutationTime(&document)
            let failed = try self.applyDueQualificationFailures(
                &document, now: logical, knowledge: knowledge
            )
            let changed = failed || logical > previousClock
            if changed {
                self.finishMutation(&document, logical: logical)
            }
            return (ARCRoomTickResult(
                room: self.roomView(document, now: logical, knowledge: knowledge),
                producer: self.producerView(document, now: logical)
            ), changed)
        }
    }

    public func activityRead(
        room: String, beforeSequence: Int64? = nil
    ) throws -> ARCActivityPage {
        try files().read(room) { document in
            let high = document.room.nextSequence - 1
            let before = beforeSequence ?? (high + 1)
            guard before >= 1, before <= high + 1 else {
                throw ARCError(.invalidArgument, "The Activity position is invalid.")
            }
            let eligible = document.activity.reversed().filter { $0.sequence < before }
            let page = Array(eligible.prefix(51))
            let visible = Array(page.prefix(50)).map(\.view)
            return ARCActivityPage(
                events: visible,
                nextBefore: page.count > 50 ? visible.last?.sequence : nil
            )
        }
    }

    /// Read-only, bound lane access. Does not qualify, renew duty or consume an
    /// operation token. Sender access supports recovering its own shared context.
    public func terseRead(room: String, participant id: String, binding: String,
                          sequence: Int64? = nil) throws -> ARCJSONValue {
        try requireParticipantID(id)
        guard ARCText.isLowerUUID(binding) else { throw ARCError(.invalidArgument, "Invalid binding.") }
        return try files().read(room) { document in
            guard let caller = document.participants.first(where: { $0.id == id }) else { throw ARCError(.notFound, "AI not found.") }
            try self.validateBinding(caller, binding: binding)
            let notice = ARCCommunication.snapshot(rootURL: self.rootURL)
            guard notice.status == "ready", let digest = notice.specificationSha256 else { throw ARCError(.knowledgeUnavailable, "Terse specification unavailable; pause and notify the operator.") }
            if let sequence {
                let event = try ARCTerseLedger.event(sequence, in: document, reader: id)
                guard let packet = ARCTerseLedger.packet(event) else { throw ARCTerse.fail("not a structured Terse message.") }
                let kind = packet.objectValue?["kind"]?.stringValue
                return .object(["sequence": .integer(sequence), "actor": .string(event.actor),
                    "recipient": .string(event.recipient!), "packet": kind == "context" || kind == "delta" ? .null : packet,
                    "context": kind == "context" || kind == "delta" ? try ARCTerseLedger.resolve(sequence, document: document, reader: id) : .null])
            }
            return ARCTerseLedger.status(document, caller: caller, digest: digest)
        }
    }

    public func diagnose(room: String) throws -> ARCDiagnosticResult {
        var context = [ARCDiagnosticFact(label: "Room ID", value: room)]
        do {
            let fileStore = try files()
            let inspection = try fileStore.inspect(room)
            let document = inspection.document
            context = [
                ARCDiagnosticFact(label: "Room ID", value: document.room.id),
                ARCDiagnosticFact(label: "Lock", value: "Acquired"),
                ARCDiagnosticFact(label: "Format", value: document.format),
                ARCDiagnosticFact(label: "Size", value: "\(inspection.byteCount) bytes"),
                ARCDiagnosticFact(
                    label: "Revision", value: String(document.room.revision)
                ),
                ARCDiagnosticFact(
                    label: "Participants",
                    value: "\(document.participants.count) of \(ARCConstants.maximumParticipants)"
                ),
                ARCDiagnosticFact(
                    label: "Current work",
                    value: "\(document.work.lazy.filter { $0.state != .complete }.count) of "
                        + String(ARCConstants.maximumCurrentWorkItems)
                ),
                ARCDiagnosticFact(
                    label: "Retained work",
                    value: "\(document.work.count) of \(ARCConstants.maximumWorkItems)"
                ),
                ARCDiagnosticFact(
                    label: "Activity",
                    value: "\(document.activity.count) complete retained items"
                ),
                ARCDiagnosticFact(
                    label: "Activity sequences",
                    value: "\(document.activity.first!.sequence) through "
                        + "\(document.activity.last!.sequence); next "
                        + String(document.room.nextSequence)
                ),
            ]

            let knowledge = try knowledgeSHA256()
            context.append(ARCDiagnosticFact(
                label: "Verified knowledge", value: knowledge
            ))
            context.append(ARCDiagnosticFact(
                label: "Latest Activity knowledge",
                value: document.activity.last!.knowledgeSha256
            ))

            do {
                _ = try ARCTime.logicalUS(clock.now())
            } catch {
                throw ARCError(.clockUnavailable, "ARC cannot check time.")
            }
            context.append(ARCDiagnosticFact(label: "Clock", value: "Usable"))
            return ARCDiagnosticResult(valid: true, failure: nil, context: context)
        } catch let error as ARCError {
            return ARCDiagnosticResult(
                valid: false,
                failure: ARCDiagnosticFailure(
                    check: diagnosticCheck(error),
                    message: error.message,
                    nextAction: diagnosticNextAction(error)
                ),
                context: context
            )
        } catch {
            let failure = ARCError(.ioFailure, "ARC could not diagnose that room.")
            return ARCDiagnosticResult(
                valid: false,
                failure: ARCDiagnosticFailure(
                    check: diagnosticCheck(failure),
                    message: failure.message,
                    nextAction: diagnosticNextAction(failure)
                ),
                context: context
            )
        }
    }

    public func roomDelete(room: String) throws -> ARCDeleteResult {
        try files().delete(room) { document in
            document.participants.allSatisfy { $0.phase == .retired }
                || self.canDeleteFullRoom(document, now: self.readTime(document))
        }
        return ARCDeleteResult(deleted: true)
    }

    public func guide(
        room: String, participant id: String, binding: String
    ) throws -> ARCGuideContext {
        try requireParticipantID(id)
        guard ARCText.isLowerUUID(binding) else {
            throw ARCError(.invalidArgument, "The binding is invalid.")
        }
        let knowledge = try knowledgeSHA256()
        return try files().read(room) { document in
            guard let participant = document.participants.first(where: { $0.id == id }) else {
                throw ARCError(.notFound, "ARC could not find that AI participant in this room.")
            }
            try self.validateBinding(participant, binding: binding)
            let now = self.readTime(document)
            return ARCGuideContext(
                room: self.roomView(document, now: now, knowledge: knowledge),
                participant: self.participantView(
                    participant, document: document, now: now
                )
            )
        }
    }

    public func poll(
        room: String, participant id: String, binding: String, after: Int64 = 0
    ) throws -> ARCPollResult {
        try requireParticipantID(id)
        guard ARCText.isLowerUUID(binding), after >= 0 else {
            throw ARCError(.invalidArgument, "The binding or Activity position is invalid.")
        }
        let knowledge = try knowledgeSHA256()
        return try files().update(room) { document in
            guard let index = document.participants.firstIndex(where: { $0.id == id }) else {
                throw ARCError(.notFound, "ARC could not find that AI participant in this room.")
            }
            try self.validateBinding(document.participants[index], binding: binding)
            let highBefore = document.room.nextSequence - 1
            guard after <= highBefore else {
                throw ARCError(.invalidArgument, "The Activity position is beyond this room.")
            }
            let logical = try self.mutationTime(&document)
            var changed = try self.applyDueQualificationFailures(
                &document, now: logical, knowledge: knowledge
            )
            changed = try self.applyPoll(
                &document, participantIndex: index, now: logical, knowledge: knowledge
            ) || changed
            if changed { self.finishMutation(&document, logical: logical) }

            let participant = document.participants[index]
            let allViews = document.participants.map {
                self.participantView($0, document: document, now: logical)
            }
            let visibleEvents = document.activity.filter {
                $0.sequence > after && ($0.recipient == nil || $0.recipient == id)
            }
            let eventPage = Array(visibleEvents.prefix(51))
            let events = Array(eventPage.prefix(50)).map(\.view)
            let high = document.room.nextSequence - 1
            let nextAfter = eventPage.count > 50 ? (events.last?.sequence ?? after) : high
            let callerIsLiveProducer = document.room.producerId == id
                && self.isAvailable(participant, now: logical)
            let currentWork = document.work.filter {
                $0.state != .complete && ($0.owner == id || callerIsLiveProducer)
            }
            let recentCompletedWork: [ARCWorkRecord]
            if participant.phase == .qualified {
                recentCompletedWork = document.work.filter {
                    $0.state == .complete && (callerIsLiveProducer || $0.owner == id)
                }
                    .sorted {
                        $0.updatedLogicalUs == $1.updatedLogicalUs
                            ? $0.id < $1.id : $0.updatedLogicalUs > $1.updatedLogicalUs
                    }
                    .prefix(ARCConstants.maximumRecentCompletedWork)
                    .map { $0 }
            } else {
                recentCompletedWork = []
            }
            let relevantWork = (currentWork + recentCompletedWork).sorted {
                $0.updatedLogicalUs == $1.updatedLogicalUs
                    ? $0.id < $1.id : $0.updatedLogicalUs < $1.updatedLogicalUs
            }.map(self.workView)
            let ownView = self.participantView(participant, document: document, now: logical)
            let earliestRetainedSequence = document.activity.first?.sequence ?? high + 1
            return (ARCPollResult(
                room: self.roomView(document, now: logical, knowledge: knowledge),
                participant: ownView,
                producer: self.producerView(document, now: logical),
                roster: allViews,
                schedule: ownView.schedule,
                qualification: self.qualificationView(participant),
                events: events,
                nextAfter: nextAfter,
                more: eventPage.count > 50,
                work: relevantWork,
                operation: participant.nextOperation,
                earlierActivityUnavailable: earliestRetainedSequence > after + 1,
                communication: ARCCommunication.snapshot(rootURL: self.rootURL)
            ), changed)
        }
    }
}

extension ARCStore {
    private func files() throws -> ARCFileStore { try ARCFileStore(rootURL: rootURL) }

    private func knowledgeSHA256() throws -> String {
        if let explicitKnowledgeSHA256 {
            guard ARCText.isSHA256(explicitKnowledgeSHA256) else {
                throw ARCError(.knowledgeUnavailable, "The test knowledge digest is invalid.")
            }
            return explicitKnowledgeSHA256
        }
        // Production operations re-open the small sealed container so damage
        // or replacement is noticed without requiring an app restart.
        return try ARCKnowledgeFile.openDefault(rootURL: rootURL).sha256
    }

    private func readTime(_ document: ARCRoomDocument) -> Int64? {
        guard let date = try? clock.now(), let sampled = try? ARCTime.logicalUS(date) else {
            return nil
        }
        return max(document.room.lastClockLogicalUs, sampled)
    }

    private func mutationTime(_ document: inout ARCRoomDocument) throws -> Int64 {
        let sampled: Int64
        do { sampled = try ARCTime.logicalUS(clock.now()) }
        catch { throw ARCError(.clockUnavailable, "ARC cannot check time.") }
        let logical = max(document.room.lastClockLogicalUs, sampled)
        document.room.lastClockLogicalUs = logical
        return logical
    }

    private func administrativeMutationTime(
        _ document: inout ARCRoomDocument
    ) -> (logical: Int64, verified: Bool) {
        do { return (try mutationTime(&document), true) }
        catch { return (document.room.lastClockLogicalUs, false) }
    }

    private func roomView(
        _ document: ARCRoomDocument, now: Int64?, knowledge: String
    ) -> ARCRoomView {
        let status: ARCRoomStatus
        if now == nil { status = .timeUnavailable }
        else {
            let available = document.participants.filter { isAvailable($0, now: now!) }
            if available.isEmpty { status = .needsTwoAIs }
            else if available.count == 1 { status = .needsOneAI }
            else if !producerView(document, now: now).live { status = .needsProducer }
            else { status = .active }
        }
        return ARCRoomView(
            id: document.room.id,
            name: document.room.name,
            status: status,
            revision: document.room.revision,
            protocol: ARCConstants.roomProtocol,
            knowledgeSha256: knowledge,
            logicalUs: now ?? document.room.lastClockLogicalUs
        )
    }

    private func producerView(_ document: ARCRoomDocument, now: Int64?) -> ARCProducerView {
        guard let id = document.room.producerId,
              let participant = document.participants.first(where: { $0.id == id }) else {
            return ARCProducerView(
                id: nil, name: nil, generation: document.room.producerGeneration, live: false
            )
        }
        return ARCProducerView(
            id: id,
            name: participant.name,
            generation: document.room.producerGeneration,
            live: now.map { isAvailable(participant, now: $0) } ?? false
        )
    }

    private func participantView(
        _ participant: ARCParticipantRecord,
        document: ARCRoomDocument,
        now: Int64?,
        includeBinding: Bool = false
    ) -> ARCParticipantView {
        let duty: ARCDuty = participant.phase == .qualified
            ? (now.map { isAvailable(participant, now: $0) } == true
                ? (participant.workingUntilLogicalUs != nil ? .working : .on) : .off)
            : .notApplicable
        return ARCParticipantView(
            id: participant.id,
            name: participant.name,
            phase: participant.phase,
            duty: duty,
            isProducer: document.room.producerId == participant.id,
            binding: includeBinding ? participant.binding : nil,
            bindingGeneration: participant.bindingGeneration,
            schedule: schedule(participant, now: now),
            lastCheckIn: participant.lastPollLogicalUs.map(ARCTime.timestamp),
            automaticRecoveryAttempts: participant.automaticRecoveryAttempts ?? 0
        )
    }

    private func qualificationView(
        _ participant: ARCParticipantRecord
    ) -> ARCQualificationView? {
        guard participant.phase == .qualifying,
              let qualification = participant.qualification else { return nil }
        let first = qualification.firstPollLogicalUs
        return ARCQualificationView(
            challenge: qualification.challenge,
            earliestCompletionLogicalUs: first.map { $0 + 40_000_000 },
            deadlineLogicalUs: first.map { $0 + 120_000_000 }
        )
    }

    private func workView(_ work: ARCWorkRecord) -> ARCWorkView {
        ARCWorkView(
            id: work.id,
            owner: work.owner,
            state: work.state,
            scope: work.scope,
            evidenceMode: work.evidenceMode,
            evidence: work.evidence,
            assigningProducerGeneration: work.assigningProducerGeneration,
            revision: work.revision,
            createdAt: work.createdAt,
            updatedAt: work.updatedAt
        )
    }

    private func openResult(
        _ document: ARCRoomDocument, now: Int64?, knowledge: String
    ) -> ARCRoomOpenResult {
        ARCRoomOpenResult(
            room: roomView(document, now: now, knowledge: knowledge),
            producer: producerView(document, now: now),
            participants: document.participants.map {
                participantView(
                    $0, document: document, now: now, includeBinding: true
                )
            },
            work: document.work.filter { $0.state != .complete }.map(workView),
            canDeleteWithoutRetirement: canDeleteFullRoom(document, now: now)
        )
    }

    private func instructionResult(
        _ participant: ARCParticipantRecord,
        document: ARCRoomDocument,
        now: Int64?
    ) -> ARCInstructionResult {
        ARCInstructionResult(
            participant: participantView(
                participant, document: document, now: now, includeBinding: true
            ),
            instructions: ARCInstructions(
                bindingGeneration: participant.bindingGeneration,
                bindingReference: participant.binding ?? ""
            )
        )
    }

    private func isAvailable(_ participant: ARCParticipantRecord, now: Int64) -> Bool {
        guard participant.phase == .qualified, let poll = participant.lastPollLogicalUs,
              now >= poll else { return false }
        // Working preserves availability and existing authority, but expires
        // at its explicit deadline even if the previous poll was recent.
        if let deadline = participant.workingUntilLogicalUs { return now < deadline }
        return now - poll < 180_000_000
    }

    private func canDeleteFullRoom(_ document: ARCRoomDocument, now: Int64?) -> Bool {
        let remaining = document.participants.indices.filter {
            document.participants[$0].phase != .retired
        }
        guard !remaining.isEmpty, let now,
              !document.participants.contains(where: { isAvailable($0, now: now) }),
              document.room.revision < Int64.max - Int64(remaining.count),
              document.room.nextSequence < Int64.max - Int64(remaining.count) else { return false }
        // A live access check also deserves the opportunity to finish.
        guard !document.participants.contains(where: {
            $0.phase == .qualifying && ($0.qualification?.firstPollLogicalUs.map {
                now < $0 + 120_000_000
            } ?? false)
        }) else { return false }
        // Simulate the exact retirement code without writing or removing any
        // history. Only an otherwise valid result that exceeds capacity enables
        // the exceptional delete path. Ordinary inactive rooms still retire first.
        var retired = document
        let operation = "00000000-0000-4000-8000-000000000000"
        guard let knowledge = document.activity.last?.knowledgeSha256 else { return false }
        do {
            for index in remaining {
                try applyRetirement(&retired, index: index, logical: now, verified: true,
                                    operation: operation, knowledge: knowledge)
            }
            _ = try ARCRoomCodec.encode(retired)
            return false
        } catch let error as ARCError {
            return error.code == .limitExceeded
        } catch { return false }
    }

    private func applyRetirement(
        _ document: inout ARCRoomDocument, index: Int, logical: Int64,
        verified: Bool, operation: String, knowledge: String
    ) throws {
        let id = document.participants[index].id
        let wasProducer = document.room.producerId == id
        document.participants[index].phase = .retired
        document.participants[index].binding = nil
        document.participants[index].qualification = nil
        document.participants[index].lastPollLogicalUs = nil
        document.participants[index].workingUntilLogicalUs = nil
        document.participants[index].lastOperation = nil
        if wasProducer {
            document.room.producerId = nil
            document.room.producerGeneration += 1
        }
        try appendEvent(to: &document, logical: logical, kind: "AI_RETIRED",
            actor: "administrator", subject: id,
            payload: .object(["producer_cleared": .boolean(wasProducer),
                              "time_verified": .boolean(verified)]),
            operation: operation, knowledge: knowledge)
        finishAdminMutation(&document, logical: logical, operation: operation,
            request: ARCRoomCodec.digest("participant.retire\u{0}\(id)"))
    }

    private func schedule(_ participant: ARCParticipantRecord, now: Int64?) -> ARCScheduleView {
        guard let now else {
            let kind: ARCScheduleKind
            let status: ARCScheduleStatus
            switch participant.phase {
            case .qualified:
                kind = participant.workingUntilLogicalUs == nil ? .duty : .working
                status = .unavailable
            case .waitingForProducer, .qualifying:
                kind = .qualification
                status = .unavailable
            case .invited, .failed, .retired:
                kind = .none
                status = .none
            }
            return ARCScheduleView(
                kind: kind, status: status,
                nextRequestLogicalUs: nil, deadlineLogicalUs: nil
            )
        }
        if participant.phase == .waitingForProducer {
            return ARCScheduleView(
                kind: .qualification, status: .waiting,
                nextRequestLogicalUs: nil, deadlineLogicalUs: nil
            )
        }
        if participant.phase == .qualifying, let value = participant.qualification {
            guard let firstPoll = value.firstPollLogicalUs else {
                return ARCScheduleView(
                    kind: .qualification, status: .waiting,
                    nextRequestLogicalUs: nil, deadlineLogicalUs: nil
                )
            }
            let boundaries = [
                firstPoll + 40_000_000,
                firstPoll + 80_000_000,
                firstPoll + 120_000_000,
            ]
            let status: ARCScheduleStatus = now < boundaries[0] ? .ok
                : now < boundaries[1] ? .request2
                : now < boundaries[2] ? .request3 : .expired
            let next = boundaries.first { $0 > now }
            return ARCScheduleView(
                kind: .qualification, status: status,
                nextRequestLogicalUs: next, deadlineLogicalUs: boundaries[2]
            )
        }
        if participant.phase == .qualified, let deadline = participant.workingUntilLogicalUs {
            return ARCScheduleView(
                kind: .working, status: now < deadline ? .ok : .expired,
                nextRequestLogicalUs: now < deadline ? deadline : nil,
                deadlineLogicalUs: deadline
            )
        }
        if participant.phase == .qualified, let poll = participant.lastPollLogicalUs {
            let boundaries = [
                poll + 60_000_000, poll + 100_000_000,
                poll + 140_000_000, poll + 180_000_000,
            ]
            let status: ARCScheduleStatus = now < boundaries[0] ? .ok
                : now < boundaries[1] ? .request1
                : now < boundaries[2] ? .request2
                : now < boundaries[3] ? .request3 : .expired
            return ARCScheduleView(
                kind: .duty, status: status,
                nextRequestLogicalUs: boundaries.first { $0 > now },
                deadlineLogicalUs: boundaries[3]
            )
        }
        return ARCScheduleView(
            kind: .none, status: .none, nextRequestLogicalUs: nil, deadlineLogicalUs: nil
        )
    }

    private func requireParticipantID(_ id: String) throws {
        guard ARCText.isSafeID(id, prefix: "ai-") else {
            throw ARCError(.invalidArgument, "The AI participant ID is invalid.")
        }
    }

    private func validateBinding(_ participant: ARCParticipantRecord, binding: String) throws {
        if participant.phase == .retired {
            throw ARCError(.retired, "This AI participant is retired.")
        }
        guard participant.binding == binding else {
            throw ARCError(
                .bindingInvalid,
                "These AI instructions are no longer current. Ask the Administrator to replace them."
            )
        }
    }

    private func isAdminReplay(
        _ document: ARCRoomDocument, operation: String, request: String
    ) throws -> Bool {
        guard let prior = document.room.lastAdminOperation, prior.id == operation else {
            return false
        }
        guard prior.requestDigest == request else {
            throw ARCError(.operationConflict, "That Administrator retry changed its request.")
        }
        return true
    }

    private func finishAdminMutation(
        _ document: inout ARCRoomDocument,
        logical: Int64,
        operation: String,
        request: String
    ) {
        document.room.lastAdminOperation = ARCAdminOperationRecord(
            id: operation, requestDigest: request
        )
        finishMutation(&document, logical: logical)
    }

    private func finishMutation(_ document: inout ARCRoomDocument, logical: Int64) {
        document.room.revision += 1
        document.room.updatedAt = ARCTime.timestamp(logical)
        document.room.lastClockLogicalUs = logical
    }

    private func appendEvent(
        to document: inout ARCRoomDocument,
        logical: Int64,
        kind: String,
        actor: String,
        recipient: String? = nil,
        subject: String? = nil,
        payload: ARCJSONValue,
        operation: String,
        knowledge: String
    ) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard let payloadBytes = try? encoder.encode(payload),
              payloadBytes.count <= maximumEventBytes else {
            throw ARCError(.limitExceeded, "An Activity item is too large.")
        }
        let event = ARCEventRecord(
            sequence: document.room.nextSequence,
            at: ARCTime.timestamp(logical),
            logicalUs: logical,
            kind: kind,
            actor: actor,
            recipient: recipient,
            subject: subject,
            payload: payload,
            operationId: operation,
            knowledgeSha256: knowledge
        )
        document.room.nextSequence += 1
        document.activity.append(event)
    }

    private func appendQualificationStart(
        to document: inout ARCRoomDocument,
        participantIndex: Int,
        logical: Int64,
        kind: String = "QUALIFICATION_STARTED",
        actor: String,
        operation: String,
        knowledge: String
    ) throws {
        let participant = document.participants[participantIndex]
        guard let challenge = participant.qualification?.challenge else {
            throw ARCError(.roomCorrupt, "The qualification challenge is missing.")
        }
        var payload: [String: ARCJSONValue] = [
            "challenge": .string(challenge),
            "answer_type": .string("qualification.answer"),
            "awaiting_first_poll": .boolean(participant.qualification?.firstPollLogicalUs == nil),
        ]
        if let first = participant.qualification?.firstPollLogicalUs {
            payload["deadline_logical_us"] = .integer(first + 120_000_000)
        }
        try appendEvent(
            to: &document, logical: logical, kind: kind, actor: actor,
            recipient: participant.id, subject: participant.id,
            payload: .object(payload), operation: operation, knowledge: knowledge
        )
    }

    private func applyDueQualificationFailures(
        _ document: inout ARCRoomDocument, now: Int64, knowledge: String
    ) throws -> Bool {
        var changed = false
        let operation = ARCText.randomUUID()
        for index in document.participants.indices {
            guard document.participants[index].phase == .qualifying,
                  let qualification = document.participants[index].qualification,
                  let firstPoll = qualification.firstPollLogicalUs,
                  now >= firstPoll + 120_000_000 else { continue }
            let id = document.participants[index].id
            document.participants[index].phase = .failed
            document.participants[index].qualification = nil
            try appendEvent(
                to: &document, logical: now, kind: "QUALIFICATION_FAILED",
                actor: "arc", recipient: id, subject: id,
                payload: .object(["reason": .string("The two-minute check expired.")]),
                operation: operation, knowledge: knowledge
            )
            changed = true
        }
        return changed
    }

    private func applyPoll(
        _ document: inout ARCRoomDocument,
        participantIndex index: Int,
        now: Int64,
        knowledge: String
    ) throws -> Bool {
        var changed = false
        let operation = ARCText.randomUUID()
        let id = document.participants[index].id
        switch document.participants[index].phase {
        case .invited:
            document.participants[index].phase = .waitingForProducer
            try appendEvent(
                to: &document, logical: now, kind: "AI_JOINED",
                actor: id, subject: id, payload: .object([:]),
                operation: operation, knowledge: knowledge
            )
            changed = true
            if !producerView(document, now: now).live {
                document.participants[index].phase = .qualifying
                document.participants[index].qualification = ARCQualificationRecord(
                    challenge: ARCText.challenge(), startedLogicalUs: now,
                    firstPollLogicalUs: now, answerLogicalUs: nil
                )
                try appendQualificationStart(
                    to: &document, participantIndex: index, logical: now,
                    actor: "arc", operation: operation, knowledge: knowledge
                )
            }
        case .waitingForProducer:
            // A missing or Off Duty Producer must never strand a candidate.
            // ARC owns this fallback; the Administrator has no hidden duty.
            if !producerView(document, now: now).live {
                document.participants[index].phase = .qualifying
                document.participants[index].qualification = ARCQualificationRecord(
                    challenge: ARCText.challenge(), startedLogicalUs: now,
                    firstPollLogicalUs: now, answerLogicalUs: nil
                )
                try appendQualificationStart(
                    to: &document, participantIndex: index, logical: now,
                    actor: "arc", operation: operation, knowledge: knowledge
                )
                changed = true
            }
        case .qualifying:
            guard var qualification = document.participants[index].qualification else {
                throw ARCError(.roomCorrupt, "The qualification state is incomplete.")
            }
            if qualification.firstPollLogicalUs == nil {
                qualification.firstPollLogicalUs = now
                document.participants[index].qualification = qualification
                changed = true
            } else if let first = qualification.firstPollLogicalUs,
                      qualification.answerLogicalUs != nil,
                      now >= first + 40_000_000,
                      now < first + 120_000_000 {
                document.participants[index].phase = .qualified
                document.participants[index].qualification = nil
                document.participants[index].lastPollLogicalUs = now
                var becameProducer = false
                if !document.room.producerEverSelected {
                    document.room.producerId = id
                    document.room.producerGeneration = 1
                    document.room.producerEverSelected = true
                    becameProducer = true
                }
                try appendEvent(
                    to: &document, logical: now, kind: "AI_QUALIFIED",
                    actor: id, subject: id,
                    payload: .object(["became_producer": .boolean(becameProducer)]),
                    operation: operation, knowledge: knowledge
                )
                changed = true
            }
        case .qualified:
            let wasAvailable = isAvailable(document.participants[index], now: now)
            let wasWorking = document.participants[index].workingUntilLogicalUs != nil
            document.participants[index].workingUntilLogicalUs = nil
            document.participants[index].lastPollLogicalUs = now
            changed = true
            if !wasAvailable || wasWorking {
                try appendEvent(
                    to: &document, logical: now, kind: "AI_RETURNED_ON_DUTY",
                    actor: id, subject: id, payload: .object([:]),
                    operation: operation, knowledge: knowledge
                )
            }
        case .failed:
            // Recover only when this exact bound AI actually returns. Timers and
            // other participants cannot consume its new two-minute window.
            let attempts = document.participants[index].automaticRecoveryAttempts ?? 0
            if attempts < 2 {
                document.participants[index].automaticRecoveryAttempts = attempts + 1
                document.participants[index].phase = .qualifying
                document.participants[index].qualification = ARCQualificationRecord(
                    challenge: ARCText.challenge(), startedLogicalUs: now,
                    firstPollLogicalUs: now, answerLogicalUs: nil)
                try appendQualificationStart(to: &document, participantIndex: index,
                    logical: now, kind: "QUALIFICATION_RECOVERED", actor: "arc",
                    operation: operation, knowledge: knowledge)
                changed = true
            }
        case .retired:
            throw ARCError(.retired, "This AI participant is retired.")
        }
        return changed
    }

    private func diagnosticCheck(_ error: ARCError) -> String {
        switch error.code {
        case .invalidArgument, .notFound: return "PATH"
        case .roomIncompatible: return "FORMAT"
        case .roomCorrupt: return "ROOM_JSON"
        case .knowledgeUnavailable: return "KNOWLEDGE"
        case .clockUnavailable: return "CLOCK"
        case .busy: return "LOCK"
        case .ioFailure where error.message.localizedCaseInsensitiveContains("lock"):
            return "LOCK"
        default: return "IO"
        }
    }

    private func diagnosticNextAction(_ error: ARCError) -> String {
        switch diagnosticCheck(error) {
        case "PATH": return "Return to the room list."
        case "KNOWLEDGE": return "Install ARC again, then diagnose this room again."
        case "CLOCK": return "Check the Mac date and time, then diagnose this room again."
        case "LOCK": return "Wait for the current room operation, then diagnose again."
        default:
            return "Keep the room unchanged and contact ARC support."
        }
    }
}

private enum ARCActOutcome {
    case success(ARCActResult)
    case failure(ARCError)
}

public extension ARCStore {
    func act(
        room: String,
        participant id: String,
        binding: String,
        operation: String,
        requestJSON: Data
    ) throws -> ARCActResult {
        try act(
            room: room,
            participant: id,
            binding: binding,
            operation: operation,
            request: ARCActionJSON.decode(requestJSON)
        )
    }

    func act(
        room: String,
        participant id: String,
        binding: String,
        operation: String,
        request: ARCActionRequest
    ) throws -> ARCActResult {
        try requireParticipantID(id)
        guard ARCText.isLowerUUID(binding), ARCText.isLowerUUID(operation) else {
            throw ARCError(.invalidArgument, "The binding or operation token is invalid.")
        }
        // The typed app entry and the JSON CLI entry share one exact admission
        // path, including NFC normalization and all byte/shape bounds.
        let request = try ARCActionJSON.decode(ARCActionJSON.encode(request))
        let requestDigest = try ARCRoomCodec.requestDigest(request)
        let knowledge = try knowledgeSHA256()
        let outcome: ARCActOutcome = try files().update(room) { document in
            guard let callerIndex = document.participants.firstIndex(where: { $0.id == id }) else {
                throw ARCError(.notFound, "ARC could not find that AI participant in this room.")
            }
            try self.validateBinding(document.participants[callerIndex], binding: binding)

            if let prior = document.participants[callerIndex].lastOperation,
               prior.token == operation {
                guard prior.requestDigest == requestDigest else {
                    throw ARCError(.operationConflict, "That operation retry changed its request.")
                }
                let now = self.readTime(document)
                return (.success(self.replayResult(prior, document: document, now: now)), false)
            }
            guard document.participants[callerIndex].nextOperation == operation else {
                throw ARCError(.operationStale, "That operation token is no longer current.")
            }

            let logical = try self.mutationTime(&document)
            let dueChanged = try self.applyDueQualificationFailures(
                &document, now: logical, knowledge: knowledge
            )
            var actionDocument = document
            do {
                let sequenceStart = actionDocument.room.nextSequence
                let resultIDs = try self.applyAction(
                    request,
                    to: &actionDocument,
                    callerIndex: callerIndex,
                    now: logical,
                    operation: operation,
                    knowledge: knowledge
                )
                self.finishMutation(&actionDocument, logical: logical)
                let next = ARCText.randomUUID()
                actionDocument.participants[callerIndex].nextOperation = next
                let sequences = Array(sequenceStart..<actionDocument.room.nextSequence)
                let record = ARCLastOperationRecord(
                    token: operation,
                    requestDigest: requestDigest,
                    eventSequences: sequences,
                    roomRevision: actionDocument.room.revision,
                    participantId: resultIDs.participant,
                    workId: resultIDs.work,
                    nextOperation: next
                )
                actionDocument.participants[callerIndex].lastOperation = record
                document = actionDocument
                return (.success(self.replayResult(
                    record, document: document, now: logical
                )), true)
            } catch let error as ARCError {
                if dueChanged { self.finishMutation(&document, logical: logical) }
                return (.failure(error), dueChanged)
            }
        }
        switch outcome {
        case .success(let result): return result
        case .failure(let error): throw error
        }
    }
}

extension ARCStore {
    private func applyAction(
        _ request: ARCActionRequest,
        to document: inout ARCRoomDocument,
        callerIndex: Int,
        now: Int64,
        operation: String,
        knowledge: String
    ) throws -> (participant: String?, work: String?) {
        let caller = document.participants[callerIndex]
        switch request {
        case .terseSend(let targetID, let packet):
            try requireAvailable(caller, now: now)
            guard let target = document.participants.first(where: { $0.id == targetID }), target.phase == .qualified else {
                throw ARCError(.wrongState, "Terse needs a qualified recipient in this room.")
            }
            let notice = ARCCommunication.snapshot(rootURL: rootURL)
            guard notice.status == "ready", let digest = notice.specificationSha256 else {
                throw ARCError(.knowledgeUnavailable, "Read the verified Terse specification before sending.")
            }
            try ARCTerseLedger.validateSend(packet, document: document, caller: caller, target: target, digest: digest)
            try appendEvent(to: &document, logical: now, kind: "TERSE_MESSAGE", actor: caller.id,
                recipient: target.id, payload: .object([
                    "packet": packet,
                    "binding_generation": .integer(caller.bindingGeneration),
                    "target_binding_generation": .integer(target.bindingGeneration),
                    "specification_sha256": .string(digest)
                ]), operation: operation, knowledge: knowledge)
            return (nil, nil)
        case .working(let deadline):
            try requireAvailable(caller, now: now)
            guard ARCTime.isLogical(deadline), deadline > now,
                  caller.workingUntilLogicalUs.map({ deadline > $0 }) ?? true else {
                throw ARCError(.invalidArgument, "Working needs a future deadline; an extension must move it later.")
            }
            document.participants[callerIndex].workingUntilLogicalUs = deadline
            try appendEvent(
                to: &document, logical: now, kind: "AI_WORKING", actor: caller.id,
                subject: caller.id, payload: .object(["until_logical_us": .integer(deadline)]),
                operation: operation, knowledge: knowledge
            )
            return (caller.id, nil)
        case .message(let targetID, let text):
            try requireAvailable(caller, now: now)
            guard let target = document.participants.first(where: { $0.id == targetID }) else {
                throw ARCError(.notFound, "ARC could not find the message target.")
            }
            guard target.phase == .qualified else {
                throw ARCError(.wrongState, "Messages require a qualified AI target.")
            }
            try appendEvent(
                to: &document, logical: now, kind: "MESSAGE",
                actor: caller.id, recipient: targetID,
                payload: .object(["text": .string(text)]),
                operation: operation, knowledge: knowledge
            )
            return (nil, nil)

        case .messageBroadcast(let text):
            try requireAvailable(caller, now: now)
            // Snapshot recipients under the same room lock as the commit. Use
            // ordinary addressed events so old histories and privacy filtering
            // retain their meaning. A failed write commits none of the fan-out.
            let recipients = document.participants.filter {
                $0.phase == .qualified && $0.id != caller.id
            }.map(\.id).sorted()
            guard !recipients.isEmpty else {
                throw ARCError(.wrongState, "A room-wide message needs at least one other qualified AI.")
            }
            guard Int64(recipients.count) < Int64.max - document.room.nextSequence else {
                throw ARCError(.limitExceeded, "This room has reached its event sequence limit.")
            }
            for recipient in recipients {
                try appendEvent(to: &document, logical: now, kind: "MESSAGE",
                    actor: caller.id, recipient: recipient,
                    payload: .object(["text": .string(text)]),
                    operation: operation, knowledge: knowledge)
            }
            return (nil, nil)

        case .qualificationStart(let targetID, let generation):
            try requireLiveProducer(
                caller, document: document, now: now, generation: generation
            )
            guard let targetIndex = document.participants.firstIndex(where: { $0.id == targetID })
            else { throw ARCError(.notFound, "ARC could not find that AI participant.") }
            guard document.participants[targetIndex].phase == .waitingForProducer else {
                throw ARCError(.wrongState, "That AI is not waiting for a qualification check.")
            }
            document.participants[targetIndex].phase = .qualifying
            document.participants[targetIndex].qualification = ARCQualificationRecord(
                challenge: ARCText.challenge(), startedLogicalUs: now,
                firstPollLogicalUs: nil, answerLogicalUs: nil
            )
            try appendQualificationStart(
                to: &document, participantIndex: targetIndex, logical: now,
                actor: caller.id, operation: operation, knowledge: knowledge
            )
            return (targetID, nil)

        case .qualificationAnswer(let answer):
            guard caller.phase == .qualifying,
                  var qualification = caller.qualification else {
                throw ARCError(.wrongState, "This AI is not taking the ARC qualification check.")
            }
            guard let firstPoll = qualification.firstPollLogicalUs,
                  now < firstPoll + 120_000_000 else {
                throw ARCError(.wrongState, "The qualification check has expired.")
            }
            guard answer == qualification.challenge else {
                throw ARCError(.wrongState, "That qualification answer is not the current challenge.")
            }
            qualification.answerLogicalUs = now
            document.participants[callerIndex].qualification = qualification
            try appendEvent(
                to: &document, logical: now, kind: "QUALIFICATION_ANSWERED",
                actor: caller.id, recipient: caller.id, subject: caller.id,
                payload: .object([:]), operation: operation, knowledge: knowledge
            )
            return (caller.id, nil)

        case .workAssign(let ownerID, let scope, let mode, let generation):
            try requireLiveProducer(
                caller, document: document, now: now, generation: generation
            )
            guard let owner = document.participants.first(where: { $0.id == ownerID }) else {
                throw ARCError(.notFound, "ARC could not find the work owner.")
            }
            try requireAvailable(owner, now: now)
            guard document.work.lazy.filter({ $0.state != .complete }).count
                    < ARCConstants.maximumCurrentWorkItems else {
                throw ARCError(
                    .limitExceeded,
                    "This room already has 50 current work items."
                )
            }
            while document.work.count >= ARCConstants.maximumWorkItems,
                  let complete = document.work.firstIndex(where: { $0.state == .complete }) {
                document.work.remove(at: complete)
            }
            guard document.work.count < ARCConstants.maximumWorkItems else {
                throw ARCError(.limitExceeded, "This room has reached its work history limit.")
            }
            var workID: String
            repeat { workID = ARCText.randomID(prefix: "work-") }
            while document.work.contains(where: { $0.id == workID })
            let timestamp = ARCTime.timestamp(now)
            let item = ARCWorkRecord(
                id: workID,
                owner: ownerID,
                state: .open,
                scope: scope,
                evidenceMode: mode,
                evidence: .object([:]),
                assigningProducerGeneration: generation,
                revision: 1,
                createdAt: timestamp,
                updatedAt: timestamp,
                updatedLogicalUs: now
            )
            document.work.append(item)
            try appendEvent(
                to: &document, logical: now, kind: "WORK_ASSIGNED",
                actor: caller.id, recipient: ownerID, subject: workID,
                payload: .object([
                    "scope": .string(scope), "evidence_mode": .string(mode.rawValue),
                ]), operation: operation, knowledge: knowledge
            )
            return (nil, workID)

        case .workUpdate(let workID, let revision, let state, let evidence):
            try requireAvailable(caller, now: now)
            guard let index = document.work.firstIndex(where: { $0.id == workID }) else {
                throw ARCError(.notFound, "ARC could not find that work item.")
            }
            let current = document.work[index]
            guard current.owner == caller.id else {
                throw ARCError(.wrongState, "Only the current work owner can update this item.")
            }
            guard current.revision == revision else {
                throw ARCError(.wrongState, "The work item changed; poll before updating it.")
            }
            guard allowedTransition(from: current.state, to: state) else {
                throw ARCError(.wrongState, "That work-state change is not allowed.")
            }
            try ARCEvidence.validate(evidence, state: state, mode: current.evidenceMode)
            if state == .complete {
                try validateInspectionTime(evidence, work: current, now: now)
            }
            document.work[index].state = state
            document.work[index].evidence = evidence
            document.work[index].revision += 1
            document.work[index].updatedAt = ARCTime.timestamp(now)
            document.work[index].updatedLogicalUs = now
            try appendEvent(
                to: &document, logical: now, kind: "WORK_UPDATED",
                actor: caller.id, subject: workID,
                payload: .object([
                    "state": .string(state.rawValue), "evidence": evidence,
                    "revision": .integer(document.work[index].revision),
                ]), operation: operation, knowledge: knowledge
            )
            return (nil, workID)

        case .workCorrect(let workID, let revision, let reason, let evidence):
            try requireAvailable(caller, now: now)
            guard let index = document.work.firstIndex(where: { $0.id == workID }) else {
                throw ARCError(.notFound, "ARC could not find that retained work item.")
            }
            let current = document.work[index]
            guard current.owner == caller.id, current.state == .complete,
                  current.revision == revision else {
                throw ARCError(.wrongState, "Only the current owner can correct retained COMPLETE work at its current revision; poll first.")
            }
            try ARCEvidence.validate(evidence, state: .complete, mode: current.evidenceMode)
            try validateInspectionTime(evidence, work: current, now: now)
            document.work[index].evidence = evidence
            document.work[index].revision += 1
            document.work[index].updatedAt = ARCTime.timestamp(now)
            document.work[index].updatedLogicalUs = now
            try appendEvent(to: &document, logical: now, kind: "WORK_CORRECTED",
                actor: caller.id, subject: workID, payload: .object([
                    "state": .string("COMPLETE"), "evidence": evidence,
                    "reason": .string(reason), "supersedes_revision": .integer(revision),
                    "revision": .integer(document.work[index].revision),
                ]), operation: operation, knowledge: knowledge)
            return (nil, workID)

        case .workReassign(
            let workID, let revision, let ownerID, let reason, let generation
        ):
            try requireLiveProducer(
                caller, document: document, now: now, generation: generation
            )
            guard let index = document.work.firstIndex(where: { $0.id == workID }) else {
                throw ARCError(.notFound, "ARC could not find that work item.")
            }
            guard document.work[index].revision == revision else {
                throw ARCError(.wrongState, "That work item cannot be reassigned from this view.")
            }
            if document.work[index].state == .complete,
               document.work.lazy.filter({ $0.state != .complete }).count >= ARCConstants.maximumCurrentWorkItems {
                throw ARCError(.limitExceeded, "Reopening this item would exceed the 50 current work item limit.")
            }
            guard let owner = document.participants.first(where: { $0.id == ownerID }) else {
                throw ARCError(.notFound, "ARC could not find the new work owner.")
            }
            try requireAvailable(owner, now: now)
            document.work[index].owner = ownerID
            document.work[index].state = .open
            document.work[index].evidence = .object([:])
            document.work[index].revision += 1
            document.work[index].assigningProducerGeneration = generation
            document.work[index].updatedAt = ARCTime.timestamp(now)
            document.work[index].updatedLogicalUs = now
            try appendEvent(
                to: &document, logical: now, kind: "WORK_REASSIGNED",
                actor: caller.id, recipient: ownerID, subject: workID,
                payload: .object([
                    "reason": .string(reason), "owner": .string(ownerID),
                    "revision": .integer(document.work[index].revision),
                ]), operation: operation, knowledge: knowledge
            )
            return (nil, workID)
        }
    }

    private func validateInspectionTime(_ evidence: ARCJSONValue, work: ARCWorkRecord, now: Int64) throws {
        guard work.evidenceMode == .visual else { return }
        // Canonical fixed-width UTC timestamps compare lexically without losing
        // microseconds to floating-point Date conversion. Legacy records remain
        // readable; this stronger check applies only to new completion/correction.
        guard let inspected = evidence.objectValue?["inspected_at"]?.stringValue,
              inspected >= work.createdAt, inspected <= ARCTime.timestamp(now) else {
            throw ARCError(.invalidArgument, "Work evidence: inspected_at must be at or after work creation and no later than this request. Perform the inspection and record its actual UTC time; do not copy an example.")
        }
    }

    private func replayResult(
        _ record: ARCLastOperationRecord,
        document: ARCRoomDocument,
        now: Int64?
    ) -> ARCActResult {
        let participant = record.participantId.flatMap { id in
            document.participants.first(where: { $0.id == id }).map {
                participantView($0, document: document, now: now)
            }
        }
        let work = record.workId.flatMap { id in
            document.work.first(where: { $0.id == id }).map(workView)
        }
        return ARCActResult(
            eventSequences: record.eventSequences,
            roomRevision: record.roomRevision,
            participant: participant,
            work: work,
            nextOperation: record.nextOperation
        )
    }

    private func requireAvailable(_ participant: ARCParticipantRecord, now: Int64) throws {
        guard isAvailable(participant, now: now) else {
            throw ARCError(.wrongState, "This action requires a qualified AI that is On Duty.")
        }
    }

    private func requireLiveProducer(
        _ participant: ARCParticipantRecord,
        document: ARCRoomDocument,
        now: Int64,
        generation: Int64
    ) throws {
        guard document.room.producerId == participant.id,
              isAvailable(participant, now: now) else {
            throw ARCError(.notProducer, "This action requires the current On Duty Producer.")
        }
        guard document.room.producerGeneration == generation else {
            throw ARCError(.wrongState, "The Producer changed; poll before acting.")
        }
    }

    private func allowedTransition(from: ARCWorkState, to: ARCWorkState) -> Bool {
        switch (from, to) {
        case (.open, .active), (.open, .blocked), (.open, .complete),
             (.active, .blocked), (.active, .complete),
             (.blocked, .active), (.blocked, .complete): true
        default: false
        }
    }
}
