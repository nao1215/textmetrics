# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.1.1] - 2026-05-10

### Changed

- Tightened the package description in `gleam.toml` to match the
  GitHub repository description: "Edit distances, similarity scores,
  LCS, and diff for Gleam."
- Replaced the internal "Design Spec" link in `gleam.toml` with a
  link to the `CHANGELOG.md`. The spec is a project-internal
  document and should not be surfaced on the Hex page.

No source-code changes; the public API is identical to v0.1.0.

## [0.1.0] - 2026-05-10

First public release.

### Added — public API

- `textmetrics/edit`: `Edit` and `Run` ADTs, plus `recover_old`,
  `recover_new`, `cost`, and `runs` helpers. `EditScript(a)` is a
  type alias for `List(Edit(a))` so it interops with `gleam/list`.
- `textmetrics/distance`: `levenshtein`, `damerau_levenshtein` (true
  variant), `osa`, `hamming` (returns `Result(Int, HammingError)`),
  `levenshtein_list/2` (generic over equality-comparable lists), and
  `normalized_levenshtein` (Levenshtein-based similarity in `[0.0,
  1.0]`).
- `textmetrics/similarity`: `jaro`, `jaro_winkler`,
  `jaro_winkler_with`, validated `JaroWinklerConfig` (opaque, with
  smart constructor and accessors), and `sorensen_dice` over grapheme
  n-grams.
- `textmetrics/lcs`: `length` and `sequence` for longest common
  subsequence over generic lists.
- `textmetrics/diff`: Myers (1986) `myers`, Bram Cohen's `patience`,
  POSIX-format `to_unified`, and validated `UnifiedOptions` (opaque)
  with `with_context_lines`, `with_old_name`, `with_new_name`
  setters and `old_name` / `new_name` / `context_lines` accessors.
- `textmetrics/search`: `did_you_mean`, `closest`, and
  `rank_jaro_winkler` (returns `List(Ranked)` where
  `Ranked(label: String, score: Float)`).

### Verification

- 346 tests pass on Erlang and JavaScript.
- Reference values from spec §12 (Levenshtein / Jaro / Jaro-Winkler /
  Sørensen-Dice / Hamming / Damerau-vs-OSA / LCS / Myers /
  unified-diff format / Unicode grapheme cases) all match exactly.
- 155 metamon-driven property and metamorphic tests covering the
  axioms in spec §13 (non-negativity, identity, symmetry, triangle
  inequality, OSA bracketing, JW floor / cap, LCS bounds, Myers
  round-trip and optimality).
- Targeted boundary probes on emoji ZWJ sequences, skin-tone
  modifiers, regional indicator pairs, Hangul jamo, NFC vs NFD,
  combining marks, RTL content, and `to_unified` hunk-merge boundary
  arithmetic.

### Project infrastructure

- `mise`-pinned Gleam / Erlang toolchain.
- `just check` / `just ci` recipes.
- GitHub Actions for CI (Erlang + JavaScript) and release automation
  (Hex publish + GitHub Release on `v*` tag).
- Contributor and security policy documents.
