# Barn

A package manager for [Goose](https://github.com/aardappel/goose). Packages are
**eggs**, named `owner/name` and released at semantic versions.

> **Work in progress.** The `barn.pkg` format and the repository layout may still
> change before the first release.

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
barn lay --release               # put numbers 0.1.0 into the local repository
cd ..

barn hatch app                   # a project that uses it
cd app
barn add acme/numbers            # depend on the newest release, and install it
barn inspect
goose main.goose
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
| `barn lay` | put the egg into the repository |
| `barn inspect` | show the dependency tree |
| `barn resolve` | list the eggs the project uses |

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
