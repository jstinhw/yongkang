---
id: release-provenance
kind: task
title: "Checksum and provenance"
status: done
depends_on: [releases-in-main-repo]
designer: ""
project: open-source-release
owner: ""
created: 2026-10-07
updated: 2026-10-11
external: {}
---

Let anyone check that the DMG they downloaded is the one this repo's workflow built: a SHA-256
checksum beside it, and a GitHub build-provenance attestation.

## Done when

- [x] Each release carries `Yongkang.dmg.sha256` (`shasum -a 256` format) beside the DMG.
- [x] The workflow attests the DMG with `actions/attest-build-provenance`, pinned by commit
      like the other actions, with only the `id-token` and `attestations` permissions it needs.
- [x] The release notes end with how to verify: `shasum -a 256 -c Yongkang.dmg.sha256`, and
      `gh attestation verify Yongkang.dmg --repo jstinhw/yongkang`.
- [x] `docs/release.md` says what is attested and how a user checks it.
- [x] The workflow passes `actionlint`, and `make check` passes.

## Context

From [[releases-in-main-repo]]: the publish step in `.github/workflows/release.yml` that now
creates one release in `jstinhw/yongkang` with `GITHUB_TOKEN`. Area: that workflow and
`docs/release.md`. The website's `download-live-check` checks the DMG against `Yongkang.dmg.sha256`: keep that
name.

## Constraints

The checksum and attestation are made after the DMG is signed, notarized and stapled — the
final bytes users download.
