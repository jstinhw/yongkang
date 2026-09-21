import Foundation
import YongkangCore

/// Usage analytics: PostHog's capture API, one small JSON POST per event. The events are the
/// app's own actions — launched, opened a project, started a session on an agent, approved a
/// task — with an agent's kind or a count at most.
///
/// **Never a path, a project's or task's name, a prompt, a file's contents or anything typed.**
/// The same rule `Log` keeps, for the same reason: what the agents work on is the user's, and an
/// event only needs to say that something happened.
///
/// Off in anything but a Release build (`Online.isRelease`), and off whenever the user unticks
/// Share Usage Analytics in the app menu.
///
/// ponytail: one request per event and no offline queue: a few events a minute, and one lost
/// offline costs a count. Batch them when the volume or that loss starts to matter.
@MainActor enum Analytics {
    /// The app menu's switch. On until the user turns it off; off sends nothing at all.
    nonisolated static let enabledKey = "shareAnalytics"
    private static let idKey = "analyticsID"

    private static let endpoint: (url: URL, key: String)? = {
        guard Online.isRelease, let host = Online.url("YKPostHogHost"), let key = Online.value("YKPostHogKey")
        else { return nil }
        return (host.appending(path: "i/v0/e/"), key)
    }()

    private static var enabled: Bool { UserDefaults.standard.object(forKey: enabledKey) as? Bool ?? true }

    /// Whose events these are: the signed-in user's id after `identify`, before that a random id
    /// made on this Mac. Never the Mac's name, its serial or anything else that could trace it.
    private static var distinctID: String {
        if let id = UserDefaults.standard.string(forKey: idKey) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: idKey)
        return id
    }

    static func capture(_ event: String, _ properties: [String: Any] = [:]) {
        guard let endpoint, enabled else { return }
        do {
            send(
                try payload(event, distinctID: distinctID, properties: properties, key: endpoint.key), to: endpoint.url)
        } catch {
            Log.online.error(
                "analytics: \(event, privacy: .public) not encoded: \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Hands this Mac's events so far to the user who just signed in, so PostHog counts one
    /// person rather than an install and an account.
    static func identify(_ user: Account.User) {
        let anonymous = distinctID
        UserDefaults.standard.set(user.id, forKey: idKey)
        capture("$identify", ["$anon_distinct_id": anonymous, "$set": user.traits])
    }

    /// After sign-out: a new random id, so whoever uses this Mac next isn't counted as the last.
    static func reset() {
        UserDefaults.standard.removeObject(forKey: idKey)
    }

    /// The body PostHog's capture endpoint takes. Every event carries the app's version and the
    /// macOS version, which is what a question like "who is still on 0.3" needs.
    static func payload(
        _ event: String, distinctID: String, properties: [String: Any], key: String,
        bundle: Bundle = .main, now: Date = .now
    ) throws -> Data {
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let common: [String: Any] = [
            "$lib": "yongkang",
            "$os": "macOS",
            "$os_version": "\(os.majorVersion).\(os.minorVersion).\(os.patchVersion)",
            "$app_version": bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "",
            "$app_build": bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "",
        ]
        return try JSONSerialization.data(withJSONObject: [
            "api_key": key,
            "event": event,
            "distinct_id": distinctID,
            "properties": common.merging(properties) { _, own in own },
            "timestamp": ISO8601DateFormatter().string(from: now),
        ])
    }

    private static func send(_ body: Data, to url: URL) {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
        Task.detached {
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                // A wrong project key or a moved host: every event is being thrown away.
                if status != 200 { Log.online.error("analytics: HTTP \(status, privacy: .public)") }
            } catch {
                // Offline is the normal case for a laptop, not a fault.
                Log.online.debug("analytics: \(error.localizedDescription, privacy: .public)")
            }
        }
    }
}
