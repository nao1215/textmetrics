//// Diff algorithms over arbitrary lists.
////
//// [`myers`](#myers) implements the O(ND) algorithm of Myers (1986)
//// and produces an optimal edit script.
//// [`patience`](#patience) implements Bram Cohen's patience diff over
//// `List(String)`, which often yields more readable diffs for source
//// code with moved blocks.
//// [`to_unified`](#to_unified) renders an edit script of strings in
//// the POSIX unified-diff format.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import textmetrics/edit.{type EditScript, Delete, Equal, Insert}

/// Returned by [`with_context_lines`](#with_context_lines) when given
/// a negative argument, and by [`unified_options_checked`](#unified_options_checked) /
/// [`with_old_name_checked`](#with_old_name_checked) /
/// [`with_new_name_checked`](#with_new_name_checked) when the name
/// contains a byte that would corrupt the unified-diff header
/// (`\n`, `\r`, `\u{0000}`, `\t`).
pub type UnifiedOptionsError {
  ContextLinesNegative(got: Int)
  NameContainsForbiddenBytes(field: NameField, value: String)
}

/// Which name field rejected the input.
pub type NameField {
  OldName
  NewName
}

/// Validated options for [`to_unified`](#to_unified).
///
/// Construct via [`unified_options`](#unified_options); override fields
/// through [`with_context_lines`](#with_context_lines). Read fields via
/// the [`old_name`](#old_name) / [`new_name`](#new_name) /
/// [`context_lines`](#context_lines) accessors.
pub opaque type UnifiedOptions {
  UnifiedOptions(old_name: String, new_name: String, context_lines: Int)
}

/// Default constructor: `context_lines = 3`, matching POSIX
/// `diff -u3`. Silently strips bytes that would corrupt the
/// `--- <old_name>` / `+++ <new_name>` header (`\n`, `\r`,
/// `\u{0000}`, `\t`) — see [`unified_options_checked`](#unified_options_checked)
/// for the strict variant that surfaces those bytes as a typed error.
pub fn unified_options(
  old_name old_name: String,
  new_name new_name: String,
) -> UnifiedOptions {
  UnifiedOptions(
    old_name: sanitize_name(old_name),
    new_name: sanitize_name(new_name),
    context_lines: 3,
  )
}

/// Strict counterpart of [`unified_options`](#unified_options).
/// Returns `Error(NameContainsForbiddenBytes(field, value))` when
/// either `old_name` or `new_name` contains `\n`, `\r`, `\u{0000}`,
/// or `\t`. The non-strict variant silently strips those bytes;
/// callers passing user-supplied paths should reach for this builder
/// so the bad input surfaces at the call site instead of producing a
/// label that disagrees with what was passed in.
pub fn unified_options_checked(
  old_name old_name: String,
  new_name new_name: String,
) -> Result(UnifiedOptions, UnifiedOptionsError) {
  use _ <- result.try(validate_name(OldName, old_name))
  use _ <- result.try(validate_name(NewName, new_name))
  Ok(UnifiedOptions(old_name: old_name, new_name: new_name, context_lines: 3))
}

/// Override the context-line count. Returns
/// `Error(ContextLinesNegative(n))` when `n < 0`.
pub fn with_context_lines(
  options: UnifiedOptions,
  n: Int,
) -> Result(UnifiedOptions, UnifiedOptionsError) {
  case n < 0 {
    True -> Error(ContextLinesNegative(n))
    False ->
      Ok(UnifiedOptions(
        old_name: options.old_name,
        new_name: options.new_name,
        context_lines: n,
      ))
  }
}

/// Override the old-file label. Silently strips `\n` / `\r` /
/// `\u{0000}` / `\t` — see [`with_old_name_checked`](#with_old_name_checked)
/// for the strict variant.
pub fn with_old_name(options: UnifiedOptions, name: String) -> UnifiedOptions {
  UnifiedOptions(
    old_name: sanitize_name(name),
    new_name: options.new_name,
    context_lines: options.context_lines,
  )
}

