import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import Observation
import YongkangCore

/// Signing in with GitHub, through Supabase Auth. It is optional — nothing in the app needs an
/// account — and it is there so the people using Yongkang are known: Supabase's user list is
/// everyone who signed in, and `Analytics.identify` ties their usage to them.
///
/// OAuth 2 with PKCE (RFC 7636) in the system's own web sheet, so the app holds no client secret
/// and never sees a password. Supabase sends GitHub's answer back to `yongkang://auth-callback`
/// with a one-time code, and only the verifier made for this attempt can trade it for the user.
///
/// ponytail: only the user is kept, never the tokens. Nothing calls Supabase after sign-in, so a
/// stored refresh token would be a secret on disk with no reader. Keep it in the Keychain when
/// the first authenticated request arrives.
@MainActor @Observable final class Account {
    struct User: Codable, Equatable, Sendable {
        let id: String
        let email: String?
        /// The GitHub login.
        let login: String?

        /// What the analytics person profile shows, so a usage chart can say who.
        var traits: [String: String] { ["email": email, "github": login].compactMapValues { $0 } }
    }

    /// A Supabase project: its URL and its publishable key.
    typealias Project = (url: URL, key: String)

    static let callbackScheme = "yongkang"
    private static let storeKey = "account"

    private(set) var user: User? = Account.stored()
    private(set) var signingIn = false
    /// Held while the sign-in sheet is up: the system drops a session nothing retains.
    @ObservationIgnored private var session: ASWebAuthenticationSession?
    @ObservationIgnored private let anchor = WindowAnchor()
    @ObservationIgnored private let project: Project? = {
        guard let url = Online.url("YKSupabaseURL"), let key = Online.value("YKSupabaseKey") else { return nil }
        return (url, key)
    }()

    /// False when this build has no Supabase project set; the menu item is disabled then.
    var available: Bool { project != nil }

    /// Returns quietly when the user closes the sheet: changing your mind is not an error.
    func signIn() async throws {
        guard let project, !signingIn else { return }
        signingIn = true
        defer { signingIn = false }
        let verifier = Self.verifier()
        let callback: URL
        do {
            callback = try await authorize(Self.authorizeURL(project.url, challenge: Self.challenge(for: verifier)))
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            return
        }
        let user = try await Self.exchange(try Self.code(from: callback), verifier: verifier, project: project)
        UserDefaults.standard.set(try JSONEncoder().encode(user), forKey: Self.storeKey)
        self.user = user
        Analytics.identify(user)
    }

    func signOut() {
        user = nil
        UserDefaults.standard.removeObject(forKey: Self.storeKey)
        Analytics.reset()
    }

    // MARK: - The flow

    private func authorize(_ url: URL) async throws -> URL {
        defer { session = nil }
        return try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(url: url, callbackURLScheme: Self.callbackScheme) {
                callback, error in
                if let callback {
                    continuation.resume(returning: callback)
                } else {
                    continuation.resume(throwing: error ?? SignInError.refused("The sign-in window closed."))
                }
            }
            session.presentationContextProvider = anchor
            self.session = session
            session.start()
        }
    }

    /// Supabase's authorize endpoint, sending the user on to GitHub.
    static func authorizeURL(_ project: URL, challenge: String) -> URL {
        project.appending(path: "auth/v1/authorize").appending(queryItems: [
            URLQueryItem(name: "provider", value: "github"),
            URLQueryItem(name: "redirect_to", value: "\(callbackScheme)://auth-callback"),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "s256"),
        ])
    }

    /// The one-time code from the callback, or the reason Supabase or GitHub gave for not
    /// sending one.
    static func code(from callback: URL) throws -> String {
        let items = URLComponents(url: callback, resolvingAgainstBaseURL: false)?.queryItems ?? []
        let value = { (name: String) in items.first { $0.name == name }?.value.flatMap { $0.isEmpty ? nil : $0 } }
        if let code = value("code") { return code }
        throw SignInError.refused(value("error_description") ?? value("error") ?? "No sign-in code came back.")
    }

    private static func exchange(_ code: String, verifier: String, project: Project) async throws -> User {
        let url = project.url.appending(path: "auth/v1/token")
            .appending(queryItems: [URLQueryItem(name: "grant_type", value: "pkce")])
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue(project.key, forHTTPHeaderField: "apikey")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["auth_code": code, "code_verifier": verifier])
        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            Log.online.error("sign-in: token exchange HTTP \(status, privacy: .public)")
            throw SignInError.server(status)
        }
        return try user(from: data)
    }

    /// The user out of Supabase's token response; the tokens themselves are dropped here.
    static func user(from data: Data) throws -> User {
        struct Response: Decodable {
            struct Profile: Decodable {
                struct Metadata: Decodable { let userName: String? }
                let id: String
                let email: String?
                let userMetadata: Metadata?
            }
            let user: Profile
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let profile = try decoder.decode(Response.self, from: data).user
        return User(id: profile.id, email: profile.email, login: profile.userMetadata?.userName)
    }

    // MARK: - PKCE

    /// 32 random bytes, from the system's cryptographic generator.
    static func verifier() -> String {
        base64URL(Data((0..<32).map { _ in UInt8.random(in: .min ... .max) }))
    }

    static func challenge(for verifier: String) -> String {
        base64URL(Data(SHA256.hash(data: Data(verifier.utf8))))
    }

    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    /// A blob a later version can't read is someone to sign in again, not a crash.
    private static func stored() -> User? {
        UserDefaults.standard.data(forKey: storeKey).flatMap { try? JSONDecoder().decode(User.self, from: $0) }
    }
}

/// Why sign-in stopped, as the alert says it.
enum SignInError: LocalizedError, Equatable {
    /// Supabase or GitHub declined, with their reason.
    case refused(String)
    /// The code came back but trading it failed: the Supabase project is down or misconfigured.
    case server(Int)

    var errorDescription: String? { "Sign-in didn't finish" }

    var recoverySuggestion: String? {
        switch self {
        case .refused(let reason): return reason
        case .server(let status): return "The sign-in server answered \(status). Try again in a minute."
        }
    }
}

/// The window the sign-in sheet hangs from: whichever of the app's is in front.
private final class WindowAnchor: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? ASPresentationAnchor()
    }
}
