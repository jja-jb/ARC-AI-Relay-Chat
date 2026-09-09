import CryptoKit
import Foundation
import XCTest
@testable import ARCCore

final class ARCTerseTests: XCTestCase {
    func json(_ text: String) throws -> ARCJSONValue { try ARCTerse.decode(Data(text.utf8)) }

    func testClassicGrammarAndLocalConstraints() throws {
        for text in ["TELL WORD SAME 2\n", "SEE WAS TELL WORK STOP\n", "WHEN (WAS TELL WORK DONE) TELL WORK BAD\n",
                     "TELL (\"n\" MORE 5) OR (\"n\" SAME 3)\n", "TELL NOT HEAR \"sec 4.11\"\n",
                     "DO ALL YOU STOP 1\n", "DO YOU ALL WORK 1\n", "[de] Prüfsumme fehlt.\n", "\n",
                     "TELL work-012345abcdef DONE\nASK YOU GOOD THIS\n"] {
            XCTAssertNoThrow(try ARCTerse.validateText(text), text)
        }
        for text in ["TELL HEAR", "TELL  HEAR\n", " TELL HEAR\n", "TELL SOON\n", "TELL NOT HEAR\n",
                     "TELL 1-2\n", "[fr] Non.\n", "TELL HEAR TELL BAD\n", "TELL (GOOD\n", "TELL ()\n",
                     "GIVE FILE \"relative\"\n", "SEE DO YOU STOP 1\n", "DO YOU FILE 1\n", "DO YOU STOP\n",
                     "ASK YOU GOOD THIS\n", "TELL \"sha256:no\"\n", "TELL \"é\"\n", "[en] \n"] {
            XCTAssertThrowsError(try ARCTerse.validateText(text), text)
        }
    }

