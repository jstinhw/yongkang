# Development

These are the details that are too long for `AGENTS.md`. The commands and the definition of
done are in that file.

## Manual smoke script

This walks the core loop by hand: open folder → intake → assign → subagent Check → block →
approve. Run it after any change to navigation, sessions, blocks or review, and at the end
of refactor Phases 2, 3 and 4. It uses real agents and spends real tokens.

Every label below comes from the code. Steps marked *agent behaviour* depend on what a
model does with its skill, so the app can't guarantee them. Steps marked *unverified*
haven't been checked against a live CLI.

**Before you start**

- Build the app bundle: `./make-app.sh && open .build/Yongkang.app`. This quits any running
  Yongkang, and every agent session in it. Use the bundle rather than `swift run`: only the
  bundle carries the packaged role skills.
- Have `claude` or `codex` on your PATH. Only those two have a subagent reader and a live
  child view. With Grok or Agy, step 8 has nothing to show.
- Make an empty folder, for example `mkdir ~/Projects/yk-smoke`.

### Open a folder

1. On the **Fleet** screen, click the **Open a folder you have** tile (⌘O) and choose the
   empty folder.
   - The panel's message reads "Agents run in this folder and its notebook lives in
     .notebook/."
   - The window enters the project. The rail shows Overview, Board, Agents, Review and
     Blocks. The top bar is titled **Overview**, and the work area asks
     **What is yk-smoke for?**
   - Nothing has been written to the folder yet: `ls -A ~/Projects/yk-smoke` is empty.

### Intake

2. In the Overview top bar, pick **Claude Code** or **Codex** in the agent switch.
3. Type a small brief into the "This project is…" box, for example: "A single-file Python
   CLI that prints the weather for a city." Then press Return or click **Start session**.
   - A session titled **Notebook Setup** appears under **Agents online** in the list
     column. Its live terminal fills the work area, with the prompt already sent.
   - If the CLI asks whether to trust the folder, a bar appears at the bottom of the window:
     **Action required · yk-smoke · Notebook Setup**, with an **Open session** button.
     Answer the question in the terminal and the bar goes away.
4. Answer the agent's questions until it has written `.notebook/`. *(Agent behaviour: the
   prompt tells it to ask a few multiple-choice questions, then write the notebook without
   asking for approval.)*
   - Within about 2 s of the files landing, **Board** in the rail shows the project's
     tasks, in chains.
   - The folder is now a git repository. Once a notebook exists, Yongkang runs `git init`,
     but nothing is staged or committed.
   - `.notebook/team/` is only written when you enter a project that already has a
     notebook. Click **YK** at the top of the rail, then click the project's card. **Agents**
     now lists five members under **Team**.

### Assign

5. Open **Board** and click a full task card, meaning the first open task in a chain.
   Tasks further down the chain are one-line rows. Clicking toggles the pick.
   - The card gets an accent outline, and the bottom bar reads "1 picked". If the task
     waits on other tasks, the bar adds "· N blockers pulled in".
6. Click **Assign to Engineering Lead**. If the batch includes a design task (one with
   `designer:` set), the button reads **Assign — design first** instead.
   - The window switches to **Agents** and opens the live terminal of a new
     **Engineering Lead** session. Its row reads "1 task · 0 running".
   - The top bar has an **Agents | Session** switch. **Agents** opens the lead's
     coordination dashboard.
   - Back on the board, the card has a **wip** pill and can't be picked again.
   - Two other ways in: the ↗ on a card opens the task page, which has its own
     **Assign to Engineering Lead** button; right-clicking a project row gives
     **Assign all tasks to Engineering Lead**.

### Subagent Check

7. Wait for the lead to dispatch its first specialist.
   - A row appears under **Engineering Lead** in the Agents list, named
     `<task-id>-<subtask>-<attempt>-<role>`, with a live dot. The Agents rail icon gets an
     accent dot.
   - Open the task's page (↗ on its card). The inspector's **Working on it** section lists
     that specialist with a **Running** pill.
