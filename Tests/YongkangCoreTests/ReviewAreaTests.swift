import Foundation
import Testing

@testable import YongkangCore

/// A file's area is worked out, not declared, and the message that sends a task back
/// opens with the words the lead skill listens for.
@Suite struct ReviewAreaTests {

    @Test(arguments: [
        ("db/migrations/0003_groups.sql", ReviewArea.database, ""),
        ("prisma/schema.prisma", .database, ""),
        ("app/actions.ts", .api, ""),
        ("src/api/orders.ts", .api, ""),
        ("app/rename-task-group-form.tsx", .frontend, ""),
        ("app/task-list.test.ts", .tests, "a test is a test before it is frontend"),
        ("Sources/Yongkang/NotebookSelfTest.swift", .tests, ""),
        ("package.json", .config, ""),
        (".github/workflows/ci.yml", .config, ""),
        (".notebook/runs/a-work-b.md", .notebook, ""),
        ("lib/task-groups.ts", .other, ""),
    ])
    func areaFromThePath(path: String, area: ReviewArea, why: String) {
        #expect(ReviewArea.of(path) == area, Comment(rawValue: why))
    }

    @Test func unknownLayoutFallsBackToTheOwningWorker() {
        #expect(
            ReviewArea.of("Sources/Yongkang/App.swift", skill: "frontend-dev") == .frontend,
            "a layout the rules do not know falls back to the worker who owned it")
    }

    @Test func sqlInTheChangeFlagsTheDatabase() {
        let sql = [
            DiffLine(kind: .add, old: "", new: "12", text: "      `update todo_groups"),
            DiffLine(kind: .add, old: "", new: "13", text: "          set title = $1"),
        ]
        #expect(
            ReviewArea.of("lib/task-groups.ts", skill: "backend-dev", diff: sql) == .database,
            "SQL written into the change flags the database even with no migration folder")
        #expect(
            !ReviewArea.touchesSQL([DiffLine(kind: .context, old: "1", new: "1", text: "select * from t")]),
            "only changed lines count, not the context around them")
    }

    @Test func blankNoteIsNothingToSend() {
        #expect(ReviewDraft(note: "   ").isEmpty, "a blank note is nothing to send")
    }

    @Test func changeRequestMessage() {
        let draft = ReviewDraft(
            comments: [
                ReviewComment(
                    path: "app/remove.tsx", line: "27",
                    code: "  {pending}  ", text: "Ask first. ")
            ],
            note: "   ")
        let message = draft.message(taskID: "manage-task-group", title: "Rename or remove a task group")
        #expect(
            message.hasPrefix("Changes requested on manage-task-group"),
            "the lead skill routes on this exact opening")
        #expect(message.contains("- app/remove.tsx:27 — Ask first.\n  > {pending}"))
        #expect(message.contains("Do not commit."))
    }
}
