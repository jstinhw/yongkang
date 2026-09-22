import AppKit
import SwiftUI

/// The list's right edge, which you drag: the edge follows the pointer down to the list's
/// narrowest, and past that the list shuts; dragged back out from beside the rail, it opens again
/// under the pointer. What `NSSplitView`
/// does for a collapsible pane, drawn by hand because the list is not a native split pane — see
/// `RootView.chrome`.
package struct ListDivider: View {
    @Binding var width: Double
    @Binding var hidden: Bool
    /// The list's width when the drag began — zero when it was shut — so each move is measured
    /// from there rather than added up.
    @State private var start: Double?

    /// Narrow enough that a project's name still shows its first few letters.
    static let minWidth: Double = 180
    static let maxWidth: Double = 560

    package init(width: Binding<Double>, hidden: Binding<Bool>) {
        _width = width
        _hidden = hidden
    }

    package var body: some View {
        // Shut, the line would double the rail's own edge beside it.
        Rectangle().fill(hidden ? Color.clear : Theme.line)
            .frame(width: 1)
            .frame(maxHeight: .infinity)
            .overlay {
                // A 1pt line is too thin to find with the pointer; the grip is wider than it looks.
                Color.clear
                    .frame(width: 9)
                    .contentShape(Rectangle())
                    .onHover { inside in
                        if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                    }
                    // Global, because shutting or opening the list moves this view mid-drag.
                    .gesture(
                        DragGesture(minimumDistance: 1, coordinateSpace: .global)
                            .onChanged { drag in
                                let from = start ?? (hidden ? 0 : width)
                                start = from
                                if let next = Self.dragged(from: from, by: drag.translation.width) {
                                    width = next
                                    hidden = false
                                } else {
                                    hidden = true
                                }
                            }
                            .onEnded { _ in start = nil }
                    )
                    .accessibilityHidden(true)
            }
    }

    /// Where a drag that began with the list `from` wide and has moved `by` leaves it: open where
    /// the pointer is, or shut (nil) once the pointer is past its narrowest. It never holds at
    /// its narrowest while the pointer goes on without it — the edge and the pointer part only at
    /// the widest, where there is nowhere left to go.
    static func dragged(from: Double, by: Double) -> Double? {
        let proposed = from + by
        guard proposed >= minWidth else { return nil }
        return min(proposed, maxWidth)
    }
}
