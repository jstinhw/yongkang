---
id: go-public
kind: task
title: "Make the repo public"
status: todo
depends_on: [history-audit, license-and-community]
designer: ""
project: open-source-release
owner: ""
created: 2026-10-07
updated: 2026-10-07
external: {}
---

Flip `jstinhw/yongkang` to public and set it up the way a public repo should be: `main`
protected, vulnerabilities reported privately, CI as the gate.

## Done when

- [ ] The repo is public, with a description, the website as its homepage, and topics.
- [ ] `main` has a ruleset: pull request required, the CI `check` job must pass, no force push,
      no deletion.
- [ ] Private vulnerability reporting, Dependabot alerts and secret scanning with push
      protection are on.
- [ ] Forked pull requests need approval before their workflows run, and no workflow a fork
      triggers can read the release secrets.
- [ ] The comment in `.github/workflows/ci.yml` about private-repo macOS minutes is gone.
- [ ] GitHub's community profile for the repo shows every item green.

## Context

From [[history-audit]]: a clean history and tree. From [[license-and-community]]: LICENSE,
README, CONTRIBUTING, SECURITY and the templates the community profile checks. Area: the
repo's GitHub settings, and `.github/workflows/ci.yml`. The settings are the user's to change:
file each as one short step in a block, the way `sre-dev` does.

## Constraints

Never change visibility before the audit's findings are all resolved.
