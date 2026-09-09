import AppKit
import SwiftUI

/// SwiftUI's selectable Text creates a SelectionOverlay that can repeatedly
/// invalidate font metrics inside the live room's nested layouts on macOS 26.
/// Keep the main window on SwiftUI's plain text renderer; offer an explicit
/// copy action without creating that overlay. The activity window uses a native
/// NSTextView for range selection and Find instead.
struct ARCCopyText: ViewModifier {
    let text: String

    func body(content: Content) -> some View {
        content
            .contextMenu {
                Button("Copy Text", systemImage: "doc.on.doc") { copy() }
            }
            .accessibilityAction(named: "Copy Text") { copy() }
    }

    private func copy() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

extension View {
    func arcCopyable(_ text: String) -> some View {
        modifier(ARCCopyText(text: text))
    }
}
