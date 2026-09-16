import Foundation
import Testing

@testable import YongkangUI

/// The design system is only a system while it is the only place a colour is written down.
/// One `Color(hex:)` in a feature file is how the last set of strays got there, so the
/// check is on the source rather than on a reviewer's eye.
@Suite struct DesignTokenTests {

    /// `Sources/YongkangUI/`, found from this file rather than the working directory, which
    /// `swift test` does not promise.
    private static let ui = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()  // YongkangUITests
        .deletingLastPathComponent()  // Tests
        .deletingLastPathComponent()  // repo root
        .appendingPathComponent("Sources/YongkangUI")

    private static func swiftFiles() throws -> [URL] {
        let all = FileManager.default.enumerator(at: ui, includingPropertiesForKeys: nil)
        let urls = (all?.allObjects as? [URL] ?? []).filter { $0.pathExtension == "swift" }
        #expect(urls.count > 40, "found \(urls.count) files under \(ui.path) — is the path right?")
        return urls
    }

    @Test func onlyThemeWritesAColourDown() throws {
        // A hex colour reaches SwiftUI through `Color(hex:)` and nothing else, so that call
        // is the whole surface to guard.
        let strays = try DesignTokenTests.swiftFiles()
            .filter { $0.lastPathComponent != "Theme.swift" }
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("Color(hex:") }
            .map(\.lastPathComponent)
            .sorted()
        #expect(strays.isEmpty, "name these in Theme instead of writing the hex here: \(strays)")
    }

    /// 5.1 renamed sizes; it did not change them. Each role still resolves to the exact
    /// `Typo` call its 142 sites used to spell out, so the shots stayed byte-identical —
    /// and so that the PR that *does* move the scale has to say so here first.
    @Test func eachRoleStillResolvesToTheSizeItReplaced() {
        #expect(Typography.title == Typo.display(22))
        #expect(Typography.headline == Typo.display(15))
        #expect(Typography.body == Typo.text(12))
        #expect(Typography.caption == Typo.text(10.5))
        #expect(Typography.mono == Typo.mono(10))
        #expect(Typography.monoCaption == Typo.mono(9.5))
        #expect(Typography.section == Typo.display(10))
    }
}
