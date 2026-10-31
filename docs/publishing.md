# Publishing an egg

> [!NOTE]
> This describes the planned design in [architecture.md](architecture.md).

An egg is published by tagging a release in its git repository. Anyone can then depend on
it as `owner/repo`, or `host/owner/repo` outside GitHub.

## The rules

Barn refuses to install an egg that breaks these rules, and checks them before it lays one:

- `name` in `barn.json` is the import name: a lowercase letter, then lowercase letters,
  digits and `_`. `goose-linalg` is not a name, and Goose could not import it either;
  `linalg` is.
- `<source>/<name>.goose` exists, `source` being `.` unless `barn.json` says otherwise.
- That file declares `namespace <name>;`.
- `version` in `barn.json` is `x.y.z`, and the tag is `v` followed by it: `v0.3.3` for
  `0.3.3`.
- The egg's files import dependencies by name only, as in `import fft;`. Their versions
  belong in `barn.json`, never in an import line.

The repository may be named differently from the egg. `example/goose-linalg` can hold
the egg `linalg`, which users then import as `linalg`.

## Publishing with Barn

```sh
barn lay --release
```

Barn checks the rules, requires a working tree with no uncommitted or untracked files, and
refuses a tag that already exists. It then creates the tag `v<version>`, keeps the release
in `~/.barn/eggs`, and asks before pushing the tag to `origin`.

Answering no, or having no `origin`, leaves a release on your machine only. It is pinned to
the tagged commit, so pushing the tag later with `git push origin v<version>` publishes
exactly the same files.

## Publishing by hand or from CI

Tagging by hand skips the checks. Run them first:

```sh
barn lay --check
git tag v0.3.3
git push origin v0.3.3
```

Or let a workflow check every release tag. For GitHub Actions:

```yaml
name: Egg

on:
  push:
    tags: ["v[0-9]+.[0-9]+.[0-9]+"]

jobs:
  check:
    runs-on: ubuntu-latest
    env:
      BARN_VERSION: "x.y.z" # a Barn release that has barn lay --check
    steps:
      - uses: actions/checkout@v4

      - name: Install Barn
        run: |
          name="barn-v$BARN_VERSION-linux-x64"
          curl -fsSL "https://github.com/aciru4L/barn/releases/download/v$BARN_VERSION/$name.tar.gz" |
            tar xz -C "$RUNNER_TEMP"
          echo "$RUNNER_TEMP/$name" >> "$GITHUB_PATH"

      - name: Check the egg
        run: barn lay --check
```

The workflow cannot take a bad tag back, but it tells you at once that the release is
broken.

## Releases are permanent

A released version never changes. Barn records the commit each tag pointed at when it was
fetched, and refuses the tag if it later sees it pointing elsewhere. To fix a broken
release, publish the next version: `0.3.4` after a broken `0.3.3`. Moving or deleting a
tag breaks every project that already uses it.

A tag ruleset in the repository's settings that blocks updating and deleting `v*` tags
keeps them from being moved by accident.

## Snapshots

Every commit is also a snapshot, named `<version>_snapshot_<stamp>_<hash>` from its commit
time and hash. A project that asks for `0.4.0_snapshot` gets the newest commit on the
default branch whose `barn.json` says `0.4.0`, so work in progress can be tried before it
is released. Projects that need it fixed write the exact snapshot,
`0.4.0_snapshot_<stamp>_<hash>`, as `barn inspect` shows it.

`barn lay` without `--release` makes a snapshot on your own machine only, in the same
shape: stamped when laid, with a hash of the egg's content. It needs no commit, and in a
git repository it leaves out the files git ignores, so it holds what your next commit
could.

## Libraries without barn.json

A plain Goose library can be installed without a `barn.json`. Barn takes the `<x>.goose`
at the root that declares `namespace <x>;` as its entry file, takes the version from the
tag, and assumes it has no dependencies. Adding a `barn.json` makes the name explicit and lets the library declare
dependencies.
