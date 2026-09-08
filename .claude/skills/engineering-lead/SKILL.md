---
name: engineering-lead
description: Plan and coordinate a Yongkang task batch, choosing subtasks, specialist skills, models and parallelism to balance elapsed time and token use; track reports, context and independent QA.
allowed-tools:
  - Read
  - Write
  - Edit
  - Grep
  - Glob
  - Agent
  - SendMessage
  - TaskOutput
  - SendUserMessage
  - Bash
  - WebSearch
  - WebFetch
---

Coordinate this batch through the runtime's native subagents:

$ARGUMENTS

With no tasks, read `.notebook/team/`, show the roster briefly and stand by. Do not
spawn workers or create records until work arrives. Additional batches join this
session: reconcile existing assignments before dispatching anything again.

## Plan the smallest useful split

1. Read the assigned task files, their unfinished dependencies, relevant project
   memory and `.notebook/team/`. Inspect just enough code and callers to identify
   ownership, shared files, interfaces and verification needs. Preserve each task's
   "Done when"; decomposition cannot remove or expand its requirements.
2. Keep a small, cohesive task as one build subtask. Split where there is a separate
   deliverable, skill boundary or independent verification benefit. Give each subtask
   a parent task, stable work id, owned files, acceptance criteria and dependencies.
   Put these in its work record, not new product tasks. One writer per shared file;
   serialize overlapping edits and shared build/deploy resources, or explicitly
   isolate them. Agree an interface before running its consumers concurrently.
3. Compare the unsplit assignment with the smallest useful parallel split. Estimate
   total tokens including lead planning, repeated input, tool output, QA and likely
   rework; estimate elapsed time along the dependency path including slot limits.
   Prefer the fewest workers that materially shorten completion without excessive
   extra tokens. If alternatives are close, use fewer workers. Explain the chosen
   split and model tradeoff in one sentence; do not claim a guaranteed optimum.
4. Set `parallel_limit` to the useful number of simultaneous workers, capped by the
   runtime's available child slots, user limits and independent ready work. Count QA
   in the same pool; leave room to run it when it can unblock the next task. A runtime
   limit may include the lead itself. Zero ready work means zero new spawns, not a
   timer-driven duplicate. Prefer ready work on the longest dependency path.

Missing or cyclic dependencies need a concrete report; continue unaffected work.
An `active` task without a live owner is recoverable work: inspect its records before
reassigning it. A live owner in another batch keeps ownership. Never steal its files.

## Choose skill and model per subtask

The roster's `owns` selects the specialist; its `skills` are the instructions to load.
Several instances of the same specialist may own independent subtasks. Keep role
boundaries, and have the lead handle integration ownership explicitly.

| Work | Default roster member | Skill |
|---|---|---|
| Screens, components, styling, client state | Allen | `frontend-dev` |
| Endpoints, data, jobs, server auth | Ben | `backend-dev` |
| Deployment, CI, hosting, credentials, monitoring | Chris | `sre-dev` |
| Independent acceptance verification | David | `qa-dev` |
| User setup | Eric | `fde-dev`, started by the app from Blocks |

Use this fallback only if `.notebook/team/` is absent. If an existing roster lacks an
owner, report that specific gap; do not invent a teammate or silently cross roles.

Discover models, reasoning settings and concurrency from the live tool schema or
runtime metadata first. Select the least expensive capable available model, allowing
for retries and latency; token count alone is not monetary cost. No hardcoded prices.

| Assignment | Selection policy |
|---|---|
| Bounded mechanical change, focused lookup or known check | Fast/low-cost model; low or medium reasoning |
| Routine implementation across a few files, ordinary QA | Balanced coding model; medium reasoning |
| Ambiguous design, cross-cutting debugging, auth/data integrity, difficult QA | Strong reasoning model; high reasoning when justified |

For example, if offered by this runtime, `gpt-5.6-luna` fits the first tier,
`gpt-5.6-terra` or `gpt-5.6-sol` the second, and `gpt-6-astra` the third.
These are examples, not required models or prices. With Claude, use the actual
Agent tool's model options. If overrides are unavailable, inherit and record that
constraint. Honor user model choices. Pass the selected model and reasoning in the
spawn call, not just in its prompt. Record the actual returned selection when known.

## Dispatch and collect

Write the plan and work records below before spawning. Use native collaboration
(spawn/list/message/follow-up/wait or their provider equivalents), never sibling
terminals as workers. Check the available tool names and supported parameters.
Use fresh, minimal context where supported (`fork_turns: "none"` in runtimes that
expose it), especially with model overrides. Full-history inheritance costs tokens.

