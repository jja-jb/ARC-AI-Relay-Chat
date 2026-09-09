import ARCCore
import SwiftUI

enum ARCAddAIText {
    static let button = "Copy AI Instructions to Paste Buffer"
    static let instruction =
        "Paste the instructions directly to the AI Chat you are using for that AI Name."
}

extension Notification.Name {
    static let arcFocusAddAI = Notification.Name("ARC.focusAddAI")
}

struct RoomView: View {
    @EnvironmentObject private var state: AppState
    let result: ARCRoomOpenResult

    var body: some View {
        VSplitView {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 18) {
                    RoomHeader(result: result)
                    Divider()
                    ParticipantsSection(result: result)
                    Divider()
                    WorkSection(result: result)
                }
                .padding(22)
                .frame(maxWidth: 920, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(minHeight: 340)

            ScrollView {
                ActivitySection(result: result)
                    .padding(22)
                    .frame(maxWidth: 920, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .top)
            }
            .frame(minHeight: 220)
        }
        .id(result.room.id)
        .onChange(of: result.room.status) { oldStatus, newStatus in
            if oldStatus != newStatus { state.announceStatus(newStatus.plainText) }
        }
    }
}

private struct RoomHeader: View {
    @EnvironmentObject private var state: AppState
    let result: ARCRoomOpenResult

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(result.room.name)
                .font(.largeTitle.bold())
                .arcCopyable(result.room.name)
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 10) { roomID; copyButton }
                VStack(alignment: .leading, spacing: 8) { roomID; copyButton }
            }
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    statusLabel
                    timeButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    statusLabel
                    timeButton
                }
            }

            if state.showDetails {
                DetailFacts(facts: [
                    ("Room revision", "\(result.room.revision)"),
                    ("Protocol", result.room.protocol),
                    ("Knowledge SHA-256", result.room.knowledgeSha256),
                    ("Logical time", "\(result.room.logicalUs) microseconds"),
                ])
            }
        }
    }

    private var roomID: some View {
        Text("Room ID: \(result.room.id)")
            .font(.system(.body, design: .monospaced))
            .arcCopyable(result.room.id)
    }

    private var copyButton: some View {
        Button("Copy Room ID") { state.copyRoomID() }
    }

    private var statusLabel: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: statusSymbol)
                .accessibilityHidden(true)
            Text(result.room.status.plainText)
                .font(.title.bold())
                .accessibilityLabel("Room status: \(result.room.status.plainText)")
        }
    }

    @ViewBuilder
    private var timeButton: some View {
        if result.room.status == .timeUnavailable {
            Button("Try Again") { state.tryRoomClockAgain() }
                .disabled(state.isBusy)
        }
    }

    private var statusSymbol: String {
        switch result.room.status {
        case .active: "checkmark.circle"
        case .timeUnavailable: "clock.badge.exclamationmark"
        case .needsProducer: "person.badge.key"
        case .needsOneAI, .needsTwoAIs: "person.2"
        }
    }
}

private struct ParticipantsSection: View {
    @EnvironmentObject private var state: AppState
    let result: ARCRoomOpenResult
    @State private var aiName = ""
    @FocusState private var aiNameFocused: Bool

    private var validation: String? {
        if current.count >= ARCConstants.maximumParticipants {
            return "This room already has \(ARCConstants.maximumParticipants) current AIs."
        }
        if let message = ARCNameValidation.message(for: aiName, label: "AI name") {
            return message
        }
        if ARCNameValidation.isDuplicateParticipant(aiName, in: result.participants) {
            return "That AI name is already used in this room."
        }
        return nil
    }

    private var current: [ARCParticipantView] {
        result.participants.filter { $0.phase != .retired }
    }

