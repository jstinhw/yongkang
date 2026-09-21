# Development

These are the details that are too long for `AGENTS.md`. The commands and the definition of
done are in that file.

## Manual smoke script

This walks the core loop by hand: open folder → intake → assign → subagent Check → block →
approve → relaunch. Run it after any change to navigation, sessions, blocks, review or the
menu bar. It uses real agents and spends real tokens.

Every label below comes from the code. Steps marked *agent behaviour* depend on what a
model does with its skill, so the app can't guarantee them. Steps marked *unverified*
haven't been checked against a live CLI.

**Before you start**

- Quit Yongkang, then run `make run`, which builds the app with Xcode and opens it. It refuses
  while any Yongkang is running rather than quitting it, because that would end every agent
  session inside it. The app bundle is also the only build that carries the packaged role
  skills.
- **Expect macOS to ask for folder access, and for permission to notify you.** The bundle ID is
  `ai.yongkang.Yongkang`; a build signed ad-hoc gets a new signature each time, so macOS asks
  again after every rebuild unless you have the signing identity below.
- Have `claude` or `codex` on your PATH. Only those two have a subagent reader and a live
  child view. With Grok or Agy, step 8 has nothing to show.
- Make an empty folder, for example `mkdir ~/Projects/yk-smoke`.

**What the shots can't check for you.** `make shots` draws each screen into an offscreen
window, which has no title bar — so the toolbar, the window title and subtitle, and the whole
menu bar only ever exist in a running app. That is most of what steps 1, 2 and 16 below are
for.

### Open a folder

1. With no project open, the empty screen offers **Open a Folder…**; click it and choose the
   empty folder. The **+** beside **Projects** in the sidebar and **File → Open Folder… (⌘O)**
   are the same door, and the menu item is the one that carries the shortcut — try them too.
   - The panel's message reads "Agents run in this folder and its notebook lives in
     .notebook/."
   - The project appears in the sidebar, picked. The rail shows Board and Agents. The
     **window's title** reads **Board** with **yk-smoke** under it, and the work area asks
     **What is yk-smoke for?**
   - Nothing has been written to the folder yet: `ls -A ~/Projects/yk-smoke` is empty.

### Intake

2. In the window's toolbar, open the agent picker and pick **Claude Code** or **Codex**. Both
   are listed under **On this Mac** if they are installed; a CLI that is not sits under **Not
   found on this Mac** and cannot be picked.
3. Type a small brief into the "This project is…" box, for example: "A single-file Python
   CLI that prints the weather for a city." Then press Return or click **Start session**.
   - A session titled **Notebook Setup** appears under **yk-smoke** in the sidebar. Its page
     opens on its live terminal, with the prompt already sent.
   - If the CLI asks whether to trust the folder, a bar appears at the bottom of the window:
     **Action required · yk-smoke · Notebook Setup**, with an **Open session** button.
     Answer the question in the terminal and the bar goes away.
4. Answer the agent's questions until it drafts the plan. *(Agent behaviour: the prompt
   tells it to ask a few multiple-choice questions, then write `.notebook/NOTEBOOK.md` and
   a ready proposal at `.notebook/blocks/plan.md`, and nothing else until you approve.)*
   - **Agents** in the rail lights amber, **yk-smoke**'s row in the sidebar gets an amber count,
     and the draft is a row of its own under it, reading **Notebook Setup · wants your
     opinion**. Its page reads **Product plan is ready**, with a **Create project** button.
     Click it: the window returns to **Notebook Setup** with the approval typed in, and the
     agent writes the notebook.
   - **Board** in the rail shows the project's roadmap and its milestones, each a column of
     tasks in chains, about a third of a second after the last file lands. The folder is watched with FSEvents, not polled, and the
     watcher holds a burst back by 300 ms so twenty files an agent just wrote are one read.
   - The folder is now a git repository. Once a notebook exists, Yongkang runs `git init`,
     but nothing is staged or committed.
   - `.notebook/team/` is only written when you pick a project that already has a
     notebook. Pick another project in the sidebar and come back, or relaunch:
     `.notebook/team/allen.md` now exists.

