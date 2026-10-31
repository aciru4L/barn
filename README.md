# Barn

A package manager for [Goose](https://github.com/aardappel/goose). Packages are
**eggs**, named `owner/name` and released at semantic versions.

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
| ✅ | `barn.lock` with a SHA-256 fingerprint for each egg |
| ✅ | `barn verify` checks `.barn/` against the lock and catches edited eggs |
| ✅ | `barn build`, `barn run` and `barn test` refuse a stale lock or edited eggs before handing off to Goose |
| ✅ | Overrides: pin an egg's version, or point it at a local folder |
| ✅ | Local eggs folder with immutable releases and timestamped snapshots |
| ✅ | Dependency tree and flat listing with `barn inspect` and `barn resolve` |
| ✅ | Prebuilt executables for Linux, macOS and Windows |
| ❌ | Remote / hosted registry |
| ❌ | Publishing and sharing eggs with others |
| ❌ | Dependencies fetched straight from Git or a URL |
| ❌ | Searching and browsing available eggs |
| ❌ | Signed releases and yanking bad versions |
| ❌ | A stable `barn.pkg` format |

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
barn lay --release               # put numbers 0.1.0 into ~/.barn/eggs
cd ..

barn hatch app                   # a project that uses it
cd app
barn add acme/numbers            # depend on the newest release, and install it
barn inspect
barn run
```

A project describes itself and its dependencies in `barn.pkg`:

```goose
owner = "acme";
name = "app";
version = "0.1.0";

dependencies = [
    "acme/numbers:0.1.0",
];
```

## Commands

| Command | Does |
|---|---|
| `barn hatch <name>` | create a project |
| `barn install` | install the project's eggs into `.barn/` |
| `barn add <egg>...` | add dependencies |
| `barn remove <egg>...` | remove dependencies |
| `barn upgrade [egg]...` | upgrade dependencies to their newest compatible releases |
| `barn verify` | check `.barn/` against `barn.lock` |
| `barn build [-- options...]` | check the eggs, then `goose build` the project |
| `barn run [-- arguments...]` | check the eggs, then `goose run` the project |
| `barn test [-- arguments...]` | check the eggs, then `goose run` the project's tests |
| `barn lay` | put the egg into `~/.barn/eggs` |
| `barn inspect` | show the dependency tree |
| `barn resolve` | list the eggs the project uses |

`barn build` and `barn run` first check that `barn.lock` matches `barn.pkg` and that
`.barn/` matches `barn.lock`, then hand the project's main file to `goose` on `PATH`.
After `--`, `build` passes options to `goose build` and `run` passes arguments to the
program. Running `goose` directly skips these checks.

`barn test` does the same checks, then runs `test/main_test.goose`, which `barn hatch`
writes next to `main.goose`. It imports the egg from `../src`, and a test fails by exiting
with a status other than 0. `test = "path.goose";` in `barn.pkg` runs another file, as
`main = "path.goose";` does for `barn run`. The tests stay out of the egg, since `barn lay`
only puts `src/` into `~/.barn/eggs`.

Barn keeps its eggs in `~/.barn/eggs`, or in `eggs/` under `BARN_HOME` when that is set.
`install`, `add`, `remove`, `upgrade` and `lay` create the folder when it is missing; the
other commands only read it.

`barn help <command>` shows a command's options.

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
