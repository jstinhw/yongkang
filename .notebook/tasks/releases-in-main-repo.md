---
id: releases-in-main-repo
kind: task
title: "Release from the main repo"
status: done
depends_on: []
designer: ""
project: open-source-release
owner: ""
created: 2026-10-07
updated: 2026-10-09
external: {}
---

Publish each release — DMG, appcast and dSYMs — as one release of `jstinhw/yongkang` itself,
with the repo's own token, and point the update feed there.

## Done when

- [x] `.github/workflows/release.yml` publishes `Yongkang.dmg`, `appcast.xml` and the dSYMs zip
      in one release of the repo it runs in, with `GITHUB_TOKEN`; `RELEASES_REPO` and
      `RELEASES_TOKEN` are gone.
- [x] `SUFeedURL` in `App/Config/Info.plist` is
      `https://github.com/jstinhw/yongkang/releases/latest/download/appcast.xml`, and the
      appcast's enclosure URL points at the same repo.
- [x] `docs/release.md` names `jstinhw/yongkang` throughout: the publish step, What users get
      (the website's button URL), and One-time setup without the releases repo or its token.
      `docs/refactor-plan.md` 6.3 notes the move in one line.
- [x] The workflow passes `actionlint`, and `make check` passes.

## Context

Area: `.github/workflows/release.yml`, `App/Config/Info.plist`, `docs/release.md`,
`docs/refactor-plan.md`. No `v*` tag has been pushed, so nothing installed reads the old feed
and no bridging release is needed (project memory `releases-on-main-repo`). The website reads
`https://github.com/jstinhw/yongkang/releases/latest/download/Yongkang.dmg`; the asset name
`Yongkang.dmg` must not change.

## Constraints

Keep the tag-driven flow: notes from `CHANGELOG.md`, `make check` before anything is signed,
nothing published if a step before Publish fails. Grant `contents: write` only to the job that
publishes. A release is never a draft or a prerelease: GitHub's `latest` skips those, and the
website's download link and version read `latest`.
