import SwiftUI
import YongkangCore
import YongkangUI

extension DesignShots {
    /// The board while Notebook Setup writes the first notebook: an imported folder reading,
    /// stopped on a question, writing its roadmap and stopped for good; a described project's
    /// plan ready and its notebook being written; and the board it leaves.
    @MainActor static func writeSetupShots(_ project: Project, agents: AgentChoice, into directory: URL) {
        let reading = AgentActivity(filesRead: 42, verb: "Read", target: "Sources/Forecast/Client.swift")
        let writing = AgentActivity(filesRead: 61, verb: "Write", target: ".notebook/tasks/expire-stale-entries.md")
        let roadmap = AgentActivity(filesRead: 61, verb: "Write", target: ".notebook/roadmap/weather-cli.md")
        let states: [(NotebookSetupCard.Phase, Bool, Bool, AgentActivity?, String)] = [
            (.reading, false, false, reading, "setup-reading"),
            (.reading, true, false, reading, "setup-waiting"),
            (.writing, false, false, roadmap, "setup-roadmap"),
            (.stopped, false, false, nil, "setup-stopped"),
            (.planReady, false, true, nil, "setup-plan"),
            (.writing, false, true, writing, "setup-writing"),
        ]
        for (phase, waiting, reviewsPlan, activity, name) in states {
            let card = NotebookSetupCard(
                phase: phase, waiting: waiting, reviewsPlan: reviewsPlan, agent: "Claude Code", project: "weather-cli",
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
