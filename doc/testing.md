# Testing

`just ci` runs formatting, lint, type checking, and the Gleam builds and tests on both targets. CI checks the Gleam floor (1.14.0, OTP 27, Node 22) on Ubuntu and the latest Gleam 1.x on Linux, macOS, and Windows. Generator checks and mutation tests run separately; the nightly workflow repeats the Gleam suite.

## Examples and unit tests

Tests under `test/textmetrics/` cover each algorithm family through the public `textmetrics` module. `test/reference/` pins published values and NFC/NFD equivalence, `test/readme_test.gleam` retains runnable usage examples, and each fixed bug keeps its reproduction in a `test/regression_*_test.gleam` file. Boundary tests cover empty inputs, single graphemes, emoji sequences, and diff behavior.

## Generated properties

`test/property/` and `test/dig_round2_property_test.gleam` use metamon to check the axioms each measure promises: identity, symmetry, non-negativity and the triangle inequality for the distances, the `[0, 1]` range and identity for the similarities, and that a diff's edit script replays to both inputs.

## Metamorphic relations

`test/dig_round3_metamorphic_test.gleam` checks relations between runs: reversing both inputs keeps the Levenshtein distance, a common prefix leaves it unchanged and grows the LCS by its length, Myers' edit cost equals `|old| + |new| - 2 * lcs`, and Patience never costs less than Myers.

## Differential testing

`test/reference/naive_oracle_test.gleam` compares distance implementations with recursive definitions of Levenshtein, optimal string alignment, and LCS length on short strings with repeated letters, accents, and emoji. Damerau-Levenshtein is checked against distance bounds, and `longest_common_subsequence` must return a common subsequence of maximal length. The legacy reference keeps its independent v0.9.0 algorithms, including Jaro's rounded-down transposition count, which the regression tests also check against rapidfuzz and jellyfish values.

## Unified diff round trip

`test/property/unified_round_trip_test.gleam` applies `to_unified` output with an independent test parser. It validates both old and new hunk positions, zero-count ranges, body counts, ordered nonoverlapping hunks, and context/deletions against the old input. Invalid fixtures exercise the parser itself, including a wrong new position in a later hunk. Applying the patch must reconstruct the new input for Myers and patience scripts and zero to four context lines. Context must remain minimal.

## Unicode generation and API boundaries

The Unicode regressions cover unassigned code points, noncharacters, First/Last range interiors, and letters assigned after Unicode 15.1. Word boundary tests cover the UAX #29 rules for apostrophes, periods, and commas inside words and numbers and for format characters; sentence tests cover quotation marks and brackets after a terminator. They also check the effects on sentence counts, polysyllabic words, and SMOG's sentence minimum. The direct nonempty word-syllable fallback is tested separately from phrase counting.

`scripts/test_gen_unicode_category.py` tests the fixed-data generator, malformed ranges, and output preservation and temporary-file cleanup on failure. The regeneration commands are in CONTRIBUTING.md. After the Unicode 17.0 update, every generated function was compared with the fixed Unicode data over all code points on both targets; there were no differences.

The API validation tests cover Jaro-Winkler and unified diff error priority before empty or unchanged input shortcuts. Raw readability fixtures include values outside display ranges; separate assertions apply the caller's clamp. Generic list tests use integers and records as well as strings.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `metamon.with_seed` and kept as a regression test.

## Mutation testing

Manual mutation checks use `gleam_mutate.py` from the mutation-testing lab in nao1215/debimate on a copy of the project. It rewrites one operator or boolean result at a time and runs `gleam test` on the Erlang target; a timeout beyond 120 seconds counts as killed. The recorded run also mutated integer comparisons and `+` / `-`. The score is killed / (killed + lived). The module names below describe the source layout at the time of that run.

| Date | Files | Killed | Lived | Score |
|---|---|---:|---:|---:|
| 2026-11-19, first run | every module under `src/` with mutants (367) | 289 | 78 | 78.7% |
| 2026-11-19, after the new tests | same | 294 | 73 | 80.1% |

The first run showed that no test counted the syllables of a word with à, ï, ô or ý, and that no Sørensen-Dice test used a string of exactly `n` graphemes; `syllables_count_each_latin1_accented_vowel_family_test` and `sorensen_dice_counts_the_one_ngram_of_a_string_of_length_n_test` now kill those mutants. The survivors, grouped:

- `diff` (28): bounds and tie-breaks inside the Myers and Patience searches. Most produce a different but still optimal edit script, which every relation accepts (it replays, its cost equals the LCS bound, its unified diff applies with minimal context). A test would have to pin one particular optimal script.
- `count` (32): the upper-case accented vowels (the pipeline lowercases first, so they are unreachable), the abbreviation and capitalisation heuristics of sentence splitting, and Unicode letter ranges that no test text reaches.
- `lcs` (3) and `distance` (4): which of several longest common subsequences the backtrack returns, `max` on equal lengths, and matrix cells that are initialised but never read.
- `similarity` (5) and `readability` (1): loop bounds that read one index past the end and fall back to a default, and a clamp at its exact bound.
