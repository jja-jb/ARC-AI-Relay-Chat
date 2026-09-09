import AppKit
import ARCCore
import Darwin
import Foundation
import SwiftUI

enum ARCNameValidation {
    static func normalized(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .precomposedStringWithCanonicalMapping
    }

    static func message(for value: String, label: String) -> String? {
        let name = normalized(value)
        guard !name.isEmpty else { return "Enter a \(label.lowercased())." }
        guard name.count <= 80, name.utf8.count <= 512 else {
            return "\(label) must be no more than 80 characters."
        }
        guard !name.contains("/") else { return "\(label) cannot contain a slash." }
        guard !name.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
            return "\(label) cannot contain a control character."
        }
        return nil
    }

    static func isDuplicateParticipant(
        _ value: String,
        in participants: [ARCParticipantView]
    ) -> Bool {
        let name = normalized(value)
        return participants.contains {
            $0.name.compare(name, options: [.caseInsensitive]) == .orderedSame
        }
    }
}

private struct ARCRoomLoad: Sendable {
    let room: ARCRoomOpenResult
    let activity: ARCActivityPage
    let observedFiles: ARCFileStamp
}

private struct ARCRoomListLoad: Sendable {
    let rooms: [ARCRoomListItem]
    let nextSafeID: String?
}

struct ARCFileStamp: Equatable, Sendable {
    struct Fact: Equatable, Sendable {
        let exists: Bool
        let inode: UInt64
        let size: Int64
        let modifiedSeconds: Int64
        let modifiedNanoseconds: Int64
    }

    let facts: [Fact]

    static func read(rootURL: URL, roomID: String) -> ARCFileStamp {
        guard roomID.range(
            of: #"^room-[0-9a-f]{12}$"#,
            options: .regularExpression
        ) != nil else {
            return ARCFileStamp(facts: [])
        }
        let rooms = rootURL.appendingPathComponent("rooms", isDirectory: true)
        let roomName = "\(roomID).arcroom"
        return ARCFileStamp(facts: [roomName, "\(roomName).lock"].map { name in
            var status = stat()
            guard lstat(rooms.appendingPathComponent(name).path, &status) == 0 else {
                return Fact(
                    exists: false,
                    inode: 0,
                    size: 0,
                    modifiedSeconds: 0,
                    modifiedNanoseconds: 0
                )
            }
            return Fact(
                exists: true,
                inode: UInt64(status.st_ino),
                size: Int64(status.st_size),
                modifiedSeconds: Int64(status.st_mtimespec.tv_sec),
                modifiedNanoseconds: Int64(status.st_mtimespec.tv_nsec)
            )
        })
    }
}

enum ARCHandoff {
    static func text(
        rootURL: URL,
        room: ARCRoomView,
        participant: ARCParticipantView,
        operatorLanguage: ARCOperatorLanguage = .english
    ) -> String? {
        guard let binding = participant.binding else { return nil }
        let launcher = rootURL
            .appendingPathComponent("current/bin", isDirectory: true)
            .appendingPathComponent("arc")
            .path
        let arguments = [
            launcher,
            "--root", rootURL.path,
            "guide",
            "--room", room.id,
            "--id", participant.id,
            "--binding", binding,
        ]
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(arguments) else { return nil }
        let argumentLine = String(decoding: data, as: UTF8.self)
        let specifications = rootURL
            .appendingPathComponent("current/specifications", isDirectory: true)
            .path
        return """
        ARC AI setup
        AI name: \(participant.name)
        Room: \(room.name)
        Room ID: \(room.id)
        Participant ID: \(participant.id)
        Installed plain-text specifications: \(specifications)
        \(ARCCommunication.setupText(rootURL: rootURL, language: operatorLanguage))

        Run this exact argument array, without searching for another ARC copy:
        \(argumentLine)
        Read and follow every part of the plain-text guide it returns. Stay inside this
        ARC lane. This is not a one-time setup: poll immediately, arrange a later
        qualifying turn at least 40 seconds after that first poll, then arrange a
        host-supported recurring turn that runs the returned poll about once a minute.
        Carry forward next_after. If ARC reports RETIRED, or ARC has exited or is otherwise
        unavailable, immediately stop and remove every recurring, scheduled, and heartbeat
        automation you created for this ARC participant; do not poll again. The ordinary
        one-minute cadence alone is not enough to complete the first access check. ARC marks
        you Off Duty 180 seconds after your last valid poll unless you have declared Working
        with an unexpired deadline as described in the guide. If the host cannot provide those
        later turns, tell the Administrator plainly instead of claiming readiness.

        """
    }
}

