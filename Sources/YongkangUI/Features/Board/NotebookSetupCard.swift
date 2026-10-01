import SwiftUI
import YongkangCore

/// What the board shows while Notebook Setup writes the first notebook: the agent reads, you
/// approve its plan when it drafted one, it writes — with where it is, what it last did, and the
/// one thing to press. An import stays on the board rather than dropping you into a terminal,
/// so this is where the setup is followed; the session is a click away for whoever wants it.
package struct NotebookSetupCard: View {
    package enum Phase: Equatable { case reading, planReady, writing, stopped }

    let phase: Phase
    /// A question is up in its session. The step it is on turns amber and the card says so.
    let waiting: Bool
    /// A described project's setup, which drafts a plan to approve. An import writes only the
    /// roadmap, and Product plans the rest from it.
    let reviewsPlan: Bool
    let agent: String
    let project: String
    let planTitle: String?
    /// The notebook as it lands, counted while it is written.
    let cards: [NotebookCard]
    /// False for a stopped setup whose session is gone: there is nothing left to open.
    let hasSession: Bool
    let openSession: () -> Void
    let reviewPlan: () -> Void
    let rerun: () -> Void
    let activity: () async -> AgentActivity?

    @State private var live: AgentActivity?

    package init(
        phase: Phase, waiting: Bool, reviewsPlan: Bool, agent: String, project: String, planTitle: String?,
        cards: [NotebookCard], hasSession: Bool, openSession: @escaping () -> Void,
        reviewPlan: @escaping () -> Void, rerun: @escaping () -> Void,
        activity: @escaping () async -> AgentActivity?, initial: AgentActivity? = nil
    ) {
        self.phase = phase
        self.waiting = waiting
        self.reviewsPlan = reviewsPlan
        self.agent = agent
        self.project = project
        self.planTitle = planTitle
        self.cards = cards
        self.hasSession = hasSession
        self.openSession = openSession
        self.reviewPlan = reviewPlan
        self.rerun = rerun
        self.activity = activity
        _live = State(initialValue: initial)
    }

    package var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Rectangle().fill(Theme.line).frame(height: 1)
            if waiting { waitingNote }
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    SetupStepRow(step: step, last: index == steps.count - 1)
                }
            }
            .padding(.horizontal, 26).padding(.top, 20).padding(.bottom, 6)
            Rectangle().fill(Theme.line).frame(height: 1)
            footer
        }
        .frame(width: 580)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.line2, lineWidth: 1))
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DotGrid())
        .task(id: phase == .stopped) { await follow() }
    }

    /// ponytail: the whole transcript is read every 2 s while the card is up. That is fine for
    /// one setup session; tail the file instead if a long one ever makes the board stutter.
    private func follow() async {
        guard phase != .stopped else { return }
        while !Task.isCancelled {
            if let read = await activity() { live = read }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                SectionLabel("Setting up the notebook")
                Spacer(minLength: 12)
                if hasSession {
                    HStack(spacing: 6) {
                        StateDot(color: stateColor, live: stateColor == Theme.accent)
                        Text("\(agent) · \(stateWord)")
                    }
                    .font(Typography.caption).foregroundStyle(Theme.tx2)
                }
            }
            Text(title).font(Typography.headline).foregroundStyle(Theme.tx)
            Text(subtitle).font(Typography.body).foregroundStyle(Theme.tx2).lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 26).padding(.top, 24).padding(.bottom, 18)
    }

    private var stateColor: Color {
        phase == .stopped ? Theme.tx3 : waiting || phase == .planReady ? Theme.amber : Theme.accent
    }

    private var stateWord: String {
        phase == .stopped ? "exited" : waiting || phase == .planReady ? "waiting for you" : "working"
    }

    private var title: String {
        if waiting { return "Notebook Setup is waiting for you" }
        switch phase {
        case .reading: return "Reading \(project)"
        case .planReady: return "The plan is ready for you"
        case .writing: return reviewsPlan ? "Writing the notebook" : "Writing the roadmap"
        case .stopped: return hasSession ? "Notebook Setup stopped" : "No notebook yet"
        }
    }

    private var subtitle: String {
        if waiting {
            return "It stopped to ask you something. Answer it in its session, and this page carries on from there."
        }
        switch phase {
        case .reading where reviewsPlan:
            return "\(agent) is working out what you want to build. Nothing is written until you approve a plan."
        case .reading:
            return "\(agent) is reading the code, docs and git history to work out what this project is for, "
                + "and writes its roadmap from that. Milestones and tasks come later, from Product."
        case .planReady:
            return "Read what you will have and what waits on you. Create project there writes the notebook; "
                + "anything else you say changes the plan first."
        case .writing where reviewsPlan:
            return "You approved the plan. The roadmap, milestones, tasks and memory are being written now, "
                + "and the board opens on them when it is done."
        case .writing:
            return "It has read the project and is writing the roadmap. The board opens on it when it is done, "
                + "ready for Product to plan the first milestones."
        case .stopped:
            return hasSession
                ? "Its session ended before the notebook was written. Run it again and it reads the project from the start."
                : "Notebook Setup reads the project and writes its roadmap."
        }
    }

    private var waitingNote: some View {
        HStack(spacing: 14) {
            Circle().fill(Theme.amber).frame(width: 8, height: 8)
            Text("The agent is waiting in its session — to be let into this folder, or with a question for you.")
                .font(Typography.body).foregroundStyle(Theme.prose).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            Button("Answer in session", action: openSession).buttonStyle(.consolePrimary)
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.amber.opacity(0.08)))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.amber.opacity(0.3), lineWidth: 1))
        .padding(.horizontal, 26).padding(.top, 18)
    }

    // MARK: - Steps

    /// An import reads and writes its roadmap; a described project has its plan approved between.
    private var steps: [SetupStep] {
        reviewsPlan ? [readStep, approveStep, writeStep] : [readStep, writeStep]
    }

    private var held: SetupStep.State { waiting ? .waiting : .active }
    private let paused = "Paused — waiting for you in its session."

    private var readStep: SetupStep {
        let read = live.flatMap { $0.filesRead > 0 ? "\($0.filesRead) files read" : nil }
        switch phase {
        case .reading:
            return SetupStep(
                title: "Read the project", state: held, meta: read,
                detail: waiting ? paused : live == nil ? "Starting \(agent)…" : nil,
                content: waiting ? .none : .live(live))
        case .planReady, .writing:
            return SetupStep(
                title: "Read the project", state: .done, meta: read,
                detail: reviewsPlan ? "Read what there is, and drafted a plan." : "Read the code, docs and history.")
        case .stopped:
            return SetupStep(
                title: "Read the project", state: hasSession ? .stopped : .pending,
                detail: hasSession ? "The session ended before the notebook was written." : nil)
        }
    }

    private var approveStep: SetupStep {
        let (state, plan): (SetupStep.State, Bool) =
            switch phase {
            case .planReady: (.waiting, true)
            case .writing: (.done, false)
            case .reading, .stopped: (.pending, false)
            }
        return SetupStep(
            title: "Approve the plan", you: true, state: state,
            detail: plan
                ? nil
                : state == .done
                    ? "Approved."
                    : "You read the plan it drafts — what you will have and what waits on you — and approve it.",
            content: plan ? .plan(planTitle ?? "The plan") : .none, review: reviewPlan)
    }

    private var writeStep: SetupStep {
        let title = reviewsPlan ? "Write the notebook" : "Write the roadmap"
        guard phase == .writing else {
            return SetupStep(
                title: title, state: .pending,
                detail: reviewsPlan
                    ? "Roadmap, milestones, tasks and memory, as the plan you approve has them."
                    : "The roadmap, from what the code says. Milestones and tasks come later, from Product.")
        }
        let latest = waiting ? nil : live
        return SetupStep(
            title: title, state: held, detail: waiting ? paused : nil,
            content: reviewsPlan ? .counts(counts, latest) : .live(latest))
    }

    private var counts: [(String, Int)] {
        [
            ("Roadmap", cards.filter { $0.kind == .roadmap }.count),
            ("Milestones", cards.filter { $0.kind == .project }.count),
            ("Tasks", cards.filter { $0.kind == .task }.count),
            ("Memory", cards.filter { $0.kind == .memory }.count),
        ]
    }

    // MARK: - Footer

    private var footer: some View {
        HStack(spacing: 10) {
            Text(footnote).font(Typography.caption).foregroundStyle(Theme.tx3)
            Spacer(minLength: 8)
            if hasSession && !waiting {
                Button(phase == .stopped ? "Open last session" : "Open session", action: openSession)
                    .buttonStyle(.consoleGhost)
            }
            if phase == .stopped {
                Button("Run Notebook Setup", action: rerun).buttonStyle(.consolePrimary)
            }
        }
        .padding(.horizontal, 26).padding(.vertical, 14)
    }

    private var footnote: String {
        guard !waiting else { return "" }
        switch phase {
        case .reading: return "You can leave this page — the sidebar shows when it needs you."
        case .writing: return "The session closes by itself when it is done."
        case .planReady, .stopped: return ""
        }
    }
}

