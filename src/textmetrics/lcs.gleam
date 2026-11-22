//// Longest Common Subsequence helpers.
////
//// Generic over any equality-comparable list type (`List(t)`); pre-split
//// strings via `gleam/string.to_graphemes` for grapheme-level results.
//// This module performs no Unicode normalization.

import gleam/int
import gleam/list

/// Length of a longest common subsequence of `a` and `b`.
///
/// Time `O(m·n)`, space `O(m + n)`. Returns `0` when either input is
/// empty.
///
/// Note: this name shadows `gleam/list.length` if both are imported
/// unqualified (`import textmetrics/lcs.{length}`). Prefer the
/// qualified `lcs.length(...)` form to avoid the conflict.
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
/// Time `O(m·n)`, space `O(n·√m)` for `m = length(a)`, `n = length(b)`.
pub fn sequence(a: List(t), b: List(t)) -> List(t) {
  let m = list.length(a)
  let n = list.length(b)
  case m == 0 || n == 0 {
    True -> []
    False -> {
      let block = block_size(m, 1)
      let first_row = list.repeat(0, n + 1)
      let checkpoints =
        forward_checkpoints(a, b, block, 0, first_row, [
          Checkpoint(index: 0, row: first_row, rest_of_a: a),
        ])
      backtrack_blocks(
        checkpoints,
        m,
        n,
        n,
        list.reverse(a),
        list.reverse(b),
        b,
        [],
      )
    }
  }
}

// The table is never held in full. The forward pass keeps every
// `block`-th row; the backtrack then recomputes one block of rows at a
// time, from the last block up, and walks it with the same rule as a
// full-table backtrack: take a match, otherwise move up when that keeps
// the length, otherwise move left.
type Checkpoint(t) {
  Checkpoint(index: Int, row: List(Int), rest_of_a: List(t))
}

fn block_size(m: Int, size: Int) -> Int {
  case size * size >= m {
    True -> size
    False -> block_size(m, size + 1)
  }
}

// Row `i + 1` of the table from row `i`, where `item` is `a[i]`.
fn next_row(item: t, b: List(t), row: List(Int)) -> List(Int) {
  case row {
    [_, ..rest] -> lcs_length_inner(item, b, 0, rest, 0, [0])
    [] -> [0]
  }
}

// Returns the checkpoints with the latest first. Row `m` is not kept.
fn forward_checkpoints(
  remaining_a: List(t),
  b: List(t),
  block: Int,
  index: Int,
  row: List(Int),
  checkpoints: List(Checkpoint(t)),
) -> List(Checkpoint(t)) {
  case remaining_a {
    [] -> checkpoints
    [item, ..rest] -> {
      let row = next_row(item, b, row)
      let index = index + 1
      let checkpoints = case rest, index % block {
        [_, ..], 0 -> [Checkpoint(index:, row:, rest_of_a: rest), ..checkpoints]
        _, _ -> checkpoints
      }
      forward_checkpoints(rest, b, block, index, row, checkpoints)
    }
  }
}

// `i` and `j` are the current cell; `reversed_a` and `reversed_b` start
// with `a[i - 1]` and `b[j - 1]`.
fn backtrack_blocks(
  checkpoints: List(Checkpoint(t)),
  i: Int,
  j: Int,
  n: Int,
  reversed_a: List(t),
  reversed_b: List(t),
  b: List(t),
  acc: List(t),
) -> List(t) {
  case checkpoints, i > 0 && j > 0 {
    [Checkpoint(index: lower, row:, rest_of_a:), ..earlier], True -> {
      // Rows `i` down to `lower`, each reversed so that it is read from
      // column `n` down to column 0.
      let rows =
        list.take(rest_of_a, i - lower)
        |> list.fold(#(row, [list.reverse(row)]), fn(state, item) {
          let #(previous, rows) = state
          let next = next_row(item, b, previous)
          #(next, [list.reverse(next), ..rows])
        })
      case rows.1 {
        [current, above, ..rest] -> {
          let #(i, j, reversed_a, reversed_b, acc) =
            backtrack_block(
              Cursor(i:, j:, reversed_a:, reversed_b:, acc:),
              lower,
              n,
              list.drop(current, n - j),
              list.drop(above, n - j),
              rest,
            )
          backtrack_blocks(earlier, i, j, n, reversed_a, reversed_b, b, acc)
        }
        _ -> acc
      }
    }
    _, _ -> acc
  }
}

type Cursor(t) {
  Cursor(i: Int, j: Int, reversed_a: List(t), reversed_b: List(t), acc: List(t))
}

// `current` and `above` are rows `i` and `i - 1` from column `j` down;
// `rest` holds the full reversed rows `i - 2` down to `lower`.
fn backtrack_block(
  cursor: Cursor(t),
  lower: Int,
  n: Int,
  current: List(Int),
  above: List(Int),
  rest: List(List(Int)),
) -> #(Int, Int, List(t), List(t), List(t)) {
  let Cursor(i:, j:, reversed_a:, reversed_b:, acc:) = cursor
  case i > lower && j > 0, reversed_a, reversed_b {
    True, [item_a, ..more_a], [item_b, ..more_b] ->
      case item_a == item_b {
        True -> {
          let #(next_above, next_rest) = row_at(rest, n - j + 1)
          backtrack_block(
            Cursor(
              i: i - 1,
              j: j - 1,
              reversed_a: more_a,
              reversed_b: more_b,
              acc: [item_a, ..acc],
            ),
            lower,
            n,
            list.drop(above, 1),
            next_above,
            next_rest,
          )
        }
        False ->
          case first(above) >= first(list.drop(current, 1)) {
            True -> {
              let #(next_above, next_rest) = row_at(rest, n - j)
              backtrack_block(
                Cursor(..cursor, i: i - 1, reversed_a: more_a),
                lower,
                n,
                above,
                next_above,
                next_rest,
              )
            }
            False ->
              backtrack_block(
                Cursor(..cursor, j: j - 1, reversed_b: more_b),
                lower,
                n,
                list.drop(current, 1),
                list.drop(above, 1),
                rest,
              )
          }
      }
    _, _, _ -> #(i, j, reversed_a, reversed_b, acc)
  }
}

fn row_at(rows: List(List(Int)), skip: Int) -> #(List(Int), List(List(Int))) {
  case rows {
    [row, ..rest] -> #(list.drop(row, skip), rest)
    [] -> #([], [])
  }
}

fn first(row: List(Int)) -> Int {
  case row {
    [value, ..] -> value
    [] -> 0
  }
}
