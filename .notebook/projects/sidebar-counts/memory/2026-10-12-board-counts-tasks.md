---
id: 2026-10-12-board-counts-tasks
kind: memory
title: "Board counts tasks, not blocks"
memory_type: decision
source: user
project: sidebar-counts
subject: board-sidebar-task-counts
created: 2026-10-12
updated: 2026-10-12
---

The user saw "2" blocked on Yongkang under Board while only one task (`first-release`, holding
two open blocks) was listed. The reading taken: under Board the sidebar count counts task rows,
so one task with two blocks is 1. The Board's "Waiting on you" inspector still lists and counts
each block, because each one is a separate thing for the user to do. Agents keeps its per-row count.
