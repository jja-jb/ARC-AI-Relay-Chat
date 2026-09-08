import SwiftUI

@main
struct ARCApplication: App {
    @StateObject private var state = AppState()

    var body: some Scene {
        Window("ARC", id: "main") {
            MainView()
                .environmentObject(state)
                .frame(minWidth: 900, minHeight: 650)
        }
        .defaultSize(width: 1_100, height: 760)
        .windowResizability(.contentMinSize)
        .commands {
            ARCMenuCommands(state: state)
        }

        Window("Room Activity", id: ARCActivityWindow.id) {
            ActivityWindowView()
                .environmentObject(state)
                .frame(minWidth: 520, minHeight: 360)
        }
        .defaultSize(width: 760, height: 650)
        .windowResizability(.contentMinSize)
        .defaultLaunchBehavior(.suppressed)
        .restorationBehavior(.disabled)
    }
}

private struct ARCMenuCommands: Commands {
    @ObservedObject var state: AppState
    @Environment(\.openWindow) private var openWindow
    @FocusedValue(\.arcReadOnlyActivity) private var readOnlyActivity
    @FocusedValue(\.arcActivityFind) private var findActivity

    private var hasRoom: Bool { state.installationReady && state.selectedRoom != nil }
    private var hasCurrentRoom: Bool {
        state.installationReady && state.selectedRoomIsCurrent
    }

    var body: some Commands {
        CommandGroup(replacing: .newItem) {
            Button("New Room…") { state.showingCreateRoom = true }
                .keyboardShortcut("n", modifiers: .command)
                .disabled(!state.installationReady || state.isBusy || readOnlyActivity == true)
        }

        CommandMenu("Room") {
            Group {
                Button("Add AI") { state.focusAddAI() }
                    .disabled(!hasCurrentRoom || state.isBusy)
                Button("Rename Room…") { state.showingRenameRoom = true }
                    .disabled(!hasCurrentRoom || state.isBusy)
                Divider()
                Button("Make Selected AI Producer") {
                    state.makeSelectedParticipantProducer()
                }
                .disabled(!state.canMakeSelectedParticipantProducer || state.isBusy)
                Button("Retire Selected AI…") { state.retireSelectedParticipant() }
                    .disabled(!state.canRetireSelectedParticipant || state.isBusy)
                Divider()
                Button("Diagnose Room…") { state.runDiagnostics() }
                    .disabled(!hasRoom || state.isBusy)
                Divider()
                Button("Delete Room…", role: .destructive) {
                    state.deleteCurrentRoom()
                }
                .disabled(!state.canDeleteCurrentRoom || state.isBusy)
            }
            .disabled(readOnlyActivity == true)
        }

        CommandGroup(after: .textEditing) {
            Button("Find in Activity…") { findActivity?() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(findActivity == nil)
        }

        CommandGroup(after: .toolbar) {
            Button("Open Activity Window") { openWindow(id: ARCActivityWindow.id) }
                .keyboardShortcut("l", modifiers: [.command, .shift])
            Divider()
            Toggle("Show Advanced Details", isOn: $state.showDetails)
            Divider()
            Button("Bigger Text") { state.increaseTextSize() }
                .keyboardShortcut("+", modifiers: .command)
            Button("Smaller Text") { state.decreaseTextSize() }
                .keyboardShortcut("-", modifiers: .command)
            Button("Actual Size") { state.resetTextSize() }
                .keyboardShortcut("0", modifiers: .command)
            Divider()
            Button("Reveal ARC Data Location") { state.revealDataLocation() }
        }

        CommandGroup(replacing: .help) {
            Button("ARC Help") { state.showingHelp = true }
                .keyboardShortcut("?", modifiers: .command)
            Button("Privacy") { state.showingPrivacy = true }
        }
    }
}
