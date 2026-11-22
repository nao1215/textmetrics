//// Jaro and Jaro-Winkler over grapheme lists that are already
//// normalised, shared by `similarity` and `search`.

import gleam/int
import gleam/list
import gleam/set.{type Set}

/// Jaro-Winkler with the prefix boost applied only when the Jaro score
/// is above 0.7. `prefix_scale` and `prefix_max` come from a validated
/// `similarity.JaroWinklerConfig`.
pub fn jaro_winkler(
  a: List(String),
  b: List(String),
  prefix_scale: Float,
  prefix_max: Int,
) -> Float {
  let jaro_score = jaro(a, b)
  case jaro_score >. boost_threshold {
    False -> jaro_score
    True -> {
      let prefix =
        common_prefix_length(a, b, 0, prefix_scale, prefix_max)
        |> int.to_float
      jaro_score +. prefix *. prefix_scale *. { 1.0 -. jaro_score }
    }
  }
}

const boost_threshold = 0.7

/// Jaro similarity; `1.0` for two empty lists and `0.0` when exactly
/// one is empty.
pub fn jaro(a: List(String), b: List(String)) -> Float {
  let a_length = list.length(a)
  let b_length = list.length(b)
  case a_length, b_length {
    0, 0 -> 1.0
    0, _ -> 0.0
    _, 0 -> 0.0
    _, _ -> {
      let window = int.max(0, int.max(a_length, b_length) / 2 - 1)
      let indexed_b = list.index_map(b, fn(item, index) { #(index, item) })
      let #(a_matches, b_matched) =
        find_matches(a, 0, indexed_b, window, b_length, [], set.new())
      case a_matches {
        [] -> 0.0
        _ -> {
          // Matched graphemes of `b` in `b` order, paired with those of
          // `a` in `a` order.
          let b_matches =
            list.filter_map(indexed_b, fn(entry) {
              case set.contains(b_matched, entry.0) {
                True -> Ok(entry.1)
                False -> Error(Nil)
              }
            })
          let half_transpositions =
            list.map2(a_matches, b_matches, fn(x, y) { x != y })
            |> list.count(fn(differs) { differs })
          let matches = int.to_float(list.length(a_matches))
          let transpositions = int.to_float(half_transpositions / 2)
          {
            matches
            /. int.to_float(a_length)
            +. matches
            /. int.to_float(b_length)
            +. { matches -. transpositions }
            /. matches
          }
          /. 3.0
        }
      }
    }
  }
}

// Matches every grapheme of `a` at index `i` with the first unmatched
// equal grapheme of `b` within `window` of `i`. `window_start` is
// `indexed_b` from index `i - window` on. Returns the matched graphemes
// of `a` in order and the matched indices of `b`.
fn find_matches(
  a: List(String),
  i: Int,
  window_start: List(#(Int, String)),
  window: Int,
  b_length: Int,
  a_matches: List(String),
  b_matched: Set(Int),
) -> #(List(String), Set(Int)) {
  case a {
    [] -> #(list.reverse(a_matches), b_matched)
    [item, ..rest] -> {
      let #(a_matches, b_matched) = case
        find_match_in_window(
          item,
          window_start,
          int.min(b_length - 1, i + window),
          b_matched,
        )
      {
        Ok(j) -> #([item, ..a_matches], set.insert(b_matched, j))
        Error(Nil) -> #(a_matches, b_matched)
      }
      let window_start = case i >= window, window_start {
        True, [_, ..later] -> later
        _, _ -> window_start
      }
      find_matches(
        rest,
        i + 1,
        window_start,
        window,
        b_length,
        a_matches,
        b_matched,
      )
    }
  }
}

fn find_match_in_window(
  item: String,
  candidates: List(#(Int, String)),
  last_index: Int,
  b_matched: Set(Int),
) -> Result(Int, Nil) {
  case candidates {
    [#(j, candidate), ..rest] if j <= last_index ->
      case candidate == item && !set.contains(b_matched, j) {
        True -> Ok(j)
        False -> find_match_in_window(item, rest, last_index, b_matched)
      }
    _ -> Error(Nil)
  }
}

// Stops at `prefix_max`, and also before `prefix_scale * count` would
// exceed 1, which keeps the boosted score at or below 1.0.
fn common_prefix_length(
  a: List(String),
  b: List(String),
  count: Int,
  prefix_scale: Float,
  prefix_max: Int,
) -> Int {
  let at_limit =
    count >= prefix_max || int.to_float(count + 1) *. prefix_scale >. 1.0
  case at_limit, a, b {
    True, _, _ -> count
    False, [x, ..xs], [y, ..ys] if x == y ->
      common_prefix_length(xs, ys, count + 1, prefix_scale, prefix_max)
    False, _, _ -> count
  }
}
