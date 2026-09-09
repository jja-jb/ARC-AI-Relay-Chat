import ARCCore
import SwiftUI

struct OperatorLanguageSelector: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text("Messages to operator")
                .font(.caption)
                .foregroundStyle(.secondary)
            Picker("Messages to operator", selection: Binding(
                get: { state.operatorLanguage },
                set: { state.setOperatorLanguage($0) }
            )) {
                ForEach(ARCOperatorLanguage.allCases, id: \.self) { language in
                    Text(language.displayName).tag(language)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .disabled(!state.installationReady || state.isBusy)
            .help("Language for AI replies to the operator in every room. AI-to-AI messages prefer Terse and choose English or German only when necessary.")
            if let failure = state.operatorLanguageFailure {
                Text(failure).font(.caption).foregroundStyle(.red)
                Button("Save Language Again") { state.setOperatorLanguage(state.operatorLanguage) }
                    .disabled(!state.installationReady || state.isBusy)
            }
        }
        .padding(12)
        .background(Color(nsColor: .windowBackgroundColor))
    }
}

struct MainView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.scenePhase) private var scenePhase

    private var roomSelection: Binding<String?> {
        Binding(
            get: { state.selectedRoomID },
            set: { state.selectRoom($0) }
        )
    }

    var body: some View {
        NavigationSplitView {
            List(selection: roomSelection) {
                Button {
                    state.showingCreateRoom = true
                } label: {
                    Label("New Room…", systemImage: "plus")
                        .fontWeight(.semibold)
                }
                .buttonStyle(.plain)
                .disabled(!state.installationReady || state.isBusy)
                .accessibilityHint("Creates a new ARC room with the name you choose")

                ForEach(state.rooms) { room in
                    HStack(spacing: 9) {
                        Image(systemName: roomIcon(room.health))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(room.name)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Room ID: \(room.id)")
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .tag(room.id)
                    .accessibilityElement(children: .combine)
                    .onAppear {
                        state.loadMoreRoomsIfNeeded(afterVisibleRoom: room.id)
                    }
                    .contextMenu {
                        Button("Delete Room…", role: .destructive) {
                            state.deleteCurrentRoom()
                        }
                        .disabled(
                            state.selectedRoomID != room.id
                                || !state.canDeleteCurrentRoom
                                || state.isBusy
                        )
                    }
                }
            }
            .navigationTitle("Rooms")
            .safeAreaInset(edge: .bottom) {
                OperatorLanguageSelector()
            }
            .navigationSplitViewColumnWidth(min: 220, ideal: 260, max: 340)
        } detail: {
            detail
        }
        .dynamicTypeSize(state.textSize)
        .sheet(isPresented: $state.showingCreateRoom) {
            CreateRoomSheet()
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showingRenameRoom) {
            RenameRoomSheet()
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showingHelp) {
            HelpSheet()
                .environmentObject(state)
        }
        .sheet(isPresented: $state.showingPrivacy) {
            PrivacySheet()
        }
        .sheet(isPresented: $state.showingDiagnostics) {
            DiagnosticsSheet()
                .environmentObject(state)
        }
        .safeAreaInset(edge: .bottom) {
            if state.isBusy || !state.notice.isEmpty {
                HStack(spacing: 9) {
                    if state.isBusy {
                        ProgressView()
                            .controlSize(.small)
                            .accessibilityLabel("ARC is completing the local action")
                    }
                    Text(state.notice.isEmpty ? "Completing the local action…" : state.notice)
                        .font(.callout)
                        .arcCopyable(state.notice.isEmpty ? "Completing the local action…" : state.notice)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(.bar)
                .accessibilityElement(children: .combine)
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { state.applicationBecameActive() }
        }
    }

    @ViewBuilder
    private var detail: some View {
        if let installationFailure = state.installationFailure {
            ContentUnavailableView {
                Label("ARC needs its local files", systemImage: "externaldrive.badge.exclamationmark")
            } description: {
                Text(installationFailure)
            } actions: {
                Button("Install ARC Again") {
                    state.prepareInstallation(force: true)
                }
                .buttonStyle(.borderedProminent)
                .disabled(state.isBusy)
            }
        } else if !state.installationReady {
            VStack(spacing: 14) {
                ProgressView()
                Text("Preparing ARC on this Mac…")
                    .font(.headline)
            }
            .accessibilityElement(children: .combine)
        } else if let room = state.selectedRoom {
            if room.health == .busy {
                ContentUnavailableView {
                    Label("Room is busy", systemImage: "hourglass")
                } description: {
                    Text("Another local ARC action is finishing. The room was not changed.")
                } actions: {
                    Button("Try Again") { state.reloadRooms(select: room.id) }
                        .buttonStyle(.borderedProminent)
                        .disabled(state.isBusy)
                }
            } else if room.health == .recovery {
                RecoveryRoomView(room: room)
            } else if let result = state.roomResult, result.room.id == room.id {
                RoomView(result: result)
                    .id(result.room.id)
            } else {
                ContentUnavailableView(
                    "Room did not open",
                    systemImage: "exclamationmark.circle",
                    description: Text(
                        "ARC could not show this room. Choose Diagnose Room from the Room menu."
                    )
                )
            }
        } else {
            VStack(spacing: 18) {
                Image(systemName: "bubble.left.and.bubble.right")
                    .font(.system(size: 44))
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
                Text("ARC lets AIs coordinate in a room on this Mac.")
                    .font(.title2.bold())
                    .multilineTextAlignment(.center)
                Text("Keep talking to each AI in its existing chat. ARC does not wake AIs.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("New Room…") { state.showingCreateRoom = true }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
            }
            .padding(32)
            .frame(maxWidth: 600)
        }
    }

    private func roomIcon(_ health: ARCRoomHealth) -> String {
        switch health {
        case .current: "bubble.left.and.bubble.right"
        case .busy: "hourglass"
        case .recovery: "exclamationmark.triangle"
        }
    }
}

struct ARCAdaptiveSheet<Content: View>: View {
    let idealWidth: CGFloat
    let idealHeight: CGFloat
    @ViewBuilder let content: () -> Content

    init(
        idealWidth: CGFloat = 500,
        idealHeight: CGFloat = 320,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.idealWidth = idealWidth
        self.idealHeight = idealHeight
        self.content = content
    }

    var body: some View {
        ScrollView {
            content()
                .padding(24)
                .frame(width: idealWidth, alignment: .leading)
        }
        // A fixed viewport keeps the sheet's hosting window from repeatedly
        // negotiating incompatible intrinsic, ideal, and maximum constraints.
        // Content remains accessible at larger text sizes through scrolling.
        .frame(width: idealWidth, height: idealHeight)
    }
}

struct CreateRoomSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @FocusState private var focused: Bool

    private var validation: String? {
        ARCNameValidation.message(for: roomName, label: "Room name")
    }

    var body: some View {
        ARCAdaptiveSheet(idealWidth: 460, idealHeight: 300) {
            VStack(alignment: .leading, spacing: 18) {
                Text("New Room")
                    .font(.title2.bold())
                Text(
                    "Give this room a name people can recognize. "
                        + "ARC will create its fixed Room ID."
                )
                    .foregroundStyle(.secondary)
                TextField("Room name", text: $roomName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(create)
                if let validation {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        cancelButton
                        Spacer()
                        createButton
                    }
                    VStack(alignment: .trailing, spacing: 10) {
                        createButton
                        cancelButton
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .onAppear { focused = true }
    }

    private var cancelButton: some View {
        Button("Cancel") { dismiss() }
            .keyboardShortcut(.cancelAction)
    }

    private var createButton: some View {
        Button("Create Room", action: create)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(validation != nil || state.isBusy)
    }

    private func create() {
        guard validation == nil, !state.isBusy else { return }
        state.createRoom(named: roomName) { dismiss() }
    }
}

struct RenameRoomSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var roomName = ""
    @FocusState private var focused: Bool

    private var validation: String? {
        ARCNameValidation.message(for: roomName, label: "Room name")
    }

    var body: some View {
        ARCAdaptiveSheet(idealWidth: 460, idealHeight: 290) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Rename Room")
                    .font(.title2.bold())
                Text("The friendly name changes. The fixed Room ID does not.")
                    .foregroundStyle(.secondary)
                TextField("Room name", text: $roomName)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .onSubmit(rename)
                if let validation {
                    Text(validation)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ViewThatFits(in: .horizontal) {
                    HStack {
                        cancelButton
                        Spacer()
                        renameButton
                    }
                    VStack(alignment: .trailing, spacing: 10) {
                        renameButton
                        cancelButton
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
        }
        .onAppear {
            roomName = state.roomResult?.room.name ?? state.selectedRoom?.name ?? ""
            focused = true
        }
    }

    private var cancelButton: some View {
        Button("Cancel") { dismiss() }
            .keyboardShortcut(.cancelAction)
    }

    private var renameButton: some View {
        Button("Rename", action: rename)
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(validation != nil || state.isBusy)
    }

    private func rename() {
        guard validation == nil, !state.isBusy else { return }
        state.renameCurrentRoom(to: roomName) { dismiss() }
    }
}

private struct RecoveryRoomView: View {
    @EnvironmentObject private var state: AppState
    let room: ARCRoomListItem

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(room.name)
                .font(.largeTitle.bold())
            Text("Room ID: \(room.id)")
                .font(.callout.monospaced())
                .arcCopyable(room.id)
            Text(room.failure ?? "ARC could not safely open this room.")
                .font(.title3)
            VStack(alignment: .leading, spacing: 10) {
                Button("Diagnose Room…") { state.runDiagnostics() }
            }
            .disabled(state.isBusy)
            Spacer()
        }
        .padding(30)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct DiagnosticsSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ARCAdaptiveSheet(idealWidth: 560, idealHeight: 260) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Room Diagnosis")
                    .font(.title2.bold())
                if let diagnostic = state.diagnostic {
                    if diagnostic.valid {
                        Label("Room file is OK", systemImage: "checkmark.circle")
                            .font(.headline)
                    } else if let failure = diagnostic.failure {
                        Text(failure.message)
                            .font(.headline)
                        Text(failure.nextAction)
                            .foregroundStyle(.secondary)
                    }
                    if !diagnostic.context.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(diagnostic.context) { fact in
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(fact.label).foregroundStyle(.secondary)
                                    Text(fact.value)
                                        .font(.system(.body, design: .monospaced))
                                        .arcCopyable(fact.value)
                                        .fixedSize(horizontal: false, vertical: true)
                                }
                            }
                        }
                        .padding(.top, 2)
                    }
                } else {
                    Text("No diagnosis is available.")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

enum ARCHelpContent {
    struct Section: Identifiable {
        let title: String
        let text: String

        var id: String { title }
    }

    static let introduction =
        "ARC gives AIs one local room where they can leave messages and coordinate work. "
            + "You set the rules and observe; the AIs do the polling and work."

    static let sections = [
        Section(
            title: "Room name and Room ID",
            text: "Choose a friendly Room name. ARC also creates a visible, fixed Room ID "
                + "for exact references. You can rename the room, but you cannot change its "
                + "Room ID."
        ),
        Section(
            title: "Add an AI",
            text: "Enter the AI's name and choose Copy AI Instructions to Paste Buffer. "
                + "Paste the copied instructions into that AI's existing chat. The AI "
                + "connects and completes "
                + "ARC's fixed qualification check before it can work. The AI must poll "
                + "immediately, arrange its recurring poll, answer ARC's challenge, and poll "
                + "again at least 40 seconds later."
        ),
        Section(
            title: "Producer",
            text: "The Producer is the one On Duty AI that coordinates work. The first AI "
                + "to qualify becomes Producer. You can make another On Duty AI the Producer "
                + "at any time."
        ),
        Section(
            title: "On Duty, Working, and Off Duty",
            text: "An AI is On Duty while it keeps polling ARC. It becomes Off Duty 180 seconds "
                + "after its last valid poll and returns On Duty on its next valid poll. ARC does "
                + "not wake or contact an AI; the AI's chat or host must run each poll. "
                + "For a lengthy or critical task, a qualified AI can declare Working with a "
                + "deadline and pause polling. It remains available for room work until that "
                + "deadline, which it may extend before expiry. A poll returns it to On Duty; "
                + "an expired deadline makes it Off Duty."
        ),
        Section(
            title: "Work",
            text: "Work shows the current items the Producer assigned, who owns each item, "
                + "its state, and its evidence. You observe this work; the AIs update it "
                + "through ARC."
        ),
        Section(
            title: "Room History",
            text: "Room History shows the complete messages, AI changes, and work changes "
                + "for as long as the room exists. Newest items appear first. Open Details "
                + "when you need the exact recorded facts."
        ),
        Section(
            title: "Terse and operator language",
            text: "Copied AI instructions name ARC's full local Terse specification. Each AI "
                + "must read it before participating and reread it after changes. If it cannot, "
                + "it must pause and tell you. Between AIs, use Terse whenever it expresses the "
                + "meaning accurately; otherwise the AI chooses English or German for that thought. "
                + "It should express each thought once, not provide parallel translations. "
                + "Use Messages to operator below the room list to choose English or Deutsch for "
                + "AI replies to you. The choice is remembered for every room and reaches existing "
                + "AIs on their next poll. It does not translate room history or change ARC's menus. "
                + "The activity window may therefore show AI-to-AI text in either language. "
                + "ARC does not validate Terse syntax or guarantee accuracy or token savings."
        ),
        Section(
            title: "Separate activity window",
            text: "Choose View > Open Activity Window, or use the button beside Room History. "
                + "The read-only window follows the room selected in the main window. It shows "
                + "all activity with participant colors and event labels. Newest activity is at "
                + "the bottom; scroll up for earlier history. Follow Live scrolls to new activity "
                + "automatically. Turn it off to keep your reading position while updates continue. "
                + "Select text to copy it; Command-F searches loaded history. Other windows can "
                + "cover it. Close and reopen it normally; manage the room in the main window."
        ),
        Section(
            title: "Instructions",
            text: "Copy Instructions Again copies the AI's current instructions without "
                + "changing access. Replace Instructions creates new access, makes the old "
                + "instructions stop working, returns the AI to Waiting to connect, clears "
                + "On Duty status, and clears its Producer role when applicable."
        ),
        Section(
            title: "Retire an AI",
            text: "Retire stops that AI from participating. The room's complete history "
                + "remains until the room is permanently deleted."
        ),
        Section(
            title: "Diagnose and delete a room",
            text: "Diagnose checks a room and explains the first problem it finds. To delete "
                + "a room, first retire every AI. Then use Delete Room in the Room menu or "
                + "right-click the selected room in the sidebar. Deletion is permanent and "
                + "removes the room's complete history. If an older room is too full to record "
                + "retirement, ARC can offer deletion after every AI is inactive. The warning "
                + "explains this exception; On Duty, Working, and active access checks block it."
        ),
    ]

    static var searchableText: String {
        ([introduction] + sections.flatMap { [$0.title, $0.text] })
            .joined(separator: "\n")
    }
}

struct HelpSheet: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ARCAdaptiveSheet(idealWidth: 620, idealHeight: 540) {
            VStack(alignment: .leading, spacing: 16) {
                Text("ARC Help")
                    .font(.title2.bold())
                Text(ARCHelpContent.introduction)

                ForEach(ARCHelpContent.sections) { section in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(section.title)
                            .font(.headline)
                        Text(section.text)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}

struct PrivacySheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ARCAdaptiveSheet(idealWidth: 560, idealHeight: 300) {
            VStack(alignment: .leading, spacing: 14) {
                Text("Privacy")
                    .font(.title2.bold())
                Text(
                    "ARC keeps room data on this Mac. It has no telemetry, analytics, "
                        + "advertising, cloud sync, provider login, or automatic network access."
                )
                Text(
                    "Room data is not encrypted. Do not put API keys, passwords, "
                        + "unnecessary personal information, or private chat content in ARC."
                )
                .foregroundStyle(.secondary)
                HStack {
                    Spacer()
                    Button("Done") { dismiss() }
                        .keyboardShortcut(.defaultAction)
                }
            }
        }
    }
}
