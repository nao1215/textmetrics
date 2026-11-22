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
// Filters by code point rather than grapheme: "\r\n" is a single
// grapheme cluster and would slip through a grapheme-wise filter.
fn sanitize_name(name: String) -> String {
  string.to_utf_codepoints(name)
  |> list.filter(fn(codepoint) {
    case string.utf_codepoint_to_int(codepoint) {
      0x0A | 0x0D | 0x00 | 0x09 -> False
      _ -> True
    }
  })
  |> string.from_utf_codepoints
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
  patience_loop([Segment(old:, new:)], [])
}

// Work still to do, in output order. Segments are expanded in place
// instead of recursing, so deeply nested inputs do not grow the stack.
type PatienceTask {
  Segment(old: List(String), new: List(String))
  Anchor(line: String)
}

fn patience_loop(
  tasks: List(PatienceTask),
  acc: List(EditScript(String)),
) -> EditScript(String) {
  case tasks {
    [] -> list.reverse(acc) |> list.flatten
    [Anchor(line:), ..rest] -> patience_loop(rest, [[Equal(line)], ..acc])
    [Segment(old: [], new: []), ..rest] -> patience_loop(rest, acc)
    [Segment(old: [], new:), ..rest] ->
      patience_loop(rest, [list.map(new, Insert), ..acc])
    [Segment(old:, new: []), ..rest] ->
      patience_loop(rest, [list.map(old, Delete), ..acc])
    [Segment(old:, new:), ..rest] ->
      case longest_increasing_subseq(find_unique_pairs(old, new)) {
        [] -> patience_loop(rest, [myers(old, new), ..acc])
        anchors ->
          split_at_anchors(old, new, anchors, 0, 0, [])
          |> list.fold(rest, fn(tasks, task) { [task, ..tasks] })
          |> patience_loop(acc)
      }
  }
}

