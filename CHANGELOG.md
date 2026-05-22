# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added

- `textmetrics/readability.smog_g` — extrapolated SMOG for texts shorter than 30 sentences. Reuses the same `30 / sentences` scaling SMOG already uses internally, but drops the 30-sentence gate so a typical Wikipedia paragraph, press release, tweet, or email can now be scored. The strict `smog` is unchanged and still returns `Error(TooFewSentences)` below 30 sentences. The two agree to within ~1 grade for 30+ sentences. (#23)

### Fixed

- `textmetrics/count.sentences` no longer counts the period after common English abbreviations (`Mr.`, `Mrs.`, `Ms.`, `Dr.`, `Prof.`, `Jr.`, `Sr.`, `St.`, `vs.`, `etc.`, `Jan.` … `Dec.`, `Mon.` … `Sun.`, and a small set of business/measurement abbreviations) as a sentence terminator. The check is case-insensitive and examines the last non-whitespace token before the period; `!` and `?` always terminate. `"Mr. Smith left."` now reports 1 sentence (was 2). Multi-period abbreviations like `e.g.` / `i.e.` / `U.S.` are not yet handled and still over-segment — handling them needs lookahead and is left for a follow-up. Downstream readability scores no longer skew "shorter sentences = easier" on text dense in single-period abbreviations. (#19)
- `textmetrics/count.syllables` / `syllables_in_word` now treat Latin-extended accented vowels (`á à â ã ä å ā ă ą`, `é è ê ë ē ĕ ė ę ě`, `í ì î ï ĩ ī ĭ į`, `ó ò ô õ ö ø ō ŏ ő`, `ú ù û ü ũ ū ŭ ů ű ų`, `ý ÿ`, and their upper-case forms) as syllable nuclei. `syllables_in_word("café")` now returns `2` (was `1`), `"résumé"` returns `3`, `"Zürich"` returns `2`. Downstream readability scores (Flesch RE, FKG, Gunning Fog, SMOG, ARI) no longer skew "easier" on text with accented words. ASCII-only words are unaffected. (#20)

### Changed

- `textmetrics/readability` grade-level scores — `flesch_kincaid_grade`, `gunning_fog`, `automated_readability_index`, and `coleman_liau_index` — now clamp their result to `[0.0, 18.0]` (US K–12 + graduate range). Synthetic inputs previously produced negative values (e.g. `-8.33`) or absurd 40+ scores. Each function has a matching `_unbounded` variant that returns the raw formula output for callers who need it. (#22)
- `textmetrics/readability.flesch_reading_ease` now clamps its result to `[0.0, 100.0]` to match the standard reporting convention used by Wikipedia, Microsoft Word, Python `textstat`'s default, and most readability UIs. Synthetic inputs that previously produced `119+` or `-245` values now report `100.0` / `0.0`. Callers who need the raw 206.835 − 1.015 × (words/sentences) − 84.6 × (syllables/words) value can switch to the new `flesch_reading_ease_unbounded`. (#21)

## [0.6.0] - 2026-05-21

### Fixed

- `textmetrics/distance.levenshtein`, `distance.normalized_levenshtein`, `distance.damerau_levenshtein`, `distance.osa`, and `distance.hamming` now pre-normalise both inputs to Unicode Normalization Form C (NFC) before comparing. Canonically-equivalent strings such as `"\u{00C1}"` (precomposed, `U+00C1`) and `"A\u{0301}"` (decomposed, `U+0041 U+0301`) previously reported a non-zero distance even though they render identically as `Á`; they now compare as equal, which matches the README's "operates on Unicode grapheme clusters (UAX #29)" contract. NFC is delegated to the platform's built-in normaliser (`unicode:characters_to_nfc_binary/1` on Erlang, `String.prototype.normalize("NFC")` on JavaScript), so no new dependency is added. `levenshtein_list/2` is unchanged — the generic list variant defines equality through the element type's own `==`. (#18)

### Documentation

- README: the "Diff: unified output" subsection now spells out that `diff.unified_options` silently strips CR / LF / NUL / TAB bytes from `old_name` / `new_name` (so they cannot corrupt the unified-diff header) and points callers at `diff.unified_options_checked` when the bad bytes should surface as a typed `Result` instead. The function-level docstring already had this distinction since #3; the README addition closes the discoverability gap for callers who only skim the top-level usage examples. (#17)

## [0.5.0] - 2026-05-16

### Documentation

- `textmetrics/search.did_you_mean` and `search.closest`: doc-comments now state explicitly that `max_distance` is measured against the whole candidate string. For prose-style candidates (multi-word titles, sentences), the length difference between a short query and a long candidate dominates the Levenshtein distance — a 4-budget call on `["Volcano in Iceland"]` looking for `"vulcano"` returns nothing because the distance is ~12. The doc-comment includes a one-line tokenise-first recipe (`list.flat_map(candidates, string.split(_, on: " "))`) for callers building "did you mean" UI over real titles. (#13)

### Changed

- **BREAKING**: `textmetrics/search.closest/3` now returns `Option(String)` instead of `Result(String, Nil)`. "No candidate within `max_distance`" is an expected, semantically empty result rather than a failure — `Option` is the idiomatic Gleam shape for that and lines up with `search.did_you_mean` (which already returns a possibly-empty `List(String)`). Callers update `Ok(name)` → `Some(name)` and `Error(Nil)` → `None`; no behaviour change beyond the constructor names. The README, all tests, and the property / metamorphic suites are migrated. (#12)

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
