import Foundation
import Testing

@testable import YongkangCore

@Suite struct TranscriptStepsTests {
    // A transcript is mostly tool calls; the viewer keeps the brief and the replies and
    // collapses everything between them into one line, the way Claude Code prints it.
    @Test func toolWorkCollapsesBetweenBriefAndReply() throws {
        let raw = [
            TranscriptLine(label: "Task", text: "Verify the four states"),
            TranscriptLine(label: "Tool", text: "Skill(command: qa-dev, args: )"),
            TranscriptLine(label: "Tool", text: "Grep(pattern: todo)"),
            TranscriptLine(label: "Result", text: "3 matches"),
            TranscriptLine(label: "Tool", text: "Read(file_path: page.tsx)"),
            TranscriptLine(label: "Result", text: "120 lines"),
            TranscriptLine(label: "Tool", text: "Bash(command: pg_ctl start)"),
            TranscriptLine(label: "Result", text: "could not start server", isError: true),
            TranscriptLine(label: "Reply", text: "Local Postgres is up on 55432."),
        ]
        let steps = TranscriptSteps.steps(raw)
        let kinds: [TranscriptStep.Kind] = [.task, .skill, .work, .say]
        try #require(
            steps.map(\.kind) == kinds,
            "a run of tool work collapses into one step between the readable ones")
        #expect(steps[1].text == "Skill(qa-dev)", "a skill keeps its own line, named")
        #expect(steps[2].text == "Searched for 1 pattern, read 1 file, ran 1 shell command")
        #expect(steps[2].errors == 1, "a failed call is counted, not hidden")
        #expect(steps[2].detail.count == 6, "the calls stay behind the summary")
    }

    @Test func skillNameComesFromTheSkillField() {
        #expect(
            TranscriptSteps.skillName("Skill(args: redesign-add-todo-flow, skill: qa-dev)") == "Skill(qa-dev)",
            "the name comes from the field called skill, not from whichever sorts first")
    }

    @Test func nothingToSummarise() {
        #expect(
            TranscriptSteps.steps([TranscriptLine(label: "Result", text: "Launching skill")]).isEmpty,
            "a result with no call in front of it is not a step")
        #expect(TranscriptSteps.steps([]).isEmpty)
    }

    // Invoking a skill pastes the whole skill document back in as a user message. It is
    // the agent's context, not something it did, and the Skill line already said so.
    @Test func skillPastesAndNotificationsAreDropped() throws {
        let noisy = [
            TranscriptLine(label: "Task", text: "Use the qa-dev skill on redesign-todo-states"),
            TranscriptLine(label: "Tool", text: "Skill(skill: qa-dev)"),
            TranscriptLine(
                label: "Task",
                text: "Base directory for this skill: ~/.claude/skills/"
                    + "qa-dev\n\nYou are QA on work that is claiming to be finished…"),
            TranscriptLine(label: "Task", text: "[SYSTEM NOTIFICATION - NOT USER INPUT] a hook ran"),
            TranscriptLine(
                label: "Task",
                text: "The coordinator sent a message while you were "
                    + "working:\nQA failed, take another look at the empty state."),
        ]
        let steps = TranscriptSteps.steps(noisy)
        let kinds: [TranscriptStep.Kind] = [.task, .skill, .note]
        try #require(
            steps.map(\.kind) == kinds,
            "the skill's own text and a system notification are dropped; a message from the lead is not")
        #expect(steps[2].text.hasPrefix("The coordinator sent"))
    }

    @Test func droppedInjectionDoesNotSplitARun() {
        let split = [
            TranscriptLine(label: "Task", text: "brief"),
            TranscriptLine(label: "Tool", text: "Read(file_path: a)"),
            TranscriptLine(label: "Task", text: "Base directory for this skill: x"),
            TranscriptLine(label: "Tool", text: "Read(file_path: b)"),
        ]
        #expect(
            TranscriptSteps.steps(split).map(\.text) == ["brief", "Read 2 files"],
            "a dropped injection does not cut the run around it in two")
        #expect(
            TranscriptSteps.aside("[Request interrupted by user]") != nil,
            "anything unrecognised is shown rather than swallowed")
    }

    // The setup card's one line of progress: the last call, aimed at a path inside the
    // project, and every file read so far.
    @Test func activityNamesTheLastCallFromTheProjectsFolder() {
        let root = URL(fileURLWithPath: "/work/weather")
        let lines = [
            TranscriptLine(label: "Tool", text: "Read(file_path: /work/weather/README.md)"),
            TranscriptLine(label: "Result", text: "# Weather"),
            TranscriptLine(label: "Tool", text: "Grep(glob: *.swift, path: /work/weather, pattern: TODO)"),
            TranscriptLine(label: "Tool", text: "Read(file_path: /work/weather/Sources/Client.swift, limit: 80)"),
        ]
        let activity = AgentActivity(lines: lines, in: root)
        #expect(activity.filesRead == 2)
        #expect(activity.verb == "Read" && activity.target == "Sources/Client.swift")
        #expect(
            AgentActivity(lines: Array(lines.prefix(3)), in: root).target == "TODO",
            "a search is named by what it looks for, not where")
        #expect(AgentActivity(lines: [], in: root) == AgentActivity(), "nothing yet is nothing, not a guess")
    }
}
