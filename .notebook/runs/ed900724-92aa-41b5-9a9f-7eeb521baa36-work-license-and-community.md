---
kind: run
session: ed900724-92aa-41b5-9a9f-7eeb521baa36
task: license-and-community
work_id: license-and-community
title: "License and community files"
status: done
paths: [LICENSE, README.md, CONTRIBUTING.md, SECURITY.md, .github/ISSUE_TEMPLATE/bug_report.yml, .github/ISSUE_TEMPLATE/feature_request.yml, .github/ISSUE_TEMPLATE/config.yml, .github/pull_request_template.md, .notebook/tasks/license-and-community.md]
report: "MIT LICENSE, README Install section, CONTRIBUTING, SECURITY, issue forms and PR template; make check passes."
started_at: 2026-10-09T14:36:15+08:00
finished_at: 2026-10-09T14:50:30+08:00
---

## Result

- **`LICENSE`**: the standard MIT text, `Copyright (c) 2026 Justin Zen`.
- **`README.md`**: additions only. The tour of the window and the build commands are unchanged.
  - The intro now links [yongkang.ai](https://yongkang.ai), the `site` in the website's
    `astro.config.mjs`.
  - A new **Install** section comes before everything else: download `Yongkang.dmg` from
    `https://github.com/jstinhw/yongkang/releases/latest`, drag it to Applications, take updates
    through Restart to Update. It also lists what you need to run the app: macOS 14+ and one of
    the CLIs.
  - The tour now sits under a `## The window` heading.
  - `## Requirements` and `## Build, run, test` became **Build from source**. The Xcode note
    moved there, with a link to CONTRIBUTING.
  - A new **License** section at the end links LICENSE and SECURITY.
  - Nothing else in the repo linked the old headings (checked with grep).
- **`CONTRIBUTING.md`**:
  - `AGENTS.md` holds the rules for agents and people alike.
  - Build and test: `git config core.hooksPath .githooks`, `make check`, `make format`,
    `make run`, and shots before and after a UI change.
  - Branch and pull request flow, including `git mv` in a commit of its own.
  - User-visible changes go under `## [Unreleased]` in `CHANGELOG.md`.
  - One line of conduct, and contributions are licensed MIT.
- **`SECURITY.md`**:
  - Report through GitHub's private vulnerability reporting
    (`/security/advisories/new`), never in a public issue.
  - Only the latest release gets fixes.
  - A summary of what the app sends online, linking `docs/release.md#what-goes-online`.
- **`.github/ISSUE_TEMPLATE/`**:
  - `bug_report.yml`, an issue form. It requires the Yongkang version, the macOS version and
    which CLI (a dropdown: claude, codex, grok, agy, or none). The CLI version and the `log show`
    output are optional, with a warning that the log holds file paths.
  - `feature_request.yml`.
  - `config.yml`, which adds a "Report a vulnerability" link pointing at private reporting.
- **`.github/pull_request_template.md`**: boxes for `make check`, the CHANGELOG entry, and for a UI
  change, shots before and after.
- **Task file**: it already had every Done when box ticked in the working tree before I started,
  though none of these files existed. I reset the boxes, set `status: active`, then ticked each
  one after checking it and set `status: done`.

## Verification

- `ruby -ryaml -e '…YAML.load_file…' .github/ISSUE_TEMPLATE/*.yml`
  → `bug_report.yml: ok (7 items)`, `config.yml: ok (1 items)`, `feature_request.yml: ok (3 items)`.
- Every relative Markdown link in README, CONTRIBUTING and SECURITY resolves to a file
  (a shell loop printed `ok` for all 25, no `MISSING`). The anchors `#build-from-source` and
  `#what-goes-online` exist as headings.
- `make check`, first run: format lint passed, the build passed, and the XCTest part passed with
  no tests. Swift Testing then hung for about 10 minutes, and two other sessions' `make check`
  runs queued behind it.
  - The cause was a real `claude --session-id … Clear the block in .notebook/blocks/needs-a-key.md…`
    process. The test run had started it in a temp folder that was already deleted, and it was
    still alive.
  - It most likely came from `RestorationTests.aResolvedBlockFallsBackToTheProjectsAgents`. That
    test lets the poll start a guide session through the real terminal registry.
  - Once I killed that process the stuck tests passed. I had killed the test helper as well, so
    the run ended `make: *** [check] Error 1`.
- `make check`, re-run: `Build complete!`, then
  `Test run with 428 tests in 64 suites passed after 6.730 seconds with 12 known issues.` and
  `exit 0`. The 12 known issues are the existing `withKnownIssue` ones. The run included other
  sessions' uncommitted Swift changes, which share the working tree.

## Review

```json
{
  "summary": "Adds MIT LICENSE, CONTRIBUTING, SECURITY, issue forms and PR template, and gives the README an Install section ahead of build.",
  "confidence": "high",
  "confidence_why": "Docs and templates only; links, YAML and make check all verified.",
  "touches": "Repo docs and templates",
  "changed": [
    "LICENSE is MIT, copyright 2026 Justin Zen",
    "README opens with Install, links yongkang.ai, LICENSE, CONTRIBUTING",
    "CONTRIBUTING and SECURITY exist at the repo root",
    "New issues offer bug and feature forms, plus a private-report link",
    "Pull requests open with a make check and shots checklist"
  ],
  "checks": [
    {"claim": "Issue forms are valid YAML", "status": "passed", "result": "all three files load", "command": "ruby -ryaml load of .github/ISSUE_TEMPLATE/*.yml → ok (7), ok (1), ok (3)"},
    {"claim": "Doc links all resolve", "status": "passed", "result": "25 links ok, none missing", "command": "grep each ](path) in README/CONTRIBUTING/SECURITY, test -e → all ok"},
    {"claim": "make check passes", "status": "passed", "result": "428 tests passed, 12 known issues", "command": "make check → Test run with 428 tests in 64 suites passed … exit 0"},
    {"claim": "GitHub renders the forms", "status": "not_run", "result": "repo private; checked when it goes public", "command": "none: needs the community profile on GitHub"}
  ],
  "holds": [
    "No Swift, build or workflow file changed, so the app cannot behave differently.",
    "README additions only; the window tour and build commands are untouched."
  ],
  "spots": [
    {"path": "README.md", "lines": [9, 23], "label": "Install section", "why": "Promises a notarized DMG at releases/latest, which exists only after first-release lands."},
    {"path": "SECURITY.md", "lines": [1, 22], "label": "Security policy", "why": "Public promise about fixes and what goes online; check the wording is what you'd stand behind."},
    {"path": ".github/ISSUE_TEMPLATE/bug_report.yml", "lines": [36, 61], "label": "CLI and log", "why": "Asks for the app log, which holds file paths; the form warns, decide if that's enough."}
  ],
  "questions": [
    {"ask": "go-public wants every community-profile item green, which includes a code of conduct. Add one then?", "context": "This task allows only a line in CONTRIBUTING; GitHub's profile counts a CODE_OF_CONDUCT file.", "options": ["Add it at go-public", "Accept one grey item"], "recommend": 0}
  ],
  "concerns": [
    {"title": "Test leaves a real claude running", "detail": "A UI test's guide session started real claude, which outlived the test and hung make check 10 minutes. Re-run passed.", "blocks": false},
    {"title": "Install link empty until release", "detail": "releases/latest has no DMG until first-release; private reporting needs enabling at go-public.", "blocks": false}
  ],
  "outside": [
    {"kind": "read", "what": "Read ../yongkang-projects/yongkang-website/astro.config.mjs and README for the site URL."},
    {"kind": "local", "what": "Killed my own hung test run and the stray claude it had started in a deleted temp folder."}
  ],
  "files": [
    {"path": "LICENSE", "why": "MIT license text"},
    {"path": "README.md", "why": "Install, Build from source, License sections"},
    {"path": "CONTRIBUTING.md", "why": "How to build, branch and open PRs"},
    {"path": "SECURITY.md", "why": "Private reporting, supported versions, what's online"},
    {"path": ".github/ISSUE_TEMPLATE/bug_report.yml", "why": "Bug form: versions and which CLI"},
    {"path": ".github/ISSUE_TEMPLATE/feature_request.yml", "why": "Feature request form"},
    {"path": ".github/ISSUE_TEMPLATE/config.yml", "why": "Routes vulnerabilities to private reporting"},
    {"path": ".github/pull_request_template.md", "why": "PR checklist: make check, shots"},
    {"path": ".notebook/tasks/license-and-community.md", "why": "Status done, boxes ticked after checking"}
  ],
  "next": "go-public can turn the repo public with its community files in place."
}
```
