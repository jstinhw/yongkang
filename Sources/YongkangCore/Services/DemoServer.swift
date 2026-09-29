import Foundation

/// Whether a demo's page is up, for bringing back one that a quit took down.
package enum DemoServer {
    /// Only a page on this Mac is ours to start. One published elsewhere that does not answer
    /// is down for reasons no command here can fix.
    package static func isLocal(_ url: URL) -> Bool {
        ["localhost", "127.0.0.1", "::1", "0.0.0.0"].contains(url.host?.lowercased() ?? "")
    }

    /// Any answer counts, a 404 included: that is a server up with a route missing, and
    /// starting a second one would only fight it for the port.
    package static func answers(_ url: URL) async -> Bool {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 2)
        request.httpMethod = "HEAD"
        return (try? await URLSession.shared.data(for: request)) != nil
    }

    /// Polls until the page answers. A dev server takes seconds to boot, and a pane loaded
    /// before it is listening shows an error page it never recovers from.
    /// ponytail: a fixed one-second poll; a server slower than `seconds` to boot shows its
    /// error page, and the pane's reload button is the way out.
    package static func waitUntilAnswering(_ url: URL, seconds: Int = 60) async -> Bool {
        for _ in 0..<seconds {
            if await answers(url) { return true }
            try? await Task.sleep(for: .seconds(1))
        }
        return false
    }
}
