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
- A local repository with immutable releases and timestamped snapshots.
- Prebuilt executables for Linux, macOS and Windows on each GitHub release.

### Fixed

- `--owner` and `BARN_OWNER` are lowercased, with a warning, instead of being rejected.
- Egg names with uppercase letters, in `barn.pkg` or given to `add`, `remove` and `upgrade`, are
  resolved as lowercase, with a warning.
