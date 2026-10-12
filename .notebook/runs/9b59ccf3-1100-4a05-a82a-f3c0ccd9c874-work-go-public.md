---
kind: run
session: 9b59ccf3-1100-4a05-a82a-f3c0ccd9c874
task: go-public
work_id: go-public
title: "Code side ready, settings blocked"
status: blocked
paths: [.github/workflows/ci.yml, CODE_OF_CONDUCT.md, CONTRIBUTING.md, docs/release.md, Tests/YongkangUITests/RestorationTests.swift, .notebook/tasks/go-public.md, .notebook/blocks/go-public-settings.md, .notebook/runs/9b59ccf3-1100-4a05-a82a-f3c0ccd9c874-work-go-public.md]
report: "Code of conduct, CI comment and the test that kept CI red on main are done; the repo's GitHub settings wait on you in a block."
started_at: 2026-10-11T14:42:00+08:00
finished_at: 2026-10-11T15:00:00+08:00
---

## Result

- **`CODE_OF_CONDUCT.md`**: the Contributor Covenant 2.1, the official text with its front
  matter dropped and the contact filled in. The contact is my pick, the commit-author email,
  until you choose (see the question).
- **`CONTRIBUTING.md`**: the conduct line now links `CODE_OF_CONDUCT.md`.
- **`.github/workflows/ci.yml`**: the private-repo macOS-minutes comment is gone. In its place:
  `main`'s ruleset requires this job by its id, `check`.
- **`docs/release.md`**, CI bullet only (line 177): the same private-minutes sentence, replaced
  with what the ruleset and fork settings do. Its other hunks are release-provenance's,
  uncommitted from another session.
- **CI was red on `main`**, so the ruleset would have locked every pull request out.
  `aResolvedBlockFallsBackToTheProjectsAgents` failed in both CI runs. The gate's guide session
  runs `claude`. CI has no `claude`, so the session exited, and `guide(of:)` counts only live
  sessions. The test now gives its model a shell that keeps every session alive, the
  `TerminalRegistry(shell:)` that `MessageDeliveryTests` already uses.
- **The GitHub settings** are all still off, and only you can change them. They are filed as
  `.notebook/blocks/go-public-settings.md`. The task is `blocked`, with one item ticked.
- Nothing changed on screen, so I rendered no shots.

Not mine to change, so reported here: `App/Config/Info.plist:16` still says the feed lives in
"the public releases repo, since this one is private". `SUFeedURL` itself already points here.

## Verification

```
$ gh api repos/jstinhw/yongkang --jq '{visibility, description, homepage, topics}'
{"description":null,"homepage":null,"topics":[],"visibility":"private"}
$ gh api repos/jstinhw/yongkang/rulesets
403 Upgrade to GitHub Pro or make this repository public to enable this feature.

$ gh run list -R jstinhw/yongkang --workflow ci.yml
failure  push main  "Look a bare command up on the shell's PATH, every match"
failure  pull_request  dependabot swiftterm-1.19.0
  ✘ aResolvedBlockFallsBackToTheProjectsAgents() at RestorationTests.swift:222 (both runs)

# CI reproduced locally: HOME=<empty dir> so the guide's login shell has no claude, 2 s pause
old test:   ✘ recorded an issue at RestorationTests.swift:223 (the #require on guide(of:))
fixed test: ✔ passed after 2.169 seconds

$ HOME=<empty dir> swift test --skip-build          # whole suite, CI-like
━ Test run with 451 tests in 66 suites passed … with 12 known issues.

$ make check; echo $?
━ Test run with 451 tests in 66 suites passed after 6.824 seconds with 12 known issues.
exit 0

$ grep -nE "pull_request_target|workflow_run|issue_comment|repository_dispatch|workflow_dispatch" .github/workflows/*.yml
(none: ci.yml runs on pull_request and push to main, release.yml on v* tags only)

$ diff <(official 2.1 text minus front matter) CODE_OF_CONDUCT.md
39c39  [INSERT CONTACT METHOD] → the contact; nothing else differs
```

## Review

