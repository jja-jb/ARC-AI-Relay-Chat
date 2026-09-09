import Foundation
import XCTest
@testable import ARCDevTool

final class ARCDevToolTests: XCTestCase {
    func testBundledTerseIsTheCompleteReviewedVersionSevenAndDigestIsChecked() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let bytes = try Data(contentsOf: source.appendingPathComponent(ARCReleaseSupport.terseSpecification))
        XCTAssertEqual(KnowledgeContainer.hex(KnowledgeContainer.sha256(bytes)),
            "92f98cfdce3a6fbfbcb37bd93e8d9776bb5db54dbff1079f559c037e7203bb83")
        let specification = String(decoding: bytes, as: UTF8.self)
        for section in ["4.14 Explicit focus", "4.15 A receiver", "13.10 Enumerating",
            "14.14 One thought", "19. Entering a room", "Appendix A", "Appendix B", "Appendix C"] {
            XCTAssertTrue(specification.contains(section), section)
        }
        XCTAssertTrue(specification.contains("TELL WORD SAME 7"))
        XCTAssertFalse(specification.contains("TELL WORD SAME 6"))
        XCTAssertFalse(specification.contains("SEE TELL FILE GOOD"))
        XCTAssertFalse(specification.contains("two participants that state the same claim therefore produce identical bytes"))
        let root = URL(fileURLWithPath: "/private/tmp/arc-terse-bundle-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let text = root.appendingPathComponent(ARCReleaseSupport.terseSpecification)
        let digest = root.appendingPathComponent(ARCReleaseSupport.terseDigest)
        try FileManager.default.createDirectory(at: text.deletingLastPathComponent(), withIntermediateDirectories: true)
        try bytes.write(to: text)
        XCTAssertThrowsError(try ARCReleaseSupport.checkTersePayload(root))
        try Data((KnowledgeContainer.hex(KnowledgeContainer.sha256(bytes)) + "\n").utf8).write(to: digest)
        XCTAssertNoThrow(try ARCReleaseSupport.checkTersePayload(root))
        try Data((String(repeating: "0", count: 64) + "\n").utf8).write(to: digest)
        XCTAssertThrowsError(try ARCReleaseSupport.checkTersePayload(root))
    }
    func testReleaseValidationCannotHideAStageFailureBehindCleanup() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let makefile = try String(contentsOf: root.appendingPathComponent("Makefile"), encoding: .utf8)
        let section = try XCTUnwrap(makefile.components(separatedBy: "release-prepared-check:").last)
            .components(separatedBy: "\nrelease-seal:")[0]
        let start = try XCTUnwrap(section.range(of: "\t@"))
        var recipe = String(section[start.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "$$", with: "$")
        for command in ["mktemp", "hdiutil", "codesign", "xcrun", "lipo", "tar"] {
            recipe = recipe.replacingOccurrences(of: "/usr/bin/\(command)", with: command)
        }
        recipe = recipe.replacingOccurrences(of: "/usr/sbin/spctl", with: "spctl")
            .replacingOccurrences(of: "/bin/mkdir", with: ":")
            .replacingOccurrences(of: "/bin/rm", with: ":")
            .replacingOccurrences(of: "$(ARC_DEV)", with: "arcdev")
        for variable in ["CANDIDATE_DMG", "CANDIDATE_SOURCE", "VERSION"] {
            recipe = recipe.replacingOccurrences(of: "$(\(variable))", with: "fixture")
        }
        // Stub only external programs. Execute the actual recipe's shell
        // sequencing, tests, traps, and final cleanup, without mounting/signing.
        let stubs = """
        stub() { [ "$1" != "$FAIL_STAGE" ]; }
        mktemp() { printf '%s\\n' /unused-arc-fixture; }
        hdiutil() { stub "$1"; }
        arcdev() { stub "$1"; }
        codesign() { stub codesign; }
        spctl() { stub spctl; }
        xcrun() { stub stapler; }
        lipo() { stub lipo || return 1; printf arm64; }
        tar() { stub tar; }
        """
        for stage in ["success", "attach", "app-check", "codesign", "spctl", "stapler", "lipo", "detach", "tar", "source-check"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sh")
            process.arguments = ["-c", stubs + "\n" + recipe]
            process.environment = ["FAIL_STAGE": stage]
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run()
            process.waitUntilExit()
            if stage == "success" { XCTAssertEqual(process.terminationStatus, 0) }
            else { XCTAssertNotEqual(process.terminationStatus, 0, stage) }
        }
    }

    func testHostileUnsignedGeometryIsRejectedWithoutIntegerTrap() throws {
        var valid = KnowledgeContainer.magic
        func append<T: FixedWidthInteger>(_ value: T) {
            var big = value.bigEndian
            withUnsafeBytes(of: &big) { valid.append(contentsOf: $0) }
        }
        append(UInt32(1)); append(UInt32(1))
        append(UInt32(18)); append(UInt32(160))
        append(UInt64(64)); append(UInt64(18 * 160))
        append(UInt64(64 + 18 * 160)); append(UInt64(64 + 18 * 160))
        append(UInt64(0))
        valid.append(Data(repeating: 0, count: 18 * 160))
        for offset in [24, 32, 40, 48, 72, 80] {
            for value in [UInt64.max, UInt64(Int.max) + 1, UInt64(Int.max)] {
                var damaged = valid
                var big = value.bigEndian
                withUnsafeBytes(of: &big) { damaged.replaceSubrange(offset..<(offset + 8), with: $0) }
                XCTAssertThrowsError(try KnowledgeContainer.parse(damaged), "offset \(offset), value \(value)")
            }
        }
    }
}
