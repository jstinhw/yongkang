import Foundation
import YongkangCore

extension DesignShots {
    /// The `## Review` the fixture's finished task is filed with, as the work prompt asks for it:
    /// a caution-free review with a question, a before and after of a screen, a format and an
    /// error, two spots, a check that could not run and a concern that does not block, so every
    /// part of the page has something in it. The screen's ports are ones nothing listens on, so
    /// its sides photograph as not running, the same on every Mac.
    static let sampleReview = WorkReview.read(
        """
        {
          "summary": "Assigning a task now brings its open blockers into the same batch, in dependency order.",
          "confidence": "high",
          "confidence_why": "Every Done when item has a test; one path needs a real hook.",
          "touches": "Blocker reader",
          "changed": [
            "A block names the task it holds and the session waiting on it",
            "Assigning a task pulls in every unfinished blocker, first",
            "The board and the list count a batch the same way"
          ],
          "checks": [
            {"claim": "Tests pass", "status": "passed", "result": "281 tests, 12 known issues",
             "command": "$ make check\\nTest run with 281 tests passed (12 known issues already recorded)"},
            {"claim": "Blockers join the batch", "status": "passed", "result": "both joined, in order",
             "command": "Assigned a task with two open blockers: both joined the batch in dependency order."},
            {"claim": "A cycle stops", "status": "passed", "result": "cyclic blocker refused",
             "command": "LeadBatchTests/cyclicBlocker passed"},
            {"claim": "Refused commit names its task", "status": "not_run", "result": "needs a refusing hook",
             "command": "Not run: it needs a pre-commit hook that refuses."}
          ],
          "holds": [
            "Nothing is committed or pushed until you approve each task.",
            "A blocker outside the notebook is ignored, never followed."
          ],
          "shows": [
            {"kind": "schema", "title": "A block's frontmatter",
             "before": "kind: block\\nstatus: open\\ntitle: \\"Add the Vercel token\\"",
             "after": "kind: block\\nstatus: open\\ntask: deploy-to-vercel\\nsession: 9b59ccf3\\ntitle: \\"Add the Vercel token\\""},
            {"kind": "error", "title": "Two blockers waiting on each other", "test": "LeadBatchTests/cyclicBlocker",
             "before": "Assigning never returns: the batch expands forever",
             "after": "Refused: deploy-to-vercel and dns wait on each other"},
            {"kind": "ui", "title": "The blocks board", "before": "http://localhost:59322/",
             "after": "http://localhost:59321/", "serve_before": "make serve-board REV=51b0740 PORT=59322",
             "serve_after": "make serve-board PORT=59321", "highlight": [".batch"]}
          ],
          "spots": [
            {"path": "Sources/YongkangCore/Notebook/LeadCoordination.swift", "lines": [88, 104],
             "label": "batch order", "why": "The order blockers join decides what runs first; the tests cover two, not three."},
            {"path": "Sources/YongkangCore/Git/GitClient.swift", "lines": [101, 108],
             "label": "refused commit", "why": "What a refused commit says could not be checked without a hook."}
          ],
          "questions": [
            {"ask": "Pull in blockers from other projects too?", "context": "Today only this notebook's blocks join a batch.",
             "options": ["This notebook only", "Other projects too"], "recommend": 0}
          ],
          "concerns": [
            {"title": "Old blocks name no session", "detail": "Blocks filed before this change show without a waiting agent.",
             "blocks": false}
          ],
          "outside": [],
          "files": [
            {"path": "Sources/YongkangCore/Notebook/LeadCoordination.swift", "why": "Resolves a block's task and session"},
            {"path": "Sources/YongkangCore/Git/GitClient.swift", "why": "Names the task a refused commit held"}
          ],
          "next": "show-agent-tree can list a blocked agent under its batch."
        }
        """)
}
