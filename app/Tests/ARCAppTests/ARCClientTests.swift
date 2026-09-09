import ARCCore
import CryptoKit
import Darwin
import Foundation
import SwiftUI
import XCTest
@testable import ARCApp

final class ARCClientTests: XCTestCase {
    @MainActor
    func testConnectionRecoveryGuidanceIsExplicitAndRendersBothAppearances() async throws {
        func ai(_ phase: ARCParticipantPhase, _ attempts: Int) -> ARCParticipantView {
            ARCParticipantView(id: "ai-012345abcdef", name: "Delayed AI", phase: phase,
                duty: .notApplicable, isProducer: false, binding: nil, bindingGeneration: 1,
                schedule: ARCScheduleView(kind: .qualification, status: .waiting,
                    nextRequestLogicalUs: nil, deadlineLogicalUs: nil), lastCheckIn: nil,
                automaticRecoveryAttempts: attempts)
        }
        XCTAssertTrue(ARCConnectionRecoveryPresentation.message(for: ai(.failed, 0))!.contains("automatically retry"))
        XCTAssertTrue(ARCConnectionRecoveryPresentation.message(for: ai(.failed, 2))!.contains("existing chat"))
        XCTAssertTrue(ARCConnectionRecoveryPresentation.message(for: ai(.qualifying, 1))!.contains("retry 1 of 2"))
        XCTAssertNil(ARCConnectionRecoveryPresentation.message(for: ai(.retired, 2)))
        let state = AppState(client: TestClient(rootURL: temporaryRoot("arc-recovery-layout")),
            installation: TestInstallation())
        try await waitUntil { state.installationReady && !state.isBusy }
        let roomID = "room-012345abcdef"
        state.rooms = [ARCRoomListItem(id: roomID, name: "Guided recovery", health: .current, failure: nil)]
        state.selectedRoomID = roomID
        state.roomResult = ARCRoomOpenResult(room: testRoom(id: roomID, name: "Guided recovery", revision: 1),
            producer: testProducer(), participants: [ai(.failed, 2)], work: [])
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 960, height: 850),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hosting = NSHostingView(rootView: MainView().environmentObject(state))
        window.contentView = hosting
        window.orderFront(nil)
        for appearance in [NSAppearance.Name.aqua, .darkAqua] {
            window.appearance = NSAppearance(named: appearance)
            try await Task.sleep(nanoseconds: 100_000_000)
            hosting.layoutSubtreeIfNeeded()
            if let path = ProcessInfo.processInfo.environment["ARC_ROOM_TEST_SNAPSHOTS"] {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    .write(to: directory.appendingPathComponent("recovery-\(appearance.rawValue).png"))
            }
        }
    }

    func testDevelopmentBuildDefaultsToAnIsolatedRoot() {
        if ProcessInfo.processInfo.environment["ARC_DEVELOPMENT_ROOT"] == nil {
            XCTAssertNotEqual(ARCClient.defaultRoot.standardizedFileURL, ARCStore.defaultRootURL.standardizedFileURL)
            XCTAssertTrue(ARCClient.defaultRoot.lastPathComponent.hasPrefix("arc-development-"))
            XCTAssertEqual(ARCClient.defaultRoot, ARCClient.defaultRoot)
        }
    }

    func testMainWindowDoesNotReintroduceSwiftUISelectionOverlay() throws {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/ARCApp")
        for name in ["MainView.swift", "RoomView.swift", "CopyableText.swift"] {
            let text = try String(contentsOf: source.appendingPathComponent(name), encoding: .utf8)
            XCTAssertFalse(text.contains(".textSelection("), name)
            XCTAssertTrue(text.contains("arcCopyable"), name)
        }
        let copy = try String(contentsOf: source.appendingPathComponent("CopyableText.swift"), encoding: .utf8)
        XCTAssertTrue(copy.contains(".accessibilityAction(named: \"Copy Text\")"))
        XCTAssertTrue(copy.contains(".contextMenu"))
    }

    @MainActor
    func testLiveRoomWorkLayoutRemainsResponsive() async throws {
        let state = AppState(client: TestClient(rootURL: temporaryRoot("arc-live-layout")),
            installation: TestInstallation())
        try await waitUntil { state.installationReady && !state.isBusy }
        let roomID = "room-012345abcdef"
        let owner = participant(name: "Testing associate", phase: .qualified, duty: .on)
        state.rooms = [ARCRoomListItem(id: roomID, name: "Live layout regression", health: .current, failure: nil)]
        state.selectedRoomID = roomID
        func result(_ revision: Int) -> ARCRoomOpenResult {
            ARCRoomOpenResult(room: testRoom(id: roomID, name: "Live layout regression", revision: Int64(revision)),
                producer: testProducer(), participants: [owner], work: (1...2).map { index in
                    ARCWorkView(id: "work-\(index)", owner: owner.id,
                        state: revision % 3 == 0 ? .blocked : .active,
                        scope: "Work \(index): " + String(repeating: "Review the evidence and report the precise result. ", count: 8),
                        evidenceMode: .text, evidence: .object(["note": .string("Update \(revision)")]),
                        assigningProducerGeneration: 1, revision: Int64(revision),
                        createdAt: "2026-09-09T01:52:00.000000Z", updatedAt: "2026-09-09T01:52:01.000000Z")
                })
        }
        state.roomResult = result(1)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hosting = NSHostingView(rootView: MainView().environmentObject(state))
        window.contentView = hosting
        window.orderFront(nil)
        let start = ProcessInfo.processInfo.systemUptime
        for revision in 1...30 {
            state.roomResult = result(revision)
            state.showDetails = revision % 4 == 0
            state.textSizeIndex = revision % 5 == 0 ? 5 : 2
            window.setContentSize(NSSize(width: revision % 2 == 0 ? 900 : 1100, height: 760))
            try await Task.sleep(nanoseconds: 50_000_000)
            hosting.layoutSubtreeIfNeeded()
            // Work is below the participant cards; render the lower viewport
            // too, rather than passing a test that never instantiates its rows.
            func scrollViews(_ view: NSView) -> [NSScrollView] {
                (view as? NSScrollView).map { [$0] } ?? view.subviews.flatMap(scrollViews)
            }
            for scroll in scrollViews(hosting) {
                guard let document = scroll.documentView else { continue }
                let y = revision % 2 == 0 ? max(0, document.bounds.height - scroll.contentSize.height) : 0
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTAssertLessThan(ProcessInfo.processInfo.systemUptime - start, 30,
            "A live room must yield to its event loop while work, text size, and width change.")
        XCTAssertEqual(state.selectedRoom?.id, roomID)
        XCTAssertEqual(state.roomResult?.work.count, 2)
        if let path = ProcessInfo.processInfo.environment["ARC_ROOM_TEST_SNAPSHOTS"] {
            let directory = URL(fileURLWithPath: path, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                .write(to: directory.appendingPathComponent("live-room.png"))
        }
    }

    @MainActor
    func testOperatorLanguagePersistsAndIsIncludedInCopiedInstructions() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc-language-ui-\(UUID().uuidString)", isDirectory: true)
        defer { removeTemporaryRoot(root) }
        try ARCOperatorPreferences.save(.german, rootURL: root)
        let state = AppState(client: TestClient(rootURL: root), installation: TestInstallation())
        try await waitUntil { state.installationReady && !state.isBusy }
        XCTAssertEqual(state.operatorLanguage, .german)
        let participant = testParticipant(phase: .invited, schedule: ARCScheduleView(
            kind: .none, status: .none, nextRequestLogicalUs: nil, deadlineLogicalUs: nil))
        let handoff = try XCTUnwrap(ARCHandoff.text(rootURL: root,
            room: testRoom(id: "room-012345abcdef", name: "Language room", revision: 1),
            participant: participant, operatorLanguage: state.operatorLanguage))
        XCTAssertTrue(handoff.contains(ARCCommunication.specificationURL(rootURL: root).path))
        XCTAssertTrue(handoff.contains("entire file, including all sections and appendices"))
        XCTAssertTrue(handoff.contains("operator use Deutsch"))
        XCTAssertTrue(handoff.contains("choose English or German"))
        state.setOperatorLanguage(.english)
        try await waitUntil { !state.isBusy && state.operatorLanguage == .english }
        let reopened = AppState(client: TestClient(rootURL: root), installation: TestInstallation())
        try await waitUntil { reopened.installationReady && !reopened.isBusy }
        XCTAssertEqual(reopened.operatorLanguage, .english)
        XCTAssertEqual(try ARCOperatorPreferences.load(rootURL: root), .english)
        XCTAssertTrue(state.notice.contains("all rooms"))
        if let snapshots = ProcessInfo.processInfo.environment["ARC_LANGUAGE_TEST_SNAPSHOTS"] {
            let directory = URL(fileURLWithPath: snapshots, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 220, height: 100),
                styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            defer { window.close() }
            let hosting = NSHostingView(rootView: OperatorLanguageSelector().environmentObject(state))
            window.contentView = hosting
            for (name, appearance) in [("light", NSAppearance.Name.aqua), ("dark", .darkAqua)] {
                window.appearance = NSAppearance(named: appearance)
                window.setContentSize(NSSize(width: 220, height: 100))
                try await Task.sleep(nanoseconds: 50_000_000)
                hosting.layoutSubtreeIfNeeded()
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try data.write(to: directory.appendingPathComponent("operator-language-\(name).png"))
            }
        }
    }

    @MainActor
    func testLanguageSaveFailureKeepsPriorSelectionAndReportsError() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/arc-language-failure-\(UUID().uuidString)", isDirectory: true)
        defer { removeTemporaryRoot(root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: false)
        let state = AppState(client: TestClient(rootURL: root), installation: TestInstallation())
        try await waitUntil { state.installationReady && !state.isBusy }
        let outside = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: outside)
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(ARCOperatorPreferences.fileName),
            withDestinationURL: outside)
        state.setOperatorLanguage(.german)
        try await waitUntil { !state.isBusy && !state.notice.isEmpty }
        XCTAssertEqual(state.operatorLanguage, .english)
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "keep")
    }

    @MainActor
    func testActivityWindowRendersBothAppearancesAndClearsStaleRoomContent() async throws {
        let state = AppState(client: TestClient(rootURL: temporaryRoot("arc-activity-window")),
            installation: TestInstallation())
        try await waitUntil { state.installationReady && !state.isBusy }
        let roomID = "room-012345abcdef"
        state.rooms = [ARCRoomListItem(id: roomID, name: "Design review", health: .current, failure: nil)]
        state.selectedRoomID = roomID
        state.roomResult = ARCRoomOpenResult(room: testRoom(id: roomID, name: "Design review", revision: 1),
            producer: testProducer(), participants: [testParticipant(phase: .qualified,
                schedule: ARCScheduleView(kind: .none, status: .none,
                    nextRequestLogicalUs: nil, deadlineLogicalUs: nil))], work: [])
        state.activity = [
            ARCEventView(sequence: 1, at: "2026-09-08T12:00:00Z", logicalUs: 1,
                kind: "AI_JOINED", actor: "arc", recipient: nil, subject: "ai-012345abcdef",
                payload: .object([:]), operationId: "one", knowledgeSha256: "test"),
            ARCEventView(sequence: 2, at: "2026-09-08T12:01:00Z", logicalUs: 2,
                kind: "MESSAGE", actor: "ai-012345abcdef", recipient: "ai-2", subject: nil,
                payload: .object(["text": .string("The review is complete. I found two edge cases and added tests for both.\nThe room history stays intact.")]),
                operationId: "two", knowledgeSha256: "test"),
            ARCEventView(sequence: 3, at: "2026-09-08T12:02:00Z", logicalUs: 3,
                kind: "MESSAGE", actor: "ai-2", recipient: "ai-012345abcdef", subject: nil,
                payload: .object(["text": .string("Thanks. I’ll verify the changes and report the result here.")]),
                operationId: "three", knowledgeSha256: "test"),
        ].reversed()
        state.nextActivityBefore = 1
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 520, height: 360),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        defer { window.close() }
        let hosting = NSHostingView(rootView: ActivityWindowView().environmentObject(state))
        window.contentView = hosting
        for (name, appearance, sizeIndex) in [("light", NSAppearance.Name.aqua, 2),
            ("dark", .darkAqua, 2), ("large-text", .aqua, 8)] {
            state.textSizeIndex = sizeIndex
            window.appearance = NSAppearance(named: appearance)
            window.setContentSize(NSSize(width: 520, height: 360))
            try await Task.sleep(nanoseconds: 50_000_000)
            hosting.layoutSubtreeIfNeeded()
            let transcript = try XCTUnwrap(activityTextView(in: hosting))
            XCTAssertTrue(transcript.string.contains("The review is complete"))
            XCTAssertFalse(transcript.isEditable)
            let viewport = try XCTUnwrap(transcript.enclosingScrollView)
            let viewportBounds = hosting.convert(viewport.bounds, from: viewport)
            XCTAssertGreaterThan(viewportBounds.height, 80)
            XCTAssertLessThanOrEqual(viewportBounds.maxX, hosting.bounds.maxX + 1)
            XCTAssertGreaterThanOrEqual(viewportBounds.minX, -1)
            if let path = ProcessInfo.processInfo.environment["ARC_ACTIVITY_TEST_SNAPSHOTS"] {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                let bitmap = try XCTUnwrap(hosting.bitmapImageRepForCachingDisplay(in: hosting.bounds))
                hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: directory.appendingPathComponent("activity-\(name).png"))
            }
        }
        state.selectedRoomID = "room-fedcba543210"
        try await Task.sleep(nanoseconds: 50_000_000)
        hosting.layoutSubtreeIfNeeded()
        XCTAssertNil(activityTextView(in: hosting), "Do not show the previous room during a pending selection.")
        state.selectedRoomID = nil
        state.roomResult = nil
        state.activity = []
        try await Task.sleep(nanoseconds: 50_000_000)
        XCTAssertNil(activityTextView(in: hosting), "Deleted or missing rooms must clear the transcript.")
    }

    @MainActor
    private func activityTextView(in view: NSView) -> NSTextView? {
        if let text = view as? NSTextView { return text }
        return view.subviews.lazy.compactMap { self.activityTextView(in: $0) }.first
    }

    @MainActor
    func testFullRoomDeletionShowsExplicitRecoveryWarningAndCanBeCancelled() async throws {
        var warning = ""
        let state = AppState(client: TestClient(rootURL: temporaryRoot("arc-delete-warning")),
            installation: TestInstallation(), confirmation: { _, message, _ in
                warning = message
                return false
            })
        try await waitUntil { state.installationReady && !state.isBusy }
        state.rooms = [ARCRoomListItem(id: "room-012345abcdef", name: "Full room", health: .current, failure: nil)]
        state.selectedRoomID = "room-012345abcdef"
        state.roomResult = ARCRoomOpenResult(room: testRoom(id: "room-012345abcdef", name: "Full room", revision: 1),
            producer: testProducer(), participants: [testParticipant(phase: .invited,
                schedule: ARCScheduleView(kind: .none, status: .none,
                    nextRequestLogicalUs: nil, deadlineLogicalUs: nil))],
            work: [], canDeleteWithoutRetirement: true)
        XCTAssertTrue(state.canDeleteCurrentRoom)
        state.deleteCurrentRoom()
        XCTAssertTrue(warning.contains("without recording retirement"))
        XCTAssertTrue(warning.contains("This cannot be undone"))
        XCTAssertNotNil(state.roomResult)
    }

    @MainActor
    func testRefreshPreservesLoadedHistoryAndBridgesMultipleNewPages() async throws {
        let client = HistoryReviewClient(rootURL: temporaryRoot("arc-history-regression"))
        let state = AppState(client: client, installation: TestInstallation())
        try await waitUntil { state.activity.count == 50 && !state.isBusy }
        state.loadEarlierActivity()
        try await waitUntil { state.activity.count == 100 && !state.isBusy }
        state.applicationBecameActive()
        try await waitUntil { !state.isBusy }
        XCTAssertEqual(state.activity.count, 100)
        client.advance(to: 225)
        state.applicationBecameActive()
        try await waitUntil { state.activity.count == 225 && !state.isBusy }
        XCTAssertEqual(state.activity.map(\.sequence), Array((1...225).reversed()).map(Int64.init))
        XCTAssertNil(state.nextActivityBefore)
    }

    @MainActor
    func testConfirmedMutationFailureRestartsRoomMonitor() async throws {
        let client = ChangingRoomClient(rootURL: temporaryRoot("arc-confirmed-failure"))
        let stamps = StampBox()
        let state = AppState(client: client, installation: TestInstallation(),
            roomStampProvider: { _, _ in stamps.value }, monitorIntervalNanoseconds: 20_000_000,
            confirmation: { _, _, _ in true })
        try await waitUntil { state.roomResult != nil && !state.isBusy }
        state.replaceInstructions(for: try XCTUnwrap(state.roomResult?.participants.first))
        try await waitUntil { !state.isBusy && state.notice.contains("Unexpected test operation") }
        client.advance()
        stamps.advance()
        try await waitUntil { state.roomResult?.participants.first?.phase == .qualifying }
    }

    @MainActor
    func testCreateRetainsOperationAcrossRetryableFailure() async throws {
        let client = CreateRetryClient(rootURL: temporaryRoot("arc-create-retry"))
        let state = AppState(client: client, installation: TestInstallation())
        try await waitUntil { state.installationReady && !state.isBusy }
        state.createRoom(named: "Retry")
        try await waitUntil { client.operations.count == 1 && !state.isBusy }
        state.createRoom(named: "Retry")
        try await waitUntil { client.operations.count == 2 && !state.isBusy }
        XCTAssertEqual(client.operations[0], client.operations[1])
    }

    func testWorkingIsVisibleWithDeadlineAndDoesNotLookOffDuty() throws {
        let participant = ARCParticipantView(id: "ai-012345abcdef", name: "Worker",
            phase: .qualified, duty: .working, isProducer: false, binding: nil,
            bindingGeneration: 1, schedule: ARCScheduleView(kind: .working, status: .ok,
                nextRequestLogicalUs: 3_600_000_000, deadlineLogicalUs: 3_600_000_000), lastCheckIn: nil)
        XCTAssertEqual(participant.plainState(roomStatus: .active), "Working")
        XCTAssertTrue(participant.isAvailable)
        XCTAssertTrue(try XCTUnwrap(ARCParticipantSchedulePresentation.text(
            for: participant, roomStatus: .active, nowLogical: 0)).contains("extension due"))
    }
    func testRoomFileStampObservesOnlyNativeRoomAndAdjacentLock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "arc-room-stamp-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { removeTemporaryRoot(root) }
        let rooms = root.appendingPathComponent("rooms", isDirectory: true)
        try FileManager.default.createDirectory(
            at: rooms,
            withIntermediateDirectories: true
        )
        let room = rooms.appendingPathComponent("room-012345abcdef.arcroom")
        let lock = rooms.appendingPathComponent("room-012345abcdef.arcroom.lock")
        try Data("{}\n".utf8).write(to: room)
        try Data().write(to: lock)

        let first = ARCFileStamp.read(rootURL: root, roomID: "room-012345abcdef")
        XCTAssertEqual(first.facts.count, 2)
        XCTAssertTrue(first.facts.allSatisfy(\.exists))

        try Data("{\"revision\":2}\n".utf8).write(to: room)
        let second = ARCFileStamp.read(rootURL: root, roomID: "room-012345abcdef")
        XCTAssertNotEqual(first, second)
        XCTAssertTrue(
            ARCFileStamp.read(rootURL: root, roomID: "../outside").facts.isEmpty
        )
    }

    func testRoomListUsesTheNativeStoreAndOneRoomFile() throws {
        let root = temporaryRoot("arc-native-list")
        defer { removeTemporaryRoot(root) }
        let client = ARCClient(
            rootURL: root,
            knowledgeSHA256: String(repeating: "a", count: 64)
        )
        let created = try client.roomCreate(
            displayName: "Design room",
            operationID: UUID()
        )

        let result = try client.roomList(afterSafeID: nil)

        XCTAssertEqual(result.rooms.map(\.name), ["Design room"])
        XCTAssertEqual(result.rooms.first?.health, .current)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(
                "rooms/\(created.room.id).arcroom"
            ).path
        ))
    }

    @MainActor
    func testSelectedRoomNoticesAIPollAndActivityWithoutFocusChange() async throws {
        let client = ChangingRoomClient(rootURL: temporaryRoot("arc-monitor-test"))
        let stamps = StampBox()
        let state = AppState(
            client: client,
            installation: TestInstallation(),
            roomStampProvider: { _, _ in stamps.value },
            monitorIntervalNanoseconds: 20_000_000
        )

        try await waitUntil {
            state.roomResult?.participants.first?.phase == .invited
        }
        XCTAssertEqual(state.rooms.count, 1)
        XCTAssertTrue(state.activity.isEmpty)

        client.advance()
        stamps.advance()

        try await waitUntil {
            state.roomResult?.participants.first?.phase == .qualifying
                && state.activity.first?.kind == "AI_JOINED"
        }
        XCTAssertEqual(
            state.roomResult?.participants.first?.plainState(
                roomStatus: state.roomResult?.room.status ?? .needsTwoAIs
            ),
            "Checking ARC access"
        )
    }

    @MainActor
    func testSelectedRoomMonitorRetriesAfterOneTransientOpenFailure() async throws {
        let client = ChangingRoomClient(rootURL: temporaryRoot("arc-monitor-retry-test"))
        let stamps = StampBox()
        let state = AppState(
            client: client,
            installation: TestInstallation(),
            roomStampProvider: { _, _ in stamps.value },
            monitorIntervalNanoseconds: 20_000_000
        )
        try await waitUntil { state.roomResult != nil }

        client.failNextOpen()
        stamps.advance()

        try await waitUntil {
            client.openRequests >= 3 && state.roomResult?.room.id == "room-012345abcdef"
        }
        XCTAssertEqual(state.selectedRoomID, "room-012345abcdef")
    }

    @MainActor
    func testRapidRoomSelectionOpensTheLatestChoice() async throws {
        let client = RapidSelectionClient(rootURL: temporaryRoot("arc-rapid-selection"))
        let state = AppState(client: client, installation: TestInstallation())

        try await waitUntil { client.firstOpenStarted }
        state.selectRoom("room-000000000002")
        client.releaseFirstOpen()

        try await waitUntil {
            state.selectedRoomID == "room-000000000002"
                && state.roomResult?.room.id == "room-000000000002"
        }
        XCTAssertEqual(client.openedRooms, [
            "room-000000000001",
            "room-000000000002",
        ])
    }

    @MainActor
    func testExpiredQualificationIsFinishedWithoutManualRefresh() async throws {
        let client = ExpiredQualificationClient(
            rootURL: temporaryRoot("arc-expired-qualification")
        )
        let state = AppState(
            client: client,
            installation: TestInstallation(),
            roomStampProvider: { _, _ in ARCFileStamp(facts: []) },
            monitorIntervalNanoseconds: 20_000_000
        )

        try await waitUntil {
            state.roomResult?.participants.first?.phase == .failed
        }

        XCTAssertEqual(client.tickRequests, 1)
    }

    @MainActor
    func testRoomSidebarLoadsTheNextPageWhenItsLastRoomAppears() async throws {
        let client = PagingRoomClient(rootURL: temporaryRoot("arc-room-page-test"))
        let state = AppState(
            client: client,
            installation: TestInstallation()
        )

        try await waitUntil {
            state.rooms.count == 1 && state.roomResult?.room.id == "room-000000000001"
        }
        XCTAssertEqual(client.listRequests, 1)

        state.loadMoreRoomsIfNeeded(afterVisibleRoom: "room-000000000001")

        try await waitUntil { state.rooms.count == 2 }
        XCTAssertEqual(state.rooms.map(\.id), [
            "room-000000000001",
            "room-000000000002",
        ])
        XCTAssertEqual(client.listRequests, 2)
    }

    @MainActor
    func testMissingKnowledgeOffersOneInstallRecoveryWithoutAReloadLoop() async throws {
        let client = KnowledgeFailureClient(rootURL: temporaryRoot("arc-knowledge-repair"))
        let state = AppState(client: client, installation: TestInstallation())

        try await waitUntil { state.installationFailure != nil }

        XCTAssertFalse(state.installationReady)
        XCTAssertEqual(state.installationFailure, "ARC's verified AI instructions are missing.")
        XCTAssertEqual(client.openRequests, 1)
    }

    @MainActor
    func testSheetsRenderAtLargeTextInsideMinimumWindow() throws {
        let client = TestClient(rootURL: temporaryRoot("arc-large-text-test"))
        let state = AppState(
            client: client,
            installation: TestInstallation()
        )
        state.diagnostic = ARCDiagnosticResult(
            valid: false,
            failure: ARCDiagnosticFailure(
                check: "room file",
                message: "ARC could not safely open this room.",
                nextAction: "Keep the room unchanged and contact ARC support."
            ),
            context: [
                ARCDiagnosticFact(
                    label: "Room digest",
                    value: String(repeating: "abcdef0123456789", count: 8)
                ),
            ]
        )
        let sheets: [(String, AnyView)] = [
            ("New Room", AnyView(CreateRoomSheet().environmentObject(state))),
            ("Rename Room", AnyView(RenameRoomSheet().environmentObject(state))),
            ("Diagnosis", AnyView(DiagnosticsSheet().environmentObject(state))),
            ("Help", AnyView(HelpSheet().environmentObject(state))),
            ("Privacy", AnyView(PrivacySheet())),
        ]

        for (name, sheet) in sheets {
            let renderer = ImageRenderer(
                content: sheet
                    .dynamicTypeSize(.accessibility3)
                    .frame(width: 900, height: 650)
            )
            renderer.scale = 1
            let image = try XCTUnwrap(renderer.nsImage, "\(name) did not render")
            XCTAssertEqual(image.size.width, 900, accuracy: 1, name)
            XCTAssertEqual(image.size.height, 650, accuracy: 1, name)
        }
    }

    @MainActor
    private func waitUntil(
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        for _ in 0..<100 {
            if condition() { return }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("The selected room did not update within two seconds.")
    }

    private func temporaryRoot(_ prefix: String) -> URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
            "\(prefix)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    func testCreateUsesTheNativeCoreAndRetainsTheOperationID() throws {
        let root = temporaryRoot("arc-native-create")
        defer { removeTemporaryRoot(root) }
        let operationID = UUID(uuidString: "AAAAAAAA-BBBB-4CCC-8DDD-EEEEEEEEEEEE")!
        let client = ARCClient(
            rootURL: root,
            knowledgeSHA256: String(repeating: "a", count: 64)
        )

        let result = try client.roomCreate(
            displayName: "Design room",
            operationID: operationID
        )

        XCTAssertEqual(result.room.status, .needsTwoAIs)
        XCTAssertTrue(result.participants.isEmpty)
        XCTAssertEqual(
            try client.activityRead(room: result.room.id, beforeSequence: nil)
                .events.first?.operationId,
            "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"
        )
    }

    func testNativeClockRefusalRemainsPlainAndRetryable() throws {
        let root = temporaryRoot("arc-native-clock")
        defer { removeTemporaryRoot(root) }
        let digest = String(repeating: "a", count: 64)
        let created = try ARCClient(
            rootURL: root,
            clock: ARCClock { Date(timeIntervalSince1970: 2_000_000_000) },
            knowledgeSHA256: digest
        ).roomCreate(displayName: "Clock room", operationID: UUID())
        let client = ARCClient(
            rootURL: root,
            clock: ARCClock {
                throw ARCError(.clockUnavailable, "ARC cannot check time.")
            },
            knowledgeSHA256: digest
        )

        XCTAssertThrowsError(try client.roomTick(room: created.room.id)) { error in
            XCTAssertEqual(error.localizedDescription, "ARC cannot check time.")
            XCTAssertEqual((error as? ARCError)?.code, .clockUnavailable)
            XCTAssertEqual((error as? ARCError)?.retryable, true)
        }
    }

    func testHandoffIsExactLaneBoundTextAndOneJSONArgumentLine() throws {
        let participant = participant(name: "Atlas", phase: .invited, duty: .notApplicable)
        let room = ARCRoomView(
            id: "room-012345abcdef",
            name: "Design Room",
            status: .needsTwoAIs,
            revision: 1,
            protocol: "arc.protocol/1",
            knowledgeSha256: String(repeating: "a", count: 64),
            logicalUs: 0
        )
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ARC Test Root", isDirectory: true)

        let handoff = try XCTUnwrap(ARCHandoff.text(
            rootURL: root,
            room: room,
            participant: participant
        ))
        let lines = handoff.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertEqual(lines[0], "ARC AI setup")
        XCTAssertEqual(lines[1], "AI name: Atlas")
        XCTAssertEqual(lines[3], "Room ID: room-012345abcdef")
        XCTAssertTrue(lines[5].hasPrefix("Installed plain-text specifications: "))
        let argumentLine = try XCTUnwrap(lines.first { $0.hasPrefix("[") })
        let arguments = try JSONDecoder().decode([String].self, from: Data(argumentLine.utf8))
        XCTAssertEqual(arguments, [
            root.appendingPathComponent("current/bin/arc").path,
            "--root", root.path,
            "guide",
            "--room", "room-012345abcdef",
            "--id", "ai-012345abcdef",
            "--binding", "11111111-1111-4111-8111-111111111111",
        ])
        XCTAssertTrue(handoff.hasSuffix("\n"))
        XCTAssertFalse(handoff.contains("provider"))
        XCTAssertFalse(handoff.contains("repository"))
        XCTAssertTrue(handoff.contains("poll immediately"))
        XCTAssertTrue(handoff.contains("at least 40 seconds after that first poll"))
        XCTAssertTrue(handoff.contains("one-minute cadence alone is not enough"))
        XCTAssertTrue(handoff.contains("you Off Duty 180 seconds after your last valid poll"))
        XCTAssertTrue(handoff.contains("If ARC reports RETIRED, or ARC has exited or is otherwise"))
        XCTAssertTrue(handoff.contains("stop and remove every recurring, scheduled, and heartbeat"))
    }

    func testNamesUseNativeNFCAndCaseInsensitiveDuplicateCheck() {
        XCTAssertEqual(ARCNameValidation.normalized("  Cafe\u{301}  "), "Café")
        XCTAssertNil(ARCNameValidation.message(for: "Room with spaces", label: "Room name"))
        XCTAssertNotNil(ARCNameValidation.message(for: "bad/name", label: "Room name"))
        XCTAssertTrue(ARCNameValidation.isDuplicateParticipant(
            "atlas",
            in: [participant(name: "ATLAS", phase: .qualified, duty: .on)]
        ))
    }

    func testClockProblemNeverDisplaysParticipantOnDuty() {
        let value = participant(name: "Atlas", phase: .qualified, duty: .on)
        XCTAssertEqual(value.plainState(roomStatus: .active), "On Duty")
        XCTAssertEqual(
            value.plainState(roomStatus: .timeUnavailable),
            "Waiting for ARC's time check"
        )
    }

    func testQualificationScheduleShowsCurrentAndNextOpportunity() throws {
        let value = ARCParticipantView(
            id: "ai-012345abcdef",
            name: "Atlas",
            phase: .qualifying,
            duty: .notApplicable,
            isProducer: false,
            binding: "11111111-1111-4111-8111-111111111111",
            bindingGeneration: 1,
            schedule: ARCScheduleView(
                kind: .qualification,
                status: .ok,
                nextRequestLogicalUs: 40_000_000,
                deadlineLogicalUs: 120_000_000
            ),
            lastCheckIn: nil
        )

        let text = try XCTUnwrap(ARCParticipantSchedulePresentation.text(
            for: value,
            roomStatus: .needsOneAI,
            nowLogical: 0
        ))
        XCTAssertTrue(text.contains("Waiting for the next access check"))
        XCTAssertFalse(text.contains("AI may check in now"))
        XCTAssertTrue(text.contains("Next request:"))
        XCTAssertTrue(text.contains("Deadline:"))

        let due = ARCParticipantView(
            id: value.id, name: value.name, phase: value.phase,
            duty: value.duty, isProducer: value.isProducer,
            binding: value.binding, bindingGeneration: value.bindingGeneration,
            schedule: ARCScheduleView(
                kind: .qualification, status: .request2,
                nextRequestLogicalUs: 80_000_000,
                deadlineLogicalUs: 120_000_000
            ),
            lastCheckIn: nil
        )
        let dueText = try XCTUnwrap(ARCParticipantSchedulePresentation.text(
            for: due, roomStatus: .needsOneAI, nowLogical: 40_000_000
        ))
        XCTAssertTrue(dueText.contains("Request 2 of 3"))
        XCTAssertTrue(dueText.contains("AI may check in now"))
    }

    func testHelpCoversTheCompleteRoomWorkflow() {
        let help = ARCHelpContent.searchableText
        let requiredTopics = [
            "Room name", "fixed Room ID", "Copy AI Instructions to Paste Buffer",
            "qualification",
            "Producer", "On Duty", "Off Duty", "polling ARC", "Work", "Room History",
            "Copy Instructions Again", "Replace Instructions", "Retire", "Diagnose",
            "Delete Room",
        ]

        for topic in requiredTopics {
            XCTAssertTrue(help.contains(topic), "ARC Help is missing \(topic)")
        }
    }

    func testAddAIUsesTheAdministratorApprovedCopy() {
        XCTAssertEqual(
            ARCAddAIText.button,
            "Copy AI Instructions to Paste Buffer"
        )
        XCTAssertEqual(
            ARCAddAIText.instruction,
            "Paste the instructions directly to the AI Chat you are using for that AI Name."
        )
    }

    func testRoomMenuOffersTheSameAddAIPath() throws {
        let source = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .deletingLastPathComponent()
                .appendingPathComponent("Sources/ARCApp/ARCApp.swift"),
            encoding: .utf8
        )
        XCTAssertTrue(source.contains("Button(\"Add AI\") { state.focusAddAI() }"))
    }

    func testWorkOwnedByUnavailableAIDerivesOneWaitingState() {
        let owner = participant(name: "Atlas", phase: .qualified, duty: .off)
        let work = ARCWorkView(
            id: "work-1",
            owner: owner.id,
            state: .active,
            scope: "Review one bounded file",
            evidenceMode: .text,
            evidence: .object(["note": .string("Reading")]),
            assigningProducerGeneration: 1,
            revision: 2,
            createdAt: "2026-08-15T18:00:00Z",
            updatedAt: "2026-08-15T18:01:00Z"
        )
        let participants = [owner.id: owner]

        XCTAssertEqual(
            ARCWorkPresentation.state(
                work,
                participants: participants,
                roomStatus: .active
            ),
            "Waiting for Producer to reassign"
        )
    }

    func testUnverifiedEventTimeIsExplicit() {
        let event = ARCEventView(
            sequence: 4,
            at: "2026-08-15T18:00:00Z",
            logicalUs: 4,
            kind: "ROOM_RENAMED",
            actor: "administrator",
            recipient: nil,
            subject: nil,
            payload: .object([
                "name": .string("New"),
                "time_verified": .boolean(false),
            ]),
            operationId: "11111111-1111-4111-8111-111111111111",
            knowledgeSha256: String(repeating: "a", count: 64)
        )
        XCTAssertFalse(event.timeIsVerified)
    }

    func testActivityPresenterCoversTheExactEventVocabulary() {
        let atlasID = "ai-012345abcdef"
        let beaconID = "ai-fedcba654321"
        let atlas = participant(name: "Atlas", phase: .qualified, duty: .on)
        let beacon = ARCParticipantView(
            id: beaconID,
            name: "Beacon",
            phase: .qualified,
            duty: .on,
            isProducer: false,
            binding: "22222222-2222-4222-8222-222222222222",
            bindingGeneration: 1,
            schedule: ARCScheduleView(
                kind: .duty,
                status: .ok,
                nextRequestLogicalUs: nil,
                deadlineLogicalUs: nil
            ),
            lastCheckIn: nil
        )
        let participants = [atlasID: atlas, beaconID: beacon]
        let challenge = String(repeating: "a", count: 32)

        func event(
            _ kind: String,
            actor: String = "administrator",
            recipient: String? = nil,
            subject: String? = nil,
            payload: [String: ARCJSONValue] = [:]
        ) -> ARCEventView {
            ARCEventView(
                sequence: 1,
                at: "2026-08-15T18:00:00.000000Z",
                logicalUs: 1,
                kind: kind,
                actor: actor,
                recipient: recipient,
                subject: subject,
                payload: .object(payload),
                operationId: "33333333-3333-4333-8333-333333333333",
                knowledgeSha256: String(repeating: "a", count: 64)
            )
        }

        let checks: [(ARCEventView, String)] = [
            (event("ROOM_CREATED", payload: ["name": .string("Design Room")]),
             "The room was created."),
            (event("ROOM_RENAMED", payload: [
                "name": .string("New Room"), "time_verified": .boolean(true),
            ]), "The room was renamed to New Room."),
            (event("AI_INVITED", recipient: atlasID, subject: atlasID, payload: [
                "name": .string("Atlas"), "time_verified": .boolean(true),
            ]), "Atlas was added to the room."),
            (event("INSTRUCTIONS_REPLACED", recipient: atlasID, subject: atlasID,
                   payload: [
                    "binding_generation": .integer(2),
                    "producer_cleared": .boolean(false),
                    "time_verified": .boolean(true),
                   ]), "Instructions for Atlas were replaced."),
            (event("QUALIFICATION_RETRIED", recipient: atlasID, subject: atlasID,
                   payload: [
                    "answer_type": .string("qualification.answer"),
                    "challenge": .string(challenge),
                    "deadline_logical_us": .integer(120_000_001),
                   ]), "ARC started a fresh access check for Atlas."),
            (event("AI_RETIRED", subject: atlasID, payload: [
                "producer_cleared": .boolean(false),
                "time_verified": .boolean(true),
            ]), "Atlas was retired."),
            (event("PRODUCER_CHANGED", subject: atlasID, payload: [
                "generation": .integer(1), "participant": .string(atlasID),
            ]), "Atlas became the Producer."),
            (event("AI_JOINED", actor: atlasID, subject: atlasID),
             "Atlas connected to ARC."),
            (event("QUALIFICATION_STARTED", actor: "arc", recipient: beaconID,
                   subject: beaconID, payload: [
                    "answer_type": .string("qualification.answer"),
                    "challenge": .string(challenge),
                    "deadline_logical_us": .integer(120_000_001),
                   ]), "ARC started the access check for Beacon."),
            (event("QUALIFICATION_ANSWERED", actor: beaconID, recipient: beaconID,
                   subject: beaconID), "Beacon answered the access check."),
            (event("QUALIFICATION_FAILED", actor: "arc", recipient: beaconID,
                   subject: beaconID, payload: [
                    "reason": .string("The two-minute check expired."),
                   ]), "The ARC access check for Beacon failed."),
            (event("AI_QUALIFIED", actor: atlasID, subject: atlasID, payload: [
                "became_producer": .boolean(true),
            ]), "Atlas qualified and became the Producer."),
            (event("AI_RETURNED_ON_DUTY", actor: beaconID, subject: beaconID),
             "Beacon returned On Duty."),
            (event("MESSAGE", actor: atlasID, recipient: beaconID, payload: [
                "text": .string("Please review the result."),
            ]), "Atlas sent a message to Beacon."),
            (event("WORK_ASSIGNED", actor: atlasID, recipient: beaconID,
                   subject: "work-012345abcdef", payload: [
                    "evidence_mode": .string("TEXT"),
                    "scope": .string("Review the result"),
                   ]), "Atlas assigned work-012345abcdef to Beacon."),
            (event("WORK_UPDATED", actor: beaconID, subject: "work-012345abcdef",
                   payload: [
                    "evidence": .object(["note": .string("Reviewing")]),
                    "revision": .integer(2),
                    "state": .string("ACTIVE"),
                   ]), "Beacon marked work-012345abcdef active."),
            (event("WORK_REASSIGNED", actor: atlasID, recipient: atlasID,
                   subject: "work-012345abcdef", payload: [
                    "owner": .string(atlasID),
                    "reason": .string("Beacon is Off Duty"),
                    "revision": .integer(3),
                   ]), "Atlas reassigned work-012345abcdef to Atlas."),
        ]

        XCTAssertEqual(checks.count, 17)
        for (value, expected) in checks {
            XCTAssertEqual(
                ARCActivityPresentation.summary(value, participants: participants),
                expected,
                value.kind
            )
        }

        let qualifiedWithoutProducer = event(
            "AI_QUALIFIED",
            actor: beaconID,
            subject: beaconID,
            payload: ["became_producer": .boolean(false)]
        )
        XCTAssertEqual(
            ARCActivityPresentation.summary(
                qualifiedWithoutProducer,
                participants: participants
            ),
            "Beacon qualified for ARC work."
        )
    }

    private func participant(
        name: String,
        phase: ARCParticipantPhase,
        duty: ARCDuty
    ) -> ARCParticipantView {
        ARCParticipantView(
            id: "ai-012345abcdef",
            name: name,
            phase: phase,
            duty: duty,
            isProducer: false,
            binding: "11111111-1111-4111-8111-111111111111",
            bindingGeneration: 1,
            schedule: ARCScheduleView(
                kind: phase == .qualified ? .duty : .none,
                status: phase == .qualified ? .ok : .none,
                nextRequestLogicalUs: nil,
                deadlineLogicalUs: nil
            ),
            lastCheckIn: nil
        )
    }
}

