# Yongkang refactor plan

**Goal:** make Yongkang a well-organised, fast, polished macOS app that is cheap to change,
for you and for the coding agents that build it. It stays a **private project** for now, but
nothing in this plan makes opening it up later harder.

**Written:** 2026-09-15, against `main` @ `69c4bc0`. Revised the same day: private in the
short term, so the open-source work moves to §8.

---

## 0. The short version

Yongkang's product thinking is strong. The problems are one god object, work running on the
main thread, test code shipped inside the app, and a build that can't produce a shareable
`.app`. The plan keeps the behaviour, the `.notebook/` format and the "the app keeps no state
of its own" principle. It changes how the code is organised, built and verified.

**Why "private" doesn't shrink the plan much:** the repo's main contributors are already
coding agents working in parallel (Conductor worktrees, the lead's specialists). Parallel
agents need what outside contributors need: small files, one obvious place for each change,
one command to verify, and instructions in the repo. What *does* drop out is everything
aimed at strangers: license, community files, a marketing README, public release channels
and a launch.

The decisions that shape everything else:

1. **Fix the default branch.** Keep the README as a short entry point, move the design journal into `docs/`, and add an `AGENTS.md`.
2. **Move the 1,786-line self-test into Swift Testing *before* touching any code.** The ~460 existing checks are the safety net for everything after.
3. **Split into two layers: `YongkangCore` (Foundation only) and `YongkangUI` (SwiftUI), plus a thin Xcode app shell.** One module boundary where it pays off, not ten.
4. **Replace `App.swift`'s 20 `@State` vars and string-typed selection with `@Observable` models and a typed `Route` enum.** Raise the minimum OS to macOS 14.
5. **Take process lifetime out of SwiftUI.** A `TerminalRegistry` owns the PTYs, so views only display them.
6. **Move all file, git and transcript I/O off the main thread.** Drive refreshes from FSEvents instead of a 2 s timer.
7. **Give each agent CLI one `AgentProvider` folder.** Adding Grok and Agy touched 8 files; the next CLI should touch one folder.
8. **Make it a proper Mac app:** menu bar commands, consistent design tokens, and a signed, notarized build only once someone other than you runs it.

---

## 1. Where the repo is today

Every number below was measured on `69c4bc0`.

### Repository

| Finding | Evidence | Why it matters |
|---|---|---|
| GitHub's default branch `notebooks` is **44 commits behind** `main` | `git rev-list --count origin/notebooks..main` | Tools that branch from the default (Conductor workspaces, `gh pr create`) start from 44-commit-old code. The `review-summary-graph-diff` worktree is based on `d6d5042`. |
| README is 21 KB and reads as a design journal | `README.md` | Excellent material, but a 21 KB file is costly context for every agent that reads it to find the build command, and there's no quick "build, run, test, where things are" section. |
| No `AGENTS.md` or `CLAUDE.md` | repo root | Agents working on Yongkang rediscover the build commands, the test flag and the design rules every session. The `/design`-first rule lives only in local memory. |
| The app's shipped role skills live in `.claude/skills/`, a dev-tool folder | `make-app.sh` copies them into the bundle | Product source (prompt code) is mixed up with dev config: your own Claude Code sessions in this repo load the app's roles as dev skills. |

### Build and config

| Finding | Evidence | Why it matters |
|---|---|---|
| The `.app` bundle is assembled by a shell script, with an inline Info.plist | `make-app.sh` | No app icon, no entitlements, no hardened runtime, no notarization path, no update path. |
| Bundle ID `local.yongkang.app`, version `0.1` hard-coded | `make-app.sh` | The version isn't tied to git, so you can't tell which build is running. |
| `swift-tools-version: 5.9`, macOS 13, while the toolchain is Swift 6.3.1 | `Package.swift` | No strict concurrency checking, and no Observation framework. |
| No formatter, no linter, no single "check" command | repo root | Nothing verifies an agent's handoff except whoever remembers `swift run Yongkang --selftest`. |

### Code

| Finding | Evidence | Why it matters |
|---|---|---|
| **One flat target:** 55 files, 15,160 lines | `Sources/Yongkang/` | No enforced boundary between parsing logic and views. |
| **`App.swift` is a 1,421-line god object**: 20 `@State` + 4 `@AppStorage`, ~80 methods covering navigation, sessions, assignment, git, review, product flows, polling and a self-test | `App.swift` | Every feature touches this file, so parallel agents collide on it. It is also well past your 800-line limit. |
| **Selection is `String?` in 15 hand-parsed prefix formats** (`review-task:<uuid>:<id>`, `subagent:<uuid>:<id>`, a bare UUID for sessions, …) | `Tags.swift`, `App.swift` | A typo compiles fine and silently shows the "Nothing selected" pane. |
| **The test suite ships inside the app binary:** `NotebookSelfTest.swift` (1,786 lines, ~460 `precondition`s), `DesignShots.swift` (531 lines), and `--attention-selftest` in `App.swift` (uses `try!` and writes to `/tmp`) | `App.swift:70-80`, `:880-917` | A precondition stops at the first failure and there are no per-test results. |
| **A 2 s main-thread timer does synchronous I/O**: it walks every project's notebook, parses frontmatter, scans `~/.codex/sessions`, reads and writes `usage.json`, and every 6 s spawns **up to 8 blocking `git` processes** | `App.swift:1016-1061`, `GitChanges.swift` | UI hitches in large repos, plus constant CPU and battery use while idle. |
| Every untracked file is **read in full** to count lines on each git refresh | `GitChanges.lineCount` | A fresh project with no `.gitignore` and a `node_modules/` will freeze the window every 6 s. |
| I/O reachable from view bodies: `previewStep` → `Service.plan` reads `package.json` and compose files. `ChangeSummary.of` is recomputed at 13 call sites | `App.swift:491`, `:1000` | Re-renders pay for file reads and repeated derivation. |
| **PTY lifetime is tied to SwiftUI view identity**: terminals are kept alive in a `ZStack` at `opacity(0)`, positioned with `railWidth + listWidth` padding math. Text reaches a terminal through a `pendingInput` binding round-trip, with a guard against double-sending | `App.swift:165-186`, `AgentTerminal.swift:174-207` | Fragile. A layout change or view-identity change can kill a running agent. |
| **Provider logic is scattered.** Adding Grok and Agy touched 8 files. `ClaudeTranscripts` lives in `SubagentActivity.swift`; `AgentKind`, `AgentCommand` and `BundledSkills` live in the terminal *view* file | `git show --stat fb13f1e` | Every new CLI or CLI format change is a hunt across the codebase. |
| Global mutable static caches | `CodexTranscripts` (4), `AgentUsage.files`, `DemoPages` (2) | Hard errors under Swift 6 mode, and real data races once I/O moves off the main thread. |
| UI mixed into domain code | `AgentUsage.tint/modelTint/palette` return `SwiftUI.Color` | Blocks a Foundation-only core. |
| 10 `NSAlert.runModal()` calls from logic code | `App.swift` (8), `NotebookEditor.swift` (2) | Blocks the main run loop, including terminal rendering, and can't be tested. |
| Design tokens exist, but 38 hex literals are spread over 12 files, there are ~19 distinct font sizes, and custom fonts are used only "if installed" | `Theme.swift` and others | The look isn't fully systematic, and it differs on any Mac without those three fonts. |
| No menu bar commands. ⌘N and ⌘O only work while the home screen is visible. **⌘[ is advertised in the README and a tooltip but isn't implemented** | `grep keyboardShortcut` | Shortcuts that depend on which view is on screen feel broken; the menu bar is how a Mac app exposes them. |

**Strengths to protect (these become invariants in `docs/architecture.md`):**
- The notebook files are the only state. The app never writes what agents write, and it never commits unless the user approves.
- The comments explain *why*, and `ponytail:` markers name deliberate ceilings.
- `--shots` renders every screen offscreen, which is a rare and valuable review tool.
- Fixture-grade coverage of real CLI output formats (Codex trust screen bytes, transcript layouts).

---

## 2. Goals and non-goals

**Goals**, each measurable:
1. **Cheap to change:** a feature lives in its own folder, no file is over 800 lines, and the app entry point is about 30 lines.
2. **Safe to change:** `make check` (format lint + build + test) is the definition of done for you and for every agent handoff.
3. **Fast and quiet:** no git or file I/O on the main thread, and idle CPU under 1% with a live lead.
4. **Polished:** menu bar commands, one set of design tokens, and native behaviour where the platform already has it.
5. **Agent-friendly:** `AGENTS.md`, one check command, and fixture-based parser tests, so an agent can fix a CLI format change without being told how.
6. **Open-source-ready later, at no extra cost now:** nothing in the refactor blocks going public, and §8 holds the checklist.

**Non-goals**, and why:
- **No open-sourcing in the short term.** No license, no community files, no public release channels, no launch. See §8 for what it would take later.
- **No rewrite.** 15k lines of working, well-reasoned code; every phase below moves or wraps existing code.
- **No change to the `.notebook/` format or product behaviour.** Your projects depend on it, and it isn't the problem.
- **No Mac App Store.** The app has to spawn arbitrary CLIs and read `~/.claude`, `~/.codex` and `~/.grok`, and the sandbox forbids that.
- **No distribution work before there's a second user.** Signing, notarization and updates wait until someone else runs the app (D9).

---

## 3. Principles for the refactor

1. **Tests before moves.** Nothing is restructured until the existing checks run under `swift test`.
2. **Behaviour-preserving phases.** Each phase ends with the same screenshots (`make shots`, compared before and after) and `make check` green.
3. **One boundary, enforced by the compiler.** Logic can't import SwiftUI. Everything else is organised with folders, not modules.
4. **Native first.** Before writing a component, check whether AppKit or SwiftUI already has one (commands, alerts, inspector, split view).
5. **`git mv` for moves, separate from edits.** Moving a file and changing it in the same commit destroys `git blame` and makes review impossible.
6. **Design changes go through `/design` first.** This is an existing project rule. The plan picks *where* native chrome is worth evaluating, and the canvas decides *what it looks like*.
7. **Keep the "why" comment culture.** Docs and code comments should keep explaining intent.

---

## 4. Decisions

Each decision lists what it is, why, what was rejected, and its cost.

### Repository and docs

#### D1 — Default branch `main`; the repo stays private

- **Why:** GitHub's default `notebooks` is 44 commits stale. Anything that branches from the default (Conductor workspaces, `gh pr create`, a fresh clone on another Mac) starts from old code, and PRs target the wrong base.
- **Steps:** push `main`, switch the GitHub default to `main`, and delete or archive the stale `notebooks` and `origin/main` branches once nothing depends on them.
- **Not now:** a secret scan of the full history. It only matters before the history becomes visible to someone else, so it's in the §8 checklist.

#### D2 — Short README; the design journal moves to `docs/`

- **Why:** the README is what you, an agent, or a future tester opens first. Today it's 21 KB of design rationale before you find how to build. Split, the entry point is quick and the reasoning stays intact and easier to navigate by topic.
- **New README, about 60 lines:**
  1. One-line description and one screenshot (from `make shots`).
  2. Requirements: macOS 14+, and at least one of Claude Code, Codex, Grok or Agy on PATH.
  3. Build, run, test: `make run`, `make check`, `make shots`.
  4. A short "how it works" paragraph (the notebook is the state), plus the existing mermaid flowchart.
  5. A map of `docs/`.
- **`docs/` receives the current sections nearly verbatim:** `guide/{projects,notebook,board,design-gate,product,engineering-lead,team,review,blocks}.md`, plus `notebook-format.md` (the spec, generated from `NotebookFormat.specText` so it can't drift), `providers.md`, `architecture.md` and `development.md`.
- **Rejected:** a marketing-style landing README with badges and a hero GIF. It has no audience while the repo is private. It's in §8.

#### D3 — `AGENTS.md` (with `CLAUDE.md` symlinked to it) and `docs/development.md`

- **Why `AGENTS.md`:** agents are the main contributors to this repo. One auto-loaded file cuts wrong guesses and repeated exploration. It holds:
  - The commands: `make check`, `make run`, `make shots`.
  - The Core/UI import rule.
  - "Never change the `.notebook` format without updating the spec test."
  - The `/design`-first rule for UI work.
  - "Review opens on outcomes before diffs."
  - "No file over 800 lines."
- **Why the symlink:** Codex reads `AGENTS.md` and Claude Code reads `CLAUDE.md`; one file keeps them from drifting. This is the same trick `.agents/skills` already uses.
- **Why `docs/development.md`:** the details that are too long for `AGENTS.md`:
  - The manual smoke script: open folder → intake → assign → subagent Check → block → approve.
  - How to capture a CLI fixture.
  - The stable local signing identity (currently a comment in `make-app.sh`).
  - How to add a provider.
- **Rejected:** `CONTRIBUTING.md`, `SECURITY.md`, `CODE_OF_CONDUCT.md` and issue or PR templates. They're for outside contributors, so they move to §8.

#### D4 — Shipped skills move to top-level `Skills/`

- **Why:** the 9 role skills (925 lines) are *product source*. They're the prompt code that decides how the lead, QA and designer behave, and probably the most-tuned files in the repo. In `.claude/skills/` they look like dev config, and your own agents working on Yongkang load them as dev skills.
- **How:** `git mv .claude/skills Skills`. Keep `.claude/skills` and `.agents/skills` as **symlinks** so dogfooding and dev-build native discovery still work. Bundle `Skills/` as a resource, which replaces the `cp -R` step in `make-app.sh`.
- **Rejected:** a separate skills repo, because versions would drift from the app that embeds them.

### Build and config

#### D5 — Thin Xcode app shell plus a Swift package that holds all code

```
Package.swift            ← unchanged location; `swift build` / `swift test` still work
App/Yongkang.xcodeproj   ← one app target, ~4 files that rarely change
App/Yongkang/            ← main.swift (one call), Assets.xcassets, .entitlements; Info.plist generated from build settings
```

- **Why an Xcode project at all:** an app icon from an asset catalog, entitlements plus hardened runtime, Archive and notarize, and (later) embedding and signing Sparkle are all automatic in Xcode and fragile to script. `make-app.sh` already can't do any of them.
- **Why a *thin* one:** all code stays in the package. **Parallel agent worktrees have the same `project.pbxproj` merge-conflict problem that many contributors do.** With Xcode 16+ synchronized folders and all sources in the package, adding files never touches the project file. `swift build` and `swift test` keep working with only the Command Line Tools.
- **Why `App/` rather than the root:** `Package.swift` stays put, so every existing command and path keeps working. Minimal churn.
- **Rejected:**
  - Pure SPM plus a longer script: the icon, entitlements and notarization would all be hand-rolled.
  - XcodeGen or Tuist: one more tool to install and pin, for a single target.
  - Moving everything into Xcode: the CLI test loop would be lost and every file add would conflict across worktrees.
- **Timing:** Phase 2. It's cheap alongside the target split, and needed for the icon in Phase 5.

#### D6 — Swift 6 tools, macOS 14 minimum, strict concurrency staged

- **`swift-tools-version: 6.0`** now, with `swiftLanguageModes: [.v5]` on the UI target at first. Core gets `.v6` as soon as its static caches are fixed (Phase 4). Phase 4 moves I/O off the main thread, which is exactly when data races start. Swift 6 mode turns those races into compile errors before they show up as crashes.
- **macOS 14 (Sonoma)** unlocks:
  - `@Observable` (D11). It replaces the whole `@State` soup with fine-grained invalidation.
  - `.inspector()`, a native inspector column (D17).
  - Two-parameter `onChange`; the current single-parameter form is deprecated.
  - For a private app the only user today is you, on macOS 26, so the bump costs nothing.
- **Rejected:**
  - Staying on 13: Observation isn't available, so the state refactor would need `ObservableObject`, whose coarse invalidation is what we're fixing.
  - Going to 15 or later: nothing here needs it, and it would narrow future testers for no reason.

#### D7 — A Makefile replaces `make-app.sh`

```
make run      # debug build of the app + open it
make check    # swift format lint + swift build + swift test  ← the definition of done
make shots    # swift run shots docs/images
make format   # swift format -i -r Sources Tests
make archive  # signed Release build (used once D9 applies)
```

- **Why Make:** it ships with the Command Line Tools, `make help` makes it discoverable, and it gives you and agents one entry point. `AGENTS.md` can say "run `make check`" instead of explaining four commands.
- **Signing:** a single committed `App/Config/Signing.xcconfig`. The current "stable self-signed identity so TCC approval sticks" trick carries over and moves into `docs/development.md`.
- **Rejected:** a gitignored `Local.xcconfig` for the Team ID. That solves an outside-contributor problem; for a private repo, committing it is simpler. A Team ID isn't secret; it's printed in every signed binary.

#### D8 — `swift format` plus a local check instead of hosted CI (for now)

- **Formatter: `swift format`**, which ships in the Swift 6 toolchain.
  - **Why this one:** zero install, Apple-maintained, works in every worktree.
  - Configure `.swift-format` to match the current style (4-space indent, ~110-column lines) so the one-time reformat is small. Put that commit's hash in **`.git-blame-ignore-revs`** so `git blame` still shows the real history.
  - **Rejected:** SwiftLint and Nick Lockwood's SwiftFormat. Both are good, but both add a Homebrew dependency and a version to pin.
- **Verification: `make check` locally, required by `AGENTS.md` before any handoff, plus a `pre-push` hook.**
  - **Why not GitHub Actions now:** hosted macOS runner minutes on *private* repos count against your plan at a high multiplier (check current pricing), and a solo private repo gets little from a remote check that `make check` doesn't already give.
  - **Add a workflow when:** a second person pushes to the repo, or you want archived release builds made off your machine. The same `make check` becomes its only step.
- **Shots:** `make shots` locally before and after any structural or UI change.

#### D9 — Distribution: stage it by audience

| Stage | What's needed | Why |
|---|---|---|
| **Now: only you** | `make run` / `make archive` with the existing stable self-signed identity. | TCC approval already sticks with that identity. Notarization, updates and installers have no user yet. |
| **First tester on another Mac** | Apple Developer Program, **Developer ID** signing with hardened runtime, `xcrun notarytool` + staple, a DMG. | Without notarization, Gatekeeper blocks the app on anyone else's Mac. Hardened runtime needs **no** exception entitlements (child processes, WebKit and UserNotifications all work under it). Keep it that way. |
| **Several testers** | **Sparkle 2** with an EdDSA-signed appcast, and the DMG and appcast on a **public static host** (an S3 or R2 bucket, or a separate public releases-only repo). SemVer tags; `MARKETING_VERSION` set from the tag. | Parsers that follow fast-moving CLI formats need fast updates. **Release assets on a private GitHub repo can't be downloaded without authentication**, so Sparkle can't fetch them. The binaries have to live somewhere public even while the source stays private. |

- **Bundle ID:** change `local.yongkang.app` to a reverse-DNS name you control, such as `io.github.jstinhw.Yongkang`, **in Phase 2 with the Xcode shell.** Changing it resets UserDefaults, TCC grants and notification permission, so do it while you're the only person it affects.
- **Bundle ID migration:** on first launch, read the old domain with `UserDefaults(suiteName: "local.yongkang.app")` to carry over `openProjects`, `listWidth`, `listHidden` and `agentKind`. It's about 10 lines and runs once.
- **Rejected for now:** a Homebrew cask. It needs a publicly downloadable artifact and mostly helps discovery, which isn't a goal yet.

### Code architecture

#### D10 — Migrate the self-test to Swift Testing first, with fixture files

- **Why first:** the ~460 checks in `NotebookSelfTest.swift` are the only safety net for a refactor that moves every file. They have to run under `swift test` before anything moves.
- **Why Swift Testing over XCTest:**
  - It ships with the toolchain.
  - `@Test(arguments:)` fits the many table-shaped checks (slug cases, compose layouts, prompt quoting).
  - `#expect` captures the expression on failure.
  - Tests run in parallel.
  - It reports *all* failures, whereas today the first precondition kills the run.
- **Fixtures:** the captured Codex trust-screen ANSI bytes, the sample Claude, Codex and Grok JSONL transcripts, and the compose and `package.json` samples move from inline strings to `Tests/YongkangCoreTests/Fixtures/<provider>/…`.
  - **Why:** the CLIs change their formats often. With fixture files, "Codex 0.160 changed rollouts" becomes: add one file, fix one parser. An agent can do that unprompted, and the fixture folder records which CLI versions are supported.
  - **Trust boundary:** these parsers read files written by agents and third-party CLIs, so the fixtures must include **malformed inputs** (truncated JSONL, frontmatter with injected newlines, `../` paths in run records). `LeadCoordination.safePath` and `safeID` show this was already considered; the tests should lock it in.
- **Split by domain**, each file under 400 lines: `NotebookFormatTests`, `NotebookIndexTests`, `BlocksTests`, `TeamTests`, `LeadCoordinationTests`, `ChangeSummaryTests`, `ServiceTests`, `SkillsTests`, `AgentCommandTests`, `AttentionPromptTests`, and `Providers/{Claude,Codex,Grok}TranscriptTests`.
- **Network test:** the `SELFTEST_REMOTE` clone check becomes `@Test(.enabled(if: env["YK_NETWORK_TESTS"] != nil))`.
- **`--attention-selftest`:** its logic half (PTY bytes to an attention reason) is already covered in the self-test. Its app-state half (banner, then navigate) becomes a plain model test once D11 lands. The screenshot moves to Shots. That deletes ~40 lines of `try!` and `/tmp` from the shipping `App.swift`.
- **Rejected:** snapshot-testing libraries. The existing Shots renderer, compared before and after, covers visual review without a new dependency or brittle pixel baselines.

#### D11 — Two library targets, one dev executable, `package` access

```
YongkangCore   Foundation only. Notebook, providers, git, review, services, skills, shell, prompts.
YongkangUI     SwiftUI/AppKit + SwiftTerm. Models, design system, terminal, features.
Shots          dev-only executable: `swift run shots <dir>`. Never in the shipped app.
```

- **Why this split:**
  1. **The compiler enforces the boundary.** Core can't `import SwiftUI`, which permanently fixes problems like `AgentUsage` returning `Color`, and agents can't erode it by accident.
  2. **Core tests run headless** and fast, with no window server.
  3. **SwiftUI Previews work reliably** in a library target.
  4. **Incremental builds get faster**, because editing a view doesn't recompile the parsers.
- **Why `package` access, not `public`:** Swift 5.9's `package` modifier lets targets in the same package see each other without turning every type into public API. It avoids a mass `public` annotation pass, and signals that there's no external API to keep stable.
- **Why not more modules** (`NotebookKit`, `GitKit`, `DesignSystem`, one per feature): at 15k lines, each extra boundary costs access annotations and dependency wiring and buys nothing the folder structure doesn't already give. Split later if a folder grows a real second consumer.
- **Moves that fall out of this:**
  - `AgentKind`, `AgentCommand` and `BundledSkills` leave the terminal view file.
  - `Transcripts` leaves `AgentUsage.swift`.
  - `ClaudeTranscripts` leaves `SubagentActivity.swift`.
  - The prompt builders leave `NotebookFormat` for `Prompts/` (the file is 462 lines, and the two concerns change for different reasons).
  - Colour helpers in `AgentUsage` move to `YongkangUI/DesignSystem`.

#### D12 — State: `@Observable` models, a typed `Route`, workflows that return where to go

Today `YongkangApp` is view, controller, store and test harness at once.

**Target shape:**

```swift
@MainActor @Observable final class AppModel {
    var projects: [ProjectModel]          // persistence via @AppStorage-backed paths, as today
    var navigation = Navigation()         // section + route, one place
    var agent: AgentKind                  // default provider
    var alert: AlertItem?                 // replaces NSAlert.runModal
    let terminals: TerminalRegistry       // D13
}

@MainActor @Observable final class ProjectModel {
    let directory: URL
    private(set) var snapshot: NotebookSnapshot   // immutable value: entries, cards, blocks, team, records
    private(set) var repo: RepoStatus             // changes, head, branch
    var sessions: [CodeSession]
    var reviewDrafts: [String: ReviewDraft]
    var summary: ChangeSummary { ... }            // derived once per snapshot, not 13× per render
}

enum Route: Hashable {
    case overview, board, usage
    case project(String), task(String), page(String)
    case session(UUID, pane: AgentPane), subagent(session: UUID, id: String)
    case block(String), member(String)
    case review(file: String?), reviewTask(String)
    case preview(URL)
}
```

- **Why Observation over `@State` in `App`:** today, every write to `projects[i].sessions[j]` invalidates every view that reads `projects`. A per-project `@Observable` class means a poll that changes project B's cards doesn't re-render project A's terminal pane. It also ends the `projects.firstIndex(where:)` index-chasing that fills `App.swift`.
- **How this fits "never mutate":** the models are the one explicit mutation boundary. The notebook data inside them stays an **immutable value that gets replaced wholesale** (`snapshot = newSnapshot`), which is exactly today's behaviour and why `Equatable` comparisons already guard every assignment.
- **Why a typed `Route`:** `Tags.swift` says selection must be a string so it "survives the 2-second reload that replaces the model wholesale". A `Hashable` enum carrying the same stable IDs (card ID, session UUID, block ID) survives just as well, and the compiler checks it. This removes all 15 prefix formats and the `hasPrefix`/`dropFirst` parsing.
- **Why workflows return a `Route`:**
  - Workflows like `assign`, `startProduct`, `startUnblock`, `requestChanges` and `approveDemo` become `ProjectModel` methods in extension files (`ProjectModel+Assign.swift`, `+Review.swift`, `+Blocks.swift`, `+Product.swift`) that **return the route to open**.
  - Navigation stays in one place, and each workflow becomes a unit test ("assigning to a running lead queues a follow-up and routes to its session") with no view involved.
  - Extension files organise by concern without inventing coordinator or service types, and two agents working on assignment and review no longer edit the same file.
- **Alerts:** use SwiftUI `.alert` and `.confirmationDialog` bound to `AppModel.alert`. The title prompt (`askTitle`, an `NSAlert` with an `NSTextField` accessory) becomes `.alert` with a `TextField`.
  - **Why:** `runModal()` blocks the run loop that renders the terminals and runs the poll, and it can't be tested.
- **The view layer:** a `RootView` switches on `navigation.route` into feature views. `App.swift` shrinks from 1,421 lines to about 30 in the shell, and no file is over 800 lines.
- **Rejected:**
  - **The Composable Architecture:** a large dependency and learning curve, and the app's effects (PTYs, FSEvents) don't need reducers.
  - **A ViewModel per view:** it duplicates what Observation already gives views.
  - **SwiftData or Core Data:** the notebook files *are* the store, by design.

#### D13 — `TerminalRegistry` owns PTY lifetime

- **Problem:** a running agent's process lives inside an `NSView` that SwiftUI creates and may destroy. The code keeps it alive by never unmounting it (a `ZStack` at `opacity(0)` with hard-coded `railWidth + listWidth` padding). It delivers typed input through a binding that `updateNSView` clears asynchronously, with a guard against sending twice.
- **Decision:** a `@MainActor` `TerminalRegistry` creates and owns one `AttentionTerminalView` per session ID. It exposes `start(session)`, `send(_ text:, to:)`, `terminate(_:)`, and attention and exit callbacks into the models. The work area embeds a small `TerminalHost: NSViewRepresentable` that **re-parents** the registry's existing view into its container when visible.
- **Why:**
  - Process lifetime becomes explicit and independent of layout, so a future native split view (D16) can't accidentally kill an agent.
  - `send` becomes a direct call, which deletes the `pendingInput` binding, the `sending` flag and the double-send comment.
  - The padding math disappears.
  - Child-agent picker navigation moves from the representable's coordinator into the registry, where it can be tested with a fake screen.
- **Risk:** confirm that removing a `LocalProcessTerminalView` from its superview doesn't stop its `LocalProcess`, and that the terminal re-lays itself out on re-attach. **Spike this first** (half a day). If re-parenting misbehaves, keep one permanent host view and position it from an anchor preference on the work area instead of hard-coded widths. That's less elegant but still removes the coupling.

#### D14 — I/O off the main thread, event-driven refresh, fewer git processes

- **Step 1, required (fixes the hitching):** the notebook read, transcript scan, usage ledger and git status run in a background `actor ProjectReader` per project. They publish a new `NotebookSnapshot` and `RepoStatus` to the `@MainActor` model only when the value changed, as today. Git goes through an `async` `Process` wrapper with a `terminationHandler`, never `waitUntilExit()` on main.
- **Step 2, FSEvents instead of the 2 s timer:**
  - Watch `<project>/.notebook/`, the project's working tree (for git changes, excluding `.git/objects`), and each live session's transcript folder. Use `FSEventStreamCreate` with file events and about 300 ms of latency so bursts coalesce.
  - Keep a **30 s safety poll**, because FSEvents can drop events (network volumes, sleep) and "the board didn't update" would be a hard bug to reproduce.
  - This revises the existing `ponytail:` note ("poll instead of FSEvents; revisit at thousands of files"). The trigger has arrived in a different form: the cost isn't the notebook tree, it's git and transcript scans on every tick while the Mac is idle.
- **Git:** replace up to 8 processes per refresh with 2: `git status --porcelain=v2 --branch -z` (branch, HEAD and untracked in one call) and `git diff --numstat -z HEAD`. **Stop reading untracked files to count lines on refresh.** Count lazily for rows actually shown, and skip files over 1 MB (show "new file" instead).
- **No I/O in view bodies:** `Service.plan` and `ChangeSummary` are computed in the model when inputs change, and views read stored values.
- **Diagnostics:** swap silent `try?` in readers and parsers for `os.Logger` (subsystem = bundle ID; categories `notebook`, `git`, `terminal`, `providers`). When a parser stops matching a new CLI version, `log show --predicate 'subsystem == "…"'` says why instead of an empty pane. Nothing is logged remotely, and no secrets or prompt bodies are logged.

#### D15 — One `AgentProvider` per CLI

```swift
protocol AgentProvider: Sendable {
    var kind: AgentKind { get }
    func launch(_ request: LaunchRequest) -> Launch            // command line, deny-commit flags, session-id strategy
    func transcriptURL(session: UUID, project: URL) -> URL?
    func subagents(session: UUID, project: URL, taskIDs: [String]) async -> [SubagentStatus]
    func transcript(at url: URL) -> [TranscriptLine]
    func usage(at url: URL) -> [UsageSample]
    func attentionReason(screen: String) -> String?
    var childView: ChildViewNavigation? { get }                // "/tasks", "/subagents", or nil
}
```

`Sources/YongkangCore/Providers/{ClaudeCode,Codex,Grok,Agy}/`, each with its fixtures in `Tests/…/Fixtures/<provider>/`.

- **Why a protocol here, when the plan otherwise avoids abstractions:** it has four implementations today, and you've already added CLIs twice (Codex, then Grok and Agy, which touched 8 files). CLI format changes land per provider too. With the protocol, a new CLI or a format fix is one folder plus fixtures. `AgentKind` stays the persisted identity and gains `var provider: AgentProvider`.
- **Static caches:** the `static var` caches in `CodexTranscripts` and `AgentUsage` become per-provider actor state, which is also what Swift 6 mode requires (D6).
- **Launching stays as it is:** `zsh -ilc` with the quoted command line, which is tested and correct for your setup. See §7 for when to switch to direct launch.
- **Rejected:** runtime plugins or dylibs. There's no stable ABI story and it's a security liability; compile-time is enough.

### Mac polish and design

#### D16 — Menu bar commands and design consolidation

- **`.commands`** (currently none):
  - **File:** New Project ⌘N, Open Folder ⌘O, Close Project, Reveal in Finder.
  - **View:** Overview through Blocks as ⌘1–⌘5, Toggle List ⌘\\, Show Completed.
  - **Go:** All Projects **⌘[** (fixes the documented-but-missing shortcut).
  - **Agent:** New Session, Assign to Lead, Product Review.
  - **Why:** menu items work from any screen, unlike button-bound shortcuts. They make every action discoverable, and they're also what Full Keyboard Access and VoiceOver use.
  - **Landed (5.3)** as `YongkangCommands`, with two readings made explicit: "Assign to Lead" hands over the *selected* task, because the board's ticked batch is that view's own state; and every item that needs a project is disabled, not hidden, on the fleet screen. `docs/architecture.md`, "The menu bar".
- **Accessibility basics:** labels on icon-only buttons (the rail especially), and `.accessibilityElement(children: .combine)` on cards and rows. A full VoiceOver audit waits for testers (§7), but unlabeled icon buttons are cheap to fix now.
  - **Landed (5.3):** the rail's mark, the two label-less toolbar pickers, five icon-only buttons across Fleet, the board, Review and the list column, and the usage chart's bars; `.combine` on the Fleet card, the board card and every list row.
- **Window restoration:** `@SceneStorage` for section and route, so relaunch returns you to where you were. Open projects already persist.
  - **Landed (5.3)**, with the entered project alongside them — section and route mean nothing without it. A route that no longer points at anything opens the section's default rather than an empty screen. The sidebar's dragged width still cannot be stored: SwiftUI exposes no binding for it.
- **Design tokens, mechanical, no visual change:**
  - Move all 38 stray hex literals into `Theme` as named tokens.
  - Collapse ~19 font sizes into about 6 semantic styles (`title`, `headline`, `body`, `caption`, `mono`, `monoCaption`).
  - Define colours as dynamic `NSColor(name:dynamicProvider:)` values.
  - **Why:** the app still looks the same, but a future light theme or high-contrast mode becomes a token change instead of 12 file edits, and new screens can't invent a 20th font size. Components move to `YongkangUI/DesignSystem/`.
- **Evaluate in a `/design` canvas before any code** (project rule):
  1. **Typography:** bundle the three OFL fonts (Space Grotesk, IBM Plex Sans, JetBrains Mono), or commit to SF Pro and SF Mono. Today the look depends on which fonts the Mac has installed.
     *Recommendation: SF Pro and SF Mono,* for native feel, nothing to bundle, and the same look on every Mac.
  2. **Chrome:** keep the custom rail, top bar and inspector, or map them onto `NavigationSplitView` + native toolbar + `.inspector()`. Native brings the standard sidebar toggle, toolbar behaviour, full-screen and resize handling, and VoiceOver structure. Custom keeps the distinctive console identity.
     *Recommendation: native containers styled with the existing dark tokens,* which keeps the identity and gains the platform behaviour. D13 makes either option safe for running terminals.
     **Decided and half-landed (5.2):** the list column is a `NavigationSplitView` sidebar and the top bar is the window's toolbar; the rail stays custom, outside the split view. `.inspector()` is held — on macOS 26 a native inspector is a window-server-composited glass container the shot renderer cannot photograph, so every screen with one would lose that pane from its shot. `docs/architecture.md`, "How the window is composed".
  3. **App icon:** there's no icon today. The Dock, Finder and ⌘-Tab all show a generic app. It needs a 1024 px master in the asset catalog (needs D5).
- **Keep:** the "review outcomes before diffs" layout rule for Review surfaces (existing project rule).

---

## 5. Target layout

```
yongkang/
├── README.md  AGENTS.md  CLAUDE.md → AGENTS.md
├── Makefile  .swift-format  .git-blame-ignore-revs  .gitignore
├── Package.swift                          # tools 6.0; Core, UI, Shots, tests
├── App/                                   # thin Xcode shell
│   ├── Yongkang.xcodeproj
│   ├── Config/Signing.xcconfig
│   └── Yongkang/{main.swift, Assets.xcassets, Yongkang.entitlements}
├── Skills/                                # shipped role skills (source of truth)
│   └── engineering-lead/ product/ designer/ frontend-dev/ backend-dev/ qa-dev/ sre-dev/ fde-dev/ incubate-agent/
├── .claude/skills → ../Skills             # symlinks, for dogfooding
├── .agents/skills → ../Skills
├── docs/
│   ├── images/                            # generated by `make shots`
│   ├── architecture.md  development.md  notebook-format.md  providers.md  refactor-plan.md
│   └── guide/{projects,notebook,board,design-gate,product,engineering-lead,team,review,blocks}.md
├── Sources/
│   ├── YongkangCore/                      # Foundation only
│   │   ├── Notebook/    Format, Loader, Index, Content, Blocks, Team, LeadCoordination, UsageLedger, Snapshot
│   │   ├── Providers/   AgentProvider, AgentKind, ClaudeCode/, Codex/, Grok/, Agy/
│   │   ├── Git/         GitClient (async), RepoStatus, FileChange, Diff
│   │   ├── Review/      ChangeSummary, ReviewArea, ReviewDraft
│   │   ├── Services/    Service detection
│   │   ├── Skills/      Skills, BundledSkills
│   │   ├── Shell/       AgentCommand, AsyncProcess
│   │   ├── Prompts/     onboarding, engineering, product, unblock, incubate, change-request
│   │   └── Watching/    FSEventWatcher, ProjectReader (actor)
│   ├── YongkangUI/                        # SwiftUI + AppKit + SwiftTerm
│   │   ├── App/         AppModel, ProjectModel(+Assign/+Review/+Blocks/+Product), Route, RootView, Commands
│   │   ├── Terminal/    TerminalRegistry, TerminalHost, AttentionTerminalView, ChildAgentPicker, Notifications
│   │   ├── DesignSystem/ Theme, Typography, ButtonStyles, Surfaces, RoleTile, MeterBar, StateDot
│   │   └── Features/    Home/ Overview/ Board/ Agents/ Usage/ Review/ Blocks/ Notebook/ Team/ Demo/ Preview/ Onboarding/
│   └── Shots/                             # dev-only executable
└── Tests/
    ├── YongkangCoreTests/  (+ Fixtures/{claude,codex,grok,compose,notebook}/)
    └── YongkangUITests/    model tests: routes, workflows, attention → navigation (not XCUITest)
```

---

## 6. Phased roadmap

Every phase can ship on its own, is split into reviewable PRs, and ends with `make check` green
and shots compared. Estimates are focused working days for one person; parallel agents
compress Phases 3–5, since the new structure is what lets them work without colliding.

### Phase 0: repo hygiene (½–1 day)

| PR | Content |
|---|---|
| 0.1 | Push `main`, switch the GitHub default branch, retire the stale branches. |
| 0.2 | README split: short README + `docs/guide/*` (content moved, not rewritten). |
| 0.3 | `AGENTS.md` (with `CLAUDE.md` symlink) and `docs/development.md` with today's commands and the smoke script. |

**Exit:** an agent starting in a fresh worktree finds the build, test and design rules without exploring.

### Phase 1: safety net (3–4 days)

| PR | Content |
|---|---|
| 1.1 | `swift-tools-version: 6.0` with `.v5` language mode; add the `YongkangTests` target. |
| 1.2 | Port `NotebookSelfTest` to Swift Testing, by domain, with fixture files. Delete the `--selftest` path. |
| 1.3 | `.swift-format` config, a one-time reformat commit, `.git-blame-ignore-revs`. |
| 1.4 | `make check` (still wrapping `swift` commands, before the Makefile is complete), the `pre-push` hook, and `AGENTS.md` updated to require it. |

**Exit:** `swift test` runs all ported checks green, and no test code ships in the app binary.
**Why this order:** 1.2 before any move means every later PR is checked. 1.3 lands before the moves so later diffs aren't polluted by formatting.

### Phase 2: structure (2–3 days, mostly `git mv`)

| PR | Content |
|---|---|
| 2.1 | Spike: `TerminalHost` re-parenting (D13 risk). Result recorded in `docs/architecture.md`. |
| 2.2 | Create `YongkangCore`, `YongkangUI` and `Shots` targets. `git mv` files into folders. Add `package` access where the compiler asks. Pull the SwiftUI colour helpers out of `AgentUsage`. |
| 2.3 | `git mv .claude/skills Skills` and add the symlinks. Bundle `Skills/` as a resource. |
| 2.4 | Thin Xcode shell in `App/`, the signing xcconfig, and a full Makefile replacing `make-app.sh`. Bundle ID change with the defaults migration. |

**Exit:** Core has no `import SwiftUI`, the shots are pixel-identical to Phase 1's, `make run` works, and your open projects survive the bundle ID change.

### Phase 3: state and lifetime (5–8 days)

| PR | Content |
|---|---|
| 3.1 | Bump minimum to macOS 14. `Route` enum replaces `Tag` and string selection (mechanical, with the old tag tests rewritten against `Route`). |
| 3.2 | `AppModel` / `ProjectModel` (`@Observable`), `NotebookSnapshot` value type. `App.swift` state moves into them. |
| 3.3 | Workflows become `ProjectModel+*` extensions returning a `Route`, each with a model test. |
| 3.4 | `TerminalRegistry` + `TerminalHost`. Delete the `ZStack`/opacity mounting and the `pendingInput` binding. |
| 3.5 | `NSAlert.runModal` → SwiftUI alerts and confirmation dialogs. Port the attention self-test to a model test. |

**Exit:** the app shell is about 30 lines, no file is over 800 lines, there's no stringly-typed selection and no `runModal`, the shots are unchanged, and the smoke script passes.

### Phase 4: performance and correctness (4–6 days)

| PR | Content |
|---|---|
| 4.1 | `AsyncProcess` + `GitClient` using 2 git calls. Lazy untracked line counts with a 1 MB skip. |
| 4.2 | `ProjectReader` actor; all reads off the main thread; no I/O in view bodies. |
| 4.3 | `AgentProvider` protocol, with the four providers moved into their folders and static caches turned into actor state. |
| 4.4 | Swift 6 language mode on Core, then UI. |
| 4.5 | FSEvents watcher with a 30 s safety poll. Delete the 2 s timer. `os.Logger` diagnostics. |

**Exit:**
- **Main-thread check:** Instruments' Time Profiler shows no git or file I/O on the main thread.
- **Idle cost:** with 3 projects open and one live lead, idle CPU is under 1% (measure before and after, and record both numbers in the PR).
- **Large-repo check:** a repo with 20k untracked files no longer hitches the UI.
- Swift 6 mode builds warning-free.

### Phase 5: Mac polish and design (4–7 days, design-dependent)

| PR | Content |
|---|---|
| 5.1 | Token consolidation, no visual change. |
| 5.2 | `/design` canvas for typography, chrome and app icon. Decide, then implement. |
| 5.3 | `.commands` menus (including ⌘[), accessibility labels, `@SceneStorage` restoration. |
| 5.4 | Regenerate `docs/images`; write `docs/architecture.md` and `docs/providers.md`. |

**Exit:** every action is reachable from the menu bar, the app has an icon, and the docs screenshots match the app.

### Phase 6: sharing with testers (only when needed; 2–4 days plus Apple enrollment time)

Triggered by the first person other than you who needs to run the app (D9).

| PR | Content |
|---|---|
| 6.1 | Apple Developer Program; Developer ID certificate and notarytool API key kept in the Keychain (never committed). |
| 6.2 | `make release`: archive, sign, notarize, staple, DMG. |
| 6.3 | When there's more than one tester: Sparkle 2, an appcast and a public static host for the DMG and appcast. |

**Exit:** on a clean Mac, the DMG opens with no Gatekeeper prompt. With Sparkle, the next version arrives by itself.

---

## 7. Risks and mitigations

| Risk | Mitigation |
|---|---|
| The refactor silently changes behaviour the ~460 checks don't cover (navigation, terminal focus, auto-opening Review) | Phase 1 first; shots compared on every structural PR; the smoke script in `docs/development.md`, run at the end of Phases 2, 3 and 4. |
| Re-parenting terminal views breaks PTY or rendering | Spike PR 2.1 before any dependent work; documented fallback (a permanent host positioned by anchor preference). |
| FSEvents misses changes | Keep the 30 s safety poll; manual "Refresh" stays in Review. |
| CLI output formats change under the parsers | Fixture-per-version tests and `os.Logger` diagnostics make the break visible and the fix one folder. |
| The bundle ID change loses your settings or TCC grants | One-time defaults migration; expect macOS to ask for folder access once more. |
| Parallel agents conflict during the moves | Phases are PR-sized and merge to `main` continuously. `git mv` PRs are kept separate, merged quickly, and not run in parallel with feature work. |
| Skipping hosted CI lets a broken `main` slip through | `make check` in the `pre-push` hook and required by `AGENTS.md`; add a workflow as soon as a second person pushes. |

---

## 8. Deliberately deferred

Each item has the trigger that would bring it back.

| Deferred | Add when |
|---|---|
| **Hosted CI (GitHub Actions)** | A second person pushes to the repo, or release builds should be made off your machine. |
| **Direct argv launch + resolved login-shell environment** (instead of `zsh -ilc "<quoted string>"`) | Session start measurably slow (e.g. over 1 s from a heavy `.zshrc`), or a tester on bash or fish whose PATH isn't found. |
| **Settings window (⌘,)** | There's more to configure than the provider picker already in the top bar, e.g. CLI path overrides for testers. |
| **First-run CLI detection** | The first tester: "clicked, nothing happened" only bites someone who didn't write the app. |
| **Full VoiceOver audit** | Testers, or anyone who relies on it. The basic labels are in Phase 5. |
| Light theme | Tokens make it cheap after Phase 5. Add it if you want it. |
| Localization (String Catalogs) | A non-English user. Until then, avoid string concatenation in new user-facing text. |
| More Swift modules | A folder in Core gains a second real consumer, such as a CLI companion. |
| Snapshot-diff testing | Comparing shots by eye stops catching regressions. |
| Multi-window | You want two projects side by side. `Route` per window makes it straightforward. |
| Mac App Store build | Never, as long as the app spawns user CLIs (sandbox). |
| Plugin or runtime provider loading | Never; compile-time `AgentProvider` is enough. |

### If you open-source it later

None of this is needed now, and the refactor keeps each step cheap:

1. **Pick a license.** MIT matches SwiftTerm and is the most common among Mac OSS apps; Apache-2.0 if patent terms matter.
2. **Scan the full history for secrets** (`gitleaks detect --log-opts="--all"`) before the history becomes public.
3. **Write a landing-page README:** hero screenshot or GIF, install line, a supported-agents matrix, and a privacy and safety section (what the app writes to your folder, no telemetry, deny-commit flags aren't a sandbox).
4. **Add community files:** `CONTRIBUTING.md` (can grow from `docs/development.md`), `SECURITY.md`, `CODE_OF_CONDUCT.md`, issue templates (bug, with CLI version; provider request), and a PR template.
5. **Turn on hosted CI**, which is free for public repos, running `make check` and uploading shots as an artifact.
6. **Set up public distribution:** Phase 6 in full plus a Homebrew tap, and `homebrew/cask` once the repo meets its notability bar.
7. **Choose the launch moment:** flip the repo public together with a notarized release, never before. You get one first impression.

The refactor already does the expensive parts: the docs split, `Skills/` as visible product
source, fixture tests, one folder per provider, and a single check command.

---

## 9. Open questions

1. **Who runs it, and when?** Only you for the foreseeable future, or a few testers soon? This decides whether Phase 6 and the Apple Developer Program ($99/yr) are on the roadmap at all.
2. **Bundle ID:** `io.github.jstinhw.Yongkang`, or a domain you own? It changes in Phase 2.
3. **Silent `git init`:** Review runs `git init` in a notebook project that isn't a repo. It's documented, but a one-time confirmation may be friendlier once testers point it at their own folders. This is a behaviour change, so it's outside the refactor unless you want it.
