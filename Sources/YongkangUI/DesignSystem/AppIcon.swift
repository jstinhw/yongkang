import SwiftUI

/// The app icon: `LogoMark` on a dark tile, which is what reads on someone else's Dock.
///
/// Drawn in code rather than exported from an editor, so the asset catalog's 1024 master is
/// reproducible from this file (`make icon`) and a colour change here repaints it. Every
/// coordinate is in units of the 256-grid the design was drawn on, scaled by `side`, so 16 px
/// in a list and 1024 px in the catalog are one picture rather than two drawings that drift.
package struct AppIcon: View {
    private let side: CGFloat

    package init(side: CGFloat) { self.side = side }

    package var body: some View {
        // Apple's continuous-corner ratio, so the tile sits beside the system's own icons.
        let corner = RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
        ZStack {
            corner.fill(
                LinearGradient(
                    colors: [Theme.iconLit, Theme.iconShade],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
            // The inner edge lifts the tile off a dark Dock. It is one grid unit, so it is a
            // hairline at 256 and simply disappears at 16, where there is no room for it.
            corner.strokeBorder(Theme.markLine, lineWidth: side / 256)
            LogoMark(side: side)
        }
        .frame(width: side, height: side)
    }
}
