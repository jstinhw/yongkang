import Foundation
import YongkangCore

/// Claude's plan limits, asked of the same endpoint Claude Code's own `/usage` asks. Newer
/// Claude Code versions stopped caching the answer in `~/.claude.json`, so there is nothing on
/// disk to read any more.
///
/// The request is signed with Claude Code's own login, which it keeps in the login keychain
/// and reads through `/usr/bin/security` — so reading it the same way raises no prompt. The
/// token is used for this one request and never stored, logged or sent anywhere else.
actor ClaudeLimits {
    static let shared = ClaudeLimits()

    private static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!
    /// The usage screen reloads on every transcript write, which is several times a second
    /// while agents work. The server's numbers move far slower than that.
    /// ponytail: one answer per minute, failures included, so a signed-out machine is not
    /// asked again on every write.
    private static let freshFor: TimeInterval = 60

    private var last: (at: Date, body: Data?)?

    /// The endpoint's JSON body, or nil when Claude Code isn't signed in or the request failed.
    func usage(now: Date = Date()) async -> Data? {
        if let last, now.timeIntervalSince(last.at) < Self.freshFor { return last.body }
        let body = await fetch()
        last = (now, body)
        return body
    }

    private func fetch() async -> Data? {
        guard let token = await token() else { return nil }
        var request = URLRequest(url: Self.endpoint, timeoutInterval: 10)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            guard status == 200 else {
                Log.online.error("Claude usage: HTTP \(status)")
                return nil
            }
            return data
        } catch {
            Log.online.error("Claude usage: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    /// Claude Code's access token. An expired one is still returned: the server's 401 says so,
    /// and Claude Code refreshes it the next time it runs.
    private func token() async -> String? {
        guard
            let output = try? await AsyncProcess.run(
                URL(fileURLWithPath: "/usr/bin/security"),
                ["find-generic-password", "-s", "Claude Code-credentials", "-w"]),
            output.status == 0,
            let root = try? JSONSerialization.jsonObject(with: output.stdout) as? [String: Any],
            let oauth = root["claudeAiOauth"] as? [String: Any]
        else { return nil }
        return oauth["accessToken"] as? String
    }
}
