import SwiftUI
import YongkangCore

/// What came of the last request on this board: Product still on it, or what it filed, which
/// the board marks "new" until this is dismissed. The outcome, not the transcript — that is one
/// click away, under the session it ran in. Once Product's turn is over, what it filed is the
/// user's to approve, which commits it, or to send back with what to change.
package struct RequestBanner: View {
    let filed: [NotebookCard]
    /// Nil where the banner is drawn on that session already.
    let openSession: (() -> Void)?
    let askForChanges: () -> Void
    /// Nil until Product has filed something and stopped.
    let approve: (() -> Void)?
    let dismiss: () -> Void

    package init(
        filed: [NotebookCard], openSession: (() -> Void)?, askForChanges: @escaping () -> Void,
        approve: (() -> Void)? = nil, dismiss: @escaping () -> Void
    ) {
        self.filed = filed
        self.openSession = openSession
        self.askForChanges = askForChanges
        self.approve = approve
        self.dismiss = dismiss
    }

    package var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "sparkles").foregroundStyle(Theme.accent)
            Text(RequestBanner.summary(of: filed, finished: approve != nil)).font(Typography.body)
                .foregroundStyle(Theme.tx).lineLimit(1)
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

    /// "a milestone and 3 tasks", in the board's own words for them.
    /// `finished` with nothing new filed is a request Product answered by changing what was there.
    static func summary(of filed: [NotebookCard], finished: Bool = false) -> String {
        let counted = [
            count(filed.filter { $0.kind == .project }.count, "milestone"),
            count(filed.filter { $0.kind == .task }.count, "task"),
        ].compactMap { $0 }
        guard !counted.isEmpty else {
            return finished ? "Product changed the board for your request." : "Product is on your request."
        }
        return "Product filed your request as " + counted.joined(separator: " and ") + "."
    }

    private static func count(_ number: Int, _ noun: String) -> String? {
        switch number {
        case 0: return nil
        case 1: return "a \(noun)"
        default: return "\(number) \(noun)s"
        }
    }
}
