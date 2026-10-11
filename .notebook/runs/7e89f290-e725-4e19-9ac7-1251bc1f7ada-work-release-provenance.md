---
kind: run
session: 7e89f290-e725-4e19-9ac7-1251bc1f7ada
task: release-provenance
work_id: release-provenance
title: "Checksum and attestation beside the DMG"
status: done
paths: [.github/workflows/release.yml, docs/release.md, .notebook/tasks/release-provenance.md, .notebook/runs/7e89f290-e725-4e19-9ac7-1251bc1f7ada-work-release-provenance.md]
report: "A release now carries Yongkang.dmg.sha256 and a build-provenance attestation of the stapled DMG, and its notes say how to verify both."
started_at: 2026-10-11T06:38:00Z
finished_at: 2026-10-11T06:48:00Z
---

## Result

- `.github/workflows/release.yml`
  - Two steps come after dSYMs and before Publish, so they run on the DMG once it is signed,
    notarized and stapled:
    - **Checksum** runs `shasum -a 256 Yongkang.dmg > Yongkang.dmg.sha256` inside
      `.build/release`, so the file names `Yongkang.dmg` with no path. `shasum -c` works in any
      folder holding both files.
    - **`actions/attest-build-provenance@4d101475d8b20a2381f78447822ac1eab6504dd8 # v4.2.2`**
      (the newest tag) attests `.build/release/Yongkang.dmg`. Dependabot already bumps pinned
      actions.
  - The job's permissions are `contents: write`, `id-token: write` and `attestations: write`.
    I left out `artifact-metadata: write`, which the actions/attest README lists, because it is
    only used for a storage record, and in v4.2.2 that happens only with `push-to-registry`
    (container images).
  - **Publish** uploads `Yongkang.dmg.sha256` too, and its notes are now `release-notes.md`: the
    changelog section plus a `### Verify the download` footer with the two commands. The repo in
    the command comes from `$GITHUB_REPOSITORY`, which is `jstinhw/yongkang`. The appcast keeps the
    plain changelog notes, so the update window doesn't show download-checking steps.
    Sparkle checks its own EdDSA signature.
- `docs/release.md`
  - The step list has a new step 6 (checksum and attestation, both of the stapled DMG), and step 7
    publishes the checksum and says the notes end with how to verify.
  - New section **Checking a download** under What users get. It says what each check proves,
    that only the DMG is attested and why, and the two commands. It also notes that the website
    reads `Yongkang.dmg.sha256` by that name.

## Verification

- `actionlint .github/workflows/release.yml .github/workflows/ci.yml` (actionlint v1.7.12, with
  shellcheck 0.11.0 on PATH) printed nothing, exit 0.
- Dry run of the Checksum and Publish `run:` scripts, pulled from the YAML with Ruby, against a
  fake DMG, with a stub `gh` that records its arguments, `GITHUB_REF_NAME=v0.1.0` and
  `GITHUB_REPOSITORY=jstinhw/yongkang`:
  - The checksum file reads `2aff92…6ed9  Yongkang.dmg`. Copied into another folder,
    `shasum -a 256 -c Yongkang.dmg.sha256` printed `Yongkang.dmg: OK`.
  - `gh release create v0.1.0 --repo jstinhw/yongkang` got the DMG, the `.sha256`, the appcast and
    the dSYMs zip, with `--notes-file …/release-notes.md`.
  - The published notes were the changelog section followed by `### Verify the download`, with
    `shasum -a 256 -c Yongkang.dmg.sha256` and
    `gh attestation verify Yongkang.dmg --repo jstinhw/yongkang`. `notes.md`, which the appcast
    uses, was unchanged.
- The parsed YAML has job permissions `{contents: write, id-token: write, attestations: write}`.
- `make check` exited 0: "Test run with 451 tests in 66 suites passed … with 12 known issues".
  These are the existing recorded `withKnownIssue`s, the same 12 as the last run; none comes from
  this change.
