import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import ARCCore

final class ARCCommunicationTests: XCTestCase {
    private var roots: [URL] = []

    func testGoverningTerseSpecificationReturnsOnlyCompleteVerifiedBytes() throws {
        let root = try temporaryRoot()
        let installation = root.appendingPathComponent("current")
        XCTAssertThrowsError(try ARCCommunication.specificationText(installationURL: installation))
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let full = try String(contentsOf: source.appendingPathComponent(
            ARCCommunication.specificationRelativePath), encoding: .utf8)
        try installSpecification(root: root, text: full)
        XCTAssertEqual(try ARCCommunication.specificationText(installationURL: installation), full)
        XCTAssertTrue(full.contains("Status: Terse v2.0, release candidate"))
        XCTAssertTrue(full.contains("TELL WORD SAME 2"))
        try Data((full + "changed\n").utf8).write(to: ARCCommunication.specificationURL(rootURL: root))
        XCTAssertThrowsError(try ARCCommunication.specificationText(installationURL: installation)) { error in
            XCTAssertEqual((error as? ARCError)?.code, .knowledgeUnavailable)
        }
    }

    func testFallbackIsSenderChosenTerseFirstAndNeverDuplicatedOnEverySurface() throws {
        let root = try temporaryRoot()
        try installSpecification(root: root, text: "Full fixture specification\n")
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let guide = try String(contentsOf: source.appendingPathComponent("docs/ARC_AI.md"), encoding: .utf8)
        let terse = try String(contentsOf: source.appendingPathComponent(ARCCommunication.specificationRelativePath), encoding: .utf8)
        for language in ARCOperatorLanguage.allCases {
            try ARCOperatorPreferences.save(language, rootURL: root)
            let poll = ARCCommunication.snapshot(rootURL: root)
            let setup = ARCCommunication.setupText(rootURL: root, language: language)
            XCTAssertEqual(poll.operatorLanguage, language)
            for text in [poll.notice, setup, guide] {
                XCTAssertTrue(text.contains("Only when it cannot"))
                XCTAssertTrue(text.contains("The sending AI chooses the fallback language, not the Producer."))
                XCTAssertTrue(text.contains("Choose one language per thought, not parallel translations"))
                XCTAssertTrue(text.contains("does not by itself justify avoiding Terse"))
                XCTAssertFalse(text.contains("test may include both"))
                XCTAssertFalse(text.contains("test may deliberately include both"))
            }
        }
        XCTAssertTrue(terse.contains("14.15 In ARC"))
        XCTAssertTrue(terse.contains("The sending AI, not the Producer"))
        XCTAssertTrue(terse.contains("Producer MUST NOT"))
        XCTAssertTrue(terse.contains("each concept\nis expressed only once"))
        XCTAssertFalse(terse.contains("test MAY include translations"))
        XCTAssertTrue(terse.contains("ARC's permitted AI-to-AI prose set is English and German"))
        XCTAssertTrue(terse.contains("These categories are not blanket prose exemptions"))
        XCTAssertFalse(terse.contains("A room MAY declare the set of natural languages"))
        XCTAssertFalse(terse.contains("Der Parser lehnt den Pfad ab"))
    }

    func testTerseCanonicalLineEndingsSurviveActionDecodingAndSafetyLimitsRemain() throws {
        let input = ARCActionRequest.message(to: "ai-012345abcdef", text: "TELL WORD SAME 6\n\nTELL HEAR\n")
        XCTAssertEqual(try ARCActionJSON.decode(ARCActionJSON.encode(input)), input)
        for rejected in ["\n \t\n", "TELL HEAR\u{0}\n", String(repeating: "A", count: 16_384) + "\n"] {
            XCTAssertThrowsError(try ARCActionJSON.decode(ARCActionJSON.encode(
                .message(to: "ai-012345abcdef", text: rejected))))
        }
    }

    override func tearDownWithError() throws {
        for root in roots { try FileManager.default.removeItem(at: root) }
        roots = []
    }

