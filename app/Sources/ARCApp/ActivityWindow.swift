import AppKit
import ARCCore
import SwiftUI

enum ARCActivityWindow {
    static let id = "room-activity"
}

struct ActivityWindowView: View {
    @EnvironmentObject private var state: AppState
    @State private var followLive = true
    @State private var findRequest = 0

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(state.selectedRoom?.name ?? "Room Activity")
                        .font(.headline)
                        .lineLimit(2)
                    Text("All room activity · Read only")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
                Toggle("Follow Live", isOn: $followLive)
                    .toggleStyle(.switch)
                    .help("When on, new activity scrolls into view. When off, updates continue without moving your reading position.")
            }
            .padding()
            Divider()
            if state.installationReady, state.selectedRoomIsCurrent,
               let result = state.roomResult, result.room.id == state.selectedRoomID {
                ActivityTranscript(
                    roomID: result.room.id,
                    events: state.activity,
                    participants: Dictionary(result.participants.map { ($0.id, $0) },
                        uniquingKeysWith: { first, _ in first }),
                    fontSize: CGFloat([11, 12, 13, 15, 17, 20, 24, 28, 34][max(0, min(state.textSizeIndex, 8))]),
                    followLive: followLive,
                    canLoadEarlier: state.nextActivityBefore != nil && !state.isBusy,
                    loadEarlier: { state.loadEarlierActivity() },
                    findRequest: findRequest
                )
                Divider()
                HStack {
                    Button("Find", systemImage: "magnifyingglass") { findRequest &+= 1 }
                        .help("Find text in the history currently loaded (Command-F).")
                    if state.nextActivityBefore != nil {
                        Button("Show Earlier History") { state.loadEarlierActivity() }
                            .disabled(state.isBusy)
                    } else {
                        Text("Beginning of room history loaded")
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(followLive ? "Following newest activity" : "Live updates · Scroll paused")
                        .foregroundStyle(.secondary)
                }
                .font(.caption)
                .padding(10)
            } else {
                ContentUnavailableView {
                    Label("No Activity to Display", systemImage: "text.bubble")
                } description: {
                    Text(state.selectedRoomID == nil
                        ? "Select a room in the main ARC window. This window follows that selection."
                        : "Waiting for the selected room to be available. Check the main ARC window for details.")
                }
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .dynamicTypeSize(state.textSize)
        .focusedSceneValue(\.arcReadOnlyActivity, true)
        .focusedSceneValue(\.arcActivityFind, { findRequest &+= 1 })
    }
}

private struct ARCReadOnlyActivityKey: FocusedValueKey {
    typealias Value = Bool
}

private struct ARCActivityFindKey: FocusedValueKey {
    typealias Value = () -> Void
}

extension FocusedValues {
    var arcReadOnlyActivity: Bool? {
        get { self[ARCReadOnlyActivityKey.self] }
        set { self[ARCReadOnlyActivityKey.self] = newValue }
    }

    var arcActivityFind: (() -> Void)? {
        get { self[ARCActivityFindKey.self] }
        set { self[ARCActivityFindKey.self] = newValue }
    }
}

