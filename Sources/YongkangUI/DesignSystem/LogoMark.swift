import SwiftUI

/// The mark without its tile: three streams joining one current. 永, the "yong" of Yongkang,
/// began as a picture of water running a long way, and that is the work here — separate
/// streams, from agents and from people, leaving as one. The middle stream is amber because it
/// is yours: the same amber the console uses for a block, so the Dock and the app agree on what
/// "waiting on you" looks like.
///
/// `AppIcon` puts it on the tile and the fleet header draws it bare, so every copy of the logo
/// is this one view. Coordinates are on the 256-grid the design was drawn on, scaled by `side`;
/// the streams span 50–206 across and 44–212 down, centred, so any square frame centres the
/// mark.
package struct LogoMark: View {
    private let side: CGFloat

    package init(side: CGFloat) {
        self.side = side
    }

    /// The mark in its own 172 × 184 box rather than the icon's square, for setting beside
    /// text: the box is centred on the grid, so the frame trims the margin without moving the
    /// streams, and the mark lines up with whatever edge the text does.
    package func trimmed() -> some View {
        frame(width: side * 172 / 256, height: side * 184 / 256)
    }

    package var body: some View {
        // 16 units: at 32 px each stream is still its own 2 px line.
        let stream = StrokeStyle(lineWidth: side * 16 / 256, lineCap: .round)
        ZStack {
            LogoSideStreams().stroke(Theme.tx, style: stream)
            LogoMainStream().stroke(Theme.amber, style: stream)
        }
        .frame(width: side, height: side)
    }
}

/// The two outer streams, mirrored about the centre. Each leaves a top corner, bends in between
/// y 116 and 160, and runs 24 units from the middle stream to the mouth — an 8-unit channel,
/// half a stroke, which is the narrowest gap that still opens at 32 px.
private struct LogoSideStreams: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 256
        func point(_ x: CGFloat, _ y: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + x * unit, y: rect.minY + y * unit)
        }
        var path = Path()
        for (source, channel) in [(CGFloat(58), CGFloat(104)), (198, 152)] {
            path.move(to: point(source, 52))
            path.addCurve(
                to: point(channel, 160), control1: point(source, 120),
                control2: point(channel, 116))
            path.addLine(to: point(channel, 204))
        }
        return path
    }
}

/// The amber current: the only stream that never turns, top to mouth on the centre line.
private struct LogoMainStream: Shape {
    func path(in rect: CGRect) -> Path {
        let unit = rect.width / 256
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 128 * unit, y: rect.minY + 52 * unit))
        path.addLine(to: CGPoint(x: rect.minX + 128 * unit, y: rect.minY + 204 * unit))
        return path
    }
}