```json
{
  "summary": "Code of conduct, CI comment and the CI-only failing test are done; repo settings wait on you in a block.",
  "confidence": "medium",
  "confidence_why": "Code side checked; settings unverifiable until you change them.",
  "touches": "CI, community files, settings",
  "changed": [
    "CODE_OF_CONDUCT.md is Contributor Covenant 2.1; CONTRIBUTING links it",
    "ci.yml no longer mentions private-repo minutes",
    "The test failing only on CI now passes without claude installed",
    "Block go-public-settings lists each GitHub setting to change"
  ],
  "checks": [
    {"claim": "Build and tests pass", "status": "passed", "result": "451 tests passed, 12 known issues", "command": "make check → exit 0"},
    {"claim": "CI failure reproduced, then fixed", "status": "passed", "result": "old fails at :223, fixed passes", "command": "HOME=<empty> swift test --filter …aResolvedBlockFallsBackToTheProjectsAgents"},
    {"claim": "Suite passes without agent CLIs", "status": "passed", "result": "451 tests passed, 12 known issues", "command": "HOME=<empty> swift test --skip-build"},
    {"claim": "No fork-triggered workflow has secrets", "status": "passed", "result": "no privileged triggers in any workflow", "command": "grep pull_request_target|workflow_run|… .github/workflows → none"},
    {"claim": "Repo public with settings on", "status": "not_run", "result": "repo still private; waits on the block", "command": "gh api repos/jstinhw/yongkang → visibility private"},
    {"claim": "CI green on main", "status": "not_run", "result": "needs this commit pushed", "command": "gh run list --workflow ci.yml --branch main"}
  ],
  "holds": [
    "GitHub passes no secret to a fork's pull_request run, and no workflow uses a privileged trigger."
  ],
  "spots": [
    {"path": "CODE_OF_CONDUCT.md", "lines": [39, 39], "label": "Conduct contact", "why": "It publishes an email address; you choose which one."},
    {"path": "Tests/YongkangUITests/RestorationTests.swift", "lines": [214, 217], "label": "Test fix", "why": "Every session in this test now sleeps instead of running its line."},
    {"path": "docs/release.md", "lines": [177, 181], "label": "CI bullet", "why": "My only hunk in a file another task also changed."}
  ],
  "questions": [
    {"ask": "Which contact goes in the code of conduct?", "context": "It is public; the commit email is already in every commit.", "options": ["Commit email", "A yongkang.ai address", "Another address"], "recommend": 0}
  ],
  "concerns": [
    {"title": "Direct pushes to main end", "detail": "With the ruleset, main takes only pull requests whose check passed; no bypass, approvals at zero.", "blocks": false},
    {"title": "Stale comment in Info.plist", "detail": "Line 16 still calls this repo private and the feed external; release tasks own it.", "blocks": false}
  ],
  "outside": [
    {"kind": "read", "what": "gh api reads of jstinhw/yongkang settings, runs, logs, issues"},
    {"kind": "read", "what": "GitHub docs pages on rulesets, Actions forks, security, community profile"},
    {"kind": "read", "what": "Downloaded Contributor Covenant 2.1 markdown from EthicalSource on GitHub"},
    {"kind": "local", "what": "Test logs and the covenant copy written to the session scratchpad"}
  ],
  "files": [
    {"path": ".github/workflows/ci.yml", "why": "Private-minutes comment replaced"},
    {"path": "CODE_OF_CONDUCT.md", "why": "Contributor Covenant 2.1"},
    {"path": "CONTRIBUTING.md", "why": "Conduct line links the code"},
    {"path": "docs/release.md", "why": "CI bullet no longer says private"},
    {"path": "Tests/YongkangUITests/RestorationTests.swift", "why": "Test no longer needs claude installed"},
    {"path": ".notebook/tasks/go-public.md", "why": "Blocked; CI comment item ticked"},
    {"path": ".notebook/blocks/go-public-settings.md", "why": "The GitHub settings only you can change"},
    {"path": ".notebook/runs/9b59ccf3-1100-4a05-a82a-f3c0ccd9c874-work-go-public.md", "why": "This report"}
  ],
  "next": "first-release can tag v0.1.0 on a public, protected repo."
}
```
