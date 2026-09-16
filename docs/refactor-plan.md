# Yongkang refactor

**What this is:** the record of the refactor that gave this repo its present shape — what was
decided, why, what was turned down, and what was deliberately left. It is not a plan any more.
Phases 0–5 have shipped; Phase 6 (distribution) has not started, and is waiting on a trigger
rather than on work.

**Written:** 2026-09-15 as a plan, against `main` @ `69c4bc0`. Rewritten at the end of Phase 5,
because the repo rule for this file is to describe what exists rather than what is planned. The
decisions keep their original reasoning; the numbers in §1 are still the ones measured on
`69c4bc0`, because they are the evidence the decisions were made on.

**Goal it was written to:** make Yongkang a well-organised, fast, polished macOS app that is
cheap to change, for the author and for the coding agents that build it. It stays a **private
project**, and nothing in the refactor makes opening it up later harder.

---

## 0. The short version

Yongkang's product thinking was strong. The problems were one god object, work running on the
main thread, test code shipped inside the app, and a build that could not produce a shareable
`.app`. The refactor kept the behaviour, the `.notebook/` format and the "the app keeps no state
of its own" principle, and changed how the code is organised, built and verified.

**Why "private" didn't shrink it much:** the repo's main contributors are coding agents working
in parallel. Parallel agents need what outside contributors need — small files, one obvious
place for each change, one command to verify, and instructions in the repo. What dropped out was
everything aimed at strangers: license, community files, a marketing README, public release
channels and a launch.

The eight decisions that shaped everything else, and what each became:

1. **Fix the default branch.** `origin/HEAD` points at `main`; the stale `notebooks` branch is
   gone. The README is a short entry point, the design journal is `docs/guide/`, and `AGENTS.md`
   exists.
2. **Move the 1,786-line self-test into Swift Testing *before* touching any code.** It went
   first, and no test code ships in the app any more. The suite is 281 tests in 44 suites, with
   12 recorded known issues (§8).
3. **Split into `YongkangCore` (Foundation only) and `YongkangUI` (SwiftUI), plus a thin Xcode
   app shell.** One module boundary, enforced by the compiler.
4. **Replace `App.swift`'s 20 `@State` vars and string-typed selection with `@Observable` models
   and a typed `Route` enum.** Minimum raised to macOS 14. `App.swift` is gone.
5. **Take process lifetime out of SwiftUI.** `TerminalRegistry` owns the PTYs; views only
   display them.
6. **Move all file, git and transcript I/O off the main thread.** FSEvents drives the refresh,
   with a 30 s safety poll behind it.
7. **Give each agent CLI one `AgentProvider` folder.** Adding Grok and Agy had touched 8 files;
   a CLI is now one folder plus fixtures.
8. **Make it a proper Mac app:** menu bar commands, one set of design tokens, an app icon. The
   signed-and-notarized part is Phase 6 and has no user yet.

---

## 1. What it started from

Every number in this section was measured on `69c4bc0`, before Phase 0. It is kept because it is
the evidence the decisions below were made on, not because it describes the repo now — §1.5 says
what the same measurements say today.

### Repository

| Finding | Evidence | Why it mattered |
|---|---|---|
| GitHub's default branch `notebooks` was **44 commits behind** `main` | `git rev-list --count origin/notebooks..main` | Anything branching from the default (Conductor workspaces, `gh pr create`) started from 44-commit-old code. |
| README was 21 KB and read as a design journal | `README.md` | Excellent material, but costly context for every agent that opened it to find the build command, with no quick "build, run, test, where things are". |
| No `AGENTS.md` or `CLAUDE.md` | repo root | Agents rediscovered the build commands, the test flag and the design rules every session. The `/design`-first rule lived only in local memory. |
| The app's shipped role skills lived in `.claude/skills/`, a dev-tool folder | `make-app.sh` copied them into the bundle | Product source (prompt code) mixed up with dev config: the repo's own Claude Code sessions loaded the app's roles as dev skills. |

### Build and config

| Finding | Evidence | Why it mattered |
|---|---|---|
| The `.app` bundle was assembled by a shell script, with an inline Info.plist | `make-app.sh` | No app icon, no entitlements, no hardened runtime, no notarization path, no update path. |
| Bundle ID `local.yongkang.app`, version `0.1` hard-coded | `make-app.sh` | The version wasn't tied to git, so you couldn't tell which build was running. |
| `swift-tools-version: 5.9`, macOS 13, while the toolchain was Swift 6.3.1 | `Package.swift` | No strict concurrency checking, and no Observation framework. |
| No formatter, no linter, no single "check" command | repo root | Nothing verified an agent's handoff except whoever remembered `swift run Yongkang --selftest`. |

### Code

