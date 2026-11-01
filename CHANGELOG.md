# Changelog

All notable changes to Barn are recorded here. The format follows
[Keep a Changelog](https://keepachangelog.com), and Barn uses
[Semantic Versioning](https://semver.org).

## [Unreleased]

### Added

- `barn hatch`, `install`, `add`, `remove`, `upgrade`, `verify`, `lay` and `inspect`, whose
  `--flat` lists the eggs a project uses.
- `barn.json`, strict JSON, with dependencies and overrides, which `add`, `remove` and
  `upgrade` rewrite. There is no lock file: the versions follow from `barn.json`, and the
  SHA-256 sums of each egg live in `~/.barn/eggs`.
- Minimal version selection: each egg gets the newest version asked for, and incompatible
  versions are an error.
- A local eggs folder with immutable releases and snapshots: `~/.barn/eggs`, or `eggs/`
  under `BARN_HOME`. The commands that install or lay eggs create it when it is missing.
  Snapshots sit beside their release as `0.1.0_snapshot_<stamp>_<hash>`, named by the time
  they were laid and their content.
- `0.1.0` asks for that release only, never a snapshot of it; `0.1.0_snapshot` asks for the
  newest snapshot.
- Prebuilt executables for Linux, macOS and Windows on each GitHub release.
- `barn build` and `barn run`, which stop when a copy in `.barn/` is not the version
  `barn.json` asks for or differs from its sums in `~/.barn/eggs`, and otherwise hand the project to `goose build` or
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
- `barn lay --release` tags the commit `v<version>` in a git repository with nothing left to
  commit, stores the release with a `barn.origin` file and asks before pushing the tag to
  `origin`. Without `origin`, or when the answer is no, the release stays on this machine.
- `install`, `add`, `remove` and `upgrade` fetch missing releases from their git repository,
  and `~/.barn/config.json` can point a host at a mirror.
- `add` and `upgrade` find releases on the repository too, and refuse a tag that has moved
  since it was fetched.
- `"local_priority": false`, `--set local_priority=...` for one command, and `--offline`.
- Plain Goose libraries without `barn.json` install as eggs with no dependencies, named
  after the one `<name>.goose` at their top that declares `namespace <name>;`.
- Eggs named by their repository, `acme/numbers` or `gitlab.com/acme/tools`, and imported
  under the `name` in their `barn.json`; `"repo"` says where a project lives when that
  differs from `<owner>/<name>`. The eggs folder keeps them under their host.
- `barn lay --check`, which checks the egg and lists its files without laying it, and a
  warning when a file in the egg names where a dependency comes from.

### Fixed

- `--owner` and `BARN_OWNER` are lowercased, with a warning, instead of being rejected.
- Owners with uppercase letters, in `barn.json` or given to `add`, `remove` and `upgrade`, are
  resolved as lowercase, with a warning. Egg names stay lowercase only, since they are folder
  and import names; an uppercase one is an error that suggests the lowercase spelling.
