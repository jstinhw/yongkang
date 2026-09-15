import Foundation
import Testing

@testable import YongkangCore
@testable import YongkangUI

// A session is several selections, not one: its own transcript, a lead's lanes, and the
// live terminal its PTY is already mounted on.
@Suite struct SessionSelectionTests {
    @Test func claudePickerRowMatchesOnlyItsOwnIdentity() throws {
        let picker = "Background\n❯ task-a-frontend (running)\n  task-b-qa (running)\nEnter to view · Esc to close"
        let claude = try #require(AgentKind.claude.provider.childView)
        let pickerRow = try #require(ChildAgentPicker.selectedRow(in: picker, of: claude))
        #expect(ChildAgentPicker.matches(pickerRow, identities: ["task-a-frontend"]))
        #expect(!ChildAgentPicker.matches(pickerRow, identities: ["task-a", "task-b-qa"]))
    }

    @Test(
        arguments: [
            ("❯ Explain background agents", AgentKind.claude, nil),
            ("Select agent\n› child-123\nEnter to select", AgentKind.codex, "› child-123"),
        ] as [(String, AgentKind, String?)])
    func selectedRowOnlyInsideAPicker(screen: String, agent: AgentKind, row: String?) throws {
        let childView = try #require(agent.provider.childView)
        #expect(ChildAgentPicker.selectedRow(in: screen, of: childView) == row)
    }

    @Test func paneFollowsTheRoute() {
        let paneSession = UUID()
        #expect(
            Route.session(paneSession, pane: .transcript).pane(of: paneSession) == .transcript,
            "an agent row lands on its transcript, the way a subagent row does")
        #expect(Route.session(paneSession, pane: .lanes).pane(of: paneSession) == .lanes)
        #expect(
            Route.session(paneSession).pane(of: paneSession) == .session,
            "the session stays reachable for anyone who wants to type at it")
        #expect(
            Route.session(paneSession) == .session(paneSession, pane: .session),
            "a terminal row and the session pane are one selection, so the terminal shows for both")
        #expect(
            Route.session(UUID(), pane: .transcript).pane(of: paneSession) == nil,
            "another session's route is not this one's pane")
        #expect(
            Route.subagent(session: paneSession, id: "a1").pane(of: paneSession) == nil,
            "a subagent of this session is not one of its panes")
    }

    @Test func onlyALeadHasLanes() {
        #expect(
            AgentPane.cases(lead: true) == [.lanes, .session]
                && AgentPane.cases(lead: false) == [.session],
            "Transcript is hidden; only a lead has specialist lanes")
    }
}