final class ARCInstallationTests: XCTestCase {
    private struct Row: Codable {
        let kind: String
        let mode: Int
        let path: String
        let sha256: String
        let size: Int
        let source: String
        let target: String?

        private enum CodingKeys: String, CodingKey {
            case kind, mode, path, sha256, size, source, target
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(kind, forKey: .kind)
            try container.encode(mode, forKey: .mode)
            try container.encode(path, forKey: .path)
            try container.encode(sha256, forKey: .sha256)
            try container.encode(size, forKey: .size)
            try container.encode(source, forKey: .source)
            if let target {
                try container.encode(target, forKey: .target)
            } else {
                try container.encodeNil(forKey: .target)
            }
        }
    }

    private struct Manifest: Codable {
        let entries: [Row]
        let knowledgeSha256: String
        let product: String
        let schema: Int
        let version: String
    }

    private enum Interruption: Error { case requested }

    private final class StageRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var recorded: [String] = []

        var names: [String] {
            lock.lock()
            defer { lock.unlock() }
            return recorded
        }

        func capture(in root: URL) throws {
            let names = try FileManager.default.contentsOfDirectory(atPath: root.path)
                .filter { $0.hasPrefix(".arc-install-stage-") }
            guard names.count == 1 else { throw Interruption.requested }
            lock.lock()
            recorded.append(names[0])
            lock.unlock()
        }
    }

    private var temporary: URL!

    override func setUpWithError() throws {
        temporary = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("arc-install-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporary, withIntermediateDirectories: false)
    }

    override func tearDownWithError() throws {
        if let temporary { try? FileManager.default.removeItem(at: temporary) }
    }

    func testVersionTwoFreshInstallUpgradeAndInvalidVersions() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        let root = temporary.appendingPathComponent("root", isDirectory: true)
        let installation = ARCInstallation(bundleURL: bundle, developmentBypass: false)
        try writeBundle(bundle, specificationText: "legacy\n", launcherText: "launcher", releaseVersion: "1.1.0")
        try installation.ensureInstalled(rootURL: root)
        try writeBundle(bundle, specificationText: "version two\n", launcherText: "launcher", releaseVersion: "2.0.0")
        try installation.ensureInstalled(rootURL: root)
        XCTAssertEqual(try String(contentsOf: ARCCommunication.specificationURL(rootURL: root), encoding: .utf8), "version two\n")
        for version in ["2.1.0", "2.2.0"] {
            try writeBundle(bundle, specificationText: "version two\n", launcherText: "launcher", releaseVersion: version)
            try installation.ensureInstalled(rootURL: root)
            XCTAssertEqual(try String(contentsOf: ARCCommunication.specificationURL(rootURL: root), encoding: .utf8), "version two\n")
        }
        let fresh = temporary.appendingPathComponent("fresh", isDirectory: true)
        try installation.ensureInstalled(rootURL: fresh)
        XCTAssertEqual(ARCCommunication.snapshot(rootURL: fresh).status, "ready")
        for version in ["3.0.0", "2.0", "2.0.0-beta", "garbage"] {
            try writeBundle(bundle, specificationText: "invalid\n", launcherText: "launcher", releaseVersion: version)
            XCTAssertThrowsError(try installation.ensureInstalled(rootURL: root), version)
            XCTAssertEqual(try String(contentsOf: ARCCommunication.specificationURL(rootURL: root), encoding: .utf8), "version two\n")
        }
    }

    func testTerseUpgradePreservesOperatorPreferenceAndRepairsMissingSpecification() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        let root = temporary.appendingPathComponent("root", isDirectory: true)
        try writeBundle(bundle, specificationText: "Terse first version\n", launcherText: "launcher")
        try ARCOperatorPreferences.save(.german, rootURL: root)
        let installation = ARCInstallation(bundleURL: bundle, developmentBypass: false)
        try installation.ensureInstalled(rootURL: root)
        let before = ARCCommunication.snapshot(rootURL: root)
        XCTAssertEqual(before.status, "ready")
        XCTAssertEqual(before.operatorLanguage, .german)
        try writeBundle(bundle, specificationText: "Terse updated version\n", launcherText: "launcher")
        try installation.ensureInstalled(rootURL: root)
        let after = ARCCommunication.snapshot(rootURL: root)
        XCTAssertEqual(after.status, "ready")
        XCTAssertNotEqual(before.specificationSha256, after.specificationSha256)
        XCTAssertEqual(after.operatorLanguage, .german)
        try FileManager.default.removeItem(at: ARCCommunication.specificationURL(rootURL: root))
        try installation.ensureInstalled(rootURL: root, force: true)
        XCTAssertEqual(ARCCommunication.snapshot(rootURL: root).status, "ready")
        XCTAssertEqual(try ARCOperatorPreferences.load(rootURL: root), .german)
    }

    func testVerifiedInstallAndInterruptedUpgradePreserveRooms() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "first specification\n",
            launcherText: "#!/bin/sh\n# first launcher\nexit 0\n"
        )
        let root = temporary.appendingPathComponent("Application Support/ARC")
        let roomFile = root.appendingPathComponent("rooms/room-012345abcdef.arcroom")
        try FileManager.default.createDirectory(
            at: roomFile.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("retained room".utf8).write(to: roomFile)

        try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false)

        let installedSpecification = root.appendingPathComponent(
            "current/specifications/000-product.txt"
        )
        XCTAssertEqual(
            try String(contentsOf: installedSpecification, encoding: .utf8),
            "first specification\n"
        )
        XCTAssertEqual(try Data(contentsOf: roomFile), Data("retained room".utf8))

        try FileManager.default.removeItem(at: bundle)
        try writeBundle(
            bundle,
            specificationText: "second specification\n",
            launcherText: "#!/bin/sh\n# second launcher\nexit 0\n"
        )
        let interrupted = ARCInstallation(
            bundleURL: bundle,
            failpoint: { step in
                if case .currentPublished = step { throw Interruption.requested }
            },
            developmentBypass: false
        )
        XCTAssertThrowsError(try interrupted.ensureInstalled(rootURL: root, force: false))
        XCTAssertEqual(
            try String(contentsOf: installedSpecification, encoding: .utf8),
            "first specification\n"
        )
        XCTAssertEqual(try Data(contentsOf: roomFile), Data("retained room".utf8))

        try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false)
        XCTAssertEqual(
            try String(contentsOf: installedSpecification, encoding: .utf8),
            "second specification\n"
        )
        XCTAssertEqual(try Data(contentsOf: roomFile), Data("retained room".utf8))
        XCTAssertEqual(
            try String(
                contentsOf: root.appendingPathComponent("current/bin/arc"),
                encoding: .utf8
            ),
            "#!/bin/sh\n# second launcher\nexit 0\n"
        )
    }

    func testInstallerDoesNotPropagateDownloadQuarantineToInstalledCommand() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "specification\n",
            launcherText: "#!/bin/sh\nexit 0\n"
        )
        let bundledCommand = bundle.appendingPathComponent(
            "Contents/Resources/install/bin/arc"
        )
        let marker = Array("test-download".utf8)
        let setResult = bundledCommand.path.withCString { path in
            "com.apple.quarantine".withCString { name in
                marker.withUnsafeBytes { bytes in
                    setxattr(path, name, bytes.baseAddress, bytes.count, 0, 0)
                }
            }
        }
        XCTAssertEqual(setResult, 0)

        let root = temporary.appendingPathComponent("Application Support/ARC")
        try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false)
        let installed = root.appendingPathComponent("current/bin/arc")
        let size = installed.path.withCString { path in
            "com.apple.quarantine".withCString { name in
                getxattr(path, name, nil, 0, 0, 0)
            }
        }
        XCTAssertEqual(size, -1)
        XCTAssertEqual(errno, ENOATTR)
    }

    func testInstallerRefusesLinkedParentComponent() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "specification\n",
            launcherText: "#!/bin/sh\nexit 0\n"
        )
        let real = temporary.appendingPathComponent("real", isDirectory: true)
        let linked = temporary.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            atPath: linked.path,
            withDestinationPath: real.path
        )
        let root = linked.appendingPathComponent("ARC", isDirectory: true)

        XCTAssertThrowsError(try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false)) { error in
            XCTAssertEqual(error as? ARCInstallationError, .installedFilesUnsafe)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.path))
    }

    func testInstallerRefusesLinkedCurrentTree() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "specification\n",
            launcherText: "#!/bin/sh\nexit 0\n"
        )
        let root = temporary.appendingPathComponent("Application Support/ARC")
        let outside = temporary.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
        try FileManager.default.createSymbolicLink(
            atPath: root.appendingPathComponent("current").path,
            withDestinationPath: outside.path
        )

        XCTAssertThrowsError(try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false)) { error in
            XCTAssertEqual(error as? ARCInstallationError, .installedFilesUnsafe)
        }
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: outside.appendingPathComponent("bin/arc").path
        ))
        XCTAssertEqual(
            try FileManager.default.destinationOfSymbolicLink(
                atPath: root.appendingPathComponent("current").path
            ),
            outside.path
        )
    }

    func testReinstallRepairsManifestOwnedSpecificationAndLauncher() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "verified specification\n",
            launcherText: "#!/bin/sh\n# verified launcher\nexit 0\n"
        )
        let root = temporary.appendingPathComponent("Application Support/ARC")
        let installer = ARCInstallation(bundleURL: bundle, developmentBypass: false)
        try installer.ensureInstalled(rootURL: root, force: false)

        let specification = root.appendingPathComponent(
            "current/specifications/000-product.txt"
        )
        let launcher = root.appendingPathComponent("current/bin/arc")
        try Data("damaged specification\n".utf8).write(to: specification)
        try Data("damaged launcher\n".utf8).write(to: launcher)

        try installer.ensureInstalled(rootURL: root, force: false)

        XCTAssertEqual(
            try String(contentsOf: specification, encoding: .utf8),
            "verified specification\n"
        )
        XCTAssertEqual(
            try String(contentsOf: launcher, encoding: .utf8),
            "#!/bin/sh\n# verified launcher\nexit 0\n"
        )
    }

    func testForcedInstallRefusesUnknownCurrentContents() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "verified specification\n",
            launcherText: "#!/bin/sh\nexit 0\n"
        )
        let installer = ARCInstallation(bundleURL: bundle, developmentBypass: false)

        let currentCollisionRoot = temporary.appendingPathComponent("unknown-current")
        let foreignCurrent = currentCollisionRoot
            .appendingPathComponent("current/foreign.txt")
        try FileManager.default.createDirectory(
            at: foreignCurrent.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not ARC\n".utf8).write(to: foreignCurrent)
        XCTAssertThrowsError(try installer.ensureInstalled(
            rootURL: currentCollisionRoot,
            force: true
        )) { error in
            XCTAssertEqual(error as? ARCInstallationError, .installedFilesUnsafe)
        }
        XCTAssertEqual(try Data(contentsOf: foreignCurrent), Data("not ARC\n".utf8))

        let addedFileRoot = temporary.appendingPathComponent("installed-with-added-file")
        try installer.ensureInstalled(rootURL: addedFileRoot, force: false)
        let addedFile = addedFileRoot.appendingPathComponent("current/foreign.txt")
        try Data("not ARC\n".utf8).write(to: addedFile)
        XCTAssertThrowsError(try installer.ensureInstalled(
            rootURL: addedFileRoot,
            force: false
        )) { error in
            XCTAssertEqual(error as? ARCInstallationError, .installedFilesUnsafe)
        }
        XCTAssertEqual(try Data(contentsOf: addedFile), Data("not ARC\n".utf8))
    }

    func testReinstallRestoresMissingOwnedPayloads() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(bundle, specificationText: "verified\n", launcherText: "#!/bin/sh\nexit 0\n")
        let installer = ARCInstallation(bundleURL: bundle, developmentBypass: false)
        for force in [false, true] {
            let root = temporary.appendingPathComponent("repair-\(force)")
            try installer.ensureInstalled(rootURL: root, force: false)
            for path in ["current/ARC_AI.arc-kb", "current/bin/arc", "current/specifications/000-product.txt"] {
                let file = root.appendingPathComponent(path)
                let expected = try Data(contentsOf: file)
                try FileManager.default.removeItem(at: file)
                try installer.ensureInstalled(rootURL: root, force: force)
                XCTAssertEqual(try Data(contentsOf: file), expected, path)
            }
        }
    }

    func testInstallerReplacesVerifiedLegacyRuntimeAndPreservesRooms() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "native specification\n",
            launcherText: "#!/bin/sh\n# native launcher\nexit 0\n"
        )
        let root = temporary.appendingPathComponent("Application Support/ARC")
        let room = root.appendingPathComponent("rooms/room-012345abcdef.arcroom")
        try FileManager.default.createDirectory(
            at: room.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("retained room".utf8).write(to: room)
        try writeLegacyRuntime(at: root)

        try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: true)

        try assertInstalledPair(root, version: "native")
        XCTAssertEqual(try Data(contentsOf: room), Data("retained room".utf8))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("bin/arc").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: root.appendingPathComponent("current/runtime").path
        ))
    }

    func testAbruptInstallStepsReopenToOneCoherentCurrentTree() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        let root = temporary.appendingPathComponent("Application Support/ARC")
        let room = root.appendingPathComponent("rooms/room-012345abcdef.arcroom")
        try FileManager.default.createDirectory(
            at: room.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("retained room".utf8).write(to: room)

        try writeBundle(
            bundle,
            specificationText: "first specification\n",
            launcherText: "#!/bin/sh\n# first launcher\nexit 0\n"
        )
        try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false)

        try FileManager.default.removeItem(at: bundle)
        try writeBundle(
            bundle,
            specificationText: "second specification\n",
            launcherText: "#!/bin/sh\n# second launcher\nexit 0\n"
        )
        XCTAssertThrowsError(try ARCInstallation(
            bundleURL: bundle,
            failpoint: { step in
                if case .staged = step { throw ARCInstallAbruptStop.requested }
            },
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false))
        try assertInstalledPair(root, version: "first")

        try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false)
        try assertInstalledPair(root, version: "second")

        try FileManager.default.removeItem(at: bundle)
        try writeBundle(
            bundle,
            specificationText: "third specification\n",
            launcherText: "#!/bin/sh\n# third launcher\nexit 0\n"
        )
        XCTAssertThrowsError(try ARCInstallation(
            bundleURL: bundle,
            failpoint: { step in
                if case .currentPublished = step {
                    throw ARCInstallAbruptStop.requested
                }
            },
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false))
        try assertInstalledPair(root, version: "third")

        try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(rootURL: root, force: false)
        try assertInstalledPair(root, version: "third")
        XCTAssertEqual(try Data(contentsOf: room), Data("retained room".utf8))
    }

    func testInstallerRejectsHiddenManifestComponents() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "specification\n",
            launcherText: "#!/bin/sh\nexit 0\n"
        )
        let manifestURL = bundle.appendingPathComponent(
            "Contents/Resources/install/ARC-INSTALL-MANIFEST.json"
        )
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let original = try decoder.decode(
            Manifest.self,
            from: Data(try Data(contentsOf: manifestURL).dropLast())
        )
        let hidden = Row(
            kind: "file",
            mode: 0o644,
            path: "current/specifications/.hidden.txt",
            sha256: String(repeating: "0", count: 64),
            size: 0,
            source: "Resources/install/current/specifications/.hidden.txt",
            target: nil
        )
        let changed = Manifest(
            entries: (original.entries + [hidden]).sorted {
                Array($0.path.utf8).lexicographicallyPrecedes(Array($1.path.utf8))
            },
            knowledgeSha256: original.knowledgeSha256,
            product: original.product,
            schema: original.schema,
            version: original.version
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var data = try encoder.encode(changed)
        data.append(0x0A)
        try data.write(to: manifestURL)

        XCTAssertThrowsError(try ARCInstallation(
            bundleURL: bundle,
            developmentBypass: false
        ).ensureInstalled(
            rootURL: temporary.appendingPathComponent("hidden-component-root"),
            force: false
        )) { error in
            guard let installationError = error as? ARCInstallationError,
                  case .manifestInvalid = installationError else {
                return XCTFail("Expected a manifest-invalid error, got \(error)")
            }
        }
    }

    func testStagingNamesAndMappedSourcePathsAreExpandedAndUnique() throws {
        let bundle = temporary.appendingPathComponent("ARC.app", isDirectory: true)
        try writeBundle(
            bundle,
            specificationText: "specification\n",
            launcherText: "#!/bin/sh\nexit 0\n"
        )
        let root = temporary.appendingPathComponent("Application Support/ARC")
        let recorder = StageRecorder()
        let installer = ARCInstallation(
            bundleURL: bundle,
            failpoint: { step in
                if case .staged = step { try recorder.capture(in: root) }
            },
            developmentBypass: false
        )

        try installer.ensureInstalled(rootURL: root, force: false)
        try installer.ensureInstalled(rootURL: root, force: true)

        XCTAssertEqual(recorder.names.count, 2)
        XCTAssertEqual(Set(recorder.names).count, 2)
        for name in recorder.names {
            XCTAssertNotNil(name.range(
                of: #"^\.arc-install-stage-[0-9a-f-]{36}$"#,
                options: .regularExpression
            ))
            XCTAssertFalse(name.contains("("))
        }
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(
                "current/specifications/000-product.txt"
            ).path
        ))
    }

    private func writeBundle(
        _ bundle: URL,
        specificationText: String,
        launcherText: String,
        releaseVersion: String = "1.0.2"
    ) throws {
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        let install = contents.appendingPathComponent("Resources/install", isDirectory: true)
        let knowledge = install.appendingPathComponent("current/ARC_AI.arc-kb")
        let specification = install.appendingPathComponent(
            "current/specifications/000-product.txt"
        )
        let launcher = install.appendingPathComponent("bin/arc")
        let terse = install.appendingPathComponent("current/" + ARCCommunication.specificationRelativePath)
        let terseDigest = install.appendingPathComponent("current/" + ARCCommunication.digestRelativePath)
        for file in [knowledge, specification, launcher, terse, terseDigest] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        try Data("sealed knowledge".utf8).write(to: knowledge)
        try Data(specificationText.utf8).write(to: specification)
        try Data(launcherText.utf8).write(to: launcher)
        try Data(specificationText.utf8).write(to: terse)
        try Data((digest(Data(specificationText.utf8)) + "\n").utf8).write(to: terseDigest)
        for file in [knowledge, specification, terse, terseDigest] {
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o644],
                ofItemAtPath: file.path
            )
        }
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755],
            ofItemAtPath: launcher.path
        )

        let descriptions = [
            ("current/ARC_AI.arc-kb", "Resources/install/current/ARC_AI.arc-kb", knowledge),
            (
                "current/specifications/000-product.txt",
                "Resources/install/current/specifications/000-product.txt",
                specification
            ),
            ("current/bin/arc", "Resources/install/bin/arc", launcher),
            ("current/" + ARCCommunication.specificationRelativePath,
                "Resources/install/current/" + ARCCommunication.specificationRelativePath, terse),
            ("current/" + ARCCommunication.digestRelativePath,
                "Resources/install/current/" + ARCCommunication.digestRelativePath, terseDigest),
        ]
        let rows = try descriptions.map { path, source, file in
            let data = try Data(contentsOf: file)
            let attributes = try FileManager.default.attributesOfItem(atPath: file.path)
            let mode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            return Row(
                kind: "file",
                mode: mode,
                path: path,
                sha256: digest(data),
                size: data.count,
                source: source,
                target: nil
            )
        }.sorted { Array($0.path.utf8).lexicographicallyPrecedes(Array($1.path.utf8)) }
        let manifest = Manifest(
            entries: rows,
            knowledgeSha256: digest(try Data(contentsOf: knowledge)),
            product: "ARC",
            schema: 1,
            version: releaseVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var data = try encoder.encode(manifest)
        data.append(0x0A)
        try data.write(to: install.appendingPathComponent("ARC-INSTALL-MANIFEST.json"))
    }

    private func writeLegacyRuntime(at root: URL) throws {
        let launcher = root.appendingPathComponent("bin/arc")
        let core = root.appendingPathComponent("current/runtime/arc/core.py")
        let legacyLink = root.appendingPathComponent("current/runtime/arc/legacy-link")
        let hidden = root.appendingPathComponent("current/runtime/arc/.legacy-config")
        for file in [launcher, core, hidden] {
            try FileManager.default.createDirectory(
                at: file.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
        }
        try Data("#!/bin/sh\n# legacy launcher\nexit 0\n".utf8).write(to: launcher)
        try Data("legacy core\n".utf8).write(to: core)
        try Data("legacy setting\n".utf8).write(to: hidden)
        try FileManager.default.createSymbolicLink(
            atPath: legacyLink.path,
            withDestinationPath: "core.py"
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: launcher.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: core.path
        )
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: hidden.path
        )
        let rows = [
            Row(
                kind: "file", mode: 0o755, path: "bin/arc",
                sha256: digest(try Data(contentsOf: launcher)),
                size: Int((try Data(contentsOf: launcher)).count),
                source: "Resources/install/bin/arc", target: nil
            ),
            Row(
                kind: "file", mode: 0o644, path: "current/runtime/arc/core.py",
                sha256: digest(try Data(contentsOf: core)),
                size: Int((try Data(contentsOf: core)).count),
                source: "Resources/install/current/runtime/arc/core.py", target: nil
            ),
            Row(
                kind: "link", mode: 0o775, path: "current/runtime/arc/legacy-link",
                sha256: String(repeating: "0", count: 64), size: 7,
                source: "legacy-link", target: "core.py"
            ),
            Row(
                kind: "file", mode: 0o644, path: "current/runtime/arc/.legacy-config",
                sha256: digest(try Data(contentsOf: hidden)),
                size: Int((try Data(contentsOf: hidden)).count),
                source: "legacy-config", target: nil
            ),
        ]
        let manifest = Manifest(
            entries: rows,
            knowledgeSha256: String(repeating: "0", count: 64),
            product: "ARC",
            schema: 1,
            version: "1.0.2"
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        var data = try encoder.encode(manifest)
        data.append(0x0A)
        let receipt = root.appendingPathComponent("current/ARC-INSTALL-MANIFEST.json")
        try data.write(to: receipt)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o644], ofItemAtPath: receipt.path
        )
    }

    private func assertInstalledPair(_ root: URL, version: String) throws {
        XCTAssertEqual(
            try String(
                contentsOf: root.appendingPathComponent(
                    "current/specifications/000-product.txt"
                ),
                encoding: .utf8
            ),
            "\(version) specification\n"
        )
        XCTAssertEqual(
            try String(
                contentsOf: root.appendingPathComponent("current/bin/arc"),
                encoding: .utf8
            ),
            "#!/bin/sh\n# \(version) launcher\nexit 0\n"
        )
    }

    private func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
}

