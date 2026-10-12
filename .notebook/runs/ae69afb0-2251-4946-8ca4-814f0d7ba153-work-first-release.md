---
kind: run
session: ae69afb0-2251-4946-8ca4-814f0d7ba153
task: first-release
work_id: first-release
title: "0.1.0 notes ready, tag blocked"
status: blocked
paths: [CHANGELOG.md, docs/release.md, .notebook/tasks/first-release.md, .notebook/blocks/release-secrets.md, .notebook/blocks/tag-v0-1-0.md, .notebook/runs/ae69afb0-2251-4946-8ca4-814f0d7ba153-work-first-release.md]
report: "The 0.1.0 changelog is written; the Apple secrets and the tag wait on you in two blocks."
started_at: 2026-10-11T22:05:00+08:00
finished_at: 2026-10-11T22:45:00+08:00
---

## Result

- **`CHANGELOG.md`**: `## [0.1.0] - 2026-10-11` describes the app as first released: one
  paragraph on what Yongkang is and needs, then what it does (window, notebook, Board, Agents,
  requests, design gate, blocks, Review, team, Usage, background updates). An empty
  `## [Unreleased]` sits above it. These become the GitHub release's notes, followed by the
  workflow's "Verify the download" section.
- **Sign In and usage analytics are left out of the notes**, though the old Unreleased listed
  them: `App/Config/Info.plist` has no Supabase or PostHog key, so in this build the Sign In
  item is disabled and analytics send nothing. See the question.
- **`docs/release.md`, Cutting a release**: the routine went `git commit` then `git push` to
  `main`, which `main`'s new ruleset refuses. It now goes through a branch and a pull request,
  then tags the merged commit on `main`.
- **Two blocks**, in order:
  - `release-secrets`: the repo has only `SPARKLE_PRIVATE_KEY`; the six Apple secrets are
    missing, and this Mac has no Developer ID certificate. It also checks the Sparkle secret
    matches `SUPublicEDKey` before anything is tagged, since a mismatch strands every install
    at its first update and no run would show it.
  - `tag-v0-1-0`: once the secrets are set and this change is merged to `main`, you approve
    the tag push; the session then watches the run to a published release.
- **Not done yet**, waiting on those: the tag's run, the release assets, the download checks
  (`curl`, checksum, `gh attestation verify`, `spctl`), and the last block, opening the DMG on
  a clean Mac. I file that one once the release exists.

## Verification

```
$ gh secret list -R jstinhw/yongkang
SPARKLE_PRIVATE_KEY	2026-10-09T07:26:04Z
$ gh release list -R jstinhw/yongkang ; git ls-remote --tags origin
(nothing: no release, no tag)
$ gh api repos/jstinhw/yongkang --jq .visibility
public
$ security find-identity -v -p codesigning
     0 valid identities found

# The workflow's own notes step, run on the new CHANGELOG.md:
$ awk -v v=0.1.0 'index($0, "## [" v "]") == 1 { on = 1; next } /^## / { on = 0 } on' CHANGELOG.md
→ 32 lines, starting "The first public release." (non-empty, so the step passes)
$ (same with v=9.9.9) | grep -q '[^[:space:]]' || echo stop
stop
$ (same with v=Unreleased) | grep -c '[^[:space:]]'
0

$ make check
Build complete!
━ Test run with 454 tests in 66 suites passed after 9.824 seconds with 12 known issues.
exit 0
```

The 12 known issues are existing `withKnownIssue` records (notebook index quoting, usage
ledger, skill paths), none touched here.

## Review

