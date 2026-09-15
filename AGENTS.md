# Yongkang

A macOS console that runs a team of agent CLIs (`claude`, `codex`, `grok`, `agy`) in real
PTYs against a project's `.notebook/` folder, and reviews the changes they leave behind.

SwiftPM, macOS 13+, one dependency (SwiftTerm). Tests are Swift Testing, one file per domain.

`CLAUDE.md` is a symlink to this file. Edit `AGENTS.md`.

## Layout

- **`Sources/YongkangCore/`**: the logic, Foundation only. `Notebook/`, `Project/`,
  `Providers/` (with one folder per CLI's transcript reader), `Git/`, `Review/`,
  `Services/`, `Skills/`, `Shell/`, `Prompts/`, `Usage/`.
- **`Sources/YongkangUI/`**: SwiftUI, AppKit and SwiftTerm. `App/` (`YongkangApp`, the rail
  and the list column), `Terminal/`, `DesignSystem/`, and `Features/<screen>/`.
- **`Sources/Yongkang/main.swift`**: the app's executable. It only runs `YongkangApp`.
- **`Sources/Shots/`**: dev-only, renders every screen offscreen. Never part of the app.
- **`Tests/YongkangCoreTests/`**: tests of Core, with captured CLI output under
  `Fixtures/<provider>/`.
- **`Tests/YongkangUITests/`**: tests that need a view, the terminal or a SwiftUI colour.
  They read the same `Fixtures/`.

## Commands

```sh
make check                                  # format lint + build + test: the definition of done
make format                                 # fix what the lint step complains about
swift test --filter UsageTests              # one suite while you work
swift test --filter UsageTests/shortCount   # one test
swift test --filter YongkangCoreTests       # one test target
swift run shots <dir>                       # render every screen offscreen to <dir>/*.png
./make-app.sh && open .build/Yongkang.app   # release build, bundled skills, signed app
```

- `make check` also runs as a `pre-push` hook (`git config core.hooksPath .githooks`, once
  per clone).
- `swift run shots` is how you see a UI or structural change without launching the app.
  Render into two folders, one before your change and one after, and compare them.
  `review.png`, `handover.png` and `usage.png` read live git or the clock, so they differ on
  every commit.
- `make-app.sh` runs `pkill -x Yongkang` first. That quits the user's running app and every
  agent session inside it, so don't run it unless you've been asked to.
- The shipped role skills live in `Skills/` (product source, the prompts the app's agents run);
  `.claude/skills` and `.agents/skills` are symlinks to it. Only the app bundle carries them
  (`Contents/Resources/skills`).
  `swift run` falls back to whatever skills the CLI can find on its own.

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
  internal.
- **The `.notebook/` format is a contract.** Never change it without updating
  `NotebookFormat.specText`, `docs/notebook-format.md` and the tests that cover it.
- **Design before SwiftUI.** UI or design work goes through Claude Code's native `/design`
  skill (a design canvas) before any SwiftUI is written. Don't use the gstack `design-*`
  skills for this, and shots don't count as a design step.
- **Review opens on outcomes.** A review screen shows the task, the QA verdict and what the
  agents did first. The diff is one click away.
- **No file over 800 lines.** `YongkangApp.swift` is a known exception
  that is being refactored. Don't grow it.
- **The notebook files are the only state.** The app never writes what agents write, and
  it never commits unless the user approves in Review.
- **Keep the comment culture.** Comments explain *why*. `ponytail:` markers name a
  deliberate ceiling and what to do when it's hit.
- **Use `git mv` for moves,** in a commit of its own, separate from any edits.

## More

- `docs/development.md`: the manual smoke script, capturing CLI fixtures, the local signing
  identity, and adding a provider.
- `docs/refactor-plan.md`: where the structure is heading. This file changes with each
  phase, so describe what exists, not what's planned.
