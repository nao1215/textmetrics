//// Round trip for `diff.to_unified`: a strict unified-diff applier,
//// written here independently of the renderer, must turn `old` into
//// `new` using only the rendered text.
////
//// The applier checks what `patch` relies on: the `---` / `+++`
//// header, hunk headers whose line counts match the hunk body, hunks
//// in increasing order that do not overlap, and context and deleted
//// lines that equal the old file at the stated position. A wrong
//// start line, an off-by-one count or a dropped context line fails
//// the relation even when the edit script itself is right.

import gleam/int
import gleam/list
import gleam/result
import gleam/string
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range
import textmetrics/diff

// ---------- generators ----------

/// Lines from a small alphabet so that equal lines, moved lines and
/// repeated runs are common.
fn lines_generator() -> Generator(List(String)) {
  generator.list_of(
    generator.element_of(["a", "b", "c", "d", "", "a b", "}"]),
    range.constant(0, 14),
  )
}

fn input_generator() -> Generator(#(List(String), List(String), Int)) {
  generator.tuple3(
    lines_generator(),
    lines_generator(),
    generator.int(range.constant(0, 4)),
  )
}

// ---------- strict applier ----------

type PatchError {
  BadRange(String)
  BadHunkHeader(String)
  NoTrailingNewline
  BadFileHeader
  CountsDoNotMatchBody
  HunksOverlapOrOutOfOrder
  HunkStartsPastEnd
  ContextMismatch(String)
  DeletedLineMismatch(String)
  BadHunkLine(String)
}

type Hunk {
  Hunk(old_start: Int, old_count: Int, new_count: Int, body: List(String))
}

