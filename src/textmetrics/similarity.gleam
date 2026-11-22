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
import gleam/string
import textmetrics/internal/jaro
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
  jaro.jaro(nfc_graphemes(a), nfc_graphemes(b))
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
  jaro.jaro_winkler(
    nfc_graphemes(a),
    nfc_graphemes(b),
    config.prefix_scale,
    config.prefix_max,
  )
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
