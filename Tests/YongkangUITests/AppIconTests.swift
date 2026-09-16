import AppKit
import Foundation
import SwiftUI
import Testing

@testable import YongkangUI

/// The icon is the one picture the app ships that no shot covers, and the catalog's master is
/// a build artefact of `AppIcon.swift` (`make icon`). These two checks keep that pair honest:
/// the view still draws its mark at the size a list row uses, and the catalog still points at
/// a 1024 master that is actually on disk.
@Suite @MainActor struct AppIconTests {

    /// The icon at `side` points, one pixel per point, drawn the way `make icon` draws it.
    private func render(side: CGFloat) throws -> NSBitmapImageRep {
        let renderer = ImageRenderer(content: AppIcon(side: side))
        renderer.scale = 1
        let image = try #require(renderer.cgImage, "AppIcon(side: \(side)) rendered nothing")
        return NSBitmapImageRep(cgImage: image)
    }

    /// 16 px is where a mark drawn for 1024 goes blank: the amber stream is one device pixel
    /// wide there, and it is the whole "yours, and waiting on you" half of the icon.
    @Test func theAmberStreamSurvivesEveryScale() throws {
        for side in [CGFloat(16), 1024] {
            let rep = try render(side: side)
            #expect(rep.pixelsWide == Int(side) && rep.pixelsHigh == Int(side))
            // The middle stream on the 256-grid the view draws on. Amber is the only warm thing
            // in the icon, so "far redder than it is blue" is the whole test — it fails if the
            // stream vanishes into the ground or turns into the outer streams' ink.
            let colour = try #require(
                rep.colorAt(x: Int(side * 128 / 256), y: Int(side * 128 / 256))?
                    .usingColorSpace(.sRGB))
            #expect(
                colour.redComponent > colour.blueComponent + 0.2,
                "the middle stream is not amber at \(Int(side)) px: \(colour)")
        }
    }

    @Test func theCatalogNamesTheMasterOnDisk() throws {
        let iconSet = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // YongkangUITests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
            .appendingPathComponent("App/Yongkang/Assets.xcassets/AppIcon.appiconset")
        let json = try JSONSerialization.jsonObject(
            with: Data(contentsOf: iconSet.appendingPathComponent("Contents.json")))
        let images = (json as? [String: Any])?["images"] as? [[String: String]] ?? []
        // One entry; actool generates the rest of the icns family from it. It has to be
        // spelled 512@2x, which is what 1024 px is called in a macOS icon set: 1024@1x builds
        // clean and silently ships no icon at all, so the spelling is worth pinning.
        #expect(
            images == [["filename": "icon-1024.png", "idiom": "mac", "scale": "2x", "size": "512x512"]],
            "one macOS entry at 512@2x, drawn by `make icon`: \(images)")
        for name in images.compactMap({ $0["filename"] }) {
            let master = try #require(
                NSImage(contentsOf: iconSet.appendingPathComponent(name))?.representations.first,
                "\(name) is named by Contents.json but is not on disk — run `make icon`")
            #expect(master.pixelsWide == 1024 && master.pixelsHigh == 1024)
        }
    }
}
