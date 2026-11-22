import gleam/float
import gleeunit/should
import textmetrics/similarity

// Reference values come from rapidfuzz 3.14 (`JaroWinkler.similarity`)
// and jellyfish (`jaro_winkler_similarity`).

const tolerance = 0.000_001

fn approx_equal(actual: Float, expected: Float) -> Bool {
  float.absolute_value(actual -. expected) <=. tolerance
}

// A long shared prefix with `prefix_scale * prefix_max > 1` used to push
// the score above 1.0 (1.0909 for a 10-grapheme prefix).
pub fn jaro_winkler_long_prefix_stays_at_most_one_test() {
  let assert Ok(config) =
    similarity.jaro_winkler_config(prefix_scale: 0.25, prefix_max: 10)
  similarity.jaro_winkler_with("abcdefghijX", "abcdefghijY", config)
  |> should.equal(1.0)
}

pub fn jaro_winkler_prefix_five_with_quarter_scale_test() {
  let assert Ok(config) =
    similarity.jaro_winkler_config(prefix_scale: 0.25, prefix_max: 5)
  let score = similarity.jaro_winkler_with("abcdeX", "abcdeY", config)
  { score <=. 1.0 } |> should.be_true
}

// The effective prefix is capped so that `prefix_scale * prefix <= 1`:
// with scale 0.15 at most 6 graphemes count.
pub fn jaro_winkler_prefix_capped_by_scale_test() {
  let assert Ok(config) =
    similarity.jaro_winkler_config(prefix_scale: 0.15, prefix_max: 10)
  similarity.jaro_winkler_with("abcdefghX", "abcdefghY", config)
  |> approx_equal(0.992_592_592_6)
  |> should.be_true
}

// The prefix boost only applies when the Jaro score is above 0.7.
pub fn jaro_winkler_no_boost_below_threshold_test() {
  similarity.jaro_winkler("abcxyz", "abcdef")
  |> approx_equal(0.666_666_666_7)
  |> should.be_true
}

pub fn jaro_winkler_below_threshold_equals_jaro_test() {
  let jaro = similarity.jaro("abcxyz", "abcdef")
  similarity.jaro_winkler("abcxyz", "abcdef") |> should.equal(jaro)
}