### Assign

5. Open **Board** and click a full task card, meaning the first open task in a chain.
   Tasks further down the chain are one-line rows. Clicking toggles the pick.
   - The card gets an accent outline, and the bottom bar reads "1 picked". If the task
     waits on other tasks, the bar adds "· N blockers pulled in".
6. Beside **Assign** is the agent it assigns to, starting on the toolbar's. Pick a different
   one there, then click **Assign**. If the batch includes a design task (one with
   `designer:` set), the button reads **Assign — design first** instead.
   - The window switches to **Agents** and opens the new agent's page on its live terminal, on
     the agent you picked. Its row in the sidebar is the session — **Codex**, say —
     reading **working** and the task's title.
   - The toolbar's agent is unchanged.
   - Beside the terminal, the page lists the task's **Done when** and, under **Access**, the one
     folder it works in.
   - Back on the board, the card has a **wip** pill and can't be picked again.
   - Two other ways in: the ↗ on a card opens the task page, which has its own picker and
     **Assign** button; a milestone's heading opens its page, whose **Pick all** takes every
     task in it.

### Subagent Check

7. Open a milestone's page from its heading on the board and use **Pick all**. Tasks that wait
   on nothing get a session each; a task and its blockers share one, and the window goes to the
   project's Agents page with every one of them under **Working**. Then wait for a session with
   several tasks to start a subagent.
   - The session's page lists it under **Subagents**, named after the task id, with a live dot.
     *(Agent behaviour: a session may work down a short chain itself.)* The Agents rail icon
     gets an accent dot.
   - Open the task's page (↗ on its card). The inspector's **Working on it** section lists
     the session that holds it, as "its session", and that subagent under it, both with a
     **Running** pill. Clicking the session row opens the session.
8. Click the subagent under **Working on it**, or on its session's page.
   - The window switches to **Agents**. The window's title becomes the subagent's name, and a
     **Parent session** button appears.
   - A notice over the session's terminal reads "Opening child agent…". Yongkang types `/tasks`
     (Claude Code) or `/subagents` (Codex), moves down to the matching row and presses
     Return. The child's live view opens.
   - If it can't find the row, the notice reads "Could not select this child
     automatically. Select it in the CLI picker below." or "Child not found in the CLI
     picker. Select it below if it is still available." Pick the row by hand.
   - If you had typed something into the session's prompt first, the notice reads "Submit or
     clear the CLI draft before switching agents."
   - *(Unverified: `ChildAgentPicker` recognises the picker from the text on screen, as each
     provider's `childView` describes it. It hasn't been checked against Claude Code 2.1.272 or
     Codex 0.154.0.)*
9. Click **Parent session**.
   - You're back in the session's own view. Claude Code gets Esc to close the child view;
     Codex gets `/subagents` again, and Yongkang selects **Main [default]**.

### Block

10. Wait for an agent to write `.notebook/blocks/<slug>.md`, or force a block by creating
    this file yourself while the session is running:

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
    session holding that task.
    - The Agents rail icon gets an amber dot, on the same watch as step 4.
    - The session's row in the sidebar turns amber and reads **blocked** and the task's title;
      the project's row counts it, and the project's Agents page shows it first, under
      **Needs you**. On the board, the task's row in the sidebar is amber too, reading
      **blocked** and the session's name.
    - Its page shows a **waiting on you** pill and "<session title> is waiting — holds up
      <task title>". The inspector shows **Holds up**, **Waiting agent** with a **blocked**
      pill, and the notice that no secret is echoed back.
    - The bottom bar has **Mark resolved** and **Do it now**.
