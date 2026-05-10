set shell := ["sh", "-cu"]

# Make the mise-managed toolchain (erlang / gleam / rebar / node)
# visible to every recipe even when the invoking shell has not run
# `mise activate`. The bootstrap helper is the same one that
# standalone shell scripts source, so `just <recipe>` and
# `bash scripts/<name>.sh` behave identically in a fresh shell.
export PATH := shell('. scripts/lib/mise_bootstrap.sh; printf %s "$PATH"')

default:
  @just --list

deps:
  gleam deps download

format:
  gleam format src/ test/

format-check:
  gleam format --check src/ test/

lint:
  gleam run -m glinter

typecheck:
  gleam check

build:
  gleam build --warnings-as-errors

build-erlang:
  gleam build --warnings-as-errors --target erlang

build-javascript:
  gleam build --warnings-as-errors --target javascript

build-all-targets: build-erlang build-javascript

test:
  gleam test

test-erlang:
  gleam test --target erlang

test-javascript:
  gleam test --target javascript

test-all-targets: test-erlang test-javascript

docs:
  gleam docs build

check: clean
  gleam format --check src/ test/
  gleam run -m glinter
  gleam check
  gleam build --warnings-as-errors
  gleam test

ci: deps check build-javascript test-javascript

all: clean deps
  gleam format --check src/ test/
  gleam run -m glinter
  gleam check
  gleam build --warnings-as-errors --target erlang
  gleam build --warnings-as-errors --target javascript
  gleam test --target erlang
  gleam test --target javascript
  gleam docs build
  @echo ""
  @echo "All checks passed."

clean:
  gleam clean
