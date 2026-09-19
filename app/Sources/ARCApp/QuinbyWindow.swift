import AppKit
import ARCCore
import SwiftUI

@MainActor
final class QuinbyWindowState: ObservableObject {
    @Published var snapshot: QuinbySnapshot?
    @Published var history: [QuinbyEntry] = []
    @Published var nextBefore: Int64?
    /// Oldest known boundary of an interval skipped by a bounded refresh.
    /// This is not inferred from sequence gaps: operational frames are hidden.
    @Published private(set) var historyGapThrough: Int64?
    /// Set only by a user action. It stays visible until the next action
    /// starts, so a failed send is not wiped by the next background refresh.
    @Published var error = ""
    /// Set only by the background refresh and cleared when one succeeds.
    @Published var refreshError = ""
    /// True only while a user action is in flight. The once-a-second refresh
    /// never sets it, so controls stay enabled and clicks are never dropped.
    @Published var busy = false
    @Published var message = ""
    @Published var aiName = ""
    @Published var copied = ""
    private let store: QuinbyStore
    private var pendingID: UUID?
    private var pendingKey: String?
    private var refreshing = false

    init(root: URL) { store = QuinbyStore(rootURL: root) }

    var displayError: String { error.isEmpty ? refreshError : error }

    func refresh() async {
        guard !refreshing, !busy else { return }
        refreshing = true
        defer { refreshing = false }
        do {
            let store = store
            let value = try await Task.detached { try store.snapshot() }.value
            accept(value)
            if !refreshError.isEmpty { refreshError = "" }
        } catch {
            refreshError = error.localizedDescription
            snapshot?.listening = false
            snapshot?.status = "Quinby cannot record."
        }
    }

    private func accept(_ value: QuinbySnapshot) {
        if let current = snapshot, current.incarnation != value.incarnation {
            history = []; nextBefore = value.page.nextBefore; historyGapThrough = nil
            message = ""; copied = ""
        }
        if snapshot == nil { nextBefore = value.page.nextBefore }
        if let current = snapshot, current.incarnation == value.incarnation,
           value.sequence > current.sequence, let before = value.page.nextBefore,
           !value.page.entries.contains(where: { $0.sequence <= current.sequence }) {
            // The newest bounded page no longer overlaps our last snapshot.
            // Expose the missing interval, even if all earlier history was
            // already loaded. Paging may revisit known rows; merge deduplicates.
            nextBefore = max(nextBefore ?? 0, before)
            historyGapThrough = min(historyGapThrough ?? current.sequence, current.sequence)
        }
        merge(value.page.entries)
        // Publish only real changes, so the conversation is not rebuilt and
        // the scroll position does not jump once a second.
        if snapshot != value { snapshot = value }
    }

    private func merge(_ entries: [QuinbyEntry]) {
        var bySequence = Dictionary(uniqueKeysWithValues: history.map { ($0.sequence, $0) })
        for entry in entries { bySequence[entry.sequence] = entry }
        let merged = bySequence.values.sorted { $0.sequence < $1.sequence }
        if merged != history { history = merged }
    }

    private func operation(_ key: String) -> UUID {
        if pendingKey == key, let pendingID { return pendingID }
        let id = UUID(); pendingID = id; pendingKey = key; return id
    }

    private func perform(_ body: @escaping @Sendable (QuinbyStore) throws -> QuinbyInvitation?, after: (() -> Void)? = nil) {
        guard !busy else { return }
        busy = true; error = ""; copied = ""
        let store = store
        Task {
            do {
                let invitation = try await Task.detached { try body(store) }.value
                if let invitation {
                    NSPasteboard.general.clearContents()
                    if NSPasteboard.general.setString(invitation.instructions, forType: .string) {
                        copied = "AI instructions copied. Paste them into that AI's own chat."
                    } else { error = "The AI was added, but copying failed. Use Copy Instructions to try again." }
                }
                pendingID = nil; pendingKey = nil
                after?()
            } catch { self.error = error.localizedDescription }
            busy = false
            if error.isEmpty { await refresh() }
        }
    }

    func toggle() {
        guard let snapshot else { return }
        let enabled = !snapshot.enabled, id = operation("enable:\(!snapshot.enabled)")
        perform { store in try store.setEnabled(enabled, operation: id); return nil }
    }

    func add() {
        let name = aiName, id = operation("invite:\(aiName)")
        perform({ try $0.invite(name: name, operation: id) }, after: { self.aiName = "" })
    }

    func copy(_ id: String) { perform { try $0.instructions(participant: id) } }

