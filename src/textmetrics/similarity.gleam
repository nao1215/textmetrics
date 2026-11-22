//// Similarity scores in the closed interval `[0.0, 1.0]`.
////
//// `1.0` means "identical", `0.0` means "no similarity by this
//// metric". No function in this module returns `NaN` or a negative
//// `Float`.
////
//// All string-typed functions operate on extended grapheme clusters
//// after normalising their inputs to Unicode Normalization Form C
//// (NFC), so `"\u{00C1}"` and `"A\u{0301}"` score as identical.

import gleam/dict.{type Dict}
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/set.{type Set}
import gleam/string
import textmetrics/internal/unicode

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
/// Jaro-Winkler output stays inside `[0.0, 1.0]` for every value of this
/// type: the prefix length that counts is capped so that
/// `prefix_scale * prefix_length <= 1`. Construct via
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
/// - `prefix_scale` must be in `[0.0, 0.25]`.
/// - `prefix_max` must be `>= 0`. At most `1 / prefix_scale` prefix
///   graphemes count, whatever `prefix_max` says.
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
  jaro_graphemes(nfc_graphemes(a), nfc_graphemes(b))
}

/// Jaro-Winkler similarity using Winkler-1990 defaults
/// (`prefix_scale = 0.1`, `prefix_max = 4`).
pub fn jaro_winkler(a: String, b: String) -> Float {
  jaro_winkler_with(a, b, default_jaro_winkler_config())
}

/// Jaro-Winkler similarity with caller-supplied parameters.
///
/// The prefix boost is applied only when the Jaro score is above `0.7`
/// (Winkler's boost threshold, as in rapidfuzz and jellyfish).
pub fn jaro_winkler_with(
  a: String,
  b: String,
  config: JaroWinklerConfig,
) -> Float {
  let a_graphemes = nfc_graphemes(a)
  let b_graphemes = nfc_graphemes(b)
  let jaro_score = jaro_graphemes(a_graphemes, b_graphemes)
  case jaro_score >. boost_threshold {
    False -> jaro_score
    True -> {
      let prefix =
        common_prefix_length(a_graphemes, b_graphemes, 0, config)
        |> int.to_float
      jaro_score +. prefix *. config.prefix_scale *. { 1.0 -. jaro_score }
    }
  }
}

const boost_threshold = 0.7

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

/// Sørensen-Dice coefficient over grapheme n-grams of size `ngram_size`.
///
/// Strict variant — surfaces `NgramSizeInvalid` for `ngram_size < 1`. For the
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
/// - `ngram_size < 1` returns `Error(NgramSizeInvalid(ngram_size))`.
pub fn sorensen_dice(
  a: String,
  b: String,
  ngram_size: Int,
) -> Result(Float, SorensenDiceError) {
  case ngram_size < 1 {
    True -> Error(NgramSizeInvalid(ngram_size))
    False -> {
      let a_graphemes = nfc_graphemes(a)
      let b_graphemes = nfc_graphemes(b)
      let a_ngrams = build_ngrams(a_graphemes, ngram_size)
      let b_ngrams = build_ngrams(b_graphemes, ngram_size)
      case list.length(a_ngrams) + list.length(b_ngrams) {
        0 ->
          case a_graphemes == b_graphemes {
            True -> Ok(1.0)
            False -> Ok(0.0)
          }
        total -> {
          let a_multiset = list.fold(a_ngrams, dict.new(), increment_count)
          let b_multiset = list.fold(b_ngrams, dict.new(), increment_count)
          let shared = intersection_size(a_multiset, b_multiset)
          Ok(int.to_float(2 * shared) /. int.to_float(total))
        }
      }
    }
  }
}

// ---------------------------------------------------------------------
// Jaro internals
// ---------------------------------------------------------------------

fn jaro_graphemes(a: List(String), b: List(String)) -> Float {
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
  config: JaroWinklerConfig,
) -> Int {
  let at_limit =
    count >= config.prefix_max
    || int.to_float(count + 1) *. config.prefix_scale >. 1.0
  case at_limit, a, b {
    True, _, _ -> count
    False, [x, ..xs], [y, ..ys] if x == y ->
      common_prefix_length(xs, ys, count + 1, config)
    False, _, _ -> count
  }
}

// ---------------------------------------------------------------------
// Sørensen-Dice internals
// ---------------------------------------------------------------------

fn build_ngrams(graphemes: List(String), size: Int) -> List(String) {
  list.window(graphemes, by: size) |> list.map(string.concat)
}

fn increment_count(acc: Dict(String, Int), key: String) -> Dict(String, Int) {
  dict.upsert(acc, key, fn(existing) {
    case existing {
      Some(count) -> count + 1
      None -> 1
    }
  })
}

fn intersection_size(a: Dict(String, Int), b: Dict(String, Int)) -> Int {
  dict.fold(a, 0, fn(acc, key, count_a) {
    case dict.get(b, key) {
      Ok(count_b) -> acc + int.min(count_a, count_b)
      Error(_) -> acc
    }
  })
}

// ---------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------

fn nfc_graphemes(text: String) -> List(String) {
  string.to_graphemes(unicode.to_nfc(text))
}
