//// Similarity scores in the closed interval `[0.0, 1.0]`.
////
//// `1.0` means "identical", `0.0` means "no similarity by this
//// metric". No function in this module returns `NaN` or a negative
//// `Float`.
////
//// All string-typed functions operate on extended grapheme clusters
//// and do not normalize their inputs — callers wanting NFC
//// equivalence must normalize first.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/result
import gleam/string

/// Returned by [`sorensen_dice`](#sorensen_dice) when given an n-gram
/// size below `1`.
pub type SorensenDiceError {
  NgramSizeInvalid(got: Int)
}

/// Returned by [`jaro_winkler_config`](#jaro_winkler_config) when its
/// arguments fall outside the validated range.
pub type JaroWinklerConfigError {
  PrefixScaleOutOfRange(got: Float)
  PrefixMaxNegative(got: Int)
}

/// Validated parameter bag for [`jaro_winkler_with`](#jaro_winkler_with).
///
/// A value of this type is *guaranteed* to encode parameters that keep
/// Jaro-Winkler output inside `[0.0, 1.0]`. Construct via
/// [`default_jaro_winkler_config`](#default_jaro_winkler_config) or
/// [`jaro_winkler_config`](#jaro_winkler_config).
pub opaque type JaroWinklerConfig {
  JaroWinklerConfig(prefix_scale: Float, prefix_max: Int)
}

/// Winkler-1990 defaults: `prefix_scale = 0.1`, `prefix_max = 4`.
pub fn default_jaro_winkler_config() -> JaroWinklerConfig {
  JaroWinklerConfig(prefix_scale: 0.1, prefix_max: 4)
}

/// Construct a [`JaroWinklerConfig`](#JaroWinklerConfig).
///
/// Invariants:
/// - `prefix_scale` must be in `[0.0, 0.25]` (Winkler's upper bound
///   that keeps the score in `[0, 1]`).
/// - `prefix_max` must be `>= 0`.
pub fn jaro_winkler_config(
  prefix_scale prefix_scale: Float,
  prefix_max prefix_max: Int,
) -> Result(JaroWinklerConfig, JaroWinklerConfigError) {
  case prefix_scale <. 0.0 || prefix_scale >. 0.25 {
    True -> Error(PrefixScaleOutOfRange(prefix_scale))
    False ->
      case prefix_max < 0 {
        True -> Error(PrefixMaxNegative(prefix_max))
        False ->
          Ok(JaroWinklerConfig(
            prefix_scale: prefix_scale,
            prefix_max: prefix_max,
          ))
      }
  }
}

/// Read the prefix-scale parameter of a config.
pub fn prefix_scale(config: JaroWinklerConfig) -> Float {
  config.prefix_scale
}

/// Read the prefix-cap parameter of a config.
pub fn prefix_max(config: JaroWinklerConfig) -> Int {
  config.prefix_max
}

/// Jaro similarity at the grapheme level.
///
/// Edge cases (defined by convention):
/// - `jaro("", "")` = `1.0`
/// - `jaro("", b)` = `0.0` for non-empty `b`
/// - `jaro(a, "")` = `0.0` for non-empty `a`
///
/// Time `O(m·n)`, space `O(m + n)`.
pub fn jaro(a: String, b: String) -> Float {
  jaro_graphemes(string.to_graphemes(a), string.to_graphemes(b))
}

/// Jaro-Winkler similarity using Winkler-1990 defaults
/// (`prefix_scale = 0.1`, `prefix_max = 4`).
pub fn jaro_winkler(a: String, b: String) -> Float {
  jaro_winkler_with(a, b, default_jaro_winkler_config())
}

/// Jaro-Winkler similarity with caller-supplied parameters.
pub fn jaro_winkler_with(
  a: String,
  b: String,
  config: JaroWinklerConfig,
) -> Float {
  let ga = string.to_graphemes(a)
  let gb = string.to_graphemes(b)
  let j = jaro_graphemes(ga, gb)
  let l = common_prefix_length(ga, gb, 0, config.prefix_max) |> int.to_float
  j +. l *. config.prefix_scale *. { 1.0 -. j }
}

/// Sørensen-Dice over bigrams (`n = 2`) — the de-facto standard for
/// string similarity. Sibling of [`jaro`](#jaro) /
/// [`jaro_winkler`](#jaro_winkler), returning a plain `Float` in
/// `[0.0, 1.0]` so call sites can pipe directly into thresholds
/// without unwrapping a `Result`.
///
/// Equivalent to `sorensen_dice(a, b, 2)` with the impossible-by-
/// construction `n < 1` branch elided.
pub fn sorensen_dice_bigrams(a: String, b: String) -> Float {
  // n = 2 is positive, so sorensen_dice's error arm is unreachable.
  case sorensen_dice(a, b, 2) {
    Ok(score) -> score
    Error(_) -> 0.0
  }
}

