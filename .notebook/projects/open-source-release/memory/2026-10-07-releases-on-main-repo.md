---
id: releases-on-main-repo
kind: memory
title: "Releases on the main repo"
project: open-source-release
subject: releases-in-main-repo
memory_type: decision
source: agent
supersedes: []
created: 2026-10-07
updated: 2026-10-07
external: {}
---

Once the code is public, releases are published on `jstinhw/yongkang` itself, and
`jstinhw/yongkang-releases` is retired. The DMG is at
`https://github.com/jstinhw/yongkang/releases/latest/download/Yongkang.dmg` and the feed at
`…/releases/latest/download/appcast.xml`.

## Why

The separate repo existed only because the code was private. One repo means one token fewer
(`RELEASES_TOKEN`), the dSYMs, DMG and notes in one release, and the source beside the binary
it built. No `v*` tag was ever pushed, so no installed copy follows the old feed and moving it
needs no bridging release.
