import SwiftUI

/// Every project at once. Leaving a project lands back here; clicking one enters it.
struct ProjectsHome: View {
    let projects: [Project]
    let enter: (Project) -> Void
    let add: () -> Void
    let close: (Project) -> Void

    var body: some View {
        ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 12)],
                      alignment: .leading, spacing: 12) {
                ForEach(projects) { project in
                    Button { enter(project) } label: { card(project) }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button("Reveal in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([project.directory])
                            }
                            Button("Close Project") { close(project) }
                        }
                }
                Button(action: add) {
                    VStack(spacing: 6) {
                        Image(systemName: "folder.badge.plus").font(.title2)
                        Text("Open Project Folder…")
                    }
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 96)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4]))
                    )
                }
                .buttonStyle(.plain)
            }
            .padding(16)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private func card(_ project: Project) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(project.name, systemImage: "folder")
                .font(.headline)
                .lineLimit(1)
            Text(project.directory.path)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 4)
            Text(summary(project))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 96, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
        .contentShape(RoundedRectangle(cornerRadius: 10))
    }

    private func summary(_ project: Project) -> String {
        let notebook = project.hasNotebook ? count(project.pageCount, "page") : "no notebook"
        return "\(notebook) · \(count(project.sessions.count, "session"))"
    }

    private func count(_ n: Int, _ noun: String) -> String {
        "\(n) \(noun)\(n == 1 ? "" : "s")"
    }
}
