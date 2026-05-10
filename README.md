# textmetrics

[![Package Version](https://img.shields.io/hexpm/v/textmetrics)](https://hex.pm/packages/textmetrics)
[![Downloads](https://img.shields.io/hexpm/dt/textmetrics)](https://hex.pm/packages/textmetrics)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/textmetrics/)
[![CI](https://github.com/nao1215/textmetrics/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/ci.yml)
[![License](https://img.shields.io/github/license/nao1215/textmetrics)](LICENSE)

String comparison metrics for Gleam: edit distances, similarity scores,
longest common subsequence, and line-level diff.

## Features

- Edit distances: Levenshtein, Damerau-Levenshtein (true variant), OSA, Hamming
- Similarity scores in `[0.0, 1.0]`: Jaro, Jaro-Winkler, Sørensen-Dice
- Longest common subsequence (length and a recovered sequence)
- Diff: Myers (1986) and patience, plus POSIX unified-diff rendering
- `did_you_mean` and Jaro-Winkler ranking for spell-correction style search
- Pure Gleam, runs on Erlang and JavaScript targets
- Operates on Unicode grapheme clusters (UAX #29)

## Install

```sh
gleam add textmetrics
```

## Suggesting a similar command name

When a user mistypes a subcommand or flag, fall back to a Levenshtein-bounded
search to suggest the closest known names. Ties are broken by the order they
appear in `candidates`, which keeps suggestions deterministic.

```gleam
import textmetrics/search

pub fn suggest_command(typed: String) -> List(String) {
  let known = ["install", "uninstall", "remove", "update", "help"]
  search.did_you_mean(typed, known, 2)
}

// suggest_command("instal") -> ["install"]
// suggest_command("updat")  -> ["update"]
// suggest_command("xyz")    -> []
```

## Comparing strings: Levenshtein, Damerau-Levenshtein, OSA

`levenshtein` counts the minimum number of insert / delete / substitute
operations. `damerau_levenshtein` adds adjacent-grapheme transposition and
lets the same substring participate in multiple edits. `osa` uses the same
operations but allows each substring to be edited at most once — that is
what most "Damerau distance" libraries actually compute.

```gleam
import textmetrics/distance

pub fn distances() -> #(Int, Int, Int) {
  let l = distance.levenshtein("CA", "ABC")
  let dl = distance.damerau_levenshtein("CA", "ABC")
  let o = distance.osa("CA", "ABC")
  #(l, dl, o)
}

// distances() -> #(3, 2, 3)
```

`hamming` requires equal-length inputs and returns
`Error(LengthMismatch(...))` otherwise, so callers do not have to
pre-validate the input lengths.

```gleam
import textmetrics/distance

pub fn hamming_check(
  a: String,
  b: String,
) -> Result(Int, distance.HammingError) {
  distance.hamming(a, b)
}

// hamming_check("karolin", "kathrin") -> Ok(3)
// hamming_check("ab", "abc")          -> Error(LengthMismatch(left: 2, right: 3))
```

## Scoring similarity: Jaro, Jaro-Winkler, Sørensen-Dice

`jaro_winkler` boosts scores for strings that share a common prefix, which
suits typo tolerance in human names. `sorensen_dice` compares the multiset
of grapheme n-grams.

```gleam
import textmetrics/similarity

pub fn jaro_score() -> Float {
  similarity.jaro("MARTHA", "MARHTA")
}

pub fn jaro_winkler_score() -> Float {
  similarity.jaro_winkler("MARTHA", "MARHTA")
}

pub fn dice_score() -> Result(Float, similarity.SorensenDiceError) {
  similarity.sorensen_dice("night", "nacht", 2)
}

// jaro_score()         -> 0.944_444…
// jaro_winkler_score() -> 0.961_111…
// dice_score()         -> Ok(0.25)
```

`jaro_winkler_with` accepts a validated `JaroWinklerConfig` for non-default
prefix scaling. The smart constructor enforces `prefix_scale ∈ [0.0, 0.25]`
and `prefix_max >= 0`.

```gleam
import gleam/result
import textmetrics/similarity

pub fn aggressive_winkler() -> Result(
  Float,
  similarity.JaroWinklerConfigError,
) {
  use cfg <- result.map(similarity.jaro_winkler_config(
    prefix_scale: 0.2,
    prefix_max: 6,
  ))
  similarity.jaro_winkler_with("MARTHA", "MARHTA", cfg)
}
```

## Producing an edit script and a unified diff

`diff.myers` returns an `EditScript` — a list of `Equal | Insert | Delete`
steps that round-trips both inputs. `to_unified` renders that script in
the format `diff -u` produces.

```gleam
import textmetrics/diff

pub fn render_diff() -> String {
  let old = ["the quick brown", "fox jumps over", "the lazy dog"]
  let new = ["the quick brown", "fox leaps over", "the lazy dog"]
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  diff.to_unified(diff.myers(old, new), opts)
}

// render_diff() ->
// --- a
// +++ b
// @@ -1,3 +1,3 @@
//  the quick brown
// -fox jumps over
// +fox leaps over
//  the lazy dog
```

`recover_old` and `recover_new` rebuild the inputs from a script. The
round-trip property is the principal invariant of the `Edit` ADT.

```gleam
import textmetrics/diff
import textmetrics/edit

pub fn round_trip_holds() -> Bool {
  let old = ["a", "b", "c"]
  let new = ["a", "x", "c"]
  let script = diff.myers(old, new)
  edit.recover_old(script) == old && edit.recover_new(script) == new
}

// round_trip_holds() -> True
```

## Longest common subsequence

```gleam
import textmetrics/lcs

pub fn lcs_example() -> #(Int, List(String)) {
  let a = ["A", "B", "C", "B", "D", "A", "B"]
  let b = ["B", "D", "C", "A", "B", "A"]
  #(lcs.length(a, b), lcs.sequence(a, b))
}

// lcs_example() -> #(4, ["B", "C", "B", "A"])  // one valid answer
```

`lcs.length` is well-defined; `lcs.sequence` returns one valid longest
common subsequence. Consumers should rely on
`length(sequence(a, b)) == length(a, b)` rather than on the specific
subsequence chosen.

## Unicode policy

All string-typed functions operate on extended grapheme clusters via
`gleam/string.to_graphemes`. The library does not normalize input — NFC
and NFD strings that render identically are reported as different.
Callers wanting NFC equivalence should normalize before invoking.

## Development

```sh
mise install
just deps
just ci
```

`just` recipes source `scripts/lib/mise_bootstrap.sh`, so `mise activate`
is not required in the current shell.

## License

[MIT](LICENSE)
