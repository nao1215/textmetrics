import gleam/float
import gleeunit/should
import textmetrics

// Reference values come from rapidfuzz 3.14 (`JaroWinkler.similarity`)
// and jellyfish (`jaro_winkler_similarity`).

const tolerance = 0.000_001

fn approx_equal(actual: Float, expected: Float) -> Bool {
  float.absolute_value(actual -. expected) <=. tolerance
}

// A long shared prefix with `prefix_scale * prefix_max > 1` used to push
// the score above 1.0 (1.0909 for a 10-grapheme prefix).
pub fn jaro_winkler_long_prefix_stays_at_most_one_test() {
  let config = #(0.25, 10)
  {
    textmetrics.jaro_winkler(
      "abcdefghijX",
      "abcdefghijY",
      prefix_scale: config.0,
      prefix_max: config.1,
    )
    |> should.be_ok
  }
  |> should.equal(1.0)
}

pub fn jaro_winkler_prefix_five_with_quarter_scale_test() {
  let config = #(0.25, 5)
  let score = {
    textmetrics.jaro_winkler(
      "abcdeX",
      "abcdeY",
      prefix_scale: config.0,
      prefix_max: config.1,
    )
    |> should.be_ok
  }
  { score <=. 1.0 } |> should.be_true
}

// The effective prefix is capped so that `prefix_scale * prefix <= 1`:
// with scale 0.15 at most 6 graphemes count.
pub fn jaro_winkler_prefix_capped_by_scale_test() {
  let config = #(0.15, 10)
  {
    textmetrics.jaro_winkler(
      "abcdefghX",
      "abcdefghY",
      prefix_scale: config.0,
      prefix_max: config.1,
    )
    |> should.be_ok
  }
  |> approx_equal(0.992_592_592_6)
  |> should.be_true
}

// The prefix boost only applies when the Jaro score is above 0.7.
pub fn jaro_winkler_no_boost_below_threshold_test() {
  {
    textmetrics.jaro_winkler(
      "abcxyz",
      "abcdef",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> approx_equal(0.666_666_666_7)
  |> should.be_true
}

pub fn jaro_winkler_below_threshold_equals_jaro_test() {
  let jaro = textmetrics.jaro("abcxyz", "abcdef")
  {
    textmetrics.jaro_winkler(
      "abcxyz",
      "abcdef",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> should.equal(jaro)
}