/// Formatting is a presentation of the shared room feed, never a second room reader.
enum ARCTranscriptPresentation {
    @MainActor
    static let participantColors: [NSColor] = zip(
        [0x175DA8, 0x7841A0, 0x166B70, 0x86532E, 0x494FAD, 0x286B38, 0xA13766, 0x984A11],
        [0x86BFFF, 0xD1A4F4, 0x75D0D5, 0xDEB48E, 0xB2B7FF, 0x94D4A0, 0xF4A1C4, 0xF4B67D]
    ).map { light, dark in
        NSColor(name: nil) { appearance in
            let rgb = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat((rgb >> 16) & 255) / 255,
                green: CGFloat((rgb >> 8) & 255) / 255, blue: CGFloat(rgb & 255) / 255, alpha: 1)
        }
    }

    static func colorIndex(for participant: String) -> Int {
        // Unlike Swift's Hasher this stays stable across launches and paging.
        var hash: UInt64 = 14_695_981_039_346_656_037
        for byte in participant.utf8 { hash = (hash ^ UInt64(byte)) &* 1_099_511_628_211 }
        return Int(hash % 8)
    }

    static func category(for kind: String) -> String {
        if kind == "MESSAGE" || kind == "TERSE_MESSAGE" { return "Message" }
        if kind.hasPrefix("WORK_") { return "Work" }
        if kind.hasPrefix("QUALIFICATION_") || kind == "AI_QUALIFIED" { return "Access check" }
        if kind == "AI_WORKING" || kind == "AI_RETURNED_ON_DUTY" { return "Duty" }
        return "Room event"
    }

    @MainActor
    static func entry(_ event: ARCEventView, participants: [String: ARCParticipantView],
                      fontSize: CGFloat) -> NSAttributedString {
        let palette = participantColors
        let category = category(for: event.kind)
        let accent: NSColor = switch category {
        case "Message": palette[colorIndex(for: event.actor)]
        case "Work": palette[7]
        case "Access check": palette[1]
        case "Duty": palette[2]
        default: .secondaryLabelColor
        }
        let sender = ARCActivityPresentation.actorName(event.actor, participants: participants)
        let recipient = event.recipient.map {
            ARCActivityPresentation.actorName($0, participants: participants)
        } ?? "Room"
        let time = event.timeIsVerified ? ARCFormatting.timestamp(event.at) : "Time unavailable"
        let heading = "\(category) · \(sender) → \(recipient)\n"
        let output = NSMutableAttributedString(string: heading, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: accent,
        ])
        output.append(NSAttributedString(string: "\(time) · #\(event.sequence) · \(event.kind)\n",
            attributes: [.font: NSFont.systemFont(ofSize: max(11, fontSize - 2)),
                .foregroundColor: NSColor.secondaryLabelColor]))
        let payload = event.payload.objectValue ?? [:]
        var body: String
        if event.kind == "TERSE_MESSAGE", let packet = payload["packet"], let text = try? ARCTerse.build(packet) {
            body = text
        } else if event.kind == "MESSAGE", let text = payload["text"]?.stringValue {
            body = text
        } else {
            body = ARCActivityPresentation.summary(event, participants: participants)
            if event.payload != .object([:]) { body += "\n" + event.payload.displayText }
        }
        if let subject = event.subject { body += "\nSubject: \(subject)" }
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = 3
        paragraph.paragraphSpacing = 5
        output.append(NSAttributedString(string: body + "\n\n", attributes: [
            .font: NSFont.systemFont(ofSize: fontSize), .foregroundColor: NSColor.labelColor,
            .paragraphStyle: paragraph,
        ]))
        return output
    }
}

