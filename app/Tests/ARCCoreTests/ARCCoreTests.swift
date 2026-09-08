import Foundation
import Darwin
import XCTest
@testable import ARCCore

final class ARCCoreTests: XCTestCase {
    private let digest = String(repeating: "a", count: 64)
    private var roots: [URL] = []

    func testTerseGuidanceDoesNotRejectOrTranslateMessageText() throws {
        let context = try qualifiedPair()
        let text = "\nTHIS IS NOT VALID TERSE\n[de] Dieser Gedanke braucht eine genaue Erklärung.\n[en] Keep the original words.\n"
        _ = try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .message(to: context.second.id, text: text))
        let event = try XCTUnwrap(context.store.activityRead(room: context.room).events.first)
        XCTAssertEqual(event.kind, "MESSAGE")
        XCTAssertEqual(event.payload.objectValue?["text"]?.stringValue, text)
        let reopened = ARCStore(rootURL: context.store.rootURL, knowledgeSHA256: digest)
        XCTAssertEqual(try reopened.activityRead(room: context.room).events.first?.payload.objectValue?["text"]?.stringValue, text)
        XCTAssertTrue(try reopened.diagnose(room: context.room).valid)
    }

    override func tearDownWithError() throws {
        for root in roots { try? FileManager.default.removeItem(at: root) }
        roots.removeAll()
    }

    func testCreationRetrySurvivesLaterMutationsAndRejectsChangedRequest() throws {
        let setup = try makeStore()
        let operation = UUID()
        let created = try setup.store.roomCreate(displayName: "Original", operationID: operation)
        _ = try setup.store.roomRename(room: created.room.id, displayName: "Renamed", operationID: UUID())
        let replay = try setup.store.roomCreate(displayName: "Original", operationID: operation)
        XCTAssertEqual(replay.room.id, created.room.id)
        XCTAssertEqual(replay.room.name, "Renamed")
        XCTAssertEqual(try setup.store.roomList().rooms.count, 1)
        XCTAssertThrowsError(try setup.store.roomCreate(displayName: "Different", operationID: operation)) {
            XCTAssertEqual(($0 as? ARCError)?.code, .operationConflict)
        }
        let distinct = try setup.store.roomCreate(displayName: "Original", operationID: UUID())
        XCTAssertNotEqual(distinct.room.id, created.room.id)
    }

    func testWorkingExtendsReplaysReturnsAndExpiresAtExactDeadline() throws {
        let context = try qualifiedPair()
        let now = try context.store.roomOpen(room: context.room).room.logicalUs
        let deadline = now + 600_000_000
        let request = ARCActionRequest.working(untilLogicalUs: deadline)
        XCTAssertEqual(try ARCActionJSON.decode(ARCActionJSON.encode(request)), request)
        let started = try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation, request: request)
        context.clock.advance(seconds: 300)
        let reopened = ARCStore(rootURL: context.store.rootURL,
            clock: ARCClock { context.clock.now() }, knowledgeSHA256: digest)
        let working = try reopened.roomOpen(room: context.room)
        XCTAssertEqual(working.participants.first { $0.id == context.first.id }?.duty, .working)
        XCTAssertTrue(working.producer.live)
        XCTAssertEqual(working.participants.first { $0.id == context.first.id }?.schedule.deadlineLogicalUs, deadline)
        let replay = try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation, request: request)
        XCTAssertEqual(replay.roomRevision, started.roomRevision)
        XCTAssertThrowsError(try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: started.nextOperation,
            request: .working(untilLogicalUs: deadline)))
        _ = try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: started.nextOperation,
            request: .working(untilLogicalUs: deadline + 600_000_000))
        let returned = try context.store.poll(room: context.room, participant: context.first.id,
            binding: context.first.binding)
        XCTAssertEqual(returned.participant.duty, .on)
        XCTAssertEqual(returned.schedule.kind, .duty)
        let shortDeadline = returned.room.logicalUs + 30_000_000
        let short = try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: returned.operation,
            request: .working(untilLogicalUs: shortDeadline))
        context.clock.advance(seconds: 30)
        _ = try context.store.roomTick(room: context.room)
        context.clock.advance(seconds: -1)
        let expired = try context.store.roomOpen(room: context.room)
        XCTAssertEqual(expired.participants.first { $0.id == context.first.id }?.duty, .off)
        XCTAssertFalse(expired.producer.live)
        XCTAssertThrowsError(try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: short.nextOperation,
            request: .working(untilLogicalUs: shortDeadline + 60_000_000))) {
            XCTAssertEqual(($0 as? ARCError)?.code, .wrongState)
        }
        let onDuty = try context.store.poll(room: context.room, participant: context.first.id,
            binding: context.first.binding)
        XCTAssertEqual(onDuty.participant.duty, .on)
        XCTAssertTrue(try context.store.diagnose(room: context.room).valid)
    }

    func testWorkingRequiresQualificationAndValidFutureDeadline() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(displayName: "Working admission", operationID: UUID()).room.id
        let invited = try setup.store.participantInvite(room: room, name: "Candidate", operationID: UUID())
        let poll = try setup.store.poll(room: room, participant: invited.participant.id,
            binding: invited.instructions.bindingReference)
        XCTAssertThrowsError(try setup.store.act(room: room, participant: invited.participant.id,
            binding: invited.instructions.bindingReference, operation: poll.operation,
            request: .working(untilLogicalUs: poll.room.logicalUs + 60_000_000)))
        let context = try qualifiedPair()
        let now = try context.store.roomOpen(room: context.room).room.logicalUs
        for deadline in [Int64(-1), now, Int64.max] {
            XCTAssertThrowsError(try context.store.act(room: context.room, participant: context.first.id,
                binding: context.first.binding, operation: context.first.operation,
                request: .working(untilLogicalUs: deadline))) {
                XCTAssertEqual(($0 as? ARCError)?.code, .invalidArgument)
            }
        }
        _ = try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .working(untilLogicalUs: now + 60_000_000))
        _ = try context.store.participantReplaceInstructions(room: context.room,
            participant: context.first.id, operationID: UUID())
        XCTAssertTrue(try context.store.diagnose(room: context.room).valid)
        XCTAssertEqual(try context.store.roomOpen(room: context.room).participants.first {
            $0.id == context.first.id
        }?.phase, .invited)
    }

    func testFullNormalWritePreservesCapacityForRetirementAndDeletion() throws {
        let context = try qualifiedPair()
        let roomURL = try context.store.roomFileURL(room: context.room)
        var document = try ARCRoomCodec.decode(Data(contentsOf: roomURL), expectedID: context.room)
        let now = document.room.lastClockLogicalUs
        document.activity = (1...500).map { sequence in
            ARCEventRecord(sequence: Int64(sequence), at: ARCTime.timestamp(now), logicalUs: now,
                kind: "MESSAGE", actor: context.first.id, recipient: context.second.id, subject: nil,
                payload: .object(["text": .string(String(repeating: "x", count: 15_000))]),
                operationId: UUID().uuidString.lowercased(), knowledgeSha256: digest)
        }
        document.room.nextSequence = 501
        let limit = ARCConstants.maximumRoomBytes - 1_024 - 2 * 4_096
        var remaining = limit - (try ARCRoomCodec.encode(document)).count
        XCTAssertGreaterThan(remaining, 0)
        for index in document.activity.indices {
            let extra = min(1_384, remaining)
            document.activity[index].payload = .object(["text": .string(String(repeating: "x", count: 15_000 + extra))])
            remaining -= extra
        }
        XCTAssertEqual(remaining, 0)
        let fileStore = try ARCFileStore(rootURL: context.store.rootURL)
        let fixture = document
        try fileStore.update(context.room) { value in value = fixture; return ((), true) }
        let bytes = try Data(contentsOf: roomURL)
        XCTAssertEqual(bytes.count, limit)
        XCTAssertThrowsError(try fileStore.update(context.room) { value in
            value.activity[499].payload = .object(["text": .string(String(repeating: "x", count: 15_001))])
            return ((), true)
        }) { XCTAssertEqual(($0 as? ARCError)?.code, .limitExceeded) }
        XCTAssertEqual(try Data(contentsOf: roomURL), bytes)
        for participant in [context.first, context.second] {
            _ = try context.store.participantRetire(room: context.room, participant: participant.id, operationID: UUID())
        }
        XCTAssertTrue(try context.store.diagnose(room: context.room).valid)
        _ = try context.store.roomDelete(room: context.room)
        XCTAssertFalse(FileManager.default.fileExists(atPath: roomURL.path))
    }

    func testDutyExpiryTickPersistsClockAcrossRollbackAndRestart() throws {
        let context = try qualifiedPair()
        let before = try context.store.activityRead(room: context.room)
        context.clock.advance(seconds: 180)
        let expired = try context.store.roomTick(room: context.room)
        context.clock.advance(seconds: -180)
        let restarted = ARCStore(rootURL: context.store.rootURL,
            clock: ARCClock { context.clock.now() }, knowledgeSHA256: digest)
        let opened = try restarted.roomOpen(room: context.room)
        XCTAssertEqual(opened.room.logicalUs, expired.room.logicalUs)
        XCTAssertTrue(opened.participants.allSatisfy { $0.duty == .off })
        XCTAssertFalse(opened.producer.live)
        XCTAssertEqual(try restarted.activityRead(room: context.room).events.count, before.events.count)
        let tick = try restarted.roomTick(room: context.room)
        XCTAssertEqual(tick.room.revision, expired.room.revision)
        XCTAssertThrowsError(try restarted.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .message(to: context.second.id, text: "Expired")))
    }

    func testLegacyFullRoomRecoveryRechecksDutyWorkingAndClockBeforeDeletion() throws {
        let context = try qualifiedPair()
        _ = try context.store.act(room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .message(to: context.second.id, text: "Seed"))
        for participant in [context.first, context.second] {
            _ = try context.store.participantRetire(room: context.room,
                participant: participant.id, operationID: UUID())
        }
        let remaining = try context.store.participantInvite(room: context.room,
            name: "Remaining", operationID: UUID()).participant.id
        let url = try context.store.roomFileURL(room: context.room)
        var document = try ARCRoomCodec.decode(Data(contentsOf: url), expectedID: context.room)
        let messageIndex = try XCTUnwrap(document.activity.firstIndex { $0.kind == "MESSAGE" })
        let template = document.activity[messageIndex]
        let copies = (0..<500).map { _ -> ARCEventRecord in
            var event = template
            event.operationId = UUID().uuidString.lowercased()
            return event
        }
        document.activity.insert(contentsOf: copies, at: messageIndex + 1)
        for index in document.activity.indices { document.activity[index].sequence = Int64(index + 1) }
        document.room.nextSequence = Int64(document.activity.count + 1)

        func writeFull(_ fixture: ARCRoomDocument) throws {
            var fixture = fixture
            let messages = fixture.activity.indices.filter { fixture.activity[$0].kind == "MESSAGE" }
            for index in messages {
                fixture.activity[index].payload = .object(["text": .string(String(repeating: "x", count: 15_000))])
            }
            var available = ARCConstants.maximumRoomBytes - (try ARCRoomCodec.encode(fixture)).count
            XCTAssertGreaterThanOrEqual(available, 0)
            for index in messages {
                let extra = min(1_384, available)
                fixture.activity[index].payload = .object(["text": .string(String(repeating: "x", count: 15_000 + extra))])
                available -= extra
            }
            XCTAssertEqual(available, 0)
            let data = try ARCRoomCodec.encode(fixture)
            XCTAssertEqual(data.count, ARCConstants.maximumRoomBytes)
            try data.write(to: url)
        }

        try writeFull(document)
        XCTAssertTrue(try context.store.diagnose(room: context.room).valid)
        XCTAssertThrowsError(try context.store.participantRetire(room: context.room,
            participant: remaining, operationID: UUID())) {
            XCTAssertEqual(($0 as? ARCError)?.code, .limitExceeded)
        }
        XCTAssertTrue(try context.store.roomOpen(room: context.room).canDeleteWithoutRetirement)

        // A stale UI authorization must not permit deletion after an AI becomes
        // available. These synthetic revisions are admitted by the real codec.
        let index = try XCTUnwrap(document.participants.firstIndex { $0.id == remaining })
        document.participants[index].phase = .qualifying
        document.participants[index].qualification = ARCQualificationRecord(
            challenge: String(repeating: "a", count: 32),
            startedLogicalUs: document.room.lastClockLogicalUs,
            firstPollLogicalUs: document.room.lastClockLogicalUs, answerLogicalUs: nil)
        try writeFull(document)
        XCTAssertThrowsError(try context.store.roomDelete(room: context.room))
        document.participants[index].phase = .qualified
        document.participants[index].qualification = nil
        document.participants[index].lastPollLogicalUs = document.room.lastClockLogicalUs
        try writeFull(document)
        XCTAssertThrowsError(try context.store.roomDelete(room: context.room)) {
            XCTAssertEqual(($0 as? ARCError)?.code, .wrongState)
        }
        document.participants[index].workingUntilLogicalUs = document.room.lastClockLogicalUs + 600_000_000
        try writeFull(document)
        context.clock.advance(seconds: 300)
        XCTAssertThrowsError(try context.store.roomDelete(room: context.room))
        let badClock = ARCStore(rootURL: context.store.rootURL,
            clock: ARCClock { throw TestClockFailure.unavailable }, knowledgeSHA256: digest)
        XCTAssertThrowsError(try badClock.roomDelete(room: context.room))
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        context.clock.advance(seconds: 300)
        XCTAssertTrue(try context.store.roomDelete(room: context.room).deleted)
        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
    }

    func testInactiveRoomWithSpaceStillRequiresRetirementBeforeDeletion() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(displayName: "Not full", operationID: UUID()).room.id
        let participant = try setup.store.participantInvite(room: room, name: "Waiting", operationID: UUID()).participant
        XCTAssertFalse(try setup.store.roomOpen(room: room).canDeleteWithoutRetirement)
        XCTAssertThrowsError(try setup.store.roomDelete(room: room)) {
            XCTAssertEqual(($0 as? ARCError)?.code, .wrongState)
        }
        _ = try setup.store.participantRetire(room: room, participant: participant.id, operationID: UUID())
        XCTAssertTrue(try setup.store.roomDelete(room: room).deleted)
    }

    func testKnowledgeRejectsFIFOWithoutWaitingForAWriter() throws {
        let root = newRoot()
        let current = root.appendingPathComponent("current")
        try FileManager.default.createDirectory(at: current, withIntermediateDirectories: true)
        let container = current.appendingPathComponent("ARC_AI.arc-kb")
        let digestURL = current.appendingPathComponent("ARC_AI.sha256")
        try Data((digest + "\n").utf8).write(to: digestURL)
        XCTAssertEqual(mkfifo(container.path, 0o600), 0)
        let started = Date()
        XCTAssertThrowsError(try ARCKnowledgeFile.openDefault(rootURL: root)) {
            XCTAssertEqual(($0 as? ARCError)?.code, .knowledgeUnavailable)
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 1)
        try FileManager.default.removeItem(at: container)
        try Data("invalid".utf8).write(to: container)
        try FileManager.default.removeItem(at: digestURL)
        XCTAssertEqual(mkfifo(digestURL.path, 0o600), 0)
        XCTAssertThrowsError(try ARCKnowledgeFile.openDefault(rootURL: root))
    }

    func testVisualEvidenceRequiresCanonicalTimestamp() throws {
        let valid: ARCJSONValue = .object([
            "artifact": .string("Rendered PDF"),
            "defects": .array([]),
            "inspected_at": .string("2026-08-17T14:35:00.000000Z"),
            "inspection": .string("Rendered every page"),
            "result": .string("PASS"),
            "surfaces": .array([.string("Page 1")]),
        ])
        XCTAssertNoThrow(try ARCEvidence.validate(
            valid, state: .complete, mode: .visual
        ))

        let invalid: ARCJSONValue = .object([
            "artifact": .string("Rendered PDF"),
            "defects": .array([]),
            "inspected_at": .string("yesterday"),
            "inspection": .string("Rendered every page"),
            "result": .string("PASS"),
            "surfaces": .array([.string("Page 1")]),
        ])
        XCTAssertThrowsError(try ARCEvidence.validate(
            invalid, state: .complete, mode: .visual
        ))
    }

    func testBespokeCanonicalWriterPreservesVersionOneRoomBytes() throws {
        let setup = try makeStore()
        let created = try setup.store.roomCreate(
            displayName: "Canonical room", operationID: UUID()
        )
        let roomURL = try setup.store.roomFileURL(room: created.room.id)
        let current = try Data(contentsOf: roomURL)
        let document = try ARCRoomCodec.decode(current, expectedID: created.room.id)

        let legacy = JSONEncoder()
        legacy.keyEncodingStrategy = .convertToSnakeCase
        legacy.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        var expected = try legacy.encode(document)
        expected.append(0x0A)
        XCTAssertEqual(current, expected)
    }

    func testMissingRoomOperationsDoNotCreateALockFile() throws {
        let setup = try makeStore()
        let missing = "room-012345abcdef"
        let lock = try setup.store.roomFileURL(room: missing).appendingPathExtension("lock")

        XCTAssertFalse(try setup.store.diagnose(room: missing).valid)
        XCTAssertThrowsError(try setup.store.poll(
            room: missing,
            participant: "ai-012345abcdef",
            binding: "00000000-0000-4000-8000-000000000000"
        ))
        XCTAssertThrowsError(try setup.store.act(
            room: missing,
            participant: "ai-012345abcdef",
            binding: "00000000-0000-4000-8000-000000000000",
            operation: "00000000-0000-4000-8000-000000000000",
            request: .message(to: "ai-012345abcdef", text: "No room")
        ))
        XCTAssertFalse(FileManager.default.fileExists(atPath: lock.path))
    }

    func testMachineResultsEncodeRequiredNullableFieldsAsNull() throws {
        let machine = JSONEncoder()
        machine.keyEncodingStrategy = .convertToSnakeCase

        let diagnostic = ARCDiagnosticResult(valid: true, failure: nil, context: [])
        let diagnosticData = try machine.encode(diagnostic)
        let diagnosticObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: diagnosticData) as? [String: Any]
        )
        XCTAssertTrue(diagnosticObject.keys.contains("failure"))
        XCTAssertTrue(diagnosticObject["failure"] is NSNull)

        let context = try qualifiedPair()
        let result = try context.store.poll(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, after: 0
        )
        let pollData = try machine.encode(result)
        let pollObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: pollData) as? [String: Any]
        )
        XCTAssertTrue(pollObject.keys.contains("qualification"))
        XCTAssertTrue(pollObject["qualification"] is NSNull)

        let producer = try XCTUnwrap(pollObject["producer"] as? [String: Any])
        XCTAssertEqual(Set(producer.keys), ["id", "name", "generation", "live"])
        let noProducer = try machine.encode(ARCProducerView(
            id: nil, name: nil, generation: 0, live: false
        ))
        let noProducerObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: noProducer) as? [String: Any]
        )
        XCTAssertTrue(noProducerObject["id"] is NSNull)
        XCTAssertTrue(noProducerObject["name"] is NSNull)

        let roster = try XCTUnwrap(pollObject["roster"] as? [[String: Any]])
        let participant = try XCTUnwrap(roster.first)
        XCTAssertEqual(Set(participant.keys), [
            "id", "name", "phase", "duty", "is_producer",
            "binding_generation", "schedule", "last_check_in",
        ])
        XCTAssertNil(participant["binding"])

        let bindingSentinel = "deadbeef-0000-4000-8000-000000000000"
        let neverPolled = ARCParticipantView(
            id: "ai-012345abcdef", name: "Never Polled", phase: .invited,
            duty: .off, isProducer: false, binding: bindingSentinel,
            bindingGeneration: 1,
            schedule: ARCScheduleView(
                kind: .none, status: .none,
                nextRequestLogicalUs: nil, deadlineLogicalUs: nil
            ),
            lastCheckIn: nil
        )
        let neverPolledData = try machine.encode(neverPolled)
        let neverPolledObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: neverPolledData) as? [String: Any]
        )
        XCTAssertTrue(neverPolledObject["last_check_in"] is NSNull)
        XCTAssertNil(neverPolledObject["binding"])
        XCTAssertFalse(String(decoding: neverPolledData, as: UTF8.self).contains(
            bindingSentinel
        ))

        let schedule = try XCTUnwrap(participant["schedule"] as? [String: Any])
        XCTAssertEqual(Set(schedule.keys), [
            "kind", "status", "next_request_logical_us", "deadline_logical_us",
        ])
        let emptySchedule = try machine.encode(ARCScheduleView(
            kind: .none, status: .none,
            nextRequestLogicalUs: nil, deadlineLogicalUs: nil
        ))
        let emptyScheduleObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: emptySchedule) as? [String: Any]
        )
        XCTAssertTrue(emptyScheduleObject["next_request_logical_us"] is NSNull)
        XCTAssertTrue(emptyScheduleObject["deadline_logical_us"] is NSNull)

        let waitingQualification = try machine.encode(ARCQualificationView(
            challenge: String(repeating: "a", count: 32),
            earliestCompletionLogicalUs: nil, deadlineLogicalUs: nil
        ))
        let waitingQualificationObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: waitingQualification) as? [String: Any]
        )
        XCTAssertTrue(
            waitingQualificationObject["earliest_completion_logical_us"] is NSNull
        )
        XCTAssertTrue(waitingQualificationObject["deadline_logical_us"] is NSNull)

        let event = ARCEventView(
            sequence: 1, at: "2026-08-18T00:00:00.000000Z", logicalUs: 0,
            kind: "ROOM_CREATED", actor: "administrator", recipient: nil,
            subject: nil, payload: .object([:]),
            operationId: "00000000-0000-4000-8000-000000000000",
            knowledgeSha256: digest
        )
        let eventData = try machine.encode(event)
        let eventObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: eventData) as? [String: Any]
        )
        XCTAssertEqual(Set(eventObject.keys), [
            "sequence", "at", "logical_us", "kind", "actor", "recipient",
            "subject", "payload", "operation_id", "knowledge_sha256",
        ])
        XCTAssertTrue(eventObject["recipient"] is NSNull)
        XCTAssertTrue(eventObject["subject"] is NSNull)

        let resultData = try machine.encode(ARCActResult(
            eventSequences: [], roomRevision: 1, participant: nil, work: nil,
            nextOperation: "00000000-0000-4000-8000-000000000000"
        ))
        let resultObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: resultData) as? [String: Any]
        )
        XCTAssertTrue(resultObject["participant"] is NSNull)
        XCTAssertTrue(resultObject["work"] is NSNull)
    }

    func testTwoQualifiedAIsMakeRoomActiveAndFirstIsProducer() throws {
        let context = try qualifiedPair()
        let opened = try context.store.roomOpen(room: context.room)

        XCTAssertEqual(opened.participants.count, 2)
        XCTAssertEqual(opened.room.status, .active)
        XCTAssertEqual(opened.producer.id, context.first.id)
        XCTAssertTrue(opened.producer.live)
        XCTAssertTrue(opened.participants.allSatisfy { $0.duty == .on })
    }

    func testActTokenRetriesOnceWithoutDuplicateMessage() throws {
        var context = try qualifiedPair()
        let request = ARCActionRequest.message(to: context.second.id, text: "Ready.")
        let first = try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: request
        )
        let replay = try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: request
        )

        XCTAssertEqual(first, replay)
        let activity = try context.store.activityRead(room: context.room)
        XCTAssertEqual(activity.events.filter { $0.kind == "MESSAGE" }.count, 1)

        XCTAssertThrowsError(try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .message(to: context.second.id, text: "Changed.")
        )) { error in
            XCTAssertEqual((error as? ARCError)?.code, .operationConflict)
        }
        context.first.operation = first.nextOperation
    }

    func testRoutineQualifiedPollChangesFactsButAddsNoActivity() throws {
        let context = try qualifiedPair()
        let before = try context.store.activityRead(room: context.room).events.count
        context.clock.advance(seconds: 10)

        let poll = try context.store.poll(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, after: 0
        )

        let after = try context.store.activityRead(room: context.room).events.count
        XCTAssertEqual(after, before)
        XCTAssertEqual(poll.operation, context.first.operation)
    }

    func testAIResponsesNeverDiscloseParticipantBindings() throws {
        let context = try qualifiedPair()
        let poll = try context.store.poll(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, after: 0
        )
        XCTAssertNil(poll.participant.binding)
        XCTAssertTrue(poll.roster.allSatisfy { $0.binding == nil })
        XCTAssertFalse(poll.earlierActivityUnavailable)
        let guide = try context.store.guide(
            room: context.room, participant: context.first.id,
            binding: context.first.binding
        )
        XCTAssertNil(guide.participant.binding)

        // The Administrator's direct room view retains the references needed
        // for Copy Instructions Again; it is not returned through the AI lane.
        XCTAssertTrue(try context.store.roomOpen(room: context.room).participants
            .allSatisfy { $0.binding != nil })
    }

    func testPollResponseContainsNoUnattributedUUID() throws {
        let context = try qualifiedPair()
        let poll = try context.store.poll(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, after: 0
        )
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = try encoder.encode(poll)
        let found = try lowerUUIDs(in: data)
        let allowed = Set([poll.operation] + poll.events.map(\.operationId))
        XCTAssertEqual(found, allowed)
        XCTAssertTrue(found.isDisjoint(with: [
            context.first.binding, context.second.binding,
        ]))

        let guidePositiveControl = Data(
            "arc guide --binding \(context.first.binding)".utf8
        )
        XCTAssertTrue(
            try lowerUUIDs(in: guidePositiveControl).contains(context.first.binding)
        )
    }

    func testLaterQualificationGetsAFullWindowFromItsOwnFirstPoll() throws {
        for delay in [0, 20, 39, 41, 79, 81] {
            let setup = try makeStore()
            let room = try setup.store.roomCreate(
                displayName: "Delay \(delay)", operationID: UUID()
            ).room.id
            var first = try qualifyFirst(
                store: setup.store, clock: setup.clock, room: room, name: "Producer"
            )
            let invitation = try setup.store.participantInvite(
                room: room, name: "Later", operationID: UUID()
            )
            _ = try setup.store.poll(
                room: room, participant: invitation.participant.id,
                binding: invitation.instructions.bindingReference, after: 0
            )
            let started = try setup.store.act(
                room: room, participant: first.id, binding: first.binding,
                operation: first.operation,
                request: .qualificationStart(
                    participant: invitation.participant.id, producerGeneration: 1
                )
            )
            first.operation = started.nextOperation
            let high = try XCTUnwrap(
                try setup.store.activityRead(room: room).events.map(\.sequence).max()
            )
            setup.clock.advance(seconds: TimeInterval(delay))
            let firstPoll = try setup.store.poll(
                room: room, participant: invitation.participant.id,
                binding: invitation.instructions.bindingReference, after: high
            )
            XCTAssertTrue(firstPoll.events.isEmpty, "delay \(delay)")
            let qualification = try XCTUnwrap(firstPoll.qualification, "delay \(delay)")
            XCTAssertEqual(firstPoll.schedule.status, .ok, "delay \(delay)")
            XCTAssertEqual(
                firstPoll.schedule.nextRequestLogicalUs,
                qualification.earliestCompletionLogicalUs,
                "delay \(delay)"
            )
            XCTAssertEqual(
                qualification.earliestCompletionLogicalUs,
                qualification.deadlineLogicalUs! - 80_000_000,
                "delay \(delay)"
            )
            let answer = try setup.store.act(
                room: room, participant: invitation.participant.id,
                binding: invitation.instructions.bindingReference,
                operation: firstPoll.operation,
                request: .qualificationAnswer(answer: qualification.challenge)
            )
            setup.clock.advance(seconds: 40)
            let passed = try setup.store.poll(
                room: room, participant: invitation.participant.id,
                binding: invitation.instructions.bindingReference,
                after: firstPoll.nextAfter
            )
            XCTAssertEqual(passed.participant.phase, .qualified, "delay \(delay)")
            XCTAssertEqual(answer.nextOperation, passed.operation, "delay \(delay)")
        }
    }

    func testQualificationAndDutyClosedOpenMicrosecondEdges() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(
            displayName: "Exact Edges", operationID: UUID()
        ).room.id
        let invitation = try setup.store.participantInvite(
            room: room, name: "Boundary AI", operationID: UUID()
        )
        let binding = invitation.instructions.bindingReference
        let firstPoll = try setup.store.poll(
            room: room, participant: invitation.participant.id,
            binding: binding, after: 0
        )
        let answer = try setup.store.act(
            room: room, participant: invitation.participant.id,
            binding: binding, operation: firstPoll.operation,
            request: .qualificationAnswer(
                answer: try XCTUnwrap(firstPoll.qualification?.challenge)
            )
        )

        setup.clock.advance(microseconds: 39_999_999)
        let justBefore = try setup.store.poll(
            room: room, participant: invitation.participant.id,
            binding: binding, after: firstPoll.nextAfter
        )
        XCTAssertEqual(justBefore.participant.phase, .qualifying)

        setup.clock.advance(microseconds: 1)
        let atOpening = try setup.store.poll(
            room: room, participant: invitation.participant.id,
            binding: binding, after: firstPoll.nextAfter
        )
        XCTAssertEqual(atOpening.participant.phase, .qualified)
        XCTAssertEqual(atOpening.operation, answer.nextOperation)

        setup.clock.advance(microseconds: 180_000_000)
        let expiredDuty = try setup.store.roomOpen(room: room)
        XCTAssertEqual(expiredDuty.participants.first?.duty, .off)
        let returned = try setup.store.poll(
            room: room, participant: invitation.participant.id,
            binding: binding, after: atOpening.nextAfter
        )
        XCTAssertEqual(returned.participant.duty, .on)
        XCTAssertTrue(returned.events.contains { $0.kind == "AI_RETURNED_ON_DUTY" })
        XCTAssertEqual(returned.operation, answer.nextOperation)

        let expirySetup = try makeStore()
        let expiryRoom = try expirySetup.store.roomCreate(
            displayName: "Exact Expiry", operationID: UUID()
        ).room.id
        let expiryInvitation = try expirySetup.store.participantInvite(
            room: expiryRoom, name: "Deadline AI", operationID: UUID()
        )
        let expiryBinding = expiryInvitation.instructions.bindingReference
        let expiryPoll = try expirySetup.store.poll(
            room: expiryRoom, participant: expiryInvitation.participant.id,
            binding: expiryBinding, after: 0
        )
        _ = try expirySetup.store.act(
            room: expiryRoom, participant: expiryInvitation.participant.id,
            binding: expiryBinding, operation: expiryPoll.operation,
            request: .qualificationAnswer(
                answer: try XCTUnwrap(expiryPoll.qualification?.challenge)
            )
        )
        expirySetup.clock.advance(microseconds: 120_000_000)
        let atDeadline = try expirySetup.store.poll(
            room: expiryRoom, participant: expiryInvitation.participant.id,
            binding: expiryBinding, after: expiryPoll.nextAfter
        )
        XCTAssertEqual(atDeadline.participant.phase, .failed)
        XCTAssertTrue(atDeadline.events.contains {
            $0.kind == "QUALIFICATION_FAILED"
        })
    }

    func testCandidateFallsBackWhenProducerIsOffDutyButAnotherAIIsOnDuty() throws {
        let context = try qualifiedPair()
        context.clock.advance(seconds: 170)
        _ = try context.store.poll(
            room: context.room, participant: context.second.id,
            binding: context.second.binding, after: 0
        )
        context.clock.advance(seconds: 11)
        let invitation = try context.store.participantInvite(
            room: context.room, name: "Fallback", operationID: UUID()
        )
        let poll = try context.store.poll(
            room: context.room, participant: invitation.participant.id,
            binding: invitation.instructions.bindingReference, after: 0
        )
        XCTAssertEqual(poll.participant.phase, .qualifying)
        XCTAssertNotNil(poll.qualification?.challenge)
        XCTAssertNotNil(poll.qualification?.deadlineLogicalUs)
    }

    func testProducerPollRetainsRecentCompletedWork() throws {
        var context = try qualifiedPair()
        let assigned = try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .workAssign(
                owner: context.second.id, scope: "Summarize the test.",
                evidenceMode: .text, producerGeneration: 1
            )
        )
        context.first.operation = assigned.nextOperation
        let work = try XCTUnwrap(assigned.work)
        let completed = try context.store.act(
            room: context.room, participant: context.second.id,
            binding: context.second.binding, operation: context.second.operation,
            request: .workUpdate(
                work: work.id, revision: work.revision, state: .complete,
                evidence: .object([
                    "references": .array([]),
                    "result": .string("Complete."),
                ])
            )
        )
        XCTAssertEqual(completed.work?.state, .complete)
        let producerPoll = try context.store.poll(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, after: 0
        )
        XCTAssertEqual(producerPoll.work.first(where: { $0.id == work.id })?.state, .complete)
    }

    func testFailedActionCannotLeakPartialWorkWhenQualificationExpiryCommits() throws {
        var context = try qualifiedPair()
        let assignment = try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .workAssign(
                owner: context.first.id, scope: "Check the room.", evidenceMode: .text,
                producerGeneration: 1
            )
        )
        context.first.operation = assignment.nextOperation
        let work = try XCTUnwrap(assignment.work)

        let candidate = try context.store.participantInvite(
            room: context.room, name: "Third", operationID: UUID()
        )
        let joined = try context.store.poll(
            room: context.room, participant: candidate.participant.id,
            binding: candidate.instructions.bindingReference, after: 0
        )
        XCTAssertEqual(joined.participant.phase, .waitingForProducer)
        let start = try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .qualificationStart(
                participant: candidate.participant.id, producerGeneration: 1
            )
        )
        context.first.operation = start.nextOperation
        _ = try context.store.poll(
            room: context.room, participant: candidate.participant.id,
            binding: candidate.instructions.bindingReference, after: 0
        )
        context.clock.advance(seconds: 120)

        let failureClock = context.clock
        let failing = ARCStore(
            testRootURL: context.store.rootURL,
            clock: ARCClock { failureClock.now() },
            knowledgeSHA256: digest,
            maximumEventBytes: 100
        )
        XCTAssertThrowsError(try failing.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .workUpdate(
                work: work.id, revision: 1, state: .active,
                evidence: .object(["note": .string(String(repeating: "x", count: 200))])
            )
        )) { error in
            XCTAssertEqual((error as? ARCError)?.code, .limitExceeded)
        }

        let opened = try context.store.roomOpen(room: context.room)
        XCTAssertEqual(opened.work.first { $0.id == work.id }?.state, .open)
        XCTAssertEqual(
            opened.participants.first { $0.id == candidate.participant.id }?.phase,
            .failed
        )
    }

    func testStrictActionJSONRejectsDuplicatesAndDeepNesting() throws {
        XCTAssertThrowsError(try ARCActionJSON.decode(Data(
            #"{"type":"qualification.answer","answer":"a","answer":"b"}"#.utf8
        ))) { error in
            XCTAssertEqual((error as? ARCError)?.code, .invalidArgument)
        }

        let nested = String(repeating: "[", count: 33)
            + "0" + String(repeating: "]", count: 33)
        XCTAssertThrowsError(try ARCActionJSON.decode(Data(
            "{\"type\":\"work.update\",\"work\":\"work-012345abcdef\","
                .appending("\"revision\":1,\"state\":\"ACTIVE\",\"evidence\":")
                .appending(nested).appending("}").utf8
        ))) { error in
            XCTAssertEqual((error as? ARCError)?.code, .invalidArgument)
        }
    }

    func testCanonicalRoomRejectsUnknownField() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(
            displayName: "Readable Room", operationID: UUID()
        ).room.id
        let url = try setup.store.roomFileURL(room: room)
        let original = try String(contentsOf: url, encoding: .utf8)
        let changed = original.replacingOccurrences(
            of: "{\n", with: "{\n  \"unknown\" : true,\n", options: [], range: original.startIndex..<original.index(original.startIndex, offsetBy: 2)
        )
        try Data(changed.utf8).write(to: url)

        let diagnosis = try setup.store.diagnose(room: room)
        XCTAssertFalse(diagnosis.valid)
        XCTAssertEqual(diagnosis.failure?.check, "ROOM_JSON")
    }

    func testRoomDeletionIsPermanentAndRequiresEveryAIToBeRetired() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(
            displayName: "Finished Room", operationID: UUID()
        ).room.id
        let roomURL = try setup.store.roomFileURL(room: room)
        let invited = try setup.store.participantInvite(
            room: room, name: "Finisher", operationID: UUID()
        )
        XCTAssertThrowsError(try setup.store.roomDelete(room: room)) { error in
            XCTAssertEqual((error as? ARCError)?.code, .wrongState)
        }
        _ = try setup.store.participantRetire(
            room: room, participant: invited.participant.id, operationID: UUID()
        )

        XCTAssertTrue(try setup.store.roomDelete(room: room).deleted)

        XCTAssertFalse(FileManager.default.fileExists(atPath: roomURL.path))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: roomURL.appendingPathExtension("lock").path
        ))
    }

    func testCanonicalValidationRejectsMalformedDurableRelationships() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(
            displayName: "Validation Room", operationID: UUID()
        ).room.id
        let files = try ARCFileStore(rootURL: setup.store.rootURL)
        let original = try files.read(room) { $0 }

        var badAdmin = original
        badAdmin.room.lastAdminOperation?.id = "not-a-uuid"
        XCTAssertThrowsError(try ARCRoomCodec.encode(badAdmin))

        var badTime = original
        badTime.room.updatedAt = "1970-01-01T00:00:00.000000Z"
        XCTAssertThrowsError(try ARCRoomCodec.encode(badTime))

        let invitation = try setup.store.participantInvite(
            room: room, name: "Candidate", operationID: UUID()
        )
        _ = try setup.store.poll(
            room: room, participant: invitation.participant.id,
            binding: invitation.instructions.bindingReference, after: 0
        )
        var badQualification = try files.read(room) { $0 }
        let candidateIndex = try XCTUnwrap(badQualification.participants.firstIndex {
            $0.id == invitation.participant.id
        })
        let started = try XCTUnwrap(
            badQualification.participants[candidateIndex].qualification?.startedLogicalUs
        )
        badQualification.participants[candidateIndex].qualification?.firstPollLogicalUs
            = started - 1
        XCTAssertThrowsError(try ARCRoomCodec.encode(badQualification))

        var pair = try qualifiedPair()
        let message = try pair.store.act(
            room: pair.room, participant: pair.first.id,
            binding: pair.first.binding, operation: pair.first.operation,
            request: .message(to: pair.second.id, text: "Validation event")
        )
        pair.first.operation = message.nextOperation
        let pairFiles = try ARCFileStore(rootURL: pair.store.rootURL)
        var badOperation = try pairFiles.read(pair.room) { $0 }
        let callerIndex = try XCTUnwrap(badOperation.participants.firstIndex {
            $0.id == pair.first.id
        })
        badOperation.participants[callerIndex].lastOperation?.eventSequences = [0]
        XCTAssertThrowsError(try ARCRoomCodec.encode(badOperation))

        var badPayload = try pairFiles.read(pair.room) { $0 }
        badPayload.activity[badPayload.activity.count - 1].payload = .object([
            "text": .string("Validation event"),
            "hidden": .boolean(true),
        ])
        XCTAssertThrowsError(try ARCRoomCodec.encode(badPayload))
    }

    func testRoomSupports64CurrentAIsAndRetiredSlotCanBeReused() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(
            displayName: "Large Team", operationID: UUID()
        ).room.id
        var firstID = ""
        for number in 1...64 {
            let invited = try setup.store.participantInvite(
                room: room, name: "AI \(number)", operationID: UUID()
            )
            if number == 1 { firstID = invited.participant.id }
        }
        XCTAssertEqual(try setup.store.roomOpen(room: room).participants.count, 64)
        XCTAssertThrowsError(try setup.store.participantInvite(
            room: room, name: "AI 65", operationID: UUID()
        )) { error in
            XCTAssertEqual((error as? ARCError)?.code, .limitExceeded)
        }

        _ = try setup.store.participantRetire(
            room: room, participant: firstID, operationID: UUID()
        )
        _ = try setup.store.participantInvite(
            room: room, name: "AI 65", operationID: UUID()
        )
        let opened = try setup.store.roomOpen(room: room)
        XCTAssertEqual(opened.participants.count, 64)
        XCTAssertFalse(opened.participants.contains { $0.id == firstID })
        XCTAssertTrue(opened.participants.contains { $0.name == "AI 65" })
    }

    func testActivityKeepsCompleteHistoryAndReportsNoGap() throws {
        let context = try qualifiedPair()
        let fileStore = try ARCFileStore(rootURL: context.store.rootURL)
        try fileStore.update(context.room) { document in
            let logical = document.room.lastClockLogicalUs
            document.activity = (1...2_000).map { sequence in
                ARCEventRecord(
                    sequence: Int64(sequence),
                    at: ARCTime.timestamp(logical),
                    logicalUs: logical,
                    kind: "MESSAGE",
                    actor: context.first.id,
                    recipient: context.second.id,
                    subject: nil,
                    payload: .object(["text": .string("x")]),
                    operationId: UUID().uuidString.lowercased(),
                    knowledgeSha256: digest
                )
            }
            document.room.nextSequence = 2_001
            return ((), true)
        }

        let poll = try context.store.poll(
            room: context.room, participant: context.second.id,
            binding: context.second.binding, after: 0
        )
        XCTAssertEqual(poll.events.count, 50)
        let activity = try context.store.activityRead(room: context.room)
        var before = activity.nextBefore
        var finalPage = activity
        while let value = before {
            finalPage = try context.store.activityRead(
                room: context.room, beforeSequence: value
            )
            before = finalPage.nextBefore
        }
        XCTAssertEqual(finalPage.events.last?.sequence, 1)
    }

    func testLinkedRootIsRefused() throws {
        let target = newRoot()
        try FileManager.default.createDirectory(
            at: target, withIntermediateDirectories: true
        )
        let link = URL(fileURLWithPath: "/private/tmp/arc-core-link-\(UUID().uuidString)")
        roots.append(link)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)
        let store = ARCStore(rootURL: link, knowledgeSHA256: digest)

        XCTAssertThrowsError(try store.roomList()) { error in
            XCTAssertEqual((error as? ARCError)?.code, .ioFailure)
        }
    }

    func testNamesUseNFCGraphemeAndByteBounds() throws {
        let setup = try makeStore()
        let composed = try setup.store.roomCreate(
            displayName: "  Cafe\u{301}  ", operationID: UUID()
        )
        XCTAssertEqual(composed.room.name, "Café")
        XCTAssertThrowsError(try setup.store.roomCreate(
            displayName: String(repeating: "é", count: 81), operationID: UUID()
        ))
        XCTAssertThrowsError(try setup.store.roomCreate(
            displayName: String(repeating: "👨‍👩‍👧‍👦", count: 80), operationID: UUID()
        ))
        XCTAssertThrowsError(try setup.store.roomCreate(
            displayName: "Team/Room", operationID: UUID()
        )) { error in
            XCTAssertEqual((error as? ARCError)?.code, .invalidArgument)
        }

        let room = composed.room.id
        XCTAssertThrowsError(try setup.store.participantInvite(
            room: room, name: "AI/One", operationID: UUID()
        )) { error in
            XCTAssertEqual((error as? ARCError)?.code, .invalidArgument)
        }
        _ = try setup.store.participantInvite(
            room: room, name: "Safe AI", operationID: UUID()
        )

        let roomURL = try setup.store.roomFileURL(room: room)
        let original = try String(contentsOf: roomURL, encoding: .utf8)
        let malformedAI = original.replacingOccurrences(of: "Safe AI", with: "Bad/AI")
        try Data(malformedAI.utf8).write(to: roomURL)
        XCTAssertEqual(try setup.store.diagnose(room: room).failure?.check, "ROOM_JSON")

        try Data(original.utf8).write(to: roomURL)
        let malformed = original.replacingOccurrences(of: "Café", with: "Bad/Room")
        try Data(malformed.utf8).write(to: roomURL)
        let diagnosis = try setup.store.diagnose(room: room)
        XCTAssertFalse(diagnosis.valid)
        XCTAssertEqual(diagnosis.failure?.check, "ROOM_JSON")
    }

    func testDiagnoseReportsBoundedFactsAndStableFailureChecks() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(
            displayName: "Diagnostic Room", operationID: UUID()
        ).room.id
        let diagnosis = try setup.store.diagnose(room: room)
        XCTAssertTrue(diagnosis.valid)
        let labels = Set(diagnosis.context.map(\.label))
        XCTAssertTrue(labels.isSuperset(of: [
            "Room ID", "Lock", "Format", "Size", "Revision", "Participants",
            "Current work", "Retained work", "Activity", "Activity sequences",
            "Verified knowledge", "Latest Activity knowledge", "Clock",
        ]))

        let badKnowledge = ARCStore(
            rootURL: setup.store.rootURL, clock: ARCClock { setup.clock.now() },
            knowledgeSHA256: "bad"
        )
        XCTAssertEqual(
            try badKnowledge.diagnose(room: room).failure?.check, "KNOWLEDGE"
        )

        let badClock = ARCStore(
            rootURL: setup.store.rootURL,
            clock: ARCClock { throw TestClockFailure.unavailable },
            knowledgeSHA256: digest
        )
        XCTAssertEqual(try badClock.diagnose(room: room).failure?.check, "CLOCK")

        let lockURL = try setup.store.roomFileURL(room: room)
            .appendingPathExtension("lock")
        try FileManager.default.removeItem(at: lockURL)
        try FileManager.default.createSymbolicLink(
            at: lockURL, withDestinationURL: try setup.store.roomFileURL(room: room)
        )
        XCTAssertEqual(try setup.store.diagnose(room: room).failure?.check, "LOCK")
    }

    func testDiagnoseDistinguishesPathFormatAndUnsafeFile() throws {
        let setup = try makeStore()
        XCTAssertEqual(
            try setup.store.diagnose(room: "room-000000000000").failure?.check,
            "PATH"
        )

        let room = try setup.store.roomCreate(
            displayName: "Check Codes", operationID: UUID()
        ).room.id
        let roomURL = try setup.store.roomFileURL(room: room)
        let original = try String(contentsOf: roomURL, encoding: .utf8)
        let incompatible = original.replacingOccurrences(
            of: "arc.room/1", with: "arc.room/2"
        )
        try Data(incompatible.utf8).write(to: roomURL)
        XCTAssertEqual(try setup.store.diagnose(room: room).failure?.check, "FORMAT")

        try FileManager.default.removeItem(at: roomURL)
        let target = newRoot()
        try Data(original.utf8).write(to: target)
        try FileManager.default.createSymbolicLink(
            at: roomURL, withDestinationURL: target
        )
        XCTAssertEqual(try setup.store.diagnose(room: room).failure?.check, "IO")
    }

    func testAdministratorRecoveryControlsRemainAvailableWithoutClock() throws {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(
            displayName: "Recovery Room", operationID: UUID()
        ).room.id
        let first = try setup.store.participantInvite(
            room: room, name: "First", operationID: UUID()
        )
        let unavailable = ARCStore(
            rootURL: setup.store.rootURL,
            clock: ARCClock { throw TestClockFailure.unavailable },
            knowledgeSHA256: digest
        )

        _ = try unavailable.roomRename(
            room: room, displayName: "Renamed While Time Is Unavailable",
            operationID: UUID()
        )
        let second = try unavailable.participantInvite(
            room: room, name: "Second", operationID: UUID()
        )
        let replaced = try unavailable.participantReplaceInstructions(
            room: room, participant: first.participant.id, operationID: UUID()
        )
        _ = try unavailable.participantRetire(
            room: room, participant: second.participant.id, operationID: UUID()
        )

        let open = try unavailable.roomOpen(room: room)
        XCTAssertEqual(open.room.status, .timeUnavailable)
        XCTAssertEqual(open.room.name, "Renamed While Time Is Unavailable")
        XCTAssertEqual(
            open.participants.first { $0.id == first.participant.id }?.schedule.kind,
            ARCScheduleKind.none
        )
        XCTAssertEqual(
            open.participants.first { $0.id == first.participant.id }?.schedule.status,
            ARCScheduleStatus.none
        )
        XCTAssertEqual(
            open.participants.first { $0.id == second.participant.id }?.phase,
            .retired
        )
        XCTAssertEqual(
            open.participants.first { $0.id == second.participant.id }?.schedule.kind,
            ARCScheduleKind.none
        )
        XCTAssertEqual(
            open.participants.first { $0.id == second.participant.id }?.schedule.status,
            ARCScheduleStatus.none
        )
        let unverifiedKinds = Set(
            try unavailable.activityRead(room: room).events
                .filter { !$0.timeIsVerified }.map(\.kind)
        )
        XCTAssertTrue(unverifiedKinds.isSuperset(of: [
            "ROOM_RENAMED", "AI_INVITED", "INSTRUCTIONS_REPLACED", "AI_RETIRED",
        ]))
        XCTAssertThrowsError(try unavailable.poll(
            room: room, participant: first.participant.id,
            binding: replaced.instructions.bindingReference, after: 0
        )) { error in
            XCTAssertEqual((error as? ARCError)?.code, .clockUnavailable)
        }
    }

    func testCurrentWorkIsLimitedToFifty() throws {
        var context = try qualifiedPair()
        for number in 1...ARCConstants.maximumCurrentWorkItems {
            let result = try context.store.act(
                room: context.room, participant: context.first.id,
                binding: context.first.binding, operation: context.first.operation,
                request: .workAssign(
                    owner: context.first.id,
                    scope: number == 1 ? "Work 1\nwith detail" : "Work \(number)",
                    evidenceMode: .text, producerGeneration: 1
                )
            )
            context.first.operation = result.nextOperation
        }
        XCTAssertEqual(
            try context.store.roomOpen(room: context.room).work.count,
            ARCConstants.maximumCurrentWorkItems
        )
        XCTAssertThrowsError(try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .workAssign(
                owner: context.first.id, scope: "Work 51",
                evidenceMode: .text, producerGeneration: 1
            )
        )) { error in
            XCTAssertEqual((error as? ARCError)?.code, .limitExceeded)
        }
    }

    func testRetiredParticipantMayBePrunedWhileOpenWorkRemainsReassignable() throws {
        var context = try qualifiedPair()
        let assignment = try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .workAssign(
                owner: context.second.id, scope: "Reassign after retirement.",
                evidenceMode: .text, producerGeneration: 1
            )
        )
        context.first.operation = assignment.nextOperation
        let work = try XCTUnwrap(assignment.work)
        _ = try context.store.participantRetire(
            room: context.room, participant: context.second.id, operationID: UUID()
        )

        for number in 3...65 {
            _ = try context.store.participantInvite(
                room: context.room, name: "Replacement \(number)", operationID: UUID()
            )
        }
        XCTAssertFalse(try context.store.roomOpen(room: context.room).participants
            .contains { $0.id == context.second.id })

        let reassigned = try context.store.act(
            room: context.room, participant: context.first.id,
            binding: context.first.binding, operation: context.first.operation,
            request: .workReassign(
                work: work.id, revision: 1, owner: context.first.id,
                reason: "Previous owner retired.", producerGeneration: 1
            )
        )
        XCTAssertEqual(reassigned.work?.owner, context.first.id)
    }

    private func qualifiedPair() throws -> PairContext {
        let setup = try makeStore()
        let room = try setup.store.roomCreate(
            displayName: "Team Room", operationID: UUID()
        ).room.id
        var first = try qualifyFirst(
            store: setup.store, clock: setup.clock, room: room, name: "First"
        )
        let secondInvitation = try setup.store.participantInvite(
            room: room, name: "Second", operationID: UUID()
        )
        let secondBinding = secondInvitation.instructions.bindingReference
        let waiting = try setup.store.poll(
            room: room, participant: secondInvitation.participant.id,
            binding: secondBinding, after: 0
        )
        XCTAssertEqual(waiting.participant.phase, .waitingForProducer)
        let start = try setup.store.act(
            room: room, participant: first.id, binding: first.binding,
            operation: first.operation,
            request: .qualificationStart(
                participant: secondInvitation.participant.id,
                producerGeneration: 1
            )
        )
        first.operation = start.nextOperation
        let firstSecondPoll = try setup.store.poll(
            room: room, participant: secondInvitation.participant.id,
            binding: secondBinding, after: 0
        )
        let challenge = try challenge(in: firstSecondPoll.events)
        let answer = try setup.store.act(
            room: room, participant: secondInvitation.participant.id,
            binding: secondBinding, operation: firstSecondPoll.operation,
            request: .qualificationAnswer(answer: challenge)
        )
        setup.clock.advance(seconds: 40)
        let qualified = try setup.store.poll(
            room: room, participant: secondInvitation.participant.id,
            binding: secondBinding, after: firstSecondPoll.nextAfter
        )
        XCTAssertEqual(qualified.participant.phase, .qualified)
        let second = ParticipantHandle(
            id: secondInvitation.participant.id,
            binding: secondBinding,
            operation: answer.nextOperation
        )
        return PairContext(
            store: setup.store, clock: setup.clock, room: room,
            first: first, second: second
        )
    }

    private func qualifyFirst(
        store: ARCStore, clock: TestClock, room: String, name: String
    ) throws -> ParticipantHandle {
        let invitation = try store.participantInvite(
            room: room, name: name, operationID: UUID()
        )
        let binding = invitation.instructions.bindingReference
        let firstPoll = try store.poll(
            room: room, participant: invitation.participant.id,
            binding: binding, after: 0
        )
        let answer = try store.act(
            room: room, participant: invitation.participant.id,
            binding: binding, operation: firstPoll.operation,
            request: .qualificationAnswer(answer: try challenge(in: firstPoll.events))
        )
        clock.advance(seconds: 40)
        let qualified = try store.poll(
            room: room, participant: invitation.participant.id,
            binding: binding, after: firstPoll.nextAfter
        )
        XCTAssertEqual(qualified.participant.phase, .qualified)
        XCTAssertTrue(qualified.participant.isProducer)
        return ParticipantHandle(
            id: invitation.participant.id,
            binding: binding,
            operation: answer.nextOperation
        )
    }

    private func challenge(in events: [ARCEventView]) throws -> String {
        try XCTUnwrap(events.last(where: { $0.kind.contains("QUALIFICATION") })?
            .payload.objectValue?["challenge"]?.stringValue)
    }

    private func lowerUUIDs(in data: Data) throws -> Set<String> {
        let text = String(decoding: data, as: UTF8.self)
        let expression = try NSRegularExpression(
            pattern: #"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"#
        )
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return Set(expression.matches(in: text, range: range).compactMap {
            Range($0.range, in: text).map { String(text[$0]) }
        })
    }

    private func makeStore() throws -> (store: ARCStore, clock: TestClock) {
        let root = newRoot()
        let clock = TestClock(
            Date(timeIntervalSince1970: 1_800_000_000)
        )
        return (
            ARCStore(
                rootURL: root,
                clock: ARCClock { clock.now() },
                knowledgeSHA256: digest
            ),
            clock
        )
    }

    private func newRoot() -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/arc-core-\(UUID().uuidString)")
        roots.append(root)
        return root
    }
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Date

    init(_ value: Date) { self.value = value }

    func now() -> Date {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func advance(seconds: TimeInterval) {
        lock.lock()
        value = value.addingTimeInterval(seconds)
        lock.unlock()
    }

    func advance(microseconds: Int64) {
        advance(seconds: TimeInterval(microseconds) / 1_000_000)
    }
}

private enum TestClockFailure: Error {
    case unavailable
}

private struct ParticipantHandle {
    let id: String
    let binding: String
    var operation: String
}

private struct PairContext {
    let store: ARCStore
    let clock: TestClock
    let room: String
    var first: ParticipantHandle
    var second: ParticipantHandle
}
