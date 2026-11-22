//// Copies of the v0.9.0 implementations of the algorithms that were
//// rewritten for speed and memory. The tests compare the current code
//// against these on random inputs, so the rewrites must return the
//// same results, including the choice among equally good answers.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string
import textmetrics/edit.{type EditScript, Delete, Equal, Insert}

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

fn find_unique_pairs(
  old: List(String),
  new: List(String),
) -> List(#(Int, Int)) {
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

// --- lcs.sequence ---

pub fn lcs_sequence(a: List(t), b: List(t)) -> List(t) {
  let m = list.length(a)
  let n = list.length(b)
  case m == 0 || n == 0 {
    True -> []
    False -> {
      let a_arr = list_to_dict(a)
      let b_arr = list_to_dict(b)
      let matrix = build_lcs_matrix(a_arr, b_arr, m, n)
      lcs_backtrack(a_arr, b_arr, matrix, m, n, [])
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

fn lcs_backtrack(
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
            True ->
              lcs_backtrack(a_arr, b_arr, matrix, i - 1, j - 1, [ai, ..acc])
            False -> {
              let up = result.unwrap(dict.get(matrix, #(i - 1, j)), 0)
              let left = result.unwrap(dict.get(matrix, #(i, j - 1)), 0)
              case up >= left {
                True -> lcs_backtrack(a_arr, b_arr, matrix, i - 1, j, acc)
                False -> lcs_backtrack(a_arr, b_arr, matrix, i, j - 1, acc)
              }
            }
          }
        _, _ -> acc
      }
  }
}

// --- distance ---

pub fn damerau_levenshtein(ga: List(String), gb: List(String)) -> Int {
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

pub fn osa(ga: List(String), gb: List(String)) -> Int {
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

fn make_init_row(n: Int) -> Dict(Int, Int) {
  int_range_inclusive(0, n)
  |> list.index_map(fn(v, i) { #(i, v) })
  |> dict.from_list
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

fn min4(a: Int, b: Int, c: Int, d: Int) -> Int {
  int.min(int.min(a, b), int.min(c, d))
}

// --- similarity.jaro ---

pub fn jaro(ga: List(String), gb: List(String)) -> Float {
  let la = list.length(ga)
  let lb = list.length(gb)
  case la, lb {
    0, 0 -> 1.0
    0, _ -> 0.0
    _, 0 -> 0.0
    _, _ -> {
      let max_len = int.max(la, lb)
      let window = int.max(0, max_len / 2 - 1)
      let a_arr = list_to_dict(ga)
      let b_arr = list_to_dict(gb)
      let #(matches, a_matched, b_matched) =
        find_matches(a_arr, b_arr, la, lb, window, 0, 0, dict.new(), dict.new())
      case matches {
        0 -> 0.0
        _ -> {
          let half_t =
            count_half_transpositions(
              a_arr,
              b_arr,
              a_matched,
              b_matched,
              la,
              0,
              0,
              0,
            )
          let t = half_t / 2
          let m_f = int.to_float(matches)
          let la_f = int.to_float(la)
          let lb_f = int.to_float(lb)
          let t_f = int.to_float(t)
          { m_f /. la_f +. m_f /. lb_f +. { m_f -. t_f } /. m_f } /. 3.0
        }
      }
    }
  }
}

fn find_matches(
  a_arr: Dict(Int, String),
  b_arr: Dict(Int, String),
  la: Int,
  lb: Int,
  window: Int,
  i: Int,
  matches: Int,
  a_matched: Dict(Int, Bool),
  b_matched: Dict(Int, Bool),
) -> #(Int, Dict(Int, Bool), Dict(Int, Bool)) {
  case i >= la {
    True -> #(matches, a_matched, b_matched)
    False -> {
      let ai = result.unwrap(dict.get(a_arr, i), "")
      let lo = int.max(0, i - window)
      let hi = int.min(lb - 1, i + window)
      case find_match_in_range(ai, b_arr, lo, hi, b_matched) {
        Ok(j) ->
          find_matches(
            a_arr,
            b_arr,
            la,
            lb,
            window,
            i + 1,
            matches + 1,
            dict.insert(a_matched, i, True),
            dict.insert(b_matched, j, True),
          )
        Error(_) ->
          find_matches(
            a_arr,
            b_arr,
            la,
            lb,
            window,
            i + 1,
            matches,
            a_matched,
            b_matched,
          )
      }
    }
  }
}

fn find_match_in_range(
  ai: String,
  b_arr: Dict(Int, String),
  j: Int,
  hi: Int,
  b_matched: Dict(Int, Bool),
) -> Result(Int, Nil) {
  case j > hi {
    True -> Error(Nil)
    False -> {
      let already = case dict.get(b_matched, j) {
        Ok(True) -> True
        _ -> False
      }
      case already {
        True -> find_match_in_range(ai, b_arr, j + 1, hi, b_matched)
        False -> {
          let bj = result.unwrap(dict.get(b_arr, j), "")
          case ai == bj {
            True -> Ok(j)
            False -> find_match_in_range(ai, b_arr, j + 1, hi, b_matched)
          }
        }
      }
    }
  }
}

fn count_half_transpositions(
  a_arr: Dict(Int, String),
  b_arr: Dict(Int, String),
  a_matched: Dict(Int, Bool),
  b_matched: Dict(Int, Bool),
  la: Int,
  i: Int,
  k: Int,
  trans: Int,
) -> Int {
  case i >= la {
    True -> trans
    False -> {
      case dict.get(a_matched, i) {
        Ok(True) -> {
          let new_k = skip_unmatched_b(b_matched, k)
          let ai = result.unwrap(dict.get(a_arr, i), "")
          let bk = result.unwrap(dict.get(b_arr, new_k), "")
          let new_trans = case ai == bk {
            True -> trans
            False -> trans + 1
          }
          count_half_transpositions(
            a_arr,
            b_arr,
            a_matched,
            b_matched,
            la,
            i + 1,
            new_k + 1,
            new_trans,
          )
        }
        _ ->
          count_half_transpositions(
            a_arr,
            b_arr,
            a_matched,
            b_matched,
            la,
            i + 1,
            k,
            trans,
          )
      }
    }
  }
}

fn skip_unmatched_b(b_matched: Dict(Int, Bool), k: Int) -> Int {
  case dict.get(b_matched, k) {
    Ok(True) -> k
    _ -> skip_unmatched_b(b_matched, k + 1)
  }
}

// --- count.sentences ---

fn is_letter_like(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [] -> False
    [cp, ..] -> {
      let n = string.utf_codepoint_to_int(cp)
      is_letter_like_code(n)
    }
  }
}

fn is_letter_like_code(n: Int) -> Bool {
  case n {
    // ASCII letters
    _ if n >= 0x41 && n <= 0x5a -> True
    _ if n >= 0x61 && n <= 0x7a -> True
    // ASCII digits
    _ if n >= 0x30 && n <= 0x39 -> True
    // Anything above ASCII — Latin-1 letters, CJK, accented graphemes
    _ if n >= 0x80 -> True
    _ -> False
  }
}

pub fn sentences(text: String) -> Int {
  let graphemes = string.to_graphemes(text)
  case has_non_whitespace(graphemes) {
    False -> 0
    True -> sentence_loop(graphemes, False, False, [], 0)
  }
}

fn sentence_loop(
  items: List(String),
  saw_content: Bool,
  in_terminator: Bool,
  current_word: List(String),
  acc: Int,
) -> Int {
  case items {
    [] ->
      case saw_content {
        True -> acc + 1
        False -> acc
      }
    [g, ..rest] -> {
      case is_terminator(g), is_whitespace(g) {
        True, _ -> {
          // For `.`, suppress termination inside a token or after an
          // abbreviation. `!` and `?` always terminate.
          let suppress = case g {
            "." -> period_continues_sentence(current_word, rest)
            _ -> False
          }
          let next_acc = case suppress, in_terminator {
            True, _ -> acc
            False, True -> acc
            False, False ->
              case saw_content {
                True -> acc + 1
                False -> acc
              }
          }
          let next_in_terminator = case suppress {
            True -> False
            False -> True
          }
          let next_saw_content = case suppress {
            True -> saw_content
            False -> False
          }
          let next_word = case suppress {
            // Keep the abbreviation token attached to the period so
            // multi-period abbreviations like "e.g." chain correctly.
            True -> [".", ..current_word]
            False -> []
          }
          sentence_loop(
            rest,
            next_saw_content,
            next_in_terminator,
            next_word,
            next_acc,
          )
        }
        False, True -> sentence_loop(rest, saw_content, False, [], acc)
        False, False ->
          sentence_loop(rest, True, False, [g, ..current_word], acc)
      }
    }
  }
}

fn is_terminator(g: String) -> Bool {
  case g {
    "." | "!" | "?" -> True
    _ -> False
  }
}

// `reversed_word` is the token before the period, graphemes reversed,
// with the periods of a multi-period abbreviation kept in it (`"p.m"`
// for the second period of `p.m.`). `rest` is the text after it.
fn period_continues_sentence(
  reversed_word: List(String),
  rest: List(String),
) -> Bool {
  let word =
    reversed_word
    |> list.reverse
    |> string.concat
    |> string.lowercase
  case rest {
    [next, ..] -> is_letter_like(next)
    [] -> False
  }
  || is_abbreviation(word)
  || { is_multi_period_abbreviation(word) && !starts_capitalised(rest) }
}

fn is_abbreviation(word: String) -> Bool {
  case word {
    "mr" | "mrs" | "ms" | "dr" | "prof" | "jr" | "sr" | "st" -> True
    "vs" | "etc" | "no" | "co" | "inc" | "ltd" | "fig" | "vol" | "ch" -> True
    "ave" | "blvd" -> True
    // Months (3-letter and 4-letter forms).
    "jan" | "feb" | "mar" | "apr" | "jun" | "jul" -> True
    "aug" | "sep" | "sept" | "oct" | "nov" | "dec" -> True
    // Days of week.
    "mon" | "tue" | "tues" | "wed" | "thu" | "thur" | "thurs" -> True
    "fri" | "sat" | "sun" -> True
    _ -> False
  }
}

// Two or more one- or two-letter parts joined by periods: `e.g`, `a.m`,
// `u.s.a`, `ph.d`.
fn is_multi_period_abbreviation(word: String) -> Bool {
  case string.split(word, on: ".") {
    [_] -> False
    parts ->
      list.all(parts, fn(part) {
        let letters = string.to_graphemes(part)
        let length = list.length(letters)
        length >= 1 && length <= 2 && list.all(letters, is_ascii_letter)
      })
  }
}

fn starts_capitalised(rest: List(String)) -> Bool {
  case list.drop_while(rest, is_whitespace) {
    [next, ..] ->
      string.uppercase(next) == next && string.lowercase(next) != next
    [] -> False
  }
}

fn is_whitespace(g: String) -> Bool {
  case g {
    " " | "\t" | "\n" | "\r" | "\u{00A0}" -> True
    _ -> False
  }
}

fn has_non_whitespace(items: List(String)) -> Bool {
  case items {
    [] -> False
    [g, ..rest] ->
      case is_whitespace(g) {
        True -> has_non_whitespace(rest)
        False -> True
      }
  }
}

fn is_ascii_letter(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [] -> False
    [cp, ..] -> {
      let n = string.utf_codepoint_to_int(cp)
      n >= 0x61 && n <= 0x7a
    }
  }
}
