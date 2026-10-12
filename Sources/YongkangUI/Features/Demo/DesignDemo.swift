import AppKit
import SwiftUI
import WebKit
import YongkangCore

/// The design a task cannot be built without, next to the thing it would replace.
///
/// A demo is a `kind: demo` file in `.notebook/blocks/`: the designer builds the screen on
/// a throwaway branch, serves it, and writes down what changed. Approving it is what
/// finishes the design task and releases the engineering tasks waiting on it, so this
/// screen is the gate — not a preview of work already done, which is what a diff in
/// Review is.
///
/// Both panes are live pages rather than pictures, because a picture of a layout answers
/// none of the questions the layout is actually for.
package struct DesignDemo: View {
    let block: UserBlock
    let cards: [NotebookCard]
    /// The session waiting on this demo, if it is still running.
    let waiting: CodeSession?
    /// Approves the current revision: clears the demo and tells the waiting agent to build.
    let approve: (DemoRevision?) -> Void
    /// What is wrong with it, in the user's words, kept while they look at the panes.
    @Binding var note: String
    /// Sends `note` to whoever has the demo, as the brief for the next pass.
    let revise: () -> Void
    /// Starts the demo's page if it is down, true once it answers. Nil in the shots.
    let serve: (() async -> Bool)?

    @State private var pane = Pane.both
    /// Which revision is in the After pane. Nil is the demo's own `url` — the newest one.
    @State private var revision: Int?

    package init(
        block: UserBlock,
        cards: [NotebookCard],
        waiting: CodeSession?,
        approve: @escaping (DemoRevision?) -> Void,
        note: Binding<String> = .constant(""),
        revise: @escaping () -> Void,
        serve: (() async -> Bool)? = nil
    ) {
        self.block = block
        self.cards = cards
        self.waiting = waiting
        self.approve = approve
        self._note = note
        self.revise = revise
        self.serve = serve
    }

    enum Pane: String, CaseIterable, Identifiable {
        case before = "Before"
        case both = "Both"
        case after = "After"
        var id: Self { self }
    }

    private var task: NotebookCard? {
        block.task.flatMap { id in cards.first { $0.id == id } }
    }

    private var shown: DemoRevision? {
        revision.flatMap { index in block.revisions.first { $0.id == index } }
    }

    /// The pass being shown, else the newest one that kept a URL, else whatever the demo
    /// itself points at. Never `block.url` — that is the block's own file on disk.
    private var after: URL? {
        shown?.url ?? block.revisions.last?.url ?? block.link
    }

    package var body: some View {
        GeometryReader { geometry in
            // Two live pages side by side need the room before anything else does, so a
            // narrow window gives them the inspector's column.
            let narrow = geometry.size.width < 950
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    VStack(spacing: 0) {
                        controls(narrow: narrow)
                        revisions
                        panes
                        if narrow { folded }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !narrow { inspector }
                }
                actionBar
            }
        }
        .background(Theme.bg)
        // A designer's next pass often republishes to the same link, so a new revision line
        // is the cue to fetch both panes again rather than keep showing the last pass.
        .onChange(of: block.revisions.count) { reloadPanes() }
        // A page a quit took down comes back on its own; the panes load it once it answers.
        .task(id: block.id) { if await serve?() == true { reloadPanes() } }
    }

    private func reloadPanes() {
        [block.before, after].compactMap { $0 }.forEach(DemoPages.reload)
    }

    // MARK: - Controls

    /// The switch keeps its size at every width; the line explaining it is the first
    /// thing to go, because the three words on the control already say it.
    private func controls(narrow: Bool) -> some View {
        HStack(spacing: 12) {
            Picker("", selection: $pane) {
                ForEach(Pane.allCases) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented).labelsHidden().frame(width: 210).layoutPriority(1)
            if !narrow {
                Text(hint).font(Typography.body).foregroundStyle(Theme.tx3).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !block.branch.isEmpty {
                Text(block.branch).font(Typography.mono).foregroundStyle(Theme.tx3)
                    .lineLimit(1).truncationMode(.head)
            }
        }
        .padding(.horizontal, 24)
        .padding(.top, 14)
    }

    /// What the inspector carries, under the panes instead of beside them.
    private var folded: some View {
        DisclosureGroup("What changes, and what it holds up") {
            VStack(alignment: .leading, spacing: 14) { inspectorContent }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 12)
        }
        .font(Typography.body).tint(Theme.tx2)
        .cardSurface()
        .padding(.horizontal, 24)
        .padding(.bottom, 14)
    }

    private var hint: String {
        switch pane {
        case .before: return "The page as it stands."
        case .both: return "The page you have, and the page this task would give you."
        case .after: return "What the task would give you."
        }
    }

    /// Every pass the designer made, so the change can be followed rather than arriving as
    /// one finished thing. A pass that kept a URL opens again; one that did not still says
    /// what it changed.
    @ViewBuilder private var revisions: some View {
        if !block.revisions.isEmpty {
            HStack(spacing: 10) {
                SectionLabel("Revisions")
                ForEach(block.revisions) { pass in chip(pass) }
                if let note = shown?.note ?? block.revisions.last?.note, !note.isEmpty {
                    Text(note).font(Typography.body).foregroundStyle(Theme.tx2).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 24)
            .padding(.top, 14)
        }
    }

    private func chip(_ pass: DemoRevision) -> some View {
        let isLast = pass.id == block.revisions.count - 1
        let on = revision == pass.id || (revision == nil && isLast)
        return Button {
            revision = pass.id
        } label: {
            HStack(spacing: 6) {
                Circle().fill(on ? Theme.violet : Theme.tx4).frame(width: 5, height: 5)
                Text(pass.label).font(Typography.mono)
                    .foregroundStyle(on ? Theme.tx : Theme.tx3)
            }
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
                RoundedRectangle(cornerRadius: 7)
                    .fill(on ? Theme.violet.opacity(0.14) : .clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 7)
                    .strokeBorder(on ? Theme.violet.opacity(0.4) : Theme.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help(
            pass.url == nil
                ? "\(pass.note) — this pass was not kept running"
                : pass.note
        )
        .disabled(pass.url == nil && pass.id != block.revisions.count - 1)
    }

    // MARK: - Panes

    private var panes: some View {
        HStack(spacing: 20) {
            if pane != .after {
                pageFrame("Before", tint: Theme.tx3, url: block.before) {
                    // A task that adds a surface has no before, and saying so is more use
                    // than an empty frame pretending to be one.
                    empty("Nothing here yet — this task adds a surface that does not exist.")
                }
            }
            if pane != .before {
                pageFrame("After", tint: Theme.violet, url: after) {
                    empty("This pass was not kept running. Its note is the record.")
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func pageFrame<Fallback: View>(
        _ label: String, tint: Color, url: URL?,
        @ViewBuilder fallback: () -> Fallback
    ) -> some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text(label.uppercased()).font(Typography.section).tracking(1.4).foregroundStyle(tint)
                Text(url?.absoluteString ?? "—")
                    .font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
                Spacer(minLength: 0)
                if let url {
                    Button {
                        DemoPages.reload(url)
                    } label: {
                        Image(systemName: "arrow.clockwise").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tx3)
                    .help("Load the latest version of this page")
                    .accessibilityLabel("Reload \(label)")
                    // The browser already has the user's sign-ins, which a claude.ai artifact —
                    // private to the account that published it — needs before it shows.
                    Button {
                        NSWorkspace.shared.open(url)
                    } label: {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 11))
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.tx3)
                    .help("Open this page in your browser")
                    .accessibilityLabel("Open \(label) in your browser")
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
            if let url {
                // Opening the demo shows the design as it is now, not as it was the first
                // time this link was loaded in this run of the app.
                WebPane(webView: DemoPages.view(for: url))
                    .onAppear { DemoPages.reload(url) }
            } else {
                fallback()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.line2, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func empty(_ text: String) -> some View {
        Text(text)
            .font(Typography.body).foregroundStyle(Theme.tx3)
            .multilineTextAlignment(.center)
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg)
    }

    // MARK: - Inspector

    private var inspector: some View {
        Inspector { inspectorContent }
    }

    @ViewBuilder private var inspectorContent: some View {
        if let task {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel("Holds up")
                HStack(spacing: 10) {
                    NotebookStyle.statusRing(task.status, progress: 0, size: 16)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(task.title).font(Typography.body).foregroundStyle(Theme.tx)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(task.id).font(Typography.mono).foregroundStyle(Theme.tx3)
                    }
                    Spacer(minLength: 0)
                    if !task.designer.isEmpty { RoleTile(role: "design", size: 22) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface(padding: 15)
        }

        if let task {
            let items = NotebookIndex.checklist(at: task.url)
            if !items.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Done when", trailing: "\(items.filter(\.done).count)/\(items.count)")
                    ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                        HStack(alignment: .top, spacing: 9) {
                            Image(systemName: item.done ? "checkmark.square.fill" : "square")
                                .font(.system(size: 11))
                                .foregroundStyle(item.done ? Theme.green : Theme.tx4)
                                .padding(.top, 1)
                            Text(item.text).font(Typography.body)
                                .foregroundStyle(item.done ? Theme.tx2 : Theme.tx3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Cost of the demo")
            Text(cost).font(Typography.body).foregroundStyle(Theme.tx2)
                .fixedSize(horizontal: false, vertical: true)
        }
        Spacer(minLength: 0)
    }

    private var cost: String {
        let who = task?.designer.isEmpty == false ? task!.designer : "The designer"
        let branch = block.branch.isEmpty ? "a throwaway branch" : block.branch
        return "\(who) built this on \(branch). Nothing is merged and no task status has "
            + "moved; saying no throws the branch away."
    }

    // MARK: - Approve

    /// Written something? Then sending it is the primary action, because building would
    /// throw it away — the same pair of answers, in the same order, as a task's review.
    private var said: Bool { !note.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    private var actionBar: some View {
        ActionBar {
            Image(systemName: "hand.raised.fill").font(.system(size: 12))
                .foregroundStyle(Theme.amber)
            if block.waiting {
                TextField("What should change? Sent to the agent as the next pass's brief", text: $note)
                    .textFieldStyle(.plain)
                    .font(Typography.body)
                    .foregroundStyle(Theme.tx)
                    .padding(.horizontal, 10)
                    .frame(height: 30)
                    .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
                    .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.line2, lineWidth: 1))
                    .onSubmit { if said { revise() } }
            } else {
                Text("Approved. \(waiting.map { "\($0.title) has it." } ?? "The agent has it.")")
                    .font(Typography.body).foregroundStyle(Theme.green)
                Spacer(minLength: 12)
            }
            if said {
                buildButton.buttonStyle(.console)
                    .help("Builds this revision and discards what you wrote")
                reviseButton.buttonStyle(.consolePrimary)
            } else {
                reviseButton.buttonStyle(.console)
                    .disabled(true)
                    .help("Say what should change first")
                buildButton.buttonStyle(.consolePrimary)
            }
        }
    }

    private var reviseButton: some View {
        Button {
            revise()
        } label: {
            Label("Request changes", systemImage: "arrow.uturn.left")
        }
        .disabled(!block.waiting)
    }

    private var buildButton: some View {
        Button {
            approve(shown ?? block.revisions.last)
        } label: {
            Label("Build it", systemImage: "checkmark.seal")
        }
        .disabled(!block.waiting)
    }
}

/// One web view per address, kept for the life of the app. Rebuilding a `WKWebView` every
/// time SwiftUI re-runs `body` — which the 2-second notebook poll guarantees — reloads the
/// page under the user and loses their scroll position on every tick.
/// The cache is main-actor state because a `WKWebView` is: the views are only ever made,
/// looked up and dropped while a pane's `body` runs.
@MainActor enum DemoPages {
    /// A page and the script it runs once loaded: a reviewed screen's outlines are part of
    /// its view, so a demo and a review at the same address are two views, not one.
    private struct Key: Hashable {
        let url: URL
        let script: String
    }

    private static var views: [Key: WKWebView] = [:]
    private static var order: [Key] = []

    /// Fetches the page again, keeping the view, so a design edited in place at the same
    /// link shows its latest version. A view not made yet has nothing stale to reload; one
    /// whose first load failed, because the server was down, has no page to reload and is
    /// sent to the address again.
    static func reload(_ url: URL) {
        for (key, view) in views where key.url == url && !view.isLoading {
            if view.url == nil { view.load(URLRequest(url: url)) } else { view.reload() }
        }
    }

    static func view(for url: URL, running script: String = "") -> WKWebView {
        let key = Key(url: url, script: script)
        if let existing = views[key] { return existing }
        let view = WKWebView()
        if !script.isEmpty {
            view.configuration.userContentController.addUserScript(
                WKUserScript(source: script, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
        }
        // Otherwise a page that has not loaded — or a dev server that is not running —
        // flashes a white rectangle in the middle of a near-black window. The public
        // property covers overscroll; the KVC one is what stops the view painting its own
        // white ground before the first paint of the page.
        view.uiDelegate = PagePopups.shared
        view.underPageBackgroundColor = NSColor(Theme.bg)
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        views[key] = view
        order.append(key)
        // ponytail: a plain cap rather than an LRU. Two panes and a handful of revisions
        // is the whole working set; anything older is cheaper to reload than to keep.
        while order.count > 8, let oldest = order.first {
            views.removeValue(forKey: oldest)
            order.removeFirst()
        }
        return view
    }
}

/// claude.ai signs in with Google in a popup, and a web view with no UI delegate refuses
/// every `window.open` — which claude.ai reports as "There was an error logging you in". So
/// a page's popup opens in a small window of its own, made from the configuration WebKit
/// hands over so it can pass the sign-in back to its opener, and goes when the page closes it.
@MainActor final class PagePopups: NSObject, WKUIDelegate {
    static let shared = PagePopups()
    /// The windows open now. A web view does not keep its window alive, so this does.
    private var windows: [NSWindow] = []

    func webView(
        _ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration,
        for action: WKNavigationAction, windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // ponytail: one the user closed is let go at the next popup, not at once.
        windows.removeAll { !$0.isVisible }
        let popup = WKWebView(frame: .zero, configuration: configuration)
        popup.uiDelegate = self
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 640),
            styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        // Whose page this is, so a sign-in window says it is Google's and not the app's.
        window.title = action.request.url?.host() ?? ""
        window.contentView = popup
        window.center()
        window.makeKeyAndOrderFront(nil)
        windows.append(window)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        webView.window?.close()
    }
}
