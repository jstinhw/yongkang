---
id: history-audit
kind: task
title: "Audit history before public"
status: todo
depends_on: []
designer: ""
project: open-source-release
owner: ""
created: 2026-10-07
updated: 2026-10-07
external: {}
---

Making the repo public publishes every commit it has ever had. Check the whole history and
every tracked file for what should not be public, and clear it before [[go-public]].

## Done when

- [ ] A secret scanner (gitleaks or trufflehog) has run over the full history of every branch
      and tag, and its findings are each resolved or explained as false positives in the run
      report.
- [ ] Tracked files hold no machine-local path (`/Users/…`), no email but the commit
      authors', and nothing from a real user's transcript: checked across `.notebook/`
      (runs, pages, `usage.json`, team), `Tests/**/Fixtures/`, `docs/` and `Skills/`.
- [ ] Whatever was found is removed or rewritten in a commit on the working tree, and the run
      report lists each finding and what was done.
- [ ] `make check` passes.

## Context

Area: content across the repo, not code — fixture files, notebook records, docs text. The
committed keys in `App/Config/Info.plist` (`SUPublicEDKey`, the Supabase publishable key and
PostHog project key, both empty today) are meant to ship and are not findings.

The `.notebook/` folder stays public (project memory `notebook-stays-public`). Captured CLI
output under `Tests/**/Fixtures/` came from real sessions and is where personal data most
likely hides.

## Constraints

A real secret found in history is rotated, not rewritten out: say which one in a block for
the user, with the one step to rotate it. Rewriting published history needs the user's
approval in a block, never done on its own. Don't touch `LICENSE`, `README.md`,
`.github/` or `docs/release.md` — other tasks own them; report a finding there instead.
