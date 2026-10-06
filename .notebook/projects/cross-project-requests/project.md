---
id: cross-project-requests
kind: project
title: "Requests across projects"
status: todo
depends_on: []
repos: [.]
roadmap: agent-team-console
owner: ""
created: 2026-10-01
updated: 2026-10-01
external: {}
---

A request that needs a change in another open project gets that change by talking to it, not by
writing into its folder. The agent here writes a message, the app opens a session in the other
project and types it in, and that project files its own part on its own board, where its own
Approve and commit lands it.

## Outcome

Someone types a request on one project's board that tags another open project. A Product session
opens under each project in the sidebar, and the two talk through their terminals: this project's
Product says what it needs, the other project's Product files that part on its own board and
answers, and each board approves and commits only its own files. No agent ever writes a file in a
project it was not started in.

## Done when

- [ ] A request on project A that needs a change in open project B opens a Product session
      under B, and B's board shows what it filed, marked new, with Approve and commit.
- [ ] Every message between the two is typed into the other session's terminal, where the user
      can read it, and the answer comes back into the session that asked.
- [ ] Approving on A commits A's files only; B's part is approved and committed on B's board.
- [ ] An agent handed another project's folder — Product or an assigned session — is told to
      ask that project for a change rather than make it.
- [ ] Each side shows who it is talking to, as the approved demo has it.
- [ ] `make check` passes, and the UI task rendered shots before and after.

## Approach

A message is a file the sending agent writes in its own notebook, `.notebook/messages/`, naming
the other project's folder and, for a reply, the session it answers. Like `blocks/`, the folder
is a channel to the app rather than notebook content, so the `.notebook/` format contract does
not change. The app delivers each message the way it already delivers an unblocked block: typed
into a session's terminal. A first message goes to the other project's Product — the one product
voice per project — which treats it as a request on its board.

## Tasks

1. [[cross-project-request-design]] — how a request crossing two projects looks (Allen).
2. [[read-project-messages]] — Core reads the messages an agent writes.
3. [[ask-other-projects-prompts]] — agents are told to ask, and how to answer.
4. [[deliver-project-messages]] — the app types each message into the right session.
5. [[cross-project-request-ui]] — the designed surfaces, built.

Tasks 1, 2 and 3 can start at once.

## Decisions

- The other project files its part on its own board; nothing is written across folders.
  See memory.
- The session in the other project opens on the first message, not on every tag.
- A task here that needs the other project's part names its task in Context; `depends_on`
  does not cross notebooks.
- The message file's shape is fixed in memory so the reading and prompt tasks can run at once.
