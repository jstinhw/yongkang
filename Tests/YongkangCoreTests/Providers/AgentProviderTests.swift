import Foundation
import Testing

@testable import YongkangCore

@Suite struct AgentProviderTests {
    // A kind is what persists and a provider is what runs it; the two must never disagree.
    @Test(arguments: AgentKind.allCases)
    func everyKindHasItsOwnProvider(kind: AgentKind) {
        #expect(kind.provider.kind == kind)
    }

    /// Each CLI's question as a person reads it, and a mention of it in ordinary output.
    static let screens: [(screen: String, asker: AgentKind?)] = [
        ("Do you trust the contents of this directory?\n› 1. Yes, continue\n  2. No, quit", .codex),
        ("Do you trust the files in this folder?\n❯ 1. Yes, I trust this folder\n  2. No, exit", .claude),
        ("Documentation: Do you trust the contents of this directory?", nil),
    ]

    @Test(arguments: AgentKind.allCases)
    func onlyTheAskingCLIClaimsItsQuestion(kind: AgentKind) {
        for (screen, asker) in Self.screens {
            #expect((kind.provider.attentionReason(screen: screen) != nil) == (kind == asker), "\(screen)")
        }
    }
}