/// Strict counterpart of [`with_old_name`](#with_old_name). Returns
/// `Error(NameContainsForbiddenBytes(OldName, value))` when `name`
/// contains `\n`, `\r`, `\u{0000}`, or `\t`.
pub fn with_old_name_checked(
  options: UnifiedOptions,
  name: String,
) -> Result(UnifiedOptions, UnifiedOptionsError) {
  use _ <- result.try(validate_name(OldName, name))
  Ok(UnifiedOptions(
    old_name: name,
    new_name: options.new_name,
    context_lines: options.context_lines,
  ))
}

/// Override the new-file label. Silently strips `\n` / `\r` /
/// `\u{0000}` / `\t` — see [`with_new_name_checked`](#with_new_name_checked)
/// for the strict variant.
pub fn with_new_name(options: UnifiedOptions, name: String) -> UnifiedOptions {
  UnifiedOptions(
    old_name: options.old_name,
    new_name: sanitize_name(name),
    context_lines: options.context_lines,
  )
}

/// Strict counterpart of [`with_new_name`](#with_new_name). Returns
/// `Error(NameContainsForbiddenBytes(NewName, value))` when `name`
/// contains `\n`, `\r`, `\u{0000}`, or `\t`.
pub fn with_new_name_checked(
  options: UnifiedOptions,
  name: String,
) -> Result(UnifiedOptions, UnifiedOptionsError) {
  use _ <- result.try(validate_name(NewName, name))
  Ok(UnifiedOptions(
    old_name: options.old_name,
    new_name: name,
    context_lines: options.context_lines,
  ))
}

// The unified-diff header — `--- <old_name>\n+++ <new_name>\n` — is
// line-oriented and tab-delimited from the optional trailing date,
// so embedded `\n` / `\r` break the header into multiple physical
// lines that downstream `patch(1)` / `git apply` reject. NUL bytes
// truncate the line for any POSIX C string consumer. Tabs are
// folded into the same set because `diff -u` uses them to separate
// the filename from the date stamp.
fn sanitize_name(name: String) -> String {
  string.to_graphemes(name)
  |> list.filter(fn(g) {
    case g {
      "\n" -> False
      "\r" -> False
      "\u{0000}" -> False
      "\t" -> False
      _ -> True
    }
  })
  |> string.concat
}

fn validate_name(
  field: NameField,
  name: String,
) -> Result(Nil, UnifiedOptionsError) {
  case
    string.contains(name, "\n")
    || string.contains(name, "\r")
    || string.contains(name, "\u{0000}")
    || string.contains(name, "\t")
  {
    True -> Error(NameContainsForbiddenBytes(field, name))
    False -> Ok(Nil)
  }
}

/// Read the old-file label.
pub fn old_name(options: UnifiedOptions) -> String {
  options.old_name
}

/// Read the new-file label.
pub fn new_name(options: UnifiedOptions) -> String {
  options.new_name
}

/// Read the context-line count.
pub fn context_lines(options: UnifiedOptions) -> Int {
  options.context_lines
}

/// Optimal edit script transforming `old` into `new`, computed by the
/// Myers (1986) O(ND) algorithm.
///
/// The script's `cost` (Insert + Delete) equals `levenshtein_list`
/// of `old` vs `new` with substitution counted as one insert plus
/// one delete. Tie-breaking prefers earlier deletions over insertions,
/// matching GNU `diff(1)`.
pub fn myers(old: List(a), new: List(a)) -> EditScript(a) {
  let m = list.length(old)
  let n = list.length(new)
  case m, n {
    0, 0 -> []
    0, _ -> list.map(new, fn(item) { Insert(item) })
    _, 0 -> list.map(old, fn(item) { Delete(item) })
    _, _ -> {
      let old_arr = list_to_dict(old)
      let new_arr = list_to_dict(new)
      let initial_v = dict.insert(dict.new(), 1, 0)
      let max_d = m + n
      let MyersResult(trace, fx, fy) =
        myers_search(old_arr, new_arr, m, n, max_d, 0, initial_v, [])
      let trace_count = list.length(trace)
      myers_backtrack(old_arr, new_arr, trace, trace_count - 1, fx, fy, [])
    }
  }
}

