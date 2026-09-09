import AppKit
import ARCCore
import XCTest
@testable import ARCApp

final class ARCActivityWindowTests: XCTestCase {
    func testParticipantColorsAndEventLabelsAreStable() {
        XCTAssertEqual(ARCTranscriptPresentation.colorIndex(for: "ai-1"),
            ARCTranscriptPresentation.colorIndex(for: "ai-1"))
        XCTAssertGreaterThan(Set((1...64).map {
            ARCTranscriptPresentation.colorIndex(for: "ai-\($0)")
        }).count, 6)
        XCTAssertEqual(ARCTranscriptPresentation.category(for: "MESSAGE"), "Message")
        XCTAssertEqual(ARCTranscriptPresentation.category(for: "TERSE_MESSAGE"), "Message")
        XCTAssertEqual(ARCTranscriptPresentation.category(for: "WORK_UPDATED"), "Work")
        XCTAssertEqual(ARCTranscriptPresentation.category(for: "AI_WORKING"), "Duty")
        XCTAssertEqual(ARCTranscriptPresentation.category(for: "QUALIFICATION_FAILED"), "Access check")
        XCTAssertEqual(ARCTranscriptPresentation.category(for: "FUTURE_EVENT"), "Room event")
    }

    @MainActor
    func testMessagesAreReadableLiteralTextAndOtherEventsKeepTheirPayloads() {
        let packet: ARCJSONValue = .object(["kind": .string("dependency"), "subject": .string("package"), "requires": .array([.string("tests")])])
        let structured = ARCEventView(sequence: 9, at: "2026-09-09T00:00:00Z", logicalUs: 9,
            kind: "TERSE_MESSAGE", actor: "ai-1", recipient: "ai-2", subject: nil,
            payload: .object(["packet": packet]), operationId: "test", knowledgeSha256: "test")
        let packetText = ARCTranscriptPresentation.entry(structured, participants: [:], fontSize: 13).string
        XCTAssertTrue(packetText.contains("@terse/2 "))
        XCTAssertTrue(packetText.contains("\"dependency\""))
        XCTAssertFalse(packetText.contains("binding_generation"))
        let hostileText = "<script>alert('no')</script> **literal** https://example.com\nSecond line"
        let event = event(1, text: hostileText)
        let rendered = ARCTranscriptPresentation.entry(event, participants: [:], fontSize: 13)
        XCTAssertTrue(rendered.string.contains(hostileText))
        XCTAssertTrue(rendered.string.contains("Message · ai-1 → ai-2"))
        XCTAssertFalse(rendered.string.contains("\\nSecond line"))
        rendered.enumerateAttribute(.link, in: NSRange(location: 0, length: rendered.length)) { value, _, _ in
            XCTAssertNil(value)
        }
        let system = ARCEventView(sequence: 2, at: "2026-09-08T12:00:00Z", logicalUs: 2,
            kind: "FUTURE_EVENT", actor: "arc", recipient: nil, subject: "work-1",
            payload: .object(["detail": .string("Complete event evidence"), "time_verified": .boolean(false)]),
            operationId: "test", knowledgeSha256: "test")
        let systemText = ARCTranscriptPresentation.entry(system, participants: [:], fontSize: 13).string
        XCTAssertTrue(systemText.contains("FUTURE_EVENT"))
        XCTAssertTrue(systemText.contains("Complete event evidence"))
        XCTAssertTrue(systemText.contains("Subject: work-1"))
        XCTAssertTrue(systemText.contains("Time unavailable"))
    }

    @MainActor
    func testHistoricalWorkingDeadlineUsesEventTimeNotCurrentTime() {
        let working = ARCEventView(sequence: 1, at: "2020-01-01T12:00:00Z", logicalUs: 1_000_000,
            kind: "AI_WORKING", actor: "ai-1", recipient: nil, subject: "ai-1",
            payload: .object(["until_logical_us": .integer(601_000_000)]),
            operationId: "test", knowledgeSha256: "test")
        let expected = Date(timeIntervalSince1970: 1_577_880_600)
            .formatted(date: .abbreviated, time: .standard)
        XCTAssertEqual(ARCFormatting.recordedLogicalTime(601_000_000, event: working), expected)
        XCTAssertTrue(ARCTranscriptPresentation.entry(working, participants: [:], fontSize: 13)
            .string.contains("Working until \(expected)"))
    }

