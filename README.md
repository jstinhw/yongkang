# Claude Code.app

macOS window that runs multiple `claude` or `codex` CLI sessions in real PTYs (SwiftTerm). Add, switch, and close sessions from the left sidebar. Nothing starts until you pick a folder — that keeps macOS from prompting for iCloud Drive / Music / Documents, which is what happened when it defaulted to `$HOME`.

```sh
./make-app.sh && open .build/ClaudeCode.app
```

Requires `claude` and/or `codex` on your PATH (they launch via `zsh -ilc`, so `.zshrc` applies).
