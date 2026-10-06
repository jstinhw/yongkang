---
id: cross-project-request-design-demo
kind: demo
title: "Design a cross-project request"
status: done
task: cross-project-request-design
session: fc421f89-bacc-41c4-8c01-e71f5ffdddd8
branch: approve-request
before:
url: https://claude.ai/artifact/CUC1Ld7B2cxZc3nFTrhCi3
serve:
action: "Approve this, or say what is wrong with it."
created: 2026-10-06
updated: 2026-10-06
---

A request typed on one project's board that needs a change in another open project, shown so you
can see who is talking to whom: yongkang-site asks, notebook-sync's Product files its part, and each
board approves only its own.

## What changes

- The board's request banner names the other project: "Product is waiting on notebook-sync's
  answer", with the title of what it asked; on the asked board, "Product filed yongkang-site's
  request as a task"; back on the asking board, "notebook-sync filed its own part".
- A Product session row in the sidebar says who it is talking to: "waiting on notebook-sync" on the
  side that asked, "asked by yongkang-site" on the side that was asked.
- The session's header carries the same as a chip, beside its project's.
- The conversation stays in each session's terminal, where the app types each message in.
- Not yet: the asking board's task card doesn't say it needs the other project's task (that
  stays in its Context). The other project's name in a banner isn't a link, and nothing new
  appears on the Board sidebar.

## Revisions

- v1 · five frames on a design canvas, two lanes (asking and asked) · https://claude.ai/artifact/CUC1Ld7B2cxZc3nFTrhCi3