    func testBuilderStrictJSONBoundsAndUnknownExtensions() throws {
        let value = try json(#"{"kind":"results","subject":"suite","checks":[{"id":"parse","status":"pass","basis":"verified"}]}"#)
        XCTAssertTrue(try ARCTerse.build(value).hasPrefix("@terse/2 {"))
        XCTAssertEqual(try ARCTerse.build(value), try ARCTerse.build(json(ARCTerse.canonical(value))))
        for invalid in [#"{"kind":"lines","kind":"declare"}"#, #"{"n":1.0}"#, #"{"n":9223372036854775808}"#] {
            XCTAssertThrowsError(try json(invalid))
        }
        for invalid in [#"{"kind":"execute","command":"anything"}"#,
                        #"{"kind":"dependency","subject":"a","requires":["a"]}"#,
                        #"{"kind":"results","subject":"a","checks":[{"id":"b","status":"not_run","basis":"verified"}]}"#,
                        #"{"kind":"context","key":"x","fields":{"nested":{}}}"#,
                        #"{"kind":"batch","items":[{"id":"x","text":"DO YOU STOP 1\n"}]}"#] {
            XCTAssertThrowsError(try ARCTerse.build(json(invalid)))
        }
        XCTAssertThrowsError(try ARCTerse.build(.object(["kind": .string("context"), "key": .string("x"),
            "fields": .object(["large": .string(String(repeating: "a", count: 4097))]) ])))
    }

    func testCommandUsesDirectArgumentsAndMachineFraming() throws {
        let executable = Bundle(for: ARCTerseTests.self).bundleURL.deletingLastPathComponent().appendingPathComponent("arc")
        for (args, status): ([String], Int32) in [
            (["terse", "validate", "--text", "TELL WORD SAME 2\n"], 0),
            (["terse", "validate", "--text", "TELL SOON\n"], 2),
            (["terse", "build", "--request", #"{"kind":"dependency","subject":"package","requires":["tests"]}"#], 0),
            (["terse", "build", "--request", #"{"kind":"unknown"}"#], 2),
            (["--root", "/private/tmp", "terse", "validate", "--text", "TELL HEAR\n"], 2)
        ] {
            let process = Process(); process.executableURL = executable; process.arguments = args
            let output = Pipe(), error = Pipe(); process.standardOutput = output; process.standardError = error
            try process.run(); process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, status)
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let result = try json(String(decoding: data, as: UTF8.self))
            XCTAssertEqual(result.objectValue?["ok"], .boolean(status == 0))
            XCTAssertEqual(data.last, 10)
            XCTAssertTrue(error.fileHandleForReading.readDataToEndOfFile().isEmpty)
        }
    }

    func testDeclarationsAreRequiredAndBoundToBothBindingsAndDigest() throws {
        let f = try Fixture(); defer { f.cleanup() }
        let context = try json(#"{"kind":"context","key":"brief","fields":{"done":false}}"#)
        XCTAssertThrowsError(try f.send(0, to: 1, context))
        _ = try f.send(0, to: 1, f.declaration())
        XCTAssertThrowsError(try f.send(0, to: 1, context))
        _ = try f.send(1, to: 0, f.declaration())
        _ = try f.send(0, to: 1, context)
        let bytes = try Data(contentsOf: f.store.roomFileURL(room: f.room))
        let d = try ARCRoomCodec.decode(bytes, expectedID: f.room)
        XCTAssertNotNil(ARCTerseLedger.declaration(d, sender: d.participants[0], target: d.participants[1], digest: f.digest))
        var changed = d.participants[0]; changed.bindingGeneration += 1
        XCTAssertNil(ARCTerseLedger.declaration(d, sender: changed, target: d.participants[1], digest: f.digest))
        XCTAssertNil(ARCTerseLedger.declaration(d, sender: d.participants[0], target: changed, digest: f.digest))
        XCTAssertNil(ARCTerseLedger.declaration(d, sender: d.participants[0], target: d.participants[1], digest: String(repeating: "0", count: 64)))
        XCTAssertThrowsError(try f.send(0, to: 1, f.declaration(digest: String(repeating: "0", count: 64))))
    }

    func testProfilesCanBeWithdrawnAndNoUnknownProfileIsAccepted() throws {
        let f = try Fixture(); defer { f.cleanup() }
        try f.handshake()
        _ = try f.send(1, to: 0, f.declaration(profiles: []))
        XCTAssertThrowsError(try f.send(0, to: 1, json(#"{"kind":"context","key":"x","fields":{"n":1}}"#)))
        XCTAssertThrowsError(try f.send(1, to: 0, f.declaration(profiles: ["anything/1"])))
        _ = try f.send(0, to: 1, json(#"{"kind":"lines","text":"TELL HEAR\n"}"#))
    }

    func testContextDeltaReferenceRecoveryAndImmutableHistory() throws {
        let f = try Fixture(); defer { f.cleanup() }; try f.handshake()
        let first = try f.send(0, to: 1, json(#"{"kind":"context","key":"brief","fields":{"done":false,"count":1}}"#))
        let sequence = first.eventSequences[0]
        let baseline = try f.read(1, sequence: sequence).objectValue!["context"]!.objectValue!
        let packet: ARCJSONValue = .object(["kind": .string("delta"), "base": .integer(sequence),
            "base_sha256": baseline["sha256"]!, "set": .object(["done": .boolean(true)]), "remove": .array([.string("count")])])
        let second = try f.send(0, to: 1, packet)
        let resolved = try f.read(1, sequence: second.eventSequences[0]).objectValue!["context"]!.objectValue!
        XCTAssertEqual(resolved["fields"], .object(["done": .boolean(true)]))
        XCTAssertEqual(resolved["delta_depth"], .integer(1))
        XCTAssertEqual(try f.read(0, sequence: sequence).objectValue!["context"], .object(baseline))
        XCTAssertThrowsError(try f.send(0, to: 1, packet), "stale base")
        _ = try f.send(1, to: 0, .object(["kind": .string("reference"), "sequence": .integer(second.eventSequences[0]), "sha256": resolved["sha256"]!]))
        let reopened = ARCStore(rootURL: f.root, knowledgeSHA256: String(repeating: "a", count: 64))
        XCTAssertEqual(try reopened.terseRead(room: f.room, participant: f.ids[1], binding: f.bindings[1], sequence: sequence).objectValue!["context"], .object(baseline))
        XCTAssertTrue(try f.store.diagnose(room: f.room).valid)
    }

    func testDeltaRejectsTamperingNoOpsMissingRemovalsAndForeignOwners() throws {
        let f = try Fixture(); defer { f.cleanup() }; try f.handshake()
        let first = try f.send(0, to: 1, json(#"{"kind":"context","key":"x","fields":{"n":1}}"#)).eventSequences[0]
        let digest = try f.read(0, sequence: first).objectValue!["context"]!.objectValue!["sha256"]!
        var delta: [String: ARCJSONValue] = ["kind": .string("delta"), "base": .integer(first), "base_sha256": digest, "set": .object(["n": .integer(1)]), "remove": .array([])]
        XCTAssertThrowsError(try f.send(0, to: 1, .object(delta)))
        delta["set"] = .object(["n": .integer(2)])
        XCTAssertThrowsError(try f.send(1, to: 0, .object(delta)))
        delta["base_sha256"] = .string(String(repeating: "0", count: 64))
        XCTAssertThrowsError(try f.send(0, to: 1, .object(delta)))
        delta["base_sha256"] = digest; delta["remove"] = .array([.string("absent")])
        XCTAssertThrowsError(try f.send(0, to: 1, .object(delta)))
        delta["remove"] = .array([])
        _ = try f.send(0, to: 1, .object(delta))
    }

    func testDeltaChainHasHardLimitAndFullSnapshotResetsIt() throws {
        let f = try Fixture(); defer { f.cleanup() }; try f.handshake()
        var seq = try f.send(0, to: 1, json(#"{"kind":"context","key":"x","fields":{"n":0}}"#)).eventSequences[0]
        for n in 1...64 {
            let digest = try f.read(0, sequence: seq).objectValue!["context"]!.objectValue!["sha256"]!
            seq = try f.send(0, to: 1, .object(["kind": .string("delta"), "base": .integer(seq),
                "base_sha256": digest, "set": .object(["n": .integer(Int64(n))]), "remove": .array([])])).eventSequences[0]
        }
        let resolved = try f.read(1, sequence: seq).objectValue!["context"]!.objectValue!
        XCTAssertEqual(resolved["fields"], .object(["n": .integer(64)]))
        XCTAssertThrowsError(try f.send(0, to: 1, .object(["kind": .string("delta"), "base": .integer(seq),
            "base_sha256": resolved["sha256"]!, "set": .object(["n": .integer(65)]), "remove": .array([])])))
        let fresh = try f.send(0, to: 1, json(#"{"kind":"context","key":"x","fields":{"n":65}}"#)).eventSequences[0]
        XCTAssertEqual(try f.read(1, sequence: fresh).objectValue!["context"]?.objectValue?["delta_depth"], .integer(0))
        XCTAssertTrue(try f.store.diagnose(room: f.room).valid)
    }

    func testDamagedSpecificationStopsTrackedSendAndRead() throws {
        let f = try Fixture(); defer { f.cleanup() }; try f.handshake()
        try Data("damaged".utf8).write(to: ARCCommunication.specificationURL(rootURL: f.root))
        XCTAssertThrowsError(try f.read(0)) { XCTAssertEqual(($0 as? ARCError)?.code, .knowledgeUnavailable) }
        XCTAssertThrowsError(try f.send(0, to: 1, f.declaration())) { XCTAssertEqual(($0 as? ARCError)?.code, .knowledgeUnavailable) }
    }

    func testBatchPartialRepliesAndDistinctAcknowledgements() throws {
        let f = try Fixture(); defer { f.cleanup() }; try f.handshake()
        let batch = try f.send(0, to: 1, json(#"{"kind":"batch","items":[{"id":"a","text":"ASK YOU DONE WORK\n"},{"id":"b","text":"ASK YOU SEE WORK\n"}]}"#)).eventSequences[0]
        for status in ["received", "understood", "agree", "disagree", "blocked"] {
            _ = try f.send(1, to: 0, .object(["kind": .string("reply"), "batch": .integer(batch),
                "answers": .array([.object(["id": .string("a"), "status": .string(status)])])]))
        }
        let invalid: ARCJSONValue = .object(["kind": .string("reply"), "batch": .integer(batch),
            "answers": .array([.object(["id": .string("missing"), "status": .string("agree")])])])
        XCTAssertThrowsError(try f.send(1, to: 0, invalid))
        XCTAssertThrowsError(try f.send(0, to: 1, invalid))
    }

    func testBlankAndProseReferencesRejectedButDiscussionAllowed() throws {
        let f = try Fixture(); defer { f.cleanup() }; try f.handshake()
        let sent = try f.act(0, .message(to: f.ids[1], text: "TELL HEAR\n\n[en] A layout test.\n"))
        let seq = sent.eventSequences[0]
        for line in [2, 3, 99] {
            XCTAssertThrowsError(try f.send(1, to: 0, .object(["kind": .string("lines"), "text": .string("TELL \"\(seq).\(line)\" GOOD\n")])))
        }
        _ = try f.send(1, to: 0, .object(["kind": .string("lines"), "text": .string("TELL HEAR \"\(seq).1\"\n")]))
        _ = try f.send(1, to: 0, .object(["kind": .string("lines"), "text": .string("[en] The reference \"\(seq).2\" names layout.\n")]))
    }

    func testPrivatePacketsDoNotLeakToThirdParticipantOrThroughReferences() throws {
        let f = try Fixture(); defer { f.cleanup() }; try f.handshake()
        let seq = try f.send(0, to: 1, json(#"{"kind":"context","key":"private","fields":{"n":1}}"#)).eventSequences[0]
        try f.addPeer()
        XCTAssertThrowsError(try f.read(2, sequence: seq))
        let poll = try f.store.poll(room: f.room, participant: f.ids[2], binding: f.bindings[2])
        XCTAssertFalse(poll.events.contains { $0.sequence == seq })
        _ = try f.send(0, to: 2, f.declaration()); _ = try f.send(2, to: 0, f.declaration())
        let hash = try f.read(0, sequence: seq).objectValue!["context"]!.objectValue!["sha256"]!
        XCTAssertThrowsError(try f.send(0, to: 2, .object(["kind": .string("reference"), "sequence": .integer(seq), "sha256": hash])))
    }

    func testExactReplayAndReadOnlyStatusDoNotConsumeTokensOrRenewDuty() throws {
        let f = try Fixture(); defer { f.cleanup() }; try f.handshake()
        let packet = try json(#"{"kind":"results","subject":"suite","checks":[{"id":"a","status":"fail","basis":"verified"}]}"#)
        let token = f.operations[0]
        let result = try f.send(0, to: 1, packet)
        let replay = try f.store.act(room: f.room, participant: f.ids[0], binding: f.bindings[0], operation: token, request: .terseSend(to: f.ids[1], packet: packet))
        XCTAssertEqual(result, replay)
        let before = try Data(contentsOf: f.store.roomFileURL(room: f.room))
        _ = try f.read(0)
        XCTAssertEqual(try Data(contentsOf: f.store.roomFileURL(room: f.room)), before)
        f.clock.advance(180)
        XCTAssertThrowsError(try f.send(0, to: 1, packet))
        _ = try f.store.participantRetire(room: f.room, participant: f.ids[0], operationID: UUID())
        XCTAssertThrowsError(try f.read(0)) { XCTAssertEqual(($0 as? ARCError)?.code, .retired) }
    }

    func testScorecardSeparatesEstimatesAndIncludesFailureCost() throws {
        let actualT = run(pair: "a", variant: "terse", correct: false, cost: 200)
        let actualE = run(pair: "a", variant: "english", correct: true, cost: 100)
        let estimateT = run(pair: "b", variant: "terse", correct: true, cost: 20, basis: "estimate")
        let estimateE = run(pair: "b", variant: "english", correct: true, cost: 100, basis: "estimate")
        let score = try ARCTerse.score(.object(["runs": .array([actualT, actualE, estimateT, estimateE])])).objectValue!
        XCTAssertEqual(score["paired_tasks"], .integer(2))
        XCTAssertEqual(score["totals"]?.objectValue?["reported_actual:terse"]?.objectValue?["cost_per_correct_microusd"], .null)
        XCTAssertEqual(score["comparisons"]?.objectValue?["reported_actual"]?.objectValue?["lower_cost_without_observed_accuracy_loss"], .boolean(false))
        XCTAssertEqual(score["comparisons"]?.objectValue?["estimate"]?.objectValue?["cost_difference_microusd"], .integer(-80))
    }
    func testScorecardRejectsUnpairedIncompleteDoubleCountedOrMixedBasisRuns() throws {
        let t = run(pair: "a", variant: "terse", correct: true, cost: 10)
        let e = run(pair: "a", variant: "english", correct: true, cost: 20)
        XCTAssertThrowsError(try ARCTerse.score(.object(["runs": .array([t])])))
        XCTAssertThrowsError(try ARCTerse.score(.object(["runs": .array([t, t, e])])))
        for (key, value): (String, ARCJSONValue) in [("includes_all_costs", .boolean(false)), ("usage_source", .string("estimate")), ("cached_input_tokens", .integer(1001)), ("reasoning_tokens", .integer(101)), ("calls", .integer(0)), ("cost_microusd", .integer(-1))] {
            var altered = t.objectValue!; altered[key] = value
            XCTAssertThrowsError(try ARCTerse.score(.object(["runs": .array([.object(altered), e])])), key)
        }
    }
    private func run(pair: String, variant: String, correct: Bool, cost: Int64, basis: String = "reported_actual") -> ARCJSONValue {
        .object(["pair": .string(pair), "variant": .string(variant), "model": .string("controlled-config"), "correct": .boolean(correct), "usage_source": .string(basis), "includes_all_costs": .boolean(true), "input_tokens": .integer(1000), "output_tokens": .integer(100), "cached_input_tokens": .integer(500), "reasoning_tokens": .integer(50), "cost_microusd": .integer(cost), "calls": .integer(2), "clarifications": .integer(0), "retries": .integer(0)])
    }
}

private final class Fixture {
    let root = URL(fileURLWithPath: "/private/tmp/arc-terse-tests-\(UUID().uuidString)")
    let clock = TerseClock()
    let store: ARCStore
    let room: String
    var ids: [String] = [], bindings: [String] = [], operations: [String] = []
    let digest: String
    init() throws {
        store = ARCStore(rootURL: root, clock: ARCClock { [clock] in clock.now() }, knowledgeSHA256: String(repeating: "a", count: 64))
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: source.appendingPathComponent(ARCCommunication.specificationRelativePath))
        digest = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let spec = ARCCommunication.specificationURL(rootURL: root)
        try FileManager.default.createDirectory(at: spec.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: spec)
        try Data((digest + "\n").utf8).write(to: root.appendingPathComponent("current/" + ARCCommunication.digestRelativePath))
        room = try store.roomCreate(displayName: "Terse isolated", operationID: UUID()).room.id
        try addPeer(); try addPeer()
    }
    func addPeer() throws {
        let i = ids.count
        let invite = try store.participantInvite(room: room, name: "Peer \(i)", operationID: UUID())
        ids.append(invite.participant.id); bindings.append(invite.instructions.bindingReference)
        var poll = try store.poll(room: room, participant: ids[i], binding: bindings[i])
        operations.append(poll.operation)
        if i > 0 {
            _ = try act(0, .qualificationStart(participant: ids[i], producerGeneration: 1))
            poll = try store.poll(room: room, participant: ids[i], binding: bindings[i])
        }
        _ = try act(i, .qualificationAnswer(answer: XCTUnwrap(poll.qualification?.challenge)))
        clock.advance(40)
        XCTAssertEqual(try store.poll(room: room, participant: ids[i], binding: bindings[i]).participant.phase, .qualified)
    }
    func declaration(digest: String? = nil, profiles: [String] = ARCTerse.profiles) -> ARCJSONValue {
        .object(["kind": .string("declare"), "version": .integer(2), "specification_sha256": .string(digest ?? self.digest), "profiles": .array(profiles.map(ARCJSONValue.string))])
    }
    func handshake() throws { _ = try send(0, to: 1, declaration()); _ = try send(1, to: 0, declaration()) }
    func act(_ i: Int, _ request: ARCActionRequest) throws -> ARCActResult {
        let result = try store.act(room: room, participant: ids[i], binding: bindings[i], operation: operations[i], request: request)
        operations[i] = result.nextOperation
        return result
    }
    func send(_ i: Int, to: Int, _ packet: ARCJSONValue) throws -> ARCActResult { try act(i, .terseSend(to: ids[to], packet: packet)) }
    func read(_ i: Int, sequence: Int64? = nil) throws -> ARCJSONValue { try store.terseRead(room: room, participant: ids[i], binding: bindings[i], sequence: sequence) }
    func cleanup() { try? FileManager.default.removeItem(at: root) }
}
private final class TerseClock: @unchecked Sendable {
    private let lock = NSLock()
    private var time = Date(timeIntervalSince1970: 1_800_000_000)
    func now() -> Date { lock.lock(); defer { lock.unlock() }; return time }
    func advance(_ seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; time.addTimeInterval(seconds) }
}
