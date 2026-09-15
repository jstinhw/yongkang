# Fixtures

Real output captured from the agent CLIs, git and sample repo files, one folder per source:
`claude/`, `codex/`, `grok/`, `git/`, `compose/`, `notebook/`. Load one with `fixture("codex/…")`.

Name a capture after the CLI version it came from (`codex-0.154.0-trust-screen.ansi`), so the
folder records which formats are supported. When a CLI changes its format, add a new file
next to the old one rather than editing it. Inputs an agent or CLI could plausibly write
badly (truncated JSONL, injected newlines, `../` paths) belong here too. The parsers read
untrusted files. See `docs/development.md` for how to capture one.

Codex rollouts use `{{CWD}}` and `{{MARKER}}` placeholders, filled in by the test, for values
only known at runtime.
