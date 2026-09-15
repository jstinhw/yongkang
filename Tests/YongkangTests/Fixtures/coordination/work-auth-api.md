---
kind: run
session: 7C9E6679-7425-40DE-944B-E07FC1F90AE7
work_id: auth-api
task: auth
title: Build API
skill: backend-dev
model: selected-model
reason: Bounded server change.
depends_on: [auth-contract]
paths: [Sources/API.swift, ./Sources/Routes.swift, /etc/passwd, ../outside.swift, "~/secrets"]
status: review
agent_id: runtime-1
estimated_tokens: 4000
estimated_minutes: 3
started_at: 2026-09-07T12:00:00Z
finished_at: 2026-09-07T12:02:00Z
updated: 2026-09-07T12:02:00Z
actual_tokens: 90
context_tokens: 500
context_window: 2000
context_source: runtime
checkpoint: API contract agreed.
report: API ready for QA.
---
Durable details.