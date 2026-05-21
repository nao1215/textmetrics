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
  levenshtein_list(
    string.to_graphemes(unicode.to_nfc(a)),
    string.to_graphemes(unicode.to_nfc(b)),
  )
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
  let ga = string.to_graphemes(unicode.to_nfc(a))
  let gb = string.to_graphemes(unicode.to_nfc(b))
  let la = list.length(ga)
  let lb = list.length(gb)
  let max_len = case la >= lb {
    True -> la
    False -> lb
  }
  case max_len {
    0 -> 1.0
    _ -> {
      let d = levenshtein_list(ga, gb)
      1.0 -. int.to_float(d) /. int.to_float(max_len)
    }
  }
}

/// Generic Levenshtein distance over any equality-comparable list
/// type. Used by `diff` internally and exposed for callers diffing
/// token streams or AST nodes.
pub fn levenshtein_list(a: List(t), b: List(t)) -> Int {
  let n = list.length(b)
  case a {
    [] -> n
    _ ->
      case b {
        [] -> list.length(a)
        _ -> {
          let initial_prev = int_range_inclusive(0, n)
          levenshtein_outer(a, b, initial_prev, 1)
        }
      }
  }
}

fn levenshtein_outer(
  remaining_a: List(t),
  bs: List(t),
  prev: List(Int),
  i: Int,
) -> Int {
  case remaining_a {
    [] ->
      case list.last(prev) {
        Ok(v) -> v
        Error(_) -> 0
      }
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
/// Time `O(m·n)`, space `O(m·n)` (full matrix is required for the
/// transposition recurrence).
pub fn damerau_levenshtein(a: String, b: String) -> Int {
  damerau_levenshtein_graphemes(
    string.to_graphemes(unicode.to_nfc(a)),
    string.to_graphemes(unicode.to_nfc(b)),
  )
}

fn damerau_levenshtein_graphemes(ga: List(String), gb: List(String)) -> Int {
  let m = list.length(ga)
  let n = list.length(gb)
  case m, n {
    0, _ -> n
    _, 0 -> m
    _, _ -> {
      let a_dict = list_to_dict(ga)
      let b_dict = list_to_dict(gb)
      let inf = m + n
      let initial = init_dl_matrix(m, n, inf)
      let final_d = dl_outer(a_dict, b_dict, m, n, 1, dict.new(), initial)
      result.unwrap(dict.get(final_d, #(m + 1, n + 1)), 0)
    }
  }
}

fn init_dl_matrix(m: Int, n: Int, inf: Int) -> Dict(#(Int, Int), Int) {
  dict.new()
  |> dict.insert(#(0, 0), inf)
  |> init_dl_rows(m, inf, 0)
  |> init_dl_cols(n, inf, 0)
}

fn init_dl_rows(
  d: Dict(#(Int, Int), Int),
  m: Int,
  inf: Int,
  i: Int,
) -> Dict(#(Int, Int), Int) {
  case i > m {
    True -> d
    False -> {
      d
      |> dict.insert(#(i + 1, 0), inf)
      |> dict.insert(#(i + 1, 1), i)
      |> init_dl_rows(m, inf, i + 1)
    }
  }
}

fn init_dl_cols(
  d: Dict(#(Int, Int), Int),
  n: Int,
  inf: Int,
  j: Int,
) -> Dict(#(Int, Int), Int) {
  case j > n {
    True -> d
    False -> {
      d
      |> dict.insert(#(0, j + 1), inf)
      |> dict.insert(#(1, j + 1), j)
      |> init_dl_cols(n, inf, j + 1)
    }
  }
}

fn dl_outer(
  a_dict: Dict(Int, String),
  b_dict: Dict(Int, String),
  m: Int,
  n: Int,
  i: Int,
  da: Dict(String, Int),
  d: Dict(#(Int, Int), Int),
) -> Dict(#(Int, Int), Int) {
  case i > m {
    True -> d
    False -> {
      let new_d = dl_inner(a_dict, b_dict, n, i, 1, 0, da, d)
      let ai = result.unwrap(dict.get(a_dict, i - 1), "")
      let new_da = dict.insert(da, ai, i)
      dl_outer(a_dict, b_dict, m, n, i + 1, new_da, new_d)
    }
  }
}

fn dl_inner(
  a_dict: Dict(Int, String),
  b_dict: Dict(Int, String),
  n: Int,
  i: Int,
  j: Int,
  db: Int,
  da: Dict(String, Int),
  d: Dict(#(Int, Int), Int),
) -> Dict(#(Int, Int), Int) {
  case j > n {
    True -> d
    False -> {
      let ai = result.unwrap(dict.get(a_dict, i - 1), "")
      let bj = result.unwrap(dict.get(b_dict, j - 1), "")
      let k = result.unwrap(dict.get(da, bj), 0)
      let l = db
      let #(cost, new_db) = case ai == bj {
        True -> #(0, j)
        False -> #(1, db)
      }
      let sub = result.unwrap(dict.get(d, #(i, j)), 0) + cost
      let ins = result.unwrap(dict.get(d, #(i + 1, j)), 0) + 1
      let del = result.unwrap(dict.get(d, #(i, j + 1)), 0) + 1
      let trans =
        result.unwrap(dict.get(d, #(k, l)), 0)
        + { i - k - 1 }
        + 1
        + { j - l - 1 }
      let val = min4(sub, ins, del, trans)
      let new_d = dict.insert(d, #(i + 1, j + 1), val)
      dl_inner(a_dict, b_dict, n, i, j + 1, new_db, da, new_d)
    }
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
  osa_graphemes(
    string.to_graphemes(unicode.to_nfc(a)),
    string.to_graphemes(unicode.to_nfc(b)),
  )
}

fn osa_graphemes(ga: List(String), gb: List(String)) -> Int {
  let m = list.length(ga)
  let n = list.length(gb)
  case m, n {
    0, _ -> n
    _, 0 -> m
    _, _ -> {
      let a_dict = list_to_dict(ga)
      let b_dict = list_to_dict(gb)
      let prev = make_init_row(n)
      let prev_prev = dict.new()
      osa_outer(a_dict, b_dict, m, n, 1, prev, prev_prev)
    }
  }
}

fn osa_outer(
  a_dict: Dict(Int, String),
  b_dict: Dict(Int, String),
  m: Int,
  n: Int,
  i: Int,
  prev: Dict(Int, Int),
  prev_prev: Dict(Int, Int),
) -> Int {
  case i > m {
    True -> result.unwrap(dict.get(prev, n), 0)
    False -> {
      let ai = result.unwrap(dict.get(a_dict, i - 1), "")
      let prev_a = case dict.get(a_dict, i - 2) {
        Ok(v) -> Ok(v)
        Error(_) -> Error(Nil)
      }
      let curr0 = dict.insert(dict.new(), 0, i)
      let curr = osa_inner(ai, prev_a, b_dict, n, prev, prev_prev, 1, curr0)
      osa_outer(a_dict, b_dict, m, n, i + 1, curr, prev)
    }
  }
}

fn osa_inner(
  ai: String,
  prev_a: Result(String, Nil),
  b_dict: Dict(Int, String),
  n: Int,
  prev: Dict(Int, Int),
  prev_prev: Dict(Int, Int),
  j: Int,
  curr: Dict(Int, Int),
) -> Dict(Int, Int) {
  case j > n {
    True -> curr
    False -> {
      let bj = result.unwrap(dict.get(b_dict, j - 1), "")
      let prev_above = result.unwrap(dict.get(prev, j), 0)
      let prev_diag = result.unwrap(dict.get(prev, j - 1), 0)
      let curr_left = result.unwrap(dict.get(curr, j - 1), 0)
      let sub_cost = case ai == bj {
        True -> 0
        False -> 1
      }
      let v0 = min3(prev_above + 1, curr_left + 1, prev_diag + sub_cost)
      let v1 = case j >= 2, prev_a {
        True, Ok(pa) -> {
          let prev_b = result.unwrap(dict.get(b_dict, j - 2), bj)
          case ai == prev_b && pa == bj {
            True -> {
              let pp = result.unwrap(dict.get(prev_prev, j - 2), 0)
              int.min(v0, pp + 1)
            }
            False -> v0
          }
        }
        _, _ -> v0
      }
      let new_curr = dict.insert(curr, j, v1)
      osa_inner(ai, prev_a, b_dict, n, prev, prev_prev, j + 1, new_curr)
    }
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
  let ga = string.to_graphemes(unicode.to_nfc(a))
  let gb = string.to_graphemes(unicode.to_nfc(b))
  let la = list.length(ga)
  let lb = list.length(gb)
  case la == lb {
    False -> Error(LengthMismatch(la, lb))
    True -> Ok(count_diffs(ga, gb, 0))
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

fn list_to_dict(items: List(t)) -> Dict(Int, t) {
  list_to_dict_loop(items, 0, dict.new())
}

fn list_to_dict_loop(items: List(t), i: Int, acc: Dict(Int, t)) -> Dict(Int, t) {
  case items {
    [] -> acc
    [x, ..rest] -> list_to_dict_loop(rest, i + 1, dict.insert(acc, i, x))
  }
}

fn make_init_row(n: Int) -> Dict(Int, Int) {
  int_range_inclusive(0, n)
  |> list.index_map(fn(v, i) { #(i, v) })
  |> dict.from_list
}

fn int_range_inclusive(start: Int, end: Int) -> List(Int) {
  int_range_inclusive_loop(start, end, [])
}

fn int_range_inclusive_loop(current: Int, end: Int, acc: List(Int)) -> List(Int) {
  case current > end {
    True -> list.reverse(acc)
    False -> int_range_inclusive_loop(current + 1, end, [current, ..acc])
  }
}

fn min3(a: Int, b: Int, c: Int) -> Int {
  int.min(a, int.min(b, c))
}

fn min4(a: Int, b: Int, c: Int, d: Int) -> Int {
  int.min(int.min(a, b), int.min(c, d))
}
