import AppKit
import SwiftUI
import WebKit

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
    /// Opens the transcript of whoever made it, to say what is wrong.
    let revise: () -> Void

    @State private var pane = Pane.both
    /// Which revision is in the After pane. Nil is the demo's own `url` — the newest one.
    @State private var revision: Int?

    package init(
        block: UserBlock,
        cards: [NotebookCard],
        waiting: CodeSession?,
        approve: @escaping (DemoRevision?) -> Void,
        revise: @escaping () -> Void
    ) {
        self.block = block
        self.cards = cards
        self.waiting = waiting
        self.approve = approve
        self.revise = revise
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
                Text(hint).font(Typo.text(12)).foregroundStyle(Theme.tx3).lineLimit(1)
            }
            Spacer(minLength: 8)
            if !block.branch.isEmpty {
                Text(block.branch).font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
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
        .font(Typo.text(12)).tint(Theme.tx2)
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
                    Text(note).font(Typo.text(12)).foregroundStyle(Theme.tx2).lineLimit(1)
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
                Text(pass.label).font(Typo.mono(10.5))
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
                Text(label.uppercased()).font(Typo.section).tracking(1.4).foregroundStyle(tint)
                Text(url?.absoluteString ?? "—")
                    .font(Typo.mono(10)).foregroundStyle(Theme.tx3).lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .frame(height: 34)
            .overlay(alignment: .bottom) { Rectangle().fill(Theme.line2).frame(height: 1) }
            if let url {
                WebPane(webView: DemoPages.view(for: url))
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
            .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
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
                        Text(task.title).font(Typo.text(12.5)).foregroundStyle(Theme.tx)
                            .lineLimit(2).multilineTextAlignment(.leading)
                        Text(task.id).font(Typo.mono(10)).foregroundStyle(Theme.tx3)
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
                            Text(item.text).font(Typo.text(12))
                                .foregroundStyle(item.done ? Theme.tx2 : Theme.tx3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }

        VStack(alignment: .leading, spacing: 10) {
            SectionLabel("Cost of the demo")
            Text(cost).font(Typo.text(12)).foregroundStyle(Theme.tx2)
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

    private var actionBar: some View {
        ActionBar {
            Image(systemName: "hand.raised.fill").font(.system(size: 12))
                .foregroundStyle(Theme.amber)
            Text(
                block.waiting
                    ? "Nothing is written to the repo until you build it."
                    : "Approved. \(waiting.map { "\($0.title) has it." } ?? "The lead has it.")"
            )
            .font(Typo.text(12.5))
            .foregroundStyle(block.waiting ? Theme.tx3 : Theme.green)
            Spacer(minLength: 12)
            Button {
                revise()
            } label: {
                Label("Request changes", systemImage: "arrow.uturn.left")
            }
            .buttonStyle(.console)
            .disabled(!block.waiting)
            Button {
                approve(shown ?? block.revisions.last)
            } label: {
                Label("Build it", systemImage: "checkmark.seal")
            }
            .buttonStyle(.consolePrimary)
            .disabled(!block.waiting)
        }
    }
}

/// One web view per address, kept for the life of the app. Rebuilding a `WKWebView` every
/// time SwiftUI re-runs `body` — which the 2-second notebook poll guarantees — reloads the
/// page under the user and loses their scroll position on every tick.
enum DemoPages {
    private static var views: [URL: WKWebView] = [:]
    private static var order: [URL] = []

    @MainActor static func view(for url: URL) -> WKWebView {
        if let existing = views[url] { return existing }
        let view = WKWebView()
        // Otherwise a page that has not loaded — or a dev server that is not running —
        // flashes a white rectangle in the middle of a near-black window. The public
        // property covers overscroll; the KVC one is what stops the view painting its own
        // white ground before the first paint of the page.
        view.underPageBackgroundColor = NSColor(Theme.bg)
        view.setValue(false, forKey: "drawsBackground")
        view.load(URLRequest(url: url))
        views[url] = view
        order.append(url)
        // ponytail: a plain cap rather than an LRU. Two panes and a handful of revisions
        // is the whole working set; anything older is cheaper to reload than to keep.
        while order.count > 8, let oldest = order.first {
            views.removeValue(forKey: oldest)
            order.removeFirst()
        }
        return view
    }
}
