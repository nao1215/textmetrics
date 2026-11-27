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

`.github/workflows/nightly-property.yml` runs the whole suite ten times with `METAMON_RUNS_MULTIPLIER=10`, each pass with a new seed. A failure report prints its seed, so the case can be replayed with `Config(..default_config(), seed: Some(seed))` and kept as a regression test.

## Mutation testing

`gleam run -m metamon/mutation` changes one operator, `!` or boolean literal in a module under `src/` at a time and runs `gleam test --target erlang` on each change. `src/textmetrics/internal/unicode_category.gleam` is left out (`--exclude` in `.github/workflows/mutation.yml` and the justfile): it is generated from the Unicode data by `scripts/gen_unicode_category.py`, its 3,162 mutants are range bounds of that table, and they would make a full run take hours. `.github/workflows/mutation.yml` mutates the modules a pull request changes and fails on a survivor that `doc/mutation/baseline.json` does not list; the weekly run mutates every module. `just mutation` runs everything and `just mutation-record` writes the baseline.

The first run (2026-11-27) scored 83.8%. Tests were then added for paragraphs of two and three lines, the silent `e` of `make`, `style` and `goodbye`, an initial `y` (`Ypres`), the digit `9` in a number and the keycaps `0` and `9`, month and day abbreviations, a digit after `e.g.`, Unicode spaces before a capital, closing marks at the end of the text, a period after dotted digits, a repeated bigram in Sorensen-Dice, and Gunning Fog and SMOG on two sentences with polysyllables, and the score rose to 88.4%. The 46 survivors left change nothing that a caller can see:

- The empty case of a grapheme or of the rest of the text (7): a grapheme always has a code point, and at the end of the text the last sentence is counted either way.
- Code point bounds that no input reaches (6): U+0080 is neither a letter nor a digit, U+2000 becomes U+2002 under NFC before the whitespace check, and the start-of-word flag of the accented vowel check only matters for the ASCII `y`.
- The length of an abbreviation token (2): it is only compared with 5, the longest abbreviation.
- Distances (3): swapping two inputs of the same length, which the distances do not depend on, and a transposition read at column 0, which `array_get` rejects anyway.
- Mutants that loop forever (4): `int_range_inclusive_loop`, `myers_search`, `myers_step` and `rebuild_frontiers` stepping the wrong way. A run kills them when the test suite times out, but on a machine where earlyoom stops a runaway BEAM with SIGTERM, the BEAM exits with status 0 and the run reports them as lived. Two runs after the new tests gave different results for `myers_step`, so the baseline lists all four as lived and the gate does not depend on the machine.
- The linear-memory LCS (8) and Myers search (8): checkpoint spacing changes only how much is kept in memory, and the other guards change no result that the exact comparison with v0.9.0, the replay and optimality relations and the unified diff round trip can see.
- Array reads past the end (2), which never happen.
- Patience (3): a line count that never returns to 1 once it has passed it, and two comparisons of line indices, which are distinct.
- Search and similarity (3): `top_n` of exactly 0, which takes nothing either way, a Jaro score of exactly 0.7, which the floating-point formula does not produce, and the end of the Jaro match window past the last grapheme.

<!-- mutation:start -->
| Module | Killed | Lived | Timed out | Score |
|---|---:|---:|---:|---:|
| `textmetrics` | 348 | 46 | 1 | 88.4% |
| all | 348 | 46 | 1 | 88.4% |
<!-- mutation:end -->