- Not run: a real attestation and `gh attestation verify` against it. Both need a pushed tag, which
  is [[first-release]]. No shots, because nothing on screen changed.
- `.notebook/tasks/go-public.md` (set active) and `.notebook/usage.json` show in `git diff` but
  are not mine: another session and the app wrote them.

## Review
```json
{
  "summary": "Each release now carries Yongkang.dmg.sha256 and a build-provenance attestation of the stapled DMG; the release notes end with both verify commands.",
  "confidence": "high",
  "confidence_why": "actionlint clean, dry run right; real attestation untested until a tag",
  "touches": "release workflow, release docs",
  "changed": [
    "Release assets add Yongkang.dmg.sha256 in shasum format",
    "DMG attested by attest-build-provenance v4.2.2, pinned by commit",
    "Release notes end with shasum and gh attestation commands",
    "docs/release.md explains what is attested and how to check"
  ],
  "checks": [
    {"claim": "Workflow passes actionlint", "status": "passed", "result": "no output, exit 0, shellcheck on", "command": "actionlint .github/workflows/release.yml .github/workflows/ci.yml → exit 0"},
    {"claim": "Checksum verifies after download", "status": "passed", "result": "Yongkang.dmg: OK", "command": "Checksum step on a fake DMG; shasum -a 256 -c Yongkang.dmg.sha256 → Yongkang.dmg: OK"},
    {"claim": "Publish uploads four assets, footer", "status": "passed", "result": "dmg, sha256, appcast, dSYMs; footer on release only", "command": "Publish step with stub gh, GITHUB_REPOSITORY=jstinhw/yongkang → args and notes recorded"},
    {"claim": "Build and tests pass", "status": "passed", "result": "451 tests passed, 12 known issues", "command": "make check → exit 0, 451 tests in 66 suites passed"},
    {"claim": "Real attestation verifies", "status": "not_run", "result": "needs a pushed tag and secrets", "command": "gh attestation verify Yongkang.dmg --repo jstinhw/yongkang (first-release)"}
  ],
  "holds": [
    "Checksum and attestation run after staple, before Publish; nothing changes the DMG after",
    "A failed attestation stops the run before anything is published"
  ],
  "spots": [
    {"path": ".github/workflows/release.yml", "lines": [20, 23], "label": "job permissions", "why": "id-token is job-wide, so build steps could mint an OIDC token too; see concern."},
    {"path": ".github/workflows/release.yml", "lines": [119, 151], "label": "Checksum, Attest, Publish", "why": "The new steps and the notes heredoc; no real tag has run them."},
    {"path": "docs/release.md", "lines": [69, 90], "label": "Checking a download", "why": "What the docs promise each check proves."}
  ],
  "questions": [],
  "concerns": [
    {"title": "OIDC token reachable by build steps", "detail": "Splitting attest into its own job fixes it but needs two more pinned actions; a compromised build could backdoor the DMG anyway.", "blocks": false}
  ],
  "outside": [
    {"kind": "read", "what": "git ls-remote of actions/attest-build-provenance tags on GitHub"},
    {"kind": "read", "what": "curl of attest-build-provenance and actions/attest action.yml, README, source at pinned commits"},
    {"kind": "read", "what": "go install of actionlint v1.7.12 from the Go module proxy, into the scratchpad"},
    {"kind": "local", "what": "Go module cache filled with actionlint's modules"},
    {"kind": "read", "what": "pip install shellcheck-py from PyPI into a scratchpad venv"}
  ],
  "files": [
    {"path": ".github/workflows/release.yml", "why": "checksum, attestation, permissions, notes footer"},
    {"path": "docs/release.md", "why": "steps 6–7, Checking a download section"},
    {"path": ".notebook/tasks/release-provenance.md", "why": "status done, Done when ticked"},
    {"path": ".notebook/runs/7e89f290-e725-4e19-9ac7-1251bc1f7ada-work-release-provenance.md", "why": "this report"}
  ],
  "next": "first-release can cut v0.1.0 with checksum and attestation"
}
```