/// "Notebook written: …", over the board Notebook Setup just filled, until dismissed.
package struct NotebookWrittenBanner: View {
    let cards: [NotebookCard]
    let dismiss: () -> Void

    package init(cards: [NotebookCard], dismiss: @escaping () -> Void) {
        self.cards = cards
        self.dismiss = dismiss
    }

    package var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.green)
            Text(Self.summary(of: cards)).font(Typography.body).foregroundStyle(Theme.tx).lineLimit(1)
            Spacer(minLength: 12)
            Button("Dismiss", action: dismiss).buttonStyle(.consoleGhost)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(RoundedRectangle(cornerRadius: 11).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(Theme.green.opacity(0.35), lineWidth: 1))
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .padding(.bottom, 2)
        .background(Theme.bg)
    }

    /// "Notebook written: a roadmap entry, 3 milestones, 8 tasks and 2 memory entries."
    static func summary(of cards: [NotebookCard]) -> String {
        let parts = [
            (EntryKind.roadmap, "roadmap entry", "roadmap entries"), (.project, "milestone", "milestones"),
            (.task, "task", "tasks"), (.memory, "memory entry", "memory entries"),
        ].compactMap { kind, one, many -> String? in
            let count = cards.filter { $0.kind == kind }.count
            return count == 0 ? nil : count == 1 ? "a \(one)" : "\(count) \(many)"
        }
        guard let last = parts.last else { return "Notebook written." }
        let list = parts.count == 1 ? last : parts.dropLast().joined(separator: ", ") + " and " + last
        return "Notebook written: \(list)."
    }
}