```json
{
  "summary": "Wrote the v0.1.0 release notes, fixed the release routine for PR-only main, and filed blocks for the Apple secrets and the tag.",
  "confidence": "medium",
  "confidence_why": "Notes and routine checked; the release itself has not run yet.",
  "touches": "Changelog, release routine",
  "changed": [
    "CHANGELOG.md has a 0.1.0 section and an empty Unreleased above it",
    "docs/release.md's routine merges through a pull request, then tags main",
    "Two blocks: the six Apple secrets, then the v0.1.0 tag push"
  ],
  "checks": [
    {"claim": "Build and tests pass", "status": "passed", "result": "454 tests passed, 12 known issues, exit 0", "command": "make check → Test run with 454 tests in 66 suites passed"},
    {"claim": "Workflow finds 0.1.0 notes", "status": "passed", "result": "32 lines extracted under ## [0.1.0]", "command": "the workflow's awk with v=0.1.0 on CHANGELOG.md → 32 lines"},
    {"claim": "Missing version still stops", "status": "passed", "result": "v=9.9.9 extracts nothing, step would fail", "command": "awk with v=9.9.9 | grep -q . || echo stop → stop"},
    {"claim": "Unreleased is fresh", "status": "passed", "result": "0 non-blank lines under Unreleased", "command": "awk with v=Unreleased | grep -c . → 0"},
    {"claim": "Release secrets all set", "status": "failed", "result": "only SPARKLE_PRIVATE_KEY; six Apple secrets missing", "command": "gh secret list -R jstinhw/yongkang → SPARKLE_PRIVATE_KEY 2026-10-09"},
    {"claim": "v0.1.0 run succeeds", "status": "not_run", "result": "no tag yet; waits on the tag block", "command": "gh run list -R jstinhw/yongkang --workflow release.yml"},
    {"claim": "Release holds all assets", "status": "not_run", "result": "no release yet", "command": "gh release view v0.1.0 -R jstinhw/yongkang --json assets"},
    {"claim": "Latest download link serves", "status": "not_run", "result": "no release yet", "command": "curl -sIL https://github.com/jstinhw/yongkang/releases/latest/download/Yongkang.dmg"},
    {"claim": "Checksum and attestation verify", "status": "not_run", "result": "no release yet", "command": "shasum -a 256 -c Yongkang.dmg.sha256; gh attestation verify Yongkang.dmg --repo jstinhw/yongkang"},
    {"claim": "Gatekeeper accepts the DMG", "status": "not_run", "result": "no release yet", "command": "spctl -a -t open --context context:primary-signature -v Yongkang.dmg"}
  ],
  "holds": [
    "The workflow stops before signing if the 0.1.0 notes are missing.",
    "A run that fails before publish publishes nothing; the tag is deleted and pushed again."
  ],
  "shows": [
    {"kind": "schema", "title": "Cutting a release, the routine",
     "before": "git commit -am \"Release 1.4.0\"\ngit push                                  # CI runs make check on main\ngit tag v1.4.0 && git push origin v1.4.0",
     "after": "git switch -c release-1.4.0 && git commit -am \"Release 1.4.0\"\ngit push -u origin release-1.4.0          # open a pull request, merge it once `check` passes\ngit switch main && git pull               # main's ruleset takes changes only that way\ngit tag v1.4.0 && git push origin v1.4.0",
     "note": "A direct push to main is refused since go-public's ruleset, so the old routine failed at step two."}
  ],
  "spots": [
    {"path": "CHANGELOG.md", "lines": [10, 42], "label": "0.1.0 notes", "why": "The first thing anyone reads on the release page; the wording is yours to accept."},
    {"path": ".notebook/blocks/release-secrets.md", "lines": [37, 44], "label": "Sparkle check", "why": "Confirms the secret matches SUPublicEDKey before tagging; a mismatch strands installs silently."}
  ],
  "questions": [
    {"ask": "Ship v0.1.0 with Sign In and analytics off?", "context": "Info.plist has no Supabase or PostHog key, so both are inert in this build.", "options": ["Ship them off", "Set keys first"], "recommend": 0}
  ],
  "concerns": [
    {"title": "Changelog date is today's", "detail": "The heading says 2026-10-11. If the tag goes out on a later day, change the date in the release pull request.", "blocks": false},
    {"title": "No Developer ID on this Mac", "detail": "Membership paid 2026-10-12, awaiting Apple's approval; the Developer ID certificate waits on it.", "blocks": false}
  ],
  "outside": [
    {"kind": "read", "what": "gh secret list, gh release list and gh api visibility on jstinhw/yongkang"},
    {"kind": "read", "what": "git fetch origin and git ls-remote --tags origin"},
    {"kind": "local", "what": "security find-identity -v -p codesigning on the login keychain"}
  ],
  "files": [
    {"path": "CHANGELOG.md", "why": "0.1.0 release notes, fresh Unreleased"},
    {"path": "docs/release.md", "why": "Routine merges through a pull request"},
    {"path": ".notebook/tasks/first-release.md", "why": "Active, changelog item ticked"},
    {"path": ".notebook/blocks/release-secrets.md", "why": "The six Apple secrets, Sparkle check"},
    {"path": ".notebook/blocks/tag-v0-1-0.md", "why": "The tag push and the run"},
    {"path": ".notebook/runs/ae69afb0-2251-4946-8ca4-814f0d7ba153-work-first-release.md", "why": "This report"}
  ],
  "next": "The tag, then the website's download-live-check against v0.1.0"
}
```
