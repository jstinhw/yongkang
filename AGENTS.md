# Yongkang

A macOS console that runs a team of agent CLIs (`claude`, `codex`, `grok`, `agy`) in real
PTYs against a project's `.notebook/` folder, and reviews the changes they leave behind.

SwiftPM, macOS 13+, one dependency (SwiftTerm). All code is one flat executable target in
`Sources/Yongkang/`. Tests are Swift Testing in `Tests/YongkangTests/`, one file per domain,
with captured CLI output under `Fixtures/<provider>/`.

`CLAUDE.md` is a symlink to this file. Edit `AGENTS.md`.

## Commands

```sh
swift build                           # build
swift test                            # test
swift run Yongkang --shots <dir>      # render every screen offscreen to <dir>/*.png
./make-app.sh && open .build/Yongkang.app   # release build, bundled skills, signed app
```

- `--shots` is how you see a UI or structural change without launching the app. Render
  into two folders, one before your change and one after, and compare them.
- `make-app.sh` runs `pkill -x Yongkang` first. That quits the user's running app and every
  agent session inside it, so don't run it unless you've been asked to.
- Only the app bundle carries the packaged role skills (`Contents/Resources/skills`).
  `swift run` falls back to whatever skills the CLI can find on its own.

## Definition of done

A handoff needs all of these:

1. `swift build` succeeds.
2. `swift test` passes. A `withKnownIssue` is a recorded bug, not a pass to copy.
3. For any UI or structural change, you rendered shots before and after and compared them.
   Say what changed on screen, or that nothing did.

## Rules

- **The `.notebook/` format is a contract.** Never change it without updating
  `NotebookFormat.specText`, `docs/notebook-format.md` and the tests that cover it.
- **Design before SwiftUI.** UI or design work goes through Claude Code's native `/design`
  skill (a design canvas) before any SwiftUI is written. Don't use the gstack `design-*`
  skills for this, and `--shots` doesn't count as a design step.
- **Review opens on outcomes.** A review screen shows the task, the QA verdict and what the
  agents did first. The diff is one click away.
- **No file over 800 lines.** `App.swift` is a known exception
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
