# Contributing

Thanks for helping. Bugs and ideas go in an
[issue](https://github.com/jstinhw/yongkang/issues/new/choose); a vulnerability goes through
[SECURITY.md](SECURITY.md) instead, never a public issue.

## The rules

[`AGENTS.md`](AGENTS.md) holds the rules everyone working in this repo follows, an agent or a
person: the layout, the commands, the definition of done, and what never changes without care
(the `.notebook/` format, what goes online). `CLAUDE.md` is a link to it. Read it first.

## Build and test

You need macOS 14+ and the Swift toolchain; building the app itself needs Xcode 16 or later
(see the [README](README.md#build-from-source)).

```sh
git config core.hooksPath .githooks   # once per clone: make check runs before every push
make check                            # format lint, build and tests: the definition of done
make format                           # fix what the lint step complains about
make run                              # build the app with Xcode and open it
```

For a change to the UI, render the screens before and after it with `make shots DIR=<dir>` and
compare them. [`docs/development.md`](docs/development.md) has the manual smoke script and the
rest of the details.

## Branches and pull requests

1. Branch off `main`, one change to a branch.
2. Keep `make check` passing. A move is a `git mv` in a commit of its own, apart from any edits.
3. A change someone using the app would notice goes under `## [Unreleased]` in
   [`CHANGELOG.md`](CHANGELOG.md): the release notes are written from it.
4. Open a pull request against `main` and fill in its template. CI runs `make check` on it,
   and `main` takes changes only through pull requests that pass.

Be kind and assume good faith; that is the whole code of conduct for now.

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
