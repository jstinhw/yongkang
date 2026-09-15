import SwiftUI
import YongkangCore

/// One standing member of the Engineering Lead's team, opened from the roster: who it is,
/// what it owns, and — the part that is actually hard to find otherwise — the skill text
/// that *is* its job, read from the same file the lead hands the agent when it dispatches.
///
/// Nothing here is live. A member is a file in `.notebook/team/`, not a session; the only
/// moving part is the list of its agents running right now, which is a way back into them.
package struct TeamMemberDetail: View {
    let member: TeamMember
    /// The roster file this member was read from, so the reader can go edit it.
    let file: URL
    /// The project folder, which is where a skill installed for this project alone lives.
    let directory: URL
    /// This member's agents working right now, across every session in the project.
    let running: [(session: CodeSession, subagent: SubagentStatus)]
    let openSubagent: (CodeSession, SubagentStatus) -> Void

    @State private var docs: [SkillDoc] = []
    /// The rendered instructions of each skill, keyed by name. Parsed once on load — a
    /// SKILL.md is a page long, and doing it up front keeps expanding one instant.
    @State private var sections: [String: [NotebookContent.Section]] = [:]
    /// Which skills are open. Empty on purpose: a member can own several, and the page is
    /// about the agent, not about whichever of its skills happened to sort first.
    @State private var expanded: Set<String> = []
    @State private var notes: [NotebookContent.Section] = []

    package init(
        member: TeamMember,
        file: URL,
        directory: URL,
        running: [(session: CodeSession, subagent: SubagentStatus)],
        openSubagent: @escaping (CodeSession, SubagentStatus) -> Void
    ) {
        self.member = member
        self.file = file
        self.directory = directory
        self.running = running
        self.openSubagent = openSubagent
    }

    package var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                header
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if !notes.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                SectionLabel("Standing notes")
                                NotebookContentView(sections: notes, cards: [])
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface(padding: 16)
                        }
                        if docs.isEmpty {
                            Text(
                                "This agent has no skill assigned, so the lead has nothing "
                                    + "to route to it."
                            )
                            .font(Typo.text(12.5)).foregroundStyle(Theme.tx3)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .cardSurface()
                        }
                        ForEach(docs) { skillCard($0) }
                    }
                    .padding(22)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(Theme.bg)
            inspector
        }
        .task(id: member.id) { loadMember() }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 12) {
            RoleTile(role: member.skills.first ?? member.name, size: 36)
            VStack(alignment: .leading, spacing: 3) {
                Text(member.name).font(Typo.display(15))
                Text(member.owns.isEmpty ? member.skills.joined(separator: ", ") : member.owns)
                    .font(Typo.text(11)).foregroundStyle(Theme.tx3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            NotebookStyle.chip(
                "\(member.skills.count) skill\(member.skills.count == 1 ? "" : "s")",
                mono: true)
            if !running.isEmpty {
                NotebookStyle.pill("\(running.count) running", Theme.accent, live: true)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 16)
        .padding(.bottom, 6)
    }

    // MARK: - The skills

    /// One skill, shut. The header is the whole of it until you ask: a member can own
    /// several, and a page that opens with one of them unrolled reads as though that one
    /// is the agent. Opening it shows the file the agent is actually handed, verbatim.
    private func skillCard(_ doc: SkillDoc) -> some View {
        let open = expanded.contains(doc.name)
        return VStack(alignment: .leading, spacing: 14) {
            Button {
                toggle(doc.name)
            } label: {
                HStack(alignment: .top, spacing: 11) {
                    RoleTile(role: doc.name, size: 26)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(doc.name).font(Typo.mono(12.5, .semibold)).foregroundStyle(Theme.tx)
                        Text(summary(of: doc)).font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                            .fixedSize(horizontal: false, vertical: true)
                            .multilineTextAlignment(.leading)
                    }
                    Spacer(minLength: 8)
                    if !doc.tools.isEmpty {
                        NotebookStyle.chip("\(doc.tools.count) tools", mono: true)
                    }
                    Image(systemName: open ? "chevron.down" : "chevron.right")
                        .font(.system(size: 10, weight: .semibold)).foregroundStyle(Theme.tx3)
                        .padding(.top, 4)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            if open {
                if !doc.tools.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        SectionLabel("Tools", trailing: "\(doc.tools.count)")
                        ChipGrid(doc.tools) { NotebookStyle.chip($0, mono: true) }
                    }
                }
                Divider().overlay(Theme.line)
                NotebookContentView(sections: sections[doc.name] ?? [], cards: [])
                if let url = doc.url {
                    HStack(spacing: 9) {
                        Text(url.path).font(Typo.mono(9.5)).foregroundStyle(Theme.tx4)
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([url])
                        } label: {
                            Label("Reveal", systemImage: "folder")
                        }
                        .buttonStyle(.consoleGhost)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
    }

    /// What the skill says it is, or why there is nothing to open.
    private func summary(of doc: SkillDoc) -> String {
        if doc.url == nil {
            return "Not installed in this project, in ~/.claude/skills or ~/.agents/skills, "
                + "and not packaged with the app — the agent falls back to whatever its "
                + "provider discovers natively."
        }
        return doc.summary.isEmpty ? "No description in the skill's frontmatter." : doc.summary
    }

    // MARK: - Inspector

    private var inspector: some View {
        Inspector {
            if !member.owns.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Owns")
                    Text(member.owns).font(Typo.text(11.5)).foregroundStyle(Theme.tx3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !running.isEmpty {
                VStack(alignment: .leading, spacing: 9) {
                    SectionLabel("Running now", trailing: "\(running.count)")
                    ForEach(running, id: \.subagent.id) { found in
                        Button {
                            openSubagent(found.session, found.subagent)
                        } label: {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(found.subagent.description).font(Typo.mono(10.5))
                                    .foregroundStyle(Theme.tx2)
                                    .lineLimit(2).multilineTextAlignment(.leading)
                                Text("in \(found.session.title)").font(Typo.text(10.5))
                                    .foregroundStyle(Theme.tx3).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            Spacer(minLength: 0)
            TranscriptSource(
                url: FileManager.default.fileExists(atPath: file.path) ? file : nil,
                label: "Agent file")
        }
    }

    private func toggle(_ name: String) {
        if expanded.contains(name) { expanded.remove(name) } else { expanded.insert(name) }
    }

    private func loadMember() {
        docs = member.skills.map { SkillDoc.load($0, project: directory) }
        sections = Dictionary(
            docs.map { ($0.name, NotebookContent.sections($0.body)) },
            uniquingKeysWith: { first, _ in first })
        expanded = []
        notes = NotebookContent.sections(member.notes)
    }
}

/// A grid of chips. Enough layout for a tool list and nothing more — the width comes from
/// the parent, and the rows are laid out in one pass over the items.
struct ChipGrid<Item: Hashable, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content

    init(_ items: [Item], @ViewBuilder content: @escaping (Item) -> Content) {
        self.items = items
        self.content = content
    }

    var body: some View {
        // ponytail: fixed 3-up grid rather than a measuring flow layout. Tool names are
        // short and the inspector width is fixed; swap in a Layout if that stops holding.
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: 6, alignment: .leading),
                count: 3),
            alignment: .leading, spacing: 6
        ) {
            ForEach(items, id: \.self) { content($0) }
        }
    }
}
