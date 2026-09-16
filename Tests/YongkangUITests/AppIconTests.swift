import AppKit
import Foundation
import SwiftUI
import Testing

@testable import YongkangUI

/// The icon is the one picture the app ships that no shot covers, so its check is here: the
/// view still draws its mark at the size a list row uses.
@Suite @MainActor struct AppIconTests {

    /// The icon at `side` points, one pixel per point, drawn the way `make icon` draws it.
    private func render(side: CGFloat) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: AppIcon(side: side))
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "AppIcon(side: \(side)) rendered nothing")
        return NSBitmapImageRep(cgImage: image)
    }

    /// 16 px is where a mark drawn for 1024 goes blank: the cursor is barely a device pixel
    /// tall there, and it is the whole "an agent is waiting on you" half of the icon.
    @Test func theWaitingCursorSurvivesEveryScale() throws {
        for side in [CGFloat(16), 1024] {
            let rep = try render(side: side)
            #expect(rep.pixelsWide == Int(side) && rep.pixelsHigh == Int(side))
            // The cursor's centre on the 256-grid the view draws on. Amber is the only warm
            // thing in the icon, so "far redder than it is blue" is the whole test — it fails
            // if the block vanishes into the ground or turns into the caret's blue.
            let colour = try #require(
                rep.colorAt(x: Int(side * 158 / 256), y: Int(side * 157 / 256))?
                    .usingColorSpace(.sRGB))
            #expect(
                colour.redComponent > colour.blueComponent + 0.2,
                "the cursor is not amber at \(Int(side)) px: \(colour)")
        }
    }
}
