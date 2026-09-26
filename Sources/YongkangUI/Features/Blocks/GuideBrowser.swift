import SwiftUI
import WebKit
import YongkangCore

/// The page the step in hand needs, inside the window, beside the engineer asking for it.
///
/// The agent does not open it: it sets `url:` in the block file as each step comes up, and
/// this pane follows that field. Shelling out to `open` put the page in a browser behind the
/// app, which is a page the user has to go and find — and on a token screen that arrived with
/// no explanation. Here the instruction and the page are the same glance.
///
/// ponytail: one address, no history of its own. Back is the web view's; if a step ever needs
/// a tab of its own, this is where that would go.
struct GuideBrowser: View {
    let url: URL

    @State private var web = WKWebView()
    /// What the pane last loaded, so a reload of the project does not reload the page under
    /// someone who is halfway through signing in.
    @State private var loaded: URL?

    var body: some View {
        VStack(spacing: 0) {
            bar
            Divider().overlay(Theme.line)
            WebPane(webView: web)
        }
        .background(Theme.panel)
        .task(id: url) { load() }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            button("chevron.left", "Back") { web.goBack() }
            button("arrow.clockwise", "Reload") { web.reload() }
            Text(url.host().map { $0 + url.path() } ?? url.absoluteString)
                .font(Typography.mono).foregroundStyle(Theme.tx2).lineLimit(1)
                .truncationMode(.middle)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 7).fill(Theme.well))
                .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.wellLine, lineWidth: 1))
            button("arrow.up.forward.square", "Open in your browser") { NSWorkspace.shared.open(url) }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
    }

    private func button(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 11)).foregroundStyle(Theme.tx2)
                .frame(width: 24, height: 24)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private func load() {
        guard loaded != url else { return }
        loaded = url
        web.load(URLRequest(url: url))
    }
}
