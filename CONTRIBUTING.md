# Contributing to textmetrics

## Development setup

You need the following tools installed:

- [Gleam](https://gleam.run/) 1.14+ (`.mise.toml` pins the local formatting toolchain)
- Erlang/OTP 27+ (CI tests 27 and 29)
- Node.js 22+ (for JavaScript-target checks)
- [just](https://github.com/casey/just) as a task runner
- [mise](https://mise.jdx.dev/) for toolchain management

Clone the repository and install the toolchain:

```console
git clone https://github.com/nao1215/textmetrics.git
cd textmetrics
mise install
just deps
```

`just` recipes source `scripts/lib/mise_bootstrap.sh`, so `mise activate`
is not required in the current shell.

## Running checks

Run the standard verification set with:

```console
just ci
```

This runs format check, lint, type check, Erlang-target build/test, and
JavaScript-target build/test. Individual commands:

| Command | Effect |
| --- | --- |
| `just format` | Reformat `src/` and `test/` |
| `just format-check` | Fail on formatting drift |
| `just lint` | Run `glinter` |
| `just typecheck` | Run `gleam check` |
| `just build-erlang` / `just build-javascript` | Per-target build |
| `just test-erlang` / `just test-javascript` | Per-target test |
| `just docs` | Build HexDocs HTML |
| `just clean` | Delete `build/` |

## Code style

- Run `gleam format src/ test/` before committing.
- The build uses `--warnings-as-errors`; fix all warnings.
- `glinter` runs in `warnings_as_errors` mode. Rule overrides live under
  `[tools.glinter]` in `gleam.toml`.
- Public API (`pub fn`, `pub type`) requires doc comments.
- Keep pure, cross-target code in `src/` unless a target-specific need is
  documented explicitly.

## Pull request expectations

- All CI checks must pass (`just ci`).
- Include tests for new behavior.
- Use [Conventional Commits](https://www.conventionalcommits.org/) for
  commit messages (`feat:`, `fix:`, `docs:`, `ci:`, ...).
- Keep each PR to one logical change.

## Bug reports

When reporting a bug, include:

- Gleam version
- Erlang/OTP version
- Node.js version if the issue is JavaScript-target specific
- Minimal reproduction code
- Expected behavior and actual behavior

## Regenerating Unicode categories

The generated tables use Unicode 17.0.0: general categories from `UnicodeData.txt`, and the word and sentence break classes used for counting from `WordBreakProperty.txt` and `SentenceBreakProperty.txt`. Regeneration requires Python 3 and Gleam 1.19.2 for formatting. Download the fixed inputs separately, then run the generator:

```sh
curl -LfsS https://www.unicode.org/Public/17.0.0/ucd/UnicodeData.txt -o /tmp/UnicodeData-17.0.0.txt
curl -LfsS https://www.unicode.org/Public/17.0.0/ucd/auxiliary/WordBreakProperty.txt -o /tmp/WordBreakProperty-17.0.0.txt
curl -LfsS https://www.unicode.org/Public/17.0.0/ucd/auxiliary/SentenceBreakProperty.txt -o /tmp/SentenceBreakProperty-17.0.0.txt
python3 scripts/gen_unicode_category.py --unicode-data /tmp/UnicodeData-17.0.0.txt --word-break-property /tmp/WordBreakProperty-17.0.0.txt --sentence-break-property /tmp/SentenceBreakProperty-17.0.0.txt
python3 scripts/gen_unicode_category.py --unicode-data /tmp/UnicodeData-17.0.0.txt --word-break-property /tmp/WordBreakProperty-17.0.0.txt --sentence-break-property /tmp/SentenceBreakProperty-17.0.0.txt --check
python3 -m unittest discover -s scripts -p 'test_gen_unicode_*.py'
python3 scripts/gen_unicode_category_fixture.py --unicode-data /tmp/UnicodeData-17.0.0.txt --word-break-property /tmp/WordBreakProperty-17.0.0.txt --sentence-break-property /tmp/SentenceBreakProperty-17.0.0.txt
```

`scripts/gen_unicode_category_fixture.py` writes `test/unicode_category_ranges.gleam`, the expected ranges that `test/unicode_category_table_test.gleam` checks the generated table against. It parses the inputs with its own code, so regenerate both files from the same data; `--check` compares without writing.

The generator checks the SHA-256 of each input, expands First/Last ranges, and treats unlisted code points as unassigned. It replaces the output only after parsing and formatting succeed; `--check` compares without replacing it. It does not use Python's Unicode database or download data. The fixed tables are separate from the target runtime's NFC normalization and grapheme segmentation.

## Verifying releases

Each GitHub Release attaches the tarball published to Hex (`textmetrics-<version>.tar`), `checksums.txt`, a cosign signature bundle (`checksums.txt.sigstore.json`) and build provenance (`textmetrics-<version>.intoto.jsonl`). The release workflow downloads the tarball from Hex after `gleam publish` and checks it against the checksum Hex records before signing it, so the tarball you get from Hex is the one that is signed and attested.

```sh
curl -fsSLO https://repo.hex.pm/tarballs/textmetrics-<version>.tar
gh attestation verify textmetrics-<version>.tar --repo nao1215/textmetrics
```

To check the signature as well, download `checksums.txt` and `checksums.txt.sigstore.json` from the Release into the same directory. The workflow runs on the release tag, or on `main` when the assets of a published tag are attached again.

```sh
cosign verify-blob \
  --bundle checksums.txt.sigstore.json \
  --certificate-identity-regexp '^https://github\.com/nao1215/textmetrics/\.github/workflows/release\.yml@refs/(tags/v.+|heads/main)$' \
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \
  checksums.txt
sha256sum --check checksums.txt
```

## License

Contributions to this project are considered to be released under the project's MIT license.