/// Native plain, selectable text keeps arbitrary AI content inert and supports Copy and Find.
struct ActivityTranscript: NSViewRepresentable {
    let roomID: String
    let events: [ARCEventView]
    let participants: [String: ARCParticipantView]
    let fontSize: CGFloat
    let followLive: Bool
    let canLoadEarlier: Bool
    let loadEarlier: () -> Void
    var findRequest = 0

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.makeScrollView()
    }

    func updateNSView(_ view: NSScrollView, context: Context) {
        context.coordinator.update(self, in: view)
    }

    @MainActor
    final class Coordinator: NSObject {
        private(set) var textView: NSTextView!
        private var previous: ActivityTranscript?
        private var orderedEvents: [ARCEventView] = []
        private var starts: [Int64: Int] = [:]
        private var updating = false
        private var needsInitialScroll = false

        func makeScrollView() -> NSScrollView {
            let scroll = ARCTranscriptScrollView()
            scroll.hasVerticalScroller = true
            scroll.autohidesScrollers = true
            scroll.borderType = .noBorder
            scroll.drawsBackground = true
            scroll.backgroundColor = .textBackgroundColor
            let text = NSTextView(frame: scroll.contentView.bounds)
            text.isEditable = false
            text.isSelectable = true
            text.isRichText = false
            text.importsGraphics = false
            text.allowsUndo = false
            text.usesFindBar = true
            text.isAutomaticLinkDetectionEnabled = false
            text.isAutomaticDataDetectionEnabled = false
            text.textContainerInset = NSSize(width: 18, height: 16)
            text.isVerticallyResizable = true
            text.isHorizontallyResizable = false
            text.autoresizingMask = [.width]
            text.minSize = .zero
            text.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
            text.textContainer?.containerSize = NSSize(width: scroll.contentSize.width,
                height: CGFloat.greatestFiniteMagnitude)
            text.textContainer?.widthTracksTextView = true
            text.setAccessibilityLabel("Room activity, read only")
            scroll.documentView = text
            textView = text
            scroll.viewportResized = { [weak self, weak scroll] in
                guard let self, let scroll, !self.updating, self.previous != nil else { return }
                self.textView.layoutManager?.ensureLayout(for: self.textView.textContainer!)
                self.textView.sizeToFit()
                if self.needsInitialScroll || self.previous?.followLive == true {
                    self.scrollToBottom(scroll)
                }
                self.needsInitialScroll = false
            }
            NotificationCenter.default.addObserver(self, selector: #selector(userScrolled(_:)),
                name: NSScrollView.didLiveScrollNotification, object: scroll)
            return scroll
        }

        deinit { NotificationCenter.default.removeObserver(self) }

        @objc private func userScrolled(_ notification: Notification) {
            guard !updating, let scroll = notification.object as? NSScrollView,
                  scroll.contentView.bounds.minY <= 24, let previous, previous.canLoadEarlier else { return }
            previous.loadEarlier()
        }

        func update(_ input: ActivityTranscript, in scroll: NSScrollView) {
            let old = previous
            previous = input
            if input.findRequest != old?.findRequest, input.findRequest != 0 {
                textView.window?.makeFirstResponder(textView)
                let sender = NSMenuItem()
                sender.tag = NSTextFinder.Action.showFindInterface.rawValue
                textView.performFindPanelAction(sender)
            }
            let roomChanged = old?.roomID != input.roomID
            if roomChanged {
                needsInitialScroll = scroll.contentSize.width <= 0 || scroll.contentSize.height <= 0
            }
            let contentChanged = roomChanged || old?.events != input.events
                || old?.participants != input.participants || old?.fontSize != input.fontSize
            let enabledFollow = input.followLive && old?.followLive == false
            guard contentChanged || enabledFollow else { return }
            updating = true
            defer { updating = false }

            // Anchor by event + UTF-16 character position, not the changing document height.
            // This preserves the visible passage when older pages are inserted above it.
            let oldOrigin = scroll.contentView.bounds.origin
            let anchor = visibleAnchor(in: scroll)
            let selected = textView.selectedRange()
            let oldFirst = orderedEvents.first?.sequence
            let oldNewest = orderedEvents.last?.sequence
            if contentChanged {
                orderedEvents = input.events.sorted { $0.sequence < $1.sequence }
                let output = NSMutableAttributedString(string: "")
                starts = [:]
                for event in orderedEvents {
                    starts[event.sequence] = output.length
                    output.append(ARCTranscriptPresentation.entry(event,
                        participants: input.participants, fontSize: input.fontSize))
                }
                textView.textStorage?.setAttributedString(output)
                textView.layoutManager?.ensureLayout(for: textView.textContainer!)
                textView.sizeToFit()
                if !roomChanged, let oldFirst, let prefix = starts[oldFirst],
                   selected.location != NSNotFound, selected.location + prefix + selected.length <= output.length {
                    textView.setSelectedRange(NSRange(location: selected.location + prefix, length: selected.length))
                } else {
                    textView.setSelectedRange(NSRange(location: 0, length: 0))
                }
            }
            let newActivity = (orderedEvents.last?.sequence ?? 0) > (oldNewest ?? 0)
            if roomChanged || enabledFollow || (input.followLive && newActivity) {
                scrollToBottom(scroll)
            } else if let anchor, let start = starts[anchor.sequence],
                      let layout = textView.layoutManager, let container = textView.textContainer {
                let character = min(start + anchor.offset, max(0, textView.string.utf16.count - 1))
                let glyph = layout.glyphIndexForCharacter(at: character)
                let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
                scroll.contentView.scroll(to: NSPoint(x: 0,
                    y: max(0, rect.minY + textView.textContainerInset.height + anchor.displacement)))
                scroll.reflectScrolledClipView(scroll.contentView)
            } else {
                scroll.contentView.scroll(to: roomChanged ? .zero : oldOrigin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
        }

        private func visibleAnchor(in scroll: NSScrollView) -> (sequence: Int64, offset: Int, displacement: CGFloat)? {
            guard !orderedEvents.isEmpty, !textView.string.isEmpty,
                  let layout = textView.layoutManager, let container = textView.textContainer else { return nil }
            layout.ensureLayout(for: container)
            let y = scroll.contentView.bounds.minY - textView.textContainerInset.height
            let glyph = layout.glyphIndex(for: NSPoint(x: 0, y: max(0, y)), in: container)
            let character = layout.characterIndexForGlyph(at: glyph)
            guard let event = orderedEvents.last(where: { (starts[$0.sequence] ?? Int.max) <= character }),
                  let start = starts[event.sequence] else { return nil }
            let rect = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: 1), in: container)
            return (event.sequence, character - start, y - rect.minY)
        }

        private func scrollToBottom(_ scroll: NSScrollView) {
            scroll.contentView.scroll(to: NSPoint(x: 0,
                y: max(0, textView.frame.height - scroll.contentSize.height)))
            scroll.reflectScrolledClipView(scroll.contentView)
        }
    }
}

private final class ARCTranscriptScrollView: NSScrollView {
    var viewportResized: (() -> Void)?
    private var lastViewportSize: NSSize = .zero

    override func layout() {
        super.layout()
        let size = contentSize
        guard size.width > 0, size.height > 0, size != lastViewportSize else { return }
        lastViewportSize = size
        viewportResized?()
    }
}