@MainActor
final class AppState: ObservableObject {
    typealias RoomStampProvider = @Sendable (URL, String) -> ARCFileStamp

    @Published var rooms: [ARCRoomListItem] = []
    @Published var selectedRoomID: String?
    @Published var roomResult: ARCRoomOpenResult?
    @Published var activity: [ARCEventView] = []
    @Published var nextActivityBefore: Int64?
    @Published var selectedParticipantID: String?
    @Published var showDetails = false
    @Published var showingCreateRoom = false
    @Published var showingRenameRoom = false
    @Published var showingHelp = false
    @Published var showingPrivacy = false
    @Published var showingDiagnostics = false
    @Published var diagnostic: ARCDiagnosticResult?
    @Published var notice = ""
    @Published var isBusy = false
    @Published var textSizeIndex = 2
    @Published var clipboardFailureParticipantID: String?
    @Published var installationReady = false
    @Published var installationFailure: String?
    @Published private(set) var operatorLanguage: ARCOperatorLanguage = .english
    @Published private(set) var operatorLanguageFailure: String?

    let client: any ARCClientProtocol
    let installation: any ARCInstallationProtocol

    private var pendingRetryKey: String?
    private var pendingOperationID: UUID?
    private var nextRoomSafeID: String?
    private var monitorTask: Task<Void, Never>?
    private var observedRoomFiles: ARCFileStamp?
    private var nextBoundaryUptime: TimeInterval?
    private var isLoadingRoomPage = false
    private var roomOpenPending = false
    private let roomStampProvider: RoomStampProvider
    private let monitorIntervalNanoseconds: UInt64
    private let confirmation: ((String, String, String) -> Bool)?

    init(
        client: any ARCClientProtocol = ARCClient(),
        installation: any ARCInstallationProtocol = ARCInstallation(),
        roomStampProvider: @escaping RoomStampProvider = ARCFileStamp.read,
        monitorIntervalNanoseconds: UInt64 = 1_000_000_000,
        confirmation: ((String, String, String) -> Bool)? = nil
    ) {
        self.client = client
        self.installation = installation
        self.roomStampProvider = roomStampProvider
        self.monitorIntervalNanoseconds = max(10_000_000, monitorIntervalNanoseconds)
        self.confirmation = confirmation
        prepareInstallation()
    }

    var selectedRoom: ARCRoomListItem? {
        rooms.first { $0.id == selectedRoomID }
    }

    var selectedParticipant: ARCParticipantView? {
        roomResult?.participants.first { $0.id == selectedParticipantID }
    }

    var selectedRoomIsCurrent: Bool {
        selectedRoom?.health == .current
    }

    var canMakeSelectedParticipantProducer: Bool {
        guard let participant = selectedParticipant,
              roomResult?.room.status != .timeUnavailable else { return false }
        return participant.isAvailable && !participant.isProducer
    }

    var canRetireSelectedParticipant: Bool {
        selectedParticipant?.phase != .retired && selectedParticipant != nil
    }

    var canDeleteCurrentRoom: Bool {
        guard selectedRoomIsCurrent, let participants = roomResult?.participants else {
            return false
        }
        return participants.allSatisfy { $0.phase == .retired }
            || roomResult?.canDeleteWithoutRetirement == true
    }

    var textSize: DynamicTypeSize {
        let sizes: [DynamicTypeSize] = [
            .small, .medium, .large, .xLarge, .xxLarge, .xxxLarge,
            .accessibility1, .accessibility2, .accessibility3,
        ]
        return sizes[max(0, min(textSizeIndex, sizes.count - 1))]
    }

    func applicationBecameActive() {
        guard installationReady, !isBusy else { return }
        if let selectedRoomID, selectedRoomIsCurrent {
            loadCurrentRoom(selectedRoomID)
        } else {
            reloadRooms(select: selectedRoomID)
        }
    }

