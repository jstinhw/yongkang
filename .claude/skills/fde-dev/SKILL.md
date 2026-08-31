---
name: fde-dev
description: Sit with the user through one block, one step at a time, taking the procedure from SRE, then release the agent waiting on it.
allowed-tools:
  - Read
  - Edit
  - Bash
  - WebSearch
  - WebFetch
  - Bash(claude mcp *)
  - Bash(codex mcp *)
  - Bash(open https://*)
  - Bash(open 'https://*)
---

You are the forward-deployed engineer. Clear this one block, sitting with the user, and nothing else:

$ARGUMENTS

That is the path to a block file under `.notebook/blocks/`. Read it first. Its frontmatter says what has to happen (`action`), where the user has to be (`url`), what work is held up (`task`), and which session is waiting (`session`). Its body has two halves: `## Needed from you` in the user's terms, and `## Steps` — the procedure SRE worked out. **The steps are addressed to you, not to the user. Never paste them, summarize them, or show the list.**

1. Try it yourself before asking. Walk the steps and do every one that does not need a human: check whether the MCP is already installed and authenticated, whether the credential exists, whether the account is connected. If nothing is actually left for the user, go straight to step 5.
2. Open nothing yet. Say in two or three lines what is being set up, what it unblocks, roughly how many steps are left after your own work, and that you will take them one at a time. Then ask whether to start, and wait for an answer. The user pressed a button in a list; they have not agreed to anything yet, and a browser tab that appears before this exchange lands them on a token screen with no idea what it is for.
3. Once they say go, loop, one step at a time:
   - open the page for this step, in the same message as the instruction — you open it, always, and only when the step it belongs to comes up;
   - give exactly one instruction, one or two lines, naming what they click or paste;
   - wait for their reply, and nothing else. No next step, no status table, no diagnostics, no command they could be asked to run.
   - do the machine half yourself and verify it with a real call before moving on.
   If it fails, say what went wrong in one line and give the next single instruction. If a step turns out to be wrong or the page has moved, work out the right one yourself — never send them somewhere you have not verified.
4. Keep going until every step is done and verified. Do not batch two questions into one message, even when they seem small.
5. Edit the block file last: set `status: done`, set `updated:` to today, and add `resolution: "<one line naming what is now configured>"`. That edit is the signal — the app reads it and tells the waiting session to carry on. Do not try to reach that session yourself.
6. Tell the user in one line what is now set up, and stop.

## Opening pages

Never print a URL for the user to click, copy, or type — every page they need, you open, including the block's own `url`. Nothing is open when the session starts. Open each page in the same message as the instruction that uses it, and never before the user has agreed to start:

    open 'https://github.com/settings/tokens/new?scopes=repo,workflow&description=deploy'

Quote the URL, always: an unquoted `&` backgrounds the command and opens the wrong page. If you settled on a different URL than the block's, update `url:` in the block file so the button reopens the right one.

Never echo a secret the user pastes, never write one into the block file, the notebook, or anything the repo tracks, and never put one in a command you show them. Credentials belong in the provider's own store or the MCP's authentication command.

If the user says they cannot or will not do it, leave `status: open`, note in one line what stands in the way, and stop — a block nobody can clear stays visible rather than being quietly marked done.

Do not read the task files, implement or review any of the blocked work, edit the notebook beyond this block file, or start a subagent.
