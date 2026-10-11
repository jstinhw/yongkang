import SwiftUI
import YongkangCore

/// Renders a page's parsed body: real checkboxes for a checklist, resolved titles in
/// place of `[[id]]` syntax, inline emphasis and code spans. `redundant` names ids
/// already shown elsewhere on the same page — a project's own task list — so a bullet
/// list that is nothing but links to them collapses instead of repeating it.
struct NotebookContentView: View {
    let sections: [NotebookContent.Section]
    let cards: [NotebookCard]
    var redundant: Set<String> = []

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
                sectionView(section)
            }
        }
    }

    @ViewBuilder
    private func sectionView(_ section: NotebookContent.Section) -> some View {
        let blocks = section.blocks.filter { !isRedundantList($0) }
        if !blocks.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                if let heading = section.heading {
                    SectionLabel(heading)
                }
                ForEach(Array(blocks.enumerated()), id: \.offset) { _, block in
                    blockView(block)
                }
            }
        }
    }

    /// A bullet list is redundant only when every item is a bare `[[id]]` and every id
    /// is already on screen — an annotated link ("`[[x]]` — why it matters") always
    /// carries information the task list does not, so it stays.
    private func isRedundantList(_ block: NotebookContent.Block) -> Bool {
        guard case .list(let items) = block, !items.isEmpty else { return false }
        return items.allSatisfy {
            NotebookContent.isPureLinks($0)
                && NotebookContent.wikilinks(in: $0).allSatisfy(redundant.contains)
        }
    }

    @ViewBuilder
    private func blockView(_ block: NotebookContent.Block) -> some View {
        switch block {
        case .paragraph(let text):
            resolved(text).font(Typography.body).lineSpacing(3).foregroundStyle(Theme.prose)
                .textSelection(.enabled)
        case .checklist(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(item.done ? Theme.green : Theme.tx4)
                        resolved(item.text)
                            .foregroundStyle(item.done ? Theme.tx2 : Theme.prose)
                            .textSelection(.enabled)
                    }
                    .font(Typography.body)
                }
            }
        case .list(let items):
            lines(items) { _ in Text("•  ").foregroundStyle(Theme.tx3) }
        case .numberedList(let items):
            lines(items) { Text("\($0 + 1).  ").font(Typography.code).foregroundStyle(Theme.tx3) }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(Typography.code)
                    .foregroundStyle(Theme.tx2)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.wellLine, lineWidth: 1))
        }
    }

    /// A list as one text, its marker leading each item. SwiftUI selects within a single `Text`
    /// only, so a list drawn a row per item could be copied an item at a time; as one, a drag
    /// takes as many items as it covers. A wrapped item no longer hangs under its own first line.
    private func lines(_ items: [String], marker: (Int) -> Text) -> some View {
        items.enumerated().reduce(Text("")) { text, item in
            text + Text(item.offset == 0 ? "" : "\n") + marker(item.offset)
                + resolved(item.element).foregroundStyle(Theme.prose)
        }
        .font(Typography.body).lineSpacing(5)
        .textSelection(.enabled)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// `text` with every `[[id]]` swapped for the linked card's title, and inline
    /// Markdown (bold, italic, code spans) rendered rather than shown as punctuation —
    /// `LocalizedStringKey` parses that for free, per run, so it composes with the
    /// per-token wikilink styling below. An id nothing resolves to is flagged in
    /// orange, the same as an unknown `depends_on`.
    private func resolved(_ text: String) -> Text {
        NotebookContent.tokens(text).reduce(Text("")) { acc, token in
            switch token {
            case .text(let s):
                return acc + Text(LocalizedStringKey(s))
            case .link(let id):
                let card = cards.first { $0.id == id }
                return acc
                    + Text(card?.title ?? id)
                    .foregroundColor(card == nil ? Theme.amber : Theme.accent)
                    .fontWeight(.medium)
            }
        }
    }
}
