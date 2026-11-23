# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project is expected to follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Changed

- Breaking: `to_unified` returns `Error(LineContainsNewline(line))` when a script element contains a line feed. Such an element used to render as two diff lines behind one prefix, which `patch` applies to the wrong lines. Elements are still checked after the names and context count, including for unchanged scripts. Carriage returns stay part of the line.
- Jaro scores change: the transposition count is half the mismatched matched pairs rounded down, as in Winkler's strcmp95 code and in rapidfuzz, jellyfish, and textdistance. 0.11.0 kept the fraction, so an odd number of mismatches gave different scores from all of them; `jaro("bdab", "daabcbbc")` is now 0.75 instead of 0.7083. `jaro_winkler` and `rank_jaro_winkler` inherit the change.
- Word counts change: words follow the UAX #29 rules that keep the punctuation it allows between two letters, such as an apostrophe, colon, or period (`don't`, `it’s`, `U.S.A`, `example.com`), and between two digits, such as a period, comma, semicolon, or apostrophe (`3.50`, `1,000`), inside one word. Format characters such as the soft hyphen no longer split a word, and Word_Break=Numeric characters such as U+066B ARABIC DECIMAL SEPARATOR and the Arabic number signs count as digits. `count_words("don't stop")` is now 2 instead of 3. Syllable, polysyllable, and readability results change for such text; on plain English the word counts now agree with textstat. Hyphens still separate words, as UAX #29 specifies.
- Word, character, and sentence classification uses Unicode 17.0.0 instead of 15.1.0, so letters added in Unicode 16 and 17 (for example U+1C89 and CJK Extension J) count as letters. The generator now also reads the pinned `WordBreakProperty.txt` and `SentenceBreakProperty.txt`.

### Fixed