    @MainActor
    func testParticipantAccentTextHasReadableContrastInBothAppearances() throws {
        for name in [NSAppearance.Name.aqua, .darkAqua] {
            let appearance = try XCTUnwrap(NSAppearance(named: name))
            appearance.performAsCurrentDrawingAppearance {
                func luminance(_ color: NSColor) -> Double {
                    let rgb = color.usingColorSpace(.sRGB)!
                    func linear(_ value: CGFloat) -> Double {
                        let value = Double(value)
                        return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
                    }
                    return 0.2126 * linear(rgb.redComponent) + 0.7152 * linear(rgb.greenComponent)
                        + 0.0722 * linear(rgb.blueComponent)
                }
                let background = luminance(.textBackgroundColor)
                for color in ARCTranscriptPresentation.participantColors {
                    let foreground = luminance(color)
                    let contrast = (max(foreground, background) + 0.05) / (min(foreground, background) + 0.05)
                    XCTAssertGreaterThanOrEqual(contrast, 4.5, "\(name): participant labels need readable text contrast")
                }
            }
        }
    }

    @MainActor
    func testFindRequestOpensNativeSearchWithoutMakingTextEditable() {
        let coordinator = ActivityTranscript.Coordinator()
        let scroll = coordinator.makeScrollView()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        window.contentView = scroll
        scroll.layoutSubtreeIfNeeded()
        coordinator.update(input(1...50), in: scroll)
        var request = input(1...50)
        request.findRequest = 1
        coordinator.update(request, in: scroll)
        XCTAssertTrue(scroll.isFindBarVisible)
        XCTAssertFalse(coordinator.textView.isEditable)
    }

    @MainActor
    func testTranscriptIsReadOnlySelectableAndSupportsFind() {
        let coordinator = ActivityTranscript.Coordinator()
        _ = coordinator.makeScrollView()
        XCTAssertFalse(coordinator.textView.isEditable)
        XCTAssertTrue(coordinator.textView.isSelectable)
        XCTAssertTrue(coordinator.textView.usesFindBar)
        XCTAssertFalse(coordinator.textView.importsGraphics)
        XCTAssertFalse(coordinator.textView.isAutomaticLinkDetectionEnabled)
        XCTAssertFalse(coordinator.textView.isAutomaticDataDetectionEnabled)
    }

    @MainActor
    func testFollowLiveAndPausedAppendAndPrependPreserveReadingPosition() {
        let coordinator = ActivityTranscript.Coordinator()
        let scroll = coordinator.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
        scroll.layoutSubtreeIfNeeded()
        coordinator.update(input(51...100), in: scroll)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 1_000)
        XCTAssertEqual(scroll.contentView.bounds.maxY, coordinator.textView.frame.maxY, accuracy: 2)

        scroll.contentView.scroll(to: NSPoint(x: 0, y: 600))
        let pausedY = scroll.contentView.bounds.minY
        coordinator.textView.setSelectedRange(NSRange(location: 150, length: 20))
        let selectedText = (coordinator.textView.string as NSString).substring(with: coordinator.textView.selectedRange())
        coordinator.update(input(51...110, follow: false), in: scroll)
        XCTAssertEqual(scroll.contentView.bounds.minY, pausedY, accuracy: 2)
        XCTAssertTrue(coordinator.textView.string.contains("Message 110"))

