import SwiftUI

/// The lead as an orchestrator: assigned notebook tasks and the spawned agents attached
/// to each one. Its live terminal is the sibling pane selected in the app toolbar.
struct EngineeringLeadBoard: View {
    let session: CodeSession
    let cards: [NotebookCard]
    let showDone: Bool
    let openTask: (String) -> Void
    let openSubagent: (SubagentStatus) -> Void

    private var done: Set<String> {
        Set(cards.filter { $0.kind == .task && $0.status == "done" }.map(\.id))
    }

    private var taskIDs: [String] {
        let running = Subagents.runningTaskIDs(session.subagents)
        return showDone ? session.taskIDs : session.taskIDs.filter { !done.contains($0) || running.contains($0) }
    }

    private var groups: [SubagentTaskGroup] {
        Subagents.grouped(session.subagents, by: taskIDs)
    }

    private var unlinked: [SubagentStatus] {
        session.subagents.filter { $0.taskID == nil }
    }

    var body: some View {
        if groups.isEmpty && unlinked.isEmpty {
            VStack(spacing: 8) {
                Image(systemName: "person.2")
                    .font(.system(size: 24))
                    .foregroundStyle(.tertiary)
                Text(session.taskIDs.isEmpty ? "No tasks assigned." : "All assigned tasks are complete.")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groups) { task($0) }
                    if !unlinked.isEmpty { unlinkedAgents }
                }
                .padding(14)
            }
        }
    }

    private func task(_ group: SubagentTaskGroup) -> some View {
        let card = cards.first { $0.kind == .task && $0.id == group.id }
        let state = group.subagents.contains(where: { $0.running }) ? "active" : card?.status
        return VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Button { openTask(group.id) } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(card?.title ?? group.id).font(.headline)
                        if card?.title != nil && card?.title != group.id {
                            Text(group.id).font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
                .buttonStyle(.plain)
                .disabled(card == nil)
                if let state, !state.isEmpty { NotebookStyle.pill(state) }
                if card == nil { NotebookStyle.pill("missing") }
                Spacer(minLength: 12)
                Text("\(group.subagents.count) agent\(group.subagents.count == 1 ? "" : "s")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if group.subagents.isEmpty {
                Label("Waiting for dispatch", systemImage: "hourglass")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(group.subagents) { agent($0) }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }

    private func agent(_ subagent: SubagentStatus) -> some View {
        Button { openSubagent(subagent) } label: {
            HStack(spacing: 8) {
                Image(systemName: subagent.running ? "circle.dotted" : "checkmark.circle")
                    .foregroundStyle(subagent.running ? Color.accentColor : Color.secondary)
                VStack(alignment: .leading, spacing: 1) {
                    Text(subagent.description)
                    Text(subagent.agentType)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 12)
                Text(subagent.running ? "Running" : "Done")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("View \(subagent.description)")
    }

    private var unlinkedAgents: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Unlinked agents").font(.headline)
            Text("Their names do not match an assigned task.")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(unlinked) { agent($0) }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color(nsColor: .controlBackgroundColor)))
    }
}
