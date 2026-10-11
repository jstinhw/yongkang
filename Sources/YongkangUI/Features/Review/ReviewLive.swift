import AppKit
import SwiftUI
import WebKit
import YongkangCore

/// A screen's change as the app itself, running twice — the commit the agent started from, and
/// its work — rather than pictures of it, which shrink a whole window into something nobody can
/// read. Full width by default, one side at a time, with what changed outlined: red on the
/// before where it went away, green on the after where it is new.
struct ReviewLive: View {
    let show: WorkReview.Show
    /// The task, which names the terminal a side is served in.
    let task: String
    /// Serves a side that is down with its command, asking first: true once it answers.
    let serve: (_ url: URL, _ command: String, _ title: String) async -> Bool

    /// After first: it is what approving gives you. Both halves the width, which a page laid
    /// out for a window reads as a narrow one, so it is a choice and not the default.
    @State private var pane = Pane.after

    private enum Pane: String, CaseIterable, Identifiable {
        case before = "Before"
        case after = "After"
        case both = "Both"
        var id: Self { self }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(
                    (show.highlight ?? []).isEmpty
                        ? "Scroll it like a browser."
                        : "Scroll it like a browser. What changed is outlined: red on the before, green on the after."
                )
                .font(Typography.body).foregroundStyle(Theme.tx3).lineLimit(1)
                Spacer(minLength: 8)
                Picker("", selection: $pane) {
                    ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 210)
            }
            HStack(spacing: 10) {
                if pane != .after { side(before: true) }
                if pane != .before { side(before: false) }
            }
            .frame(height: 640)
        }
    }

    private func side(before: Bool) -> some View {
        let given = before ? show.before : show.after
        return LiveSide(
            label: before ? "Before" : "After",
            tint: before ? Theme.problem : Theme.insertion,
            given: given,
            url: WorkReview.Show.page(given),
            command: (before ? show.serveBefore : show.serveAfter) ?? "",
            script: Self.outline(show.highlight ?? [], in: before ? Theme.red : Theme.green),
            title: "Serve \(task) \(before ? "before" : "after")",
            serve: serve)
    }

    /// Outlines whatever the selectors match, and brings the first match into view once the
    /// page has loaded. A selector the page cannot parse is dropped rather than voiding the
    /// rest, and the list goes in as JSON, so no selector can end the string it sits in. Drawn
    /// just inside the element, so a full-width section shows all four edges.
    static func outline(_ selectors: [String], in color: Color) -> String {
        guard !selectors.isEmpty, let data = try? JSONEncoder().encode(selectors),
            let list = String(data: data, encoding: .utf8)
        else { return "" }
        let rgb = NSColor(color).usingColorSpace(.sRGB) ?? .white
        let css =
            "rgb(\(Int(rgb.redComponent * 255)), \(Int(rgb.greenComponent * 255)), \(Int(rgb.blueComponent * 255)))"
        return """
            (() => {
              const valid = \(list).filter(s => { try { document.querySelector(s); return true } catch { return false } });
              if (!valid.length) return;
              const style = document.createElement('style');
              style.textContent = valid.join(',') + '{outline:3px solid \(css) !important;outline-offset:-3px !important}';
              (document.head || document.documentElement).appendChild(style);
              const first = () => valid.map(s => document.querySelector(s)).find(Boolean);
              addEventListener('load', () => setTimeout(() => first()?.scrollIntoView({block: 'center'}), 300));
            })();
            """
    }
}

/// One side: the page live, or why it is not, with the way to bring it back.
private struct LiveSide: View {
    let label: String
    let tint: Color
    /// What the agent wrote for this side, said back when it is not an address.
    let given: String?
    let url: URL?
    let command: String
    let script: String
    let title: String
    let serve: (URL, String, String) async -> Bool

    /// Whether the page answers; nil until asked.
    @State private var up: Bool?
    @State private var starting = false

    var body: some View {
        VStack(spacing: 0) {
            header
            content.frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.bg)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line2, lineWidth: 1))
        .task(id: url) {
            guard let url else { return }
            up = await DemoServer.answers(url)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Text(label.uppercased()).font(Typography.section).tracking(1.2).foregroundStyle(tint)
            Text(url?.absoluteString ?? "—").font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
                .textSelection(.enabled)
            Spacer(minLength: 0)
            if let url, up == true {
                Button {
                    DemoPages.reload(url)
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 11))
                }
                .buttonStyle(.plain).foregroundStyle(Theme.tx3)
                .help("Load this page again")
                .accessibilityLabel("Reload \(label)")
                Button("Open in browser") { NSWorkspace.shared.open(url) }
                    .buttonStyle(.plain).font(Typography.body).foregroundStyle(Theme.tx2)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 32)
        .background(Theme.panel)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
    }

    @ViewBuilder private var content: some View {
        if given == nil {
            say(label == "Before" ? "Nothing before: it is new." : "Gone.")
        } else if url == nil {
            say("Not a web address: \(given ?? "")")
        } else if let url, up == true {
            WebPane(webView: DemoPages.view(for: url, running: script))
        } else if let url, up == false {
            down(url)
        } else {
            Color.clear
        }
    }

    private func down(_ url: URL) -> some View {
        VStack(spacing: 10) {
            Text(starting ? "Starting…" : "Not running.").font(Typography.body(.semibold)).foregroundStyle(Theme.tx2)
            if command.isEmpty || !DemoServer.isLocal(url) {
                Text("The agent left no command here to serve it again.")
                    .font(Typography.body).foregroundStyle(Theme.tx3)
            } else {
                Text(command).font(Typography.code).foregroundStyle(Theme.prose)
                    .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                    .frame(maxWidth: 520)
                Button("Run it") { start(url) }.buttonStyle(.console).disabled(starting)
            }
        }
        .padding(24)
    }

    /// Asked first by the app when this project has not run this command before, and the
    /// question's own Run starts it; either way the page is watched for until it answers.
    private func start(_ url: URL) {
        starting = true
        Task {
            let answered = await serve(url, command, title)
            up = answered ? true : await DemoServer.waitUntilAnswering(url)
            starting = false
        }
    }

    private func say(_ text: String) -> some View {
        Text(text).font(Typography.body).foregroundStyle(Theme.tx3).padding(24)
    }
}