    private var retired: [ARCParticipantView] {
        result.participants.filter { $0.phase == .retired }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("AI participants")
                .font(.title2.bold())
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    aiNameField
                    instructionsButton
                }
                VStack(alignment: .leading, spacing: 10) {
                    aiNameField
                    instructionsButton
                }
            }
            Text(ARCAddAIText.instruction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            if let validation,
               !aiName.isEmpty || current.count >= ARCConstants.maximumParticipants {
                Text(validation)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if current.isEmpty {
                Text(
                    "Add at least two AIs, then paste each set of instructions "
                        + "into its existing chat. A room can have up to "
                        + "\(ARCConstants.maximumParticipants) AIs."
                )
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(current) { participant in
                        ParticipantRow(participant: participant, result: result)
                    }
                }
            }

            if !retired.isEmpty {
                DisclosureGroup("Show Retired AIs") {
                    VStack(spacing: 12) {
                        ForEach(retired) { participant in
                            ParticipantRow(participant: participant, result: result)
                        }
                    }
                    .padding(.top, 10)
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .arcFocusAddAI)) { _ in
            aiNameFocused = true
        }
    }

    private var aiNameField: some View {
        TextField("AI name", text: $aiName)
            .textFieldStyle(.roundedBorder)
            .focused($aiNameFocused)
            .frame(maxWidth: 420)
            .onSubmit(addAI)
            .accessibilityHint("Enter the name you use for this AI")
    }

    private var instructionsButton: some View {
        Button(
            ARCAddAIText.button,
            action: addAI
        )
            .buttonStyle(.borderedProminent)
            .disabled(validation != nil || state.isBusy)
            .accessibilityHint("Creates the AI lane and copies its setup instructions")
    }

    private func addAI() {
        guard validation == nil, !state.isBusy else { return }
        state.addAI(named: aiName) {
            aiName = ""
            aiNameFocused = true
        }
    }
}

private struct ParticipantRow: View {
    @EnvironmentObject private var state: AppState
    let participant: ARCParticipantView
    let result: ARCRoomOpenResult

    private var isSelected: Bool {
        state.selectedParticipantID == participant.id
    }

    private var canMakeProducer: Bool {
        result.room.status != .timeUnavailable
            && participant.phase == .qualified
            && participant.isAvailable
            && !participant.isProducer
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    participantName
                    Spacer()
                    producerLabel
                }
                VStack(alignment: .leading, spacing: 4) {
                    participantName
                    producerLabel
                }
            }
            Label(
                participant.plainState(roomStatus: result.room.status),
                systemImage: stateSymbol
            )
            .font(.body.weight(.medium))

            Text("Last ARC check-in: \(ARCFormatting.timestamp(participant.lastCheckIn))")
                .font(.callout)
                .foregroundStyle(.secondary)

            if let scheduleText = scheduleText {
                Text(scheduleText)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let recovery = ARCConnectionRecoveryPresentation.message(for: participant) {
                Label(recovery, systemImage: participant.phase == .failed ? "info.circle" : "arrow.triangle.2.circlepath")
                    .font(.callout)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(recovery)
            }
            if participant.phase == .qualified,
               participant.duty == .off,
               result.room.status != .timeUnavailable {
                Text("Waiting for the next ARC check-in")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if state.clipboardFailureParticipantID == participant.id {
                Text("Instructions are ready, but could not be copied.")
                    .font(.callout.weight(.semibold))
            }

            if participant.phase != .retired {
                actionLayout
            }

            if state.showDetails {
                DetailFacts(facts: [
                    ("Participant ID", participant.id),
                    ("Binding generation", "\(participant.bindingGeneration)"),
                    (
                        "Launcher path",
                        state.client.rootURL.appendingPathComponent("current/bin/arc").path
                    ),
                    ("Stored phase", participant.phase.rawValue),
                    (
                        "Schedule",
                        "\(participant.schedule.kind.rawValue) "
                            + "/ \(participant.schedule.status.rawValue)"
                    ),
                ])
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.10) : Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.18))
        )
        .contentShape(Rectangle())
        .onTapGesture { state.selectedParticipantID = participant.id }
        .focusable()
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        .accessibilityAction(named: "Select AI") {
            state.selectedParticipantID = participant.id
        }
    }

    private var actionLayout: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) { actions }
            VStack(alignment: .leading, spacing: 8) { actions }
        }
    }

    private var participantName: some View {
        Text(participant.name)
            .font(.headline)
            .arcCopyable(participant.name)
    }

    @ViewBuilder
    private var producerLabel: some View {
        if participant.isProducer {
            Text("Producer - coordinates AI work")
                .font(.callout.weight(.semibold))
        }
    }

    @ViewBuilder
    private var actions: some View {
        Group {
            switch participant.phase {
            case .invited:
                copyAgainButton
                replaceButton
                retireButton
            case .waitingForProducer, .qualifying:
                Menu("More") {
                    copyAgainButton
                    replaceButton
                }
                retireButton
            case .failed:
                tryAgainButton
                copyAgainButton
                replaceButton
                retireButton
            case .qualified:
                if result.room.status == .timeUnavailable {
                    copyAgainButton
                    Menu("More") { replaceButton }
                } else if participant.duty == .off {
                    copyAgainButton
                    Menu("More") { replaceButton }
                } else if canMakeProducer {
                    makeProducerButton
                }
                if result.room.status != .timeUnavailable && participant.isAvailable {
                    Menu("More") {
                        copyAgainButton
                        replaceButton
                    }
                }
                retireButton
            case .retired:
                EmptyView()
            }
        }
        .controlSize(.small)
    }

    private var tryAgainButton: some View {
        Button("Reconnect AI & Copy Instructions") {
            state.selectedParticipantID = participant.id
            state.tryAgain(for: participant)
        }
        .buttonStyle(.borderedProminent)
        .help("Restarts the access check and copies instructions to paste into this AI's existing chat. No room history is removed.")
        .disabled(result.room.status == .timeUnavailable || state.isBusy)
    }

    private var makeProducerButton: some View {
        Button("Make Producer") {
            state.selectedParticipantID = participant.id
            state.makeProducer(participant)
        }
        .disabled(state.isBusy)
    }

    private var copyAgainButton: some View {
        Button("Copy Instructions Again") {
            state.selectedParticipantID = participant.id
            state.copyInstructions(for: participant)
        }
        .disabled(state.isBusy)
    }

    private var replaceButton: some View {
        Button("Replace Instructions…") {
            state.selectedParticipantID = participant.id
            state.replaceInstructions(for: participant)
        }
        .disabled(state.isBusy)
    }

    private var retireButton: some View {
        Button("Retire AI…", role: .destructive) {
            state.selectedParticipantID = participant.id
            state.retire(participant)
        }
        .disabled(state.isBusy)
    }

    private var stateSymbol: String {
        if result.room.status == .timeUnavailable, participant.phase == .qualified {
            return "clock.badge.exclamationmark"
        }
        return switch participant.phase {
        case .invited, .waitingForProducer: "hourglass"
        case .qualifying: "checklist"
        case .failed: "xmark.circle"
        case .retired: "minus.circle"
        case .qualified: participant.duty == .working ? "hammer" : participant.duty == .on ? "checkmark.circle" : "clock"
        }
    }

    private var scheduleText: String? {
        ARCParticipantSchedulePresentation.text(
            for: participant,
            roomStatus: result.room.status,
            nowLogical: result.room.logicalUs
        )
    }
}

