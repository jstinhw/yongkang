import SwiftUI
import AppKit

/// Every project at once — the way in. Leaving a project lands back here; clicking one
/// enters it. A card says only what you would want before choosing: how far the work has
/// got, who is on it, and whether anything is waiting on you.
struct ProjectsHome: View {
    let projects: [Project]
    let enter: (Project) -> Void
    /// Describe a project and an agent creates the folder and starts it.
    let create: () -> Void
    /// The other door: a folder that already exists.
    let add: () -> Void
    let close: (Project) -> Void

    /// The card under the pointer, which is the only one that offers to be removed. A
    /// permanent × on every card reads as a grid of things to undo.
    @State private var hovered: Project.ID?

    private var running: Int {
        projects.reduce(0) { $0 + $1.sessions.filter { !$0.exited && $0.agent != nil }.count }
    }
    private var waiting: Int {
        projects.reduce(0) { $0 + $1.blocks.filter(\.waiting).count }
    }

    var body: some View {
        VStack(spacing: 0) {
            top
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    hero
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)],
                              alignment: .leading, spacing: 16) {
                        ForEach(projects) { project in
                            Button { enter(project) } label: { card(project) }
                                .buttonStyle(.plain)
                                .overlay(alignment: .topTrailing) {
                                    // Centred on the progress ring, and never overhanging
                                    // the card: a badge outside the frame is outside what
                                    // the pointer is tracked over, so half of it would
                                    // draw but not click.
                                    if hovered == project.id {
                                        removeTile(project).padding(20)
                                    }
                                }
                                .onHover { inside in
                                    hovered = inside ? project.id
                                                     : (hovered == project.id ? nil : hovered)
                                }
                                .contextMenu {
                                    Button("Reveal in Finder") {
                                        NSWorkspace.shared.activateFileViewerSelecting([project.directory])
                                    }
                                    Button("Remove from Fleet") { close(project) }
                                }
                        }
                        newProjectTile
                        openFolderTile
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
        .background(Theme.bg)
    }

    private var top: some View {
        HStack(spacing: 14) {
            Text("YK")
                .font(Typo.mono(12, .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(RoundedRectangle(cornerRadius: 9).fill(Color(hex: 0x141C28)))
                .overlay(RoundedRectangle(cornerRadius: 9)
                    .strokeBorder(Color(hex: 0x2B3B52), lineWidth: 1))
            Text("Yongkang").font(Typo.display(14)).tracking(0.3)
            Spacer(minLength: 12)
        }
        .padding(.horizontal, 32)
        .frame(height: 60)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.line).frame(height: 1) }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 11) {
            Text("Fleet").font(Typo.display(27)).foregroundStyle(Theme.tx)
            HStack(spacing: 18) {
                strip(Theme.accent, "\(running) agent\(running == 1 ? "" : "s") running", live: running > 0)
                strip(Theme.amber, "\(waiting) waiting on you", live: false)
                strip(Theme.green, "\(projects.count) project\(projects.count == 1 ? "" : "s") open",
                      live: false)
            }
        }
        .padding(.top, 30)
    }

    private func strip(_ color: Color, _ text: String, live: Bool) -> some View {
        HStack(spacing: 7) {
            StateDot(color: color, live: live)
            Text(text).font(Typo.text(12.5)).foregroundStyle(Theme.tx2)
        }
    }

    private func card(_ project: Project) -> some View {
        let tasks = project.cards.filter { $0.kind == .task }
        let done = tasks.filter { $0.status == "done" }.count
        let blocks = project.blocks.filter(\.waiting).count
        let agents = project.sessions.filter { !$0.exited && $0.agent != nil }
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 11) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(project.name).font(Typo.display(16)).foregroundStyle(Theme.tx).lineLimit(1)
                    Text(project.directory.path)
                        .font(Typo.mono(10.5)).foregroundStyle(Theme.tx3)
                        .lineLimit(1).truncationMode(.head)
                }
                Spacer(minLength: 8)
                NotebookStyle.statusRing(done == tasks.count && !tasks.isEmpty ? "done" : "active",
                                         progress: tasks.isEmpty ? 0 : Double(done) / Double(tasks.count),
                                         size: 30)
            }
            HStack(spacing: 6) {
                // Four tiles is what fits beside the badge; the rest become a count, which
                // is all a card needs to say before you have even opened the project.
                let roles = agents.map { $0.isEngineeringLead ? "lead" : $0.title }
                    + agents.flatMap(\.activeSubagents).map(\.agentType)
                ForEach(Array(roles.prefix(4).enumerated()), id: \.offset) { _, role in
                    RoleTile(role: role, size: 22)
                }
                if roles.count > 4 {
                    Text("+\(roles.count - 4)").font(Typo.mono(10)).foregroundStyle(Theme.tx3)
                }
                Spacer(minLength: 4)
                if blocks > 0 {
                    NotebookStyle.pill("\(blocks) waiting", Theme.amber).fixedSize()
                }
            }
            .frame(height: 22)
            .padding(.top, 16)
            Rectangle().fill(Theme.line).frame(height: 1).padding(.vertical, 12)
            HStack(spacing: 8) {
                Text(summary(project)).font(Typo.text(11)).foregroundStyle(Theme.tx3).lineLimit(1)
                Spacer(minLength: 8)
                if !tasks.isEmpty {
                    Text("\(done)/\(tasks.count)").font(Typo.mono(11)).foregroundStyle(Theme.tx2)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface(padding: 16)
        .contentShape(RoundedRectangle(cornerRadius: 12))
    }

    /// The two ways to add one, sitting where a card would rather than in the toolbar:
    /// a folder that does not exist yet is described and built, one that does is opened
    /// as it stands. Picking which comes first, and only then is there a prompt to fill.
    private var newProjectTile: some View {
        tile("plus", "Describe a new project…", "an agent builds it", action: create)
            .keyboardShortcut("n")
    }

    private var openFolderTile: some View {
        tile("folder", "Open a folder you have", "nothing is created", action: add)
            .keyboardShortcut("o")
    }

    private func tile(_ symbol: String, _ title: String, _ note: String,
                      action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(spacing: 9) {
                Image(systemName: symbol).font(.system(size: 20))
                Text(title).font(Typo.text(12))
                Text(note).font(Typo.mono(10))
            }
            .foregroundStyle(Theme.tx3)
            .frame(maxWidth: .infinity, minHeight: 152)
            .background(RoundedRectangle(cornerRadius: 12)
                .strokeBorder(Color(hex: 0x262D3A), style: StrokeStyle(lineWidth: 1, dash: [4])))
        }
        .buttonStyle(.plain)
    }

    /// Removing a project takes it off this screen and nothing else: the folder, its
    /// notebook and anything an agent left there are untouched, and ⌘O opens it again.
    /// That is why it asks nothing first — there is nothing to lose by pressing it.
    private func removeTile(_ project: Project) -> some View {
        Button { close(project) } label: {
            Image(systemName: "xmark")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(Theme.tx2)
                .frame(width: 22, height: 22)
                .background(Circle().fill(Theme.card))
                .overlay(Circle().strokeBorder(Theme.line2, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Remove \(project.name) from Fleet — the folder stays on disk")
    }

    private func summary(_ project: Project) -> String {
        guard project.hasNotebook else { return "no notebook yet" }
        let sessions = project.sessions.filter { !$0.exited }.count
        return sessions == 0 ? "\(project.pageCount) pages"
                             : "\(sessions) session\(sessions == 1 ? "" : "s") live"
    }
}