    func change(_ member: QuinbyParticipant, action: String) {
        let id = operation("\(action):\(member.id)")
        perform { try $0.changeParticipant(member.id, action: action, operation: id) }
    }

    func send() {
        // Return in the field reaches here even while the Send button is
        // disabled, so the same conditions are checked again.
        let text = message
        guard snapshot?.listening == true,
              !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        let id = operation("message:\(text)")
        perform({ try $0.humanMessage(text, operation: id); return nil }, after: {
            // Clear only what was sent; keep anything typed while it was in flight.
            if self.message == text { self.message = "" }
        })
    }

    func reset() {
        // With no readable snapshot, the store verifies corruption or an older
        // format under its lock before removing an unreadable record.
        let incarnation = snapshot?.incarnation ?? ""
        let id = operation("reset:\(incarnation)")
        perform({ try $0.reincarnate(incarnation: incarnation, operation: id); return nil }, after: {
            self.history = []; self.snapshot = nil; self.nextBefore = nil
            self.historyGapThrough = nil
            self.message = ""; self.copied = ""
        })
    }

    func earlier() {
        guard let before = nextBefore, !busy else { return }
        busy = true
        let store = store
        Task {
            do {
                let value = try await Task.detached { try store.snapshot(before: before) }.value
                guard value.incarnation == self.snapshot?.incarnation else {
                    busy = false
                    await refresh()
                    return
                }
                // Merge the older page only; the latest snapshot stays current.
                merge(value.page.entries); nextBefore = value.page.nextBefore
                if nextBefore == nil || historyGapThrough.map({ boundary in
                    value.page.entries.contains { $0.sequence <= boundary }
                }) == true { historyGapThrough = nil }
            } catch { self.error = error.localizedDescription }
            busy = false
        }
    }
}

struct QuinbyWindowView: View {
    @EnvironmentObject private var app: AppState
    var body: some View {
        Group {
            if app.installationReady {
                QuinbyContentView(root: app.client.rootURL)
                    .dynamicTypeSize(app.textSize)
            } else {
                ContentUnavailableView("ARC needs its support files", systemImage: "folder.badge.questionmark",
                    description: Text("Return to the ARC window to complete installation."))
            }
        }
        .frame(minWidth: 680, minHeight: 620)
    }
}

struct QuinbyContentView: View {
    let root: URL
    @StateObject private var state: QuinbyWindowState
    @State private var section = "Conversation"
    @State private var confirmReset = false
    @State private var removeMember: QuinbyParticipant?
    @State private var replaceMember: QuinbyParticipant?
    @State private var showAIs = true
    @FocusState private var composing: Bool

