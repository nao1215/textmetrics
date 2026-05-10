//// Longest Common Subsequence helpers.
////
//// Generic over any equality-comparable list type (`List(t)`); pre-split
//// strings via `gleam/string.to_graphemes` for grapheme-level results.
//// This module performs no Unicode normalization.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/result

/// Length of a longest common subsequence of `a` and `b`.
///
/// Time `O(m·n)`, space `O(m + n)`. Returns `0` when either input is
/// empty.
pub fn length(a: List(t), b: List(t)) -> Int {
  let n = list.length(b)
  case a, b {
    [], _ -> 0
    _, [] -> 0
    _, _ -> {
      let initial_prev = list.repeat(0, n + 1)
      lcs_length_outer(a, b, initial_prev)
    }
  }
}

fn lcs_length_outer(remaining_a: List(t), bs: List(t), prev: List(Int)) -> Int {
  case remaining_a {
    [] ->
      case list.last(prev) {
        Ok(v) -> v
        Error(_) -> 0
      }
    [ai, ..rest] -> {
      let curr = case prev {
        [_, ..p_rest] -> lcs_length_inner(ai, bs, 0, p_rest, 0, [0])
        [] -> [0]
      }
      lcs_length_outer(rest, bs, curr)
    }
  }
}

fn lcs_length_inner(
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
      let curr_j = case ai == bj {
        True -> prev_diag + 1
        False -> int.max(prev_above, curr_left)
      }
      lcs_length_inner(ai, bs_rest, prev_above, prev_more, curr_j, [
        curr_j,
        ..acc
      ])
    }
  }
}

/// One longest common subsequence of `a` and `b`.
///
/// When multiple equally-long subsequences exist, this implementation
/// returns the one preferring upward backtracking on ties — callers
/// should treat the choice as implementation-defined and only rely on
/// `length(sequence(a, b)) == length(a, b)`.
///
/// Time `O(m·n)`, space `O(m·n)` (full DP matrix retained for
/// backtracking).
pub fn sequence(a: List(t), b: List(t)) -> List(t) {
  let m = list.length(a)
  let n = list.length(b)
  case m == 0 || n == 0 {
    True -> []
    False -> {
      let a_arr = list_to_dict(a)
      let b_arr = list_to_dict(b)
      let matrix = build_lcs_matrix(a_arr, b_arr, m, n)
      backtrack(a_arr, b_arr, matrix, m, n, [])
    }
  }
}

fn build_lcs_matrix(
  a_arr: Dict(Int, t),
  b_arr: Dict(Int, t),
  m: Int,
  n: Int,
) -> Dict(#(Int, Int), Int) {
  build_lcs_loop(a_arr, b_arr, m, n, 1, dict.new())
}

fn build_lcs_loop(
  a_arr: Dict(Int, t),
  b_arr: Dict(Int, t),
  m: Int,
  n: Int,
  i: Int,
  d: Dict(#(Int, Int), Int),
) -> Dict(#(Int, Int), Int) {
  case i > m {
    True -> d
    False -> {
      let new_d = build_lcs_row(a_arr, b_arr, n, i, 1, d)
      build_lcs_loop(a_arr, b_arr, m, n, i + 1, new_d)
    }
  }
}

fn build_lcs_row(
  a_arr: Dict(Int, t),
  b_arr: Dict(Int, t),
  n: Int,
  i: Int,
  j: Int,
  d: Dict(#(Int, Int), Int),
) -> Dict(#(Int, Int), Int) {
  case j > n {
    True -> d
    False -> {
      let new_d = case dict.get(a_arr, i - 1), dict.get(b_arr, j - 1) {
        Ok(ai), Ok(bj) -> {
          let val = case ai == bj {
            True -> result.unwrap(dict.get(d, #(i - 1, j - 1)), 0) + 1
            False ->
              int.max(
                result.unwrap(dict.get(d, #(i - 1, j)), 0),
                result.unwrap(dict.get(d, #(i, j - 1)), 0),
              )
          }
          dict.insert(d, #(i, j), val)
        }
        _, _ -> d
      }
      build_lcs_row(a_arr, b_arr, n, i, j + 1, new_d)
    }
  }
}

fn backtrack(
  a_arr: Dict(Int, t),
  b_arr: Dict(Int, t),
  matrix: Dict(#(Int, Int), Int),
  i: Int,
  j: Int,
  acc: List(t),
) -> List(t) {
  case i == 0 || j == 0 {
    True -> acc
    False ->
      case dict.get(a_arr, i - 1), dict.get(b_arr, j - 1) {
        Ok(ai), Ok(bj) ->
          case ai == bj {
            True -> backtrack(a_arr, b_arr, matrix, i - 1, j - 1, [ai, ..acc])
            False -> {
              let up = result.unwrap(dict.get(matrix, #(i - 1, j)), 0)
              let left = result.unwrap(dict.get(matrix, #(i, j - 1)), 0)
              case up >= left {
                True -> backtrack(a_arr, b_arr, matrix, i - 1, j, acc)
                False -> backtrack(a_arr, b_arr, matrix, i, j - 1, acc)
              }
            }
          }
        _, _ -> acc
      }
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
