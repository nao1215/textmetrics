# Contributing to textmetrics

## Development setup

You need the following tools installed:

- [Gleam](https://gleam.run/) 1.15+
- Erlang/OTP 28+
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

## License

Contributions to this project are considered to be released under the
project's MIT license.
