# Providers

Yongkang runs four agent CLIs: Claude Code (`claude`), Codex (`codex`), Grok (`grok`) and Agy
(`agy`). Everything the app knows about one of them lives in its **provider**, one folder under
`Sources/YongkangCore/Providers/`. A new CLI, or a format change in one, is that folder plus its
fixtures.

## The protocol

`AgentKind` is what persists: a session row's `agent`, the agent picker's `@AppStorage`. Its raw
value is the executable's name on PATH, which `AgentKind.installed` looks for.
`AgentKind.provider` is the one switch that maps a kind to its `AgentProvider`
(`Providers/AgentProvider.swift`):

| Member | What it answers | Who asks |
|---|---|---|
| `kind`, `displayName`, `systemImage` | Identity, and the agent picker's label and icon, which are the row's too | `AgentKind` forwards the last two |
| `skillPrefix` | What starts a skill in a prompt: `$` for Codex, `/` for the rest | `AgentKind.skillInvocation` |
| `skillFolders` | The folders the CLI reads `<name>/SKILL.md` from, under the project and under `$HOME` | `Skills.shared`, `Skills.loaded(by:project:)`, for the Skills page |
| `launch(prompt:sessionID:noCommit:)` | The words after the executable: the session id strategy, the deny-commit flags, the quoted prompt | `AgentCommand.line`, which wraps them in `cd … && exec` for `zsh -ilc` |
| `effort(_:)` | The words ahead of `launch`'s that set how hard the CLI thinks in one session: `--effort` for Claude Code, nothing by default | `AgentCommand.line`, for Product (`ProjectModel.productEffort`) |
| `ask(prompt:)` | The words that make the CLI answer one prompt on stdout and exit: `-p`, or `exec --skip-git-repo-check` for Codex | `ProjectNaming.ask`, which names a described project's folder before its session starts |
| `transcriptURL(session:project:) async` | The session's own transcript, or nil | `AppModel.reloadAgentTranscript`, `AgentUsage.spends` (through `usageURL`) |
| `usageURL(session:project:) async` | Where token usage is written. Defaults to the transcript; Grok overrides it | `AgentUsage.spends`, `UsageBoard` |
| `subagents(session:project:taskIDs:) async` | The agents the session spawned, with the task each one's label names | `ProjectModel`'s poll |
| `transcript(at:)` | A transcript's lines as the viewer shows them (Task, Tool, Result, Reply) | `AppModel.reloadAgentTranscript` |
| `usage(at:) async` | Every turn's spend in a usage file, parsing only what's new | `AgentUsage.spends`, `LeadCoordination.load` |
| `attentionReason(screen:)` | Why the rendered terminal is waiting on the user, such as a trust question | `AgentPrompt.reason`, which asks every provider |
| `trusts(_:) async` | Whether the CLI's own record lets it work in a folder, so its sessions there ask nothing. Nil when the record can't be read; true by default. Claude Code reads `~/.claude.json`, Codex `~/.codex/config.toml`, Agy `~/.gemini/antigravity-cli/settings.json`, and Grok asks `grok inspect` | `ProjectModel.readTrust`: the board's Assign buttons wait for it, and the board opens a session to ask |
| `childView` | The CLI's child-agent picker: its command (`/tasks`, `/subagents`), how to recognise it on screen, and the row that goes back to the session. Nil when there's none | `TerminalRegistry.showChild`, which does the typing and key-walking |

**State lives in actors.** A provider is a `Sendable` struct, and the ones with something to
remember keep one `static let shared` instance. What they remember between calls sits in an actor
the provider owns: every provider that reads usage has a
`UsageReader` (`Usage/UsageReader.swift`, one read cursor per file), and Codex has a
`CodexTranscripts` (the rollout index: parsed `session_meta` lines, the thread each session
drives, and the rollouts already searched). Nothing in `Providers/` or `Usage/` is a mutable
`static var`. The members that can touch that state are `async`, and the models await them:
`ProjectModel` starts the poll's read in a task, and `AppModel` resolves the on-screen
transcript before swapping it in.

**Shared plumbing** a provider reuses rather than re-implements:

- `Transcripts.text(at:)` reads a file a CLI is still writing, keeping every line that
  decodes. A read of the whole file as strict UTF-8 would lose every line when the CLI is caught
  mid-character.
- `AgentUsage.json(_:)` and `AgentUsage.date(_:)` parse a JSONL line and an ISO 8601 stamp.
- `AgentCommand.quoted(_:)` and `AgentCommand.commitRules`, for `launch`.
- `AgentPrompt.visibleText(_:)` turns a rendered screen into the text a person reads:
  lowercased, with NUL cells and runs of whitespace as one space.
