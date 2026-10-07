---
id: website-files-download
kind: memory
title: "Website files its download"
project: open-source-release
subject: open-source-release
memory_type: fact
source: agent
supersedes: []
created: 2026-10-07
updated: 2026-10-07
external: {}
---

The website (`../yongkang-projects/yongkang-website`) replaces its waitlist with the download
button and a source link on its own board, project `mac-download`, asked in
`.notebook/messages/download-button.md`. Its `download-live-check` waits on [[first-release]];
until a release exists its buttons link to the releases page, so nothing 404s. It relies on
`Yongkang.dmg` and `Yongkang.dmg.sha256` as asset names, `vX.Y.Z` tags, no draft or prerelease
releases, and the repo staying public.