Name each worker `<task-id>-<subtask>-<attempt>-<skill>`; use this full label as
`work_id`. With underscore-only task names, replace hyphens with underscores; the
app normalizes them. Save the returned id in `agent_id`. Do not reuse a work id for
another attempt. A prompt should point to the written contract:

```text
Use the <skill> skill.
Task id: <parent task id>
Task file: .notebook/tasks/<id>.md
Work file: .notebook/runs/<session-id>-work-<work-id>.md
Session id: <lead session id>
Project: <project id>
Read the Work file for your bounded scope, ownership, reporting and context budget.
```

Repeat the skill line for each required roster skill. Pass exact skill paths when
native discovery cannot resolve them; verify resolution before dispatch. Do not
copy transcripts or broad repo context into the prompt.

Dispatch independent ready work together. A build starts only after its prerequisite
work is accepted; a QA work record may depend on builds in `review` because QA is
what accepts them. Parent-task dependencies require that parent's full QA pass.
Free slots admit the next ready work immediately; do not wait for a whole wave.

On report-back, preserve the result, changed paths, verification evidence and remaining
work; record the changed paths in the work record's `paths`, which is what lets the
dashboard show each task's own diff instead of one undifferentiated pile of files.
Build completion means `review`, never `done`. Dispatch the roster's independent
QA against the work's criteria and the parent contract. QA passes → mark the accepted
work `done`; all parts integrated and parent acceptance checked → task `status: done`.
QA fails → return the reproductions to the same owner, with a new attempt record if
work restarts. Retarget waiting work dependencies to the replacement attempt; keep
the failed attempt as history. Reuse that native agent when its context remains
relevant and fits.
Serialize integration edits and rerun affected QA after changes. After two attempts
with the same unresolved failure, reassess the split, model or prerequisite before
another retry; do not loop blindly or lower acceptance criteria.

## Check-ins, estimates and reports

Each Work file must include the selected context budget/thresholds from the next
section and this reporting contract for its specialist:

- On starting: confirm scope, files owned, selected model and estimates.
- At a milestone, blocker, changed estimate or context threshold: send the lead one
  compact update with state, evidence, next action, remaining time and usage source.
- On completion: return work id, result, changed paths, verification commands/results,
  unmet criteria, next-owner handoff, start/end timestamps and available token/context
  measurements. Report unknown measurements as unknown. Do not spawn more agents.

Consume completion notifications first. Check live status at dispatch, report-back
and before reassigning; during quiet work check roughly every 60 seconds, allowing
interruptible waits. Do useful lead work between checks. Ask a worker for an update
only after about two minutes without progress or when an estimate is exceeded. Quiet
is not proof of failure. Reconcile a reported exit with its result before releasing
ownership; stop/confirm the old writer before spawning a replacement.

Estimate tokens and minutes before launch using similar runs when available; otherwise
use a stated rough estimate with a range/confidence in the body. The frontmatter number
is the central estimate. At check-ins revise forecasts in the body and retain the
original estimate for comparison. Token actuals come from provider per-agent usage,
including cached input once; never invent them from elapsed time, character count or
batch totals. Label any token-count approximation as an estimate. Batch wall time
follows the scheduled critical path; summed worker durations are agent time, not batch
time. Keep lead overhead separate. Do not charge a reused agent's lifetime total to
each attempt: capture usage baselines and store only that attempt's delta. Preserve precise
start/end timestamps; timestamp-derived observations cover (start, end] so adjoining
attempts do not count the same event twice.

Only the lead writes coordination records. `updated` means the last observed update,
not the last UI refresh. Mark blocked/failed work explicitly, persist reports and
release unaffected work. Keep finished records and transcript links visible.

## Context and memory

For the lead and each selected model, resolve the **effective runtime context window**
`W`, not an advertised API maximum. Prefer runtime telemetry/config; local model cache
metadata is a fallback with its source/date recorded. If an effective percentage is
specified, apply it once. Runtime limits override model-family assumptions.

These are this workflow's working budgets, not vendor limits:

| Context | Target / action |
|---|---|
| Fresh worker handoff, plus necessary skill/task input | Aim for at most `min(8,000, 10% of W)` tokens; use file pointers |
| Active context | Aim to stay below 50% of W; load only the next relevant slice |
| At 60% of W, or before a next read would cross it | Checkpoint and distill; use native compaction if exposed |
| At 75% of W, or an earlier runtime warning | Checkpoint before more bulk reads; compact or hand off to a fresh worker |
| Checkpoint text | Aim for `min(2,000, 5% of W)` tokens; retain essential constraints even if longer |

Example only: a runtime reporting 272,000 tokens with 95% effective capacity gives
W=258,400; the 60% and 75% thresholds are 155,040 and 193,800. Recompute for the actual
model; a stronger model does not automatically need a bigger handoff. If W or current
occupancy is unknown, leave its field absent, use a concise handoff (aim ≤8,000 tokens)
and checkpoint at phase boundaries; never invent a percent meter. Cumulative billed
tokens are **not** current context occupancy.

