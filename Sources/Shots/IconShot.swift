import AppKit
import SwiftUI
import YongkangUI

/// Writes the app icon's 1024 master from the same view the app draws at any size, so the
/// PNG in the asset catalog is a build artefact of `AppIcon.swift` rather than a file nobody
/// can regenerate.
///
///     make icon
enum IconShot {
    /// One master. The catalog's single-size macOS entry is 1024; every smaller size macOS
    /// shows is a downscale of it.
    static let side: CGFloat = 1024

    /// `ImageRenderer` rather than the offscreen window `DesignShots` uses: it takes an
    /// explicit scale, so 1024 points come out as exactly 1024 pixels instead of whatever
    /// backing scale the main display has. The renderer's one blind spot is `ScrollView`,
    /// and the icon is a tile and three strokes.
    @MainActor static func write(to file: URL) -> Bool {
        let renderer = ImageRenderer(content: AppIcon(side: side))
        renderer.scale = 1
        guard let image = renderer.cgImage else {
            print("could not render the icon")
            return false
        }
        guard let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            print("could not encode the icon as PNG")
            return false
        }
        do {
            try png.write(to: file)
        } catch {
            print("could not write \(file.path): \(error.localizedDescription)")
            return false
        }
        print("icon written to \(file.path)")
        return true
    }
}
