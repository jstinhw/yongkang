This is the spec the app writes into every notebook as `.notebook/NOTEBOOK.md`.

# Notebook

Plain files. One entry = one Markdown file with YAML frontmatter. No database,
no index to keep in sync — the folder tree is the index, so any agent or human
with filesystem access can read and write it.

This notebook belongs to the project folder holding it: it lives at
`<project>/.notebook/`, and the agents working on it run in `<project>`.

## Layout

Paths are relative to the project folder. Everything the notebook owns lives
under `.notebook/` — never write these at the project root.

    .notebook/roadmap/<id>.md             goals and bets — the why
    .notebook/projects/<id>/project.md    one project — the what
    .notebook/projects/<id>/memory/*.md   that project's memory: decisions, context
    .notebook/tasks/<id>.md               shippable units of work — the how
    .notebook/runs/<timestamp>-<id>.md    one agent-team session — the handoff

Memory sits inside its project on purpose: it is archived, moved and handed off
with the project, and one file per fact means several agents can write memory at
once without touching the same file.

## Frontmatter

    ---
    id: <slug>          stable, never changes — the filename may, this may not
    kind: roadmap | project | task | memory | run
    title: "<a few words>"   what it is, short enough to scan in a list — not
                        a sentence; the brief is the body's first paragraph
    status: todo | designing | active | blocked | done   (state pages only)
    depends_on: []      ids that must land first (state pages only)
    designer: <name>    tasks only — this task is design work, and this is who does
                        it. Product writes design as its own task; the engineering
                        tasks on that screen name it in depends_on, and the user
                        approving its demo is what finishes it. Empty on everything
                        else; never inferred from the title or the repo.
    repos: []           projects only — folders the work lands in, relative to the
                        project folder: [.] for the folder itself, [web, api] for two
    roadmap: <id>       projects only
    project: <id>       tasks, memory and project-scoped runs
    subject: <id>       memory and runs — the entry this record explains
    memory_type: decision | fact | constraint | assumption | note
    source: user | agent | code | external
    supersedes: []      memory ids made stale by this memory
    result: succeeded | partial | blocked | failed | cancelled   (runs only)
    agent: ""           runs only
    started: RFC-3339   runs only
    ended: RFC-3339     runs only
    owner: ""           free text — the format fixes no roles
    created: YYYY-MM-DD
    updated: YYYY-MM-DD
    external: {}        mirrors elsewhere, e.g. notion: <page-id>
    ---

Unknown keys are preserved, never dropped. Add what a project needs.

## Body

CommonMark. The first body paragraph is a one-to-three-sentence brief for a human;
details follow under `##` headings. Omit empty sections. Tasks use `- [ ]`
checkboxes for acceptance criteria. Cross-link entries with `[[id]]`.

State pages (roadmap, project and task) are mutable current truth. Do not append
dated work logs to them. Roadmaps normally use Goal, Success, Context,
Requirements, Projects and Not doing; projects use Outcome, Done when, Context,
Approach, Tasks and Decisions; tasks use Done when, Context and Constraints.

## Dependencies

`depends_on` holds ids and crosses kinds freely: a task may depend on another
task, a project on another project. Nothing enforces acyclicity — that is the
author's problem.

## Repos

A project's `repos` are the folders its work lands in: one for an app that is its
own folder, several when a web app and the service behind it are separate. Fill it
in — it is what says which code a project touches before anyone opens it, and the
board starts each folder the way the folder itself says to (a compose file, an npm
`dev` script, Cargo, go, a Makefile `dev` target).

A repo holding more than one app is a monorepo, not one blob to start with a single
command: put each independently-runnable app under its own folder in `apps/` (or
`services/`), each with its own start command, so a web frontend and the API behind
it come up and get reviewed separately. A compose file naming its services works too —
either way, each app is found and started on its own, not lumped into whatever one
command the repo root happens to have.

## Memory

One durable fact, decision, constraint or assumption per file, named
`YYYY-MM-DD-<slug>.md`. Append; do not rewrite history. Point `subject` at the
entry it explains. Supersede stale memory with a new entry whose `supersedes`
names the old id. Runs are history, not canonical truth: promote anything the next
agent must rely on into durable memory.

## Runs

Ordinary sessions append one handoff record with an RFC-3339 timestamp in the
filename and frontmatter, then a brief and Handoff, Completed, Verification,
Changed and Learned sections as applicable. A session assigned tasks keeps one
`<session-id>-work-<work-id>.md` report per attempt at a task, `kind: run`, where
the work id is the task id with `-2`, `-3` for a later attempt. Its flat frontmatter
names the `session`, `task`, `work_id`, `title`, `status`, the `paths` it changed,
a one-line `report`, `started_at` and `finished_at`; its body is `## Result`,
`## Verification` and `## Review` — a JSON block the review page is drawn from: a
one-sentence summary, a confidence, the checks run, the places a person should read,
questions and concerns — and `## Change request` quotes what the user sent back. Work
states running/blocked/done/failed are separate from task states. These records
stay out of notebook navigation and appear on the session's result and in Review.
Keep raw transcripts outside the notebook. Never store secrets, environment
values or machine-local transcript paths.

## Third-party notebooks (Notion et al.)

The layout maps 1:1 onto a Notion workspace, so an exporter stays a pure
function over these files:

| here                                   | Notion             |
|----------------------------------------|--------------------|
| folder (`roadmap/`, `projects/`, `tasks/`, `runs/`) | database |
| `.md` file                             | page in that database |
| frontmatter key                        | page property      |
| `depends_on`, `roadmap`, `project`, `subject` | relation property |
| body                                   | page content blocks |
| `external.notion`                      | page id, so sync is idempotent |

What keeps that true, and must stay true: ids are stable and slug-shaped, dates
are ISO-8601, `kind`/`status` are closed enums (Notion selects), relations are
YAML arrays of ids, and bodies are portable CommonMark — no raw HTML, no
machine-local paths.