private struct TestInstallation: ARCInstallationProtocol {
    func ensureInstalled(rootURL: URL, force: Bool) throws {}
}

private final class StampBox: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: Int64 = 1

    var value: ARCFileStamp {
        lock.lock()
        defer { lock.unlock() }
        return ARCFileStamp(facts: [ARCFileStamp.Fact(
            exists: true,
            inode: 1,
            size: generation,
            modifiedSeconds: generation,
            modifiedNanoseconds: 0
        )])
    }

    func advance() {
        lock.lock()
        generation += 1
        lock.unlock()
    }
}

private class TestClient: ARCClientProtocol, @unchecked Sendable {
    let rootURL: URL

    init(rootURL: URL) { self.rootURL = rootURL }

    func roomList(afterSafeID: String?) throws -> ARCRoomListPage {
        ARCRoomListPage(rooms: [], nextSafeId: nil)
    }

    func roomOpen(room: String) throws -> ARCRoomOpenResult { try unsupported() }
    func roomCreate(displayName: String, operationID: UUID) throws -> ARCRoomOpenResult {
        try unsupported()
    }
    func roomRename(
        room: String, displayName: String, operationID: UUID
    ) throws -> ARCRevisionResult { try unsupported() }
    func roomTick(room: String) throws -> ARCRoomTickResult { try unsupported() }
    func participantInvite(
        room: String, name: String, operationID: UUID
    ) throws -> ARCInstructionResult { try unsupported() }
    func participantReplaceInstructions(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCInstructionResult { try unsupported() }
    func participantTryAgain(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult { try unsupported() }
    func participantRetire(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult { try unsupported() }
    func producerSelect(
        room: String, participant: String, operationID: UUID
    ) throws -> ARCRevisionResult { try unsupported() }
    func activityRead(room: String, beforeSequence: Int64?) throws -> ARCActivityPage {
        ARCActivityPage(events: [], nextBefore: nil)
    }
    func diagnose(room: String) throws -> ARCDiagnosticResult { try unsupported() }
    func roomDelete(room: String) throws -> ARCDeleteResult { try unsupported() }

    private func unsupported<T>() throws -> T {
        throw ARCError(.wrongState, "Unexpected test operation.")
    }
}

private final class CreateRetryClient: TestClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOperations: [UUID] = []
    var operations: [UUID] {
        lock.lock(); defer { lock.unlock() }
        return storedOperations
    }
    override func roomCreate(displayName: String, operationID: UUID) throws -> ARCRoomOpenResult {
        lock.lock(); storedOperations.append(operationID); lock.unlock()
        throw ARCError(.busy, "Retry creation.")
    }
}

private final class HistoryReviewClient: TestClient, @unchecked Sendable {
    private let lock = NSLock()
    private var latest: Int64 = 100
    func advance(to value: Int64) { lock.lock(); latest = value; lock.unlock() }
    override func roomList(afterSafeID: String?) throws -> ARCRoomListPage {
        ARCRoomListPage(rooms: [ARCRoomListItem(id: "room-012345abcdef", name: "History",
            health: .current, failure: nil)], nextSafeId: nil)
    }
    override func roomOpen(room: String) throws -> ARCRoomOpenResult {
        ARCRoomOpenResult(room: testRoom(id: room, name: "History", revision: 1),
            producer: testProducer(), participants: [], work: [])
    }
    override func activityRead(room: String, beforeSequence: Int64?) throws -> ARCActivityPage {
        lock.lock(); let newest = latest; lock.unlock()
        let upper = min(newest, (beforeSequence ?? (newest + 1)) - 1)
        let lower = max(1, upper - 49)
        let events = (lower...upper).reversed().map { sequence in
            ARCEventView(sequence: sequence, at: "2026-09-08T00:00:00.000000Z", logicalUs: sequence,
                kind: "ROOM_RENAMED", actor: "administrator", recipient: nil, subject: nil,
                payload: .object([:]), operationId: "22222222-2222-4222-8222-222222222222",
                knowledgeSha256: String(repeating: "a", count: 64))
        }
        return ARCActivityPage(events: events, nextBefore: lower > 1 ? lower : nil)
    }
}

private final class ChangingRoomClient: TestClient, @unchecked Sendable {
    private let lock = NSLock()
    private var hasAdvanced = false
    private var shouldFailNextOpen = false
    private var storedOpenRequests = 0

    var openRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedOpenRequests
    }

    func advance() {
        lock.lock()
        hasAdvanced = true
        lock.unlock()
    }

    func failNextOpen() {
        lock.lock()
        shouldFailNextOpen = true
        lock.unlock()
    }

    override func roomList(afterSafeID: String?) throws -> ARCRoomListPage {
        ARCRoomListPage(
            rooms: [ARCRoomListItem(
                id: "room-012345abcdef",
                name: "Live room",
                health: .current,
                failure: nil
            )],
            nextSafeId: nil
        )
    }

    override func roomOpen(room: String) throws -> ARCRoomOpenResult {
        lock.lock()
        storedOpenRequests += 1
        let fail = shouldFailNextOpen
        shouldFailNextOpen = false
        let advanced = hasAdvanced
        lock.unlock()
        if fail { throw ARCError(.busy, "That ARC room is busy. Try again.") }
        let phase: ARCParticipantPhase = advanced ? .qualifying : .invited
        let schedule = ARCScheduleView(
            kind: advanced ? .qualification : .none,
            status: advanced ? .request1 : .none,
            nextRequestLogicalUs: advanced ? 40_000_000 : nil,
            deadlineLogicalUs: advanced ? 120_000_000 : nil
        )
        return ARCRoomOpenResult(
            room: testRoom(id: room, name: "Live room", revision: 2),
            producer: testProducer(),
            participants: [testParticipant(phase: phase, schedule: schedule)],
            work: []
        )
    }

    override func activityRead(
        room: String,
        beforeSequence: Int64?
    ) throws -> ARCActivityPage {
        lock.lock()
        let advanced = hasAdvanced
        lock.unlock()
        return ARCActivityPage(
            events: advanced ? [testJoinedEvent()] : [],
            nextBefore: nil
        )
    }
}

private final class PagingRoomClient: TestClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedListRequests = 0

