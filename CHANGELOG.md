# Changelog

All notable changes to Barn are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com), and Barn uses
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

- `barn hatch`, `install`, `add`, `remove`, `upgrade`, `verify`, `lay`, `inspect` and `resolve`.
- `barn.json`, strict JSON, with dependencies and overrides, which `add`, `remove` and
  `upgrade` rewrite; `barn.lock` with a SHA-256 fingerprint of each egg.
- Minimal version selection: each egg gets the newest version asked for, and incompatible
  versions are an error.
- A local eggs folder with immutable releases and snapshots: `~/.barn/eggs`, or `eggs/`
  under `BARN_HOME`. The commands that install or lay eggs create it when it is missing.
  Snapshots sit beside their release as `0.1.0_snapshot_<stamp>_<hash>`, named by the time
  they were laid and their content.
- `0.1.0` asks for that release only, never a snapshot of it; `0.1.0_snapshot` asks for the
  newest snapshot.
- Prebuilt executables for Linux, macOS and Windows on each GitHub release.
- `barn build` and `barn run`, which stop when `barn.lock` does not match `barn.json` or
  `.barn/` does not match `barn.lock`, and otherwise hand the project to `goose build` or
  `goose run`.
- `barn test`, which does the same checks and then runs `test/main_test.goose`, or the file
  `test` names in `barn.json`. `barn hatch` writes the test file, and `barn install` updates
  its imports as it does those of `main.goose`.
- Eggs laid from the project folder, or from the folder `source` names: `<name>.goose` at
  its top, the other files under it, and `LICENSE` and `README`. Tests, examples, benches,
  docs, dot-files, the main and test files and whatever `exclude` lists stay out, and in a
  git repository so do the files git ignores.
- `barn hatch` makes an egg with `<name>.goose` at the top; `barn hatch --app` adds
  `main.goose`.
- `barn lay --check`, which checks the egg and lists its files without laying it, and a
  warning when a file in the egg names where a dependency comes from.

### Fixed

- `--owner` and `BARN_OWNER` are lowercased, with a warning, instead of being rejected.
- Owners with uppercase letters, in `barn.json` or given to `add`, `remove` and `upgrade`, are
  resolved as lowercase, with a warning. Egg names stay lowercase only, since they are folder
  and import names; an uppercase one is an error that suggests the lowercase spelling.
