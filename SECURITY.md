# Security

## Reporting a vulnerability

Report it privately through GitHub's private vulnerability reporting: the repo's
[**Security** tab → **Report a vulnerability**](https://github.com/jstinhw/yongkang/security/advisories/new).
Please don't open a public issue or pull request for it. Say what you found, the app version
(**Yongkang → About Yongkang**) and how to reproduce it. You'll hear back there.

## Supported versions

Only the latest release gets fixes. A fix ships as a new release, and installed copies take it
through **Yongkang → Restart to Update**.

## What the app sends online

Yongkang runs agent CLIs on your Mac and keeps its state in the project's `.notebook/` folder.
Apart from those CLIs, which talk to their own services, the app sends only the update check,
the optional sign-in, Claude plan limits, and usage analytics that **Share Usage Analytics**
turns off — and never a path, a name, a prompt or a file's contents.
[`docs/release.md`, What goes online](docs/release.md#what-goes-online) lists each one, where
it goes and exactly what it sends.
