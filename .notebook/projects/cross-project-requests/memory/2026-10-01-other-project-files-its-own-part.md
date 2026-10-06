---
id: other-project-files-its-own-part
kind: memory
title: "Other project files its own part"
project: cross-project-requests
subject: cross-project-requests
memory_type: assumption
source: agent
supersedes: []
created: 2026-10-01
updated: 2026-10-01
external: {}
---

"Guide another project to do the change" is read as: the other project's own Product session
files that project's part on its own board, and its own Approve and commit lands it. The asking
project never writes there, and the session in the other project does not edit code outside its
board's flow.

## Why

It keeps each project's Review and commit about its own files, which is how `approveRequest`
and task review already work, and it keeps "the notebook files are the only state" true on both
sides. Having the other project's session change code directly would bypass its board and its
Review.
