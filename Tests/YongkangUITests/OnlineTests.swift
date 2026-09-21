import Foundation
import Testing

@testable import YongkangUI

/// The parts of `Online/` that don't need a server: PKCE, reading Supabase's answers, and the
/// body PostHog is sent. The network round trips are checked by the smoke script instead.
@MainActor struct OnlineTests {
    @Test func challengeMatchesRFC7636() {
        // Appendix B of RFC 7636: a server compares exactly this.
        #expect(
            Account.challenge(for: "dBjftJeZ4CVP-mB92K27uhbUJU1p1r_wW1gFWFOEjXk")
                == "E9Melhoa2OwvFrEMTJguCHaoeK1t8URWbuGJSstw-cM")
    }

    @Test func verifierIsURLSafeAndFresh() {
        let verifier = Account.verifier()
        // 32 bytes is 43 base64url characters, inside the RFC's 43...128.
        #expect(verifier.count == 43)
        #expect(verifier.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" })
        #expect(verifier != Account.verifier(), "a verifier that repeats is one an attacker can guess")
    }

    @Test func authorizeURLSendsTheChallengeToGitHub() throws {
        let url = Account.authorizeURL(URL(string: "https://abc.supabase.co")!, challenge: "C")
        let items = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
        #expect(url.path() == "/auth/v1/authorize")
        #expect(query["provider"] == "github")
        #expect(query["redirect_to"] == "yongkang://auth-callback")
        #expect(query["code_challenge"] == "C")
        #expect(query["code_challenge_method"] == "s256")
    }

    @Test func callbackGivesTheCodeOrTheReason() throws {
        #expect(try Account.code(from: URL(string: "yongkang://auth-callback?code=abc")!) == "abc")
        #expect(throws: SignInError.refused("Email not verified")) {
            try Account.code(
                from: URL(
                    string: "yongkang://auth-callback?error=access_denied&error_description=Email%20not%20verified")!)
        }
        #expect(throws: SignInError.refused("No sign-in code came back.")) {
            try Account.code(from: URL(string: "yongkang://auth-callback?code=")!)
        }
    }

    @Test func tokenResponseKeepsTheUserAndDropsTheTokens() throws {
        let data = Data(
            """
            {"access_token":"secret","refresh_token":"secret","expires_in":3600,
             "user":{"id":"u1","email":"a@example.com","user_metadata":{"user_name":"octo","full_name":"Octo Cat"}}}
            """.utf8)
        let user = try Account.user(from: data)
        #expect(user == Account.User(id: "u1", email: "a@example.com", login: "octo"))
        #expect(!String(decoding: try JSONEncoder().encode(user), as: UTF8.self).contains("secret"))
    }

    @Test func payloadIsWhatPostHogCaptures() throws {
        let body = try Analytics.payload(
            "session_started", distinctID: "d1", properties: ["agent": "codex", "tasks": 2], key: "phc_x",
            now: Date(timeIntervalSince1970: 0))
        let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        let properties = try #require(json["properties"] as? [String: Any])
        #expect(json["api_key"] as? String == "phc_x")
        #expect(json["event"] as? String == "session_started")
        #expect(json["distinct_id"] as? String == "d1")
        #expect(json["timestamp"] as? String == "1970-01-01T00:00:00Z")
        #expect(properties["agent"] as? String == "codex")
        #expect(properties["tasks"] as? Int == 2)
        #expect(properties["$os"] as? String == "macOS")
        #expect(properties["$app_version"] != nil, "every event says which version sent it")
    }

    @Test func nothingGoesOnlineOutsideTheReleaseApp() {
        // The test runner's bundle has no YKConfiguration, like `shots` and a Debug build.
        #expect(!Online.isRelease)
        #expect(!Updates.shared.available)
        #expect(!Account().available)
    }
}
