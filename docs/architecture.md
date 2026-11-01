# Barn architecture

> [!NOTE]
> This is Barn's design, and Barn implements it except for what [Not built yet](#not-built-yet)
> lists. [README.md](../README.md) describes the commands as they work today.

## Barn and Goose

Goose compiles programs and finds packages from import lines. Barn decides which version
of each package a project uses, stores the packages, checks that nobody changed them, and
writes the import lines Goose reads.

| | Goose | Barn |
|---|---|---|
| Compiles | yes | hands the project to `goose` |
| Finds a package from an import line | paths and git | writes local-path import lines |
| Chooses versions | exact refs, by hand | semantic versions, minimal version selection |
| Stores packages | its own git cache | `~/.barn/eggs` |
| Integrity | the ref in the import line | SHA-256 sums of every egg, checked before each build |

Goose only ever sees ordinary path imports, such as `import geometry from "./.barn/geometry";`
in `main.goose`.

## Eggs

An egg is a Goose package with a `barn.json`. It is identified by the repository it lives
in, `owner/repo` on GitHub or `host/owner/repo` elsewhere, and imported under the `name` its
own `barn.json` declares:

| Written in a dependency | Lives in | Imported as |
|---|---|---|
| `acme/numbers` | `github.com/acme/numbers` | `numbers` |
| `acme/goose-geometry` | `github.com/acme/goose-geometry` | `geometry` |
| `gitlab.com/acme/stats` | `gitlab.com/acme/stats` | the `name` in its `barn.json` |

The repository is the identity, so two different repositories can never be mistaken for
one egg. A repository path may contain `-` and `.`, which a `name` may not. Two
dependencies that declare the same `name` are an error, since Goose could not import both.

## Files and folders

```
~/.barn/                                 BARN_HOME, if set
  config.json                            settings for this user
  eggs/<host>/<owner>/<repo>/
    0.1.0/                               a release
    0.1.0_snapshot_<stamp>_<hash>/       a snapshot, laid here or fetched from a commit

project/
  barn.json                              the project and its dependencies
  <name>.goose                           the egg's entry file, under source
  main.goose                             barn run, for apps
  test/main_test.goose                   barn test
  .barn/<name>/                          copies of the eggs, for Goose
```

- `BARN_HOME` replaces `~/.barn`. Nothing else moves Barn's folders.
- `~/.barn/eggs` is where every egg a project uses comes from. Eggs laid on this machine
  and eggs fetched from repositories live there side by side, and each records its origin.
- Every egg in `~/.barn/eggs` is immutable. Barn never replaces one.
- `install`, `add`, `remove`, `upgrade` and `lay` create `~/.barn/eggs` when it is missing.
  The other commands only read it.
- `.barn/` exists so that the import lines are the same on every machine. It is not in git.
  Each copy records the exact version it was copied from.

## barn.json

```json
{
  "owner": "acme",
  "name": "stats",
  "version": "0.2.0",
  "repo": "acme/goose-stats",
  "source": ".",
  "exclude": ["notes"],
  "main": "main.goose",
  "test": "test/main_test.goose",
  "local_priority": true,
  "dependencies": {
    "acme/numbers": "0.2.0",
    "acme/goose-geometry": "1.2.0"
  },
  "overrides": {
    "acme/numbers": "../numbers"
  }
}
```

| Key | Required | Default | Meaning |
|---|---|---|---|
| `owner` | yes | | lowercase letters, digits, `-` and `_` |
| `name` | yes | | the import name: a lowercase letter, then lowercase letters, digits and `_` |
| `version` | yes | | `x.y.z` |
| `repo` | no | `<owner>/<name>` | where the egg lives, when the repository is named differently |
| `source` | no | `.` | the folder holding `<name>.goose` |
| `exclude` | no | `[]` | more files and folders to leave out of the egg |
| `main` | no | `main.goose` | the file `barn run` and `barn build` use |
| `test` | no | `test/main_test.goose` | the file `barn test` runs |
| `local_priority` | no | `true` | look in `~/.barn/eggs` before the repository |
| `dependencies` | no | `{}` | repository to version |
| `overrides` | no | `{}` | repository to a version, or to a local folder starting with `./` or `../` |

- A repository without a host, in `repo` or as a dependency, is on `github.com`.
- Only the project's own `overrides` apply. Those in its dependencies are ignored.
- Strict JSON: no comments and no trailing commas. `add`, `remove` and `upgrade` rewrite the
  file.

## What an egg holds

- `<source>/<name>.goose` must exist and declare `namespace <name>;`.
- Eggs import their dependencies by name only, as in `import numbers;`. A line such as
  `import numbers from "acme/numbers@v0.2.0"` makes Goose refuse Barn's own declaration,
  so `barn lay` warns about it: versions belong in `barn.json`.
