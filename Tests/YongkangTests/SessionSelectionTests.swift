import Foundation
import Testing
@testable import Yongkang

// A session is several selections, not one: its own transcript by default, a lead's
// lanes, and the live terminal under the tag its PTY is already mounted on.
@Suite struct SessionSelectionTests {
    @Test func claudePickerRowMatchesOnlyItsOwnIdentity() throws {
        let picker = "Background\n❯ task-a-frontend (running)\n  task-b-qa (running)\nEnter to view · Esc to close"
        let pickerRow = try #require(ChildAgentPicker.selectedRow(in: picker, agent: .claude))
        #expect(ChildAgentPicker.matches(pickerRow, identities: ["task-a-frontend"]))
        #expect(!ChildAgentPicker.matches(pickerRow, identities: ["task-a", "task-b-qa"]))
    }

    @Test(arguments: [
        ("❯ Explain background agents", AgentKind.claude, nil),
        ("Select agent\n› child-123\nEnter to select", AgentKind.codex, "› child-123"),
    ] as [(String, AgentKind, String?)])
    func selectedRowOnlyInsideAPicker(screen: String, agent: AgentKind, row: String?) {
        #expect(ChildAgentPicker.selectedRow(in: screen, agent: agent) == row)
    }

    @Test func paneFollowsTheSelectionTag() {
        let paneSession = UUID()
        #expect(AgentPane.of(Tag.transcript(paneSession), session: paneSession) == .transcript,
                "an agent row lands on its transcript, the way a subagent row does")
        #expect(AgentPane.of(Tag.lanes(paneSession), session: paneSession) == .lanes)
        #expect(AgentPane.of(paneSession.uuidString, session: paneSession) == .session,
                "the session stays reachable for anyone who wants to type at it")
        #expect(AgentPane.of(Tag.transcript(UUID()), session: paneSession) == nil,
                "another session's tag is not this one's pane")
    }

    @Test func onlyALeadHasLanes() {
        #expect(AgentPane.cases(lead: true) == [.lanes, .session]
                && AgentPane.cases(lead: false) == [.session],
                "Transcript is hidden; only a lead has specialist lanes")
    }
}
