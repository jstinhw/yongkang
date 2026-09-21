import AppKit
import SwiftUI

/// The list's right edge, which you drag: left narrows the list to its narrowest, and past that
/// shuts it; dragged back out from beside the rail, a shut list opens again. What `NSSplitView`
/// does for a collapsible pane, drawn by hand because the list is not a native split pane — see
/// `RootView.chrome`.
package struct ListDivider: View {
    @Binding var width: Double
    @Binding var hidden: Bool
    /// The list's width when the drag began — zero when it was shut — so each move is measured
    /// from there rather than added up.
    @State private var start: Double?

    static let minWidth: Double = 220
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

    /// Where a drag that began with the list `from` wide and has moved `by` leaves it: open at a
    /// width it allows, or shut (nil). Short of its narrowest the list holds there; well past it,
    /// the drag means shut — the snap a collapsible `NSSplitView` pane makes.
    static func dragged(from: Double, by: Double) -> Double? {
        let proposed = from + by
        guard proposed >= minWidth * 0.6 else { return nil }
        return min(max(proposed, minWidth), maxWidth)
    }
}
