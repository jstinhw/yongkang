# Yongkang

A macOS console that runs a team of agent CLIs (`claude`, `codex`, `grok`, `agy`) in real
PTYs against a project's `.notebook/` folder, and reviews the changes they leave behind.

A Swift package holds all the code, with a thin Xcode project that builds the app. macOS 14+,
two dependencies (SwiftTerm, and Sparkle for updates). Tests are Swift Testing, one file per
domain.

`CLAUDE.md` is a symlink to this file. Edit `AGENTS.md`.

## Layout

- **`Sources/YongkangCore/`**: the logic, Foundation only. `Notebook/`, `Project/`,
  `Providers/` (the `AgentProvider` protocol, and one folder per CLI: `ClaudeCode/`, `Codex/`,
  `Grok/`, `Agy/`), `Git/`, `Review/`, `Services/`, `Skills/`, `Shell/`, `Prompts/`, `Usage/`,
  `Watching/` (the FSEvents watcher and the per-project reader), `Diagnostics/` (`Log`).
- **`Sources/YongkangUI/`**: SwiftUI, AppKit and SwiftTerm. `Model/` (`AppModel` and one
  `ProjectModel` per open project, the `@Observable` state every screen reads, with the
  workflows in `ProjectModel+<concern>.swift` returning where the window goes, and anything
  that has to ask or tell the user set as `AppModel.alert` rather than run modally), `App/`
  (`YongkangApp`, `RootView`, the rail and the list column), `Terminal/`, `DesignSystem/`,
  `Online/` (updates, sign-in, analytics: the only code that talks to a server), and
  `Features/<screen>/`.
