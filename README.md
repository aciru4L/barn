# Barn

A package manager for [Goose](https://github.com/aardappel/goose). Packages are
**eggs**, named by the repository they live in and released at semantic versions.

> [!WARNING]
> **Work in progress.**

## Features

| | Feature |
|:-:|---|
| ✅ | Create projects with `barn hatch` |
| ✅ | Add, remove and upgrade dependencies |
| ✅ | Install eggs into `.barn/` and update the imports in `main.goose` and `test/main_test.goose` automatically |
| ✅ | Minimal version selection |
| ✅ | Errors on incompatible versions, so there are no silent conflicts |
| ✅ | SHA-256 sums of every egg, kept in `~/.barn/eggs` |
| ✅ | `barn verify` checks `.barn/` against `barn.json` and the eggs folder, and catches edited eggs |
| ✅ | `barn build`, `barn run` and `barn test` refuse out-of-date or edited eggs before handing off to Goose |
| ✅ | Overrides: pin an egg's version, or point it at a local folder |
| ✅ | Local eggs folder with immutable releases and snapshots named by time and content |
| ✅ | Dependency tree and flat listing with `barn inspect` and `barn inspect --flat` |
| ✅ | Prebuilt executables for Linux, macOS and Windows |
| ✅ | Publishing eggs as git tags, and fetching releases from their git repository |
| ❌ | Fetching snapshots straight from commits |
| ❌ | Searching and browsing available eggs |
| ❌ | Signed releases and yanking bad versions |
| ❌ | A stable `barn.json` format |

## Build

Each [release](https://github.com/aciru4L/barn/releases) has prebuilt executables for
Linux, macOS and Windows. To build barn yourself, put Goose 2026.3 or later on `PATH`:

```sh
goose build barn.goose -o bin/barn
```

## Quick start

```sh
export BARN_OWNER=acme

barn hatch numbers               # a new egg in ./numbers
cd numbers
git init && git add -A && git commit -m "numbers 0.1.0"
barn lay --release               # tag v0.1.0 and put numbers 0.1.0 into ~/.barn/eggs
cd ..

barn hatch app --app             # a program that uses it
cd app
barn add acme/numbers            # depend on the newest release, and install it
barn inspect
barn run
```

A project describes itself and its dependencies in `barn.json`:

```json
{
  "owner": "acme",
  "name": "app",
  "version": "0.1.0",
  "dependencies": {
    "acme/numbers": "0.1.0"
  }
}
```

`barn.json` is strict JSON, with no comments or trailing commas. Besides `owner`, `name`,
`version` and `dependencies`, it may set `main` and `test`, `local_priority`, and `overrides`, which maps an
egg to the version to use instead, or to a local folder starting with `./` or `../`.
`add`, `remove` and `upgrade` rewrite the file in this layout.

An egg is named by its repository: `acme/numbers` on GitHub, or `gitlab.com/acme/tools`
on another host, and `github.com/acme/numbers` is the same as `acme/numbers`. It is
imported under the `name` its own `barn.json` declares, so the repository
`acme/goose-geometry` can hold the egg `geometry`, imported as `geometry`; its `barn.json`
says `"repo": "acme/goose-geometry"`, which defaults to `<owner>/<name>`. Two dependencies
imported under the same name are an error.

## Commands

| Command | Does |
|---|---|
| `barn hatch <name> [--app]` | create an egg, or with `--app` a program |
| `barn install` | install the project's eggs into `.barn/` |
| `barn add <egg>...` | add dependencies |
| `barn remove <egg>...` | remove dependencies |
| `barn upgrade [egg]...` | upgrade dependencies to their newest compatible releases |
| `barn verify` | check `.barn/` against `barn.json` and `~/.barn/eggs` |
| `barn build [-- options...]` | check the eggs, then `goose build` the project |
| `barn run [-- arguments...]` | check the eggs, then `goose run` the project |
| `barn test [-- arguments...]` | check the eggs, then `goose run` the project's tests |
| `barn lay` | put the egg into `~/.barn/eggs` |
| `barn lay --check` | check the egg and list the files it would hold |
| `barn inspect [--flat]` | show the dependency tree, or list the eggs the project uses |

`barn build` and `barn run` first check that each egg in `.barn/` is the version `barn.json`
asks for and matches its sums in `~/.barn/eggs`, then hand the project's main file to `goose`
on `PATH`. Each copy records the version it was installed from in `barn.egg`; for
`0.1.0_snapshot`, any snapshot of 0.1.0 passes, and `barn install` looks for a newer one.
After `--`, `build` passes options to `goose build` and `run` passes arguments to the
program. Running `goose` directly skips these checks.

`barn test` does the same checks, then runs `test/main_test.goose`, which `barn hatch`
writes. It imports the egg from `..`, and a test fails by exiting with a status other than
0. `"test": "path.goose"` in `barn.json` runs another file, as `"main": "path.goose"` does
for `barn run`.

`barn help <command>` shows a command's options.

## What an egg holds

`barn hatch numbers` makes an egg: `barn.json`, `numbers.goose`, which declares
`namespace numbers;`, `test/main_test.goose` and `.gitignore`. `barn hatch app --app` also
writes `main.goose`, for `barn run`.

`barn lay` puts into the egg every file under `source`, which is the project folder unless
`barn.json` says `"source": "lib"` or another folder inside it. `<source>/<name>.goose` must
exist and declare `namespace <name>;`. These stay out:

- dot-files and dot-folders, such as `.git` and `.barn`
- in a git repository, the files git ignores, so the egg holds what the next commit could
- built files ending in `.exe`, `.pdb`, `.ilk` or `.obj`
- `barn.json`, which Barn writes into the egg itself
- the `main` and `test` files
- `test/`, `tests/`, `examples/`, `bench/` and `docs/`
- whatever `"exclude": ["notes", "tools/gen.goose"]` lists

`LICENSE*` and `README*` at the top of the project always ship.

Eggs import their dependencies by name only, as in `import numbers;`: versions belong in
`barn.json`. `barn lay` warns about a line such as `import numbers from "acme/numbers@v1"` in
a file it ships, since Goose would refuse it next to the import line Barn writes.
`barn lay --check` runs every check and lists the files the egg would hold, without laying
it.

A release is a git tag. `barn lay --release` needs a git repository with nothing left to
commit and no tag `v<version>` yet, locally or on `origin`. It tags the commit, stores the
release in `~/.barn/eggs` with a `barn.origin` file naming the repository, tag and commit,
and then asks before running `git push origin v<version>`; `-y` answers yes. Answering no,
or having no `origin`, keeps the release on this machine, and pushing the tag later
publishes the same files. A plain `barn lay` needs no git and no commit.

## Fetching

`install`, `add`, `remove` and `upgrade` fetch a release that is not in `~/.barn/eggs` from
its git repository: `git ls-remote --tags` finds the tag `v<version>`, and a shallow clone
of it is checked as `barn lay --check` would check it, then stored with a `barn.origin`
file naming the repository, tag and commit. `verify`, `build`, `run`, `test` and `inspect`
never use the network. Barn runs `git`, so private repositories work with whatever access
`git` already has.

`add` without a version and `upgrade` look at the tags on the repository as well as the
releases in `~/.barn/eggs`. A repository that cannot be reached is a warning, and the
releases already here are used. Releases never change: when a tag Barn has fetched now
points at another commit than the one in `barn.origin`, Barn refuses it.

A release already in `~/.barn/eggs` is used without asking the repository. With
`"local_priority": false` in `barn.json`, or `--set local_priority=false` for one command,
Barn asks the repository first and refuses the release if its tag has moved. `--offline`
uses `~/.barn/eggs` only.

A repository is fetched from `https://<host>/<owner>/<repo>`. `~/.barn/config.json` can
point a host elsewhere, such as a mirror:

```json
{
  "hosts": {
    "github.com": { "url": "https://mirror.example.org/github" }
  }
}
```

## The eggs folder

Barn keeps its eggs in `~/.barn/eggs`, or in `eggs/` under `BARN_HOME` when that is set.
`install`, `add`, `remove`, `upgrade` and `lay` create the folder when it is missing; the
other commands only read it. A release lives in `github.com/acme/numbers/0.1.0/`, host
first, and each snapshot beside it in `0.1.0_snapshot_<stamp>_<hash>/`: the UTC time it was
laid and the first 12 hex digits of its content hash. Laying unchanged content again reports the
snapshot it already is.

In `barn.json`, `0.1.0` means that release and nothing else, `0.1.0_snapshot` the newest
snapshot of it, and `0.1.0_snapshot_<stamp>_<hash>` that one snapshot. `barn add` without a
version picks the newest release.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). `test/run.sh` runs the test suite.

## Credits

- [Goose](https://github.com/aardappel/goose), by Wouter van Oortmerssen, is the
  language Barn is written in and the language it manages packages for. Goose is
  licensed under the Apache License 2.0.
- Version selection follows Go's
  [minimal version selection](https://research.swtch.com/vgo-mvs), and version
  compatibility follows Cargo's rules for `0.x` versions.
- Snapshot timestamps use Howard Hinnant's public-domain
  [`civil_from_days`](https://howardhinnant.github.io/date_algorithms.html) algorithm.

Barn is an independent project, not affiliated with or endorsed by the Goose project.

## License

Barn is licensed under the [Apache License 2.0](LICENSE).

An executable built from Barn includes the Goose runtime and standard library, which
are licensed under the Apache License 2.0. Distributing such an executable requires
including Goose's license with it.

## Disclaimer

Barn is a hobby project and almost entirely developed with AI.