    private static let recordTime: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    init(root: URL, model: QuinbyWindowState? = nil) {
        self.root = root
        _state = StateObject(wrappedValue: model ?? QuinbyWindowState(root: root))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 16) {
                if let image = NSImage(contentsOf: root.appendingPathComponent("current/quinby/quinby-headshot.png")) {
                    Image(nsImage: image).resizable().scaledToFit().frame(width: 84, height: 84)
                        .clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityLabel("Quinby")
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quinby's Corner").font(.largeTitle.bold())
                    Text(state.snapshot?.status ?? "Opening Quinby's record…")
                        .foregroundStyle(state.snapshot?.listening == true ? Color.primary : Color.secondary)
                }
                Spacer(minLength: 12)
                Button(state.snapshot?.enabled == true ? "Turn Off" : "Turn On") { state.toggle() }
                    .disabled(state.busy || state.snapshot == nil)
            }
            Text("Quinby hears every ARC room only while on with an available AI. What he hears stays in his record, even after a room is deleted.")
                .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)

            DisclosureGroup("Contributing AIs (\(state.snapshot?.participants.count ?? 0))", isExpanded: $showAIs) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        TextField("AI name", text: $state.aiName).textFieldStyle(.roundedBorder)
                            .onSubmit { state.add() }
                        Button("Add AI and Copy Instructions") { state.add() }
                            .disabled(state.busy || state.aiName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    Text("Paste the instructions into a separate AI chat for this Corner.").font(.caption).foregroundStyle(.secondary)
                    if !state.copied.isEmpty { Text(state.copied).font(.caption).foregroundStyle(.secondary) }
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 6) {
                            ForEach(state.snapshot?.participants ?? []) { member in
                                HStack {
                                    Text(member.name).fontWeight(.medium)
                                    Text(label(member)).font(.caption).foregroundStyle(.secondary)
                                    Text(Self.meter(member.usage)).font(.caption).foregroundStyle(.secondary)
                                        .help("Polls, waits, reads, acts and bytes ARC served to this AI in the last hour, then lifetime polls and bytes.")
                                    if member.phase == .qualified, member.duty != .off,
                                       member.usage.headless(now: Int64(Date().timeIntervalSince1970 * 1_000_000)) {
                                        Label(ARCFormatting.headless(member.usage, now: Int64(Date().timeIntervalSince1970 * 1_000_000)),
                                              systemImage: "exclamationmark.triangle").font(.caption)
                                            .help("A script alone can keep a lane On Duty. Ask this AI's chat whether it is still running; if not, remove the AI.")
                                    }
                                    Spacer()
                                    Menu("Actions") {
                                        Button("Copy Instructions") { state.copy(member.id) }
                                        Button("Reconnect") { state.change(member, action: "retry") }
                                        Button("Replace Instructions…") { replaceMember = member }
                                        Button("Remove AI…", role: .destructive) { removeMember = member }
                                    }.disabled(state.busy)
                                }
                            }
                        }
                    }.frame(maxHeight: 110)
                }.padding(.top, 8)
            }
            Divider()
            Picker("View", selection: $section) {
                Text("Conversation").tag("Conversation")
                Text("Summary").tag("Summary")
                Text("Record").tag("Record")
            }.pickerStyle(.segmented)

            if section != "Summary", state.historyGapThrough != nil {
                HStack {
                    Label("Some intervening history is not loaded.", systemImage: "exclamationmark.circle")
                        .font(.callout)
                    Spacer()
                    Button("Load Missing History") { state.earlier() }.disabled(state.busy)
                }
                .padding(8)
                .background(.yellow.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        if section == "Summary" {
                            Text(state.snapshot?.summary?.text ?? "").frame(maxWidth: .infinity, alignment: .leading)
                                .arcCopyable(state.snapshot?.summary?.text ?? "")
                        } else {
                            if state.nextBefore != nil {
                                Button("Load Earlier") { state.earlier() }.disabled(state.busy)
                            }
                            ForEach(visibleEntries) { entry in
                                entryRow(entry).id(entry.id)
                            }
                            if section == "Conversation", visibleEntries.isEmpty {
                                Text("Quinby's conversation begins here. His AIs choose what he says, and he may choose not to answer.")
                                    .foregroundStyle(.secondary).padding(.vertical)
                            }
                        }
                    }.padding(.trailing, 6)
                }
                // Follow new entries at the bottom. Loading earlier history
                // leaves the newest entry unchanged, so it never jumps.
                .onChange(of: visibleEntries.last?.id) { _, newest in
                    guard let newest else { return }
                    withAnimation { proxy.scrollTo(newest, anchor: .bottom) }
                }
                .onChange(of: section) { _, _ in
                    if let newest = visibleEntries.last?.id { proxy.scrollTo(newest, anchor: .bottom) }
                }
            }
            if state.snapshot?.assignments.contains(where: { $0.kind == "reply" }) == true {
                Text("Waiting for Quinby. Working AIs may take time to respond.").font(.caption).foregroundStyle(.secondary)
            }
            HStack(alignment: .bottom) {
                TextField("Chat with Quinby", text: $state.message, axis: .vertical)
                    .lineLimit(2...5).textFieldStyle(.roundedBorder)
                    .focused($composing)
                    .onSubmit { state.send() }
                    .onKeyPress(.return, phases: .down) { press in
                        // Plain Return sends; Shift-Return or Option-Return starts a new line.
                        guard press.modifiers.contains(.shift) || press.modifiers.contains(.option) else { return .ignored }
                        state.message += "\n"
                        return .handled
                    }
                Button("Send") { state.send() }
                    .disabled(!canSend)
            }
            if state.snapshot?.listening == true {
                Text("Return sends. Shift-Return starts a new line.").font(.caption).foregroundStyle(.secondary)
            } else if let status = state.snapshot?.status {
                // The draft is kept, and the reason sending is unavailable is shown.
                Text("Sending is unavailable: \(status)").font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if !state.displayError.isEmpty { Text(state.displayError).font(.callout).foregroundStyle(.red) }
                Spacer()
                Button("Kill and Reincarnate…", role: .destructive) { confirmReset = true }
                    .disabled(state.busy || (state.snapshot == nil && state.refreshError.isEmpty))
            }
        }
        .padding(20)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear { composing = true }
        .task {
            while !Task.isCancelled {
                await state.refresh()
                try? await Task.sleep(for: .seconds(1))
            }
        }
        .alert("Permanently erase this Quinby?", isPresented: $confirmReset) {
            Button("Cancel", role: .cancel) {}
            Button("Kill and Reincarnate", role: .destructive) { state.reset() }
        } message: {
            Text("All of his records, summaries, conversations, observations, and AI memberships will be permanently deleted. A new Quinby starts Off with his original Brightshelf profile and no AIs. There is no undo.")
        }
        .alert("Remove this AI?", isPresented: Binding(get: { removeMember != nil }, set: { if !$0 { removeMember = nil } })) {
            Button("Cancel", role: .cancel) { removeMember = nil }
            Button("Remove AI", role: .destructive) {
                if let member = removeMember { state.change(member, action: "remove") }; removeMember = nil
            }
        } message: { Text("Its contributions remain part of Quinby's permanent record.") }
        .alert("Replace this AI's instructions?", isPresented: Binding(get: { replaceMember != nil }, set: { if !$0 { replaceMember = nil } })) {
            Button("Cancel", role: .cancel) { replaceMember = nil }
            Button("Replace") {
                if let member = replaceMember { state.change(member, action: "replace") }; replaceMember = nil
            }
        } message: { Text("The old connection will stop working. Paste the new instructions into the AI's chat.") }
    }

    private var visibleEntries: [QuinbyEntry] {
        section == "Record" ? state.history : state.history.filter { ["human", "reply", "refusal", "silence"].contains($0.kind) }
    }

    private var canSend: Bool {
        !state.busy && state.snapshot?.listening == true
            && !state.message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    @ViewBuilder
    private func entryRow(_ entry: QuinbyEntry) -> some View {
        if entry.kind == "silence", section == "Conversation" {
            // An explicit silence is a recorded AI disposition. It is shown as
            // interface status, never as Quinby's speech, and nothing is added
            // to explain it.
            Text("No reply. Quinby's AI chose silence.")
                .font(.callout).italic().foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 12)
        } else {
            VStack(alignment: .leading, spacing: 5) {
                HStack {
                    Text(entryLabel(entry)).font(.headline)
                    Spacer()
                    Text(Self.displayTime(entry.at)).font(.caption2.monospaced()).foregroundStyle(.secondary)
                        .help(entry.at)
                }
                if !entry.text.isEmpty { Text(entry.text).arcCopyable(entry.text) }
                if section == "Record" {
                    Text("Record \(entry.sequence) · \(entry.author)").font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(entry.observations.enumerated()), id: \.offset) { _, observation in
                        VStack(alignment: .leading, spacing: 4) {
                            Text("\(observation.roomName) · \(observation.actorName) · \(observation.kind)").font(.subheadline.bold())
                            Text(observation.payload.displayText).font(.callout)
                                .arcCopyable(observation.payload.displayText)
                        }
                    }
                }
            }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(entry.kind == "human" ? Color.accentColor.opacity(0.08) : Color.secondary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    private func entryLabel(_ entry: QuinbyEntry) -> String {
        switch entry.kind {
        case "human": return "You"
        case "reply", "refusal": return "Quinby"
        default: return entry.kind
        }
    }

    /// Local, readable time for the conversation; the exact recorded UTC
    /// timestamp remains available as the hover help text.
    static func displayTime(_ raw: String) -> String {
        var text = raw
        if let dot = text.firstIndex(of: "."), let end = text.lastIndex(of: "Z"), dot < end {
            let fraction = text[text.index(after: dot)..<end]
            text = String(text[..<dot]) + "." + String(fraction.prefix(3)) + "Z"
        }
        guard let date = Self.recordTime.date(from: text) else { return raw }
        let style: Date.FormatStyle = Calendar.current.isDateInToday(date)
            ? .init(date: .omitted, time: .shortened)
            : .init(date: .abbreviated, time: .shortened)
        return date.formatted(style)
    }

    /// The cost meter: what ARC served this AI in the last hour, then lifetime.
    static func meter(_ usage: QuinbyUsage) -> String {
        let hour = "\(usage.pollsLastHour) polls, \(usage.waitsLastHour) waits, \(usage.readsLastHour) reads, \(usage.actsLastHour) acts, \(ARCFormatting.bytes(usage.bytesServedLastHour))/h"
        return "\(hour) · total \(usage.pollsTotal) polls, \(ARCFormatting.bytes(usage.bytesServedTotal))"
    }

    private func label(_ member: QuinbyParticipant) -> String {
        if member.phase == .qualified {
            switch member.duty { case .on: return "On Duty"; case .working: return "Working"; default: return "Off Duty" }
        }
        switch member.phase {
        case .invited: return "Waiting to connect"
        case .qualifying: return "Checking ARC access"
        case .failed: return "ARC access check failed"
        default: return member.phase.rawValue
        }
    }
}