- Everything under `source` ships, except:
  - in a git repository, files that git ignores: only what the next commit could contain
    ships, the files `git ls-files --cached --others --exclude-standard` lists. Outside git,
    nothing is left out for this reason.
  - `barn.json`, which Barn writes into the egg itself
  - dot-files and dot-folders, including `.git` and `.barn`
  - the `main` and `test` files
  - `test/`, `tests/`, `examples/`, `bench/` and `docs/`
  - whatever `exclude` lists
- `LICENSE*` and `README*` at the project root always ship.

A repository without `barn.json` is a plain Goose library. Barn installs it as an egg with
no dependencies, whose entry file is the `<x>.goose` at the root that declares
`namespace <x>;`, and writes a `barn.json` for it with that name and the tag's version.
When no file or more than one file matches, the install fails and asks for a `barn.json`.

## Versions

| Written | Means | Changes over time |
|---|---|---|
| `0.1.0` | release 0.1.0, and nothing else | no |
| `0.1.0_snapshot_<stamp>_<hash>` | that snapshot | no |
| `0.1.0_snapshot` | the newest snapshot of 0.1.0 | yes |

- A release is the git tag `v0.1.0`, and the `barn.json` at that tag says `0.1.0`.
- Every snapshot is named `<version>_snapshot_<stamp>_<hash>`, so all snapshots parse and
  sort the same way:

  | Snapshot | Stamp | Hash |
  |---|---|---|
  | laid with `barn lay` | when it was laid | the first 12 hex digits of the egg's content hash |
  | fetched from a repository | the commit time | the first 12 hex digits of the commit hash |

  Either way the hash names exactly one set of files. Laying unchanged content again
  reports the snapshot it already is.
- On a repository, `0.1.0_snapshot` is the newest commit on the default branch whose
  `barn.json` says `0.1.0`.
- `0.1.0` never falls back to a snapshot: a project gets only what it declares.
- Stamps are UTC, `YYYYMMDDTHHMMSSZ`.

## Resolution

Minimal version selection picks one version of each egg from the `barn.json` files in the
tree. The same files always give the same versions, whatever is newest on a remote, except
where a file asks for `_snapshot`, which means whatever is newest. Barn has no lock file.

### Fixed versions

Releases and exact snapshots never change. A copy that is present is checked against its
stored sums, and with `local_priority` true it is used without the network.

| `~/.barn/eggs` has | `local_priority` true | `local_priority` false |
|---|---|---|
| an unchanged copy | use it | ask the repository first, then use the copy |
| a changed copy | error | the same |
| nothing | fetch from the repository, check it, store it | the same |

With `local_priority` false, a repository that has the version must match the copy, or it
is an error. When it does not have the version, or cannot be reached, the copy is used.

A changed copy that was fetched is fetched again by `barn install --force`. A changed copy
laid on this machine has nowhere to come from: delete it and lay it again. When nothing has
the version, the install fails and says where Barn looked.

### Newest snapshot

Only `install`, `add` and `upgrade` look for the newest snapshot:

| Situation | Barn uses |
|---|---|
| snapshots of that version were laid here, and `local_priority` is true | the newest of them, without the network |
| the repository has snapshots of that version | the newest of them |
| that snapshot is already in `~/.barn/eggs` | the copy, without downloading |
| the repository has none, but some were laid here | the newest laid here |
| the repository cannot be reached | the newest copy, with a warning that it may be stale |
| nothing anywhere | an error |

Only snapshots laid on this machine take priority. A fetched snapshot is a copy, not a
source, or `0.1.0_snapshot` would keep returning the first snapshot ever fetched.

### Options

- `--offline` uses `~/.barn/eggs` only.
- `--set key=value` overrides a `barn.json` setting for one command, as in
  `barn install --set local_priority=false`.
- `--force` replaces eggs that were changed, and nothing else.

## Integrity

- `barn lay` and every fetch write `barn.sha256`, the sums of the egg's files, into the
  egg's folder in `~/.barn/eggs`.
- A fetched egg also records its origin: the repository, the tag and the commit.
- `verify`, `build`, `run` and `test` never use the network. They compare each
  `.barn/<name>` with the sums in `~/.barn/eggs` for the version it records. A copy that
  differs from its sums was edited. A copy whose version is not the one `barn.json` asks
  for is out of date, which `barn install` fixes. For `_snapshot`, any snapshot of that
  version is accepted; `barn install` looks for a newer one.
- An egg missing from `~/.barn/eggs` means `barn install`.

