import SwiftUI
import YongkangCore

/// The board's request box: say what you want in your own words, `@`-tag a file or another
/// project, and Product files it as milestones and tasks and decides what waits on what. It
/// takes the assign bar's place while it is open — a prompt along the bottom, under the work,
/// the way an agent CLI's is — so the board stays in view while you write about it.
package struct RequestDock: View {
    let root: URL
    let projects: [Mention.Project]
    /// Product is still on the last request, so this goes to it as a change rather than a new
    /// request, and to the agent already running it.
    let followUp: Bool
    @Binding var text: String
    let agents: AgentChoice
    let send: (AgentKind) -> Void
    let close: () -> Void

    package init(
        root: URL, projects: [Mention.Project], followUp: Bool, text: Binding<String>, agents: AgentChoice,
        send: @escaping (AgentKind) -> Void, close: @escaping () -> Void
    ) {
        self.root = root
        self.projects = projects
        self.followUp = followUp
        _text = text
        self.agents = agents
        self.send = send
        self.close = close
    }

    /// This box's own pick, leaving the toolbar's default alone, like an Assign button's.
    @State private var chosen: AgentKind?

    private var agent: AgentKind { chosen ?? agents.initial }
    private var prompt: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var sendable: Bool {
        !prompt.isEmpty && (followUp || (!agents.untrusted.contains(agent) && agents.found?.contains(agent) != false))
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                SectionLabel(followUp ? "Ask for changes" : "New request")
                Text("Product turns it into milestones and tasks, and decides what waits on what")
                    .font(Typography.caption).foregroundStyle(Theme.tx3).lineLimit(1)
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).frame(width: 18, height: 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(Theme.tx3)
                .help("Close (Esc)")
                .accessibilityLabel("Close the request")
            }
            PromptField(
                placeholder: followUp ? "What should change?" : "What do you want? @ tags a project or a file",
                root: root, projects: projects, tagsAbove: true, text: $text, submit: submit)
            HStack(spacing: 10) {
                Text("@/ this group · @../ another group · @ a file here · ⇧↩ new line")
                    .font(Typography.mono).foregroundStyle(Theme.tx3).lineLimit(1)
                Spacer(minLength: 12)
                sendButton
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 14)
        .background(Theme.panel)
        .overlay(alignment: .top) { Rectangle().fill(Theme.line).frame(height: 1) }
        .onExitCommand(perform: close)
    }

    /// The agent and Send as one tray, like the Assign button the bar had. A follow-up goes to
    /// the session already running, so there is no agent to pick.
    private var sendButton: some View {
        HStack(spacing: 2) {
            if !followUp {
                AgentPicker(
                    agent: Binding {
                        agent
                    } set: {
                        chosen = $0
                    }, found: agents.found, lookUp: agents.lookUp,
                    purpose: "Agent to run Product", ghost: true)
            }
            Button(action: submit) {
                Label("Send to Product", systemImage: "arrow.up")
            }
            .buttonStyle(.consolePrimary)
            .disabled(!sendable)
        }
        .padding(2)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.raised))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.controlLine, lineWidth: 1))
    }

    private func submit() {
        guard sendable else { return }
        send(agent)
    }
}
