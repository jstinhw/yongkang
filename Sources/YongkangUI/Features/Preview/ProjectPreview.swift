import SwiftUI
import WebKit
import YongkangCore

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

    /// Answered by the detection that found the services, not by another look at the disk.
    private var hasFrontend: Bool { services.contains(where: \.frontend) }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Button {
                    run()
                } label: {
                    Label("Run all services", systemImage: "play.fill")
                }
                .buttonStyle(.console)
                Spacer()
                if hasFrontend {
                    TextField("http://localhost:3000", text: $address, onCommit: load)
                        .textFieldStyle(.plain)
                        .font(Typo.mono(11))
                        .padding(.horizontal, 10)
                        .frame(width: 260, height: 30)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .strokeBorder(Theme.line2, lineWidth: 1))
                    Button("Go", action: load).buttonStyle(.console)
                    Button {
                        webView.reload()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise").labelStyle(.iconOnly)
                    }
                    .buttonStyle(.console)
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
                    .font(Typo.text(13))
                    .foregroundStyle(Theme.tx3)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(Theme.bg)
    }

    /// Every service under this repo, run independently — the point of a monorepo split.
    private var serviceList: some View {
        HStack(spacing: 16) {
            ForEach(services, id: \.name) { service in
                HStack(spacing: 4) {
                    Text(service.name).font(Typo.text(11.5, .medium)).foregroundStyle(Theme.tx2)
                    Text(service.command ?? "nothing to run")
                        .font(Typo.mono(10.5))
                        .foregroundStyle(service.command == nil ? Theme.amber : Theme.tx3)
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
/// Shared with the design demo, which shows two of these side by side.
struct WebPane: NSViewRepresentable {
    let webView: WKWebView
    func makeNSView(context: Context) -> WKWebView { webView }
    func updateNSView(_ view: WKWebView, context: Context) {}
}