| Finding | Evidence | Why it mattered |
|---|---|---|
| **One flat target:** 55 files, 15,160 lines | `Sources/Yongkang/` | No enforced boundary between parsing logic and views. |
| **`App.swift` was a 1,421-line god object**: 20 `@State` + 4 `@AppStorage`, ~80 methods covering navigation, sessions, assignment, git, review, product flows, polling and a self-test | `App.swift` | Every feature touched it, so parallel agents collided on it. Well past the 800-line limit. |
| **Selection was `String?` in 15 hand-parsed prefix formats** (`review-task:<uuid>:<id>`, `subagent:<uuid>:<id>`, a bare UUID for sessions, …) | `Tags.swift`, `App.swift` | A typo compiled fine and silently showed the "Nothing selected" pane. |
| **The test suite shipped inside the app binary:** `NotebookSelfTest.swift` (1,786 lines, ~460 `precondition`s), `DesignShots.swift` (531 lines), and `--attention-selftest` in `App.swift` (used `try!` and wrote to `/tmp`) | `App.swift:70-80`, `:880-917` | A precondition stops at the first failure, and there were no per-test results. |
| **A 2 s main-thread timer did synchronous I/O**: it walked every project's notebook, parsed frontmatter, scanned `~/.codex/sessions`, read and wrote `usage.json`, and every 6 s spawned **up to 8 blocking `git` processes** | `App.swift:1016-1061`, `GitChanges.swift` | UI hitches in large repos, plus constant CPU and battery use while idle. |
| Every untracked file was **read in full** to count lines on each git refresh | `GitChanges.lineCount` | A fresh project with no `.gitignore` and a `node_modules/` froze the window every 6 s. |
| I/O reachable from view bodies: `previewStep` → `Service.plan` read `package.json` and compose files. `ChangeSummary.of` was recomputed at 13 call sites | `App.swift:491`, `:1000` | Re-renders paid for file reads and repeated derivation. |
| **PTY lifetime was tied to SwiftUI view identity**: terminals kept alive in a `ZStack` at `opacity(0)`, positioned with `railWidth + listWidth` padding math. Text reached a terminal through a `pendingInput` binding round-trip, with a guard against double-sending | `App.swift:165-186`, `AgentTerminal.swift:174-207` | Fragile. A layout change or view-identity change could kill a running agent. |
| **Provider logic was scattered.** Adding Grok and Agy touched 8 files. `ClaudeTranscripts` lived in `SubagentActivity.swift`; `AgentKind`, `AgentCommand` and `BundledSkills` lived in the terminal *view* file | `git show --stat fb13f1e` | Every new CLI or CLI format change was a hunt across the codebase. |
| Global mutable static caches | `CodexTranscripts` (4), `AgentUsage.files`, `DemoPages` (2) | Hard errors under Swift 6 mode, and real data races once I/O moved off the main thread. |
| UI mixed into domain code | `AgentUsage.tint/modelTint/palette` returned `SwiftUI.Color` | Blocked a Foundation-only core. |
| 10 `NSAlert.runModal()` calls from logic code | `App.swift` (8), `NotebookEditor.swift` (2) | Blocked the main run loop, including terminal rendering, and couldn't be tested. |
| Design tokens existed, but hex literals were spread across the features, there were 15 distinct font sizes on a 0.5 pt ramp, and custom fonts were used only "if installed" | `Theme.swift` and others | The look wasn't systematic, and it differed on any Mac without those three fonts. |
| No menu bar commands. ⌘N and ⌘O only worked while the home screen was visible. **⌘[ was advertised in the README and a tooltip but wasn't implemented** | `grep keyboardShortcut` | Shortcuts that depend on which view is on screen feel broken; the menu bar is how a Mac app exposes them. |

**Strengths the refactor protected** (they are invariants in `docs/architecture.md` now):

- The notebook files are the only state. The app never writes what agents write, and it never
  commits unless the user approves.
- The comments explain *why*, and `ponytail:` markers name deliberate ceilings.
- The shots renderer draws every screen offscreen, which is a rare and valuable review tool.
- Fixture-grade coverage of real CLI output formats (Codex trust screen bytes, transcript
  layouts).

### 1.5 The same measurements now

| Then (`69c4bc0`) | Now |
|---|---|
| One flat target, 55 files, 15,160 lines | Three targets: `YongkangCore` 41 files / 5,660 lines, `YongkangUI` 61 / 10,690, `Shots` 3 / 719 |
| `App.swift`, 1,421 lines | Gone. The largest source file is `Sources/Shots/DesignShots.swift` at 661 lines, and it never ships |
| ~460 `precondition`s inside the app binary | 281 tests in 44 suites across 46 test files (6,303 lines), 12 recorded known issues |
| `swift-tools-version: 5.9`, macOS 13, no concurrency checking | tools 6.0, macOS 14, Swift 6 language mode on every target, plus `ExistentialAny` |
| `make-app.sh` with an inline Info.plist | `App/Yongkang.xcodeproj`, bundle ID `ai.yongkang.Yongkang`, build number from `git rev-list --count HEAD` |
| No check command | `make check` — `swift format lint --strict`, `swift build`, `swift test` — also a `pre-push` hook |
| 42 hex literals across 14 feature files | 35 named tokens in `Theme.swift` and nowhere else; `DesignTokenTests` fails the build on a stray one |
| 15 font sizes on a 0.5 pt ramp | 8 roles over 7 sizes in `Typography`; `DesignTokenTests` fails the build if a screen reaches past a role |
| No menu bar | `YongkangCommands`: File, View, Go, Agent, and every shortcut in the app on one of their items |

---

## 2. Goals and non-goals

**Goals**, each with what checks it now:

1. **Cheap to change:** a feature lives in its own folder, no file is over 800 lines, and the
   app's own entry point is `App/Yongkang/main.swift`, 5 lines. *Checked by reading; nothing
   fails the build on a 900-line file.*
2. **Safe to change:** `make check` is the definition of done, for the author and for every
   agent handoff. *Checked by the `pre-push` hook.*
3. **Fast and quiet:** no git or file I/O on the main thread. *`ProjectModelTests.aReloadDoesItsReadingOffTheMainActor`
   pins the notebook read. The "idle CPU under 1%" target was never measured, so it is not
   claimed.*
4. **Polished:** menu bar commands, one set of design tokens, an icon drawn from a view, and
   native containers where the platform already had them.
5. **Agent-friendly:** `AGENTS.md`, one check command, and fixture-based parser tests, so an
   agent can fix a CLI format change without being told how.
6. **Open-source-ready later, at no extra cost now:** nothing blocks going public, and §8 holds
   the checklist.

**Non-goals**, and why:

- **No open-sourcing in the short term.** No license, no community files, no public release
  channels, no launch. §8 says what it would take.
- **No rewrite.** 15k lines of working, well-reasoned code; every phase moved or wrapped
  existing code.
- **No change to the `.notebook/` format or product behaviour.** The projects depend on it, and
  it wasn't the problem.
- **No Mac App Store.** The app has to spawn arbitrary CLIs and read `~/.claude`, `~/.codex` and
  `~/.grok`, and the sandbox forbids that.
- **No distribution work before there's a second user** (D9).

---

## 3. Principles the refactor was run under

1. **Tests before moves.** Nothing was restructured until the existing checks ran under
   `swift test`.
2. **Behaviour-preserving phases.** Each phase ended with shots compared before and after, and
   `make check` green.
3. **One boundary, enforced by the compiler.** Logic cannot import SwiftUI. Everything else is
   organised with folders, not modules.
4. **Native first.** Before writing a component, check whether AppKit or SwiftUI already has one
   (commands, alerts, split view, toolbar).
5. **`git mv` for moves, separate from edits.** Moving a file and changing it in one commit
   destroys `git blame` and makes review impossible.
6. **Design changes go through `/design` first.** An existing project rule. The plan picked
   *where* native chrome was worth evaluating; the canvas decided *what it looks like*.
7. **Keep the "why" comment culture.**

---

## 4. Decisions

Each decision lists what it is, why, what was rejected, and what it cost. These are the part
worth keeping.

### Repository and docs

#### D1 — Default branch `main`; the repo stays private

- **Why:** GitHub's default `notebooks` was 44 commits stale. Anything that branched from the
  default started from old code, and PRs targeted the wrong base.
- **Shipped:** `origin/HEAD` points at `main`, and `notebooks` is gone from the remote.
- **Not done:** a secret scan of the full history. It only matters before the history becomes
  visible to someone else, so it is in the §8 checklist.

#### D2 — Short README; the design journal moves to `docs/`

- **Why:** the README is what the author, an agent, or a future tester opens first. It was 21 KB
  of design rationale before you found how to build. Split, the entry point is quick and the
  reasoning stays intact and easier to navigate by topic.
- **Shipped:** a README of about 70 lines — one-line description, one screenshot, requirements,
  build/run/test, how it works with the mermaid flowchart, and a map of `docs/`.
- **`docs/` received the old sections nearly verbatim:** `guide/{projects,notebook,board,design-gate,product,engineering-lead,team,review,blocks}.md`,
  plus `notebook-format.md`, `providers.md`, `architecture.md` and `development.md`.
- **Rejected:** a marketing-style landing README with badges and a hero GIF. No audience while
  the repo is private. It is in §8.

#### D3 — `AGENTS.md` (with `CLAUDE.md` symlinked to it) and `docs/development.md`

- **Why `AGENTS.md`:** agents are the main contributors. One auto-loaded file cuts wrong guesses
  and repeated exploration. It holds the commands, the Core/UI import rule, the `.notebook`
  format rule, the `/design`-first rule, "review opens on outcomes", and the 800-line limit.
- **Why the symlink:** Codex reads `AGENTS.md` and Claude Code reads `CLAUDE.md`; one file keeps
  them from drifting. The same trick `.agents/skills` already used.
- **Why `docs/development.md`:** the details too long for `AGENTS.md` — the manual smoke script,
  how to capture a CLI fixture, the app icon, and the stable local signing identity (which had
  been a comment in `make-app.sh`).
- **Rejected:** `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` and issue or PR
  templates. They are for outside contributors, so they moved to §8.

#### D4 — Shipped skills move to top-level `Skills/`

- **Why:** the 9 role skills are *product source*. They are the prompt code that decides how the
  lead, QA and designer behave, and probably the most-tuned files in the repo. In
  `.claude/skills/` they looked like dev config, and the repo's own agents loaded them as dev
  skills.
- **Shipped:** `git mv .claude/skills Skills`, with `.claude/skills` and `.agents/skills` kept as
  symlinks so dogfooding and native discovery still work. A `Bundle skills` build phase rsyncs
  the folder into `Contents/Resources/skills` on every build, which replaced the `cp -R` in
  `make-app.sh`.
- **Rejected:** a separate skills repo, because versions would drift from the app that embeds
  them.

### Build and config

#### D5 — Thin Xcode app shell plus a Swift package that holds all code

```
Package.swift            ← unchanged location; `swift build` / `swift test` still work
App/Yongkang.xcodeproj   ← one app target, ~4 files that rarely change
App/Yongkang/            ← main.swift (one call), Assets.xcassets, .entitlements
```

- **Why an Xcode project at all:** an app icon from an asset catalog, entitlements plus hardened
  runtime, Archive and notarize, and (later) embedding and signing Sparkle are all automatic in
  Xcode and fragile to script. `make-app.sh` could do none of them.
- **Why a *thin* one:** parallel agent worktrees have the same `project.pbxproj` merge-conflict
  problem that many contributors do. With Xcode 16+ synchronized folders and all sources in the
  package, adding a file never touches the project file, and `swift build` and `swift test` keep
  working with only the Command Line Tools.
- **Why `App/` rather than the root:** `Package.swift` stays put, so every existing command and
  path keeps working.
- **Rejected:** pure SPM plus a longer script (the icon, entitlements and notarization would all
  be hand-rolled); XcodeGen or Tuist (one more tool to install and pin, for a single target);
  moving everything into Xcode (the CLI test loop would be lost and every file add would conflict
  across worktrees).

#### D6 — Swift 6 tools, macOS 14 minimum, strict concurrency staged

- **Shipped:** `swift-tools-version: 6.0`. The UI target started in `.v5` language mode; Core got
  `.v6` once its static caches were fixed, then the SwiftUI targets followed. `ExistentialAny`
  is on as well — it costs a handful of `any Error` and makes the one place that really does box
  a protocol, `any AgentProvider`, say so.
- **Why staged:** Phase 4 moved I/O off the main thread, which is exactly when data races start.
  Swift 6 mode turns those into compile errors before they show up as crashes.
- **macOS 14 (Sonoma)** unlocked `@Observable` (D12), `.inspector()` (evaluated in D16 and not
  taken), and two-parameter `onChange`.
- **Rejected:** staying on 13 (Observation isn't available, so the state refactor would need
  `ObservableObject`, whose coarse invalidation is what was being fixed); going to 15 or later
  (nothing needed it, and it would narrow future testers for no reason).

#### D7 — A Makefile replaces `make-app.sh`

```
make check    # swift format lint + swift build + swift test  ← the definition of done
make format   # swift format -i -r Sources Tests
make run      # debug build of the app, then open it
make shots    # render every screen offscreen
make icon     # redraw the app icon's 1024 master
make archive  # signed Release build
make help     # every target
```

- **Why Make:** it ships with the Command Line Tools, `make help` makes it discoverable, and it
  gives the author and the agents one entry point.
- **Signing:** a single committed `App/Config/Signing.xcconfig`. The "stable self-signed identity
  so TCC approval sticks" trick carried over into `docs/development.md`.
- **Rejected:** a gitignored `Local.xcconfig` for the Team ID. That solves an outside-contributor
  problem; for a private repo, committing it is simpler, and a Team ID isn't secret.

#### D8 — `swift format` plus a local check instead of hosted CI

- **Formatter: `swift format`**, which ships in the Swift 6 toolchain. Zero install,
  Apple-maintained, works in every worktree. `.swift-format` matches the existing style, and the
  one-time reformat commit is listed in `.git-blame-ignore-revs` so `git blame` still shows the
  real history.
  - **Rejected:** SwiftLint and Nick Lockwood's SwiftFormat. Both good, both add a Homebrew
    dependency and a version to pin.
- **Verification: `make check` locally,** required by `AGENTS.md` before any handoff, plus a
  `pre-push` hook.
  - **Why not GitHub Actions:** hosted macOS runner minutes on *private* repos count against the
    plan at a high multiplier, and a solo private repo gets little from a remote check that
    `make check` doesn't already give.
  - **Add a workflow when:** a second person pushes, or release builds should be made off this
    machine. The same `make check` becomes its only step.

#### D9 — Distribution: stage it by audience

| Stage | What's needed | Why |
|---|---|---|
| **Now: only you** | `make run` / `make archive` with the stable self-signed identity. | TCC approval sticks with that identity. Notarization, updates and installers have no user yet. |
| **First tester on another Mac** | Apple Developer Program, **Developer ID** signing with hardened runtime, `xcrun notarytool` + staple, a DMG. | Without notarization, Gatekeeper blocks the app on anyone else's Mac. Hardened runtime needs **no** exception entitlements (child processes, WebKit and UserNotifications all work under it). Keep it that way. |
| **Several testers** | **Sparkle 2** with an EdDSA-signed appcast, and the DMG and appcast on a **public static host**. SemVer tags; `MARKETING_VERSION` from the tag. | Parsers that follow fast-moving CLI formats need fast updates. **Release assets on a private GitHub repo can't be downloaded without authentication**, so Sparkle can't fetch them: the binaries have to live somewhere public even while the source stays private. |

- **Bundle ID:** changed from `local.yongkang.app` to **`ai.yongkang.Yongkang`** in Phase 2, with
  the Xcode shell — while the author was the only person it affected, because the change resets
  UserDefaults, TCC grants and notification permission. (The plan had guessed at
  `io.github.jstinhw.Yongkang`; §9 records the answer.)
- **Bundle ID migration:** `DefaultsMigration` reads the old domain once on first launch and
  carries over `openProjects`, `listWidth`, `listHidden` and `agentKind`. `listWidth` is
  migrated even though nothing writes it any more (D16, window restoration) — dropping a key
  from the migration would silently lose it for anyone still on the old domain.
- **Rejected for now:** a Homebrew cask. It needs a publicly downloadable artifact and mostly
  helps discovery, which isn't a goal yet.
- **Status: not started.** Everything in this table past the first row is Phase 6.

### Code architecture

#### D10 — Migrate the self-test to Swift Testing first, with fixture files

- **Why first:** the ~460 checks in `NotebookSelfTest.swift` were the only safety net for a
  refactor that moved every file. They had to run under `swift test` before anything moved.
- **Why Swift Testing over XCTest:** it ships with the toolchain; `@Test(arguments:)` fits the
  many table-shaped checks; `#expect` captures the expression on failure; tests run in parallel;
  and it reports *all* failures, where the first precondition used to kill the run.
- **Fixtures:** captured Codex trust-screen ANSI bytes, sample Claude, Codex and Grok JSONL
  transcripts, and compose and `package.json` samples moved from inline strings to
  `Tests/YongkangCoreTests/Fixtures/<provider>/…`.
  - **Why:** the CLIs change their formats often. With fixture files, "Codex 0.160 changed
    rollouts" becomes: add one file, fix one parser. An agent can do that unprompted, and the
    fixture folder records which CLI versions are supported.
  - **Trust boundary:** these parsers read files written by agents and third-party CLIs, so the
    fixtures include **malformed inputs** — truncated JSONL, frontmatter with injected newlines,
    `../` paths. Three of those inputs are still handled wrongly, and are recorded as known
    issues rather than hidden (§8).
- **Split by domain**, one file per domain.
- **`--attention-selftest`** became a model test, and the screenshot moved to Shots. `--selftest`
  is gone from the app.
- **Rejected:** snapshot-testing libraries. The shots renderer, compared before and after, covers
  visual review without a new dependency or brittle pixel baselines.

#### D11 — Two library targets, one dev executable, `package` access

```
YongkangCore   Foundation only. Notebook, providers, git, review, services, skills, shell, prompts.
YongkangUI     SwiftUI/AppKit + SwiftTerm. Models, design system, terminal, features.
Shots          dev-only executable: `swift run shots <dir>`. Never in the shipped app.
```

- **Why this split:** the compiler enforces the boundary, so Core can't `import SwiftUI` and
  agents can't erode it by accident; Core tests run headless and fast; SwiftUI Previews work
  reliably in a library target; and editing a view doesn't recompile the parsers.
- **Why `package` access, not `public`:** `package` lets targets in the same package see each
  other without turning every type into public API. It avoids a mass `public` pass and signals
  that there is no external API to keep stable. The one `public` is `YongkangMain`, because Xcode
  builds the app target without the package's `-package-name`.
- **Why not more modules** (`NotebookKit`, `GitKit`, `DesignSystem`, one per feature): at 15k
  lines, each extra boundary costs access annotations and dependency wiring and buys nothing the
  folder structure doesn't already give. Split later if a folder grows a real second consumer.
- **Moves that fell out of it:** `AgentKind`, `AgentCommand` and `BundledSkills` left the terminal
  view file; `Transcripts` left `AgentUsage.swift`; `ClaudeTranscripts` left
  `SubagentActivity.swift`; the prompt builders left `NotebookFormat` for `Prompts/`; the colour
  helpers in `AgentUsage` moved to `YongkangUI/DesignSystem`.

#### D12 — State: `@Observable` models, a typed `Route`, workflows that return where to go

`YongkangApp` had been view, controller, store and test harness at once. It became:

- **`AppModel`** — the projects, the section and selection, the agent kind, `alert`, and the
  `TerminalRegistry`.
- **`ProjectModel`** — one per open project: an immutable `NotebookSnapshot`, a `RepoStatus`, the
  sessions, the review drafts, and a stored `ChangeSummary`.
- **`Route`** — a `Hashable` enum: `overview`, `board`, `usage`, `project`, `task`, `page`,
  `session(UUID, pane:)`, `subagent`, `block`, `member`, `review`, `reviewTask`, `preview`.

- **Why Observation over `@State` in `App`:** every write to `projects[i].sessions[j]`
  invalidated every view that read `projects`. A per-project `@Observable` class means a poll that
  changes project B's cards doesn't re-render project A's terminal pane. It also ended the
  `projects.firstIndex(where:)` index-chasing that filled `App.swift`.
- **How it fits "never mutate":** the models are the one explicit mutation boundary. The notebook
  data inside them stays an **immutable value replaced wholesale** (`snapshot = newSnapshot`),
  which is what the `Equatable` comparison before every assignment is for.
- **Why a typed `Route`:** `Tags.swift` argued selection had to be a string so it "survives the
  2-second reload that replaces the model wholesale". A `Hashable` enum carrying the same stable
  IDs survives just as well, and the compiler checks it. That removed all 15 prefix formats and
  the `hasPrefix`/`dropFirst` parsing.
- **Why workflows return a `Route`:** `assign`, `startProduct`, `startUnblock`, `requestChanges`
  and `approveDemo` are `ProjectModel+<concern>.swift` methods that **return the route to open**.
  Navigation stays in one place, each workflow is a unit test with no view involved, and two
  agents working on assignment and review no longer edit the same file.
- **Alerts:** SwiftUI `.alert` and `.confirmationDialog` bound to `AppModel.alert`. The title
  prompt became `.alert` with a `TextField`. `runModal()` blocked the run loop that renders the
  terminals and runs the poll, and couldn't be tested.
- **Rejected:** The Composable Architecture (a large dependency and learning curve, and the app's
  effects — PTYs, FSEvents — don't need reducers); a ViewModel per view (it duplicates what
  Observation already gives views); SwiftData or Core Data (the notebook files *are* the store,
  by design).

#### D13 — `TerminalRegistry` owns PTY lifetime

- **Problem:** a running agent's process lived inside an `NSView` that SwiftUI created and might
  destroy. The code kept it alive by never unmounting it, and delivered typed input through a
  binding that `updateNSView` cleared asynchronously, with a guard against sending twice.
- **Decision:** a `@MainActor` `TerminalRegistry` creates and owns one `AttentionTerminalView`
  per session, and the work area embeds a `TerminalHost: NSViewRepresentable` that **re-parents**
  the registry's existing view into its container when visible.
- **Why:** process lifetime becomes explicit and independent of layout, so a later native split
  view could not accidentally kill an agent; `send` becomes a direct call; the padding math
  disappears; and child-agent picker navigation moves into the registry, where it can be tested.
- **The risk was spiked first** (PR 2.1), before the registry was built. All six questions
  passed, so the fallback — one permanent host view positioned from outside — was never built.
  The verdicts, with SwiftTerm line numbers, and the constraints the registry has to respect are
  in `docs/architecture.md`, "Terminal lifetime".

#### D14 — I/O off the main thread, event-driven refresh, fewer git processes

- **A `ProjectReader` actor per project** holds the notebook read, the transcript scan, the usage
  ledger and git. It answers with values; `ProjectModel` publishes them, and only when they
  differ from what it already holds.
- **FSEvents instead of the 2 s timer**, with about 300 ms of latency so a burst coalesces, and a
  **30 s safety poll** behind it, because FSEvents drops events on network volumes and across
  sleep and "the board didn't update" would be a hard bug to reproduce.
  - This revised the existing `ponytail:` note ("poll instead of FSEvents; revisit at thousands
    of files"). The trigger arrived in a different form: the cost wasn't the notebook tree, it
    was git and transcript scans on every tick while the Mac was idle.
- **Git:** two processes per refresh instead of up to eight —
  `git status --porcelain=v2 --branch -z --untracked-files=all` and `git diff --numstat -z HEAD`,
  at most every 6 s. Untracked line counts are taken lazily, only for rows a screen is showing,
  and a file over 1 MiB (`RepoStatus.countLimit`) is never read.
- **No I/O in view bodies:** `Service.plan` and `ChangeSummary` are computed in the model when
  their inputs change, and views read stored values.
- **Diagnostics:** `os.Logger` under subsystem `ai.yongkang.Yongkang`, categories `notebook`,
  `git`, `terminal`, `providers`. Only paths, counts, exit statuses and error descriptions are
  ever logged, and nothing leaves the Mac.

#### D15 — One `AgentProvider` per CLI

`Sources/YongkangCore/Providers/{ClaudeCode,Codex,Grok,Agy}/`, each with its fixtures under
`Tests/YongkangCoreTests/Fixtures/<cli>/`. The protocol as it shipped, and the checklist for
adding a CLI, are in [`docs/providers.md`](providers.md).

- **Why a protocol here, when the plan otherwise avoids abstractions:** it has four
  implementations, CLIs had already been added twice (Codex, then Grok and Agy, which touched 8
  files), and format changes land per provider. `AgentKind` stays the persisted identity and
  gains `var provider: any AgentProvider`.
- **Static caches:** the `static var` caches in `CodexTranscripts` and `AgentUsage` became
  per-provider actor state — `UsageReader` for usage cursors, `CodexTranscripts` for the rollout
  index — which is also what Swift 6 mode requires.
- **Launching stays as it is:** `zsh -ilc` with the quoted command line, which is tested and
  correct for this setup. §8 says when to switch to direct launch.
- **Rejected:** runtime plugins or dylibs. No stable ABI story, a security liability, and
  compile-time is enough.

### Mac polish and design

#### D16 — Menu bar commands and design consolidation

- **`.commands`** landed as `YongkangCommands`: File (New Project ⌘N, Open Folder ⌘O, Close
  Project, Reveal in Finder), View (⌘1–⌘5, Hide List ⌘\\, Show Completed), Go (All Projects ⌘[,
  which fixes the documented-but-missing shortcut), Agent (New Session, Assign to Lead, Product
  Review). Two readings were made explicit: "Assign to Lead" hands over the *selected* task,
  because the board's ticked batch is that view's own state; and every item that needs a project
  is disabled, not hidden. The tree and its rules are in `docs/architecture.md`, "The menu bar".
- **Accessibility basics:** eleven `.accessibilityLabel`s, on the things with no text of their
  own — the rail's mark and its section icons, the two label-less toolbar pickers, the usage
  chart's bars, and six icon-only buttons across Fleet, the board, the lead board, Review and the
  list column. `.accessibilityElement(children: .combine)` makes one element of the Fleet card,
  the board card, the lead board's worker card and a list row, so VoiceOver reads a card rather
  than its pieces. A full VoiceOver audit waits for testers (§8).
- **Window restoration:** `@SceneStorage` for the entered project, the section and the route —
  section and route mean nothing without the project. A route that no longer points at anything
  opens the section's default rather than an empty screen. The sidebar's dragged width is the one
  thing that could not be stored (§8).
- **Design tokens, mechanical, no visual change:**
  - **42 hex literals across 14 feature files** moved into `Theme` as named tokens — sixteen new
    names, and four literals that turned out to be values `Theme` already had. `DesignTokenTests`
    fails the build if one reappears outside `Theme.swift`.
  - **15 font sizes on a 0.5 pt ramp collapsed to 8 roles over 7 sizes** (`title`, `headline`,
    `body`, `caption`, `code`, `mono`, `monoCaption`, `section`), each carrying one size and a
    weight where a call site leaned on weight rather than size. `Typo`, the face plumbing, has no
    caller outside `Typography`, and a scanner test holds it that way.
  - **Colours were *not* made dynamic** `NSColor(name:dynamicProvider:)` values, as this decision
    originally asked. `RootView` pins `.preferredColorScheme(.dark)`, so a provider would only
    ever run its dark branch, and there is no light palette for the other one to return. Dynamic
    arrives with the palette that gives it something to return. The reasoning is on `Theme`.
- **Evaluated in a `/design` canvas before any code** (project rule):
  1. **Typography:** bundle three OFL fonts, or commit to SF Pro and SF Mono. *Decided: SF Pro
     and SF Mono* — native feel, nothing to bundle, and the same look on every Mac. The three
     named faces only ever reached the screen on a Mac that happened to have them installed.
  2. **Chrome:** keep the custom rail, top bar and inspector, or map them onto
     `NavigationSplitView` + native toolbar + `.inspector()`. *Decided: native containers styled
     with the existing dark tokens, except the inspector.* The list column is a
     `NavigationSplitView` sidebar and the top bar is the window's toolbar; the rail stays custom,
     outside the split view, because a native sidebar cannot hold both without reading as two
     sidebars. `.inspector()` was held, on purpose and not by accident — see §8 and
     `docs/architecture.md`, "How the window is composed".
  3. **App icon:** there was none, so the Dock, Finder and ⌘-Tab showed a generic app. It is now
     drawn in code from `DesignSystem/AppIcon.swift` and rendered to the catalog's 1024 master by
     `make icon`. `docs/development.md` has the `actool` trap that makes a wrong catalog entry
     ship no icon at all.

---

## 5. The layout

```
yongkang/
├── README.md  AGENTS.md  CLAUDE.md → AGENTS.md
├── Makefile  .swift-format  .git-blame-ignore-revs  .gitignore  .githooks/
├── Package.swift                          # tools 6.0; Core, UI, Shots, two test targets
├── App/                                   # thin Xcode shell
│   ├── Yongkang.xcodeproj
│   ├── Config/Signing.xcconfig
│   └── Yongkang/{main.swift, Assets.xcassets, Yongkang.entitlements}
├── Skills/                                # shipped role skills (source of truth)
│   └── engineering-lead/ product/ designer/ frontend-dev/ backend-dev/ qa-dev/ sre-dev/ fde-dev/ incubate-agent/
├── .claude/skills → ../Skills             # symlinks, for dogfooding
├── .agents/skills → ../Skills
├── docs/
│   ├── images/                            # the nine shots the pages point at
│   ├── architecture.md  development.md  notebook-format.md  providers.md  refactor-plan.md
│   └── guide/{projects,notebook,board,design-gate,product,engineering-lead,team,review,blocks}.md
├── Sources/
│   ├── YongkangCore/                      # Foundation only
│   │   ├── Notebook/    Format, Notebook, Index, Content, Blocks, Team, LeadCoordination, UsageLedger, Snapshot
│   │   ├── Providers/   AgentProvider, AgentKind, AgentState, ClaudeCode/, Codex/, Grok/, Agy/
│   │   ├── Project/     Project, Route, DefaultsMigration
│   │   ├── Git/         GitClient (async), RepoStatus
│   │   ├── Review/      ChangeSummary, ReviewArea
│   │   ├── Services/    Service detection
│   │   ├── Skills/      Skills, SkillDoc, BundledSkills
│   │   ├── Shell/       AgentCommand, AsyncProcess
│   │   ├── Prompts/     NotebookPrompts
│   │   ├── Usage/       AgentUsage, UsageReader
│   │   ├── Watching/    FSEventWatcher, ProjectReader (actor)
│   │   └── Diagnostics/ Log
│   ├── YongkangUI/                        # SwiftUI + AppKit + SwiftTerm
│   │   ├── App/         YongkangMain, YongkangApp, RootView(+Actions/+Screen/+Toolbar), Rail, ProjectList, Commands
│   │   ├── Model/       AppModel(+Alerts/+Restore), ProjectModel(+Assign/+Blocks/+Notebook/+Product/+Review/+Services)
│   │   ├── Terminal/    TerminalRegistry, TerminalHost, AgentAttention
│   │   ├── DesignSystem/ Theme, Typography, ButtonStyles, Surfaces, RoleTile, MeterBar, StateDot, AppIcon, …
│   │   └── Features/    Home/ Onboarding/ Overview/ Board/ Agents/ Blocks/ Notebook/ Team/ Review/ Demo/ Preview/ Usage/
│   └── Shots/                             # dev-only executable
└── Tests/
    ├── YongkangCoreTests/  (+ Fixtures/{claude,codex,grok,usage,compose,coordination,git,notebook}/)
    └── YongkangUITests/    views, the terminal, colours and the models (not XCUITest)
```

---

## 6. The phases

Every phase shipped on its own, split into reviewable PRs, ending with `make check` green and
shots compared.

### Phase 0: repo hygiene — done

| PR | Content |
|---|---|
| 0.1 | Push `main`, switch the GitHub default branch, retire the stale branches. |
| 0.2 | README split: short README + `docs/guide/*` (content moved, not rewritten). |
| 0.3 | `AGENTS.md` (with `CLAUDE.md` symlink) and `docs/development.md`. |

### Phase 1: safety net — done

| PR | Content |
|---|---|
| 1.1 | `swift-tools-version: 6.0` with `.v5` language mode; add the test target. |
| 1.2 | Port `NotebookSelfTest` to Swift Testing, by domain, with fixture files. Delete `--selftest`. |
| 1.3 | `.swift-format` config, a one-time reformat commit, `.git-blame-ignore-revs`. |
| 1.4 | `make check`, the `pre-push` hook, and `AGENTS.md` updated to require it. |

**Why this order:** 1.2 before any move meant every later PR was checked. 1.3 landed before the
moves so later diffs weren't polluted by formatting.

### Phase 2: structure — done

| PR | Content |
|---|---|
| 2.1 | Spike: `TerminalHost` re-parenting (D13 risk). Result recorded in `docs/architecture.md`. |
| 2.2 | Create `YongkangCore`, `YongkangUI` and `Shots`. `git mv` files into folders, add `package` access, pull the SwiftUI colour helpers out of `AgentUsage`. |
| 2.3 | `git mv .claude/skills Skills` and add the symlinks. Bundle `Skills/` as a resource. |
| 2.4 | Thin Xcode shell in `App/`, the signing xcconfig, and a Makefile replacing `make-app.sh`. Bundle ID change with the defaults migration. |

### Phase 3: state and lifetime — done

| PR | Content |
|---|---|
| 3.1 | Minimum to macOS 14. `Route` enum replaces `Tag` and string selection. |
| 3.2 | `AppModel` / `ProjectModel` (`@Observable`), `NotebookSnapshot` value type. |
| 3.3 | Workflows become `ProjectModel+*` extensions returning a `Route`, each with a model test. |
| 3.4 | `TerminalRegistry` + `TerminalHost`. Delete the `ZStack`/opacity mounting and `pendingInput`. |
| 3.5 | `NSAlert.runModal` → SwiftUI alerts and dialogs. Port the attention self-test to a model test. |

### Phase 4: performance and correctness — done

| PR | Content |
|---|---|
| 4.1 | `AsyncProcess` + `GitClient` using 2 git calls. Lazy untracked line counts with a 1 MiB skip. |
| 4.2 | `ProjectReader` actor; all reads off the main thread; no I/O in view bodies. |
| 4.3 | `AgentProvider` protocol, the four providers in their folders, static caches into actor state. |
| 4.4 | Swift 6 language mode on Core, then UI. Then `ExistentialAny`. |
| 4.5 | FSEvents watcher with a 30 s safety poll. Delete the 2 s timer. `os.Logger` diagnostics. |

**The exit criteria, honestly:** the main-thread claim is pinned by a test
(`aReloadDoesItsReadingOffTheMainActor`) rather than by an Instruments trace. The "idle CPU under
1%" and "20k untracked files" measurements were never taken, so §2 no longer claims them. Swift
6 mode builds warning-free: `swift build --build-tests -Xswiftc -warnings-as-errors` is clean.

### Phase 5: Mac polish and design — done

| PR | Content |
|---|---|
| 5.1 | Token consolidation, no visual change. |
| 5.2 | `/design` canvas for typography, chrome and the app icon. Decided, then implemented. |
| 5.3 | `.commands` menus (including ⌘[), accessibility labels, `@SceneStorage` restoration. |
| 5.4 | Regenerate `docs/images`; make every claim in the docs true against the code. |

### Phase 6: sharing with testers — not started

Triggered by the first person other than the author who needs to run the app (D9). Nothing here
exists yet: no Developer ID, no `make release`, no notarization, no Sparkle, no appcast.

| PR | Content |
|---|---|
| 6.1 | Apple Developer Program; Developer ID certificate and notarytool API key in the Keychain. |
| 6.2 | `make release`: archive, sign, notarize, staple, DMG. |
| 6.3 | With more than one tester: Sparkle 2, an appcast, and a public static host for both. |

**Exit:** on a clean Mac, the DMG opens with no Gatekeeper prompt.

---

## 7. Risks, and what happened

| Risk | Mitigation | Outcome |
|---|---|---|
| The refactor silently changes behaviour the ~460 checks don't cover | Phase 1 first; shots compared on every structural PR; the smoke script run at the end of Phases 2, 3 and 4 | The suite grew to 281 tests. The smoke script is the part that still needs a person; it is in `docs/development.md`. |
| Re-parenting terminal views breaks PTY or rendering | Spike PR 2.1 before any dependent work; a documented fallback | All six verdicts passed. The fallback was never built, and `TerminalReparentingTests` stays as the regression test. |
| FSEvents misses changes | Keep the 30 s safety poll; manual "Refresh" stays in Review | Both are there. `ProjectWatchTests` covers the watch and the beat behind it. |
| CLI output formats change under the parsers | Fixture-per-version tests and `os.Logger` diagnostics | Fixtures are named after the CLI version they came from; `Log` replaced the silent `try?`. |
| The bundle ID change loses settings or TCC grants | One-time defaults migration; expect macOS to ask for folder access once more | `DefaultsMigration` carries four keys over. Whether the grants survived is not something this repo can check. |
| Parallel agents conflict during the moves | PR-sized phases merged to `main` continuously; `git mv` PRs kept separate | Held. |
| Skipping hosted CI lets a broken `main` slip through | `make check` in the `pre-push` hook and required by `AGENTS.md` | Held; the hook needs `git config core.hooksPath .githooks` once per clone. |

---

## 8. Deliberately not done

What a reader might expect to find and won't, with the trigger that would bring it back.

### Known bugs, recorded rather than fixed

`swift test` passes with **12 known issues**, in five `withKnownIssue` blocks. They are real bugs
in readers that take agent-written files, kept visible instead of being papered over. A
`withKnownIssue` is a recorded bug, never a pass to copy.

| Bug | Recorded in | Issues |
|---|---|---|
| `NotebookFormat.yaml` escapes quotes and backslashes but not newlines, so a title containing a line break is written as frontmatter that parses as extra keys | `NotebookFormatTests.titleWithNewlineStaysOneValue` | 4 |
| A line inside a quoted title is read as a key of its own — `status: done` hides a todo task as done | `NotebookIndexTests.quotedValueSpanningLinesInjectsAKey` | 1 |
| A `---` line inside a quoted title closes the frontmatter early, dropping `status`, `project` and `depends_on` | `NotebookIndexTests.quotedValueSpanningLinesClosesTheBlockEarly` | 3 |
| `Skills.url` appends a skill name to each root unchecked, so a `../../outside` name in a team file resolves to a `SKILL.md` outside the skill folders | `SkillsTests.dotDotSkillNameDoesNotEscapeTheSkillRoots` | 2 |
| `UsageLedger.record` treats an unreadable `usage.json` as empty and replaces it, losing the hours it held | `UsageTests.damagedLedgerIsNotOverwritten` | 2 |

The first three rows are one root cause: `NotebookIndex` parses frontmatter line by line, and
`NotebookFormat.yaml` doesn't escape what that parser treats as structure. Fixing the writer and
the reader together would clear those three rows — eight of the twelve issues.

### Decisions that look like omissions

| Not there | Why, and what would change it |
|---|---|
| **A native `.inspector()`** | Decided in 5.2, not forgotten. On macOS 26 a native inspector is an `NSContainerConcentricGlassEffectView` the window server composites, and `NSView.cacheDisplay` photographs it as a white rectangle — so every screen with one would lose that pane from its shot, and the shots are how this repo checks a layout. Ten screens draw the hand-built pane. Change it when a capture path can see glass, or when the shots compose each screen's inspector the way `console` already composes the list column. `docs/architecture.md` has the full note. |
| **The list column's dragged width isn't restored** | SwiftUI takes `min`/`ideal`/`max` for a split view column and hands back no binding for the width the user dragged it to, so `@SceneStorage` has nothing to store. `Theme.listWidth` is the width it opens at, every launch; whether it is *collapsed* does persist. Reaching into the underlying `NSSplitView` would be inventing a mechanism rather than using one. Revisit if SwiftUI ever exposes the width. |
| **`NonisolatedNonsendingByDefault` is off** | It is not in `Package.swift`. Turning it on compiles clean and the whole suite still passes — which is the problem: it would move `UsageLedger.load`, `AgentUsage.claudeQuota`/`codexQuota` and the usage screen's file-size checks onto the caller's actor, undoing part of D14, and nothing in the suite would fail. Turn it on together with `@concurrent` on those reads and a test that pins them off the main actor, the way `ProjectModelTests` pins the notebook read. |
| **`MemberImportVisibility` is off** | 77 errors across 6 files, almost all "missing import of defining module `os`" from `Log`'s interpolations. It is a tidy-up with no behaviour attached, so it waits for a PR that has nothing else in it. |
| **Colours are fixed sRGB, not dynamic** | D16 asked for `NSColor(name:dynamicProvider:)`. `RootView` pins `.preferredColorScheme(.dark)`, so a dynamic colour would only ever run its dark branch, and there is no light palette for the other one. It arrives with the palette that gives it something to return. |
| **Nine edge tokens across 0x1C–0x2B** | A ramp, not a system, unlike the type scale beside it. Collapsing them to three or four is a value change plus renames, and belongs in the palette PR with its own before/after shots. The `ponytail:` marker over `Theme`'s Edges section says so. |
| **Phase 6: signing, notarization, updates** | Not started, and waiting on a person rather than on work: the first tester on another Mac. Without notarization Gatekeeper blocks the app on anyone else's machine, so the trigger and the work arrive together. |

### Still deferred, as originally planned

| Deferred | Add when |
|---|---|
| **Hosted CI (GitHub Actions)** | A second person pushes, or release builds should be made off this machine. |
| **Direct argv launch + resolved login-shell environment** (instead of `zsh -ilc`) | Session start is measurably slow (over 1 s from a heavy `.zshrc`), or a tester on bash or fish whose PATH isn't found. |
| **Settings window (⌘,)** | There is more to configure than the provider picker already in the toolbar, e.g. CLI path overrides for testers. |
| **First-run CLI detection** | The first tester: "clicked, nothing happened" only bites someone who didn't write the app. |
| **Full VoiceOver audit** | Testers, or anyone who relies on it. The basic labels landed in 5.3. |
| **Light theme** | Tokens make it cheap now. Add it if you want it. |
| **Localization (String Catalogs)** | A non-English user. Until then, avoid string concatenation in new user-facing text. |
| **More Swift modules** | A folder in Core gains a second real consumer, such as a CLI companion. |
| **Snapshot-diff testing** | Comparing shots by eye stops catching regressions. |
| **Multi-window** | You want two projects side by side. `Route` per window makes it straightforward, but `AppModel` and its `TerminalRegistry` are app-wide today, which is also why File → New Window is dropped. |
| **Mac App Store build** | Never, as long as the app spawns user CLIs (sandbox). |
| **Plugin or runtime provider loading** | Never; compile-time `AgentProvider` is enough. |

### If you open-source it later

None of this is needed now, and the refactor kept each step cheap:

1. **Pick a license.** MIT matches SwiftTerm and is the most common among Mac OSS apps;
   Apache-2.0 if patent terms matter.
2. **Scan the full history for secrets** (`gitleaks detect --log-opts="--all"`) before the
   history becomes public.
3. **Write a landing-page README:** hero screenshot or GIF, install line, a supported-agents
   matrix, and a privacy and safety section (what the app writes to your folder, no telemetry,
   deny-commit flags aren't a sandbox).
4. **Add community files:** `CONTRIBUTING.md` (can grow from `docs/development.md`),
   `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue templates, a PR template.
5. **Turn on hosted CI**, free for public repos, running `make check`.
6. **Set up public distribution:** Phase 6 in full plus a Homebrew tap.
7. **Choose the launch moment:** flip the repo public together with a notarized release, never
   before. You get one first impression.

The refactor already did the expensive parts: the docs split, `Skills/` as visible product
source, fixture tests, one folder per provider, and a single check command.

---

## 9. The open questions, and their answers

1. **Who runs it, and when?** Still only the author. That is why Phase 6 and the Apple Developer
   Program are not on the roadmap yet — D9 stages the work by audience, and the first audience
   hasn't arrived.
2. **Bundle ID.** Answered in Phase 2: **`ai.yongkang.Yongkang`**, not the
   `io.github.jstinhw.Yongkang` the plan guessed at. `DefaultsMigration` carries the old domain's
   settings over once.
3. **Silent `git init`.** Unchanged: Review still runs `git init` in a notebook project that
   isn't a repo, with nothing staged or committed. It is documented in
   [`docs/guide/review.md`](guide/review.md), and a one-time confirmation may be friendlier once
   testers point it at their own folders. That is a behaviour change, so it stays outside the
   refactor.
