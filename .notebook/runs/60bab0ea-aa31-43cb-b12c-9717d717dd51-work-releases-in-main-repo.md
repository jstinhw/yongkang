---
kind: run
session: 60bab0ea-aa31-43cb-b12c-9717d717dd51
task: releases-in-main-repo
work_id: releases-in-main-repo
title: "Releases publish from jstinhw/yongkang"
status: done
paths: [.github/workflows/release.yml, App/Config/Info.plist, docs/release.md, docs/refactor-plan.md, .notebook/tasks/releases-in-main-repo.md, .notebook/runs/60bab0ea-aa31-43cb-b12c-9717d717dd51-work-releases-in-main-repo.md]
report: "A v* tag now publishes the DMG, appcast and dSYMs as one release of this repo with GITHUB_TOKEN; the feed follows."
started_at: 2026-10-09T06:30:00Z
finished_at: 2026-10-09T06:50:00Z
---

## Result

- `.github/workflows/release.yml`: the `RELEASES_REPO` env and `RELEASES_TOKEN` secret are gone.
  The dSYMs are zipped before Publish, and Publish runs one `gh release create` on
  `$GITHUB_REPOSITORY` with `Yongkang.dmg`, `appcast.xml` and `Yongkang-<tag>-dSYMs.zip`,
  using `github.token`. It is not a draft or a prerelease (gh's defaults), so `latest` picks it up.
- Permissions: the workflow default is now `contents: read`. Only the `release` job gets
  `contents: write`. The checkout has `persist-credentials: false`, so `make check` and the build
  never have the write token on disk. Only the Publish step gets it.
- The appcast's enclosure URL is built from `$GITHUB_REPOSITORY`, so it names the repo the release
  is in.
- `App/Config/Info.plist`: `SUFeedURL` is
  `https://github.com/jstinhw/yongkang/releases/latest/download/appcast.xml`.
- `docs/release.md`: the intro, publish step 6, What users get (the download and feed URLs) and
  One-time setup now name `jstinhw/yongkang`. The "public releases repo" setup section is gone,
  and a line says publishing needs no secret.
- `docs/refactor-plan.md` 6.3 says in one line that releases moved to `jstinhw/yongkang`.
- One pre-existing shellcheck warning (SC2046 in the signing step, which also fails on `HEAD`)
  blocked actionlint. The split there is on purpose, so it now has a disable directive and a
  comment saying why.
- I kept a single job instead of splitting build and publish. With credentials kept off disk,
  only Publish holds the token, and a split would need two more pinned actions to pass the DMG
  between jobs.

The flow is otherwise the same: notes from `CHANGELOG.md` come first, then `make check`, then
signing, and nothing is published if an earlier step fails.

## Verification

- `actionlint .github/workflows/release.yml .github/workflows/ci.yml` (v1.7.12, with
  shellcheck 0.11.0 on PATH) → no output, exit 0. On `HEAD`'s release.yml it reported
  SC2046 at the signing step, which is now fixed.
- Dry run of the Appcast step: its `run:` script, pulled from the YAML, was run with a stub
  `sign_update`, a stub Info.plist, `GITHUB_REPOSITORY=jstinhw/yongkang` and
  `GITHUB_REF_NAME=v0.1.0`. xmllint passed, and the step wrote
  `<enclosure url="https://github.com/jstinhw/yongkang/releases/download/v0.1.0/Yongkang.dmg"`.
- `make check` → exit 0, "Test run with 428 tests in 64 suites passed … with 12 known issues"
  (the existing recorded `withKnownIssue`s, none from this change).
- `grep -rn "yongkang-releases|RELEASES_TOKEN|RELEASES_REPO" .github App docs README.md CHANGELOG.md Makefile`
  → only the history line in `docs/refactor-plan.md` 6.3.
- Not run: a real tag push. That's [[first-release]]. No shots, because nothing on screen changed.

## Review
```json
{
  "summary": "A v* tag now publishes the DMG, appcast and dSYMs as one release of jstinhw/yongkang with GITHUB_TOKEN, and the feed points there.",
  "confidence": "high",
  "confidence_why": "actionlint clean, appcast dry run correct; real publish untested until a tag",
  "touches": "release workflow, feed URL",
  "changed": [
    "Publish makes one release in this repo with three assets",
    "RELEASES_REPO and RELEASES_TOKEN removed from the workflow and docs",
    "SUFeedURL reads jstinhw/yongkang's latest appcast.xml",
    "Only the release job can write; checkout keeps no token"
  ],
  "checks": [
    {"claim": "Workflow passes actionlint", "status": "passed", "result": "no output, exit 0, shellcheck on", "command": "actionlint .github/workflows/release.yml .github/workflows/ci.yml → exit 0"},
    {"claim": "Enclosure URL names this repo", "status": "passed", "result": "jstinhw/yongkang/releases/download/v0.1.0/Yongkang.dmg; xmllint ok", "command": "bash -e appcast.sh (Appcast step, stubbed sign_update and plist) → xmllint ok"},
    {"claim": "Build and tests pass", "status": "passed", "result": "428 tests passed, 12 known issues", "command": "make check → exit 0, 428 tests in 64 suites passed"},
    {"claim": "No old repo references", "status": "passed", "result": "only refactor-plan 6.3 history line", "command": "grep -rn yongkang-releases|RELEASES_ .github App docs README.md CHANGELOG.md Makefile"},
    {"claim": "Tag publishes real release", "status": "not_run", "result": "needs a pushed tag and secrets", "command": "git push origin v0.1.0 (first-release task)"}
  ],
  "holds": [
    "Publish is the last step, so any earlier failure publishes nothing",
    "Write token is only on the Publish step; checkout drops it"
  ],
  "spots": [
    {"path": ".github/workflows/release.yml", "lines": [10, 29], "label": "permissions, checkout", "why": "Write is on the single job; persist-credentials false is what keeps make check from holding it."},
    {"path": ".github/workflows/release.yml", "lines": [112, 125], "label": "dSYMs, Publish", "why": "The one gh release create; no real tag has run it yet."}
  ],
  "questions": [],
  "concerns": [
    {"title": "Retire the old repo and secret", "detail": "If you created jstinhw/yongkang-releases or a RELEASES_TOKEN secret, delete the secret and archive the repo; nothing reads them now.", "blocks": false}
  ],
  "outside": [
    {"kind": "read", "what": "go install of actionlint v1.7.12 from the Go module proxy, into the scratchpad"},
    {"kind": "local", "what": "Go module cache filled with actionlint's modules"},
    {"kind": "read", "what": "pip install shellcheck-py from PyPI into a scratchpad venv"}
  ],
  "files": [
    {"path": ".github/workflows/release.yml", "why": "one release here, GITHUB_TOKEN, scoped write"},
    {"path": "App/Config/Info.plist", "why": "feed URL moves to jstinhw/yongkang"},
    {"path": "docs/release.md", "why": "publish step, URLs, setup without releases repo"},
    {"path": "docs/refactor-plan.md", "why": "6.3 notes the move"},
    {"path": ".notebook/tasks/releases-in-main-repo.md", "why": "status done"},
    {"path": ".notebook/runs/60bab0ea-aa31-43cb-b12c-9717d717dd51-work-releases-in-main-repo.md", "why": "this report"}
  ],
  "next": "release-provenance can add the checksum and attestation to Publish"
}
```
