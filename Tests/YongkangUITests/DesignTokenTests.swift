import Foundation
import SwiftUI
import Testing

@testable import YongkangUI

/// The design system is only a system while it is the only place a colour or a size is
/// written down. One `Color(hex:)` in a feature file is how the last set of strays got
/// there, so the checks are on the source rather than on a reviewer's eye.
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

    /// The whole scale, written out against SwiftUI rather than against `Typo`, so this fails
    /// on a changed size, a changed weight *and* a changed face. Seven roles, one size each:
    /// a PR that wants an eighth size has to add it here first, where the ramp it would
    /// restart is visible on one screen.
    @Test func everyRoleResolvesToItsOneSize() {
        #expect(Typography.title == .system(size: 22, weight: .semibold))
        #expect(Typography.headline == .system(size: 15, weight: .semibold))
        #expect(Typography.body == .system(size: 12, weight: .regular))
        #expect(Typography.caption == .system(size: 10.5, weight: .regular))
        #expect(Typography.code == .system(size: 11.5, weight: .regular, design: .monospaced))
        #expect(Typography.mono == .system(size: 10, weight: .regular, design: .monospaced))
        #expect(Typography.monoCaption == .system(size: 9.5, weight: .regular, design: .monospaced))
        #expect(Typography.section == .system(size: 10, weight: .semibold))
    }

    /// A weighted role is the *same* size as its plain form — that is what makes it a weight
    /// and not a new size sneaking in through a second spelling.
    @Test func aWeightedRoleKeepsItsRolesSize() {
        #expect(Typography.body(.regular) == Typography.body)
        #expect(Typography.caption(.regular) == Typography.caption)
        #expect(Typography.code(.regular) == Typography.code)
        #expect(Typography.mono(.regular) == Typography.mono)
        #expect(Typography.monoCaption(.regular) == Typography.monoCaption)
    }

    /// `Typo` is the face plumbing, not a scale: calling it from a screen is how the 0.5 pt
    /// ramp got built the first time, one reasonable-looking 11.5 at a time. Same shape as
    /// the `Color(hex:` check above, for the same reason — a reviewer's eye missed it before.
    @Test func onlyTheDesignSystemReachesPastARole() throws {
        let strays = try DesignTokenTests.swiftFiles()
            .filter { $0.deletingLastPathComponent().lastPathComponent != "DesignSystem" }
            .filter { try String(contentsOf: $0, encoding: .utf8).contains("Typo.") }
            .map(\.lastPathComponent)
            .sorted()
        #expect(strays.isEmpty, "pick a Typography role instead of a raw size here: \(strays)")
    }
}
