# textmetrics

[![CI](https://github.com/nao1215/textmetrics/actions/workflows/ci.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/ci.yml)
[![Gitleaks](https://github.com/nao1215/textmetrics/actions/workflows/gitleaks.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/gitleaks.yml)
[![Trivy](https://github.com/nao1215/textmetrics/actions/workflows/trivy.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/trivy.yml)
[![OSV-Scanner](https://github.com/nao1215/textmetrics/actions/workflows/osv-scan.yml/badge.svg)](https://github.com/nao1215/textmetrics/actions/workflows/osv-scan.yml)
[![Hex](https://img.shields.io/hexpm/v/textmetrics)](https://hex.pm/packages/textmetrics)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/textmetrics/)
[![Hex Downloads](https://img.shields.io/hexpm/dt/textmetrics)](https://hex.pm/packages/textmetrics)
[![License](https://img.shields.io/github/license/nao1215/textmetrics)](https://github.com/nao1215/textmetrics/blob/main/LICENSE)
[![OpenSSF Scorecard](https://api.scorecard.dev/projects/github.com/nao1215/textmetrics/badge)](https://scorecard.dev/viewer/?uri=github.com/nao1215/textmetrics)

textmetrics compares text, builds diffs, and calculates English readability scores in Gleam.

Use it to rank spelling suggestions, measure edits between strings, compare line sequences, or calculate reading-level estimates. String comparisons normalize Unicode to NFC and operate on grapheme clusters. The package runs on Erlang and JavaScript; readability scores use an English syllable heuristic.

## Installation

```sh
gleam add textmetrics@0
```

Requires Gleam 1.14 or later.

## Usage

```gleam
import gleam/int
import gleam/io
import textmetrics

pub fn main() {
  textmetrics.levenshtein("kitten", "sitting")
  |> int.to_string
  |> io.println
}
```

Running this with `gleam run` prints `3`: the minimum number of insertions, deletions, and substitutions needed to turn one string into the other. [`did_you_mean`](https://hexdocs.pm/textmetrics/textmetrics.html#did_you_mean) uses this distance to select candidates and keeps their input order when distances tie.

The [API reference](https://hexdocs.pm/textmetrics/textmetrics.html) covers distances, similarity scores, longest common subsequences, Myers and patience diffs, word counts, and readability formulas. All functions use the `textmetrics` import.

## Input and result conventions

String comparison normalizes inputs to NFC using the target runtime. Generic list operations compare their elements directly. Candidate ranking returns the original candidate strings. Similarity scores range from `0.0` to `1.0`. Different strings can receive the same maximum score.

Unified diff rendering takes an edit script of individual lines without line terminators. It emits LF-terminated lines and does not preserve whether a file originally lacked its final newline.

Readability functions return a Result containing the raw formula value, which may fall outside customary display ranges. They return an error for input with no words; `smog` also requires 30 sentences. `smog_extrapolated` permits shorter samples. The syllable heuristic does not detect language, and its reading-level estimates are intended for English.

## Contributing

See [CONTRIBUTING.md](https://github.com/nao1215/textmetrics/blob/main/CONTRIBUTING.md) for development and release verification, and the [testing guide](https://github.com/nao1215/textmetrics/blob/main/doc/testing.md) for the test methods. Report reproducible problems in [GitHub Issues](https://github.com/nao1215/textmetrics/issues).

## License

[MIT](https://github.com/nao1215/textmetrics/blob/main/LICENSE).
