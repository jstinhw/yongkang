---
kind: run
session: 5ecd3f5d-da6a-4601-aca5-f5997d38df0b
task: ask-other-projects-prompts
work_id: ask-other-projects-prompts
title: "Agents ask other projects"
status: done
paths: [Sources/YongkangCore/Prompts/NotebookPrompts.swift, Sources/YongkangUI/Model/ProjectModel+Product.swift, Sources/YongkangUI/Model/ProjectModel+Assign.swift, Sources/YongkangUI/App/RootView.swift, Tests/YongkangCoreTests/AgentCommandTests.swift, Skills/product/SKILL.md, docs/guide/product.md, docs/guide/projects.md, .notebook/tasks/ask-other-projects-prompts.md, .notebook/projects/cross-project-requests/memory/2026-10-06-incoming-message-prompt.md]
report: "Reading note says how to ask; incomingMessage(from:session:title:body:) builds the delivered text; Product has an asked mode."
started_at: 2026-10-06T11:11:41Z
finished_at: 2026-10-06T11:19:00Z
---

## Result

- `NotebookFormat.readingNote(_:sessionID:)` still says change nothing in the folders it lists,
  and now says how to ask: a `.notebook/messages/<slug>.md` in this project, in the message
  memory's shape with `session` filled in and `reply_to: ""`, then carry on with what does not
  need the answer. The folders are now listed relative to the project, which is what `to` names.
- Product gets it too: `productPrompt(..., reading:)` puts the note in its arguments, and
  `startProduct` passes the tagged projects to a new Product and to one already running.
  Assigned sessions get it through `workPrompt` as before; a free-prompt session from New Agent
  now mints its id up front so its note can carry it.
- New: `NotebookFormat.incomingMessage(from:session:title:body:)` — `from` is the sender's
  folder relative to the receiver's, `session` the sender's id. Returns the text to type in:
  who sent it, the body, "change nothing in" that folder, and the answer's frontmatter with
  `to` and `reply_to` filled in.
- `Skills/product/SKILL.md`: Describing step 3 messages a tagged project that needs a change and
  fits this project's tasks around the answer, naming the other side's tasks in Context. New
  mode `asked` ("Asked by Another Project"): files the part on this board via Describing's steps
  2, 5 and 6, puts questions to the asking session as a message, and answers with what landed and
  what the asker can rely on. The other modes are untouched.
- `docs/guide/product.md` says what happens when a request tags a project whose part changes;
  `docs/guide/projects.md` says a New Agent session with other folders asks the same way.
- Memory `incoming-message-prompt` tells [[deliver-project-messages]] the function and how to
  call it: a first message is `startProduct("asked\n" + incomingMessage(...), ...)`, a reply is
  typed as is.

No screen changed: prompt text, a skill and docs. No shots rendered.

## Verification

    $ swift test --filter AgentCommandTests
    ✔ Test anIncomingMessageSaysHowToAnswerIt() passed
    ✔ Test anAgentHandedAnotherProjectAsksItForAChange() passed
    ✔ Test aWorkPromptSaysWhatElseItMayReadAndNotChange() passed
    ✔ Suite AgentCommandTests passed — 14 tests

    $ make check; echo $?
    swift format lint --strict -r Sources Tests
    swift build
    ━ Test run with 405 tests in 60 suites passed with 12 known issues.
    0

The 12 known issues are the existing `withKnownIssue` records (NotebookIndex, Usage, Skills),
none from this change. The rendered note and message were printed once from a throwaway test
and read through.
