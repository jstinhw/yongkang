import SwiftUI
import WebKit

/// One repo, run locally. A repo is not always one app — a monorepo's `apps/` or
/// `services/` folder, or a compose file's own service names, can name several — so every
/// service under it gets listed, and whichever looks like a frontend app is shown live so
/// you can click around and test it without leaving the window.
struct ProjectPreview: View {
    let repo: String
    let services: [Service.Runnable]
    let run: () -> Void

    // ponytail: no port detection. Frameworks default all over the map (3000, 5173, 8080);
    // guessing wrong looks like a bug. An editable address bar defaulting to the commonest
    // one is simpler and always correctable.
    @State private var address = "http://localhost:3000"
    @State private var webView = WKWebView()

    private var hasFrontend: Bool {
        services.contains { Service.isFrontend($0.directory) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button("Run All Services", systemImage: "play.fill") { run() }
                Spacer()
                if hasFrontend {
                    TextField("http://localhost:3000", text: $address, onCommit: load)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 260)
                    Button("Go", action: load)
                    Button("Reload", systemImage: "arrow.clockwise") { webView.reload() }
                        .labelStyle(.iconOnly)
                }
            }
            .padding(10)
            Divider()
            serviceList
            Divider()
            if hasFrontend {
                WebPane(webView: webView).onAppear(perform: load)
            } else {
                Text("No frontend app among \(repo)'s services — nothing to open here.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    /// Every service under this repo, run independently — the point of a monorepo split.
    private var serviceList: some View {
        HStack(spacing: 16) {
            ForEach(services, id: \.name) { service in
                HStack(spacing: 4) {
                    Text(service.name).font(.caption.weight(.medium))
                    Text(service.command ?? "nothing to run")
                        .font(.caption2)
                        .foregroundStyle(service.command == nil ? Color.orange : .secondary)
                }
            }
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
    }

    private func load() {
        guard let url = URL(string: address) else { return }
        webView.load(URLRequest(url: url))
    }
}

/// The WKWebView lives in the parent's @State so Go/Reload can drive it directly — no
/// delegate or Coordinator needed for that.
private struct WebPane: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
