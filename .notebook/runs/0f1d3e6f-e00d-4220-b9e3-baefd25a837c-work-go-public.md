---
kind: run
session: 0f1d3e6f-e00d-4220-b9e3-baefd25a837c
task: go-public
work_id: go-public
title: "Public repo checked, two flaky tests fixed"
status: done
paths: [.notebook/tasks/go-public.md, Tests/YongkangUITests/TerminalRegistryTests.swift, Tests/YongkangUITests/ProjectWatchTests.swift, .notebook/runs/0f1d3e6f-e00d-4220-b9e3-baefd25a837c-work-go-public.md]
report: "Every GitHub setting you changed reads back as asked; go-public is done. Two flaky tests that failed make check are fixed."
started_at: 2026-10-11T21:30:00+08:00
finished_at: 2026-10-11T21:47:00+08:00
---

## Result

- **go-public is `done`**, every Done when item ticked. I re-read each setting from the
  `go-public-settings` block myself, and each one is as the task asks (see Verification).
- **The conduct contact**: you committed `839a18a` with "the commit email as its contact", so
  I took that as your choice. The earlier session's question is settled.
- **`make check` failed on its first run**, on a test unrelated to this task. Two tests were
  flaky, and both are fixed in the test, not the app:
  - `TerminalRegistryTests.steeringToAChildTypesThePickerCommandAndWalksToItsRow` (lines
    390–393) read the key log as soon as `showChild` returned. The last Enter is in the PTY by
    then, but `cat` may not have logged it yet. It now waits for the log with `eventually`,
    as the test's earlier checks already do.
  - `ProjectWatchTests.closingAProjectEndsItsWatch` (lines 66–68). `open` starts the folder
    watch right away, and FSEvents can still deliver the notebook's own setup writes. The
    reload that starts is not ended by `close`, so its read could land after `Ship it` was
    written. The test now joins any read in flight (`reloadNotebook` joins one) before
    writing. Only `reloadNotebook` ever writes a snapshot, so that was the only way in.
- `TerminalRegistryTests.swift` also holds another session's uncommitted test
  (`anApprovedCommandsBangArrivesInAReadOfItsOwn`, approve-request). Only lines 390–393 are mine.
- Nothing changed on screen, so I rendered no shots.

Still there, and not this task's: `App/Config/Info.plist:16` says the feed lives "in the public
releases repo, since this one is private".

## Verification

```
$ gh api repos/jstinhw/yongkang --jq '{visibility, description, homepage, topics, security_and_analysis}'
visibility "public"; description "A macOS console that runs a team of agent CLIs …";
homepage "https://yongkang.ai"; topics [ai-agents, claude-code, codex, developer-tools, macos,
swift, swiftui]; secret_scanning enabled; secret_scanning_push_protection enabled

$ gh api repos/jstinhw/yongkang/rules/branches/main --jq '[.[].type]'
deletion, non_fast_forward, pull_request (0 approvals), required_status_checks [check]
$ gh api repos/jstinhw/yongkang/rulesets/24880591 --jq '{enforcement, bypass_actors, conditions}'
{"bypass_actors":[],"conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"]}},"enforcement":"active"}

$ gh api repos/jstinhw/yongkang/private-vulnerability-reporting      → {"enabled":true}
$ gh api repos/jstinhw/yongkang/vulnerability-alerts -i              → HTTP/2.0 204 No Content
$ gh api repos/jstinhw/yongkang/actions/permissions/fork-pr-contributor-approval
{"approval_policy":"all_external_contributors"}
$ gh api repos/jstinhw/yongkang/actions/permissions/workflow
{"can_approve_pull_request_reviews":false,"default_workflow_permissions":"read"}
$ grep -nE "^on:|pull_request|push|tags|secrets\." .github/workflows/*.yml
ci.yml: pull_request, push to main, no secrets; release.yml: push of v* tags only, every secret
(no pull_request_target, workflow_run, issue_comment or dispatch anywhere)

$ gh run list -R jstinhw/yongkang --workflow ci.yml --branch main -L 1
completed success  Add a code of conduct and drop the private-minutes comment  main  push

$ gh api repos/jstinhw/yongkang/community/profile --jq .health_percentage   → 100
code_of_conduct_file, contributing, license, readme, pull_request_template all present
$ curl -sL https://github.com/jstinhw/yongkang/community   (public page, signed out)
check beside Description, README, Code of conduct, Contributing, License, Security policy,
Issue templates, Pull request template: 8 of 8
# The "content reports" row shows only to admins. The API's content_reports_enabled is null,
# and docs.github.com says it "is only returned for organization-owned repositories".

$ make check                     # first run, before the fixes
✘ steeringToAChildTypesThePickerCommandAndWalksToItsRow() at TerminalRegistryTests.swift:390
  keys() lacked the final Enter; passes 5 of 5 run alone
$ swift test --skip-build        # full suite, during the reruns
✘ closingAProjectEndsItsWatch() at ProjectWatchTests.swift:68 (1 in about 14 full runs;
  0 of 30 run alone under full CPU load, so not reproduced on demand)

$ make check; echo $?            # after both fixes
━ Test run with 453 tests in 66 suites passed after 9.347 seconds with 12 known issues.
exit 0
$ swift test --skip-build  ×20   # after both fixes
20 × "Test run with 453 tests in 66 suites passed … with 12 known issues", no ✘
$ swift test --filter steeringToAChild… ×10, every core busy with `yes`
10 × passed
```

