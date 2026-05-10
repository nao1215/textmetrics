#!/bin/sh
# mise_bootstrap.sh -- Shared helper that makes mise-managed tools
# (erlang, gleam, rebar3, node) visible on PATH without requiring the
# caller to have run `mise activate` in the current shell.
#
# Usage:
#   . scripts/lib/mise_bootstrap.sh
#   textmetrics_require_tool gleam
#
# The helper is intentionally POSIX-compatible so it can be sourced
# from `sh` as well as `bash`.

_textmetrics_mise_prepend() {
  case ":${PATH-}:" in
    *":$1:"*) ;;
    *) PATH="$1${PATH:+:$PATH}" ;;
  esac
}

_TEXTMETRICS_MISE_TOOLS="gleam escript erl rebar3 node"

textmetrics_mise_bootstrap() {
  if [ -n "${HOME:-}" ] && [ -d "$HOME/.local/bin" ]; then
    _textmetrics_mise_prepend "$HOME/.local/bin"
  fi

  if command -v mise >/dev/null 2>&1; then
    for _textmetrics_bootstrap_tool in $_TEXTMETRICS_MISE_TOOLS; do
      _textmetrics_bootstrap_path="$(mise which "$_textmetrics_bootstrap_tool" 2>/dev/null || true)"
      if [ -n "$_textmetrics_bootstrap_path" ]; then
        _textmetrics_mise_prepend "$(dirname "$_textmetrics_bootstrap_path")"
      fi
    done
    unset _textmetrics_bootstrap_tool _textmetrics_bootstrap_path
  fi

  if ! command -v gleam >/dev/null 2>&1 && [ -n "${HOME:-}" ]; then
    _textmetrics_mise_prepend "$HOME/.local/share/mise/shims"
  fi

  export PATH
}

textmetrics_require_tool() {
  if command -v "$1" >/dev/null 2>&1; then
    return 0
  fi
  cat >&2 <<EOF
error: required tool '$1' was not found on PATH.

This repository manages its toolchain (Erlang, Gleam, rebar3, Node)
with mise. To set up the development environment from a fresh
checkout:

    mise install

If mise itself is missing, see https://mise.jdx.dev/getting-started.html.
Alternatively, install '$1' by hand and make sure it is on PATH
before running this command.
EOF
  return 127
}

textmetrics_mise_bootstrap
