import AppKit
import SwiftUI

extension View {
    /// A right-click Copy, for text that sits in a button or a row a click already answers — a
    /// check that unfolds, a diff line that opens a comment. Making that text selectable would
    /// hand the click to the selection, so it is copied from the menu instead.
    func copyable(_ text: String, label: String = "Copy") -> some View {
        contextMenu {
            Button(label) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(text, forType: .string)
            }
        }
    }
}