    var listRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedListRequests
    }

    override func roomList(afterSafeID: String?) throws -> ARCRoomListPage {
        lock.lock()
        storedListRequests += 1
        lock.unlock()
        if afterSafeID == nil {
            return ARCRoomListPage(
                rooms: [ARCRoomListItem(
                    id: "room-000000000001",
                    name: "First room",
                    health: .current,
                    failure: nil
                )],
                nextSafeId: "room-000000000001"
            )
        }
        guard afterSafeID == "room-000000000001" else {
            throw ARCError(.invalidArgument, "Unexpected room page.")
        }
        return ARCRoomListPage(
            rooms: [ARCRoomListItem(
                id: "room-000000000002",
                name: "Second room",
                health: .current,
                failure: nil
            )],
            nextSafeId: nil
        )
    }

    override func roomOpen(room: String) throws -> ARCRoomOpenResult {
        ARCRoomOpenResult(
            room: testRoom(id: room, name: "First room", revision: 1),
            producer: testProducer(),
            participants: [],
            work: []
        )
    }
}

private final class RapidSelectionClient: TestClient, @unchecked Sendable {
    private let lock = NSLock()
    private let firstOpenGate = DispatchSemaphore(value: 0)
    private var storedFirstOpenStarted = false
    private var storedOpenedRooms: [String] = []

