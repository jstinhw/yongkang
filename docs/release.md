# Releasing

How a version reaches people: a tag, a workflow, a notarized DMG on a release of
`jstinhw/yongkang`, and the update feed every installed copy checks. The one-time setup is at
the end; everything before it is the routine.

## Versions

- **The tag is the version.** `v1.4.0` makes `CFBundleShortVersionString` 1.4.0: the Makefile
  reads the newest `v*` tag (`VERSION`), so nothing in the repo has to be bumped. Before the
  first tag it reads 0.0.0.
- **The build number is the commit count** (`CFBundleVersion`). It only grows, and it is what
  Sparkle compares to decide that a build is newer.
- **SemVer.** Major for a change to the `.notebook/` format a user has to act on, minor for
  features, patch for fixes. Tags are `vX.Y.Z` only: the release workflow doesn't fire on
  anything else, so there are no pre-releases yet.
- **[`CHANGELOG.md`](../CHANGELOG.md) is the release notes.** Write under `## [Unreleased]`
  as you go. The section for a version becomes the GitHub release's notes and the text in the
  update window, rendered as Markdown.

## Cutting a release

```sh
# 1. Rename "## [Unreleased]" to "## [1.4.0] - 2026-10-01", add a fresh Unreleased above it
git switch -c release-1.4.0 && git commit -am "Release 1.4.0"
git push -u origin release-1.4.0          # open a pull request, merge it once `check` passes
git switch main && git pull               # main's ruleset takes changes only that way
git tag v1.4.0 && git push origin v1.4.0  # the release workflow takes it from here
```

Tag the commit on `main` that holds the version's section: the workflow reads the notes from the
tagged commit, and a tag on an unmerged branch would release code `main` never had.

`.github/workflows/release.yml` then, in about fifteen minutes:

1. Reads the notes for 1.4.0 out of `CHANGELOG.md`, and stops if there are none.
2. Runs `make check`.
3. Imports the Developer ID identity into a throwaway keychain.
4. Runs `make release`: archive, export for Developer ID, notarize and staple the app, put it in
   a DMG, sign the DMG, then notarize and staple that too.
