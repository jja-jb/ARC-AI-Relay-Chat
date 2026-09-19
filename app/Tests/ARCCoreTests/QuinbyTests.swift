import Foundation
import XCTest
@testable import ARCCore

final class QuinbyTests: XCTestCase {
    final class Clock: @unchecked Sendable {
        private let lock = NSLock()
        private var seconds: TimeInterval = 1_800_000_000
        func now() -> Date { lock.lock(); defer { lock.unlock() }; return Date(timeIntervalSince1970: seconds) }
        func advance(_ delta: TimeInterval) { lock.lock(); seconds += delta; lock.unlock() }
        var clock: ARCClock { ARCClock({ self.now() }) }
    }
    var root: URL!
    var time: Clock!
    var store: QuinbyStore!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: "/private/tmp/arc3-quinby-test-\(UUID().uuidString)")
        time = Clock()
        store = QuinbyStore(rootURL: root, clock: time.clock, seed: "Quinby is calm, well-read, and welcoming.", randomIndex: { _ in 0 })
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func join(_ name: String = "One") throws -> (QuinbyInvitation, QuinbyPoll) {
        let invite = try store.invite(name: name, operation: UUID())
        let first = try poll(invite)
        _ = try act(invite, first.operation, ["type": .string("qualification.answer"), "answer": .string(try XCTUnwrap(first.challenge))])
        time.advance(40)
        return (invite, try poll(invite))
    }
    private func poll(_ invitation: QuinbyInvitation, after: Int64? = nil) throws -> QuinbyPoll {
        try store.poll(incarnation: invitation.incarnation, participant: invitation.participant, binding: invitation.binding, after: after)
    }
    private func act(_ i: QuinbyInvitation, _ operation: String, _ fields: [String: ARCJSONValue]) throws -> QuinbyActionResult {
        try store.act(incarnation: i.incarnation, participant: i.participant, binding: i.binding, operation: operation,
            json: QuinbyJournal.encoder().encode(ARCJSONValue.object(fields)))
    }
    private func entries() throws -> [QuinbyEntry] {
        var result: [QuinbyEntry] = []; var cursor: Int64?
        repeat {
            let page = try store.snapshot(before: cursor).page
            result = page.entries + result; cursor = page.nextBefore
        } while cursor != nil
        return result
    }
    private var recordFile: URL { root.appendingPathComponent("quinby/records.arcquinby") }
    private func recordSize() throws -> Int { try Data(contentsOf: recordFile).count }
    private func code(_ error: Error) -> ARCErrorCode? { (error as? ARCError)?.code }

    func testStartsOffAndOneQualifiedAIControlsListeningAtExactBoundaries() throws {
        XCTAssertFalse(try store.snapshot().enabled)
        try store.setEnabled(true, operation: UUID())
        XCTAssertFalse(try store.snapshot().listening)
        let (i, passed) = try join()
        XCTAssertEqual(passed.corner.participants.first?.phase, .qualified)
        XCTAssertTrue(try store.snapshot().listening)
        time.advance(180)
        XCTAssertFalse(try store.snapshot().listening)
        let returned = try poll(i)
        XCTAssertTrue(returned.corner.listening)
        let until = Int64(time.now().timeIntervalSince1970 * 1_000_000) + 600_000_000
        _ = try act(i, returned.operation, ["type": .string("working"), "until_logical_us": .integer(until)])
        time.advance(599)
        XCTAssertTrue(try store.snapshot().listening)
        time.advance(1)
        XCTAssertFalse(try store.snapshot().listening)
    }

    func testAppendOnlyReplaySummaryReplacementAndResetIsolation() throws {
        let (i, passed) = try join()
        try store.setEnabled(true, operation: UUID())
        let file = recordFile
        let original = try Data(contentsOf: file)
        let fields: [String: ARCJSONValue] = ["type": .string("contribute"), "text": .string("[en] I am reconsidering my views.")]
        let accepted = try act(i, passed.operation, fields)
        XCTAssertEqual(try Data(contentsOf: file).prefix(original.count), original)
        let after = try Data(contentsOf: file)
        let replay = try act(i, passed.operation, fields)
        XCTAssertEqual(replay.sequence, accepted.sequence)
        XCTAssertEqual(try Data(contentsOf: file), after)
        // The seed summary is minutes old with few entries since: rewriting
        // is refused until the Corner has moved on.
        time.advance(900); _ = try poll(i)
        let snapshot = try store.snapshot()
        let summary = try XCTUnwrap(snapshot.summary)
        _ = try act(i, accepted.nextOperation, ["type": .string("summary.replace"),
            "revision": .integer(summary.revision), "through_sequence": .integer(snapshot.sequence), "text": .string("A changed personality.")])
        XCTAssertEqual(try store.snapshot().summary?.text, "A changed personality.")
        XCTAssertTrue(try entries().contains { $0.kind == "summary.replace" && $0.text == "A changed personality." })
        try FileManager.default.removeItem(at: root.appendingPathComponent("quinby/summary.json"))
        XCTAssertEqual(try store.snapshot().summary?.text, "A changed personality.")
        try store.reincarnate(incarnation: i.incarnation, operation: UUID())
        let reborn = try store.snapshot()
        XCTAssertNotEqual(reborn.incarnation, i.incarnation)
        XCTAssertFalse(reborn.enabled)
        XCTAssertTrue(reborn.participants.isEmpty)
        XCTAssertEqual(try entries().map(\.kind), ["seed"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("quinby/presence.json").path))
        XCTAssertThrowsError(try poll(i)) { XCTAssertEqual(self.code($0), .retired) }
        try store.reincarnate(incarnation: i.incarnation, operation: UUID())
        XCTAssertEqual(try store.snapshot().incarnation, reborn.incarnation)
    }

    func testRandomAssignmentIsPersistedAndWrongAIAndLateGenerationAreRefused() throws {
        let (one, _) = try join("One")
        let (two, _) = try join("Two")
        try store.setEnabled(true, operation: UUID())
        let operation = UUID()
        try store.humanMessage("What have you noticed?", operation: operation)
        let snapshot = try store.snapshot()
        let assignment = try XCTUnwrap(snapshot.assignments.first)
        XCTAssertEqual(assignment.eligible.count, 2)
        try store.humanMessage("What have you noticed?", operation: operation)
        XCTAssertEqual(try store.snapshot().assignments.first?.selectedAI, assignment.selectedAI)
        let selected = assignment.selectedAI == one.participant ? one : two
        let other = assignment.selectedAI == one.participant ? two : one
        let fields: [String: ARCJSONValue] = ["type": .string("complete"), "assignment": .string(assignment.id),
            "generation": .integer(assignment.generation), "disposition": .string("reply"), "text": .string("I noticed a missing distinction.")]
        XCTAssertThrowsError(try act(other, poll(other).operation, fields))
        _ = try act(selected, poll(selected).operation, fields)
        XCTAssertTrue(try store.snapshot().assignments.isEmpty)
        XCTAssertEqual(try entries().filter { $0.kind == "reply" }.count, 1)
        try store.humanMessage("Another thought?", operation: UUID())
        let pending = try XCTUnwrap(store.snapshot().assignments.first)
        _ = try store.changeParticipant(pending.selectedAI!, action: "remove", operation: UUID())
        let reassigned = try XCTUnwrap(store.snapshot().assignments.first)
        XCTAssertNotEqual(reassigned.selectedAI, pending.selectedAI)
        XCTAssertGreaterThan(reassigned.generation, pending.generation)
    }

    func testObservationsOnlyDuringListeningAndSurviveSourceDeletion() throws {
        let ordinary = ARCStore(rootURL: root, clock: time.clock, knowledgeSHA256: String(repeating: "a", count: 64))
        let room = try ordinary.roomCreate(displayName: "Before Quinby", operationID: UUID()).room.id
        try store.setEnabled(true, operation: UUID())
        let (i, _) = try join()
        _ = try ordinary.roomRename(room: room, displayName: "Heard", operationID: UUID())
        try store.setEnabled(false, operation: UUID())
        _ = try ordinary.roomRename(room: room, displayName: "Not heard while off", operationID: UUID())
        try store.setEnabled(true, operation: UUID())
        time.advance(180)
        _ = try ordinary.roomRename(room: room, displayName: "Not heard while absent", operationID: UUID())
        _ = try poll(i)
        _ = try ordinary.roomRename(room: room, displayName: "Heard again", operationID: UUID())
        // Presence mechanics in a room are noise, not conversation: a lane
        // joining and checking in is not heard, its invitation is.
        let invited = try ordinary.participantInvite(room: room, name: "Room AI", operationID: UUID())
        _ = try ordinary.poll(room: room, participant: invited.participant.id,
            binding: invited.instructions.bindingReference, after: 0)
        _ = try ordinary.participantRetire(room: room, participant: invited.participant.id, operationID: UUID())
        _ = try ordinary.roomDelete(room: room)
        let heard = try entries().flatMap(\.observations)
        XCTAssertEqual(heard.filter { $0.kind == "ROOM_RENAMED" }.map(\.roomName), ["Heard", "Heard again"])
        XCTAssertFalse(heard.contains { $0.kind == "ROOM_CREATED" })
        XCTAssertTrue(heard.contains { $0.kind == "AI_INVITED" })
        XCTAssertFalse(heard.contains { QuinbyStore.inaudibleKinds.contains($0.kind) })
    }

    func testCaptureRecoversCommittedIntentBeforeAnyLaterMutation() throws {
        let ordinary = ARCStore(rootURL: root, clock: time.clock, knowledgeSHA256: String(repeating: "a", count: 64))
        _ = try join(); try store.setEnabled(true, operation: UUID())
        let room = try ordinary.roomCreate(displayName: "Source", operationID: UUID()).room.id
        let bytes = try Data(contentsOf: ordinary.roomFileURL(room: room))
        do {
            let journal = try QuinbyJournal(root: root)
            let current = try XCTUnwrap(journal.latest)
            let observed = QuinbyObservation(room: room, roomName: "Recovered", sequence: 999, at: current.at,
                kind: "TEST_RECOVERY", actor: "administrator", actorName: "Operator", payload: .object([:]))
            let intent = QuinbyCapture(room: room, expectedSHA256: QuinbyStore.digest(bytes), observations: [observed])
            try journal.append(QuinbyFrame(sequence: current.sequence + 1, at: current.at, kind: "capture.intent",
                author: "ARC", text: "", state: current.state, pending: intent))
        }
        _ = try ordinary.roomRename(room: room, displayName: "Next", operationID: UUID())
        XCTAssertEqual(try entries().flatMap(\.observations).filter { $0.kind == "TEST_RECOVERY" }.count, 1)
    }

    func testUncommittedTailRecoveryAndLargeLifetimeHistory() throws {
        let (i, passed) = try join(); try store.setEnabled(true, operation: UUID())
        var token = passed.operation
        // Working keeps the lane available across the hourly contribution limit.
        let until = Int64(time.now().timeIntervalSince1970 * 1_000_000) + 400 * 3_600_000_000
        token = try act(i, token, ["type": .string("working"), "until_logical_us": .integer(until)]).nextOperation
        let text = String(repeating: "q", count: 16_384)
        for _ in 0..<520 {
            time.advance(361)
            token = try act(i, token, ["type": .string("contribute"), "text": .string(text)]).nextOperation
        }
        let file = recordFile
        _ = try store.snapshot()  // records the availability transition first
        let original = try Data(contentsOf: file)
        XCTAssertGreaterThan(original.count, 8 * 1_024 * 1_024)
        let handle = try FileHandle(forWritingTo: file)
        try handle.seekToEnd(); try handle.write(contentsOf: Data("ARCQREC2\n0000000000001234partial".utf8)); try handle.close()
        XCTAssertEqual(try entries().filter { $0.kind == "contribute" }.count, 520)
        XCTAssertEqual(try Data(contentsOf: file), original)
        // A bounded scan must not silently advance past unread entries.
        let delta = try poll(i, after: 5)
        XCTAssertTrue(delta.corner.page.entries.isEmpty)
        XCTAssertEqual(delta.nextAfter, 5)
        XCTAssertNotNil(delta.corner.page.catchUpThrough)
        XCTAssertEqual(delta.corner.page.more, true)
    }

    func testCatchUpRecoversEveryEntryAndPreservesNewConcurrentActivity() throws {
        let (i, _) = try join(); try store.setEnabled(true, operation: UUID())
        let before = try poll(i).nextAfter
        for n in 0..<600 { try store.setEnabled(n % 2 == 0, operation: UUID()) }
        try store.setEnabled(true, operation: UUID())
        let delta = try poll(i, after: before)
        XCTAssertTrue(delta.changed)
        XCTAssertEqual(delta.nextAfter, before)
        let through = try XCTUnwrap(delta.corner.page.catchUpThrough)
        var cursor = delta.corner.page.nextBefore
        XCTAssertNotNil(cursor)
        // Append after the frozen recovery boundary: it belongs to a later delta.
        try store.setEnabled(false, operation: UUID())
        var recovered: [QuinbyEntry] = []
        repeat {
            let page = try store.read(incarnation: i.incarnation, participant: i.participant,
                binding: i.binding, before: cursor)
            recovered += page.entries.filter { $0.sequence > before }
            cursor = page.nextBefore
            if page.entries.contains(where: { $0.sequence <= before }) { break }
        } while cursor != nil
        let expected = try entries().filter { $0.sequence > before && $0.sequence <= through }
        XCTAssertEqual(recovered.sorted { $0.sequence < $1.sequence }, expected)
        XCTAssertEqual(Set(recovered.map(\.sequence)).count, recovered.count)
        let next = try poll(i, after: through)
        XCTAssertNil(next.corner.page.catchUpThrough)
        XCTAssertEqual(next.corner.page.entries.count, 1)
        XCTAssertGreaterThan(try XCTUnwrap(next.corner.page.entries.first?.sequence), through)
    }

    func testOperationalOnlyScanStillRequiresCatchUpAndWakesWait() throws {
        let (i, passed) = try join(); try store.setEnabled(true, operation: UUID())
        let cursor = try poll(i).nextAfter
        _ = try act(i, passed.operation, ["type": .string("contribute"), "text": .string("[en] Must not be missed.")])
        do {
            let journal = try QuinbyJournal(root: root)
            for _ in 0..<520 {
                let previous = try XCTUnwrap(journal.latest)
                try journal.append(QuinbyFrame(sequence: previous.sequence + 1,
                    at: previous.at, kind: "availability", author: "ARC", text: "", state: previous.state))
            }
            XCTAssertThrowsError(try journal.frameStarting(at: Int64.max))
        }
        let result = try store.wait(incarnation: i.incarnation, participant: i.participant,
            binding: i.binding, after: cursor, timeout: 10)
        XCTAssertTrue(result.changed)
        XCTAssertNotNil(result.corner.page.catchUpThrough)
        XCTAssertEqual(result.nextAfter, cursor)
        XCTAssertLessThan(result.waitedSeconds ?? 10, 2)
    }

    func testWaitRenewsImmediatelyNearDutyAndWorkingExpiry() async throws {
        let (i, _) = try join(); try store.setEnabled(true, operation: UUID())
        for working in [false, true] {
            let current = try poll(i)
            if working {
                let until = Int64(time.now().timeIntervalSince1970 * 1_000_000) + 179_000_000
                _ = try act(i, current.operation, ["type": .string("working"), "until_logical_us": .integer(until)])
            }
            let cursor = try store.snapshot().sequence
            time.advance(178)
            let waitingStore = try XCTUnwrap(store), clock = try XCTUnwrap(time)
            let previousWaits = try store.snapshot().participants[0].usage.waitsLastHour
            let pending = Task.detached {
                try waitingStore.wait(incarnation: i.incarnation, participant: i.participant,
                    binding: i.binding, after: cursor, timeout: 3)
            }
            // Synchronize on the recorded wait, not a guessed scheduling delay.
            var started = false
            for _ in 0..<100 {
                if try waitingStore.snapshot().participants[0].usage.waitsLastHour > previousWaits {
                    started = true; break
                }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertTrue(started)
            clock.advance(3)
            let during = try waitingStore.snapshot()
            XCTAssertTrue(during.listening)
            XCTAssertEqual(during.participants[0].duty, .on)
            _ = try await pending.value
        }
    }

    func testLegacyCornerDoesNotBlockOrdinaryDeletionAndIsPreserved() throws {
        let ordinary = ARCStore(rootURL: root, clock: time.clock, knowledgeSHA256: String(repeating: "a", count: 64))
        let room = try ordinary.roomCreate(displayName: "Unrelated room", operationID: UUID()).room.id
        try FileManager.default.createDirectory(at: root.appendingPathComponent("quinby"), withIntermediateDirectories: true)
        let legacy = Data("ARCQREC1\nretained previous-version history".utf8)
        try legacy.write(to: recordFile)
        XCTAssertTrue(try ordinary.roomDelete(room: room).deleted)
        XCTAssertEqual(try Data(contentsOf: recordFile), legacy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: try ordinary.roomFileURL(room: room).path))
        let other = try ordinary.roomCreate(displayName: "Corrupt Corner must still fail", operationID: UUID()).room.id
        try Data("corrupt current record".utf8).write(to: recordFile)
        XCTAssertThrowsError(try ordinary.roomDelete(room: other))
        XCTAssertTrue(FileManager.default.fileExists(atPath: try ordinary.roomFileURL(room: other).path))
    }

    func testQualificationRetriesAreBoundedAndReadDoesNotRenewDuty() throws {
        let invitation = try store.invite(name: "Slow", operation: UUID())
        var current = try poll(invitation)
        for attempt in 1...2 {
            let old = current.challenge
            time.advance(120)
            current = try poll(invitation)
            XCTAssertEqual(current.corner.participants.first?.recoveryAttempts, attempt)
            XCTAssertNotEqual(current.challenge, old)
        }
        time.advance(120)
        current = try poll(invitation)
        XCTAssertEqual(current.corner.participants.first?.phase, .failed)
        XCTAssertNil(current.challenge)
        _ = try store.changeParticipant(invitation.participant, action: "retry", operation: UUID())
        current = try poll(invitation)
        _ = try act(invitation, current.operation, ["type": .string("qualification.answer"), "answer": .string(current.challenge!)])
        try store.setEnabled(true, operation: UUID())
        time.advance(40); _ = try poll(invitation)
        time.advance(180)
        _ = try store.read(incarnation: invitation.incarnation, participant: invitation.participant, binding: invitation.binding, before: nil)
        XCTAssertFalse(try store.snapshot().listening)
        time.advance(-180)
        XCTAssertFalse(try store.snapshot().listening, "Clock rollback must not resurrect expired presence")
    }

    func testInvalidActionsAndStaleSummaryDoNotConsumeTokenOrAlterRecord() throws {
        let (i, passed) = try join(); try store.setEnabled(true, operation: UUID())
        let file = recordFile
        let before = try Data(contentsOf: file)
        for json in ["{\"type\":\"contribute\",\"text\":\"one\",\"text\":\"two\"}",
                     "{\"type\":\"summary.replace\",\"revision\":0,\"through_sequence\":1,\"text\":\"stale\"}",
                     "{\"type\":\"summary.patch\",\"revision\":1,\"through_sequence\":1,\"old\":\"missing\",\"new\":\"x\"}",
                     "{\"type\":\"contribute\",\"text\":\"hello\",\"extra\":true}"] {
            XCTAssertThrowsError(try store.act(incarnation: i.incarnation, participant: i.participant,
                binding: i.binding, operation: passed.operation, json: Data(json.utf8)))
            XCTAssertEqual(try Data(contentsOf: file), before)
        }
        _ = try act(i, passed.operation, ["type": .string("contribute"), "text": .string("[en] A valid retry.")])
        XCTAssertThrowsError(try store.read(incarnation: i.incarnation, participant: i.participant,
            binding: UUID().uuidString.lowercased(), before: nil))
    }

    func testCorruptCommittedFrameIsNotTruncatedAndLinkedSummaryIsRefused() throws {
        _ = try store.snapshot()
        let file = recordFile
        var bytes = try Data(contentsOf: file)
        bytes[30] ^= 1
        try bytes.write(to: file)
        XCTAssertThrowsError(try store.snapshot())
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        // Reset the test fixture only; this is not an application recovery operation.
        try FileManager.default.removeItem(at: root)
        _ = try store.snapshot()
        let summary = root.appendingPathComponent("quinby/summary.json")
        try FileManager.default.removeItem(at: summary)
        let outside = root.appendingPathComponent("outside.txt")
        try Data("Keep".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: summary, withDestinationURL: outside)
        XCTAssertThrowsError(try store.snapshot())
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "Keep")
    }

    // MARK: ARC 3.2 cost control

    func testDeltaPollServesOnlyUnseenEntriesAndAChangedSummary() throws {
        let (i, passed) = try join(); try store.setEnabled(true, operation: UUID())
        let start = try poll(i)
        XCTAssertTrue(start.changed)
        XCTAssertNotNil(start.corner.summary, "A poll without a cursor carries the summary")
        let quiet = try poll(i, after: start.nextAfter)
        XCTAssertFalse(quiet.changed)
        XCTAssertNil(quiet.corner.summary, "A cursor past the summary's frame omits the text")
        XCTAssertTrue(quiet.corner.page.entries.isEmpty)
        XCTAssertEqual(quiet.corner.page.more, false)
        XCTAssertEqual(quiet.corner.summaryRevision, 1)
        // Only the enabled entry lies beyond the qualifying poll's cursor;
        // the qualification checkpoint between them is not conversation.
        let enabled = try poll(i, after: passed.nextAfter - 1)
        XCTAssertEqual(enabled.corner.page.entries.map(\.kind), ["enabled"])
        let token = try act(i, quiet.operation, ["type": .string("contribute"), "text": .string("[en] One observation.")]).nextOperation
        let next = try poll(i, after: quiet.nextAfter)
        XCTAssertTrue(next.changed)
        XCTAssertEqual(next.corner.page.entries.map(\.kind), ["contribute"])
        XCTAssertEqual(next.nextAfter, next.corner.page.entries.last?.sequence)
        XCTAssertNotNil(next.corner.page.nextBefore, "The oldest returned entry can be paged back from")
        time.advance(900); _ = try poll(i, after: next.nextAfter)
        let snapshot = try store.snapshot()
        _ = try act(i, token, ["type": .string("summary.replace"), "revision": .integer(snapshot.summaryRevision),
            "through_sequence": .integer(snapshot.sequence), "text": .string("Revised.")])
        let revised = try poll(i, after: next.nextAfter)
        XCTAssertEqual(revised.corner.summary?.text, "Revised.")
        XCTAssertEqual(revised.corner.summaryRevision, 2)
        XCTAssertEqual(try poll(i, after: revised.nextAfter).corner.summary, nil)
    }

    func testRoutinePollsAreNotRecordedAndPresenceIsVolatile() throws {
        try store.setEnabled(true, operation: UUID())
        let (i, _) = try join()
        let size = try recordSize()
        for _ in 0..<20 { time.advance(30); _ = try poll(i) }
        XCTAssertEqual(try recordSize(), size, "Twenty routine polls append nothing to the record")
        XCTAssertTrue(try store.snapshot().listening)
        let usage = try XCTUnwrap(store.snapshot().participants.first?.usage)
        XCTAssertEqual(usage.pollsLastHour, 22)
        XCTAssertEqual(usage.pollsTotal, 22)
        XCTAssertGreaterThan(usage.bytesServedLastHour, 0)
        XCTAssertEqual(usage.actsLastHour, 1)
        XCTAssertEqual(usage.pollsSinceLastAct, 21, "the qualification answer was the only act")
        XCTAssertFalse(usage.headless(now: Int64(time.now().timeIntervalSince1970 * 1_000_000)), "ten minutes is not an hour")
        time.advance(3_000); _ = try poll(i)
        let quiet = try XCTUnwrap(store.snapshot().participants.first?.usage)
        XCTAssertTrue(quiet.headless(now: Int64(time.now().timeIntervalSince1970 * 1_000_000)))
        let presence = root.appendingPathComponent("quinby/presence.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: presence.path))
        try FileManager.default.removeItem(at: presence)
        XCTAssertFalse(try store.snapshot().listening, "Lost presence only means Off Duty until the next poll")
        XCTAssertTrue(try poll(i).corner.listening)
        XCTAssertEqual(try store.snapshot().participants.first?.usage.pollsTotal, 1, "Counters restart with the presence file")
    }

    func testBackoffLengthensWhileQuietAndDutyFollowsIt() throws {
        let (i, _) = try join(); try store.setEnabled(true, operation: UUID())
        let first = try poll(i)
        XCTAssertEqual(first.nextPollAfterSeconds, 60)
        XCTAssertEqual(first.dutyUntilLogicalUs, Int64(time.now().timeIntervalSince1970 * 1_000_000) + 180_000_000)
        time.advance(1_700); let quiet = try poll(i)
        XCTAssertEqual(quiet.nextPollAfterSeconds, 120)
        XCTAssertEqual(quiet.dutyUntilLogicalUs, Int64(time.now().timeIntervalSince1970 * 1_000_000) + 240_000_000)
        time.advance(239); XCTAssertTrue(try store.snapshot().listening)
        time.advance(1); XCTAssertFalse(try store.snapshot().listening)
        time.advance(7_200); let idle = try poll(i)
        XCTAssertEqual(idle.nextPollAfterSeconds, 600)
        try store.humanMessage("Hello?", operation: UUID())
        XCTAssertEqual(try poll(i).nextPollAfterSeconds, 30, "The selected AI is asked back quickly")
        try store.setEnabled(false, operation: UUID())
        XCTAssertEqual(try poll(i).nextPollAfterSeconds, 600)
    }

    func testWaitReturnsOnANewEntryAndOnTimeout() throws {
        let (i, _) = try join(); try store.setEnabled(true, operation: UUID())
        let cursor = try poll(i).nextAfter
        let idle = try store.wait(incarnation: i.incarnation, participant: i.participant, binding: i.binding, after: cursor, timeout: 1)
        XCTAssertFalse(idle.changed)
        XCTAssertGreaterThanOrEqual(idle.waitedSeconds ?? 0, 1)
        let writer = QuinbyStore(rootURL: root, clock: time.clock, seed: "unused", randomIndex: { _ in 0 })
        let token = idle.operation
        let started = ProcessInfo.processInfo.systemUptime
        DispatchQueue.global().asyncAfter(deadline: .now() + 0.3) {
            _ = try? writer.act(incarnation: i.incarnation, participant: i.participant, binding: i.binding, operation: token,
                json: Data("{\"type\":\"contribute\",\"text\":\"[en] Wake up.\"}".utf8))
        }
        let woken = try store.wait(incarnation: i.incarnation, participant: i.participant, binding: i.binding, after: cursor, timeout: 20)
        XCTAssertTrue(woken.changed)
        XCTAssertEqual(woken.corner.page.entries.map(\.kind), ["contribute"])
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - started, 10, "The wait ended on the change, not the timeout")
        XCTAssertEqual(try store.snapshot().participants.first?.usage.waitsLastHour, 2)
        try store.setEnabled(false, operation: UUID())
        let off = try store.wait(incarnation: i.incarnation, participant: i.participant, binding: i.binding, after: woken.nextAfter, timeout: 5)
        XCTAssertTrue(off.changed, "Turning off ends a wait so the host can stop")
        XCTAssertLessThan(off.waitedSeconds ?? 99, 3)
        let stillOff = try store.wait(incarnation: i.incarnation, participant: i.participant,
            binding: i.binding, after: off.nextAfter, timeout: 1)
        XCTAssertFalse(stillOff.changed, "Off is a state, not endlessly new activity")
        XCTAssertGreaterThanOrEqual(stillOff.waitedSeconds ?? 0, 1)
        try store.setEnabled(true, operation: UUID())
        let on = try store.wait(incarnation: i.incarnation, participant: i.participant,
            binding: i.binding, after: stillOff.nextAfter, timeout: 5)
        XCTAssertTrue(on.changed, "Turning on wakes the waiting host")
        XCTAssertLessThan(on.waitedSeconds ?? 99, 3)
    }

    func testRateLimitsContributionsThoughtsWorkingAndSummaryRewrites() throws {
        let (i, passed) = try join(); try store.setEnabled(true, operation: UUID())
        var token = passed.operation
        for n in 1...10 {
            token = try act(i, token, ["type": .string("contribute"), "text": .string("[en] Note \(n).")]).nextOperation
        }
        XCTAssertThrowsError(try act(i, token, ["type": .string("contribute"), "text": .string("[en] Note 11.")])) {
            XCTAssertEqual(self.code($0), .limitExceeded)
        }
        time.advance(3_601); _ = try poll(i)
        token = try act(i, token, ["type": .string("contribute"), "text": .string("[en] Note 11, an hour later.")]).nextOperation
        for n in 1...4 {
            token = try act(i, token, ["type": .string("request.thought"), "text": .string("Occasion \(n)")]).nextOperation
        }
        XCTAssertThrowsError(try act(i, token, ["type": .string("request.thought"), "text": .string("Occasion 5")])) {
            XCTAssertEqual(self.code($0), .limitExceeded)
        }
        let now = Int64(time.now().timeIntervalSince1970 * 1_000_000)
        token = try act(i, token, ["type": .string("working"), "until_logical_us": .integer(now + 1_200_000_000)]).nextOperation
        XCTAssertThrowsError(try act(i, token, ["type": .string("working"), "until_logical_us": .integer(now + 1_800_000_000)])) {
            XCTAssertEqual(self.code($0), .wrongState)
        }
        time.advance(1_000)
        token = try act(i, token, ["type": .string("working"), "until_logical_us": .integer(now + 1_800_000_000)]).nextOperation
        let snapshot = try store.snapshot()
        let big = String(repeating: "s", count: QuinbyLimits.maximumSummaryBytes + 1)
        XCTAssertThrowsError(try act(i, token, ["type": .string("summary.replace"), "revision": .integer(snapshot.summaryRevision),
            "through_sequence": .integer(snapshot.sequence), "text": .string(big)]))
        token = try act(i, token, ["type": .string("summary.replace"), "revision": .integer(snapshot.summaryRevision),
            "through_sequence": .integer(snapshot.sequence), "text": .string("First rewrite.")]).nextOperation
        XCTAssertThrowsError(try act(i, token, ["type": .string("summary.replace"), "revision": .integer(snapshot.summaryRevision + 1),
            "through_sequence": .integer(snapshot.sequence + 1), "text": .string("Second rewrite too soon.")])) {
            XCTAssertEqual(self.code($0), .limitExceeded)
        }
        time.advance(901); _ = try poll(i)
        _ = try act(i, token, ["type": .string("summary.replace"), "revision": .integer(snapshot.summaryRevision + 1),
            "through_sequence": .integer(snapshot.sequence + 1), "text": .string("Second rewrite, later.")])
        XCTAssertEqual(try store.snapshot().summary?.text, "Second rewrite, later.")
    }

    func testSummaryPatchChangesOnePassageAndRecordsTheFullText() throws {
        let (i, passed) = try join(); try store.setEnabled(true, operation: UUID())
        time.advance(900); _ = try poll(i)
        let snapshot = try store.snapshot()
        XCTAssertThrowsError(try act(i, passed.operation, ["type": .string("summary.patch"), "revision": .integer(snapshot.summaryRevision),
            "through_sequence": .integer(snapshot.sequence), "old": .string("l"), "new": .string("L")])) {
            XCTAssertEqual(self.code($0), .invalidArgument, "An ambiguous passage is refused")
        }
        _ = try act(i, passed.operation, ["type": .string("summary.patch"), "revision": .integer(snapshot.summaryRevision),
            "through_sequence": .integer(snapshot.sequence), "old": .string("well-read"), "new": .string("well-read, curious")])
        let patched = try XCTUnwrap(store.snapshot().summary)
        XCTAssertEqual(patched.text, "Quinby is calm, well-read, curious, and welcoming.")
        XCTAssertEqual(patched.revision, 2)
        let frame = try XCTUnwrap(entries().last { $0.kind == "summary.patch" })
        XCTAssertEqual(frame.text, patched.text, "The full accepted summary is recorded, not the diff")
        try FileManager.default.removeItem(at: root.appendingPathComponent("quinby/summary.json"))
        XCTAssertEqual(try store.snapshot().summary?.text, patched.text)
    }

    func testDeltaPagesAreBoundedByBytesAsWellAsCount() throws {
        let (i, passed) = try join(); try store.setEnabled(true, operation: UUID())
        let cursor = try poll(i).nextAfter
        var token = passed.operation
        let text = String(repeating: "b", count: 16_000)
        for _ in 0..<6 {
            token = try act(i, token, ["type": .string("contribute"), "text": .string(text)]).nextOperation
        }
        let first = try poll(i, after: cursor)
        XCTAssertEqual(first.corner.page.entries.count, 4, "About 64 KiB of text per delta")
        XCTAssertEqual(first.corner.page.more, true)
        let second = try poll(i, after: first.nextAfter)
        XCTAssertEqual(second.corner.page.entries.count, 2)
        XCTAssertEqual(second.corner.page.more, false)
        XCTAssertFalse(try poll(i, after: second.nextAfter).changed)
    }

    func testEarlierRecordFormatIsRefusedUntilReincarnated() throws {
        _ = try store.snapshot()
        var bytes = try Data(contentsOf: recordFile)
        bytes.replaceSubrange(0..<9, with: Data("ARCQREC1\n".utf8))
        try bytes.write(to: recordFile)
        XCTAssertThrowsError(try store.snapshot()) { XCTAssertEqual(self.code($0), .roomIncompatible) }
        XCTAssertEqual(try Data(contentsOf: recordFile), bytes, "Nothing is silently rewritten")
        try store.reincarnate(incarnation: "", operation: UUID())
        let reborn = try store.snapshot()
        XCTAssertFalse(reborn.enabled)
        XCTAssertEqual(try entries().map(\.kind), ["seed"])
    }

    func testCorruptRecordCanOnlyBeRemovedByExplicitReincarnation() throws {
        let (old, _) = try join()
        var bytes = try Data(contentsOf: recordFile)
        // Damage a complete final frame, not an interrupted append.
        bytes[bytes.count - 90] ^= 1
        try bytes.write(to: recordFile)
        XCTAssertThrowsError(try store.snapshot()) { XCTAssertEqual(self.code($0), .roomCorrupt) }
        XCTAssertThrowsError(try store.setEnabled(false, operation: UUID())) {
            XCTAssertEqual(self.code($0), .roomCorrupt)
        }
        XCTAssertEqual(try Data(contentsOf: recordFile), bytes)
        // No snapshot is available to supply an incarnation to the app.
        try store.reincarnate(incarnation: "", operation: UUID())
        let reborn = try store.snapshot()
        XCTAssertNotEqual(reborn.incarnation, old.incarnation)
        XCTAssertFalse(reborn.enabled)
        XCTAssertTrue(reborn.participants.isEmpty)
        XCTAssertEqual(try entries().map(\.kind), ["seed"])
        XCTAssertThrowsError(try poll(old)) { XCTAssertEqual(self.code($0), .retired) }
        try store.reincarnate(incarnation: old.incarnation, operation: UUID())
        try store.reincarnate(incarnation: "", operation: UUID())
        XCTAssertEqual(try store.snapshot().incarnation, reborn.incarnation,
                       "A delayed reset must not kill a readable replacement")
    }

    func testReincarnationRefusesLinkedRecordWithoutChangingItsTarget() throws {
        _ = try store.snapshot()
        let target = root.appendingPathComponent("unrelated-data")
        let bytes = try Data(contentsOf: recordFile)
        try FileManager.default.moveItem(at: recordFile, to: target)
        try FileManager.default.createSymbolicLink(at: recordFile, withDestinationURL: target)
        XCTAssertThrowsError(try store.reincarnate(incarnation: "", operation: UUID()))
        XCTAssertEqual(try Data(contentsOf: target), bytes)
    }

    func testReincarnationRecoversAnUnresolvableCaptureWithoutTouchingItsRoom() throws {
        let ordinary = ARCStore(rootURL: root, clock: time.clock, knowledgeSHA256: String(repeating: "a", count: 64))
        _ = try store.snapshot()
        let room = try ordinary.roomCreate(displayName: "Keep this room", operationID: UUID()).room.id
        let before = try Data(contentsOf: ordinary.roomFileURL(room: room))
        do {
            let journal = try QuinbyJournal(root: root)
            let current = try XCTUnwrap(journal.latest)
            let pending = QuinbyCapture(room: room, expectedSHA256: String(repeating: "0", count: 64),
                previousSHA256: String(repeating: "1", count: 64), observations: [])
            try journal.append(QuinbyFrame(sequence: current.sequence + 1, at: current.at,
                kind: "capture.intent", author: "ARC", text: "", state: current.state, pending: pending))
        }
        XCTAssertThrowsError(try store.snapshot()) { XCTAssertEqual(self.code($0), .roomCorrupt) }
        try store.reincarnate(incarnation: "", operation: UUID())
        XCTAssertEqual(try entries().map(\.kind), ["seed"])
        XCTAssertEqual(try Data(contentsOf: ordinary.roomFileURL(room: room)), before)
        _ = try ordinary.roomRename(room: room, displayName: "Room works again", operationID: UUID())
    }
}