8. Click that entry under **Working on it**, or the subagent's row in the Agents list.
   - The window switches to **Agents**. The top bar title becomes the subagent's name, and a
     **Parent session** button appears.
   - A notice over the lead's terminal reads "Opening child agent…". Yongkang types `/tasks`
     (Claude Code) or `/subagents` (Codex), moves down to the matching row and presses
     Return. The child's live view opens.
   - If it can't find the row, the notice reads "Could not select this child
     automatically. Select it in the CLI picker below." or "Child not found in the CLI
     picker. Select it below if it is still available." Pick the row by hand.
   - If you had typed something into the lead's prompt first, the notice reads "Submit or
     clear the CLI draft before switching agents."
   - *(Unverified: `ChildAgentPicker` recognises the picker from the text on screen. It
     hasn't been checked against Claude Code 2.1.272 or Codex 0.154.0.)*
9. Click **Parent session**.
   - You're back in the lead's own view. Claude Code gets Esc to close the child view;
     Codex gets `/subagents` again, and Yongkang selects **Main [default]**.

### Block

10. Wait for an agent to write `.notebook/blocks/<slug>.md`, or force a block by creating
    this file yourself while the lead is running:

    ```markdown
    ---
    title: Smoke test gate
    kind: block
    status: open
    task: <a task id from the batch>
    ---
    Nothing to do. This block only exists to test the flow.
    ```

    Keep the `status:` line: **Mark resolved** rewrites that exact line, and does nothing
    without it. Because there's no `session:` field, the block goes to the newest running
    Engineering Lead.
    - Within about 2 s, the Blocks rail icon gets an amber dot.
    - **Blocks** lists the block under **Waiting on you**, with "holds <task-id>" under its
      title.
    - Its page shows a **waiting on you** pill and "Engineering Lead is waiting — holds up
      <task title>". The inspector shows **Holds up**, **Waiting agent** with a **blocked**
      pill, and the notice that no secret is echoed back.
    - The bottom bar has **Mark resolved** and **Do it now**.
11. Click **Mark resolved**.
    - The file's status line becomes `status: done`.
    - On the next poll, the window switches to **Agents** on the lead and submits
      `Unblocked: Smoke test gate. Continue from where you stopped.` to it.
    - Turn on **Completed** in the Blocks top bar. The block is listed under **Resolved**.
    - **Do it now** would have started an **Unblock Smoke test gate** session with the
      `fde-dev` skill. *(Agent behaviour: that session explains the gate first, then walks
      through the block's `## Steps` one at a time.)*

### Approve

12. Wait for the lead to finish the task: QA passes it, and the lead sets `status: done` in
    the task file.
    - The Review rail icon lights green.
    - If no terminal is on screen at that moment, the window opens **Review** on the task by
      itself. If a terminal is up, the window stays where it is, because the terminal has
      the keyboard.
    - **Review** lists the task under **Waiting for you**, as "N files · QA passed" or
      "N files · no QA record".
    - A done task only counts as waiting if the lead's work records list its files in
      `paths`. *(Agent behaviour.)* If they don't, the task isn't under
      **Waiting for you**, its files show as "not claimed by a task" under **All changes**,
      and the only commit button is **Commit all changes**.
13. Open the task.
    - The header pill reads **Ready for your review**.
    - The cards, in order: **The task**, **Reviewer**, **What the agents did**,
      **Changes by area**, **Feedback for the agents**. There's no diff on this page.
    - The inspector shows **Verdict** ("QA passed") and **This commit** ("Only this task's
      files and its run records. Nothing is pushed.").
14. Optional: click a file under **Changes by area**, click a line, type a comment and click
    **Add comment**.
    - The diff has its own page, with a "‹ <task title>" button that goes back to the task.
    - The bar's primary button becomes **Request changes · 1**.
    - Delete the comment with its × under **Feedback for the agents**. Approving with
      feedback still unsent would discard it.
15. Check the commit message, which starts as the task title, then click
    **Approve and commit**.
    - The page moves to the next waiting task, or to **All changes** if none is left.
    - Check the result: `git -C ~/Projects/yk-smoke log -1 --stat` lists only the task's
      files and its run records, and `git status` shows everything else still uncommitted.
      Nothing was pushed.

**Clean up:** right-click each session row and choose **Close Session**. On the Fleet
screen, right-click the project card and choose **Remove from Fleet**, then delete the
folder.

## Capturing a CLI fixture

A fixture is real CLI output, trimmed down. It's what keeps a reader honest when a CLI
changes its format.

**Where fixtures live.** Under `Tests/YongkangCoreTests/Fixtures/<provider>/`, loaded with
`fixture("codex/…")` from `Tests/YongkangCoreTests/Support.swift`. `YongkangUITests` has
its own `fixture()`, which reads the same folder:

- **Terminal bytes.** `codex/codex-0.154.0-trust-screen.ansi` is Codex 0.154.0's trust
  screen. `AttentionPromptTests` feeds it to `AttentionTerminalView.dataReceived` and
  expects an `attentionReason`. The `--attention-selftest` flag in `YongkangApp.swift` plays
  the same file through a real PTY.
- **Transcripts and usage.** One JSON object per line, copied into a temporary fake home
  and read back through the real reader. Each reader takes `claudeHome:`, `codexHome:` or
  `grokHome:` for this. Values only known at runtime (a temp path, a session marker) are
  `{{CWD}}`-style placeholders that the test fills in.
- **Malformed inputs.** Truncated lines, non-JSON lines, empty files, injected newlines and
  `../` paths sit beside the good captures. The readers take files agents write, so a bad
  file must not crash them or escape the project.

**Where the real files are**

| CLI | File | Read by |
|---|---|---|
| Claude Code | `~/.claude/projects/<project path, "/" → "-">/<session-id>.jsonl`, the session's transcript and usage | `ClaudeTranscripts`, `AgentUsage` |
| | `…/<session-id>/subagents/agent-<id>.jsonl` and `agent-<id>.meta.json` | `ClaudeTranscripts.subagents` |
| | `~/.claude.json`, the cached plan and limits | `AgentUsage.claudeQuota` |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. The first line is `session_meta`; a subagent's `source` carries `subagent.thread_spawn.parent_thread_id`. A lead's rollout is the one whose opening prompt quotes `AgentCommand.marker`. | `CodexTranscripts`, `AgentUsage` |
| Grok | `~/.grok/sessions/<percent-encoded project path>/<session-id>/chat_history.jsonl` and `updates.jsonl` | `GrokTranscripts`, `AgentUsage` |
| Agy | Nothing is read. Agy runs in its live terminal only. | — |

Yongkang passes its session UUID, lowercased, as `--session-id` to Claude Code and Grok, so
those files are named after the UUID.

**Steps**

1. **Reproduce the case somewhere disposable.** Use a throwaway folder such as
   `/tmp/yongkang-fixture` and a throwaway prompt, so the capture holds nothing private.
   Note the CLI version (`claude --version`, `codex --version`).
2. **Find the file.** The newest one is usually it: `ls -t ~/.claude/projects/`, then
   `ls -t` inside the folder; `ls -t ~/.codex/sessions/*/*/*/ | head`;
   `ls -t ~/.grok/sessions/`. For output that only ever exists on screen, like a trust
   question, record the terminal instead: `script -q /tmp/cli.typescript codex`, get the
   screen to appear, then quit.
3. **Trim it to the minimum.** Keep only the lines the reader needs for the behaviour
   you're pinning, plus any line it has to skip, if skipping is the point. Keep the keys,
   nesting and value types exactly as the CLI wrote them, because that's the part that
   breaks. For terminal bytes, keep one whole frame that contains the question.
4. **Scrub it.**
   - Replace prompt text, replies, and tool inputs and outputs with short stand-ins
     ("Do the thing").
   - Replace home and user paths with `/tmp/…`.
   - Shorten long blobs to a placeholder (the fixtures use `"gAAA"` for
     `encrypted_content`). Codex's `session_meta` line also carries the base instructions.
   - Remove account ids, emails, org names, API keys and tokens.
   - Check nothing is left: `grep -nE '/Users/|@|sk-|ghp_|Bearer' <file>`.
5. **Save it** as `Tests/YongkangCoreTests/Fixtures/<provider>/<cli>-<version>-<what>.<ext>`.
   Copy terminal bytes byte-exact (`cp /tmp/cli.typescript …`, then trim with a hex-safe
   tool), never retyped. Add a new file next to the old one when a CLI changes its format,
   so the folder records which versions are supported.
6. **Add a check.** In that reader's test file (`Providers/CodexTranscriptTests.swift` and so
   on), copy the fixture into a temp home, call the reader, and `#expect` the behaviour with a
   message naming what it protects. Run `swift test`. Then break the reader on purpose for a
   moment and confirm the check fails.

## Stable local signing identity

macOS ties the Desktop and Documents permission (TCC) to the app's code signature. The
ad-hoc signature the linker leaves behind changes with every build, so macOS asks for folder
access again after each rebuild. If you sign with an identity that stays the same, you only
approve once.

Create the identity once:

1. Open Keychain Access and choose **Certificate Assistant → Create a Certificate…**.
2. Name it `Yongkang Dev`, set Identity Type to **Self Signed Root** and Certificate Type
   to **Code Signing**.

`make-app.sh` checks `security find-identity -v -p codesigning` for that name. If it's
there, the script signs with it (`--identifier local.yongkang.app`). If it isn't, the script
signs ad-hoc and prints a note that macOS will keep asking. To use a different certificate,
set `YONGKANG_IDENTITY=<name>`.

To check which signature a build got, run
`codesign -dv .build/Yongkang.app 2>&1 | grep -E 'Authority|Signature'`. A stable build
shows `Authority=Yongkang Dev`; an ad-hoc one shows `Signature=adhoc`.

*(Unverified: if `security find-identity -v -p codesigning` doesn't list the new
certificate, it may need **Trust → Code Signing: Always Trust** in Keychain Access. The
certificate hasn't been created on the machine this was written on.)*

## Adding a provider (today)

Adding Grok and Agy (`fb13f1e`) touched 8 files. This is the checklist for the next CLI,
with the code as it is now. The compiler flags the exhaustive `switch`es over `AgentKind`,
but not the ones that end in `default:`. To find every provider branch, run
`grep -rn '\.codex\|\.grok\|\.agy' Sources`.

1. **The command line**, in `YongkangCore`
   - `Providers/AgentKind.swift`, `AgentKind`: add the case, plus its `displayName` and
     `systemImage`. `command` is the raw value, so the case name has to match the
     executable's name on PATH. `skillInvocation` is how the CLI calls a skill: `$name` for
     Codex and `/name` for the rest.
   - `Shell/AgentCommand.swift`, `AgentCommand.line`: how the CLI accepts a session id
     (Claude Code and Grok take `--session-id`; Codex gets `marker` appended to its prompt),
     how it accepts an opening prompt (Agy needs `--prompt-interactive`), and whether it
     supports `--brief`.
   - `AgentCommand.denyCommits`: the CLI's flag for refusing `git commit`, `git push` and
     `gh pr create` in lead sessions, if it has one.
2. **`YongkangUI/Terminal/AgentTerminal.swift`**, `AgentTerminal.Coordinator.navigate` and
   `ChildAgentPicker`: the command that opens a live child-agent view, and how its picker
   looks on screen. Only Claude Code (`/tasks`) and Codex (`/subagents`) have one.
3. **`YongkangCore/Providers/<Provider>/<Provider>Transcripts.swift`** (new file, like
   `Providers/Grok/GrokTranscripts.swift`): where a session's transcript lives and how to
   parse it into `TranscriptLine`s. Take the home folder as a parameter that defaults to
   `~/.<cli>`, so the self-test can point it at a temporary folder.
4. **Usage**, in `YongkangCore`
   - `Usage/AgentUsage.swift`, `samples(at:_:)`: parse the CLI's token usage (see
     `grokSamples`).
   - `Providers/Transcripts.swift`, `Transcripts.url(of:in:)` and `usageURL(of:in:)`: point
     to the transcript and usage files.
   - Optional: a quota reader like `claudeQuota` or `codexQuota`, added to the list in
     `UsageBoard.load()` (`YongkangUI/Features/Usage/UsageBoard.swift`).
5. **`YongkangUI/App/YongkangApp.swift`**
   - `reloadAgentTranscript()`: call the new reader.
   - `subagents(of:in:)`: only if the CLI's subagents can be read from disk. Otherwise the
     `default: []` branch covers it.
   - `providerPicker`: widen its frame for the extra segment.
6. **`YongkangUI/Terminal/AgentAttention.swift`**, `AgentPrompt.reason`: the CLI's trust or
   consent question, so the **Action required** bar appears. `fb13f1e` skipped this step, so
   Grok and Agy have no entry.
7. **`Tests/YongkangCoreTests/`**: captured transcript and usage fixtures, with a test for
   each in `Providers/<Provider>TranscriptTests.swift` (see
   [Capturing a CLI fixture](#capturing-a-cli-fixture)).
8. **Docs**: every place in `README.md` and `docs/` that lists the supported CLIs.

Then run `swift test`, render shots (the agent switch gets wider), and do
the smoke script with the new provider selected.

Phase 4.3 of the refactor replaces this checklist with a single `AgentProvider` folder per
CLI.
