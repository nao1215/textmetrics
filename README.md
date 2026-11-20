# textmetrics

[![CI](https://github.com/nao1215/textmetrics/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/textmetrics/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/textmetrics/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/textmetrics/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/textmetrics)](https://hex.pm/packages/textmetrics)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/textmetrics/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/textmetrics)](https://hex.pm/packages/textmetrics)
[![License](https://img.shields.io/github/license/nao1215/textmetrics)](./LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/textmetrics/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/textmetrics)

String comparison and readability metrics for Gleam. Pure Gleam, on the
Erlang and JavaScript targets, working on Unicode grapheme clusters
(UAX #29).

- Edit distances: Levenshtein, Damerau-Levenshtein (true variant), OSA, Hamming
- Similarity scores in `[0.0, 1.0]`: Jaro, Jaro-Winkler, Sørensen-Dice
- Longest common subsequence (length and a recovered sequence)
- Diff: Myers (1986) and patience, plus POSIX unified-diff rendering
- `did_you_mean` and Jaro-Winkler ranking for spell-correction style search
- Readability: Flesch Reading Ease, Flesch-Kincaid Grade, Gunning Fog,
  SMOG, Automated Readability Index, Coleman-Liau
- Count primitives: words, sentences, syllables, characters, paragraphs,
  polysyllables

## Install

```sh
gleam add textmetrics
```

## Suggesting a similar command name

`search.did_you_mean` returns the known names within a Levenshtein bound.
Ties keep the order of `candidates`.

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

`search.closest` returns a single suggestion.

```gleam
import gleam/option.{type Option}
import textmetrics/search

pub fn one_suggestion(typed: String) -> Option(String) {
  let known = ["install", "uninstall", "remove", "update", "help"]
  search.closest(typed, known, 2)
}

// one_suggestion("instal") -> Some("install")
// one_suggestion("xyz")    -> None
```

## Comparing strings: Levenshtein, Damerau-Levenshtein, OSA

`levenshtein` counts inserts, deletes, and substitutions.
`damerau_levenshtein` also counts adjacent transpositions and lets a
substring be edited more than once. `osa` edits each substring at most
once, which is what most "Damerau distance" libraries compute.

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

`distance.normalized_levenshtein` turns the distance into a similarity in
`[0.0, 1.0]`, where `1.0` means identical.

```gleam
import textmetrics/distance

pub fn levenshtein_similarity() -> Float {
  // levenshtein = 3, max graphemes = 7 → 1 - 3/7 = 4/7.
  distance.normalized_levenshtein("kitten", "sitting")
}
```

`hamming` returns `Error(LengthMismatch(...))` when the lengths differ.

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

`jaro_winkler` raises the score for a shared prefix, which helps with
typos in names. `sorensen_dice` compares grapheme n-grams.

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

`jaro_winkler_with` takes a `JaroWinklerConfig` for other prefix scaling.
Its constructor requires `prefix_scale ∈ [0.0, 0.25]` and `prefix_max >= 0`.

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

`diff.myers` returns an `EditScript`, a list of `Equal | Insert | Delete`
steps. `to_unified` renders it in `diff -u` format.

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

`diff.unified_options` strips CR, LF, NUL, and TAB from the header names.
`diff.unified_options_checked` takes the same arguments and returns
`Result(UnifiedOptions, UnifiedOptionsError)` instead.

`recover_old` and `recover_new` rebuild both inputs from a script.

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

`lcs.sequence` returns one of the longest common subsequences, so rely on
`length(sequence(a, b)) == length(a, b)`, not on which one it picks.

## Readability scores

Six English readability formulas. Each returns `Result(Float, _)`, so an
input that is too small (SMOG needs 30 sentences) gets an error instead of
a non-finite number.

```gleam
import textmetrics/readability

pub fn grade_for(text: String) -> Result(Float, readability.ReadabilityError) {
  readability.flesch_kincaid_grade(text)
}

// grade_for("The quick brown fox jumps over the lazy dog.")
// -> Ok(~2.3)   (mid-2nd-grade reading level)
```

`textmetrics/count` has the counters behind them: `count.words`,
`count.sentences`, `count.syllables_in_word`, `count.syllables`,
`count.characters`, `count.paragraphs`, `count.polysyllables`. Syllables
are counted with an English heuristic (silent `e`, with the consonant-`le`
exception), and other languages get one syllable per word, so grades only
mean something for English.

## Unicode policy

String functions work on extended grapheme clusters
(`gleam/string.to_graphemes`) after NFC normalization, so `"\u{00C1}"`
(`U+00C1`) and `"A\u{0301}"` (`U+0041 U+0301`) compare equal. NFC uses the
platform normalizer (`unicode:characters_to_nfc_binary/1` on Erlang,
`String.prototype.normalize("NFC")` on JavaScript), with no extra
dependency.

## Development

```sh
mise install
just deps
just ci
```

`just` recipes source `scripts/lib/mise_bootstrap.sh`, so `mise activate`
is not required in the current shell.

## Testing

| Technique | Bug class caught here |
|---|---|
| Examples and unit tests | [Wrong values against published examples, Unicode edge cases](doc/testing.md#examples-and-unit-tests) |
| Generated properties | [Broken metric axioms, edit scripts that do not replay](doc/testing.md#generated-properties) |
| Metamorphic relations | [Distances and diffs that change under reversal or a common prefix](doc/testing.md#metamorphic-relations) |
| Differential testing | [Optimised distance code that disagrees with the textbook definition](doc/testing.md#differential-testing) |
| Unified diff round trip | [Hunk headers, counts or context that `patch` would reject](doc/testing.md#unified-diff-round-trip) |
| Mutation testing | [Assertions that miss a changed operator or branch](doc/testing.md#mutation-testing) |

## Verifying releases

Each GitHub Release attaches the Hex package tarball (`textmetrics-<version>.tar`),
`checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and
build provenance (`textmetrics-<version>.intoto.jsonl`). Download the assets, then:

```sh
gh attestation verify textmetrics-<version>.tar --repo nao1215/textmetrics

cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/textmetrics/\.github/workflows/release\.yml@refs/tags/v' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

[MIT](LICENSE)
