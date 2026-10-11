---
id: license-and-community
kind: task
title: "License and community files"
status: done
depends_on: []
designer: ""
project: open-source-release
owner: ""
created: 2026-10-07
updated: 2026-10-09
external: {}
---

The files an open-source repo is expected to have, so someone arriving at
`jstinhw/yongkang` knows they may use it, how to install it, how to build it and how to
contribute or report a vulnerability.

## Done when

- [x] `LICENSE` is the MIT license, copyright 2026 Justin Zen.
- [x] `README.md` opens with what Yongkang is and an **Install** section — download the DMG from
      `https://github.com/jstinhw/yongkang/releases/latest`, drag it to Applications, the
      requirements — before **Build from source**, and links the website, LICENSE and
      CONTRIBUTING.
- [x] `CONTRIBUTING.md`: build and test (`make check`, the pre-push hook), branch and pull
      request flow, that `AGENTS.md` holds the rules an agent or a person follows, and that
      user-visible changes go under `## [Unreleased]` in `CHANGELOG.md`.
- [x] `SECURITY.md`: report privately through GitHub's private vulnerability reporting, which
      versions get fixes (the latest release), and what the app sends online
      (`docs/release.md`, What goes online).
- [x] `.github/ISSUE_TEMPLATE/` has a bug report (macOS version, app version, which CLI) and a
      feature request, and `.github/pull_request_template.md` asks for `make check` and, for a
      UI change, shots before and after.
- [x] `make check` passes.

## Context

Area: repo-root community files, `README.md`, and `.github/ISSUE_TEMPLATE/` and
`.github/pull_request_template.md`. Not the workflows. The license is the project memory
`mit-license`. The download URL is the one [[releases-in-main-repo]] moves releases to; this
task only links it.

## Constraints

Keep the README's existing tour of the window and its build commands; add, don't rewrite.
No code of conduct beyond a line in CONTRIBUTING here: `CODE_OF_CONDUCT.md` comes with
[[go-public]] (the project memory `code-of-conduct-at-go-public`).