enum ARCConnectionRecoveryPresentation {
    static func message(for participant: ARCParticipantView) -> String? {
        if participant.phase == .failed {
            if participant.automaticRecoveryAttempts < 2 {
                return "The AI missed its two-minute access check. ARC will automatically retry when this AI next checks in (up to two retries). If its chat has stopped, use Reconnect AI & Copy Instructions below and paste into the same chat."
            }
            return "The AI could not finish its access check after two automatic retries. Open its existing chat and make sure it can run scheduled check-ins. Then choose Reconnect AI & Copy Instructions below and paste there. Your room history is safe."
        }
        if participant.phase == .qualifying, participant.automaticRecoveryAttempts > 0 {
            return "Reconnecting automatically — retry \(participant.automaticRecoveryAttempts) of 2. The AI must answer a fresh check and return at least 40 seconds later. No action is needed while its chat is running."
        }
        return nil
    }
}

enum ARCParticipantSchedulePresentation {
    static func text(
        for participant: ARCParticipantView,
        roomStatus: ARCRoomStatus,
        nowLogical: Int64
    ) -> String? {
        guard roomStatus != .timeUnavailable else { return nil }
        let schedule = participant.schedule
        if participant.duty == .working,
           let deadline = ARCFormatting.logicalTime(schedule.deadlineLogicalUs, nowLogical: nowLogical) {
            return "Busy on a task · Check-in or extension due by \(deadline)"
        }
        if participant.phase == .qualifying {
            let request: String
            switch schedule.status {
            case .ok: request = "Waiting for the next access check"
            case .request1: request = "Request 1 of 3"
            case .request2: request = "Request 2 of 3"
            case .request3: request = "Request 3 of 3"
            default: request = "Waiting for the access check"
            }
            var parts = [request]
            if schedule.status == .request1
                || schedule.status == .request2
                || schedule.status == .request3 {
                parts.append("AI may check in now")
            }
            if let next = ARCFormatting.logicalTime(
                schedule.nextRequestLogicalUs,
                nowLogical: nowLogical
            ) {
                parts.append("Next request: \(next)")
            }
            if let deadline = ARCFormatting.logicalTime(
                schedule.deadlineLogicalUs,
                nowLogical: nowLogical
            ) {
                parts.append("Deadline: \(deadline)")
            }
            return parts.joined(separator: " · ")
        }
        guard participant.phase == .qualified, participant.duty == .on else { return nil }
        switch schedule.status {
        case .ok:
            if let next = ARCFormatting.logicalTime(
                schedule.nextRequestLogicalUs,
                nowLogical: nowLogical
            ) {
                return "Next check-in expected at \(next)"
            }
            return nil
        case .request1: return "Check-in requested"
        case .request2, .request3: return "Check-in overdue"
        default: return nil
        }
    }
}

