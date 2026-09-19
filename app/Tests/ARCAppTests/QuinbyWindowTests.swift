import AppKit
import Combine
import SwiftUI
import XCTest
@testable import ARCApp
@testable import ARCCore

final class QuinbyWindowTests: XCTestCase {
    @MainActor
    func testRefreshGapRemainsReachableThroughEarlierHistory() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc-corner-gap-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = QuinbyStore(rootURL: root, clock: .system, seed: "Starting Quinby")
        _ = try store.snapshot()
        let model = QuinbyWindowState(root: root)
        await model.refresh()
        XCTAssertNil(model.nextBefore)
        for n in 0..<120 { try store.setEnabled(n % 2 == 0, operation: UUID()) }
        await model.refresh()
        XCTAssertNotNil(model.nextBefore)
        XCTAssertNotNil(model.historyGapThrough, "The transcript must disclose its missing interval")
        let host = NSHostingView(rootView: QuinbyContentView(root: root, model: model)
            .frame(width: 820, height: 840).background(Color.white).environment(\.colorScheme, .light))
        host.frame = NSRect(x: 0, y: 0, width: 820, height: 840)
        host.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: bitmap)
        let output = URL(fileURLWithPath: "/private/tmp/arc-release-review-visuals")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            .write(to: output.appendingPathComponent("quinby-history-gap.png"))
        for _ in 0..<10 {
            if model.nextBefore == nil { break }
            model.earlier()
            for _ in 0..<200 {
                if !model.busy { break }
                try await Task.sleep(for: .milliseconds(10))
            }
            XCTAssertFalse(model.busy)
        }
        XCTAssertNil(model.nextBefore)
        XCTAssertNil(model.historyGapThrough)
        XCTAssertEqual(model.history.map(\.sequence), Array(Int64(1)...Int64(121)))
        XCTAssertTrue(model.error.isEmpty)
    }

    /// 014 QC-006 and QC-016 item 15: a send while Quinby is off is refused
    /// without an error, the draft survives, and the status says why.
    @MainActor
    func testSendWhileOffIsRefusedWithoutErrorAndKeepsTheDraft() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc3-corner-send-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = QuinbyStore(rootURL: root, clock: .system, seed: "Starting Quinby")
        _ = try store.snapshot()
        let model = QuinbyWindowState(root: root)
        await model.refresh()
        XCTAssertEqual(model.snapshot?.status, "Quinby is off.")
        model.message = "Hello, Quinby"
        model.send()
        try await Task.sleep(for: .milliseconds(250))
        XCTAssertEqual(model.message, "Hello, Quinby", "the draft is preserved")
        XCTAssertTrue(model.error.isEmpty, "an unavailable send is not an error")
        XCTAssertFalse(model.busy)
        model.message = "   \n"
        model.send()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertFalse(model.busy, "a blank draft is never submitted")
    }

    /// 014 QC-014 and QC-016 item 16: an action error survives background
    /// refreshes, and an unchanged record publishes nothing.
    @MainActor
    func testRefreshKeepsActionErrorAndPublishesOnlyChanges() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc3-corner-refresh-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = QuinbyStore(rootURL: root, clock: .system, seed: "Starting Quinby")
        _ = try store.snapshot()
        let model = QuinbyWindowState(root: root)
        await model.refresh()
        XCTAssertNotNil(model.snapshot)
        model.error = "Send failed"
        var publications = 0
        let subscription = model.objectWillChange.sink { _ in publications += 1 }
        defer { subscription.cancel() }
        await model.refresh()
        await model.refresh()
        XCTAssertEqual(model.error, "Send failed", "refresh must not clear an action error")
        XCTAssertEqual(publications, 0, "an unchanged record republishes nothing")
        XCTAssertEqual(model.displayError, "Send failed")
    }

    /// 014 QC-014 and QC-016 item 17: times render locally and a value that
    /// is not a recorded timestamp is shown unchanged.
    @MainActor
    func testTimesRenderLocallyAndUnparseableValuesPassThrough() throws {
        let today = ARCTime.timestamp(try ARCTime.logicalUS(Date()))
        let shownToday = QuinbyContentView.displayTime(today)
        XCTAssertFalse(shownToday.isEmpty)
        XCTAssertNotEqual(shownToday, today)
        let old = "2020-01-02T03:04:05.123456Z"
        let shownOld = QuinbyContentView.displayTime(old)
        XCTAssertNotEqual(shownOld, old)
        XCTAssertGreaterThan(shownOld.count, shownToday.count, "an older entry also shows its date")
        XCTAssertEqual(QuinbyContentView.displayTime("not a time"), "not a time")
    }

    @MainActor
    func testCornerRendersCanonAndKeepsDisabledChatHonestInBothAppearances() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc3-corner-window-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let assets = root.appendingPathComponent("current/quinby")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        for name in ["initial-profile.json", "quinby-headshot.png"] {
            try FileManager.default.copyItem(at: source.appendingPathComponent("docs/quinbys-corner/\(name)"),
                to: assets.appendingPathComponent(name))
        }
        let model = QuinbyWindowState(root: root)
        await model.refresh()
        XCTAssertFalse(try XCTUnwrap(model.snapshot).listening)
        XCTAssertFalse(try XCTUnwrap(model.snapshot).enabled)
        XCTAssertTrue(model.snapshot?.summary?.text.contains("Calm, well-read") == true)
        XCTAssertTrue(model.error.isEmpty)
        let output = URL(fileURLWithPath: "/private/tmp/arc-build-3.2.2/visuals")
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
            let host = NSHostingView(rootView: QuinbyContentView(root: root, model: model)
                .environment(\.colorScheme, name == "dark" ? .dark : .light))
            host.frame = NSRect(x: 0, y: 0, width: 820, height: 840)
            host.appearance = NSAppearance(named: appearance)
            host.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
            host.cacheDisplay(in: host.bounds, to: bitmap)
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            XCTAssertGreaterThan(png.count, 10_000)
            try png.write(to: output.appendingPathComponent("quinby-\(name).png"))
        }
    }

    @MainActor
    func testCornerWindowClearsOldIdentityAfterReincarnation() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc3-corner-reset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let store = QuinbyStore(rootURL: root, clock: .system, seed: "Starting Quinby")
        let previous = try store.snapshot()
        _ = try store.invite(name: "Old AI", operation: UUID())
        let model = QuinbyWindowState(root: root)
        await model.refresh()
        XCTAssertEqual(model.snapshot?.participants.count, 1)
        model.message = "Unsent old conversation"
        try store.reincarnate(incarnation: previous.incarnation, operation: UUID())
        _ = try store.snapshot()
        await model.refresh()
        XCTAssertNotEqual(model.snapshot?.incarnation, previous.incarnation)
        XCTAssertTrue(model.snapshot?.participants.isEmpty == true)
        XCTAssertEqual(model.message, "")
        XCTAssertFalse(model.history.contains { $0.text == "Old AI" })
    }

    @MainActor
    func testResetWorksWhenCorruptionPreventsTheFirstSnapshot() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc-corner-corrupt-reset-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let assets = root.appendingPathComponent("current/quinby")
        try FileManager.default.createDirectory(at: assets, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: source.appendingPathComponent("docs/quinbys-corner/initial-profile.json"),
            to: assets.appendingPathComponent("initial-profile.json"))
        let store = QuinbyStore(rootURL: root)
        let old = try store.snapshot()
        let record = root.appendingPathComponent("quinby/records.arcquinby")
        var bytes = try Data(contentsOf: record)
        bytes[30] ^= 1
        try bytes.write(to: record)
        let model = QuinbyWindowState(root: root)
        await model.refresh()
        XCTAssertNil(model.snapshot)
        XCTAssertFalse(model.displayError.isEmpty)
        model.reset()
        for _ in 0..<200 {
            if model.snapshot != nil && !model.busy { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertNotEqual(try XCTUnwrap(model.snapshot).incarnation, old.incarnation)
        XCTAssertFalse(try XCTUnwrap(model.snapshot).enabled)
        XCTAssertTrue(model.displayError.isEmpty)
        XCTAssertEqual(model.history.map(\.kind), ["seed"])
    }
}
