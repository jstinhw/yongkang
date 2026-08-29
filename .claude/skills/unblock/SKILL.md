---
name: unblock
description: Walk the user through one thing only they can do, then release the agent waiting on it.
allowed-tools:
  - Read
  - Edit
  - WebSearch
  - WebFetch
  - Bash(claude mcp *)
  - Bash(open https://*)
  - Bash(open 'https://*)
---

Clear this one block, and nothing else:

$ARGUMENTS

That is the path to a block file under `.notebook/blocks/`. Read it first. Its frontmatter says what has to happen (`action`), where the user has to be (`url`), what work is held up (`task`), and which session is waiting (`session`); its body is the checklist in the user's own terms.

1. Try it yourself before asking. Check whether the MCP is already installed and authenticated, whether the credential already exists, whether the account is already connected. If nothing is actually needed from the user, go straight to step 5.
2. Verify the route before sending the user anywhere: the official page on the provider's own domain, and the token scopes or permissions this actually needs. Never invent a settings URL or a configuration format.
3. Put the page in front of them, then give exactly one instruction, and wait. Name what they click or paste, in one or two lines. Do not show the steps after this one, a status table, diagnostics, or a command you could run yourself.
4. When they answer, do the machine half yourself: write the configuration, install or authenticate the MCP, then verify with a real call rather than assuming. If it fails, say what went wrong in one line and give the next single instruction. Repeat until it works.
5. Edit the block file last: set `status: done`, set `updated:` to today, and add `resolution: "<one line naming what is now configured>"`. That edit is the signal — the app reads it and tells the waiting session to carry on. Do not try to reach that session yourself.
6. Tell the user in one line what is now set up, and stop.

## Opening pages

Never print a URL for the user to click, copy, or type — every page they need, you open. The app already opened the block's `url` when the user pressed the button, so if that is the page, tell them it is open. The moment you need any other page — different scopes, a different provider screen, a page you found while checking — open it yourself in the same message you ask about it:

    open 'https://github.com/settings/tokens/new?scopes=repo,workflow&description=deploy'

Quote the URL, always: an unquoted `&` backgrounds the command and opens the wrong page. If you settled on a different URL than the block's, update `url:` in the block file so the button reopens the right one.

Never echo a secret the user pastes, never write one into the block file, the notebook, or anything the repo tracks, and never put one in a command you show them. Credentials belong in the provider's own store or the MCP's authentication command.

If the user says they cannot or will not do it, leave `status: open`, note in one line what stands in the way, and stop — a block nobody can clear stays visible rather than being quietly marked done.

Do not read the task files, implement or review any of the blocked work, edit the notebook beyond this block file, or start a subagent.
