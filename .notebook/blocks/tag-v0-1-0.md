---
kind: block
status: open
session: ae69afb0-2251-4946-8ca4-814f0d7ba153
task: first-release
title: "Tag v0.1.0"
url: https://github.com/jstinhw/yongkang/actions/workflows/release.yml
run: ""
action: "Once the release secrets are set and the 0.1.0 changelog is on main, have the user push the v0.1.0 tag, then watch the release run to a published release."
created: 2026-10-11
updated: 2026-10-11
resolution: ""
---

v0.1.0 is cut by pushing its tag; the workflow does the rest in about fifteen minutes. The tag
waits for two things: the release secrets (the block "Release signing secrets") and the
`## [0.1.0]` changelog on `main`, which reaches it through a pull request like any change.

## Needed from you

- [ ] This task's changes (`CHANGELOG.md`, `docs/release.md`) merged into `main` through a
      pull request whose `check` passed.
- [ ] The `v0.1.0` tag pushed, on the `main` commit that holds them.

## Steps

The repo is `/Users/justinzen/Desktop/justin/justinzen/sources/projects/yongkang`. Never tag,
push, commit or open a pull request yourself: each is the user's, approved in `run:` or done
in their own tools.

1. **Ready?** All of these, or stop and say which is missing:
   - `.notebook/blocks/release-secrets.md` is `status: done`, and `gh secret list -R
     jstinhw/yongkang` lists the seven secrets it names.
   - `git fetch origin` then `git show origin/main:CHANGELOG.md | grep -n '^## \[0.1.0\]'`
     prints the heading. If not, the user's next step is the pull request: they commit this
     task's changes on a branch (Review does that), push it, open a pull request to `main` and
     merge it once `check` passes. Poll the grep until it shows.
   - `gh run list -R jstinhw/yongkang --workflow ci.yml --branch main -L 1 --json
     headSha,conclusion` is `success` on `git rev-parse origin/main`.
   - `git ls-remote --tags origin v0.1.0` prints nothing, and `gh release list -R
     jstinhw/yongkang` has no v0.1.0.
2. **Tag.** Set `run:` to the tag on that exact commit, so a later push to `main` cannot change
   what is released: `git -C /Users/justinzen/Desktop/justin/justinzen/sources/projects/yongkang tag v0.1.0 <origin/main sha> && git -C /Users/justinzen/Desktop/justin/justinzen/sources/projects/yongkang push origin v0.1.0`.
   Say before they approve: the pre-push hook runs `make check` first (a few minutes); the
   push starts a public release that every copy of the app and the website's button will
   follow; a run that fails before publishing publishes nothing, but a published release
   is public at once. Clear `run:` once it has run.
3. **Watch.** `gh run list -R jstinhw/yongkang --workflow release.yml -L 1 --json
   databaseId,status,conclusion,headBranch` shows the `v0.1.0` run; poll it every minute
   (it takes about fifteen). If it fails, `gh run view <id> -R jstinhw/yongkang --log-failed`,
   and come back to the session with the failing step: the fix goes through a pull request, and
   the tag is deleted and pushed again as `docs/release.md` says, both by the user in `run:`.
4. **Published.** `gh release view v0.1.0 -R jstinhw/yongkang --json isDraft,isPrerelease,assets
   --jq '{isDraft, isPrerelease, assets: [.assets[].name]}'` shows both false and
   `Yongkang.dmg`, `Yongkang.dmg.sha256`, `appcast.xml` and `Yongkang-v0.1.0-dSYMs.zip`.

Then set this block `status: done` with a one-line `resolution` naming the tagged sha and the
run id. The first-release session downloads and checks the DMG itself.