## Review

```json
{
  "summary": "Re-checked every GitHub setting you changed; go-public is done. Fixed two flaky tests that failed make check.",
  "confidence": "high",
  "confidence_why": "Every setting read back; suite passed 20 full runs.",
  "touches": "Task record, two tests",
  "changed": [
    "go-public is done with every Done when item ticked",
    "The picker test waits for its key log instead of racing it",
    "The watch test lets an in-flight read land before writing"
  ],
  "checks": [
    {"claim": "Repo public with About", "status": "passed", "result": "public, description, yongkang.ai, seven topics", "command": "gh api repos/jstinhw/yongkang → visibility public"},
    {"claim": "main ruleset enforced", "status": "passed", "result": "PR, check, no force push, no deletion", "command": "gh api …/rules/branches/main → 4 rules, no bypass"},
    {"claim": "Security reporting and scanning on", "status": "passed", "result": "PVR true, alerts 204, push protection enabled", "command": "gh api …/private-vulnerability-reporting, …/vulnerability-alerts"},
    {"claim": "Forks wait for approval", "status": "passed", "result": "all_external_contributors", "command": "gh api …/fork-pr-contributor-approval"},
    {"claim": "Forks cannot reach release secrets", "status": "passed", "result": "secrets only in release.yml on v* tags", "command": "grep on:/secrets in .github/workflows"},
    {"claim": "CI green on main", "status": "passed", "result": "completed success on the conduct commit", "command": "gh run list --workflow ci.yml --branch main -L 1"},
    {"claim": "Community profile all green", "status": "passed", "result": "100 percent; 8 of 8 checks", "command": "gh api …/community/profile; curl …/community"},
    {"claim": "Content reports row", "status": "not_run", "result": "admin-only page; API omits it for personal repos", "command": "gh api …/community/profile → content_reports_enabled null"},
    {"claim": "Build and tests pass", "status": "passed", "result": "453 tests passed, 12 known issues", "command": "make check → exit 0"},
    {"claim": "Flakes gone", "status": "passed", "result": "20 of 20 full runs passed", "command": "swift test --skip-build ×20"}
  ],
  "holds": [
    "GitHub gives a fork's pull_request run no secrets, and only a v* tag push runs release.yml.",
    "Both fixes touch tests only; no app code changed."
  ],
  "spots": [
    {"path": "Tests/YongkangUITests/ProjectWatchTests.swift", "lines": [66, 68], "label": "Watch fix", "why": "Fixed from reasoning; the flake was too rare to reproduce on demand."},
    {"path": "Tests/YongkangUITests/TerminalRegistryTests.swift", "lines": [390, 393], "label": "Picker fix", "why": "My only hunk in a file holding another session's uncommitted test."}
  ],
  "questions": [],
  "concerns": [
    {"title": "Shared file with uncommitted work", "detail": "TerminalRegistryTests.swift also has approve-request's new test; commit my lines 390–393 with go-public, theirs with theirs.", "blocks": false},
    {"title": "Content reports unread by me", "detail": "That community row is admin-only; your block resolution says it was handled.", "blocks": false},
    {"title": "Stale comment in Info.plist", "detail": "Line 16 still calls this repo private and the feed external; release tasks own it.", "blocks": false}
  ],
  "outside": [
    {"kind": "read", "what": "gh api reads of jstinhw/yongkang settings, ruleset, runs, secret names, community profile"},
    {"kind": "read", "what": "gh api community profiles of github/docs, cli/cli, sindresorhus/awesome, for comparison"},
    {"kind": "read", "what": "curl of github.com/jstinhw/yongkang/community and docs.github.com community metrics page"},
    {"kind": "local", "what": "Test logs and fetched pages in the session scratchpad; CPU-load processes, since stopped"}
  ],
  "files": [
    {"path": ".notebook/tasks/go-public.md", "why": "Done, every item ticked"},
    {"path": "Tests/YongkangUITests/TerminalRegistryTests.swift", "why": "Picker test waits for its log"},
    {"path": "Tests/YongkangUITests/ProjectWatchTests.swift", "why": "Watch test joins an in-flight read"},
    {"path": ".notebook/runs/0f1d3e6f-e00d-4220-b9e3-baefd25a837c-work-go-public.md", "why": "This report"}
  ],
  "next": "first-release can tag v0.1.0 on the public, protected repo."
}
```
