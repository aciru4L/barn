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
