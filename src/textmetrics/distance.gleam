//// Edit-distance functions.
////
//// All string-typed functions operate on **extended grapheme
//// clusters** as defined by Unicode UAX #29; user-visible characters
//// (CJK ideographs, emoji ZWJ sequences, Hangul jamo) count as one
//// unit. Inputs are pre-normalised to Unicode Normalization Form C
//// (NFC), so canonically-equivalent strings such as `"\u{00C1}"`
//// (precomposed) and `"A\u{0301}"` (decomposed) compare as equal.
////
//// `levenshtein_list/2` exposes the same algorithm over arbitrary
//// equality-comparable lists for callers diffing tokens, AST nodes,
//// or any non-string sequence. The list variant does not normalise
//// its inputs — equality is defined by the element type's own `==`.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result
import gleam/string
import textmetrics/internal/unicode

/// Returned by [`hamming`](#hamming) when its two inputs have a
/// different number of graphemes.
pub type HammingError {
  LengthMismatch(left: Int, right: Int)
}

/// Minimum number of single-grapheme insert / delete / substitute
/// operations needed to transform `a` into `b`.
///
/// Both inputs are pre-normalised to NFC, so canonically-equivalent
/// strings (`"\u{00C1}"` vs `"A\u{0301}"`) compare as equal.
///
/// Edge cases:
/// - `levenshtein("", "")` = `0`
/// - `levenshtein("", b)` = grapheme count of `b`
/// - `levenshtein(a, "")` = grapheme count of `a`
/// - `levenshtein(a, a)` = `0`
///
/// Time `O(m·n)`, space `O(min(m, n))`.
pub fn levenshtein(a: String, b: String) -> Int {
  levenshtein_list(nfc_graphemes(a), nfc_graphemes(b))
}

/// Levenshtein-based similarity in `[0.0, 1.0]`.
///
/// Defined as `1.0 - levenshtein(a, b) / max(|a|, |b|)` where lengths
/// are grapheme counts. `1.0` means identical, `0.0` means every
/// grapheme position differs at the longer length.
///
/// Both inputs are pre-normalised to NFC, so canonically-equivalent
/// strings score `1.0`.
///
/// Edge cases:
/// - `normalized_levenshtein("", "")` = `1.0` (convention).
/// - `normalized_levenshtein(a, a)` = `1.0`.
/// - `normalized_levenshtein("", non_empty)` = `0.0`.
///
/// Use this when ranking by Levenshtein-style edit distance is
/// preferred over Jaro / Jaro-Winkler. Time `O(m·n)`, space
/// `O(min(m, n))` — same as [`levenshtein`](#levenshtein).
pub fn normalized_levenshtein(a: String, b: String) -> Float {
  let a_graphemes = nfc_graphemes(a)
  let b_graphemes = nfc_graphemes(b)
  case int.max(list.length(a_graphemes), list.length(b_graphemes)) {
    0 -> 1.0
    longest -> {
      let distance = levenshtein_list(a_graphemes, b_graphemes)
      1.0 -. int.to_float(distance) /. int.to_float(longest)
    }
  }
}

/// Generic Levenshtein distance over any equality-comparable list
/// type. Used by `diff` internally and exposed for callers diffing
/// token streams or AST nodes.
pub fn levenshtein_list(a: List(t), b: List(t)) -> Int {
  let m = list.length(a)
  let n = list.length(b)
  case m, n {
    0, _ -> n
    _, 0 -> m
    // The distance is symmetric; the shorter list sets the row length.
    _, _ if m < n -> levenshtein_outer(b, a, int_range_inclusive(0, m), 1)
    _, _ -> levenshtein_outer(a, b, int_range_inclusive(0, n), 1)
  }
}

fn levenshtein_outer(
  remaining_a: List(t),
  bs: List(t),
  prev: List(Int),
  i: Int,
) -> Int {
  case remaining_a {
    [] -> last_or_zero(prev)
    [ai, ..rest] -> {
      let curr = case prev {
        [p0, ..p_rest] -> levenshtein_inner(ai, bs, p0, p_rest, i, [i])
        [] -> [i]
      }
      levenshtein_outer(rest, bs, curr, i + 1)
    }
  }
}

fn levenshtein_inner(
  ai: t,
  bs: List(t),
  prev_diag: Int,
  prev_rest: List(Int),
  curr_left: Int,
  acc: List(Int),
) -> List(Int) {
  case bs, prev_rest {
    [], _ -> list.reverse(acc)
    _, [] -> list.reverse(acc)
    [bj, ..bs_rest], [prev_above, ..prev_more] -> {
      let sub_cost = case ai == bj {
        True -> 0
        False -> 1
      }
      let curr_j = min3(prev_above + 1, curr_left + 1, prev_diag + sub_cost)
      levenshtein_inner(ai, bs_rest, prev_above, prev_more, curr_j, [
        curr_j,
        ..acc
      ])
    }
  }
}

