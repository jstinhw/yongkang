---
kind: run
session: fc421f89-bacc-41c4-8c01-e71f5ffdddd8
task: cross-project-request-design
work_id: cross-project-request-design-2
title: "Design a cross-project request"
status: done
paths: [.notebook/tasks/cross-project-request-design.md, .notebook/blocks/cross-project-request-design-demo.md, .notebook/runs/fc421f89-bacc-41c4-8c01-e71f5ffdddd8-work-cross-project-request-design-2.md, .notebook/pages/fc421f89-bacc-41c4-8c01-e71f5ffdddd8.html]
report: "Five-frame demo on a design canvas; approved."
started_at: 2026-10-06T12:02:42Z
finished_at: 2026-10-06T12:11:51Z
---

## Result

The demo is a design canvas: https://claude.ai/artifact/CUC1Ld7B2cxZc3nFTrhCi3. It has five 1440×900
frames in two lanes, the asking project on top and the asked one below:

1. yongkang-site's board with a request typed in the request box that tags `@/notebook-sync`.
2. yongkang-site's board while it waits. The banner reads "Product is waiting on notebook-sync's
   answer · asked “Last sync time for the download page”", with Open session.
3. Agents, with notebook-sync's Product session open. Its row says "asked by yongkang-site",
   yongkang-site's Product row says "waiting on notebook-sync", the header has an "asked by
   yongkang-site" chip, and the terminal shows the message the app typed in and the agent's reply.
4. notebook-sync's board with `expose-last-sync` marked new. The banner reads "Product filed
   yongkang-site's request as a task", with Open session, Ask for changes and Approve and commit.
5. yongkang-site's board once the answer is back, with `download-last-sync` marked new. The banner
   reads "Product filed your request as a task; notebook-sync filed its own part", with the same
   three actions.

What's new is the other project's name, in the request banner, the session row's second line and
the session header. There are no new screens. The demo file is
`.notebook/blocks/cross-project-request-design-demo.md`. The task is `status: designing` with its
every Done when item ticked: you approved v1 on 2026-10-06, and the task is `done`.

It leaves out three things on purpose. The asking task's card doesn't say it needs notebook-sync's
task: that stays in its Context, per the depends-on-stays-in-one-notebook memory. The other
project's name in a banner isn't a link. The Board sidebar doesn't change.

## Verification

- `swift run shots <scratch>/before` rendered the current screens (board-filed, board-request,
  session-request, session). The frames copy their tokens, sizes and components from those shots and
  from Theme.swift, Typography.swift, RequestBanner.swift and ProjectSidebar.swift.
- I rendered each frame offscreen with headless Chrome at 1440×900 and looked at it. Nothing was
  clipped or truncated, and each banner's text fits beside its buttons.
- I published each frame to the canvas, and the last publish lists all six files.
- No code changed, so I didn't run `make check`.