11. Click **Mark resolved**.
    - The file's status line becomes `status: done`.
    - On the next read of the file, the window switches to **Agents** on the session and
      submits `Unblocked: Smoke test gate. Continue from where you stopped.` to it.
    - The session's row goes back to working: a resolved block has nothing left to do.
    - **Do it now** would have started an **Unblock Smoke test gate** session. *(Agent
      behaviour: that session does what it can itself, then walks through the block's
      `## Steps` with you one at a time.)*

### Approve

12. Wait for the session to finish the task: it checks the `Done when`, sets `status: done`
    in the task file, writes its report and opens a report page for you.
    - The Agents rail icon lights green.
    - If no terminal is on screen at that moment, the window opens the task's review by
      itself. If a terminal is up, the window stays where it is, because the terminal has
      the keyboard.
    - The session's row turns green and reads **<agent> · ready for review**, and the
      project's row counts it in green.
    - A done task only counts as waiting if the session's report lists its files in
      `paths`. *(Agent behaviour.)* If they don't, the row stays plain and its files are
      only reachable through the working tree's own page, whose one button is
      **Commit all changes**.
13. Open the task.
    - The header pill reads **Ready for your review**.
    - The cards, in order: **The task**, **What changed**, **Self-review**,
      **Code changes**, **Feedback**. Every file under **Code changes** is folded.
    - The session's page lists the task under **Waiting for your review**; clicking it there, or
      **Review** on its card on the project's Agents page, opens this same page.
    - The inspector shows **Verdict** ("Checked by the agent") and **This commit** ("Only this task's
      files and its run records. Nothing is pushed.").
14. Optional: click a file under **Code changes**, click a line of the diff it unfolds, type
    a comment and click **Add comment**.
    - The diff unfolds in place, under the file's row.
    - The bar's primary button becomes **Request changes · 1**.
    - Delete the comment with its × under **Feedback**. Approving with feedback still
      unsent would discard it.
15. Check the commit message, which starts as the task title, then click
    **Approve and commit**.
    - The page moves to the next waiting task, or to **All changes** if none is left.
    - Check the result: `git -C ~/Projects/yk-smoke log -1 --stat` lists only the task's
      files and its run records, and `git status` shows everything else still uncommitted.
      Nothing was pushed.

### The menu bar, and coming back

16. Walk the menus. Nothing here is on a button only, and an item the window cannot act on is
    disabled rather than hidden — so the shape stays the same on every screen.
    - **View → Board** and **Agents**, `⌘1`–`⌘2`, move between sections from any
      screen. Try it with a terminal focused too: that is the case a button-bound shortcut
      could never answer, and the one this step exists for. *(Unverified: the registry's key
      monitor passes the event on rather than swallowing it, and `MenuCommandTests` checks the
      items with no window, but nothing has checked a menu shortcut against a focused SwiftTerm
      view.)*
    - **View → Hide List**, `⌘\`, collapses the sidebar, and the toolbar's own button
      agrees with it. The item's title flips to **Show List**. Clicking any rail icon, the
      current one included, brings the list back.
    - **Agent → Assign Task** and **Assign Task To ▸** are lit only while a task page is open
      for a task that is neither done nor already with a session. Open a done task: they grey
      out.
    - **Agent → New Agent…**, `⌘N`, opens the New Agent sheet from any screen. Pick a ready task,
      tick another open project under **Can also read**, and start it: the agent's page lists
      both folders under **Access**, and `ps -ef | grep add-dir` shows the second on its
      command line. With Grok picked, the folder list is off.
    - **File → New Project…** is `⇧⌘N`, and **Open Folder…** `⌘O`.
    - There is no **New Window**: the model and its terminals are app-wide, so a second
      window would take the first one's terminals.
    - **Yongkang → Check for Updates…** is disabled in a `make run` build: only a Release build
      with `SUPublicEDKey` set checks. **Sign In with GitHub…** is lit once `YKSupabaseURL` and
      `YKSupabaseKey` are set in `App/Config/Info.plist`: it opens GitHub in a system sheet, and
      afterwards the item reads **Sign Out <your login>**. Closing the sheet is not an error.
      *(Unverified: no Supabase project existed when this was written.)*
17. With the project open on a task page, quit Yongkang (⌘Q) and run `make run` again.
    - The window comes back on the same project, the same section and the same page.
    - The sessions do not: those PTYs died with the app, and the project has no agents under it
      in the sidebar.
    - The sidebar comes back collapsed if you left it collapsed. Its **width** does not —
      it opens at its default every launch, which is a known gap (`docs/refactor-plan.md` §8).
    - Delete the task's file while the app is closed, then relaunch: the window opens the
      board rather than an empty page.

**Clean up:** right-click each agent's row and choose **Close Session**. Right-click the
project in the sidebar and choose **Close Project**, then delete the folder.

## Capturing a CLI fixture

A fixture is real CLI output, trimmed down. It's what keeps a reader honest when a CLI
changes its format.

**Where fixtures live.** Under `Tests/YongkangCoreTests/Fixtures/<provider>/`, loaded with
`fixture("codex/…")` from `Tests/YongkangCoreTests/Support.swift`. `YongkangUITests` has
its own `fixture()`, which reads the same folder:

- **Terminal bytes.** `codex/codex-0.154.0-trust-screen.ansi` is Codex 0.154.0's trust
  screen. `AttentionPromptTests` feeds it to `AttentionTerminalView.dataReceived` and
  expects an `attentionReason`. `TerminalRegistryTests` plays the same file through a real
  PTY into `AppModel`, up to the notice and the session it opens.
- **Transcripts and usage.** One JSON object per line, copied into a temporary fake home
  and read back through the real reader. Each reader takes a home for this: `claudeHome:` and
  `grokHome:`, or `CodexTranscripts(codexHome:launched:)`. Values only known at runtime (a temp
  path, a session marker) are `{{CWD}}`-style placeholders that the test fills in.
- **Malformed inputs.** Truncated lines, non-JSON lines, empty files, injected newlines and
  `../` paths sit beside the good captures. The readers take files agents write, so a bad
  file must not crash them or escape the project.

**Where the real files are**

| CLI | File | Read by |
|---|---|---|
| Claude Code | `~/.claude/projects/<project path, "/" → "-">/<session-id>.jsonl`, the session's transcript and usage | `ClaudeTranscripts`, `ClaudeCodeProvider.usage` |
| | `…/<session-id>/subagents/agent-<id>.jsonl` and `agent-<id>.meta.json` | `ClaudeTranscripts.subagents` |
| | `~/.claude.json`, the cached plan and limits | `AgentUsage.claudeQuota` |
| Codex | `~/.codex/sessions/YYYY/MM/DD/rollout-*.jsonl`. The first line is `session_meta`; a subagent's `source` carries `subagent.thread_spawn.parent_thread_id`. A session's rollout is the one whose opening prompt quotes `CodexProvider.marker`. | `CodexTranscripts`, `CodexProvider.usage` |
| Grok | `~/.grok/sessions/<percent-encoded project path>/<session-id>/chat_history.jsonl` and `updates.jsonl` | `GrokTranscripts`, `GrokProvider.usage` |
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
6. **Add a check.** In that reader's test file (`Providers/Codex/CodexTranscriptTests.swift` and
   so on), copy the fixture into a temp home, call the reader, and `#expect` the behaviour with a
   message naming what it protects. Run `swift test`. Then break the reader on purpose for a
   moment and confirm the check fails.

## The app icon

Three streams joining one current. 永, the "yong" of Yongkang, began as a picture of water
running a long way: separate streams of work, from agents and from people, leaving as one. The
middle stream is yours, in the console's own `amber`, so the Dock and the app agree on what
"waiting on you" looks like; the outer two are its text ink, `tx`.

It is drawn in code, not exported from an editor. `Sources/YongkangUI/DesignSystem/LogoMark.swift`
is the mark: a SwiftUI view that takes a side length and puts every coordinate on a 256-unit
grid scaled by it, so 16 px and 1024 px are one picture. `AppIcon.swift` sets it on the dark
tile. To change it, edit the view, then:

```sh
make icon   # → App/Yongkang/Assets.xcassets/AppIcon.appiconset/icon-1024.png
```

That runs `swift run shots --icon <file>`, which renders through `ImageRenderer` at scale 1 —
not the offscreen window the screens use, because that one renders at the display's backing
scale and 1024 points would come out 2048 px. Commit the view and the PNG together: the PNG is
a build artefact of the view, and nothing else regenerates it. No other logo file is kept in
the repo — not the icon at other sizes, the bare mark, or the mark with the name.

The catalog holds one entry, not the ten slots Xcode used to want: `actool` takes that 1024
master and generates the whole `AppIcon.icns` family from it. The entry has to be spelled
`"size": "512x512", "scale": "2x"`, which is what "1024 px" is called in a macOS icon set.
`"size": "1024x1024", "scale": "1x"` builds without an error and produces no icon at all —
`actool` calls it "an unassigned child", skips it, and the app ships with no `Assets.car` and
no `CFBundleIconName`. Check for that file and that key after any change here.

macOS downscales the master for every size it shows, so the check that matters is the small
end. At 128 px and 32 px all three streams read separately, and the channels between them
still open. At 16 px the channels close, and the streams blur into a Y with a dim amber
centre — still the only warm thing in the icon, and still visible. `AppIconTests` checks this
by sampling that pixel. Retina draws a 16 pt row
from the 32 px picture, so 1x-at-16 is the worst case rather than the usual one. The tile's
dark ground carries the mark on a light Dock, and the `markLine` inner edge separates it from
a dark one.

## Stable local signing identity

macOS ties the Desktop and Documents permission (TCC) to the app's code signature. The
ad-hoc signature the linker leaves behind changes with every build, so macOS asks for folder
access again after each rebuild. If you sign with an identity that stays the same, you only
approve once.

Create the identity once:

1. Open Keychain Access and choose **Certificate Assistant → Create a Certificate…**.
2. Name it `Yongkang Dev`, set Identity Type to **Self Signed Root** and Certificate Type
   to **Code Signing**.

`App/Config/Signing.xcconfig` names the identity. `make run` and `make archive` check
`security find-identity -v -p codesigning` for that name. If it's there, Xcode signs with it.
If it isn't, they sign ad-hoc and print a note that macOS will keep asking. To use a
different certificate, change `CODE_SIGN_IDENTITY` in that file.

To check which signature a build got, run
`codesign -dv --verbose=4 .build/xcode/Build/Products/Debug/Yongkang.app 2>&1 | grep -E 'Authority|Signature|flags'`.
A stable build shows `Authority=Yongkang Dev`; an ad-hoc one shows `Signature=adhoc`. Both
show `runtime` in the flags: the app always has hardened runtime. Neither signature has a Team
ID, so a local build carries the one exception entitlement,
`com.apple.security.cs.disable-library-validation` — without it the runtime refuses the embedded
Sparkle framework and the app crashes at launch. A release, signed with a Team ID, has none.

*(Unverified: if `security find-identity -v -p codesigning` doesn't list the new
certificate, it may need **Trust → Code Signing: Always Trust** in Keychain Access. The
certificate hasn't been created on the machine this was written on.)*

The bundle ID changed from `local.yongkang.app` to `ai.yongkang.Yongkang` in refactor PR 2.4.
On its first launch the app copies the open projects, the list column's width and visibility,
and the agent choice from the old defaults domain (`DefaultsMigration`). macOS still treats
it as a new app, so it asks for folder access and notification permission again.

## Adding a provider

A new CLI is one folder under `Sources/YongkangCore/Providers/` plus its fixtures. The protocol,
the folders and the checklist are in [`docs/providers.md`](providers.md).
