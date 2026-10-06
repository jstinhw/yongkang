---
id: depends-on-stays-in-one-notebook
kind: memory
title: "Depends on stays in one notebook"
project: cross-project-requests
subject: cross-project-requests
memory_type: decision
source: agent
supersedes: []
created: 2026-10-01
updated: 2026-10-01
external: {}
---

A task that needs another project's part names that project and its task ids in its Context,
from the other Product's answer. `depends_on` stays within one notebook: a qualified id that
crosses notebooks would change the `.notebook/` format contract, which this project does not
take on. Bring it in if testers start one side's task before the other side's part has landed.
