# Changelog

## [Unreleased]

### Upgrade Notes

- No special notes.

### Changed Sandboxing Profiles

- No profiles changed.

## [0.2.0] - 2026-03-11

### Features

- Added a standalone `safehouse update` subcommand, including `--head` support for updating from the latest `main` build when needed.
- Added `safehouse --version` and switched standalone install and launcher docs to tagged GitHub release assets instead of `main`.

### Bug Fixes

- Hardened self-update failure handling so invalid assets are rejected safely, identical assets report as already up to date, replacement failures clean up temporary files, and `update` does not hijack wrapped commands after policy flags or `--`.
- Fixed Homebrew tap packaging for `brew install --HEAD` so it installs `dist/safehouse.sh` correctly.

### Chores

- Centralized project versioning in the repo-root `VERSION` file so release assets, docs, and generated artifacts stay aligned.
- Kept the dist-regeneration workflow from running on tag pushes, so release tags do not trigger a push-back job against the tag ref.
- Made Homebrew tap cleanup in the release flow nounset-safe under `set -u`.

## [0.1.0] - 2026-03-11

### Upgrade Notes

- First tagged release.
