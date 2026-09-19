import Foundation
import XCTest
@testable import ARCCore

final class MeterTests: XCTestCase {
    func testConcurrentWritersPreserveEveryLaneCount() throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc-meter-test-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        DispatchQueue.concurrentPerform(iterations: 100) { n in
            ARCMeter.note(root: root, room: "room-123456abcdef",
                          participant: "lane-\(n % 4)", now: 1_800_000_000_000_000, polls: 1, bytes: 100)
        }
        let counts = ARCMeter.usage(root: root, room: "room-123456abcdef", now: 1_800_000_000_000_000)
        XCTAssertEqual(counts.count, 4)
        for count in counts.values {
            XCTAssertEqual(count.pollsTotal, 25)
            XCTAssertEqual(count.bytesServedTotal, 2_500)
        }
    }
}
