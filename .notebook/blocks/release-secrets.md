---
kind: block
status: open
session: ae69afb0-2251-4946-8ca4-814f0d7ba153
task: first-release
title: "Release signing secrets"
url: https://developer.apple.com/account
run: ""
action: "Get the Developer ID and notarization secrets set on jstinhw/yongkang, and confirm SPARKLE_PRIVATE_KEY matches the app's public key."
created: 2026-10-11
updated: 2026-10-12
resolution: ""
---

The release workflow signs, notarizes and Sparkle-signs v0.1.0 with secrets only you can make.
`jstinhw/yongkang` has `SPARKLE_PRIVATE_KEY` (set 2026-10-09) and none of the Apple ones, and
this Mac has no Developer ID certificate yet. Without them the v0.1.0 run stops at signing.

The Apple Developer Program was paid for on 2026-10-12 and is waiting on Apple's approval
(up to 48 hours); the Developer ID certificate can be made only after that.

## Needed from you

- [ ] A Developer ID Application certificate, exported as a .p12 with a password.
- [ ] An App Store Connect team key with the Developer role (the .p8, its Key ID, Issuer ID).
- [ ] The six Apple secrets set on the repo: `APPLE_TEAM_ID`, `DEVELOPER_ID_P12`,
      `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_KEY_P8`, `NOTARY_KEY_ID`, `NOTARY_ISSUER_ID`.
- [ ] Your word that `SPARKLE_PRIVATE_KEY` came from the key whose public half is in
      `App/Config/Info.plist`, or that it is set again from it.

## Steps

The repo is `/Users/justinzen/Desktop/justin/justinzen/sources/projects/yongkang`. Every secret
goes in through the page in `url:` or a `gh secret set` the user approves in `run:`; never print,
echo or write a secret's value anywhere the repo tracks. `docs/release.md` → One-time setup is
the source for each.

1. **What exists.** `gh secret list -R jstinhw/yongkang` (names only). Skip any step below whose
   secret is already listed, and say so.
2. **Sparkle first: a wrong key strands every installed copy, and no run would show it.**
   `.build/artifacts/sparkle/Sparkle/bin/generate_keys -p` prints the public key of the login
   keychain's Sparkle key (macOS may ask the user to allow keychain access). It must equal
   `SUPublicEDKey` in `App/Config/Info.plist`, `7EgqQ1OMAQfkD+MlcqZVNggc+dfVXlLiOWnjFLpOj9k=`.
   If it does not, stop and come back to the session: the key in the plist and the one in the
   keychain differ, and that is the user's call. If it matches, ask the user whether the secret
   was exported from this key. If they are not sure, set it again: `run:`
   `umask 077 && /Users/justinzen/Desktop/justin/justinzen/sources/projects/yongkang/.build/artifacts/sparkle/Sparkle/bin/generate_keys -x /private/tmp/sparkle.key && gh secret set SPARKLE_PRIVATE_KEY -R jstinhw/yongkang < /private/tmp/sparkle.key; rm -f /private/tmp/sparkle.key`.
3. **Developer ID certificate.** Needs the Apple Developer Program's Account Holder. Xcode →
   Settings → Accounts → the team → **Manage Certificates…** → **+** → **Developer ID
   Application**. Poll `security find-identity -v -p codesigning` until a `Developer ID
   Application: … (TEAMID)` line shows; the team id is the part in brackets. Then in Keychain
   Access → My Certificates, the user exports that certificate with its private key as a .p12
   with a password, and says where they saved it.
4. **Notary key.** App Store Connect → Users and Access → Integrations → Team Keys → **+**,
   role **Developer**; set `url:` to `https://appstoreconnect.apple.com/access/integrations/api`.
   The .p8 downloads once: the user says where. Key ID and Issuer ID are on that page.
   Check it works before going on: `xcrun notarytool history --key <p8> --key-id <id> --issuer
   <issuer>` exits 0 (a read; it lists past submissions, likely none).
5. **Set them.** One `run:` for the file-based and plain ones, with the paths and ids filled in:
   `base64 -i <p12 path> | gh secret set DEVELOPER_ID_P12 -R jstinhw/yongkang && gh secret set NOTARY_KEY_P8 -R jstinhw/yongkang < <p8 path> && gh secret set APPLE_TEAM_ID -R jstinhw/yongkang --body <TEAMID> && gh secret set NOTARY_KEY_ID -R jstinhw/yongkang --body <key id> && gh secret set NOTARY_ISSUER_ID -R jstinhw/yongkang --body <issuer id>`.
   The .p12 password goes in by hand on the page in `url:` → **New repository secret** →
   `DEVELOPER_ID_P12_PASSWORD`, so it is never in a command line.
6. **Verify.** `gh secret list -R jstinhw/yongkang` lists all seven: `APPLE_TEAM_ID`,
   `DEVELOPER_ID_P12`, `DEVELOPER_ID_P12_PASSWORD`, `NOTARY_ISSUER_ID`, `NOTARY_KEY_ID`,
   `NOTARY_KEY_P8`, `SPARKLE_PRIVATE_KEY`. Remind the user to keep the .p12 and .p8 somewhere
   safe outside the repo (or delete them: the certificate stays in the keychain and a new key
   can be made), and to keep the keychain's Sparkle key backed up.

Then set this block `status: done` with a one-line `resolution` naming the seven secrets and
whether the Sparkle key was confirmed or set again.
