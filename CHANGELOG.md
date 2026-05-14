# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

## [0.4.0] - 2026-05-14

### Added

- New `textmetrics/readability` module implementing the six canonical
  English-language readability scores: `flesch_reading_ease`,
  `flesch_kincaid_grade`, `gunning_fog`, `smog`,
  `automated_readability_index`, `coleman_liau_index`. All return
  `Result(Float, ReadabilityError)` so that empty inputs and the
  SMOG 30-sentence statistical-validity floor surface as a typed
  `TooFewWords` / `TooFewSentences` error instead of `NaN` /
  infinity. Scores match Python `textstat` to within roughly ±2 on
  the Reading Ease 0–100 scale and ±1 on grade-level scales. (#7)
- New `textmetrics/count` module exposing the primitives consumed by
  the readability scores: `words`, `sentences`, `syllables_in_word`,
  `syllables`, `characters`, `paragraphs`, `polysyllables`. All
  functions are pure, deterministic, `O(n)` in input length, and
  iterate over Unicode grapheme clusters. `syllables_in_word`
  implements the English silent-`e` heuristic with the consonant-`le`
  exception (e.g. "syllable" → 3, "table" → 2) and falls back to
  `1` for words with no ASCII letters so non-English tokens don't
  poison the surrounding score. (#7)

## [0.3.0] - 2026-05-12

### Added

- `similarity.sorensen_dice_bigrams(a, b)` and
  `similarity.sorensen_dice_trigrams(a, b)`: pipe-friendly lenient
  aliases of `similarity.sorensen_dice` that return a plain `Float`
  in `[0.0, 1.0]` instead of `Result(Float, SorensenDiceError)`.
  The strict variant stays available for callers that take `n` from
  user input; the new aliases close the awkward asymmetry with
  `jaro` and `jaro_winkler` (which already return plain `Float`) and
  remove the `case … { Ok(s) -> s; Error(_) -> 0.0 }` boilerplate
  at the dominant call shape — "give me a similarity score between
  two strings". (#6)

## [0.2.0] - 2026-05-11

### Fixed

- **`textmetrics/diff`**: `unified_options`, `with_old_name`, and
  `with_new_name` now silently strip bytes that would corrupt the
  unified-diff header (`\n`, `\r`, `\u{0000}`, `\t`), keeping
  `to_unified` output parseable by `patch(1)` / `git apply` regardless
  of caller-supplied filename labels. The previous version wrote the
  bytes verbatim and produced output that *looked* like a unified
  diff but split the header across multiple lines or truncated under
  POSIX C string consumers. (#3)

### Added

- **`textmetrics/diff`**: `unified_options_checked`,
  `with_old_name_checked`, and `with_new_name_checked` are the
  typed-error counterparts of the existing builders. They return
  `Error(NameContainsForbiddenBytes(field, value))` instead of
  silently stripping, so callers passing user-supplied paths can
  surface the bad input at the call site. New `NameField` ADT
  (`OldName` / `NewName`) identifies which field rejected the input,
  and the new `NameContainsForbiddenBytes` variant joins the existing
  `ContextLinesNegative` under `UnifiedOptionsError`.

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
