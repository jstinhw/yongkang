import SwiftUI

/// The app icon: a shell caret with a waiting cursor. Real terminals running real CLIs, and
/// the amber block is the moment one of them needs you — the same amber the console uses for
/// a block, so the Dock and the app agree on what "waiting on you" looks like.
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
            IconCaret()
                .stroke(
                    Theme.accent,
                    style: StrokeStyle(lineWidth: side * 0.078, lineCap: .round, lineJoin: .round))
            IconCursor().fill(Theme.amber)
        }
        .frame(width: side, height: side)
    }
}

/// The `>` of a shell prompt. Left margin 27.3%, which keeps the stroke and its round caps
/// clear of the corner radius at every size.
private struct IconCaret: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 256
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        path.move(to: point(70, 90))
        path.addLine(to: point(108, 128))
        path.addLine(to: point(70, 166))
        return path
    }
}

/// The block cursor, on the caret's baseline: 23.4% wide, 7% tall, rounded by half its height.
private struct IconCursor: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 256
        let box = CGRect(
            x: rect.minX + 128 * unit, y: rect.minY + 148 * unit,
            width: 60 * unit, height: 18 * unit)
        return Path(roundedRect: box, cornerRadius: 9 * unit, style: .continuous)
    }
}
