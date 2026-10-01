import SwiftUI
import YongkangCore
import YongkangUI

extension DesignShots {
    /// The board while Notebook Setup writes the first notebook of an imported folder: reading,
    /// stopped on a question, the plan ready, writing, stopped for good, and the board it leaves.
    @MainActor static func writeSetupShots(_ project: Project, agents: AgentChoice, into directory: URL) {
        let reading = AgentActivity(filesRead: 42, verb: "Read", target: "Sources/Forecast/Client.swift")
        let writing = AgentActivity(filesRead: 61, verb: "Write", target: ".notebook/tasks/expire-stale-entries.md")
        let states: [(NotebookSetupCard.Phase, Bool, AgentActivity?, String)] = [
            (.reading, false, reading, "setup-reading"),
            (.reading, true, reading, "setup-waiting"),
            (.planReady, false, reading, "setup-plan"),
            (.writing, false, writing, "setup-writing"),
            (.stopped, false, nil, "setup-stopped"),
        ]
        for (phase, waiting, activity, name) in states {
            let card = NotebookSetupCard(
                phase: phase, waiting: waiting, agent: "Claude Code", project: "weather-cli",
                planTitle: "Plan for Weather CLI", cards: phase == .writing ? project.cards : [],
                hasSession: true, openSession: {}, reviewPlan: {}, rerun: {}, activity: { nil }, initial: activity)
            write(
                console(project, section: .board) {
                    NotebookBoard(
                        cards: [], blocks: [], assigned: [], reviewing: [], showDone: false, agents: agents,
                        assign: { _, _ in }, review: {}, openCard: { _ in }, openBlock: { _ in },
                        openReview: { _ in }, remove: { _ in }, request: {}, setup: AnyView(card))
                }, name, into: directory)
        }

        // Done: the session has closed, and the board it wrote says what it is.
        write(
            console(project, section: .board) {
                VStack(spacing: 0) {
                    NotebookWrittenBanner(cards: project.cards, dismiss: {})
                    NotebookBoard(
                        cards: project.cards, blocks: project.blocks, assigned: [], reviewing: [], showDone: false,
                        agents: agents, assign: { _, _ in }, review: {}, openCard: { _ in }, openBlock: { _ in },
                        openReview: { _ in }, remove: { _ in }, request: {})
                }
            }, "setup-done", into: directory)
    }
}
