import Foundation

/// What the app's online parts read from the bundle. This folder is the only code that talks to
/// a server: Sparkle's update check, GitHub sign-in through Supabase, and PostHog analytics.
/// Everything else stays on the Mac (`docs/architecture.md`, "What goes online").
///
/// The values live in `App/Config/Info.plist`, not in code. None of them is a secret: an appcast
/// URL, an EdDSA *public* key, Supabase's publishable key and PostHog's project key are all
/// written to be shipped inside an app. `docs/release.md` says where each one comes from.
enum Online {
    /// True only in the app's Release build. Info.plist carries `$(CONFIGURATION)`, and under
    /// `swift test` and `shots` the main bundle is the runner's, with no such key. So the tests,
    /// the shots and `make run` never check for updates or send an event.
    static let isRelease = value("YKConfiguration") == "Release"

    /// A string from Info.plist, or nil when it is missing or empty: an empty value is a service
    /// nobody has set up yet, and that should switch the feature off rather than break it.
    static func value(_ key: String) -> String? {
        guard let value = Bundle.main.object(forInfoDictionaryKey: key) as? String, !value.isEmpty else { return nil }
        return value
    }

    /// An https URL from Info.plist. Anything else is refused, so a typo can't send a key over
    /// plain HTTP.
    static func url(_ key: String) -> URL? {
        guard let url = value(key).flatMap(URL.init(string:)), url.scheme == "https", url.host() != nil else {
            return nil
        }
        return url
    }
}
