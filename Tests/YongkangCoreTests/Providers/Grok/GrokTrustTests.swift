import Testing

@testable import YongkangCore

/// Grok 1.0.30 says itself whether it would ask, as `projectTrusted` in `grok inspect --json`.
@Suite struct GrokTrustTests {
    @Test func readsProjectTrustedWhateverTheLoginShellPrintedFirst() {
        #expect(GrokProvider.projectTrusted(in: #"{"cwd":"/a","projectTrusted":true}"#) == true)
        #expect(GrokProvider.projectTrusted(in: "Welcome back!\n{\n  \"projectTrusted\": false\n}") == false)
        #expect(GrokProvider.projectTrusted(in: "zsh: command not found: grok") == nil)
    }
}