- `count_sentences` no longer counts a closing quotation mark or bracket after a terminator as the start of another sentence (UAX #29 SB9). `He said "Hi."`, `(See above.)`, and `「終わり。」` are each one sentence instead of two. A multi-period abbreviation followed by a closer and a capitalized word, as in `the U.S.A." She`, now ends its sentence. Readability scores built on sentence counts change accordingly.
- `myers` (and `patience`, which falls back to it) no longer keeps a persistent Dict for every edit step. Two unrelated 3,000-line inputs took 16 seconds on Erlang and 25 seconds on JavaScript and now take about 2 seconds on each, with memory near O(D √(n + m)) instead of O(D²). The scripts are unchanged. On Erlang, inputs longer than the 16,777,215-element tuple limit fall back to the `array` module.
- `damerau_levenshtein` no longer builds a Dict for every row, and `optimal_string_alignment` no longer allocates a Result per cell. For two 2,000-grapheme strings this halves the Damerau-Levenshtein time and makes optimal string alignment about 2.7 times faster on JavaScript. Results are unchanged.

## [0.11.0] - 2026-11-23

### Changed

- Breaking: consolidate the `count`, `distance`, `similarity`, `lcs`, `diff`, `edit`, `search`, and `readability` modules into `textmetrics`. Remove the old module paths and the `EditScript(a)` alias; use `List(Edit(a))`.
- Breaking: prefix the seven count functions with `count_`. Rename `normalized_levenshtein` to `levenshtein_similarity`, `osa` to `optimal_string_alignment`, `lcs.length` and `lcs.sequence` to `longest_common_subsequence_length` and `longest_common_subsequence`, and `edit.cost` and `edit.runs` to `edit_cost` and `edit_runs`.
- Breaking: make `jaro_winkler` take explicit `prefix_scale` and `prefix_max` arguments and return a Result. Remove `jaro_winkler_with`, `JaroWinklerConfig`, `default_jaro_winkler_config`, `jaro_winkler_config`, `prefix_scale`, and `prefix_max`. Rename `JaroWinklerConfigError` to `JaroWinklerError`. Validate both arguments before inspecting input strings.
- Breaking: make `to_unified` take explicit `old_name`, `new_name`, and `context_lines` arguments and return a Result. Remove `UnifiedOptions`, `unified_options`, `unified_options_checked`, `with_context_lines`, `with_old_name`, `with_old_name_checked`, `with_new_name`, `with_new_name_checked`, `old_name`, `new_name`, and `context_lines`. Rename `UnifiedOptionsError` to `UnifiedError`. Reject LF, CR, NUL, and tab in filenames instead of silently removing them. Validate the old name, new name, then context count, including unchanged scripts.
- Breaking: label the `sorensen_dice` size argument `ngram_size` and return `Error(Nil)` for an invalid size. Remove `SorensenDiceError`, `NgramSizeInvalid`, `sorensen_dice_bigrams`, and `sorensen_dice_trigrams`; pass the desired size to `sorensen_dice`.
- Breaking: remove `closest`; use `did_you_mean` followed by `list.first`.
- Breaking: return raw formula values from `flesch_reading_ease`, `flesch_kincaid_grade`, `gunning_fog`, `automated_readability_index`, and `coleman_liau_index`, and remove their `_unbounded` counterparts. Apply `result.map(float.clamp)` when a display needs a bounded score. Rename `smog_g` to `smog_extrapolated`; keep `smog`'s 30-sentence requirement.
- Share normalized graphemes and per-word syllable counts when calculating readability. Keep paragraph counting and the direct word-syllable fallback separate. Return immediately for empty search bounds.

```gleam
// Before: import textmetrics/similarity
let score = similarity.jaro_winkler("MARTHA", "MARHTA")

// After: import textmetrics
let assert Ok(score) = textmetrics.jaro_winkler(
  "MARTHA", "MARHTA", prefix_scale: 0.1, prefix_max: 4,
)
```

### Fixed

- Keep letters and non-ASCII decimal digits in words when they carry U+20E3 or U+FE0F. Only ASCII digits use the additional emoji exclusion; counts and readability now retain these non-emoji graphemes.
- Reject a NaN Jaro-Winkler prefix scale before checking the prefix cap or input strings on JavaScript, using `PrefixScaleOutOfRange`.
- Allow Unicode table verification with `--check` in a read-only checkout. Format the check candidate in the system temporary directory; generation still replaces the output atomically from the same directory.
- Treat unassigned Unicode 15.1 code points, including noncharacters, as word boundaries instead of letters. This corrects word and character counts and can change sentence boundaries, polysyllable counts, and readability results. For example, `a.\u{FDD0}b` now has two sentences, and `banana\u{FDD0}banana` has two polysyllabic words.
- Preserve fractional half-transpositions in Jaro similarity. Three mismatches in the matched sequences contribute 1.5 transpositions; integer division previously discarded the fraction. Jaro-Winkler scores and candidate ranking inherit the corrected values.

### Documentation

- Rewrite the README and public comments around the consolidated API, raw readability scores, Unicode input units, and fallible operations. Document that different strings can share a maximum similarity score and that unified diff elements are individual lines without final-newline metadata.
- Move release verification to CONTRIBUTING.md and document regeneration from the fixed Unicode 15.1 data file. Normalization and grapheme segmentation still use the target runtime's Unicode data.

## [0.10.0] - 2026-11-22

### Changed

- Jaro-Winkler scores change: `similarity.jaro_winkler`, `jaro_winkler_with` and `search.rank_jaro_winkler` add the prefix bonus only when the Jaro similarity is above 0.7, as in Winkler's definition and in rapidfuzz and jellyfish. `jaro_winkler("abcxyz", "abcdef")` is now 0.6667 instead of 0.7667, so fixed thresholds may match different pairs.
- `count` and the readability scores count a grapheme as a letter only when its first code point is a letter, mark or decimal or letter number (General_Category L, M, Nd or Nl, Unicode 15.1). Punctuation and symbols of every script (`—`, `…`, `・`, `™`, `،`), other numbers such as `①`, `²` and `½`, keycap emoji and spaces such as NBSP are separators and are not counted by `characters`.
- `count` normalises its input to NFC, so `"cafe\u{0301}"` has as many syllables as `"café"`.
- `count.sentences` also ends a sentence at `…`, `。`, `．`, `！`, `？`, `।` and `॥`. Abbreviation rules such as `Mr.` still apply to the ASCII `.` only.

### Fixed

- `similarity.jaro_winkler_with` no longer returns scores above 1.0. The prefix that earns the bonus stops where `prefix_scale * prefix_length` would exceed 1.
- The `similarity` functions and `search.rank_jaro_winkler` normalise their inputs to NFC like `distance` does, so `"\u{00E9}"` and `"e\u{0301}"` compare as equal.
- Unified diff headers remove CRLF from file names. A name containing `"\r\n"` used to break the header.
- `diff.patience` no longer overflows the JavaScript stack on deeply nested inputs, and finds its anchors in O(k log² k) instead of O(k²).
- `count.sentences` is linear on long dotted tokens such as URLs and version numbers; 40 KB of `"a."` took 13 seconds.
- `lcs.sequence` uses O(n√m) memory instead of a full table, and `distance.damerau_levenshtein`, `distance.osa` and `similarity.jaro` no longer index a `Dict` per cell. Results are unchanged.
- `search.did_you_mean` and `search.rank_jaro_winkler` normalise and split the query once per call instead of once per candidate.
- Several doc comments now match the code, including the cost of an edit script, which is the indel distance.

## [0.9.0] - 2026-11-19

### Changed

- GitHub Releases now attach the Hex package tarball, `checksums.txt`, a keyless cosign signature bundle for it and build provenance (`*.intoto.jsonl`). See "Verifying releases" in the README.

## [0.8.0] - 2026-09-11

### Changed

- The minimum Gleam version is now 1.14.0 (was 1.15.0). 1.14.0 builds and tests the package unchanged on both targets, and `gleam_stdlib` 1.0 already requires it. CI tests that floor alongside the latest Gleam 1.x.

### Fixed

- `textmetrics/count.sentences` no longer splits sentences at multi-period abbreviations or at periods inside a token. A period followed directly by a letter or digit (`3.50`, `example.com`, the first period of `p.m.`) never ends a sentence, and a period that closes an abbreviation made of one- or two-letter parts (`e.g.`, `i.e.`, `a.m.`, `p.m.`, `U.S.`, `U.S.A.`, `Ph.D.`) ends one only when the next word is capitalised: `"He left at 5 p.m. yesterday."` is now 1 sentence (was 3) and `"at 5 p.m. Then he left."` is 2. `Ave.` and `Blvd.` join the single-period abbreviations. Readability scores built on sentence counts change accordingly for such text. (#33)

## [0.7.0] - 2026-05-22

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