/// `"12"` -> #(12, 1), `"12,3"` -> #(12, 3).
fn parse_range(text: String) -> Result(#(Int, Int), PatchError) {
  case string.split(text, ",") {
    [start] -> int.parse(start) |> result.map(fn(s) { #(s, 1) })
    [start, count] ->
      case int.parse(start), int.parse(count) {
        Ok(s), Ok(c) -> Ok(#(s, c))
        _, _ -> Error(Nil)
      }
    _ -> Error(Nil)
  }
  |> result.replace_error(BadRange(text))
}

fn parse_header(line: String) -> Result(#(Int, Int, Int), PatchError) {
  case string.split(line, " ") {
    ["@@", "-" <> old, "+" <> new, "@@"] -> {
      use #(os, oc) <- result.try(parse_range(old))
      use #(_, nc) <- result.try(parse_range(new))
      Ok(#(os, oc, nc))
    }
    _ -> Error(BadHunkHeader(line))
  }
}

fn parse_hunks(
  lines: List(String),
  acc: List(Hunk),
) -> Result(List(Hunk), PatchError) {
  case lines {
    [] -> Ok(list.reverse(acc))
    [header, ..rest] -> {
      use #(os, oc, nc) <- result.try(parse_header(header))
      let #(body, after) =
        list.split_while(rest, fn(l) { !string.starts_with(l, "@@ ") })
      parse_hunks(after, [Hunk(os, oc, nc, body), ..acc])
    }
  }
}

fn count_prefix(body: List(String), prefixes: List(String)) -> Int {
  list.count(body, fn(l) {
    list.any(prefixes, fn(p) { string.starts_with(l, p) })
  })
}

/// Apply `patch` to `old`. Every check failure is an `Error`.
fn apply(patch: String, old: List(String)) -> Result(List(String), PatchError) {
  case patch {
    "" -> Ok(old)
    _ -> {
      use body <- result.try(case string.ends_with(patch, "\n") {
        True -> Ok(string.drop_end(patch, 1))
        False -> Error(NoTrailingNewline)
      })
      case string.split(body, "\n") {
        ["--- old", "+++ new", ..hunk_lines] -> {
          use hunks <- result.try(parse_hunks(hunk_lines, []))
          apply_hunks(hunks, old, 1, [])
        }
        _ -> Error(BadFileHeader)
      }
    }
  }
}

/// `line` is the 1-based number of the next unread old line.
fn apply_hunks(
  hunks: List(Hunk),
  old: List(String),
  line: Int,
  acc: List(String),
) -> Result(List(String), PatchError) {
  case hunks {
    [] -> Ok(list.append(list.reverse(acc), old))
    [hunk, ..rest] -> {
      use _ <- result.try(
        case
          count_prefix(hunk.body, [" ", "-"]) == hunk.old_count
          && count_prefix(hunk.body, [" ", "+"]) == hunk.new_count
          && hunk.old_count + hunk.new_count > 0
        {
          True -> Ok(Nil)
          False -> Error(CountsDoNotMatchBody)
        },
      )
      // A hunk with no old lines names the line it is inserted after.
      let first_old = case hunk.old_count {
        0 -> hunk.old_start + 1
        _ -> hunk.old_start
      }
      use _ <- result.try(case first_old >= line {
        True -> Ok(Nil)
        False -> Error(HunksOverlapOrOutOfOrder)
      })
      let #(skipped, from_hunk) = list.split(old, first_old - line)
      use _ <- result.try(case list.length(skipped) == first_old - line {
        True -> Ok(Nil)
        False -> Error(HunkStartsPastEnd)
      })
      let acc = list.append(list.reverse(skipped), acc)
      use #(remaining, acc) <- result.try(apply_body(hunk.body, from_hunk, acc))
      apply_hunks(rest, remaining, first_old + hunk.old_count, acc)
    }
  }
}

fn apply_body(
  body: List(String),
  old: List(String),
  acc: List(String),
) -> Result(#(List(String), List(String)), PatchError) {
  case body {
    [] -> Ok(#(old, acc))
    ["+" <> added, ..rest] -> apply_body(rest, old, [added, ..acc])
    [" " <> kept, ..rest] ->
      case old {
        [o, ..old_rest] if o == kept -> apply_body(rest, old_rest, [kept, ..acc])
        _ -> Error(ContextMismatch(kept))
      }
    ["-" <> removed, ..rest] ->
      case old {
        [o, ..old_rest] if o == removed -> apply_body(rest, old_rest, acc)
        _ -> Error(DeletedLineMismatch(removed))
      }
    [other, ..] -> Error(BadHunkLine(other))
  }
}

/// Context rules of `diff -u`: at most `context` unchanged lines before
/// the first and after the last change of a hunk, at most `2 * context`
/// between two changes inside one hunk, and at least one unshown line
/// between two hunks (otherwise they should have been one hunk).
fn context_is_minimal(patch: String, context: Int) -> Bool {
  case string.split(patch, "\n") {
    ["--- old", "+++ new", ..hunk_lines] ->
      case parse_hunks(list.filter(hunk_lines, fn(l) { l != "" }), []) {
        Ok(hunks) -> hunks_are_minimal(hunks, context, -1)
        Error(_) -> False
      }
    _ -> patch == ""
  }
}

fn hunks_are_minimal(hunks: List(Hunk), context: Int, prev_end: Int) -> Bool {
  case hunks {
    [] -> True
    [hunk, ..rest] -> {
      let first_old = case hunk.old_count {
        0 -> hunk.old_start + 1
        _ -> hunk.old_start
      }
      let runs = context_runs(hunk.body)
      let inner_ok = case runs {
        [] | [_] -> True
        _ ->
          runs
          |> list.drop(1)
          |> list.take(list.length(runs) - 2)
          |> list.all(fn(n) { n <= 2 * context })
      }
      let edges_ok = case runs {
        [] -> True
        [only] -> only <= context
        [first, ..] ->
          first <= context && result.unwrap(list.last(runs), 0) <= context
      }
      { prev_end < 0 || first_old > prev_end }
      && inner_ok
      && edges_ok
      && hunks_are_minimal(rest, context, first_old + hunk.old_count)
    }
  }
}

/// Lengths of the runs of context lines, including the empty run
/// before the first change and after the last one.
fn context_runs(body: List(String)) -> List(Int) {
  let is_context = fn(l) { string.starts_with(l, " ") }
  let groups = list.chunk(body, is_context)
  let lengths =
    list.filter_map(groups, fn(group) {
      case group {
        [first, ..] ->
          case is_context(first) {
            True -> Ok(list.length(group))
            False -> Error(Nil)
          }
        [] -> Error(Nil)
      }
    })
  let starts_with_change = case body {
    [first, ..] -> !is_context(first)
    [] -> False
  }
  let ends_with_change = case list.last(body) {
    Ok(last) -> !is_context(last)
    Error(_) -> False
  }
  let lengths = case starts_with_change {
    True -> [0, ..lengths]
    False -> lengths
  }
  case ends_with_change {
    True -> list.append(lengths, [0])
    False -> lengths
  }
}

fn options(context: Int) -> diff.UnifiedOptions {
  let assert Ok(options) =
    diff.unified_options(old_name: "old", new_name: "new")
    |> diff.with_context_lines(context)
  options
}

// ---------- relations ----------

pub fn to_unified_of_myers_applies_back_to_new_test() -> Nil {
  metamon.forall(input_generator(), fn(input) {
    let #(old, new, context) = input
    diff.myers(old, new)
    |> diff.to_unified(options(context))
    |> apply(old)
    == Ok(new)
  })
}

pub fn to_unified_of_patience_applies_back_to_new_test() -> Nil {
  metamon.forall(input_generator(), fn(input) {
    let #(old, new, context) = input
    diff.patience(old, new)
    |> diff.to_unified(options(context))
    |> apply(old)
    == Ok(new)
  })
}

pub fn applier_rejects_a_wrong_count_test() -> Nil {
  // The applier itself must notice a broken header.
  let patch = "--- old\n+++ new\n@@ -1,2 +1 @@\n-a\n"
  assert apply(patch, ["a", "b"]) == Error(CountsDoNotMatchBody)
}

pub fn applier_inserts_into_an_empty_file_test() -> Nil {
  let patch = "--- old\n+++ new\n@@ -0,0 +1,2 @@\n+x\n+y\n"
  assert apply(patch, []) == Ok(["x", "y"])
}

pub fn to_unified_shows_minimal_context_test() -> Nil {
  metamon.forall(input_generator(), fn(input) {
    let #(old, new, context) = input
    diff.myers(old, new)
    |> diff.to_unified(options(context))
    |> context_is_minimal(context)
  })
}

pub fn context_check_rejects_unmerged_hunks_test() -> Nil {
  // Two hunks with no unshown line between them must be one hunk.
  let patch = "--- old\n+++ new\n@@ -1 +1 @@\n-a\n+b\n@@ -2 +2 @@\n-c\n+d\n"
  assert !context_is_minimal(patch, 0)
}

pub fn context_check_rejects_extra_leading_context_test() -> Nil {
  let patch = "--- old\n+++ new\n@@ -1,3 +1,3 @@\n a\n b\n-c\n+d\n"
  assert !context_is_minimal(patch, 1)
  assert context_is_minimal(patch, 2)
}