- `ClaudeTranscripts.resultText`, `describe` and `truncate` turn arbitrary JSON content into
  one-line transcript text. Codex and Grok use them too.

## The folders

| Provider | Folder | Files | Fixtures |
|---|---|---|---|
| Claude Code | `Providers/ClaudeCode/` | `ClaudeCodeProvider.swift`; `ClaudeTranscripts.swift` (the session folder, subagents and their finished state, the transcript) | `Fixtures/claude/`, `Fixtures/usage/claude-*` |
| Codex | `Providers/Codex/` | `CodexProvider.swift` (with the prompt `marker` and the running-total usage parser); `CodexTranscripts.swift` (the rollout index actor and the transcript) | `Fixtures/codex/`, `Fixtures/usage/codex-*` |
| Grok | `Providers/Grok/` | `GrokProvider.swift`; `GrokTranscripts.swift` (the session folder, chat history and usage stream) | `Fixtures/grok/` |
| Agy | `Providers/Agy/` | `AgyProvider.swift`. Agy only runs in its terminal, so it reads nothing | none |

Tests sit in the same shape: `Tests/YongkangCoreTests/Providers/<Provider>/`, beside
`Providers/AgentProviderTests.swift`, which checks every kind against its provider. Terminal
captures are rendered through SwiftTerm in `Tests/YongkangUITests/AttentionPromptTests.swift`.

## Where fixtures go

Under `Tests/YongkangCoreTests/Fixtures/<cli>/`, named after the CLI version they came from
(`codex-0.154.0-trust-screen.ansi`). Put the malformed inputs a CLI could plausibly write
(truncated lines, non-JSON lines, empty files) beside the good captures.
[Capturing a CLI fixture](development.md#capturing-a-cli-fixture) has the steps, including
how to scrub a capture.

## Adding a CLI

1. **The folder.** `Sources/YongkangCore/Providers/<Name>/<Name>Provider.swift`, a
   `package struct` that conforms to `AgentProvider`. The compiler lists what's missing. Put its
   readers beside it (`<Name>Transcripts.swift`), and keep anything they remember between calls
   in an actor the provider owns, like `UsageReader`. Take a home folder in the reader so tests
   can point it at a temporary one.
   - `launch`: how the CLI takes a session id (a flag, a marker in the prompt, or nothing), an
     opening prompt, and a deny-commit flag if it has one. Turn off anything it would stop to
     ask before the prompt that isn't about the folder, such as Codex's update offer
     (`-c check_for_update_on_startup=false`): every session of a batch would stop on it. `AgentCommandTests` pins every line
     byte for byte, so add a case there.
   - `ask`: the CLI's one-shot mode, answering on stdout with no session. The name it gives
     a new project is read off the last line printed, so a CLI that ends with anything else
     (a token count) has to print that to stderr.
   - `skillFolders`: where the CLI looks for skills, under the project and under `$HOME`. Its
     home folders join the Skills page's shared list.
   - `transcriptURL`, `subagents`, `transcript`, `usage`: return nil or empty for what the CLI
     doesn't write, as `AgyProvider` does.
   - `attentionReason`: the CLI's trust question, matched with its controls, so the
     **Action required** bar appears. Nil until one has been captured. Only a question about
     the folder: the user's answer in one session is typed into the folder's other sessions of
     that CLI still asking it.
   - `trusts`: where the CLI records a folder's answer, and under which path: its own, its repo's
     root, symlinks resolved or not. Find out by answering yes in a scratch home (`CODEX_HOME`,
     `GROK_HOME`, or a copied `~/.claude.json` under `CLAUDE_CONFIG_DIR`) and reading what it
     wrote. A wrong guess isn't fatal: a session opened to ask that asks nothing lets the agent in
     for the rest of the run. Leave the default (true) for a CLI that never asks.
   - `childView`: nil unless the CLI has a live child-agent picker.
2. **The kind.** In `Providers/AgentKind.swift`, add the case, named after the executable, and
   its arm in `provider`. That switch is exhaustive, so the compiler points at it.
3. **Fixtures and tests.** Captured transcripts and usage in `Fixtures/<cli>/`, and
   `Tests/YongkangCoreTests/Providers/<Name>/<Name>TranscriptTests.swift` reading them through
   the real reader. A captured trust screen gets a case in `AttentionPromptTests`.
4. **Outside the folder, only if it applies:**
   - A plan-limits reader like `AgentUsage.claudeQuota`, added to the list in `UsageBoard.load()`.
   - `README.md` and `docs/guide/` list the supported CLIs.
5. **Check it.** `make check`, render shots before and after (`agent-picker.png` lists the new CLI), and run
   the [smoke script](development.md#manual-smoke-script) with the new CLI selected.