type MyersResult(a) {
  MyersResult(trace: List(Dict(Int, Int)), final_x: Int, final_y: Int)
}

fn myers_search(
  old_arr: Dict(Int, a),
  new_arr: Dict(Int, a),
  m: Int,
  n: Int,
  max_d: Int,
  d: Int,
  v: Dict(Int, Int),
  trace_acc: List(Dict(Int, Int)),
) -> MyersResult(a) {
  let trace_acc_2 = [v, ..trace_acc]
  case d > max_d {
    True -> MyersResult(trace_acc_2, m, n)
    False ->
      case myers_d_step(old_arr, new_arr, m, n, d, -d, v) {
        Ok(#(_, fx, fy)) -> MyersResult(trace_acc_2, fx, fy)
        Error(updated_v) ->
          myers_search(
            old_arr,
            new_arr,
            m,
            n,
            max_d,
            d + 1,
            updated_v,
            trace_acc_2,
          )
      }
  }
}

fn myers_d_step(
  old_arr: Dict(Int, a),
  new_arr: Dict(Int, a),
  m: Int,
  n: Int,
  d: Int,
  k: Int,
  v: Dict(Int, Int),
) -> Result(#(Dict(Int, Int), Int, Int), Dict(Int, Int)) {
  case k > d {
    True -> Error(v)
    False -> {
      let v_minus = result.unwrap(dict.get(v, k - 1), -1)
      let v_plus = result.unwrap(dict.get(v, k + 1), -1)
      let from_above = k == -d || { k != d && v_minus < v_plus }
      let x = case from_above {
        True -> v_plus
        False -> v_minus + 1
      }
      let y = x - k
      let #(fx, fy) = follow_snake(old_arr, new_arr, m, n, x, y)
      let new_v = dict.insert(v, k, fx)
      case fx >= m && fy >= n {
        True -> Ok(#(new_v, fx, fy))
        False -> myers_d_step(old_arr, new_arr, m, n, d, k + 2, new_v)
      }
    }
  }
}

fn follow_snake(
  old_arr: Dict(Int, a),
  new_arr: Dict(Int, a),
  m: Int,
  n: Int,
  x: Int,
  y: Int,
) -> #(Int, Int) {
  case x < m && y < n {
    False -> #(x, y)
    True ->
      case dict.get(old_arr, x), dict.get(new_arr, y) {
        Ok(ax), Ok(by) ->
          case ax == by {
            True -> follow_snake(old_arr, new_arr, m, n, x + 1, y + 1)
            False -> #(x, y)
          }
        _, _ -> #(x, y)
      }
  }
}

fn myers_backtrack(
  old_arr: Dict(Int, a),
  new_arr: Dict(Int, a),
  trace: List(Dict(Int, Int)),
  d: Int,
  x: Int,
  y: Int,
  acc: EditScript(a),
) -> EditScript(a) {
  case d {
    0 -> walk_origin_back(old_arr, x, y, acc)
    _ ->
      case trace {
        [v, ..rest] -> {
          let k = x - y
          let v_minus = result.unwrap(dict.get(v, k - 1), -1)
          let v_plus = result.unwrap(dict.get(v, k + 1), -1)
          let from_above = k == -d || { k != d && v_minus < v_plus }
          let prev_k = case from_above {
            True -> k + 1
            False -> k - 1
          }
          let prev_x = result.unwrap(dict.get(v, prev_k), 0)
          let prev_y = prev_x - prev_k
          let #(x2, y2, acc2) =
            walk_diag_back(old_arr, x, y, prev_x, prev_y, acc)
          let #(next_x, next_y, acc3) = case x2 > prev_x, y2 > prev_y {
            True, _ ->
              case dict.get(old_arr, x2 - 1) {
                Ok(item) -> #(x2 - 1, y2, [Delete(item), ..acc2])
                Error(_) -> #(prev_x, prev_y, acc2)
              }
            False, True ->
              case dict.get(new_arr, y2 - 1) {
                Ok(item) -> #(x2, y2 - 1, [Insert(item), ..acc2])
                Error(_) -> #(prev_x, prev_y, acc2)
              }
            False, False -> #(prev_x, prev_y, acc2)
          }
          myers_backtrack(old_arr, new_arr, rest, d - 1, next_x, next_y, acc3)
        }
        [] -> walk_origin_back(old_arr, x, y, acc)
      }
  }
}