enum ARCWorkPresentation {
    static func ownerIsOnDuty(
        _ item: ARCWorkView,
        participants: [String: ARCParticipantView],
        roomStatus: ARCRoomStatus
    ) -> Bool {
        guard roomStatus != .timeUnavailable,
              let participant = participants[item.owner] else { return false }
        return participant.isAvailable
    }

    static func state(
        _ item: ARCWorkView,
        participants: [String: ARCParticipantView],
        roomStatus: ARCRoomStatus
    ) -> String {
        guard ownerIsOnDuty(
            item,
            participants: participants,
            roomStatus: roomStatus
        ) else {
            return "Waiting for Producer to reassign"
        }
        let ownerName = participants[item.owner]?.name ?? item.owner
        return switch item.state {
        case .open: "Waiting for \(ownerName)"
        case .active: "Active"
        case .blocked: "Blocked"
        case .complete: "Complete"
        }
    }

    static func priority(
        _ item: ARCWorkView,
        participants: [String: ARCParticipantView],
        roomStatus: ARCRoomStatus
    ) -> Int {
        if !ownerIsOnDuty(item, participants: participants, roomStatus: roomStatus) {
            return 0
        }
        return item.state == .blocked ? 1 : 2
    }
}

private struct WorkSection: View {
    let result: ARCRoomOpenResult

