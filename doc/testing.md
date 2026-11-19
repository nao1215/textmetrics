# Testing

`just ci` runs everything below except the nightly job and mutation testing. Tests run on the Erlang and JavaScript targets, on the Gleam floor (1.14.0, OTP 27, Node 22) and on the latest Gleam 1.x, on Linux, macOS and Windows.

## Examples and unit tests

Every module has a test file under `test/textmetrics/`. `test/reference/` pins published values (Levenshtein, Jaro and Jaro-Winkler examples, NFC/NFD equivalence), `test/readme_test.gleam` runs the README snippets, and each fixed bug keeps its reproduction in a `test/regression_*_test.gleam` file. `test/dig_round1_boundary_test.gleam` and `test/dig_round4_targeted_test.gleam` probe empty inputs, single graphemes, emoji sequences and the internals of the diff algorithms.

## Generated properties

`test/property/` and `test/dig_round2_property_test.gleam` use metamon to check the axioms each measure promises: identity, symmetry, non-negativity and the triangle inequality for the distances, the `[0, 1]` range and identity for the similarities, and that a diff's edit script replays to both inputs.

## Metamorphic relations

`test/dig_round3_metamorphic_test.gleam` checks relations between runs: reversing both inputs keeps the Levenshtein distance, a common prefix leaves it unchanged and grows the LCS by its length, Myers' edit cost equals `|old| + |new| - 2 * lcs`, and Patience never costs less than Myers.

## Differential testing

`test/reference/naive_oracle_test.gleam` compares the optimised distance code (rolling rows, a dictionary-backed matrix) with the plain recursive definitions of Levenshtein, optimal string alignment and the LCS length on random short strings that mix repeated letters, precomposed and decomposed accents and an emoji with a skin-tone modifier. Damerau-Levenshtein, which has no short recursive definition, is checked to lie between half of Levenshtein and the smaller of OSA and Levenshtein, and `lcs.sequence` must be a common subsequence of maximal length.

## Unified diff round trip

`test/property/unified_round_trip_test.gleam` applies the output of `diff.to_unified` with a strict applier written in the test: the file header, hunk headers whose counts match the body, hunks in order without overlap, and context and deleted lines that equal the old file. Applying the patch to `old` must give `new` for Myers and Patience scripts and 0 to 4 context lines, and the context must be minimal: at most `n` unchanged lines before and after the changes of a hunk, at most `2n` between two changes, and at least one unshown line between two hunks.

## Nightly runs

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `metamon.with_seed` and kept as a regression test.

## Mutation testing

There is no mutation testing tool for Gleam, so `gleam_mutate.py` (from the mutation-testing lab in nao1215/debimate) is run by hand on a copy of the project. It rewrites one operator or boolean result at a time and runs `gleam test` on the Erlang target; a mutant that makes the suite hang past 120 seconds counts as killed. For this run the script also mutated integer comparisons and `+` / `-`. The score is killed / (killed + lived).

| Date | Files | Killed | Lived | Score |
|---|---|---:|---:|---:|
| 2026-11-19, first run | every module under `src/` with mutants (367) | 289 | 78 | 78.7% |
| 2026-11-19, after the new tests | same | 294 | 73 | 80.1% |

The first run showed that no test counted the syllables of a word with à, ï, ô or ý, and that no Sørensen-Dice test used a string of exactly `n` graphemes; `syllables_count_each_latin1_accented_vowel_family_test` and `sorensen_dice_counts_the_one_ngram_of_a_string_of_length_n_test` now kill those mutants. The survivors, grouped:

- `diff` (28): bounds and tie-breaks inside the Myers and Patience searches. Most produce a different but still optimal edit script, which every relation accepts (it replays, its cost equals the LCS bound, its unified diff applies with minimal context). A test would have to pin one particular optimal script.
- `count` (32): the upper-case accented vowels (the pipeline lowercases first, so they are unreachable), the abbreviation and capitalisation heuristics of sentence splitting, and Unicode letter ranges that no test text reaches.
- `lcs` (3) and `distance` (4): which of several longest common subsequences the backtrack returns, `max` on equal lengths, and matrix cells that are initialised but never read.
- `similarity` (5) and `readability` (1): loop bounds that read one index past the end and fall back to a default, and a clamp at its exact bound.