fn walk_diag_back(
  old_arr: Dict(Int, a),
  x: Int,
  y: Int,
  lo_x: Int,
  lo_y: Int,
  acc: EditScript(a),
) -> #(Int, Int, EditScript(a)) {
  case x > lo_x && y > lo_y {
    False -> #(x, y, acc)
    True ->
      case dict.get(old_arr, x - 1) {
        Ok(item) ->
          walk_diag_back(old_arr, x - 1, y - 1, lo_x, lo_y, [Equal(item), ..acc])
        Error(_) -> #(x, y, acc)
      }
  }
}

fn walk_origin_back(
  old_arr: Dict(Int, a),
  x: Int,
  y: Int,
  acc: EditScript(a),
) -> EditScript(a) {
  case x > 0 && y > 0 {
    False -> acc
    True ->
      case dict.get(old_arr, x - 1) {
        Ok(item) ->
          walk_origin_back(old_arr, x - 1, y - 1, [Equal(item), ..acc])
        Error(_) -> acc
      }
  }
}

/// Patience diff (Bram Cohen). Identifies anchor lines that are unique
/// in both inputs, computes the longest increasing subsequence of
/// those anchors, and recursively diffs the surrounding segments.
/// Falls back to [`myers`](#myers) at leaves where no unique anchors
/// exist. Operates on `List(String)`.
pub fn patience(old: List(String), new: List(String)) -> EditScript(String) {
  case old, new {
    [], [] -> []
    [], _ -> list.map(new, fn(item) { Insert(item) })
    _, [] -> list.map(old, fn(item) { Delete(item) })
    _, _ -> {
      let pairs = find_unique_pairs(old, new)
      case pairs {
        [] -> myers(old, new)
        _ -> {
          let anchors = longest_increasing_subseq(pairs)
          case anchors {
            [] -> myers(old, new)
            _ -> patience_segments(old, new, anchors, [])
          }
        }
      }
    }
  }
}