        let beforePrepend = scroll.contentView.bounds.minY
        coordinator.update(input(1...110, follow: false), in: scroll)
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, beforePrepend + 1_000)
        XCTAssertEqual((coordinator.textView.string as NSString).substring(with: coordinator.textView.selectedRange()), selectedText)
        let preservedY = scroll.contentView.bounds.minY
        coordinator.update(input(1...111, follow: false), in: scroll)
        XCTAssertEqual(scroll.contentView.bounds.minY, preservedY, accuracy: 2)

        coordinator.update(input(1...111), in: scroll)
        XCTAssertEqual(scroll.contentView.bounds.maxY, coordinator.textView.frame.maxY, accuracy: 2)
        coordinator.update(input(1...112), in: scroll)
        XCTAssertEqual(scroll.contentView.bounds.maxY, coordinator.textView.frame.maxY, accuracy: 2)
    }

    @MainActor
    func testEarlierPageDoesNotJumpToBottomWhileFollowLiveIsOn() {
        let coordinator = ActivityTranscript.Coordinator()
        let scroll = coordinator.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
        scroll.layoutSubtreeIfNeeded()
        coordinator.update(input(51...100), in: scroll)
        scroll.contentView.scroll(to: NSPoint(x: 0, y: 200))
        coordinator.update(input(1...100), in: scroll)
        XCTAssertLessThan(scroll.contentView.bounds.maxY, coordinator.textView.frame.maxY - 1_000)
    }

    @MainActor
    func testRoomChangeReplacesTranscriptAndStartsAtNewestEvenWhenPaused() {
        let coordinator = ActivityTranscript.Coordinator()
        let scroll = coordinator.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
        scroll.layoutSubtreeIfNeeded()
        coordinator.update(input(1...50, room: "one", follow: false), in: scroll)
        scroll.contentView.scroll(to: .zero)
        coordinator.update(input(101...150, room: "two", follow: false), in: scroll)
        XCTAssertFalse(coordinator.textView.string.contains("Message 50\n"))
        XCTAssertTrue(coordinator.textView.string.contains("Message 150\n"))
        XCTAssertEqual(scroll.contentView.bounds.maxY, coordinator.textView.frame.maxY, accuracy: 2)
        XCTAssertEqual(coordinator.textView.selectedRange().length, 0)
    }

    @MainActor
    func testInitialZeroSizeViewScrollsToNewestAfterLayout() {
        let coordinator = ActivityTranscript.Coordinator()
        let scroll = coordinator.makeScrollView()
        coordinator.update(input(1...50, follow: false), in: scroll)
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
        scroll.layoutSubtreeIfNeeded()
        XCTAssertGreaterThan(scroll.contentView.bounds.minY, 1_000)
        XCTAssertEqual(scroll.contentView.bounds.maxY, coordinator.textView.frame.maxY, accuracy: 2)
        XCTAssertEqual(coordinator.textView.frame.width, scroll.contentSize.width, accuracy: 2)
    }

    @MainActor
    func testHistoryPagingUsesExistingFeedAndOnlyOnUserScroll() {
        let coordinator = ActivityTranscript.Coordinator()
        let scroll = coordinator.makeScrollView()
        scroll.frame = NSRect(x: 0, y: 0, width: 520, height: 360)
        scroll.layoutSubtreeIfNeeded()
        var requests = 0
        let initial = input(51...100, load: { requests += 1 })
        coordinator.update(initial, in: scroll)
        XCTAssertEqual(requests, 0)
        scroll.contentView.scroll(to: .zero)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        XCTAssertEqual(requests, 1)
        coordinator.update(input(1...100, canLoad: false, load: { requests += 1 }), in: scroll)
        scroll.contentView.scroll(to: .zero)
        NotificationCenter.default.post(name: NSScrollView.didLiveScrollNotification, object: scroll)
        XCTAssertEqual(requests, 1)
    }

    @MainActor
    private func input(_ range: ClosedRange<Int>, room: String = "test-room", follow: Bool = true,
                       canLoad: Bool = true, load: @escaping () -> Void = {}) -> ActivityTranscript {
        ActivityTranscript(roomID: room, events: range.reversed().map { event($0) },
            participants: [:], fontSize: 13, followLive: follow, canLoadEarlier: canLoad, loadEarlier: load)
    }

    private func event(_ sequence: Int, text: String? = nil) -> ARCEventView {
        ARCEventView(sequence: Int64(sequence), at: "2026-09-08T12:00:00Z", logicalUs: Int64(sequence),
            kind: "MESSAGE", actor: "ai-1", recipient: "ai-2", subject: nil,
            payload: .object(["text": .string(text ?? "Message \(sequence)\nA second line of the conversation.")]),
            operationId: "test-\(sequence)", knowledgeSha256: "test")
    }
}
