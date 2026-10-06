---
kind: run
session: f5c98211-4492-4f1a-9f6e-71a8f8ed6501
task: deliver-project-messages
work_id: deliver-project-messages
title: "Deliver messages between projects"
status: done
paths: [Sources/YongkangUI/Model/ProjectModel+Messages.swift, Sources/YongkangUI/Model/ProjectModel.swift, Sources/YongkangUI/Model/ProjectModel+Request.swift, Sources/YongkangUI/Model/AppModel.swift, Sources/YongkangUI/App/RootView.swift, Sources/YongkangCore/Prompts/NotebookPrompts.swift, Tests/YongkangUITests/MessageDeliveryTests.swift, docs/architecture.md, AGENTS.md, .notebook/tasks/deliver-project-messages.md, .notebook/projects/cross-project-requests/memory/2026-10-06-who-asked-and-who-waits.md]
report: "The poll types each message into the right session in the other project, once, even after a relaunch, without moving the window; make check passed; no screen changed."
started_at: 2026-10-06T11:52:00Z
finished_at: 2026-10-06T12:13:00Z
---

## Result

- **New `Sources/YongkangUI/Model/ProjectModel+Messages.swift`.**
  `ProjectModel.deliveries(among:skipping:agent:)` routes each message the sender's agents wrote
  that has not been delivered yet. It resolves `to` against the sender's folder and matches it
  to an open project. Then:
  - A `reply_to` naming a session running there is typed into that session as
    `NotebookFormat.incomingMessage(...)`.
  - Any other message goes to that project's Product as `"asked\n" + incomingMessage(...)`,
    through `startProduct`. That either types it into the running Product or starts a new one,
    which can read the sender's folder. The receiving board gets a `BoardRequest` (unless
    Product is already on one), so what it files is marked new and its own Approve and commit
    lands only its own files.
  - A `to` naming no open project is answered in the sender's session in one line, from the
    new `NotebookFormat.undeliveredMessage(to:file:)`. If the sender session is gone too, the
    message waits for a later read.
- **`AppModel.deliverMessages()`** runs on every read, after all projects have been read. It
  only calls `terminals.send`, so the window never moves.
  - `AppModel.deliveredMessages` holds every message already typed in, keyed by
    `ProjectMessage.deliveryKey`: the file path plus a SHA-256 of its fields. A reused slug with
    a new message is delivered again; the same file read again is not.
  - `RootView` keeps that set in `@AppStorage("deliveredMessages")` and restores it before the
    first read of a launch.
- **For [[cross-project-request-ui]]:** `BoardRequest.from` holds the folder of the project
  that asked. `ProjectModel.waitingOn[sessionID]` holds the folder of the project a session
  wrote to and has had no answer from yet. Both are in memory only, and memory
  `who-asked-and-who-waits` says so.
- **Docs:** `docs/architecture.md` has a new section, "How a message travels between
  projects", and `AGENTS.md` lists it.
- **Nothing logs a message's title or body.** The defaults store only paths and hashes.

Not mine: while I worked, another session edited `ProjectModel+Request.swift` (`resumeRequest`
became `async`), `AppModel+Restore.swift`, one line of `AppModel.checkTurn`,
`Tests/YongkangUITests/RequestTests.swift` and `docs/guide/product.md`, and added
`.notebook/blocks/`. In `ProjectModel+Request.swift` I added only the `from` field.

## Verification

    $ swift test --filter MessageDeliveryTests
    ✔ aFirstMessageOpensProductThereAndEachBoardCommitsOnlyItsOwnPart()   (two git repos)
    ✔ aMessageToARunningProductIsTypedIntoItAndKeepsItsRequest()
    ✔ aMessageToNoOpenProjectIsAnsweredInTheSessionThatWroteIt()
    ✔ eachMessageIsTypedInOnceWithoutMovingTheWindowEvenAfterARelaunch()  (real /bin/sh PTYs)
    ✔ Suite MessageDeliveryTests passed — 4 tests

    # mutation check: relaunch test with the stored set not restored
    ✘ ...EvenAfterARelaunch() — typed(into: a.log ...).isEmpty failed   (restored afterwards)

    $ make check; echo $?
    swift format lint --strict -r Sources Tests
    swift build
    ━ Test run with 409 tests in 61 suites passed with 12 known issues.
    0

The 12 known issues are the existing `withKnownIssue` records; I added none.

Shots: HEAD came from `git archive` (no stash, no branch switch) and was rendered with
`swift run shots`, then my tree. 31 of 35 shots are byte-identical. `review`, `handover` and
`usage` read live git or the clock, so they differ on every commit. `agents-blocked.png`
differed in the first render, but a second render of my tree matches HEAD's byte for byte, so
that was render noise. Nothing changed on screen: no view reads the new fields yet.
