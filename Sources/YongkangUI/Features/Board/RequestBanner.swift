import SwiftUI
import YongkangCore

/// What came of the last request on this board: Product still on it, or what it filed, which
/// the board marks "new" until this is dismissed. The outcome, not the transcript — that is one
/// click away, under the session it ran in. Once Product's turn is over, what it filed is the
/// user's to approve, which commits it, or to send back with what to change.
///
/// A request that crosses projects names the other one: the project that asked for it, or the
/// one Product asked for its part — while the answer is still to come, and once it is in.
package struct RequestBanner: View {
    let filed: [NotebookCard]
    /// The project that asked for this request, by name, when its message started it.
    let from: String?
    /// The project Product asked for its part, by name, with the title of what it asked.
    let asked: (project: String, title: String)?
    /// Whether that project's answer is still to come.
    let waiting: Bool
    /// Nil where the banner is drawn on that session already.
    let openSession: (() -> Void)?
    let askForChanges: () -> Void
    /// Nil until Product has filed something and stopped.
    let approve: (() -> Void)?
    let dismiss: () -> Void

    package init(
        filed: [NotebookCard], from: String? = nil, asked: (project: String, title: String)? = nil,
        waiting: Bool = false, openSession: (() -> Void)?, askForChanges: @escaping () -> Void,
        approve: (() -> Void)? = nil, dismiss: @escaping () -> Void
    ) {
        self.filed = filed
        self.from = from
        self.asked = asked
        self.waiting = waiting
        self.openSession = openSession
        self.askForChanges = askForChanges
        self.approve = approve
        self.dismiss = dismiss
    }

    package var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            Text(RequestBanner.line(of: filed, finished: approve != nil, from: from, asked: asked, waiting: waiting))
                .font(Typography.body).foregroundStyle(Theme.tx).lineLimit(1)
            Spacer(minLength: 12)
            if let openSession {
                Button("Open session", action: openSession).buttonStyle(.consoleGhost)
            }
            if !filed.isEmpty || approve != nil {
                Button("Ask for changes", action: askForChanges).buttonStyle(.console)
            }
            if let approve {
                Button(action: approve) { Label("Approve and commit", systemImage: "checkmark.seal") }
                    .buttonStyle(.consolePrimary)
            }
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
            }
            .buttonStyle(.plain)
            .foregroundStyle(Theme.tx3)
            .help("Dismiss")
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.accent.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .background(Theme.bg)
    }

    /// What the banner says, with the other project's name, if any, in bold. Waiting on that
    /// project's answer is all there is to say until it comes: what Product asked, dimmed after it.
    static func line(
        of filed: [NotebookCard], finished: Bool, from: String? = nil, asked: (project: String, title: String)? = nil,
        waiting: Bool = false
    ) -> AttributedString {
        if let asked, waiting {
            var title = AttributedString(" · asked “\(asked.title)”")
            title.foregroundColor = Theme.tx3
            return naming(asked.project, in: "Product is waiting on \(asked.project)’s answer") + title
        }
        if let from { return naming(from, in: summary(of: filed, finished: finished, whose: "\(from)’s")) }
        let own = summary(of: filed, finished: finished)
        guard let asked else { return AttributedString(own) }
        return naming(asked.project, in: String(own.dropLast()) + "; \(asked.project) filed its own part.")
    }

    /// `sentence`, with the first `name` in it set in bold.
    private static func naming(_ name: String, in sentence: String) -> AttributedString {
        var text = AttributedString(sentence)
        if let range = text.range(of: name) { text[range].font = Typography.body(.semibold) }
        return text
    }

    /// "a milestone and 3 tasks", in the board's own words for them.
    /// `finished` with nothing new filed is a request Product answered by changing what was there.
    static func summary(of filed: [NotebookCard], finished: Bool = false, whose: String = "your") -> String {
        let counted = [
            count(filed.filter { $0.kind == .project }.count, "milestone"),
            count(filed.filter { $0.kind == .task }.count, "task"),
        ].compactMap { $0 }
        guard !counted.isEmpty else {
            return finished ? "Product changed the board for \(whose) request." : "Product is on \(whose) request."
        }
        return "Product filed \(whose) request as " + counted.joined(separator: " and ") + "."
    }

    private static func count(_ number: Int, _ noun: String) -> String? {
        switch number {
        case 0: return nil
        case 1: return "a \(noun)"
        default: return "\(number) \(noun)s"
        }
    }
}
