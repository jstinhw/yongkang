---
id: agent-team-console
kind: roadmap
title: "Agent team console"
status: active
depends_on: []
owner: ""
created: 2026-10-01
updated: 2026-10-01
external: {}
---

Yongkang is a macOS console where one person runs a team of coding-agent CLIs — Claude Code,
Codex, Grok and Agy — in real terminals against each project's `.notebook/`, and approves what
they leave behind before any of it is committed. The next bet is taking it from the author's
own daily tool to an app a first tester can download, install and trust on their own Mac.

## Goal

One window where someone who already works in an agent CLI turns a plan into work for a team of
those CLIs, watches them across every project they have open, is asked only for what only they
can do, and reviews outcomes rather than diffs before anything lands — with the plan kept in
plain files any agent or human can read.

## Success

- A tester on a clean Mac downloads the DMG from the public releases repo, opens it with no
  Gatekeeper prompt, and later takes an update through **Restart to Update** without
  reinstalling.
- From an empty folder or an existing repo, a tester gets a notebook and a board without editing
  a file by hand, and can assign its tasks to whichever supported CLI they have installed; a CLI
  that is missing or not signed in is said, never a silent nothing.
- Every agent's work waits uncommitted in Review and lands only through **Approve and commit**;
  the app never loses or overwrites what an agent wrote, including after a quit or a crash.
- The readers that take agent-written files handle every malformed input the test suite records
  as a known issue, so `make check` passes with no `withKnownIssue` left.
- Nothing about a tester's work leaves their Mac: no path, project or task name, prompt or file
  contents in an analytics event, and no log line sent anywhere.

## Context

**What the code is.** One Swift package: `YongkangCore` (Foundation only — notebook, providers,
git, review, prompts, usage, watching), `YongkangUI` (SwiftUI, AppKit, SwiftTerm — models,
design system, terminal, features, and `Online/`), and `Shots`, a dev-only renderer. `App/` is a
thin Xcode shell that builds `Yongkang.app` (`ai.yongkang.Yongkang`). macOS 14+, Swift 6
language mode, two dependencies (SwiftTerm, Sparkle). `AGENTS.md` (with `CLAUDE.md` linked to
it) is the instruction file; read it, and `docs/architecture.md` before touching reads, the
window, the menus, restoration or terminal lifetime.

**What it already does.** Every open project in one window's sidebar; a dependency-ordered board
over the notebook; Assign splits picked tasks into chains, one CLI session each; a designer gate
before visible work; blocks handed back to the agent that filed them; Product files requests
straight onto the board or reviews the product; Review opens on the task, the agent's own
verification and what changed, with the diff one click away; Usage covers every project's spend
and Claude's and Codex's plan limits; sessions resume after a relaunch.

**Rules an agent must keep.**

- The notebook files are the only state. The app never writes what agents write, and no
  agent commits: sessions holding tasks are refused git commit and push, and work lands only
  when the user approves it in Review.
- The `.notebook/` format is a contract: change `NotebookFormat.specText`,
  `docs/notebook-format.md` and their tests together, or not at all. A format change a user has
  to act on is a major version (`docs/release.md`).
- Only `Sources/YongkangUI/Online/` talks to a server. An analytics event says only that
  something happened, with an agent's kind or a count; a log line holds only paths, counts,
  exit statuses and error descriptions, and never leaves the Mac.
- `make check` is the definition of done. A UI or structural change also renders
  `swift run shots` before and after and says what changed; the toolbar, title and menus only
  show in the running app (`docs/development.md`, smoke script). Never launch or quit the
  user's running copy — it holds their agent sessions.
- A visible change is designed in Claude Code's `/design` canvas before any SwiftUI is written,
  so Product gives it a design task. Every app-wide shortcut is a menu item. No file over 800
  lines; `Tests/YongkangUITests/WorkflowTests.swift` is already over it.

**Where it stands.** The refactor in `docs/refactor-plan.md` (Phases 0–5) has shipped. Phase 6
is built — `make release`, `.github/workflows/release.yml`, Sparkle with its public key in
`App/Config/Info.plist`, `jstinhw/yongkang-releases` as the public host — but no `v*` tag
exists and `CHANGELOG.md` has only Unreleased. The Developer ID certificate and notarization
key are the user's to create (`docs/release.md`, One-time setup). The Supabase and PostHog keys
in `Info.plist` are empty, so sign-in and analytics are off.

**Known gaps the repo records.** Twelve known issues in five `withKnownIssue` blocks
(`docs/refactor-plan.md` §8): eight come from one root cause, `NotebookIndex` parsing
frontmatter line by line while `NotebookFormat.yaml` does not escape what it treats as
structure; `Skills.url` lets a `../` skill name escape the skill folders; `UsageLedger.record`
replaces an unreadable `usage.json`. Agy runs in its live terminal only, with no transcript or
usage read. Plan limits exist for Claude and Codex only. Sessions launch through `zsh -ilc`, so
a bash or fish user's PATH is untested. Review runs `git init` silently in a notebook project
that is not a repo (§9.3). §8's deferred list — settings window, VoiceOver audit, light theme,
localization, multi-window, crash reports, beta channel — each names the tester-driven trigger
that brings it back.

**Calls this import made.**

- One roadmap entry, not one per area: the product's goal plus its next bet. `docs/refactor-plan.md`
  stages the work by audience (D9), every distribution piece is built and waiting on the
  first tester, and most of its deferred work names that tester as the trigger.
- The audience is people who already run Claude Code or Codex in a terminal on a Mac — the
  requirements are those CLIs on PATH, and the guide adopts their habits (a prompt box, plain
  `@` tags, the agent acts) rather than a project tracker's.
- Clearing the recorded known issues is part of success, because testers point the app at
  their own repos and those readers sit on the trust boundary.
- Status `active`: work on the product continues daily; only the release is waiting on a
  person.

## Not doing

- Open-sourcing the code — no license, community files or public CI. The repo stays private;
  only the binaries and the update feed are public.
- A Mac App Store build: the sandbox forbids spawning the user's CLIs and reading `~/.claude`,
  `~/.codex` and `~/.grok`.
- Runtime plugins or dynamically loaded providers: a CLI is one compile-time `AgentProvider`
  folder plus fixtures (`docs/providers.md`).
- State of the app's own — a database, SwiftData, a sync service. The notebook files are the
  store.
- Agents that commit, push, branch or open pull requests on their own.
- Polishing for testers who have not arrived yet: the deferred items in `docs/refactor-plan.md`
  §8 wait for the trigger each one names.
