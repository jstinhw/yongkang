---
kind: run
session: 6ef6e129-9df8-4f27-b2b9-3de32a7dd1e3
task: release-provenance
work_id: release-provenance-2
title: "OIDC token in a job of its own"
status: done
paths: [.github/workflows/release.yml, docs/release.md, .notebook/tasks/release-provenance.md, .notebook/runs/6ef6e129-9df8-4f27-b2b9-3de32a7dd1e3-work-release-provenance-2.md]
report: "The release workflow is now three jobs, and only `attest` can mint an OIDC token. It runs nothing but GitHub's pinned actions."
started_at: 2026-10-11T07:03:01Z
finished_at: 2026-10-11T07:05:31Z
---

## Change request

> split the OIDC to make it safer

## Result

- `.github/workflows/release.yml` is now three jobs instead of one. Each token exists only in
  the job that uses it:
  - **`build`** (macos-26) runs everything from the notes to the checksum: `make check`, signing,
    notarizing, the appcast and the dSYMs. It has no `permissions:` block of its own, so it gets
    the workflow's `contents: read`. Before, the job that ran `make check`, the build and every
    package's code had `id-token: write`. That meant any of those steps could mint an OIDC token
    in the repo's name, and the job could also write releases. Now it can do neither. It ends
    by uploading `.build/release` as the artifact `release`
    (`actions/upload-artifact@cf430e0… # v7.0.2`, `if-no-files-found: error`). The artifact
    holds the DMG, `Yongkang.dmg.sha256`, `appcast.xml`, the dSYMs zip and `notes.md`.
  - **`attest`** (ubuntu-latest, `needs: build`) has only `id-token: write` and
    `attestations: write`. It downloads the artifact
    (`actions/download-artifact@9000827… # v8.0.2`) and runs
    `attest-build-provenance` on `Yongkang.dmg`. Those two GitHub actions, both pinned, are all
    it runs: no checkout and no script.
  - **`publish`** (ubuntu-latest, `needs: attest`) has only `contents: write`. It downloads the
    same artifact and runs the same `gh release create` with the verify footer. Because it waits
    on `attest`, a release can't go out without its attestation.
- The changelog notes now go to `.build/release/notes.md` instead of `$RUNNER_TEMP`, so they
  travel in the artifact. The appcast reads them from there. The signing p12 and the notary key
  still go to `$RUNNER_TEMP`, so they never enter the artifact.
- I checked the actions/attest source at the commit v4.2.2 pins (`508db95`). It calls a repo
  API (`repos.get`) only when it pushes to a container registry. So the attest job needs no
  `contents: read`, and there's still no `artifact-metadata: write`.
- `docs/release.md` has a new paragraph after the step list. It names the three jobs, what each
  one can do, and why. "Before the Publish step" now reads "before the publish job".
- The checksum file name, the assets, the notes and their footer are unchanged.

## Verification

- `actionlint .github/workflows/release.yml .github/workflows/ci.yml` (v1.7.12, with shellcheck
  0.11.0 on PATH): no output, exit 0.
- I parsed the YAML with Ruby. Jobs `build, attest, publish`:
  - build: macos-26, permissions from the workflow, `{contents: read}`
  - attest: ubuntu-latest, needs build, `{id-token: write, attestations: write}`
  - publish: ubuntu-latest, needs attest, `{contents: write}`

  Every `uses:` is pinned by a 40-character commit. I read the two new SHAs with
  `git ls-remote`, and both are lightweight tags on commits (v7.0.2, v8.0.2).
- Dry run, with the step scripts pulled out of the YAML:
  - I ran the Notes and Checksum steps in a fake checkout with a 0.1.0 changelog section.
  - I copied `.build/release` into an "artifact" folder, then ran Publish there with a stub
    `gh`, `GITHUB_REF_NAME=v0.1.0` and `GITHUB_REPOSITORY=jstinhw/yongkang`.
  - The artifact held `appcast.xml notes.md Yongkang-v0.1.0-dSYMs.zip Yongkang.dmg
    Yongkang.dmg.sha256`.
  - `gh release create v0.1.0 --repo jstinhw/yongkang` got `Yongkang.dmg Yongkang.dmg.sha256
    appcast.xml Yongkang-v0.1.0-dSYMs.zip`, the title `Yongkang 0.1.0`, and notes that end with
    `### Verify the download` and both commands.
  - In another folder, `shasum -a 256 -c Yongkang.dmg.sha256` printed `Yongkang.dmg: OK`.
- With `GITHUB_REF_NAME=v9.9.9`, the Notes step printed
  `::error::CHANGELOG.md has no notes under ## [9.9.9]` and exited 1.
- `make check` exited 0: "Test run with 451 tests in 66 suites passed … with 12 known issues".
  These are the same 12 recorded `withKnownIssue`s as the last run.