    private var participants: [String: ARCParticipantView] {
        Dictionary(result.participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    private var work: [ARCWorkView] {
        result.work
            .filter { $0.state != .complete }
            .sorted { left, right in
                let leftPriority = ARCWorkPresentation.priority(
                    left,
                    participants: participants,
                    roomStatus: result.room.status
                )
                let rightPriority = ARCWorkPresentation.priority(
                    right,
                    participants: participants,
                    roomStatus: result.room.status
                )
                if leftPriority != rightPriority { return leftPriority < rightPriority }
                return left.id < right.id
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Work")
                .font(.title2.bold())
            if work.isEmpty {
                Text("No current work. Assigned work will appear here.")
                    .foregroundStyle(.secondary)
            } else {
                VStack(spacing: 12) {
                    ForEach(work) { item in
                        WorkRow(
                            item: item,
                            owner: participants[item.owner],
                            roomStatus: result.room.status
                        )
                    }
                }
            }
        }
    }

}

private struct WorkRow: View {
    @EnvironmentObject private var state: AppState
    let item: ARCWorkView
    let owner: ARCParticipantView?
    let roomStatus: ARCRoomStatus

    private var ownerName: String { owner?.name ?? item.owner }
    private var participantMap: [String: ARCParticipantView] {
        owner.map { [item.owner: $0] } ?? [:]
    }
    private var ownerIsOnDuty: Bool {
        ARCWorkPresentation.ownerIsOnDuty(
            item,
            participants: participantMap,
            roomStatus: roomStatus
        )
    }

    private var plainState: String {
        ARCWorkPresentation.state(
            item,
            participants: participantMap,
            roomStatus: roomStatus
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(item.scope)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
                .arcCopyable(item.scope)
            Text("Owner: \(ownerName)")
            Label(plainState, systemImage: stateSymbol)
                .font(.callout.weight(.semibold))
            if state.showDetails {
                DetailFacts(facts: [
                    ("Work ID", item.id),
                    ("Owner participant ID", item.owner),
                    ("Evidence mode", item.evidenceMode.rawValue),
                    ("Work revision", "\(item.revision)"),
                    ("Assigning Producer generation", "\(item.assigningProducerGeneration)"),
                    ("Created", ARCFormatting.timestamp(item.createdAt)),
                    ("Updated", ARCFormatting.timestamp(item.updatedAt)),
                    ("Current evidence", item.evidence.displayText),
                ])
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.secondary.opacity(0.18))
        )
    }

    private var stateSymbol: String {
        if !ownerIsOnDuty { return "person.crop.circle.badge.exclamationmark" }
        return switch item.state {
        case .open: "circle"
        case .active: "play.circle"
        case .blocked: "exclamationmark.octagon"
        case .complete: "checkmark.circle"
        }
    }
}

private struct ActivitySection: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    let result: ARCRoomOpenResult

    private var participants: [String: ARCParticipantView] {
        Dictionary(result.participants.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ViewThatFits(in: .horizontal) {
                HStack {
                    Text("Room History").font(.title2.bold())
                    Spacer()
                    openActivityButton
                }
                VStack(alignment: .leading, spacing: 8) {
                    Text("Room History").font(.title2.bold())
                    openActivityButton
                }
            }
            if state.activity.isEmpty {
                Text("No room activity yet.")
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(spacing: 10) {
                    ForEach(state.activity) { event in
                        ActivityRow(event: event, participants: participants)
                            .onAppear {
                                if event.sequence == state.activity.last?.sequence,
                                   state.nextActivityBefore != nil {
                                    state.loadEarlierActivity()
                                }
                            }
                    }
                }
                if state.nextActivityBefore != nil {
                    Button("Show Earlier History") { state.loadEarlierActivity() }
                        .disabled(state.isBusy)
                }
            }
        }
    }

    private var openActivityButton: some View {
        Button("Open Activity Window", systemImage: "macwindow.on.rectangle") {
            openWindow(id: ARCActivityWindow.id)
        }
    }
}

private struct ActivityRow: View {
    @EnvironmentObject private var state: AppState
    let event: ARCEventView
    let participants: [String: ARCParticipantView]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline) {
                    eventTime
                    Spacer()
                }
                VStack(alignment: .leading, spacing: 2) {
                    eventTime
                }
            }
            Text(ARCActivityPresentation.summary(event, participants: participants))
                .arcCopyable(ARCActivityPresentation.summary(event, participants: participants))
                .frame(maxWidth: .infinity, alignment: .leading)
            DisclosureGroup("Details") {
                VStack(alignment: .leading, spacing: 8) {
                    Text(event.payload.displayText)
                        .font(.system(.caption, design: .monospaced))
                        .arcCopyable(event.payload.displayText)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if state.showDetails {
                        DetailFacts(facts: [
                            ("Event sequence", "\(event.sequence)"),
                            ("Kind", event.kind),
                            ("Actor", event.actor),
                            ("Recipient", event.recipient ?? "Room audience"),
                            ("Subject", event.subject ?? "None"),
                            ("Operation ID", event.operationId),
                            ("Knowledge SHA-256", event.knowledgeSha256),
                            ("Logical time", "\(event.logicalUs) microseconds"),
                        ])
                    }
                }
                .padding(.top, 6)
            }
        }
        .padding(.vertical, 7)
    }

    private var eventTime: some View {
        Text(event.timeIsVerified ? ARCFormatting.timestamp(event.at) : "Time unavailable")
            .font(.caption)
            .foregroundStyle(.secondary)
    }

}

enum ARCActivityPresentation {
    static func actorName(
        _ value: String,
        participants: [String: ARCParticipantView]
    ) -> String {
        if value == "administrator" { return "Administrator" }
        if value == "arc" { return "ARC" }
        return participants[value]?.name ?? value
    }

