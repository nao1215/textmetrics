# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `textmetrics/edit`: `Edit` and `Run` ADTs, plus `recover_old`,
  `recover_new`, `cost`, and `runs` helpers.
- `textmetrics/distance`: `levenshtein`, `damerau_levenshtein`, `osa`,
  `hamming`, and a generic `levenshtein_list/2`.
- `textmetrics/similarity`: `jaro`, `jaro_winkler`,
  `jaro_winkler_with`, validated `JaroWinklerConfig`, and
  `sorensen_dice` over grapheme n-grams.
- `textmetrics/lcs`: `length` and `sequence` helpers for longest common
  subsequence.
- `textmetrics/diff`: Myers (1986) and patience diff plus POSIX
  unified-diff rendering with a validated `UnifiedOptions` bag.
- `textmetrics/search`: `did_you_mean` and `rank_jaro_winkler`.
- Spec §12 reference values, §13 axiom-style property tests, and
  Unicode reference suite all passing on Erlang and JavaScript.

## [0.1.0] - 2026-05-10

### Added

- Initial Gleam project scaffold
- GitHub Actions for CI and release automation
- `mise` and `just` based local development workflow
- Contributor and security policy documents
