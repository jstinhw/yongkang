import SwiftUI

/// A raised panel. Everything that is its own object on a screen sits on one of these.
struct CardSurface: ViewModifier {
    var radius: CGFloat = 12
    var padding: CGFloat = 14
    var border: Color = Theme.line2
    var fill: Color = Theme.card

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .background(RoundedRectangle(cornerRadius: radius).fill(fill))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(border, lineWidth: 1))
    }
}

extension View {
    func cardSurface(
        radius: CGFloat = 12, padding: CGFloat = 14,
        border: Color = Theme.line2, fill: Color = Theme.card
    ) -> some View {
        modifier(CardSurface(radius: radius, padding: padding, border: border, fill: fill))
    }

    /// The selected row treatment used by every list column.
    func rowSelection(_ on: Bool) -> some View {
        background(RoundedRectangle(cornerRadius: 9).fill(on ? Theme.raised : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(on ? Theme.hairline : .clear, lineWidth: 1))
    }
}
