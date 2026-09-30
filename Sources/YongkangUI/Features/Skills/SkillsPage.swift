import AppKit
import SwiftUI
import YongkangCore

/// The skills a project's agents can load. It opens on the shared ones, the skills in the home
/// folders every project's agents read; picking a CLI swaps the list for what that CLI finds on
/// its own here, the project's copies first. Nothing on it is written: a skill is a folder, and
/// the row's menu is the way to it.
package struct SkillsPage: View {
    let project: URL

    /// Nil lists the shared skills.
    @State private var agent: AgentKind?
    @State private var own: [SkillDoc] = []
    @State private var shared: [SkillDoc] = []
    @State private var query = ""
    /// The sections folded away, by title. Kept across launches: 80-odd shared skills are a
    /// list you shut once and leave shut.
    @AppStorage("skillsFolded") private var folded = ""

    private let home = FileManager.default.homeDirectoryForCurrentUser

    package init(project: URL) {
        self.project = project
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            controls
            Text(caption).font(Typography.body).foregroundStyle(Theme.tx3)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if agent != nil, own.isEmpty, shared.isEmpty {
                        empty
                    } else {
                        if agent != nil { section("From this project", own) }
                        section("Shared", shared)
                    }
                }
                .padding(.bottom, 20)
            }
        }
        .padding(.horizontal, 28)
        .padding(.top, 20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Theme.bg)
        .task(id: agent) { load() }
    }

    // MARK: - Controls

    private var controls: some View {
        HStack(spacing: 10) {
            Text("Show").font(Typography.body).foregroundStyle(Theme.tx3)
            Menu {
                Button("Shared skills") { agent = nil }
                Divider()
                ForEach(AgentKind.allCases) { kind in
                    Button(kind.displayName) { agent = kind }
                }
            } label: {
                Label(agent?.displayName ?? "Shared skills", systemImage: agent?.systemImage ?? "book.closed")
                    .font(Typography.body)
            }
            .menuStyle(.button)
            .buttonStyle(.console)
            .fixedSize()
            .accessibilityLabel("Show the skills of")
            Spacer(minLength: 12)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 11)).foregroundStyle(Theme.tx3)
                TextField("Filter skills", text: $query).textFieldStyle(.plain).font(Typography.body)
            }
            .padding(.horizontal, 9)
            .frame(width: 240, height: 28)
            .background(RoundedRectangle(cornerRadius: 8).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Theme.controlLine, lineWidth: 1))
        }
    }

    /// Where the list came from, so an empty or surprising one explains itself.
    private var caption: String {
        guard let agent else {
            let folders = AgentKind.allCases.flatMap { $0.provider.skillFolders.home }
            let unique = folders.reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            return "Every project’s agents can load these, from " + unique.map { "~/\($0)" }.joined(separator: ", ")
                + "."
        }
        let folders = agent.provider.skillFolders
        let count = own.count + shared.count
        return "\(agent.displayName) reads \(folders.project.joined(separator: ", ")) in this project, then "
            + folders.home.map { "~/\($0)" }.joined(separator: ", ")
            + " — \(count) skill\(count == 1 ? "" : "s")."
    }

    // MARK: - The lists

    @ViewBuilder private func section(_ title: String, _ docs: [SkillDoc]) -> some View {
        let shown = docs.filter(matches)
        // A name you typed is never kept behind a closed fold.
        let open = !isFolded(title) || !query.isEmpty
        if !docs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                Button {
                    toggle(title)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: open ? "chevron.down" : "chevron.right")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(Theme.tx3).frame(width: 10)
                        SectionLabel(title, trailing: "\(docs.count)")
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.panel)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("\(title), \(docs.count) skills, \(open ? "shown" : "hidden")")
                .accessibilityHint(open ? "Hides the list" : "Shows the list")
                if open { ForEach(shown) { row($0) } }
                if open, shown.isEmpty {
                    Text("None match “\(query)”.").font(Typography.body).foregroundStyle(Theme.tx3)
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.line2, lineWidth: 1))
            .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        }
    }

    private func row(_ doc: SkillDoc) -> some View {
        HStack(spacing: 12) {
            RoleTile(role: doc.name, size: 26)
            VStack(alignment: .leading, spacing: 2) {
                Text(doc.name).font(Typography.code(.semibold)).foregroundStyle(Theme.tx)
                Text(doc.summary.isEmpty ? "No description in the skill’s frontmatter." : doc.summary)
                    .font(Typography.body).foregroundStyle(Theme.tx3).lineLimit(1)
            }
            Spacer(minLength: 12)
            Text(place(of: doc)).font(Typography.mono).foregroundStyle(Theme.tx4).lineLimit(1)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .contentShape(Rectangle())
        .help(doc.summary)
        .contextMenu {
            if let url = doc.url {
                Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
            }
        }
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Text("No skills reach \(agent?.displayName ?? "") in this project.")
                .font(Typography.body).foregroundStyle(Theme.tx2)
            Text("Put a skill folder in one of the folders above and it shows here.")
                .font(Typography.caption).foregroundStyle(Theme.tx3)
        }
        .frame(maxWidth: .infinity)
        .padding(28)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(Theme.hairline, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    // MARK: - Reading

    private func isFolded(_ title: String) -> Bool {
        folded.split(separator: "\n").contains { $0 == title }
    }

    private func toggle(_ title: String) {
        let rest = folded.split(separator: "\n").map(String.init).filter { $0 != title }
        folded = (isFolded(title) ? rest : rest + [title]).joined(separator: "\n")
    }

    private func matches(_ doc: SkillDoc) -> Bool {
        query.isEmpty || doc.name.localizedCaseInsensitiveContains(query)
            || doc.summary.localizedCaseInsensitiveContains(query)
    }

    /// The folder a skill was found in, as the caption names it: relative to the project, or
    /// to `~`.
    private func place(of doc: SkillDoc) -> String {
        guard let root = doc.url?.deletingLastPathComponent().deletingLastPathComponent().path else { return "" }
        if root.hasPrefix(project.path + "/") { return String(root.dropFirst(project.path.count + 1)) }
        if root.hasPrefix(home.path + "/") { return "~/" + root.dropFirst(home.path.count + 1) }
        return root
    }

    /// ponytail: on the main thread, like a member's page reads its skills. A few dozen small
    /// files is milliseconds; move it to `Task.detached` if a home folder ever holds hundreds.
    private func load() {
        let found = agent.map { Skills.loaded(by: $0, project: project) } ?? (project: [], shared: Skills.shared())
        own = found.project
        shared = found.shared
    }
}