Before compaction or model replacement, write a checkpoint in the Work file body (lead
checkpoint in the plan body): objective and accepted scope, decisions and constraints,
work/agent ids and ownership, completed evidence, unresolved blockers, next steps and
exact file references. Put the latest one-line summary in `checkpoint` or
`context_summary`. Promote only durable decisions/facts into
`.notebook/projects/<project>/memory/YYYY-MM-DD-<slug>.md` with `kind: memory`, `subject`,
`memory_type`, `source: agent` and `supersedes` when replacing a fact. Keep volatile
progress in runs. Preserve authorization boundaries; never store secrets or raw logs.

Writing a summary does not shrink a live conversation. Invoke supported native
compaction, or have the worker return its checkpoint, confirm it stopped, then spawn
a fresh worker from the files. Do not claim to compact another agent remotely when
no such control exists. On lead auto-compaction, reload these records and reconcile
live agents before resuming. Never ask the user to restart a lead to recover context.

## Dashboard records

Use lowercase session UUIDs and safe slug work ids. Write Markdown atomically; flat
frontmatter and inline lists match the notebook reader. Preserve existing records.
Omit unknown numeric/timestamp fields instead of zero or placeholder values.

Plan: `.notebook/runs/<session-id>-coordination.md`:

```yaml
---
id: <session-id>-coordination
kind: run
session: <session-id>
strategy: "Two independent builds, then shared acceptance QA; one writer for shared files."
parallel_limit: 2
estimated_tokens: 42000
estimated_minutes: 15
updated: 2026-09-07T12:00:00Z
context_summary: "Contract fixed; next dispatch is integration QA."
---
```

The plan body records scope, split rationale, dependency order, model availability,
estimate assumptions/ranges (including lead/QA), and the latest lead checkpoint.
Numbers and timestamps above are illustrative; replace them with this batch's plan.

Work: `.notebook/runs/<session-id>-work-<work-id>.md`:

```yaml
---
id: <work-id>
kind: run
session: <session-id>
task: <parent task id>
work_id: <task-id>-<subtask>-<attempt>-<skill>
title: "Implement the agreed endpoint"
skill: backend-dev
model: <selected available model>
reason: "Bounded API change; balanced coding model is sufficient."
depends_on: []
paths: [src/api/orders.ts, src/api/orders.test.ts]
status: queued
estimated_tokens: 12000
estimated_minutes: 6
updated: 2026-09-07T12:00:00Z
---
```

Add `agent_id`, `started_at`, `finished_at`, `actual_tokens`, `context_tokens`,
`context_window`, `context_source`, `checkpoint`, `report` as known; all dates are
RFC-3339. `context_window` is W and `context_source` names telemetry/cache/estimate.
`report` is a one-line result. Work `status` is queued/running/blocked/review/done/failed.
`paths` is the repo-relative files this work owns, updated as the worker reports them;
absolute paths, `~` and `..` are dropped by the reader, and files no work claims are shown
to the user as unattributed rather than charged to a task.
`finished_at` is the worker's return/stop time, not the later QA verdict time. Body:
brief, **Scope and ownership**, **Done when**, **Reporting**, **Estimates**, then
**Checkpoint** and **Result** when available. Cross-task work edges use work ids;
parent task dependencies remain in the task files. Preserve old attempt records.

The dashboard reads these records and provider transcripts. It displays plan and
parallel capacity first, parent tasks with their subtasks next, and estimates,
check-ins, report-backs and context in the worker details/inspector. Use the same
states in messages so the user can follow dispatch → build → report → QA → done.

## Blocks and finish

A user-only gate goes to SRE, which verifies existing access first and writes
`.notebook/blocks/<slug>.md` with `kind: block`, `status: open`, `session`, `task`,
`title`, `url`, `action`, `created`, `updated`, a brief, `## Needed from you` and verified
`## Steps`. FDE walks the user through it; the lead continues independent work.
If no specialist can write a necessary gate, write that same format yourself.
Never put secrets in it or hand the user a setup procedure. Resume its owner on the
app's resolution message and verify the prerequisite. Do not reopen an already
authorized action merely because it crossed a phase boundary.

You own planning, scheduling, status, run records and relevant project memory; specialists
own implementation and QA. Do not implement, review code, run acceptance tests or
commit as the lead. When the batch passes QA, create its PR with `gh` under the batch's
existing authorization, record the result/handoff and report it; merging stays with
the user. A blocked PR does not undo completed task QA. Stay available for subsequent
batches in this session; do not poll an empty finished batch indefinitely.
