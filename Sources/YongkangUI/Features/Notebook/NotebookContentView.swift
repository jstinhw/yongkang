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
            resolved(text).font(Typo.text(13)).lineSpacing(3).foregroundStyle(Theme.prose)
        case .checklist(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(item.done ? Theme.green : Theme.tx4)
                        resolved(item.text)
                            .foregroundStyle(item.done ? Theme.tx2 : Theme.prose)
                    }
                    .font(Typo.text(12.5))
                }
            }
        case .list(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("•").foregroundStyle(Theme.tx3)
                        resolved(item).foregroundStyle(Theme.prose)
                    }
                    .font(Typo.text(12.5))
                }
            }
        case .numberedList(let items):
            VStack(alignment: .leading, spacing: 5) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    HStack(alignment: .top, spacing: 6) {
                        Text("\(index + 1).")
                            .font(Typo.mono(11.5))
                            .foregroundStyle(Theme.tx3)
                        resolved(item).foregroundStyle(Theme.prose)
                    }
                    .font(Typo.text(12.5))
                }
            }
        case .code(let code):
            ScrollView(.horizontal) {
                Text(code)
                    .font(Typo.mono(11.5))
                    .foregroundStyle(Theme.tx2)
                    .textSelection(.enabled)
                    .padding(10)
            }
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.panel))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.wellLine, lineWidth: 1))
        }
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