- **The window is the rail, then an `HSplitView`.** The 64pt icon rail is drawn outside the
  split view; the list column is its first pane, the screen its second, and what
  used to be a hand-built 56pt bar above the screen is the window's own toolbar
  (`RootView+Toolbar.swift`, with `.navigationTitle`/`.navigationSubtitle`). Nothing adds
  column widths up any more — a pane's geometry is its container's.
  [`docs/architecture.md`](docs/architecture.md#how-the-window-is-composed) says why.
- **An app-wide shortcut is a menu item** (`App/Commands.swift`), never a button's
  `.keyboardShortcut`: a button's only answers while that button is drawn. An item that
  cannot act is disabled, not hidden. A shortcut that means nothing off its own screen stays
  there — ⌘S in the notebook editor, a sheet's default and cancel actions.
  [`docs/architecture.md`](docs/architecture.md#the-menu-bar) has the tree and its rules.
- **`App/`**: the thin Xcode shell that builds `Yongkang.app` (bundle ID `ai.yongkang.Yongkang`).
  `Yongkang/main.swift` only calls `YongkangMain.run()`; the rest is assets, entitlements and
  `Config/Signing.xcconfig`. Its sources are a synchronized folder, so adding a file never
  touches `project.pbxproj`.
- **`Sources/Shots/`**: dev-only, renders every screen offscreen. Never part of the app.
- **`Tests/YongkangCoreTests/`**: tests of Core, with each provider's tests under
  `Providers/<provider>/` and captured CLI output under `Fixtures/<cli>/`.
- **`Tests/YongkangUITests/`**: tests that need a view, the terminal, a SwiftUI colour or
  the models. They read the same `Fixtures/`.

## Commands

```sh
make check                                  # format lint + build + test: the definition of done
make format                                 # fix what the lint step complains about
swift test --filter UsageTests              # one suite while you work
swift test --filter UsageTests/shortCount   # one test
swift test --filter YongkangCoreTests       # one test target
swift run shots <dir>                       # render every screen offscreen to <dir>/*.png
make icon                                   # redraw the app icon's 1024 master
make run                                    # debug build of the app, then open it
make archive                                # signed Release build in .build/xcode
make release                                # Developer ID, notarized dmg (CI runs it on a v* tag)
make help                                   # every target
```

- `make check` also runs as a `pre-push` hook (`git config core.hooksPath .githooks`, once
  per clone).
- `swift run shots` is how you see a UI or structural change without launching the app.
  Render into two folders, one before your change and one after, and compare them.
  `review.png`, `handover.png` and `usage.png` read live git or the clock, so they differ on
  every commit — which is why `docs/images/` holds only the nine fixture-drawn shots the guide
  pages point at, and those three are not among them.
- **The shots have no title bar.** They are drawn into an offscreen window, so the toolbar, the
  window title and subtitle, and the menu bar do not appear in one. Those are checked by running
  the app, which is what the smoke script in
  [`docs/development.md`](docs/development.md#manual-smoke-script) is for.
- `make icon` redraws `App/Yongkang/Assets.xcassets/AppIcon.appiconset/icon-1024.png` from
  `DesignSystem/AppIcon.swift`, through the same shots binary. The PNG is a build artefact,
  not artwork: change the view, run the command, commit both. See
  [`docs/development.md`](docs/development.md#the-app-icon).
- `make run` refuses while Yongkang is running (`ai.yongkang.Yongkang`, or the old
  `local.yongkang.app`) instead of quitting it: that would end every agent session inside
  it. The user's copy is usually running, so don't launch or `open` a built app unless
  you've been asked to.
- Building the app needs Xcode; `make check` needs only the Swift toolchain.
- The shipped role skills live in `Skills/` (product source, the prompts the app's agents run);
  `.claude/skills` and `.agents/skills` are symlinks to it. Only the app bundle carries them
  (`Contents/Resources/skills`, copied by a build phase on every build).

## Definition of done

A handoff needs all of these:

1. `make check` passes. A `withKnownIssue` is a recorded bug, not a pass to copy.
2. For any UI or structural change, you rendered shots before and after and compared them.
   Say what changed on screen, or that nothing did.

## Rules

- **YongkangCore imports Foundation only.** If you need SwiftUI, the code belongs in
  YongkangUI. A colour for a Core type is an extension there, like `ReviewArea+Color.swift`.
- **`package`, never `public`,** for what one target uses from another. A struct that
  another target builds needs an explicit `package init`: the synthesized memberwise one is
  internal. The one `public` is `YongkangMain`, because Xcode builds the app target without
  the package's `-package-name`.
- **The `.notebook/` format is a contract.** Never change it without updating
  `NotebookFormat.specText`, `docs/notebook-format.md` and the tests that cover it.
- **Design before SwiftUI.** UI or design work goes through Claude Code's native `/design`
  skill (a design canvas) before any SwiftUI is written. Don't use the gstack `design-*`
  skills for this, and shots don't count as a design step.
- **Review opens on outcomes.** A review screen shows the task, how the agent checked it and what the
  agents did first. The diff is one click away.
- **No file over 800 lines.**
- **The notebook files are the only state.** The app never writes what agents write, and
  it never commits unless the user approves in Review.
- **Only `Online/` talks to a server,** and an analytics event says only that something
  happened: an agent's kind or a count, never a path, a name, a prompt or a file's contents.
  [`docs/release.md`](docs/release.md#what-goes-online) lists every event; a new one goes there.
- **Keep the comment culture.** Comments explain *why*. `ponytail:` markers name a
  deliberate ceiling and what to do when it's hit.
- **Use `git mv` for moves,** in a commit of its own, separate from any edits.

## More

- `docs/architecture.md`: how a project is read, what the diagnostics log, how the window is
  composed, the menu tree, what a relaunch restores, and the rules a terminal's lifetime obeys.
  Read it before changing any of those.
- `docs/development.md`: the manual smoke script, capturing CLI fixtures, the app icon, and the
  local signing identity.
- `docs/release.md`: versions, cutting a release, the update feed, what goes online, and the
  one-time accounts and secrets.
- `docs/providers.md`: the `AgentProvider` protocol, where fixtures go, and the checklist for
  adding a CLI.
- `docs/refactor-plan.md`: the record of the refactor that gave the repo this shape — the
  decisions, and §8, what is deliberately not there and what would bring it back. Describe what
  exists, not what's planned.