// Splits `old` and `new` around the anchors, whose positions are
// absolute within the segment. Returns the tasks in reverse order.
fn split_at_anchors(
  old: List(String),
  new: List(String),
  anchors: List(#(Int, Int)),
  old_position: Int,
  new_position: Int,
  reversed_tasks: List(PatienceTask),
) -> List(PatienceTask) {
  case anchors {
    [] -> [Segment(old:, new:), ..reversed_tasks]
    [#(old_index, new_index), ..rest] -> {
      let #(old_before, old_after) = list.split(old, old_index - old_position)
      let #(new_before, new_after) = list.split(new, new_index - new_position)
      let reversed_tasks = [
        Segment(old: old_before, new: new_before),
        ..reversed_tasks
      ]
      case old_after, new_after {
        [line, ..old_rest], [_, ..new_rest] ->
          split_at_anchors(
            old_rest,
            new_rest,
            rest,
            old_index + 1,
            new_index + 1,
            [Anchor(line:), ..reversed_tasks],
          )
        _, _ -> reversed_tasks
      }
    }
  }
}

// Pairs `#(old_index, new_index)` of the lines that occur exactly once
// in each input, in increasing old-index order.
fn find_unique_pairs(
  old: List(String),
  new: List(String),
) -> List(#(Int, Int)) {
  let counts =
    list.index_fold(old, dict.new(), fn(counts, line, index) {
      dict.upsert(counts, line, fn(existing) {
        case existing {
          Some(count) -> LineCount(..count, in_old: count.in_old + 1)
          None ->
            LineCount(in_old: 1, old_index: index, in_new: 0, new_index: 0)
        }
      })
    })
  let counts =
    list.index_fold(new, counts, fn(counts, line, index) {
      case dict.get(counts, line) {
        Ok(count) ->
          dict.insert(
            counts,
            line,
            LineCount(..count, in_new: count.in_new + 1, new_index: index),
          )
        Error(Nil) -> counts
      }
    })
  dict.fold(counts, [], fn(pairs, _line, count) {
    case count {
      LineCount(in_old: 1, old_index:, in_new: 1, new_index:) -> [
        #(old_index, new_index),
        ..pairs
      ]
      LineCount(..) -> pairs
    }
  })
  |> list.sort(fn(left, right) { int.compare(left.0, right.0) })
}

type LineCount {
  LineCount(in_old: Int, old_index: Int, in_new: Int, new_index: Int)
}

// Longest increasing subsequence (by new index) of `pairs`, which are in
// increasing old-index order, via patience sorting: `O(k log² k)` for
// `k` pairs. Among equally long subsequences it picks the same one as a
// quadratic scan that takes, for each pair, the earliest predecessor
// of maximal length, and ends at the earliest pair of maximal length.
fn longest_increasing_subseq(pairs: List(#(Int, Int))) -> List(#(Int, Int)) {
  let #(dealt, pile_count) = deal_into_piles(pairs, dict.new(), 0, [])
  // Each pile lists its pairs in increasing old-index order; within a
  // pile the new indices decrease.
  let piles =
    list.fold(dealt, dict.new(), fn(piles, entry) {
      let #(pile, pair) = entry
      dict.upsert(piles, pile, fn(existing) {
        case existing {
          Some(pairs) -> [pair, ..pairs]
          None -> [pair]
        }
      })
    })
  case dict.get(piles, pile_count - 1) {
    Ok([last, ..]) -> collect_lis(piles, pile_count - 2, last, [last])
    Ok([]) | Error(Nil) -> []
  }
}

// Places each pair on the leftmost pile whose top has a larger new
// index, and returns `#(pile, pair)` for every pair in reverse order.
fn deal_into_piles(
  pairs: List(#(Int, Int)),
  tops: Dict(Int, Int),
  pile_count: Int,
  dealt: List(#(Int, #(Int, Int))),
) -> #(List(#(Int, #(Int, Int))), Int) {
  case pairs {
    [] -> #(dealt, pile_count)
    [pair, ..rest] -> {
      let #(_, new_index) = pair
      let pile = first_pile_above(tops, new_index, 0, pile_count)
      let pile_count = int.max(pile_count, pile + 1)
      deal_into_piles(rest, dict.insert(tops, pile, new_index), pile_count, [
        #(pile, pair),
        ..dealt
      ])
    }
  }
}

// Binary search over the pile tops, which increase from left to right.
fn first_pile_above(
  tops: Dict(Int, Int),
  value: Int,
  low: Int,
  high: Int,
) -> Int {
  case low >= high {
    True -> low
    False -> {
      let middle = { low + high } / 2
      case dict.get(tops, middle) {
        Ok(top) if top < value -> first_pile_above(tops, value, middle + 1, high)
        Ok(_) | Error(Nil) -> first_pile_above(tops, value, low, middle)
      }
    }
  }
}

// Walks back from the chosen last pair, taking from each earlier pile
// the earliest pair whose new index is smaller.
fn collect_lis(
  piles: Dict(Int, List(#(Int, Int))),
  pile: Int,
  next: #(Int, Int),
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case pile < 0 {
    True -> acc
    False -> {
      let #(_, next_new_index) = next
      let candidates = result.unwrap(dict.get(piles, pile), [])
      case list.find(candidates, fn(pair) { pair.1 < next_new_index }) {
        Ok(pair) -> collect_lis(piles, pile - 1, pair, [pair, ..acc])
        Error(Nil) -> acc
      }
    }
  }
}

/// Render an edit script of strings in POSIX unified-diff format.
///
/// When the script contains no `Insert` or `Delete` steps the output
/// is exactly the empty string.
pub fn to_unified(
  script: EditScript(String),
  options: UnifiedOptions,
) -> String {
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

fn list_to_dict_loop(
  items: List(t),
  i: Int,
  acc: Dict(Int, t),
) -> Dict(Int, t) {
  case items {
    [] -> acc
    [x, ..rest] -> list_to_dict_loop(rest, i + 1, dict.insert(acc, i, x))
  }
}
