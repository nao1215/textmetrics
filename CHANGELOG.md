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
- `textmetrics/search`: `did_you_mean`, `rank_jaro_winkler`, and
  `closest` (single best match for "Did you mean ...?" CLI prompts).
- `textmetrics/distance`: `normalized_levenshtein` — Levenshtein-based
  similarity score in `[0.0, 1.0]` for ranking by edit distance
  without rolling the formula by hand.
- `textmetrics/diff`: `with_old_name` and `with_new_name` setters on
  `UnifiedOptions`, mirroring `with_context_lines` for symmetric
  builder-style overrides.
- Spec §12 reference values, §13 axiom-style property tests, and
  Unicode reference suite all passing on Erlang and JavaScript.

### Changed

- `textmetrics/search.rank_jaro_winkler` now returns `List(Ranked)`,
  where `Ranked` is a labelled record (`label: String`, `score:
  Float`). Callers can read `r.label` / `r.score` directly instead of
  destructuring a tuple. The previous `List(#(String, Float))` shape
  is gone — callsites need a small update. (Pre-release breaking
  change; the package has not been published to Hex.)
- `textmetrics/lcs.length` now documents that it shadows
  `gleam/list.length` when both are imported unqualified, and
  recommends the qualified call form.

## [0.1.0] - 2026-05-10

### Added

- Initial Gleam project scaffold
- GitHub Actions for CI and release automation
- `mise` and `just` based local development workflow
- Contributor and security policy documents