/// Sørensen-Dice over trigrams (`n = 3`). The same shape as
/// [`sorensen_dice_bigrams`](#sorensen_dice_bigrams) but with a wider
/// n-gram window; useful when inputs share long common substrings
/// and bigrams produce a noisy score.
pub fn sorensen_dice_trigrams(a: String, b: String) -> Float {
  case sorensen_dice(a, b, 3) {
    Ok(score) -> score
    Error(_) -> 0.0
  }
}

/// Sørensen-Dice coefficient over grapheme n-grams of size `n`.
///
/// Strict variant — surfaces `NgramSizeInvalid` for `n < 1`. For the
/// common case of bigrams or trigrams over user-controlled `a` and
/// `b`, prefer the lenient siblings
/// [`sorensen_dice_bigrams`](#sorensen_dice_bigrams) and
/// [`sorensen_dice_trigrams`](#sorensen_dice_trigrams), which return
/// a plain `Float` and skip the error-discarding boilerplate at the
/// call site.
///
/// Edge cases (per spec §7.5):
/// - When both n-gram multisets are empty, the result is `Ok(1.0)` if
///   the inputs are equal (including both empty) and `Ok(0.0)`
///   otherwise.
/// - When exactly one input has no n-grams the score is `Ok(0.0)`
///   (no overlap is possible).
/// - `n < 1` returns `Error(NgramSizeInvalid(n))`.
pub fn sorensen_dice(
  a: String,
  b: String,
  n: Int,
) -> Result(Float, SorensenDiceError) {
  case n < 1 {
    True -> Error(NgramSizeInvalid(n))
    False -> {
      let ga = string.to_graphemes(a)
      let gb = string.to_graphemes(b)
      let ngs_a = build_ngrams(ga, n)
      let ngs_b = build_ngrams(gb, n)
      let total_a = list.length(ngs_a)
      let total_b = list.length(ngs_b)
      case total_a + total_b {
        0 ->
          case a == b {
            True -> Ok(1.0)
            False -> Ok(0.0)
          }
        denom -> {
          let multiset_a = list.fold(ngs_a, dict.new(), increment_count)
          let multiset_b = list.fold(ngs_b, dict.new(), increment_count)
          let inter = intersection_size(multiset_a, multiset_b)
          Ok(int.to_float(2 * inter) /. int.to_float(denom))
        }
      }
    }
  }
}

// ---------------------------------------------------------------------
// Jaro internals
// ---------------------------------------------------------------------

fn jaro_graphemes(ga: List(String), gb: List(String)) -> Float {
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

fn common_prefix_length(
  a: List(String),
  b: List(String),
  count: Int,
  max: Int,
) -> Int {
  case count >= max {
    True -> count
    False ->
      case a, b {
        [x, ..xs], [y, ..ys] ->
          case x == y {
            True -> common_prefix_length(xs, ys, count + 1, max)
            False -> count
          }
        _, _ -> count
      }
  }
}

// ---------------------------------------------------------------------
// Sørensen-Dice internals
// ---------------------------------------------------------------------

fn build_ngrams(gs: List(String), n: Int) -> List(String) {
  let len = list.length(gs)
  case len < n {
    True -> []
    False -> {
      let arr = list_to_dict(gs)
      build_ngrams_loop(arr, n, len, 0, [])
    }
  }
}

fn build_ngrams_loop(
  arr: Dict(Int, String),
  n: Int,
  len: Int,
  i: Int,
  acc: List(String),
) -> List(String) {
  case i + n > len {
    True -> list.reverse(acc)
    False -> {
      let ngram = build_ngram_at(arr, i, n, [])
      build_ngrams_loop(arr, n, len, i + 1, [ngram, ..acc])
    }
  }
}

fn build_ngram_at(
  arr: Dict(Int, String),
  start: Int,
  count: Int,
  acc: List(String),
) -> String {
  case count {
    0 -> list.reverse(acc) |> string.concat
    _ -> {
      let g = result.unwrap(dict.get(arr, start), "")
      build_ngram_at(arr, start + 1, count - 1, [g, ..acc])
    }
  }
}

fn increment_count(acc: Dict(String, Int), key: String) -> Dict(String, Int) {
  dict.upsert(acc, key, fn(opt) {
    case opt {
      Some(c) -> c + 1
      None -> 1
    }
  })
}

fn intersection_size(a: Dict(String, Int), b: Dict(String, Int)) -> Int {
  dict.fold(a, 0, fn(acc, key, ca) {
    case dict.get(b, key) {
      Ok(cb) -> acc + int.min(ca, cb)
      Error(_) -> acc
    }
  })
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
