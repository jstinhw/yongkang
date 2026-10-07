---
id: first-release
kind: task
title: "Cut v0.1.0"
status: todo
depends_on: [go-public, release-provenance]
designer: ""
project: open-source-release
owner: ""
created: 2026-10-07
updated: 2026-10-07
external: {}
---

The first public release: v0.1.0 tagged, built, published on `jstinhw/yongkang`, downloaded
from the latest-release URL and opened on a clean Mac.

## Done when

- [ ] The release secrets in `docs/release.md` One-time setup are set on `jstinhw/yongkang`
      (Developer ID, notarization, Sparkle), each confirmed by the user in a block.
- [ ] `CHANGELOG.md` has a `## [0.1.0] - <date>` section describing the app as first released,
      and a fresh `## [Unreleased]` above it.
- [ ] The `v0.1.0` tag's workflow run succeeds, and its release holds `Yongkang.dmg`,
      `Yongkang.dmg.sha256`, `appcast.xml`, the dSYMs zip and an attestation.
- [ ] `curl -sIL https://github.com/jstinhw/yongkang/releases/latest/download/Yongkang.dmg`
      ends in 200, the checksum and `gh attestation verify` pass on the downloaded file, and
      `spctl -a -t open --context context:primary-signature -v` accepts it.
- [ ] The user opens the downloaded DMG and the app on a Mac with no Gatekeeper prompt, and
      confirms it in a block.

## Context

From [[go-public]]: the repo is public, so release assets download without a login. From
[[release-provenance]]: the release workflow publishing the DMG, checksum, appcast, dSYMs and
attestation on this repo. Version 0.1.0 is the project memory `first-version`. The routine is
`docs/release.md`, Cutting a release.

The website (`../yongkang-projects/yongkang-website`) waits on this in its task
`download-live-check`: after v0.1.0 is published, the user pushes the website's `main` (it reads
the version at build time), and it checks both Download buttons against this release. Until
then its buttons link to `https://github.com/jstinhw/yongkang/releases`.

## Constraints

The agent never pushes or tags: it prepares the CHANGELOG commit, and the tag and push are the
user's one step in a block. A failed run is fixed and re-tagged as `docs/release.md` says.
