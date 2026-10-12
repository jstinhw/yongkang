---
id: go-public-settings
kind: block
title: "Make the repo public and protect main"
status: done
session: 9b59ccf3-1100-4a05-a82a-f3c0ccd9c874
task: go-public
url: https://github.com/jstinhw/yongkang
run: ""
action: "Push go-public's commit to main, flip jstinhw/yongkang public, then turn on its ruleset, security and fork settings."
created: 2026-10-11
updated: 2026-10-11
resolution: "jstinhw/yongkang is public with About set; main has a PR + check ruleset; PVR, Dependabot alerts, secret scanning + push protection and fork approval on; community 100%."
---

`jstinhw/yongkang` is still private, and every setting go-public needs is on GitHub's settings
pages, which are yours to change. The code side is ready: the code of conduct, the CI comment,
and the test that kept CI red on `main`.

## Needed from you

- [ ] go-public's commit on `main`, with CI green there.
- [ ] The repo public, with a description, `https://yongkang.ai` as its website, and topics.
- [ ] `main` protected: a pull request that passed CI, no force push, no deletion.
- [ ] Private vulnerability reporting, Dependabot alerts, and secret scanning with push
      protection on.
- [ ] A fork's pull request waits for your approval before its CI runs.

## Steps

Each step is one page and one change. After each, verify with the read-only call given; never
make a setting through `gh api` yourself, and never change visibility before step 1 holds.

1. **Commit and push.** The user approves go-public in Review and pushes `main` (a direct push
   still works: there is no ruleset yet). Verify: `gh run list -R jstinhw/yongkang --workflow
   ci.yml --branch main -L 1` shows the new commit `completed success`. If `check` fails, stop
   and hand it back to the session; a red `check` locks every pull request out after step 4.
   Also confirm `.notebook/tasks/history-audit.md` is `status: done` (the task's constraint).
2. **Public.** Settings → General → Danger Zone → **Change visibility** → **Change to public**,
   then confirm with the repo name. Tell the user first: anyone can clone or fork it from that
   moment, and going private again recalls no copy. Verify: `gh api repos/jstinhw/yongkang --jq
   .visibility` → `public`.
3. **About.** On the repo's home page, the gear beside **About**: Description `A macOS console
   that runs a team of agent CLIs (claude, codex, grok, agy) against a project's notebook, and
   reviews the changes they leave behind.`; Website `https://yongkang.ai`; Topics `macos`,
   `swift`, `swiftui`, `ai-agents`, `claude-code`, `codex`, `developer-tools`. The user may
   reword any of them. Verify: `gh api repos/jstinhw/yongkang --jq '{description, homepage,
   topics}'`.
4. **Ruleset.** Settings → Rules → Rulesets → **New ruleset** → **New branch ruleset**. Name
   `main`; Enforcement status **Active**; Target branches → **Add target** → **Include default
   branch**; tick **Restrict deletions**, **Require a pull request before merging** with
   Required approvals **0** (GitHub never lets an author approve their own pull request, and
   the user is the only maintainer), **Require status checks to pass** → **Add checks** →
   `check` from GitHub Actions, and **Block force pushes**; no bypass list. **Create**. If
   `check` is not offered, it has not run in the last week: step 1 runs it. Verify:
   `gh api repos/jstinhw/yongkang/rules/branches/main --jq '[.[].type]'` lists `deletion`,
   `pull_request`, `required_status_checks` and `non_fast_forward`.
5. **Security.** Settings → Advanced Security: **Enable** Private vulnerability reporting,
   Dependabot alerts, and Secret Protection (secret scanning), then its **Push protection**.
   Verify: `gh api repos/jstinhw/yongkang/private-vulnerability-reporting --jq .enabled` →
   `true`; `gh api repos/jstinhw/yongkang/vulnerability-alerts` exits 0 (204);
   `gh api repos/jstinhw/yongkang --jq .security_and_analysis` shows `secret_scanning` and
   `secret_scanning_push_protection` `enabled`.
6. **Forks.** Settings → Actions → General → Approval for running fork pull request workflows
   from contributors → **Require approval for all external contributors** → **Save**. Verify:
   `gh api repos/jstinhw/yongkang/actions/permissions/fork-pr-contributor-approval --jq
   .approval_policy` → `all_external_contributors`.
7. **Community.** Open `https://github.com/jstinhw/yongkang/community`: every item is green.
   If it lists **Repository admins accept content reports** unticked, Settings → Moderation
   options → Reported content → **Prior contributors and collaborators** → **Save**. Verify:
   `gh api repos/jstinhw/yongkang/community/profile --jq .health_percentage` → `100`, and
   `.files.code_of_conduct_file` is not null.

Then set this block `status: done` with a one-line `resolution`. The go-public session re-checks
every item itself before it marks the task done.