    var firstOpenStarted: Bool {
        lock.lock()
        defer { lock.unlock() }
        return storedFirstOpenStarted
    }

    var openedRooms: [String] {
        lock.lock()
        defer { lock.unlock() }
        return storedOpenedRooms
    }

    func releaseFirstOpen() { firstOpenGate.signal() }

    override func roomList(afterSafeID: String?) throws -> ARCRoomListPage {
        ARCRoomListPage(
            rooms: [
                ARCRoomListItem(
                    id: "room-000000000001",
                    name: "First room",
                    health: .current,
                    failure: nil
                ),
                ARCRoomListItem(
                    id: "room-000000000002",
                    name: "Second room",
                    health: .current,
                    failure: nil
                ),
            ],
            nextSafeId: nil
        )
    }

    override func roomOpen(room: String) throws -> ARCRoomOpenResult {
        lock.lock()
        storedOpenedRooms.append(room)
        let shouldWait = room == "room-000000000001" && !storedFirstOpenStarted
        if shouldWait { storedFirstOpenStarted = true }
        lock.unlock()
        if shouldWait {
            _ = firstOpenGate.wait(timeout: .now() + 2)
        }
        return ARCRoomOpenResult(
            room: testRoom(
                id: room,
                name: room.hasSuffix("1") ? "First room" : "Second room",
                revision: 1
            ),
            producer: testProducer(),
            participants: [],
            work: []
        )
    }
}

