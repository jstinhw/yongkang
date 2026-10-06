---
kind: run
session: 8e971f0a-6851-4104-b030-2ec325329115
task: cross-project-request-ui
work_id: cross-project-request-ui
title: "Show who is talking"
status: done
paths: [Sources/YongkangCore/Project/AgentRow.swift, Sources/YongkangCore/Project/Project.swift, Sources/YongkangUI/Model/ProjectModel.swift, Sources/YongkangUI/Model/ProjectModel+Request.swift, Sources/YongkangUI/Model/ProjectModel+Messages.swift, Sources/YongkangUI/Features/Board/RequestBanner.swift, Sources/YongkangUI/Features/Agents/AgentPage.swift, Sources/YongkangUI/Features/Agents/AgentRow+Style.swift, Sources/YongkangUI/DesignSystem/NotebookStyle.swift, Sources/YongkangUI/App/ProjectSidebar.swift, Sources/YongkangUI/App/RootView+Screen.swift, Sources/Shots/DesignShots.swift, Sources/Shots/RequestShots.swift, Tests/YongkangUITests/MessageDeliveryTests.swift, docs/development.md, docs/architecture.md, .notebook/tasks/cross-project-request-ui.md, .notebook/projects/cross-project-requests/memory/2026-10-06-who-asked-and-who-waits.md, .notebook/runs/8e971f0a-6851-4104-b030-2ec325329115-work-cross-project-request-ui.md, .notebook/pages/8e971f0a-6851-4104-b030-2ec325329115.html]
report: "The banner, the session rows and the session header name the other project, as the approved demo shows; make check passes."
started_at: 2026-10-06T12:30:00Z
finished_at: 2026-10-06T13:03:00Z
---

## Result

Every surface in the approved demo (https://claude.ai/artifact/CUC1Ld7B2cxZc3nFTrhCi3) is built:

- **Asking board, waiting** (frame 2): the request banner reads "Product is waiting on
  **notebook-sync**’s answer · asked “<message title>”" (the title dimmed), with only Open
  session. Approve and commit stays off until the answer is in (`requestFinished` is false while
  `requestWaitsOn` is set).
- **Session rows** (frame 3): the asking Product reads "waiting on **notebook-sync**" with the
  working ring. Its turn is over, but it no longer reads as "your turn" or counts as needing you.
  The asked Product reads "asked by **yongkang-site**".
- **Session header** (frame 3): the same as a chip beside the project's, "↳ asked by
  **yongkang-site**" (or "waiting on …").
- **Asked board** (frame 4): "Product filed **yongkang-site**’s request as a task." with Open
  session, Ask for changes and Approve and commit.
- **Asking board, answered** (frame 5): "Product filed your request as a task;
  **notebook-sync** filed its own part."

How it works:

- `BoardRequest.asked` records what the request's own Product asked another project: its folder
  and the message's title. `ProjectModel.deliveries` sets it, and it stays after the answer.
- `ProjectModel.peers` turns `waitingOn`, `request.from` and `request.asked` into a `Peer`
  (`.waitingOn(name)` or `.askedBy(name)`) for each session. `Project.peers` carries it into
  Core, and `AgentRow.peer` carries it to the sidebar and the header.
- The asked Product stays `askedBy` after it answers, even though `waitingOn` then holds it,
  because its answer isn't a question it waits on. Without that, its row would hide the plan
  waiting for your approval.

Shots, before and after (`swift run shots`): 35 of the 36 existing shots are byte-identical. The
other is `review.png`, which reads live git. Nothing that already existed changed on screen. Four shots
are new: `board-waiting`, `session-asked`, `board-asked` and `board-answered`. Each matches its
demo frame's wording and layout.

The smoke script in `docs/development.md` gains step 18, "A request across two projects".
`docs/architecture.md` says how the screens read who is talking. The memory
`who-asked-and-who-waits` records `asked`, `peers` and the two rules.

Not built: the header's status word for a waiting Product still reads "working", because the
demo never drew that header. Who is talking is still forgotten on a relaunch, as the memory
already says.

## Verification

    $ swift run shots <scratch>/before   # before any edit
    $ swift run shots <scratch>/after
    NEW board-answered.png  NEW board-asked.png  NEW board-waiting.png  NEW session-asked.png
    DIFF review.png        # live git, differs on every commit
    # looked at all four: text, bold names and buttons as in the demo frames

    $ swift test --filter "MessageDeliveryTests|AgentRowStyleTests|AgentRowTests|RequestTests"
    ✔ eachSideSaysWhoItIsTalkingTo()  ✔ theBannerNamesTheOtherProjectInBold()
    ✔ Test run with 26 tests in 4 suites passed

    # mutation checks, each restored afterwards
    drop `&& requestWaitsOn == nil`    → ✘ eachSideSaysWhoItIsTalkingTo: !site.requestFinished
    drop the waiting → working rule    → ✘ eachSideSaysWhoItIsTalkingTo: waiting.state == .working

    $ make check; echo $?
    swift format lint --strict -r Sources Tests
    swift build
    ━ Test run with 412 tests in 61 suites passed with 12 known issues.
    0

Two timing tests fail now and then under full-suite load. Neither touches this change:

- `ProjectModelTests.aPollThatChangesOneProjectLeavesTheOtherAlone` also fails on a baseline
  copy of this tree without my edits (1 of 12 runs there).
- `TerminalRegistryTests.steeringToAChildTypesThePickerCommandAndWalksToItsRow` is a real-PTY
  test of child navigation. It failed 2 times in 17 full runs here, passes 3 of 3 alone, and
  never failed in 12 baseline runs. The new delivery test adds git processes to the parallel
  load, which is the likely link.

The last 8 full runs and the final `make check` were clean.