    func testPreferenceDefaultsToEnglishAndPersistsAcrossInstances() throws {
        let root = try temporaryRoot()
        XCTAssertEqual(try ARCOperatorPreferences.load(rootURL: root), .english)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("rooms").path))
        try ARCOperatorPreferences.save(.german, rootURL: root)
        XCTAssertEqual(try ARCOperatorPreferences.load(rootURL: root), .german)
        let file = root.appendingPathComponent(ARCOperatorPreferences.fileName)
        XCTAssertEqual(try Data(contentsOf: file), Data("de\n".utf8))
        let permissions = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? NSNumber
        XCTAssertEqual(permissions?.intValue, 0o600)
        try ARCOperatorPreferences.save(.english, rootURL: root)
        XCTAssertEqual(try ARCOperatorPreferences.load(rootURL: root), .english)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [ARCOperatorPreferences.fileName])
    }

    func testMissingOrDamagedSpecificationProducesExplicitPauseNotice() throws {
        let root = try temporaryRoot()
        let missing = ARCCommunication.snapshot(rootURL: root)
        XCTAssertEqual(missing.status, "unavailable")
        XCTAssertNil(missing.specificationSha256)
        XCTAssertTrue(missing.notice.contains("Pause ARC participation"))
        try installSpecification(root: root, text: "Full test specification\n")
        XCTAssertEqual(ARCCommunication.snapshot(rootURL: root).status, "ready")
        try Data("Changed without digest\n".utf8).write(to: ARCCommunication.specificationURL(rootURL: root))
        XCTAssertEqual(ARCCommunication.snapshot(rootURL: root).status, "unavailable")
    }

    func testPolicyDetectsChangedBytesAndLanguageWithoutRewritingRoomHistory() throws {
        let root = try temporaryRoot()
        try installSpecification(root: root, text: "Vocabulary version 6, original rules\n")
        let store = ARCStore(rootURL: root, knowledgeSHA256: String(repeating: "a", count: 64))
        let room = try store.roomCreate(displayName: "Existing room", operationID: UUID()).room.id
        let invite = try store.participantInvite(room: room, name: "Existing AI", operationID: UUID())
        let before = try store.poll(room: room, participant: invite.participant.id,
            binding: invite.instructions.bindingReference)
        XCTAssertEqual(before.communication.status, "ready")
        XCTAssertEqual(before.communication.operatorLanguage, .english)
        let history = try store.activityRead(room: room).events
        try installSpecification(root: root, text: "Vocabulary version 6, corrected rules\n")
        try ARCOperatorPreferences.save(.german, rootURL: root)
        let reopened = ARCStore(rootURL: root, knowledgeSHA256: String(repeating: "a", count: 64))
        let after = try reopened.poll(room: room, participant: invite.participant.id,
            binding: invite.instructions.bindingReference, after: before.nextAfter)
        XCTAssertNotEqual(before.communication.specificationSha256, after.communication.specificationSha256)
        XCTAssertEqual(after.communication.operatorLanguage, .german)
        XCTAssertEqual(after.communication.specificationPath, "current/" + ARCCommunication.specificationRelativePath)
        XCTAssertFalse(after.communication.specificationPath.contains(root.path))
        XCTAssertEqual(try store.activityRead(room: room).events, history)
        XCTAssertTrue(after.events.isEmpty)
        XCTAssertTrue(after.communication.notice.contains("whenever specification_sha256 changes"))
        XCTAssertTrue(after.communication.notice.contains("that specific thought or concept"))
        XCTAssertTrue(after.communication.notice.contains(ARCCommunication.languagePolicy))
        XCTAssertEqual(after.participant.id, before.participant.id)
    }

    func testPauseNoticeHasExplicitNullDigestInMachineOutput() throws {
        let notice = ARCCommunication.snapshot(rootURL: try temporaryRoot())
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(notice)) as? [String: Any])
        XCTAssertEqual(Set(object.keys), ["status", "specification_path", "specification_sha256", "operator_language", "notice"])
        XCTAssertTrue(object["specification_sha256"] is NSNull)
        XCTAssertEqual(object["operator_language"] as? String, "en")
    }

    func testPreferenceRefusesLinksHardLinksAndMalformedValues() throws {
        let root = try temporaryRoot()
        let outside = root.appendingPathComponent("outside.txt")
        let setting = root.appendingPathComponent(ARCOperatorPreferences.fileName)
        try Data("do not change\n".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: setting, withDestinationURL: outside)
        XCTAssertThrowsError(try ARCOperatorPreferences.load(rootURL: root))
        XCTAssertThrowsError(try ARCOperatorPreferences.save(.german, rootURL: root))
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "do not change\n")
        try FileManager.default.removeItem(at: setting)
        XCTAssertEqual(link(outside.path, setting.path), 0)
        XCTAssertThrowsError(try ARCOperatorPreferences.save(.german, rootURL: root))
        try FileManager.default.removeItem(at: setting)
        try Data("fr\n".utf8).write(to: setting)
        XCTAssertThrowsError(try ARCOperatorPreferences.load(rootURL: root))
        XCTAssertEqual(ARCCommunication.snapshot(rootURL: root).status, "unavailable")
    }

    func testSpecificationRefusesSymlinksHardLinksAndOversizedFiles() throws {
        let root = try temporaryRoot()
        try installSpecification(root: root, text: "Test specification\n")
        let spec = ARCCommunication.specificationURL(rootURL: root)
        let outside = root.appendingPathComponent("outside-spec.txt")
        try FileManager.default.moveItem(at: spec, to: outside)
        try FileManager.default.createSymbolicLink(at: spec, withDestinationURL: outside)
        XCTAssertEqual(ARCCommunication.snapshot(rootURL: root).status, "unavailable")
        try FileManager.default.removeItem(at: spec)
        XCTAssertEqual(link(outside.path, spec.path), 0)
        XCTAssertEqual(ARCCommunication.snapshot(rootURL: root).status, "unavailable")
        try FileManager.default.removeItem(at: spec)
        try Data(repeating: 65, count: 524_289).write(to: spec)
        XCTAssertEqual(ARCCommunication.snapshot(rootURL: root).status, "unavailable")
    }

    func testGuidanceDoesNotClaimAuthorityEnforcementOrGuaranteedSavings() throws {
        let text = ARCCommunication.setupText(rootURL: try temporaryRoot(), language: .german)
        for required in ["entire file", "all sections and appendices", "section 19",
            "choose English or German", "specific thought", "tag each prose line [en] or [de]",
            "operator use Deutsch", "take precedence", "validates structured packets",
            "not measured guarantees", "reread the whole local specification"] {
            XCTAssertTrue(text.contains(required), required)
        }
        XCTAssertTrue(text.contains(ARCCommunication.languagePolicy))
        XCTAssertTrue(text.contains("Choose one language per thought, not parallel translations"))
        XCTAssertTrue(text.contains("Do not provide both translations to the operator"))
    }

    private func temporaryRoot() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp", isDirectory: true)
            .appendingPathComponent("arc-communication-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        roots.append(root)
        return root
    }

    private func installSpecification(root: URL, text: String) throws {
        let spec = ARCCommunication.specificationURL(rootURL: root)
        try FileManager.default.createDirectory(at: spec.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(text.utf8)
        try data.write(to: spec, options: .atomic)
        let digest = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        try Data((digest + "\n").utf8).write(to: root.appendingPathComponent("current")
            .appendingPathComponent(ARCCommunication.digestRelativePath), options: .atomic)
    }
}