private final class KnowledgeFailureClient: TestClient, @unchecked Sendable {
    private let lock = NSLock()
    private var storedOpenRequests = 0

    var openRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedOpenRequests
    }

    override func roomList(afterSafeID: String?) throws -> ARCRoomListPage {
        ARCRoomListPage(
            rooms: [ARCRoomListItem(
                id: "room-012345abcdef",
                name: "Repair room",
                health: .current,
                failure: nil
            )],
            nextSafeId: nil
        )
    }

    override func roomOpen(room: String) throws -> ARCRoomOpenResult {
        lock.lock()
        storedOpenRequests += 1
        lock.unlock()
        throw ARCError(
            .knowledgeUnavailable,
            "ARC's verified AI instructions are missing."
        )
    }
}

private final class ExpiredQualificationClient: TestClient, @unchecked Sendable {
    private let lock = NSLock()
    private var hasTicked = false
    private var storedTickRequests = 0

    var tickRequests: Int {
        lock.lock()
        defer { lock.unlock() }
        return storedTickRequests
    }

    override func roomList(afterSafeID: String?) throws -> ARCRoomListPage {
        ARCRoomListPage(
            rooms: [ARCRoomListItem(
                id: "room-012345abcdef",
                name: "Qualification room",
                health: .current,
                failure: nil
            )],
            nextSafeId: nil
        )
    }