Remotes are trusted to be immutable. Whenever Barn lists a repository's tags, for `add`,
`upgrade` or `local_priority` false, it compares each tag it already holds with the commit
it recorded, and refuses a tag that moved. A machine that first fetches a tag after it
moved cannot tell.

## Commands

| Command | Does |
|---|---|
| `barn hatch <name>` | a library: `barn.json`, `<name>.goose`, `test/main_test.goose`, `.gitignore` |
| `barn hatch <name> --app` | the same, plus `main.goose` |
| `barn install` | resolve, fetch what is missing, copy into `.barn/`, update the imports |
| `barn add <egg>...` | add dependencies, at the newest release unless a version is given |
| `barn remove <egg>...` | remove dependencies, their copies and their import lines |
| `barn upgrade [egg]...` | move dependencies to their newest compatible releases |
| `barn verify` | check `.barn/` against `~/.barn/eggs` |
| `barn build`, `run`, `test` | verify, then hand the project to `goose` |
| `barn inspect [--flat]` | the dependency tree with exact versions, or a flat list |
| `barn lay` | a snapshot in `~/.barn/eggs`, from the folder as it is; no commit needed |
| `barn lay --release` | tag `v<version>`, store the release, then offer to push the tag |
| `barn lay --check` | every check `lay` does, and nothing else |

A release is always a git tag; pushing it is what publishes it. `barn lay --release`:

1. runs every check, and requires a git repository whose working tree has no uncommitted
   or untracked files
2. refuses when the tag `v<version>` exists, locally or on `origin`
3. runs `git tag v0.1.0`
4. stores the release in `~/.barn/eggs` from the tagged commit, recording the repository,
   the tag and the commit as a fetch would
5. when the project has an `origin`, asks `Push v0.1.0 to origin? [y/N]`, where `-y`
   answers yes, and runs `git push origin v0.1.0`

| Outcome | Result |
|---|---|
| pushed | the release is published |
| answered N, no `origin`, or the push failed | a release on this machine only, pinned to its commit |
| pushed later with `git push origin v0.1.0` | the same files go public, since the tag names the same commit |
| someone else published a different `v0.1.0` first | git refuses the push; Barn reports it when it next lists tags |

A local release and a published one can only be the same tag, so the same version never
names two different sets of files. A plain `barn lay` needs no commit: it works in any
folder, and uses git, when there is a repository, only to leave out ignored files.

[Publishing an egg](publishing.md) is the guide for egg authors.

## Fetching

Barn runs `git`, which also handles credentials for private repositories:

- `git ls-remote --tags` lists the releases and the commit each tag points at.
- A shallow clone at the tag or commit fetches the files, before Barn applies `source` and
  the exclusions.
- Every fetched egg is checked as `barn lay --check` would check it, and its `barn.json`
  version must match the tag. A broken egg fails with a message naming the egg and what is
  wrong, and its author fixes it in a new release.

## config.json

```json
{
  "hosts": {
    "github.com": { "url": "https://mirror.example.org/github" }
  }
}
```

The file is optional. `url` points a host somewhere other than `https://<host>`, such as a
mirror, and a repository is fetched from `<url>/<owner>/<repo>`. Barn runs `git`, so private
repositories work with whatever access `git` already has.

## What changed

What Barn did before this design, and what it does now:

| Before | Now |
|---|---|
| `barn.pkg` | `barn.json` |
| `barn.lock` | removed: versions come from `barn.json`, sums from `~/.barn/eggs` |
| `~/.barn/repository`, `BARN_REPO`, `--repo` | `~/.barn/eggs`, moved only by `BARN_HOME` |
| eggs named `owner/name` | dependencies named by repository, imported by `name` |
| `0.1.0/_snapshot_<stamp>/` | `0.1.0_snapshot_<stamp>_<hash>/`, beside the release |
| `0.1.0` falls back to the newest snapshot | `0.1.0` means the release only |
| entry file at `src/<name>.goose` | `<source>/<name>.goose`, `source` defaulting to `.` |
| only `src/` ships | `source` minus exclusions and git-ignored files, plus `LICENSE` and `README` |
| `hatch` writes `main.goose` | only with `--app` |
| `barn resolve` | `barn inspect --flat` |
| local repository only | eggs fetched from git repositories |
| `barn lay --release` stores the folder | it tags `v<version>`, stores the tagged commit, offers to push |

## Not built yet

- A token for a host in `config.json`. Private repositories use the credentials `git` has.

## Open details

- Whether `config.json` holds defaults such as the owner for `barn hatch`, replacing
  `BARN_OWNER`.
- How a changed release that was never pushed is restored: its tag exists, so
  `barn lay --release` refuses it, and there is no remote to fetch it from.
