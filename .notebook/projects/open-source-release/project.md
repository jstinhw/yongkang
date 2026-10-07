---
id: open-source-release
kind: project
title: "Open source and release"
status: todo
depends_on: []
repos: [.]
roadmap: agent-team-console
owner: ""
created: 2026-10-07
updated: 2026-10-07
external: {}
---

Yongkang's code goes public on GitHub under the MIT license, and its releases are published
from that same repo: a signed, notarized DMG with a checksum and build provenance, cut from a
`vX.Y.Z` tag, with notes from `CHANGELOG.md` and a Sparkle feed every installed copy follows.
The website's waitlist becomes a download button, filed on the website's own board.

## Outcome

Anyone can read, build and contribute to Yongkang from `jstinhw/yongkang`, and anyone on a Mac
can download v0.1.0 from that repo's latest release — the link the website's button points at
— open it with no Gatekeeper prompt, check what they downloaded, and take later versions
through **Restart to Update**.

## Done when

- [ ] `jstinhw/yongkang` is public, with nothing in its history or tracked files that should not
      be: no secret, no personal data, no machine-local path.
- [ ] The repo has a LICENSE, a README that says how to install and how to build, and
      CONTRIBUTING and SECURITY files; GitHub's community profile shows them.
- [ ] A `v*` tag publishes the DMG, `Yongkang.dmg.sha256` and `appcast.xml` as a release of
      `jstinhw/yongkang` itself, with a build-provenance attestation, and no other repo or
      personal token is involved.
- [ ] `https://github.com/jstinhw/yongkang/releases/latest/download/Yongkang.dmg` serves v0.1.0,
      which opens on a clean Mac with no Gatekeeper prompt.
- [ ] `main` accepts changes only through pull requests that pass CI.

## Context

No `v*` tag has ever been pushed, so no installed copy polls the old feed at
`jstinhw/yongkang-releases`: the feed can move with no bridging release. `docs/release.md`
has the routine and the one-time setup; the Developer ID, notarization and Sparkle secrets are
the user's to create there.

The website (`../yongkang-projects/yongkang-website`) replaces its waitlist with the download
button on its own board, as project `mac-download`: its `release-source-repo` reads the
latest release of `jstinhw/yongkang`, and its `download-live-check` waits on
[[first-release]]. It relies on the asset names `Yongkang.dmg` and `Yongkang.dmg.sha256`,
`vX.Y.Z` tags, releases that are never drafts or prereleases, and the repo staying public.

## Approach

Keep the tag-driven release the repo already has — Keep a Changelog notes, SemVer, the tag is
the version, `make release` on a runner — and change only where it publishes and what it adds:
the release lands in the public repo with the repo's own `GITHUB_TOKEN`, beside a SHA-256
checksum and a GitHub artifact attestation. Before the repo goes public, its whole history is
audited, because making it public publishes every past commit.

## Tasks

1. [[history-audit]] — nothing private in the history or the tracked files.
2. [[license-and-community]] — LICENSE, README, CONTRIBUTING, SECURITY, templates.
3. [[releases-in-main-repo]] — releases and the feed move to `jstinhw/yongkang`.
4. [[release-provenance]] — checksum and attestation beside the DMG.
5. [[go-public]] — the repo goes public, with `main` protected.
6. [[first-release]] — v0.1.0 cut, downloaded and opened on a clean Mac.

Tasks 1, 2 and 3 can start at once.

## Decisions

- Releases are published on the public repo; `jstinhw/yongkang-releases` is retired.
- MIT license.
- The first version is 0.1.0.
- The website files its own download button.
- The notebook stays tracked and public, after the audit.