/// True Damerau-Levenshtein distance: insert, delete, substitute, and
/// transposition of two adjacent graphemes are each counted as one
/// operation. Unlike OSA, the same substring may participate in
/// multiple edits (e.g. `"ca"` → `"abc"` is `2`).
///
/// Both inputs are pre-normalised to NFC, so canonically-equivalent
/// strings have distance `0`.
///
/// Time `O(m·n)`, space `O(k·n)` for `k` distinct graphemes in `a`
/// and `n = length(b)`.
pub fn damerau_levenshtein(a: String, b: String) -> Int {
  damerau_levenshtein_graphemes(nfc_graphemes(a), nfc_graphemes(b))
}

// Lowrance-Wagner. Row `i` of the table needs, besides row `i - 1`, the
// row before the last occurrence of `b[j]` in `a`; only those rows are
// kept, one per distinct grapheme of `a`, indexed for random access.
fn damerau_levenshtein_graphemes(a: List(String), b: List(String)) -> Int {
  case a, b {
    [], _ -> list.length(b)
    _, [] -> list.length(a)
    _, _ ->
      damerau_levenshtein_rows(
        a,
        b,
        1,
        int_range_inclusive(0, list.length(b)),
        dict.new(),
      )
  }
}

fn damerau_levenshtein_rows(
  remaining_a: List(t),
  b: List(t),
  i: Int,
  previous: List(Int),
  rows_before_last: Dict(t, #(Int, Dict(Int, Int))),
) -> Int {
  case remaining_a, previous {
    [], _ -> last_or_zero(previous)
    [item, ..rest], [previous_first, ..previous_rest] -> {
      let row =
        damerau_levenshtein_row(
          DamerauRow(item:, i:, rows_before_last:, j: 1, last_match_column: 0),
          b,
          previous_first,
          previous_rest,
          i,
          [i],
        )
      let indexed_previous =
        previous
        |> list.index_map(fn(value, column) { #(column, value) })
        |> dict.from_list
      damerau_levenshtein_rows(
        rest,
        b,
        i + 1,
        row,
        dict.insert(rows_before_last, item, #(i, indexed_previous)),
      )
    }
    [_, ..], [] -> 0
  }
}

type DamerauRow(t) {
  DamerauRow(
    item: t,
    i: Int,
    rows_before_last: Dict(t, #(Int, Dict(Int, Int))),
    j: Int,
    // The last column `j' < j` of this row where `b[j'] == item`, or 0.
    last_match_column: Int,
  )
}

fn damerau_levenshtein_row(
  state: DamerauRow(t),
  b: List(t),
  previous_diagonal: Int,
  previous_rest: List(Int),
  left: Int,
  acc: List(Int),
) -> List(Int) {
  case b, previous_rest {
    [item_b, ..b_rest], [above, ..previous_more] -> {
      let DamerauRow(item:, i:, rows_before_last:, j:, last_match_column:) =
        state
      let cost = case item == item_b {
        True -> 0
        False -> 1
      }
      let best = min3(previous_diagonal + cost, left + 1, above + 1)
      // Transposition through the last `item_b` in `a` (row `k`) and the
      // last `item` in `b` (column `last_match_column`).
      let best = case dict.get(rows_before_last, item_b), last_match_column {
        Ok(#(k, row_before_k)), l if l > 0 ->
          case dict.get(row_before_k, l - 1) {
            Ok(value) ->
              int.min(best, value + { i - k - 1 } + 1 + { j - l - 1 })
            Error(Nil) -> best
          }
        _, _ -> best
      }
      let last_match_column = case cost {
        0 -> j
        _ -> last_match_column
      }
      damerau_levenshtein_row(
        DamerauRow(..state, j: j + 1, last_match_column:),
        b_rest,
        above,
        previous_more,
        best,
        [best, ..acc],
      )
    }
    _, _ -> list.reverse(acc)
  }
}

/// Optimal String Alignment distance. Same operations as
/// Damerau-Levenshtein but each substring is edited at most once,
/// which is what most "Damerau distance" implementations actually
/// compute.
///
/// Both inputs are pre-normalised to NFC, so canonically-equivalent
/// strings have distance `0`.
///
/// OSA does **not** satisfy the triangle inequality. Use
/// [`damerau_levenshtein`](#damerau_levenshtein) when a true metric is
/// required.
///
/// Time `O(m·n)`, space `O(min(m, n))` (three rows).
pub fn osa(a: String, b: String) -> Int {
  osa_graphemes(nfc_graphemes(a), nfc_graphemes(b))
}

fn osa_graphemes(a: List(String), b: List(String)) -> Int {
  let m = list.length(a)
  let n = list.length(b)
  case m, n {
    0, _ -> n
    _, 0 -> m
    // OSA is symmetric; the shorter list sets the row length.
    _, _ if m < n -> osa_rows(b, a, Error(Nil), int_range_inclusive(0, m), [])
    _, _ -> osa_rows(a, b, Error(Nil), int_range_inclusive(0, n), [])
  }
}

// `previous` and `before_previous` are rows `i - 1` and `i - 2` of the
// table; `previous_a` is `a[i - 1]`.
fn osa_rows(
  remaining_a: List(t),
  b: List(t),
  previous_a: Result(t, Nil),
  previous: List(Int),
  before_previous: List(Int),
) -> Int {
  case remaining_a, previous {
    [], _ -> last_or_zero(previous)
    [item, ..rest], [previous_first, ..previous_rest] -> {
      let i = previous_first + 1
      let row =
        osa_row(
          OsaRow(item:, previous_a:, previous_b: Error(Nil), j: 1),
          b,
          previous_first,
          previous_rest,
          before_previous,
          i,
          [i],
        )
      osa_rows(rest, b, Ok(item), row, previous)
    }
    [_, ..], [] -> 0
  }
}

type OsaRow(t) {
  OsaRow(
    item: t,
    previous_a: Result(t, Nil),
    previous_b: Result(t, Nil),
    j: Int,
  )
}

// `two_back` starts at column `j - 2` of row `i - 2` once `j >= 2`.
fn osa_row(
  state: OsaRow(t),
  b: List(t),
  previous_diagonal: Int,
  previous_rest: List(Int),
  two_back: List(Int),
  left: Int,
  acc: List(Int),
) -> List(Int) {
  case b, previous_rest {
    [item_b, ..b_rest], [above, ..previous_more] -> {
      let OsaRow(item:, previous_a:, previous_b:, j:) = state
      let cost = case item == item_b {
        True -> 0
        False -> 1
      }
      let best = min3(above + 1, left + 1, previous_diagonal + cost)
      let #(best, two_back) = case j >= 2, two_back {
        True, [diagonal_two_back, ..two_back_rest] -> {
          let best = case previous_a, previous_b {
            Ok(before_item), Ok(before_item_b)
              if item == before_item_b && before_item == item_b
            -> int.min(best, diagonal_two_back + 1)
            _, _ -> best
          }
          #(best, two_back_rest)
        }
        _, _ -> #(best, two_back)
      }
      osa_row(
        OsaRow(..state, previous_b: Ok(item_b), j: j + 1),
        b_rest,
        above,
        previous_more,
        two_back,
        best,
        [best, ..acc],
      )
    }
    _, _ -> list.reverse(acc)
  }
}

/// Hamming distance: the number of grapheme positions at which the
/// inputs differ. Returns `Error(LengthMismatch(...))` when the inputs
/// have different grapheme counts.
///
/// Both inputs are pre-normalised to NFC, so canonically-equivalent
/// strings have distance `0` (and equal grapheme counts after
/// normalisation, so no spurious `LengthMismatch`).
///
/// Edge cases:
/// - `hamming("", "")` = `Ok(0)`
/// - `hamming("a", "")` = `Error(LengthMismatch(1, 0))`
///
/// Time `O(n)`, space `O(1)`.
pub fn hamming(a: String, b: String) -> Result(Int, HammingError) {
  let a_graphemes = nfc_graphemes(a)
  let b_graphemes = nfc_graphemes(b)
  let a_length = list.length(a_graphemes)
  let b_length = list.length(b_graphemes)
  case a_length == b_length {
    False -> Error(LengthMismatch(a_length, b_length))
    True -> Ok(count_diffs(a_graphemes, b_graphemes, 0))
  }
}

fn count_diffs(a: List(String), b: List(String), acc: Int) -> Int {
  case a, b {
    [], [] -> acc
    [x, ..xs], [y, ..ys] ->
      case x == y {
        True -> count_diffs(xs, ys, acc)
        False -> count_diffs(xs, ys, acc + 1)
      }
    _, _ -> acc
  }
}

// ---------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------

fn nfc_graphemes(text: String) -> List(String) {
  string.to_graphemes(unicode.to_nfc(text))
}

fn last_or_zero(row: List(Int)) -> Int {
  result.unwrap(list.last(row), 0)
}

fn int_range_inclusive(start: Int, end: Int) -> List(Int) {
  int_range_inclusive_loop(start, end, [])
}

fn int_range_inclusive_loop(
  current: Int,
  end: Int,
  acc: List(Int),
) -> List(Int) {
  case current > end {
    True -> list.reverse(acc)
    False -> int_range_inclusive_loop(current + 1, end, [current, ..acc])
  }
}

fn min3(a: Int, b: Int, c: Int) -> Int {
  int.min(a, int.min(b, c))
}