fn patience_segments(
  old: List(String),
  new: List(String),
  anchors: List(#(Int, Int)),
  acc: List(EditScript(String)),
) -> EditScript(String) {
  case anchors {
    [] -> {
      let sub = case old, new {
        [], [] -> []
        _, _ -> patience(old, new)
      }
      list.flatten(list.reverse([sub, ..acc]))
    }
    [#(oi, ni), ..rest] -> {
      let #(seg_old, anchor_and_after_old) = list.split(old, oi)
      let #(seg_new, anchor_and_after_new) = list.split(new, ni)
      let sub = patience(seg_old, seg_new)
      case anchor_and_after_old, anchor_and_after_new {
        [anchor_old, ..rest_old], [_, ..rest_new] -> {
          let anchor_step = [Equal(anchor_old)]
          let new_anchors =
            list.map(rest, fn(p) {
              let #(o, n) = p
              #(o - oi - 1, n - ni - 1)
            })
          patience_segments(rest_old, rest_new, new_anchors, [
            anchor_step,
            sub,
            ..acc
          ])
        }
        _, _ -> list.flatten(list.reverse([sub, ..acc]))
      }
    }
  }
}

fn find_unique_pairs(old: List(String), new: List(String)) -> List(#(Int, Int)) {
  let old_counts = count_occurrences(old)
  let new_counts = count_occurrences(new)
  let new_index_of = first_index_of(new)
  list.index_fold(old, [], fn(acc, line, oi) {
    case
      dict.get(old_counts, line),
      dict.get(new_counts, line),
      dict.get(new_index_of, line)
    {
      Ok(1), Ok(1), Ok(ni) -> [#(oi, ni), ..acc]
      _, _, _ -> acc
    }
  })
  |> list.reverse
}

fn count_occurrences(lines: List(String)) -> Dict(String, Int) {
  list.fold(lines, dict.new(), fn(acc, line) {
    dict.upsert(acc, line, fn(opt) {
      case opt {
        Some(c) -> c + 1
        None -> 1
      }
    })
  })
}

fn first_index_of(lines: List(String)) -> Dict(String, Int) {
  list.index_fold(lines, dict.new(), fn(acc, line, i) {
    case dict.has_key(acc, line) {
      True -> acc
      False -> dict.insert(acc, line, i)
    }
  })
}

fn longest_increasing_subseq(pairs: List(#(Int, Int))) -> List(#(Int, Int)) {
  let n = list.length(pairs)
  case n {
    0 -> []
    _ -> {
      let arr = list_to_dict(pairs)
      let #(dp, prev) = build_lis_tables(arr, n, 0, dict.new(), dict.new())
      let best_idx = find_max_dp(dp, n, 0, 0, 0)
      reconstruct_lis(arr, prev, best_idx, [])
    }
  }
}

fn build_lis_tables(
  arr: Dict(Int, #(Int, Int)),
  n: Int,
  i: Int,
  dp: Dict(Int, Int),
  prev: Dict(Int, Int),
) -> #(Dict(Int, Int), Dict(Int, Int)) {
  case i >= n {
    True -> #(dp, prev)
    False -> {
      let #(best_len, best_prev) = scan_predecessors(arr, dp, i, 0, 1, -1)
      let dp2 = dict.insert(dp, i, best_len)
      let prev2 = dict.insert(prev, i, best_prev)
      build_lis_tables(arr, n, i + 1, dp2, prev2)
    }
  }
}

fn scan_predecessors(
  arr: Dict(Int, #(Int, Int)),
  dp: Dict(Int, Int),
  i: Int,
  j: Int,
  best_len: Int,
  best_prev: Int,
) -> #(Int, Int) {
  case j >= i {
    True -> #(best_len, best_prev)
    False -> {
      let pi = case dict.get(arr, i) {
        Ok(p) -> p
        _ -> #(0, 0)
      }
      let pj = case dict.get(arr, j) {
        Ok(p) -> p
        _ -> #(0, 0)
      }
      let #(_, ni) = pi
      let #(_, nj) = pj
      let dp_j = result.unwrap(dict.get(dp, j), 0)
      let candidate = dp_j + 1
      case nj < ni && candidate > best_len {
        True -> scan_predecessors(arr, dp, i, j + 1, candidate, j)
        False -> scan_predecessors(arr, dp, i, j + 1, best_len, best_prev)
      }
    }
  }
}

fn find_max_dp(
  dp: Dict(Int, Int),
  n: Int,
  i: Int,
  best_len: Int,
  best_idx: Int,
) -> Int {
  case i >= n {
    True -> best_idx
    False -> {
      let v = result.unwrap(dict.get(dp, i), 0)
      case v > best_len {
        True -> find_max_dp(dp, n, i + 1, v, i)
        False -> find_max_dp(dp, n, i + 1, best_len, best_idx)
      }
    }
  }
}

fn reconstruct_lis(
  arr: Dict(Int, #(Int, Int)),
  prev: Dict(Int, Int),
  idx: Int,
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case idx < 0 {
    True -> acc
    False -> {
      let pair = case dict.get(arr, idx) {
        Ok(p) -> p
        _ -> #(0, 0)
      }
      let prev_idx = result.unwrap(dict.get(prev, idx), -1)
      reconstruct_lis(arr, prev, prev_idx, [pair, ..acc])
    }
  }
}

/// Render an edit script of strings in POSIX unified-diff format.
///
/// When the script contains no `Insert` or `Delete` steps the output
/// is exactly the empty string.
pub fn to_unified(script: EditScript(String), options: UnifiedOptions) -> String {
  case has_changes(script) {
    False -> ""
    True -> {
      let header =
        "--- " <> options.old_name <> "\n+++ " <> options.new_name <> "\n"
      let events = script_to_events(script, 1, 1, [])
      let hunks = build_hunks(events, options.context_lines)
      let body = list.map(hunks, emit_hunk) |> string.concat
      header <> body
    }
  }
}

fn has_changes(script: EditScript(String)) -> Bool {
  case script {
    [] -> False
    [Equal(_), ..rest] -> has_changes(rest)
    _ -> True
  }
}

type LineEvent {
  ContextEvent(line: String, old_pos: Int, new_pos: Int)
  DeleteEvent(line: String, old_pos: Int, new_pos: Int)
  InsertEvent(line: String, old_pos: Int, new_pos: Int)
}

fn script_to_events(
  script: EditScript(String),
  old_pos: Int,
  new_pos: Int,
  acc: List(LineEvent),
) -> List(LineEvent) {
  case script {
    [] -> list.reverse(acc)
    [Equal(line), ..rest] ->
      script_to_events(rest, old_pos + 1, new_pos + 1, [
        ContextEvent(line, old_pos, new_pos),
        ..acc
      ])
    [Delete(line), ..rest] ->
      script_to_events(rest, old_pos + 1, new_pos, [
        DeleteEvent(line, old_pos, new_pos),
        ..acc
      ])
    [Insert(line), ..rest] ->
      script_to_events(rest, old_pos, new_pos + 1, [
        InsertEvent(line, old_pos, new_pos),
        ..acc
      ])
  }
}

fn build_hunks(
  events: List(LineEvent),
  context_lines: Int,
) -> List(List(LineEvent)) {
  let events_arr = list_to_dict(events)
  let n = list.length(events)
  let change_indices = find_change_indices(events_arr, n, 0, []) |> list.reverse
  case change_indices {
    [] -> []
    _ -> {
      let ranges =
        list.map(change_indices, fn(i) {
          #(int.max(0, i - context_lines), int.min(n - 1, i + context_lines))
        })
      let merged = merge_ranges(ranges)
      list.map(merged, fn(range) {
        let #(lo, hi) = range
        slice_events(events_arr, lo, hi + 1, [])
      })
    }
  }
}

fn find_change_indices(
  events_arr: Dict(Int, LineEvent),
  n: Int,
  i: Int,
  acc: List(Int),
) -> List(Int) {
  case i >= n {
    True -> acc
    False -> {
      let new_acc = case dict.get(events_arr, i) {
        Ok(InsertEvent(_, _, _)) -> [i, ..acc]
        Ok(DeleteEvent(_, _, _)) -> [i, ..acc]
        _ -> acc
      }
      find_change_indices(events_arr, n, i + 1, new_acc)
    }
  }
}

fn merge_ranges(ranges: List(#(Int, Int))) -> List(#(Int, Int)) {
  case ranges {
    [] -> []
    [first, ..rest] -> merge_ranges_loop(rest, first, [])
  }
}

fn merge_ranges_loop(
  remaining: List(#(Int, Int)),
  current: #(Int, Int),
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case remaining {
    [] -> list.reverse([current, ..acc])
    [#(lo, hi), ..rest] -> {
      let #(c_lo, c_hi) = current
      case lo <= c_hi + 1 {
        True -> merge_ranges_loop(rest, #(c_lo, int.max(c_hi, hi)), acc)
        False -> merge_ranges_loop(rest, #(lo, hi), [current, ..acc])
      }
    }
  }
}

fn slice_events(
  events_arr: Dict(Int, LineEvent),
  i: Int,
  end: Int,
  acc: List(LineEvent),
) -> List(LineEvent) {
  case i >= end {
    True -> list.reverse(acc)
    False ->
      case dict.get(events_arr, i) {
        Ok(e) -> slice_events(events_arr, i + 1, end, [e, ..acc])
        Error(_) -> list.reverse(acc)
      }
  }
}

fn emit_hunk(events: List(LineEvent)) -> String {
  let #(os, oc, ns, nc) = compute_hunk_meta(events)
  let header =
    "@@ -" <> format_range(os, oc) <> " +" <> format_range(ns, nc) <> " @@\n"
  let body = list.map(events, event_to_line) |> string.concat
  header <> body
}

fn format_range(start: Int, count: Int) -> String {
  case count {
    1 -> int.to_string(start)
    _ -> int.to_string(start) <> "," <> int.to_string(count)
  }
}

fn compute_hunk_meta(events: List(LineEvent)) -> #(Int, Int, Int, Int) {
  let #(os, oc) = old_start_count(events)
  let #(ns, nc) = new_start_count(events)
  #(os, oc, ns, nc)
}

fn old_start_count(events: List(LineEvent)) -> #(Int, Int) {
  let folded =
    list.fold(events, #(-1, 0), fn(acc, e) {
      let #(start, count) = acc
      case e {
        ContextEvent(_, op, _) ->
          case start {
            -1 -> #(op, count + 1)
            _ -> #(start, count + 1)
          }
        DeleteEvent(_, op, _) ->
          case start {
            -1 -> #(op, count + 1)
            _ -> #(start, count + 1)
          }
        InsertEvent(_, _, _) -> acc
      }
    })
  let #(s, c) = folded
  case s {
    -1 ->
      case events {
        [InsertEvent(_, op, _), ..] -> #(int.max(0, op - 1), 0)
        _ -> #(0, 0)
      }
    _ -> #(s, c)
  }
}

fn new_start_count(events: List(LineEvent)) -> #(Int, Int) {
  let folded =
    list.fold(events, #(-1, 0), fn(acc, e) {
      let #(start, count) = acc
      case e {
        ContextEvent(_, _, np) ->
          case start {
            -1 -> #(np, count + 1)
            _ -> #(start, count + 1)
          }
        InsertEvent(_, _, np) ->
          case start {
            -1 -> #(np, count + 1)
            _ -> #(start, count + 1)
          }
        DeleteEvent(_, _, _) -> acc
      }
    })
  let #(s, c) = folded
  case s {
    -1 ->
      case events {
        [DeleteEvent(_, _, np), ..] -> #(int.max(0, np - 1), 0)
        _ -> #(0, 0)
      }
    _ -> #(s, c)
  }
}

fn event_to_line(e: LineEvent) -> String {
  case e {
    ContextEvent(line, _, _) -> " " <> line <> "\n"
    DeleteEvent(line, _, _) -> "-" <> line <> "\n"
    InsertEvent(line, _, _) -> "+" <> line <> "\n"
  }
}

fn list_to_dict(items: List(t)) -> Dict(Int, t) {
  list_to_dict_loop(items, 0, dict.new())
}

fn list_to_dict_loop(items: List(t), i: Int, acc: Dict(Int, t)) -> Dict(Int, t) {
  case items {
    [] -> acc
    [x, ..rest] -> list_to_dict_loop(rest, i + 1, dict.insert(acc, i, x))
  }
}
