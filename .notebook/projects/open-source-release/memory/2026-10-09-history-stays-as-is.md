---
id: history-stays-as-is
kind: memory
title: "History stays as is"
project: open-source-release
subject: history-audit
memory_type: decision
source: user
supersedes: []
created: 2026-10-09
updated: 2026-10-09
external: {}
---

The repo goes public with its history unrewritten, and the doc comment on `Mention.extend` in
`PromptField.swift` keeps the three entry names from the user's home folder it has had since
`b524fe8`. They are not an audit finding to fix.

## Why

They are file names only, no contents, and `b524fe8` is already on `origin/main`. Rewriting
would change every later commit hash and force-push `main`, which costs more than the names
reveal; with history keeping them, renaming them in the tree hides nothing. [[go-public]] does
not need to re-ask.
