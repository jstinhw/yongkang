# Claude Code.app

macOS window that runs the `claude` CLI in a real PTY (SwiftTerm). Nothing starts until you pick a folder — that keeps macOS from prompting for iCloud Drive / Music / Documents, which is what happened when it defaulted to `$HOME`.

```sh
./make-app.sh && open .build/ClaudeCode.app
```

Requires `claude` on your PATH (it's launched via `zsh -ilc`, so `.zshrc` applies).