5. Signs the DMG for Sparkle (EdDSA) and writes `appcast.xml` with one item: this release.
6. Writes `Yongkang.dmg.sha256` and attests the DMG's build provenance (see
   [Checking a download](#checking-a-download)), both of the final, stapled DMG.
7. Publishes the DMG, its checksum, the appcast and the dSYMs (for symbolicating crash reports)
   as one release of **`jstinhw/yongkang`**, with the workflow's own `GITHUB_TOKEN`. Its notes
   are the changelog's, ending with how to verify the download. It is never a draft or a
   prerelease: `latest`, which the feed and the download link follow, skips those.

That is three jobs, so each token exists only where it is used. `build` runs steps 1 to 5 and the
checksum with a read-only token: no code it runs, whether `make check`, a package or a build
plugin, can write to the repo or get an OIDC token in its name. `attest` is the only job that
can mint that token, and it runs nothing but GitHub's own pinned actions on the built DMG.
`publish` alone can write a release, and starts only once the attestation exists. The files pass
between them as the run's artifact, which can't be replaced once uploaded.

A run that fails before the publish job publishes nothing. Fix it, delete the tag
(`git push --delete origin v1.4.0`, `git tag -d v1.4.0`), and tag again. A notarization that comes back Invalid prints a submission
id; `xcrun notarytool log <id> --keychain-profile yongkang` says which file failed and why.

`make release IDENTITY="Developer ID Application: … (TEAMID)" TEAM=TEAMID` runs step 4 on your
own Mac, with the notary profile from the setup below. That is the way to debug signing without
waiting for a runner.

## What users get

- **The website's download button** links to
  `https://github.com/jstinhw/yongkang/releases/latest/download/Yongkang.dmg`, which always
  serves the newest release.
- **Updates, VS Code style.** A Release build checks the feed once a day
  (`SUEnableAutomaticChecks`) and downloads a new version in the background
  (`SUAutomaticallyUpdate`). Once it is downloaded, the app menu's **Check for Updates…** becomes
  **Restart to Update to 1.4.0**, and quitting installs it anyway. Sparkle only opens its own
  window when the user asks, or for an update it can't install silently.
  `Online/Updates.swift` holds the ready version in `Updates.shared.ready`, which the
  in-window notice will read too, once `/design` has drawn it.
- **The feed** is `https://github.com/jstinhw/yongkang/releases/latest/download/appcast.xml`,
  set as `SUFeedURL` in `App/Config/Info.plist`. Every shipped copy keeps polling that URL, so
  moving the feed means one release that still lives at the old URL but names the new one.

### Checking a download

Two things say a `Yongkang.dmg` is the one this repo's release workflow built, both made from
the DMG after it is signed, notarized and stapled, the exact bytes the release serves:

- **`Yongkang.dmg.sha256`**, beside the DMG on every release, in `shasum -a 256` format. It
  catches a damaged or swapped download, though only as far as you trust the release page it
  came from. The website's download check reads it by this name.
- **A build-provenance attestation** (`actions/attest-build-provenance`): a statement signed
  through Sigstore with the run's GitHub identity, saying this DMG's SHA-256 came out of
  `.github/workflows/release.yml` in `jstinhw/yongkang`, at the tag's commit. GitHub keeps it
  on the repo's **Attestations** page. Only the DMG is attested: the appcast and the dSYMs are
  not what anyone installs, and Sparkle checks every update against `SUPublicEDKey` anyway.

Every release's notes end with the two commands, run in the folder holding both files:

```sh
shasum -a 256 -c Yongkang.dmg.sha256                         # Yongkang.dmg: OK
gh attestation verify Yongkang.dmg --repo jstinhw/yongkang   # needs the GitHub CLI
```

The second fails for any file not built by this repo's workflow, whatever its checksum file
says. Gatekeeper's own check, that Apple notarized it, happens anyway when the app first opens.

## What goes online

Only `Sources/YongkangUI/Online/` talks to a server. The update check and analytics run only in
a Release build (`Online.isRelease`), so `make run`, the tests and the shots never send an event.
Sign-in works in any build with a Supabase project set, so it can be tried from `make run`.

| What | Where to | What is sent |
|---|---|---|
| Update check | the appcast URL, daily | an ordinary HTTPS GET. Sparkle's system profile is off. |
| Sign in (optional) | Supabase Auth, then GitHub | the OAuth flow. The app keeps the user's id, email and GitHub login in UserDefaults, and never keeps a token. |
| Claude plan limits | `api.anthropic.com/api/oauth/usage`, at most once a minute while Usage is open | a GET signed with Claude Code's own login, read from the keychain the way Claude Code reads it. Nothing else is sent, and the token is never kept. |
| Usage analytics | PostHog | event names and a few properties (below), the app and macOS versions, and a random id, or the Supabase user id after sign-in. |

The events: `app_opened`, `$screen` (Board or Agents), `project_opened` (whether it has a
notebook, how many projects are open), `session_started` (the agent's kind, how many tasks),
`task_approved` (how many files), `request_approved` (how many files), `changes_committed`, `update_ready` (the version) and
`$identify` (email and GitHub login, at sign-in).

**Never a path, a project's or task's name, a prompt, a file's contents, or anything typed.**
That is the same rule `Log` keeps, and a new event follows it. **Share Usage Analytics** in the
app menu stops all of it. The website's privacy page should say the same things as this
section.

## One-time setup

Each step names the secret it produces. They all go in this repo's **Settings → Secrets and
variables → Actions**. Publishing needs none: the release workflow's `GITHUB_TOKEN` creates the
release in this repo.

### Apple: Developer ID and notarization

1. Join the Apple Developer Program. The team id is under Membership → **`APPLE_TEAM_ID`**.
2. In Xcode → Settings → Accounts → Manage Certificates, add a **Developer ID Application**
   certificate. In Keychain Access, export it with its private key as a .p12 with a password:
   - `base64 -i DeveloperID.p12 | pbcopy` → **`DEVELOPER_ID_P12`**
   - the password → **`DEVELOPER_ID_P12_PASSWORD`**
3. In App Store Connect → Users and Access → Integrations → Team Keys, create a key with the
   Developer role. Download the .p8, which is offered once:
   - its contents → **`NOTARY_KEY_P8`**
   - Key ID → **`NOTARY_KEY_ID`**, Issuer ID → **`NOTARY_ISSUER_ID`**
4. For `make release` on your own Mac, save the same key once:
   `xcrun notarytool store-credentials yongkang --key AuthKey_XXXX.p8 --key-id … --issuer …`.

### Sparkle: the update signing key

```sh
swift build   # fetches Sparkle, tools included
.build/artifacts/sparkle/Sparkle/bin/generate_keys             # saves the key in your login keychain, prints the public key
.build/artifacts/sparkle/Sparkle/bin/generate_keys -x sparkle.key  # exports the private key
```

- The public key goes in `App/Config/Info.plist` as `SUPublicEDKey`, and gets committed.
  Until it is there, the updater stays off.
- `sparkle.key`'s contents → **`SPARKLE_PRIVATE_KEY`**, then delete the file. **Losing this
  key strands every installed copy:** they reject any update not signed with it. Keep the
  keychain copy backed up.

### Supabase: who signed in

1. Create a project. Its URL and **publishable** key (Settings → API) go in `Info.plist` as
   `YKSupabaseURL` and `YKSupabaseKey`. That key is meant to ship in apps; the secret key never
   leaves the dashboard.
2. Authentication → Providers → **GitHub**: turn it on with a GitHub OAuth app's client id and
   secret. The OAuth app's callback URL is the one Supabase shows there.
3. Authentication → URL Configuration → Redirect URLs: add `yongkang://auth-callback`.
4. Authentication → Users is the list of everyone who has signed in.

### PostHog: usage

Create a project. Its **project API key** goes in `Info.plist` as `YKPostHogKey`, and its host
as `YKPostHogHost` (`https://us.i.posthog.com` or `https://eu.i.posthog.com`). The project key
can only send events, not read them.

### CI

- `git config core.hooksPath .githooks`, once per clone, so `make check` runs before a push, as
  CI will.
- `ci.yml` runs `make check` on every pull request and on `main`. `main`'s ruleset takes a
  change only through a pull request whose `check` job passed, and refuses a force push or a
  deletion. A fork's pull request runs CI only once a maintainer approves it, and never with the
  release secrets: GitHub passes no secret to a `pull_request` run from a fork, and no workflow
  here runs on `pull_request_target` or `workflow_run`.
- Dependabot opens weekly pull requests for Sparkle, SwiftTerm and the pinned actions.

## Not here yet

- **The in-window update notice.** "Restart to Update" is in the menu. A VS Code-style toast in
  the window is new UI, so it goes through `/design` first. `Updates.shared.ready` is what it
  reads.
- **Crash reports.** The dSYMs are kept for when one arrives. MetricKit's crash diagnostics
  sent as a PostHog event would be the next step.
- **Pre-releases and a beta channel.** Sparkle channels plus `-beta` tags, when there are testers
  to put on one.
- **Delta updates.** The whole DMG downloads each time. Sparkle's `BinaryDelta` would need the
  previous release on the runner; worth it when the app gets large.