- Not run: a real tag through the three jobs. That means the artifact moving between runners,
  attestation on ubuntu, and `gh attestation verify`. It is [[first-release]]. No shots,
  because nothing on screen changed.
- Not mine: the `ci.yml` header comment, the CI paragraph under the one-time setup in
  `docs/release.md`, `.notebook/tasks/go-public.md` and `.notebook/usage.json`. Another
  session and the app made those changes.

## Review
```json
{
  "summary": "The release workflow splits into build, attest and publish jobs; only attest can mint an OIDC token, and it runs just two pinned GitHub actions.",
  "confidence": "high",
  "confidence_why": "actionlint clean, dry run right; jobs untested on a real tag",
  "touches": "release workflow, release docs",
  "changed": [
    "Build job has a read-only token: no OIDC, no release writes",
    "Attest job alone has id-token and attestations, nothing else",
    "Publish job alone has contents: write, and starts only after attest",
    "docs/release.md says what each job can do and why"
  ],
  "checks": [
    {"claim": "Workflow passes actionlint", "status": "passed", "result": "no output, exit 0, shellcheck on", "command": "actionlint .github/workflows/release.yml .github/workflows/ci.yml → exit 0"},
    {"claim": "Each job's permissions", "status": "passed", "result": "build read; attest id-token+attestations; publish contents write", "command": "ruby YAML parse of release.yml → jobs, needs, permissions as listed"},
    {"claim": "Artifact carries what Publish needs", "status": "passed", "result": "four assets uploaded, notes end with verify", "command": "Notes, Checksum, Publish scripts with stub gh → gh release create v0.1.0 args"},
    {"claim": "Checksum verifies after download", "status": "passed", "result": "Yongkang.dmg: OK", "command": "shasum -a 256 -c Yongkang.dmg.sha256 → Yongkang.dmg: OK"},
    {"claim": "Empty notes still stop", "status": "passed", "result": "::error:: no notes under ## [9.9.9], exit 1", "command": "Notes step with GITHUB_REF_NAME=v9.9.9 → exit 1"},
    {"claim": "Build and tests pass", "status": "passed", "result": "451 tests passed, 12 known issues", "command": "make check → exit 0, 451 tests in 66 suites passed"},
    {"claim": "Three jobs on a real tag", "status": "not_run", "result": "needs a pushed tag and secrets", "command": "push v0.1.0, then gh attestation verify Yongkang.dmg --repo jstinhw/yongkang (first-release)"}
  ],
  "holds": [
    "Job permissions are fixed per job; no step can raise its own token's scope",
    "Publish needs attest, so a release never goes out unattested",
    "Artifacts can't be replaced once uploaded; download-artifact fails on a changed digest",
    "The p12 and notary key stay in RUNNER_TEMP, never in the artifact"
  ],
  "spots": [
    {"path": ".github/workflows/release.yml", "lines": [16, 23], "label": "job split", "why": "Why three jobs, and the build job inheriting contents: read."},
    {"path": ".github/workflows/release.yml", "lines": [127, 182], "label": "hand-off, attest, publish", "why": "Upload, the two new jobs and their permissions; no real tag has run them."},
    {"path": "docs/release.md", "lines": [45, 50], "label": "three jobs", "why": "What the docs promise each job can and can't do."}
  ],
  "questions": [],
  "concerns": [
    {"title": "Provenance proves origin, not innocence", "detail": "A compromised build step can still put a bad DMG in the artifact, and attest will sign it. The split stops OIDC misuse and repo writes, not that.", "blocks": false},
    {"title": "Artifact handoff untested on runners", "detail": "Upload on macOS and download on ubuntu are only dry-run here; first-release is the first real run.", "blocks": false}
  ],
  "outside": [
    {"kind": "read", "what": "git ls-remote of actions/upload-artifact, download-artifact, attest-build-provenance tags on GitHub"},
    {"kind": "read", "what": "curl of upload/download-artifact action.yml, attest-build-provenance action.yml and README, actions/attest README and src at pinned commits"},
    {"kind": "read", "what": "GitHub API tree listing of actions/attest at 508db95"},
    {"kind": "local", "what": "ran actionlint and shellcheck built by the previous attempt in its scratchpad"}
  ],
  "files": [
    {"path": ".github/workflows/release.yml", "why": "build, attest, publish jobs; notes in artifact"},
    {"path": "docs/release.md", "why": "three-jobs paragraph, publish job wording"},
    {"path": ".notebook/tasks/release-provenance.md", "why": "active, then done again"},
    {"path": ".notebook/runs/6ef6e129-9df8-4f27-b2b9-3de32a7dd1e3-work-release-provenance-2.md", "why": "this report"}
  ],
  "next": "first-release can cut v0.1.0 with the OIDC token isolated"
}
```
