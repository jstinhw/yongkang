import AppKit
import SwiftUI
import YongkangCore

/// What a project's agents decided and learned: every memory entry in its notebook, grouped by
/// the milestone it is filed under, with the one picked open beside the list. Every agent reads
/// these before it starts, so this is where to see — and correct — what they will go on.
package struct MemoryPage: View {
    let project: Project
    /// The entry the route names, or nil for the first one.
    let selected: String?
    let select: (String) -> Void
    /// The raw file in the editor.
    let edit: (URL) -> Void
    /// A new entry, filed under one milestone — memory has to live inside one.
    let add: (String) -> Void

    /// Nil shows every type.
    @State private var type: String?
    @State private var content: [NotebookContent.Section] = []

    package init(
        project: Project, selected: String?, select: @escaping (String) -> Void, edit: @escaping (URL) -> Void,
        add: @escaping (String) -> Void
    ) {
        self.project = project
        self.selected = selected
        self.select = select
        self.edit = edit
        self.add = add
    }

    package var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: 440)
                .overlay(alignment: .trailing) { Rectangle().fill(Theme.line).frame(width: 1) }
            reader
        }
        .background(Theme.bg)
    }

    // MARK: - The entries

    private var memory: [NotebookCard] {
        NotebookIndex.ordered(project.cards.filter { $0.kind == .memory }).sorted { $0.id > $1.id }
    }

    private var milestones: [NotebookCard] {
        NotebookIndex.ordered(project.cards.filter { $0.kind == .project })
    }

    private func kind(of card: NotebookCard) -> String { card.memoryType.isEmpty ? "note" : card.memoryType }

    private var shown: NotebookCard? {
        memory.first { $0.id == selected } ?? memory.first
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Memory").font(Typography.title).foregroundStyle(Theme.tx)
                        Text(
                            "What \(project.name)’s agents decided and learned. Every agent reads it before it starts."
                        )
                        .font(Typography.body).foregroundStyle(Theme.tx3)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 0)
                    Menu {
                        ForEach(milestones) { milestone in
                            Button(milestone.title) { add(milestone.id) }
                        }
                    } label: {
                        Label("New Memory", systemImage: "plus")
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                    .disabled(milestones.isEmpty)
                    .help("Memory is filed under a milestone")
                }
                filters
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 10)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if memory.isEmpty {
                        Text("Nothing remembered yet. Agents write here as they decide things.")
                            .font(Typography.body).foregroundStyle(Theme.tx3)
                            .padding(.horizontal, 22).padding(.vertical, 8)
                    }
                    ForEach(groups, id: \.title) { group in
                        SectionLabel(group.title, trailing: "\(group.entries.count)")
                            .padding(.horizontal, 22).padding(.top, 14).padding(.bottom, 6)
                        ForEach(group.entries) { row($0) }
                    }
                }
                .padding(.bottom, 14)
            }
        }
    }

    private var filters: some View {
        let kinds = ["decision", "fact", "constraint", "assumption", "note"].filter { kind in
            memory.contains { self.kind(of: $0) == kind }
        }
        return HStack(spacing: 6) {
            filter(nil, "All", memory.count)
            ForEach(kinds, id: \.self) { kind in
                filter(kind, kind.capitalized, memory.filter { self.kind(of: $0) == kind }.count)
            }
        }
    }

    private func filter(_ kind: String?, _ label: String, _ count: Int) -> some View {
        let on = type == kind
        return Button {
            type = kind
        } label: {
            HStack(spacing: 5) {
                Text(label).font(Typography.caption(.semibold))
                Text("\(count)").font(Typography.monoCaption).foregroundStyle(Theme.tx3)
            }
            .foregroundStyle(on ? Theme.tx : Theme.tx2)
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(RoundedRectangle(cornerRadius: 6).fill(on ? Theme.raised : .clear))
            .overlay(
                RoundedRectangle(cornerRadius: 6).strokeBorder(on ? Theme.hairline : Theme.controlLine, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(on ? .isSelected : [])
    }

    /// The entries the filter lets through, under the milestone each is filed in.
    private var groups: [(title: String, entries: [NotebookCard])] {
        let passing = memory.filter { type == nil || kind(of: $0) == type }
        let filed = milestones.compactMap { milestone -> (String, [NotebookCard])? in
            let entries = passing.filter { $0.project == milestone.id }
            return entries.isEmpty ? nil : (milestone.title, entries)
        }
        let known = Set(milestones.map(\.id))
        let loose = passing.filter { !known.contains($0.project ?? "") }
        return filed + (loose.isEmpty ? [] : [("Not filed", loose)])
    }

    private func row(_ card: NotebookCard) -> some View {
        Button {
            select(card.id)
        } label: {
            HStack(alignment: .top, spacing: 12) {
                Text(kind(of: card)).font(Typography.caption(.semibold)).foregroundStyle(Theme.prose)
                    .frame(width: 74).padding(.vertical, 2)
                    .background(RoundedRectangle(cornerRadius: 5).fill(Theme.raised))
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Theme.chipLine, lineWidth: 1))
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.title).font(Typography.body(.semibold)).foregroundStyle(Theme.tx).lineLimit(1)
                    if let brief = NotebookIndex.brief(of: card.body) {
                        Text(brief).font(Typography.caption).foregroundStyle(Theme.prose).lineLimit(1)
                    }
                    Text(meta(of: card)).font(Typography.monoCaption).foregroundStyle(Theme.tx3).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12).padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .accessibilityElement(children: .combine)
        }
        .buttonStyle(.plain)
        .rowSelection(shown?.id == card.id)
        .padding(.horizontal, 10)
        .padding(.bottom, 2)
    }

    /// When it was written — the format names memory files `YYYY-MM-DD-<slug>` — and what it is
    /// about.
    private func meta(of card: NotebookCard) -> String {
        let date = card.id.count >= 10 ? String(card.id.prefix(10)) : ""
        let subject = card.subject.flatMap { id in project.cards.first { $0.id == id }?.title }
        return [date, subject.map { "about \($0)" }].compactMap { $0?.isEmpty == false ? $0 : nil }
            .joined(separator: " · ")
    }

    // MARK: - The one picked

    @ViewBuilder private var reader: some View {
        if let card = shown {
            VStack(alignment: .leading, spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(spacing: 8) {
                            NotebookStyle.chip(kind(of: card))
                            Text(meta(of: card)).font(Typography.mono).foregroundStyle(Theme.tx3)
                        }
                        Text(card.title).font(Typography.title).foregroundStyle(Theme.tx)
                            .fixedSize(horizontal: false, vertical: true)
                        NotebookContentView(sections: content, cards: project.cards)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.horizontal, 30)
                    .padding(.vertical, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                ActionBar {
                    Text(card.url.path.replacingOccurrences(of: project.directory.path + "/", with: ""))
                        .font(Typography.mono).foregroundStyle(Theme.tx3)
                        .lineLimit(1).truncationMode(.middle)
                    Spacer(minLength: 12)
                    Button("Edit") { edit(card.url) }.buttonStyle(.console)
                    Button("Reveal in Finder") {
                        NSWorkspace.shared.activateFileViewerSelecting([card.url])
                    }
                    .buttonStyle(.console)
                }
            }
            .task(id: card.body) { content = NotebookContent.sections(card.body) }
        } else {
            Text("Pick an entry to read it.")
                .font(Typography.body).foregroundStyle(Theme.tx3)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