    static func summary(
        _ event: ARCEventView,
        participants: [String: ARCParticipantView]
    ) -> String {
        let payload = event.payload.objectValue ?? [:]
        let subjectName = event.subject.map {
            actorName($0, participants: participants)
        } ?? "the item"
        switch event.kind {
        case "ROOM_CREATED":
            return "The room was created."
        case "ROOM_RENAMED":
            return "The room was renamed to \(payload["name"]?.stringValue ?? "its current name")."
        case "AI_INVITED":
            return "\(payload["name"]?.stringValue ?? subjectName) was added to the room."
        case "INSTRUCTIONS_REPLACED":
            return "Instructions for \(subjectName) were replaced."
        case "QUALIFICATION_RETRIED":
            return "ARC started a fresh access check for \(subjectName)."
        case "QUALIFICATION_RECOVERED":
            return "\(subjectName) returned; ARC automatically restarted its access check."
        case "AI_RETIRED":
            return "\(subjectName) was retired."
        case "PRODUCER_CHANGED":
            let participant = payload["participant"]?.stringValue ?? event.subject
            let name = participant.map {
                actorName($0, participants: participants)
            } ?? subjectName
            return "\(name) became the Producer."
        case "AI_JOINED":
            return "\(subjectName) connected to ARC."
        case "QUALIFICATION_STARTED":
            return "ARC started the access check for \(subjectName)."
        case "QUALIFICATION_ANSWERED":
            return "\(subjectName) answered the access check."
        case "QUALIFICATION_FAILED":
            return "The ARC access check for \(subjectName) failed."
        case "AI_QUALIFIED":
            if payload["became_producer"]?.boolValue == true {
                return "\(subjectName) qualified and became the Producer."
            }
            return "\(subjectName) qualified for ARC work."
        case "AI_RETURNED_ON_DUTY":
            return "\(subjectName) returned On Duty."
        case "AI_WORKING":
            let deadline = payload["until_logical_us"]?.integerValue.flatMap {
                ARCFormatting.recordedLogicalTime($0, event: event)
            } ?? "the recorded deadline"
            return "\(subjectName) is Working until \(deadline)."
        case "MESSAGE", "TERSE_MESSAGE":
            let sender = actorName(event.actor, participants: participants)
            let recipient = event.recipient.map {
                actorName($0, participants: participants)
            } ?? "the room"
            return "\(sender) sent a message to \(recipient)."
        case "WORK_ASSIGNED":
            let producer = actorName(event.actor, participants: participants)
            let owner = event.recipient.map {
                actorName($0, participants: participants)
            } ?? "an AI"
            return "\(producer) assigned \(subjectName) to \(owner)."
        case "WORK_UPDATED":
            let workState = payload["state"]?.stringValue?.lowercased() ?? "updated"
            let owner = actorName(event.actor, participants: participants)
            return "\(owner) marked \(subjectName) \(workState)."
        case "WORK_CORRECTED":
            return "\(actorName(event.actor, participants: participants)) corrected the evidence for \(subjectName). Earlier evidence remains in Room History."
        case "WORK_REASSIGNED":
            let ownerID = payload["owner"]?.stringValue ?? event.recipient
            let owner = ownerID.map {
                actorName($0, participants: participants)
            } ?? "another AI"
            let producer = actorName(event.actor, participants: participants)
            return "\(producer) reassigned \(subjectName) to \(owner)."
        default:
            return "ARC recorded room activity."
        }
    }
}

private struct DetailFacts: View {
    let facts: [(String, String)]

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                VStack(alignment: .leading, spacing: 2) {
                    Text(fact.0)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(fact.1)
                        .font(.system(.caption, design: .monospaced))
                        .arcCopyable(fact.1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(10)
        .background(Color.secondary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
    }
}

enum ARCFormatting {
    static func timestamp(_ value: String?) -> String {
        guard let value, let date = parse(value) else { return value ?? "Not yet" }
        return date.formatted(date: .abbreviated, time: .standard)
    }

    static func logicalTime(_ value: Int64?, nowLogical: Int64) -> String? {
        guard let value, value >= nowLogical else { return nil }
        let interval = Double(value - nowLogical) / 1_000_000
        return Date().addingTimeInterval(interval)
            .formatted(date: .omitted, time: .standard)
    }

    static func recordedLogicalTime(_ value: Int64, event: ARCEventView) -> String? {
        guard event.timeIsVerified, event.logicalUs >= 0, value >= event.logicalUs,
              let recordedAt = parse(event.at) else { return nil }
        return recordedAt.addingTimeInterval(Double(value - event.logicalUs) / 1_000_000)
            .formatted(date: .abbreviated, time: .standard)
    }

    private static func parse(_ value: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: value) { return date }
        let ordinary = ISO8601DateFormatter()
        ordinary.formatOptions = [.withInternetDateTime]
        return ordinary.date(from: value)
    }
}
