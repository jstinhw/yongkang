---
id: notebook-stays-public
kind: memory
title: "Notebook stays public"
project: open-source-release
subject: history-audit
memory_type: assumption
source: agent
supersedes: []
created: 2026-10-07
updated: 2026-10-07
external: {}
---

The `.notebook/` folder stays tracked and becomes public with the code: it is the product
using itself, and an example of the format. [[history-audit]] checks it like any other file;
what it holds that should not be public is removed or rewritten, not the folder.