    override func roomOpen(room: String) throws -> ARCRoomOpenResult {
        lock.lock()
        let ticked = hasTicked
        lock.unlock()
        let schedule = ARCScheduleView(
            kind: ticked ? .none : .qualification,
            status: ticked ? .none : .expired,
            nextRequestLogicalUs: nil,
            deadlineLogicalUs: ticked ? nil : 0
        )
        return ARCRoomOpenResult(
            room: testRoom(id: room, name: "Qualification room", revision: ticked ? 2 : 1),
            producer: testProducer(),
            participants: [testParticipant(
                phase: ticked ? .failed : .qualifying,
                schedule: schedule
            )],
            work: []
        )
    }

    override func roomTick(room: String) throws -> ARCRoomTickResult {
        lock.lock()
        hasTicked = true
        storedTickRequests += 1
        lock.unlock()
        return ARCRoomTickResult(
            room: testRoom(id: room, name: "Qualification room", revision: 2),
            producer: testProducer()
        )
    }
}

private func testRoom(id: String, name: String, revision: Int64) -> ARCRoomView {
    ARCRoomView(
        id: id,
        name: name,
        status: .needsTwoAIs,
        revision: revision,
        protocol: ARCConstants.roomProtocol,
        knowledgeSha256: String(repeating: "a", count: 64),
        logicalUs: 0
    )
}

private func testProducer() -> ARCProducerView {
    ARCProducerView(id: nil, name: nil, generation: 0, live: false)
}

private func testParticipant(
    phase: ARCParticipantPhase,
    schedule: ARCScheduleView
) -> ARCParticipantView {
    ARCParticipantView(
        id: "ai-012345abcdef",
        name: "Atlas",
        phase: phase,
        duty: .notApplicable,
        isProducer: false,
        binding: "11111111-1111-4111-8111-111111111111",
        bindingGeneration: 1,
        schedule: schedule,
        lastCheckIn: nil
    )
}

private func testJoinedEvent() -> ARCEventView {
    ARCEventView(
        sequence: 1,
        at: "2026-08-15T18:00:00.000000Z",
        logicalUs: 1,
        kind: "AI_JOINED",
        actor: "ai-012345abcdef",
        recipient: nil,
        subject: "ai-012345abcdef",
        payload: .object([:]),
        operationId: "22222222-2222-4222-8222-222222222222",
        knowledgeSha256: String(repeating: "a", count: 64)
    )
}

private func removeTemporaryRoot(_ root: URL) {
    guard FileManager.default.fileExists(atPath: root.path) else { return }
    try? FileManager.default.removeItem(at: root)
}
