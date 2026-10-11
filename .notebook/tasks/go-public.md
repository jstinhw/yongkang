---
id: go-public
kind: task
title: "Make the repo public"
status: done
depends_on: [history-audit, license-and-community]
designer: ""
project: open-source-release
owner: ""
created: 2026-10-07
updated: 2026-10-11
external: {}
---

Flip `jstinhw/yongkang` to public and set it up the way a public repo should be: `main`
protected, vulnerabilities reported privately, CI as the gate.

## Done when

- [x] The repo is public, with a description, the website as its homepage, and topics.
- [x] `main` has a ruleset: pull request required, the CI `check` job must pass, no force push,
      no deletion.
- [x] Private vulnerability reporting, Dependabot alerts and secret scanning with push
      protection are on.
- [x] Forked pull requests need approval before their workflows run, and no workflow a fork
      triggers can read the release secrets.
- [x] The comment in `.github/workflows/ci.yml` about private-repo macOS minutes is gone.
- [x] `CODE_OF_CONDUCT.md` is the Contributor Covenant 2.1 with a contact the user chose, and
      the conduct line in `CONTRIBUTING.md` links it.
- [x] GitHub's community profile for the repo shows every item green.

## Context

From [[history-audit]]: a clean history and tree. From [[license-and-community]]: LICENSE,
README, CONTRIBUTING, SECURITY and the templates the community profile checks; the code of
conduct is left to this task (the project memory `code-of-conduct-at-go-public`). Area: the
repo's GitHub settings, `.github/workflows/ci.yml`, `CODE_OF_CONDUCT.md` and its line in
`CONTRIBUTING.md`. The settings are the user's to change: file each as one short step in a
block, the way `sre-dev` does.

## Constraints

Never change visibility before the audit's findings are all resolved.