    func prepareInstallation(force: Bool = false) {
        guard !isBusy else { return }
        isBusy = true
        installationFailure = nil
        let installation = installation
        let root = client.rootURL
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Swift.Result {
                    try installation.ensureInstalled(rootURL: root, force: force)
                    do { return (try ARCOperatorPreferences.load(rootURL: root), Optional<String>.none) }
                    catch { return (ARCOperatorLanguage.english, Optional(error.localizedDescription)) }
                }
            }.value
            guard let self else { return }
            self.isBusy = false
            switch result {
            case .success(let preference):
                self.installationReady = true
                self.operatorLanguage = preference.0
                self.operatorLanguageFailure = preference.1
                self.notice = ""
                self.reloadRooms()
            case .failure(let error):
                self.installationReady = false
                self.installationFailure = error.localizedDescription
            }
        }
    }

    func setOperatorLanguage(_ language: ARCOperatorLanguage) {
        guard installationReady, !isBusy else { return }
        let root = client.rootURL
        perform({
            try ARCOperatorPreferences.save(language, rootURL: root)
            return language
        }) { [weak self] saved in
            self?.operatorLanguage = saved
            self?.operatorLanguageFailure = nil
            self?.notice = "Operator messages: \(saved.displayName). Applies to all rooms; AIs receive the preference on their next poll."
        }
    }

    func reloadRooms(select requestedRoom: String? = nil) {
        let client = client
        let targetRoom = requestedRoom ?? selectedRoomID
        perform({
            var all: [ARCRoomListItem] = []
            var after: String?
            repeat {
                let page = try client.roomList(afterSafeID: after)
                all.append(contentsOf: page.rooms)
                after = page.nextSafeId
            } while targetRoom != nil
                && !all.contains(where: { $0.id == targetRoom })
                && after != nil
            return ARCRoomListLoad(rooms: all, nextSafeID: after)
        }) { [weak self] load in
            guard let self else { return }
            self.rooms = load.rooms
            self.nextRoomSafeID = load.nextSafeID
            if let requestedRoom,
               load.rooms.contains(where: { $0.id == requestedRoom }) {
                self.selectedRoomID = requestedRoom
            } else if let selectedRoomID,
                      !load.rooms.contains(where: { $0.id == selectedRoomID }) {
                self.selectedRoomID = load.rooms.first?.id
            } else if self.selectedRoomID == nil {
                self.selectedRoomID = load.rooms.first?.id
            }
            if let roomID = self.selectedRoomID, self.roomResult?.room.id == roomID,
               self.selectedRoomIsCurrent {
                self.loadCurrentRoom(roomID)
            } else {
                self.openSelectedRoom()
            }
        }
    }

    func loadMoreRoomsIfNeeded(afterVisibleRoom roomID: String) {
        guard installationReady,
              !isLoadingRoomPage,
              rooms.last?.id == roomID,
              let after = nextRoomSafeID else { return }
        isLoadingRoomPage = true
        let client = client
        Task { [weak self] in
            let result = await Task.detached(priority: .utility) {
                Swift.Result { try client.roomList(afterSafeID: after) }
            }.value
            guard let self else { return }
            self.isLoadingRoomPage = false
            guard self.nextRoomSafeID == after else { return }
            switch result {
            case .success(let page):
                let existing = Set(self.rooms.map(\.id))
                self.rooms.append(contentsOf: page.rooms.filter {
                    !existing.contains($0.id)
                })
                self.nextRoomSafeID = page.nextSafeId
            case .failure(let error):
                self.present(error)
            }
        }
    }

    func selectRoom(_ roomID: String?) {
        selectedRoomID = roomID
        roomOpenPending = true
        openSelectedRoom()
    }

    func createRoom(named rawName: String, completion: (() -> Void)? = nil) {
        guard ARCNameValidation.message(for: rawName, label: "Room name") == nil else { return }
        let name = ARCNameValidation.normalized(rawName)
        let key = "room_create\u{0}\(name)"
        let operationID = retryID(for: key)
        let client = client
        performMutation(key: key, operation: {
            try client.roomCreate(displayName: name, operationID: operationID)
        }) { [weak self] result in
            guard let self else { return }
            let roomID = result.room.id
            self.notice = "Room created. ARC uses this fixed ID to prevent naming errors. "
                + "You can copy it, but not edit it."
            completion?()
            self.reloadRooms(select: roomID)
        }
    }

    func renameCurrentRoom(to rawName: String, completion: (() -> Void)? = nil) {
        guard let roomID = selectedRoomID,
              ARCNameValidation.message(for: rawName, label: "Room name") == nil else { return }
        let name = ARCNameValidation.normalized(rawName)
        let key = "room_rename\u{0}\(roomID)\u{0}\(name)"
        let operationID = retryID(for: key)
        let client = client
        performMutation(key: key, operation: {
            try client.roomRename(
                room: roomID,
                displayName: name,
                operationID: operationID
            )
        }) { [weak self] _ in
            guard let self else { return }
            self.notice = "Room renamed. Its Room ID did not change."
            completion?()
            self.reloadRooms(select: roomID)
        }
    }

    func addAI(named rawName: String, completion: (() -> Void)? = nil) {
        guard let roomID = selectedRoomID,
              ARCNameValidation.message(for: rawName, label: "AI name") == nil else { return }
        let name = ARCNameValidation.normalized(rawName)
        guard !ARCNameValidation.isDuplicateParticipant(
            name,
            in: roomResult?.participants ?? []
        ) else {
            notice = "That AI name is already used in this room."
            return
        }

        let key = "participant_invite\u{0}\(roomID)\u{0}\(name)"
        let operationID = retryID(for: key)
        let client = client
        performMutation(key: key, operation: {
            try client.participantInvite(
                room: roomID,
                name: name,
                operationID: operationID
            )
        }) { [weak self] result in
            guard let self else { return }
            self.copyInstructions(for: result.participant)
            completion?()
            self.loadCurrentRoom(roomID)
        }
    }

    func copyRoomID() {
        guard let room = roomResult?.room else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(room.id, forType: .string) {
            notice = "Room ID copied."
            announce(notice)
        } else {
            notice = "The Room ID could not be copied. Select it and choose Copy."
        }
    }

    /// The Room menu and the visible participant field are one Add AI path.
    func focusAddAI() {
        guard selectedRoomIsCurrent, !isBusy else { return }
        NotificationCenter.default.post(name: .arcFocusAddAI, object: nil)
    }

    func copyInstructions(for participant: ARCParticipantView) {
        guard let room = roomResult?.room,
              let handoff = ARCHandoff.text(
                rootURL: client.rootURL,
                room: room,
                participant: participant,
                operatorLanguage: operatorLanguage
              ) else {
            notice = "ARC could not rebuild the current instructions. Diagnose the room."
            return
        }
        copy(handoff, participantID: participant.id, name: participant.name)
    }

    func replaceInstructions(for participant: ARCParticipantView) {
        guard let roomID = selectedRoomID,
              confirmWithoutMonitor(
                title: "Replace instructions for \(participant.name)?",
                message: "The former instructions will stop working. \(participant.name) "
                    + "returns to Waiting to connect, loses On Duty status, and stops being "
                    + "Producer if currently selected. The room's complete history remains.",
                action: "Replace Instructions"
              ) else { return }
        let key = "participant_replace_instructions\u{0}\(roomID)\u{0}\(participant.id)"
        let operationID = retryID(for: key)
        let client = client
        performMutation(key: key, operation: {
            try client.participantReplaceInstructions(
                room: roomID,
                participant: participant.id,
                operationID: operationID
            )
        }) { [weak self] result in
            guard let self else { return }
            self.copyInstructions(for: result.participant)
            self.loadCurrentRoom(roomID)
        }
    }

    func tryAgain(for participant: ARCParticipantView) {
        guard let roomID = selectedRoomID,
              roomResult?.room.status != .timeUnavailable else { return }
        let key = "participant_try_again\u{0}\(roomID)\u{0}\(participant.id)"
        let operationID = retryID(for: key)
        let client = client
        performMutation(key: key, operation: {
            try client.participantTryAgain(
                room: roomID,
                participant: participant.id,
                operationID: operationID
            )
        }) { [weak self] _ in
            guard let self else { return }
            self.copyInstructions(for: participant)
            self.loadCurrentRoom(roomID)
        }
    }

    func retire(_ participant: ARCParticipantView) {
        guard let roomID = selectedRoomID,
              confirmWithoutMonitor(
                title: "Retire \(participant.name)?",
                message: "Stops \(participant.name) from participating. The room's complete "
                    + "history remains until the room is permanently deleted.",
                action: "Retire AI",
                destructive: true,
                noDefault: true
              ) else { return }
        let key = "participant_retire\u{0}\(roomID)\u{0}\(participant.id)"
        let operationID = retryID(for: key)
        let client = client
        performMutation(key: key, operation: {
            try client.participantRetire(
                room: roomID,
                participant: participant.id,
                operationID: operationID
            )
        }) { [weak self] _ in
            guard let self else { return }
            self.selectedParticipantID = nil
            self.notice = "\(participant.name) was retired. The room's history remains."
            self.loadCurrentRoom(roomID)
        }
    }

    func makeProducer(_ participant: ARCParticipantView) {
        guard let roomID = selectedRoomID,
              roomResult?.room.status != .timeUnavailable,
              participant.phase == .qualified,
              participant.isAvailable else { return }
        let key = "producer_select\u{0}\(roomID)\u{0}\(participant.id)"
        let operationID = retryID(for: key)
        let client = client
        performMutation(key: key, operation: {
            try client.producerSelect(
                room: roomID,
                participant: participant.id,
                operationID: operationID
            )
        }) { [weak self] _ in
            guard let self else { return }
            self.notice = "\(participant.name) is now the Producer."
            self.loadCurrentRoom(roomID)
        }
    }

    func tryRoomClockAgain() {
        guard let roomID = selectedRoomID else { return }
        let client = client
        perform({ try client.roomTick(room: roomID) }) { [weak self] _ in
            self?.loadCurrentRoom(roomID)
        } failure: { [weak self] error in
            guard let self else { return }
            self.present(error)
            self.loadCurrentRoom(roomID)
        }
    }

    func loadEarlierActivity() {
        guard let roomID = selectedRoomID, let before = nextActivityBefore else { return }
        let client = client
        perform({ try client.activityRead(room: roomID, beforeSequence: before) }) {
            [weak self] page in
            guard let self, self.selectedRoomID == roomID else { return }
            let existing = Set(self.activity.map(\.sequence))
            self.activity.append(contentsOf: page.events.filter {
                !existing.contains($0.sequence)
            })
            self.activity.sort { $0.sequence > $1.sequence }
            self.nextActivityBefore = page.nextBefore
        }
    }

    func runDiagnostics() {
        guard let roomID = selectedRoomID else { return }
        let client = client
        perform({ try client.diagnose(room: roomID) }) { [weak self] result in
            self?.diagnostic = result
            self?.showingDiagnostics = true
        }
    }

    func deleteCurrentRoom() {
        let recoveryWarning = roomResult?.canDeleteWithoutRetirement == true
            ? "This room is too full to record all retirements. No AI is currently On Duty or Working. Deletion will end every remaining AI lane without recording retirement. " : ""
        guard canDeleteCurrentRoom,
              let roomID = selectedRoomID,
              let roomName = roomResult?.room.name,
              confirmWithoutMonitor(
                title: "Permanently delete \(roomName)?",
                message: recoveryWarning + "ARC will permanently delete this room and its complete history. "
                    + "This cannot be undone.",
                action: "Delete Room",
                destructive: true,
                noDefault: true
              ) else { return }
        let client = client
        perform({ try client.roomDelete(room: roomID) }) { [weak self] result in
            guard let self, result.deleted else { return }
            self.selectedRoomID = nil
            self.roomResult = nil
            self.activity = []
            self.notice = "Room permanently deleted."
            self.reloadRooms()
        } failure: { [weak self] error in
            guard let self else { return }
            self.present(error)
            self.loadCurrentRoom(roomID)
        }
    }

    func revealDataLocation() {
        let root = client.rootURL
        guard FileManager.default.fileExists(atPath: root.path) else {
            notice = "ARC has not created its data folder yet."
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([root])
    }

    func announceStatus(_ status: String) { announce("Room status: \(status)") }
    func makeSelectedParticipantProducer() {
        if let selectedParticipant { makeProducer(selectedParticipant) }
    }
    func retireSelectedParticipant() {
        if let selectedParticipant { retire(selectedParticipant) }
    }
    func increaseTextSize() { textSizeIndex = min(textSizeIndex + 1, 8) }
    func decreaseTextSize() { textSizeIndex = max(textSizeIndex - 1, 0) }
    func resetTextSize() { textSizeIndex = 2 }

    private func openSelectedRoom() {
        guard installationReady else {
            roomOpenPending = false
            return
        }
        guard !isBusy else {
            roomOpenPending = true
            return
        }
        roomOpenPending = false
        monitorTask?.cancel()
        observedRoomFiles = nil
        nextBoundaryUptime = nil
        selectedParticipantID = nil
        activity = []
        nextActivityBefore = nil
        guard let room = selectedRoom else {
            roomResult = nil
            return
        }
        guard room.health == .current else {
            roomResult = nil
            return
        }
        loadCurrentRoom(room.id)
    }

    private func loadCurrentRoom(_ roomID: String) {
        let client = client
        let roomStampProvider = roomStampProvider
        let rootURL = client.rootURL
        let previousEvents = activity
        let previousBefore = nextActivityBefore
        perform({
            let observedFiles = roomStampProvider(rootURL, roomID)
            let room = try client.roomOpen(room: roomID)
            var page = try client.activityRead(room: roomID, beforeSequence: nil)
            var events = page.events
            if let newest = previousEvents.map(\.sequence).max(),
               let currentNewest = events.map(\.sequence).max(), currentNewest >= newest {
                // Catch up across every intervening page before merging the
                // previously loaded history, so refresh cannot introduce a gap.
                while let before = page.nextBefore,
                      (events.map(\.sequence).min() ?? newest) > newest {
                    let next = try client.activityRead(room: roomID, beforeSequence: before)
                    guard next.nextBefore == nil || next.nextBefore! < before else {
                        throw ARCError(.ioFailure, "ARC could not advance through room history.")
                    }
                    events.append(contentsOf: next.events)
                    page = next
                }
                var bySequence = Dictionary(uniqueKeysWithValues: previousEvents.map { ($0.sequence, $0) })
                for event in events { bySequence[event.sequence] = event }
                page = ARCActivityPage(events: Array(bySequence.values), nextBefore: previousBefore)
            }
            return ARCRoomLoad(
                room: room,
                activity: page,
                observedFiles: observedFiles
            )
        }) { [weak self] load in
            guard let self, self.selectedRoomID == roomID else { return }
            self.roomResult = load.room
            self.activity = load.activity.events.sorted { $0.sequence > $1.sequence }
            self.nextActivityBefore = load.activity.nextBefore
            if let selectedParticipantID = self.selectedParticipantID,
               !load.room.participants.contains(where: { $0.id == selectedParticipantID }) {
                self.selectedParticipantID = nil
            }
            self.scheduleNextTick(for: load.room, observedFiles: load.observedFiles)
        } failure: { [weak self] error in
            guard let self else { return }
            self.present(error)
            self.roomResult = nil
            if (error as? ARCError)?.requiresRoomListRefresh == true {
                self.reloadRooms(select: roomID)
            } else if self.installationReady,
                      self.selectedRoomID == roomID,
                      self.selectedRoomIsCurrent {
                // A normal transient lock or read failure must not kill live
                // observation. Clearing the stamp forces the next iteration
                // to reopen the selected room even if its bytes did not change.
                self.observedRoomFiles = nil
                self.scheduleMonitorIteration(roomID: roomID)
            }
        }
    }

    private func scheduleNextTick(
        for result: ARCRoomOpenResult,
        observedFiles: ARCFileStamp
    ) {
        monitorTask?.cancel()
        observedRoomFiles = observedFiles
        let now = result.room.logicalUs
        let boundaries = result.participants.flatMap { participant in
            [participant.schedule.nextRequestLogicalUs,
             participant.schedule.deadlineLogicalUs]
                .compactMap { $0 }
                .filter { $0 > now }
        }
        let qualificationExpired = result.participants.contains {
            $0.phase == .qualifying && $0.schedule.status == .expired
        }
        if qualificationExpired {
            nextBoundaryUptime = ProcessInfo.processInfo.systemUptime
        } else {
            nextBoundaryUptime = boundaries.min().map { next in
                ProcessInfo.processInfo.systemUptime
                    + Double(min(next - now, 86_400_000_000)) / 1_000_000
            }
        }
        scheduleMonitorIteration(roomID: result.room.id)
    }

    private func scheduleMonitorIteration(roomID: String) {
        monitorTask?.cancel()
        let intervalSeconds = Double(monitorIntervalNanoseconds) / 1_000_000_000
        let remaining = nextBoundaryUptime.map {
            max(0, $0 - ProcessInfo.processInfo.systemUptime)
        }
        let delaySeconds = min(intervalSeconds, remaining ?? intervalSeconds)
        let delay = UInt64(max(0.01, delaySeconds) * 1_000_000_000)
        monitorTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: delay)
            guard !Task.isCancelled,
                  let self,
                  self.selectedRoomID == roomID,
                  self.selectedRoomIsCurrent else { return }
            if let nextBoundaryUptime = self.nextBoundaryUptime,
               ProcessInfo.processInfo.systemUptime >= nextBoundaryUptime {
                if self.isBusy {
                    self.scheduleMonitorIteration(roomID: roomID)
                } else {
                    self.tryRoomClockAgain()
                }
                return
            }
            let stamp = self.roomStampProvider(self.client.rootURL, roomID)
            if stamp != self.observedRoomFiles, !self.isBusy {
                self.loadCurrentRoom(roomID)
            } else {
                self.scheduleMonitorIteration(roomID: roomID)
            }
        }
    }

    private func copy(_ handoff: String, participantID: String, name: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        if pasteboard.setString(handoff, forType: .string) {
            clipboardFailureParticipantID = nil
            notice = "Instructions for \(name) copied. Paste them into that AI's existing chat."
            announce(notice)
        } else {
            clipboardFailureParticipantID = participantID
            notice = "Instructions are ready, but could not be copied."
        }
    }

    private func announce(_ message: String) {
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: message]
        )
    }

    private func retryID(for key: String) -> UUID {
        if pendingRetryKey == key, let pendingOperationID { return pendingOperationID }
        let operationID = UUID()
        pendingRetryKey = key
        pendingOperationID = operationID
        return operationID
    }

    private func finishRetry(_ key: String) {
        if pendingRetryKey == key {
            pendingRetryKey = nil
            pendingOperationID = nil
        }
    }

    private func performMutation<Result: Sendable>(
        key: String,
        operation: @escaping @Sendable () throws -> Result,
        then success: @escaping @MainActor (Result) -> Void
    ) {
        perform(operation) { [weak self] result in
            self?.finishRetry(key)
            success(result)
        } failure: { [weak self] error in
            guard let self else { return }
            let retainForRetry = (error as? ARCError)?.retryable ?? false
            if !retainForRetry {
                self.finishRetry(key)
            }
            self.present(error)
            if self.installationReady, let roomResult = self.roomResult,
               let observedFiles = self.observedRoomFiles,
               self.selectedRoomID == roomResult.room.id {
                self.scheduleNextTick(for: roomResult, observedFiles: observedFiles)
            }
        }
    }

    private func confirm(
        title: String,
        message: String,
        action: String,
        destructive: Bool = false,
        noDefault: Bool = false
    ) -> Bool {
        if let confirmation { return confirmation(title, message, action) }
        let alert = NSAlert()
        alert.messageText = title
        alert.informativeText = message
        alert.alertStyle = destructive ? .warning : .informational
        alert.addButton(withTitle: action)
        alert.addButton(withTitle: "Cancel")
        if destructive { alert.buttons.first?.hasDestructiveAction = true }
        if noDefault { alert.buttons.first?.keyEquivalent = "" }
        alert.buttons.last?.keyEquivalent = "\u{1b}"
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmWithoutMonitor(
        title: String,
        message: String,
        action: String,
        destructive: Bool = false,
        noDefault: Bool = false
    ) -> Bool {
        guard !isBusy else { return false }
        monitorTask?.cancel()
        let accepted = confirm(
            title: title,
            message: message,
            action: action,
            destructive: destructive,
            noDefault: noDefault
        )
        if !accepted,
           let roomResult,
           let observedRoomFiles,
           selectedRoomID == roomResult.room.id {
            scheduleNextTick(for: roomResult, observedFiles: observedRoomFiles)
        }
        return accepted
    }

    private func perform<Result: Sendable>(
        _ operation: @escaping @Sendable () throws -> Result,
        then success: @escaping @MainActor (Result) -> Void,
        failure: (@MainActor (Error) -> Void)? = nil
    ) {
        guard installationReady, !isBusy else { return }
        isBusy = true
        Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Swift.Result { try operation() }
            }.value
            guard let self else { return }
            self.isBusy = false
            switch result {
            case .success(let value): success(value)
            case .failure(let error):
                if let failure { failure(error) }
                else { self.present(error) }
            }
            if self.roomOpenPending, self.installationReady, !self.isBusy {
                self.openSelectedRoom()
            }
        }
    }

    private func present(_ error: Error) {
        if (error as? ARCError)?.code == .knowledgeUnavailable {
            monitorTask?.cancel()
            installationReady = false
            installationFailure = error.localizedDescription
            notice = ""
        } else {
            notice = error.localizedDescription
        }
    }
}
