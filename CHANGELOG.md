# Changelog

All notable changes to Barn are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com), and Barn uses
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

- `barn hatch`, `install`, `add`, `remove`, `upgrade`, `verify`, `lay`, `inspect` and `resolve`.
- `barn.pkg` with dependencies and overrides; `barn.lock` with a SHA-256 fingerprint of each egg.
- Minimal version selection: each egg gets the newest version asked for, and incompatible
  versions are an error.
- A local eggs folder with immutable releases and timestamped snapshots: `~/.barn/eggs`, or
  `eggs/` under `BARN_HOME`. The commands that install or lay eggs create it when it is
  missing.
- Prebuilt executables for Linux, macOS and Windows on each GitHub release.
- `barn build` and `barn run`, which stop when `barn.lock` does not match `barn.pkg` or
  `.barn/` does not match `barn.lock`, and otherwise hand the project to `goose build` or
  `goose run`.
- `barn test`, which does the same checks and then runs `test/main_test.goose`, or the file
  `test` names in `barn.pkg`. `barn hatch` writes the test file, and `barn install` updates
  its imports as it does those of `main.goose`.

### Fixed

- `--owner` and `BARN_OWNER` are lowercased, with a warning, instead of being rejected.
- Owners with uppercase letters, in `barn.pkg` or given to `add`, `remove` and `upgrade`, are
  resolved as lowercase, with a warning. Egg names stay lowercase only, since they are folder
  and import names; an uppercase one is an error that suggests the lowercase spelling.
