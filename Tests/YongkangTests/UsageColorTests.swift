import Foundation
import Testing

@testable import Yongkang

/// The colours the usage screen draws spend in. Apart from `UsageTests` because these are
/// SwiftUI colours, and everything else about usage is not.
@Suite struct UsageColorTests {

    // Two versions of one model must not draw as the same colour, or a stacked bar
    // says how much went to Opus without saying which Opus.
    @Test func paletteShadesVersionsOfOneFamily() {
        let shades = AgentUsage.palette(for: ["claude-opus-5", "claude-opus-4-7", "claude-sonnet-5"])
        #expect(shades["claude-opus-5"] != shades["claude-opus-4-7"])
        #expect(
            shades["claude-opus-5"] == AgentUsage.modelTint("claude-opus-5"),
            "and the biggest spender in a family keeps the family's own colour")
    }
}
