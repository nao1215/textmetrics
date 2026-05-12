import gleam/float
import gleeunit/should
import textmetrics/similarity.{
  NgramSizeInvalid, PrefixMaxNegative, PrefixScaleOutOfRange,
}

const tolerance = 0.000_001

fn approx_equal(actual: Float, expected: Float) -> Bool {
  float.absolute_value(actual -. expected) <=. tolerance
}

pub fn jaro_empty_pair_is_one_test() {
  similarity.jaro("", "") |> should.equal(1.0)
}

pub fn jaro_empty_left_is_zero_test() {
  similarity.jaro("", "abc") |> should.equal(0.0)
}

pub fn jaro_empty_right_is_zero_test() {
  similarity.jaro("abc", "") |> should.equal(0.0)
}

pub fn jaro_identical_is_one_test() {
  similarity.jaro("abc", "abc") |> should.equal(1.0)
}

pub fn jaro_single_char_match_test() {
  similarity.jaro("a", "a") |> should.equal(1.0)
}

pub fn jaro_single_char_mismatch_test() {
  similarity.jaro("a", "b") |> should.equal(0.0)
}

pub fn jaro_winkler_empty_pair_is_one_test() {
  similarity.jaro_winkler("", "") |> should.equal(1.0)
}

pub fn jaro_winkler_identical_is_one_test() {
  similarity.jaro_winkler("abc", "abc") |> should.equal(1.0)
}

pub fn jaro_winkler_no_common_prefix_equals_jaro_test() {
  // JELLYFISH vs SMELLYFISH share no prefix, so jw == j.
  let j = similarity.jaro("JELLYFISH", "SMELLYFISH")
  let jw = similarity.jaro_winkler("JELLYFISH", "SMELLYFISH")
  approx_equal(jw, j) |> should.be_true
}

pub fn jaro_winkler_with_default_config_test() {
  let cfg = similarity.default_jaro_winkler_config()
  let direct = similarity.jaro_winkler("MARTHA", "MARHTA")
  let viacfg = similarity.jaro_winkler_with("MARTHA", "MARHTA", cfg)
  approx_equal(direct, viacfg) |> should.be_true
}

pub fn jaro_winkler_config_accepts_valid_test() {
  similarity.jaro_winkler_config(prefix_scale: 0.1, prefix_max: 4)
  |> should.be_ok
  similarity.jaro_winkler_config(prefix_scale: 0.0, prefix_max: 0)
  |> should.be_ok
  similarity.jaro_winkler_config(prefix_scale: 0.25, prefix_max: 10)
  |> should.be_ok
}

pub fn jaro_winkler_config_rejects_high_scale_test() {
  similarity.jaro_winkler_config(prefix_scale: 0.26, prefix_max: 4)
  |> should.equal(Error(PrefixScaleOutOfRange(0.26)))
}

pub fn jaro_winkler_config_rejects_negative_scale_test() {
  similarity.jaro_winkler_config(prefix_scale: -0.01, prefix_max: 4)
  |> should.equal(Error(PrefixScaleOutOfRange(-0.01)))
}

pub fn jaro_winkler_config_rejects_negative_max_test() {
  similarity.jaro_winkler_config(prefix_scale: 0.1, prefix_max: -1)
  |> should.equal(Error(PrefixMaxNegative(-1)))
}

pub fn jaro_winkler_config_accessors_test() {
  let assert Ok(cfg) =
    similarity.jaro_winkler_config(prefix_scale: 0.2, prefix_max: 6)
  similarity.prefix_scale(cfg) |> should.equal(0.2)
  similarity.prefix_max(cfg) |> should.equal(6)
}

pub fn sorensen_dice_identical_test() {
  similarity.sorensen_dice("abc", "abc", 2) |> should.equal(Ok(1.0))
}

pub fn sorensen_dice_empty_pair_is_one_test() {
  similarity.sorensen_dice("", "", 2) |> should.equal(Ok(1.0))
}

pub fn sorensen_dice_disjoint_is_zero_test() {
  similarity.sorensen_dice("abc", "xyz", 2) |> should.equal(Ok(0.0))
}

pub fn sorensen_dice_one_grapheme_a_a_test() {
  similarity.sorensen_dice("a", "a", 2) |> should.equal(Ok(1.0))
}

pub fn sorensen_dice_one_grapheme_a_b_test() {
  similarity.sorensen_dice("a", "b", 2) |> should.equal(Ok(0.0))
}

pub fn sorensen_dice_night_nacht_test() {
  let assert Ok(score) = similarity.sorensen_dice("night", "nacht", 2)
  approx_equal(score, 0.25) |> should.be_true
}

pub fn sorensen_dice_context_contact_test() {
  let assert Ok(score) = similarity.sorensen_dice("context", "contact", 2)
  approx_equal(score, 0.5) |> should.be_true
}

pub fn sorensen_dice_rejects_zero_n_test() {
  similarity.sorensen_dice("abc", "xyz", 0)
  |> should.equal(Error(NgramSizeInvalid(0)))
}

pub fn sorensen_dice_rejects_negative_n_test() {
  similarity.sorensen_dice("abc", "xyz", -1)
  |> should.equal(Error(NgramSizeInvalid(-1)))
}

// --- sorensen_dice_bigrams / sorensen_dice_trigrams (lenient #6) ---

pub fn sorensen_dice_bigrams_identical_test() {
  similarity.sorensen_dice_bigrams("abc", "abc") |> should.equal(1.0)
}

pub fn sorensen_dice_bigrams_empty_pair_test() {
  similarity.sorensen_dice_bigrams("", "") |> should.equal(1.0)
}

pub fn sorensen_dice_bigrams_disjoint_test() {
  similarity.sorensen_dice_bigrams("abc", "xyz") |> should.equal(0.0)
}

pub fn sorensen_dice_bigrams_night_nacht_test() {
  // Same fixture as sorensen_dice_night_nacht_test — the lenient
  // alias must match the strict variant exactly when n = 2.
  approx_equal(similarity.sorensen_dice_bigrams("night", "nacht"), 0.25)
  |> should.be_true
}

pub fn sorensen_dice_bigrams_matches_strict_test() {
  let assert Ok(strict) = similarity.sorensen_dice("context", "contact", 2)
  similarity.sorensen_dice_bigrams("context", "contact")
  |> should.equal(strict)
}

pub fn sorensen_dice_trigrams_identical_test() {
  similarity.sorensen_dice_trigrams("abcd", "abcd") |> should.equal(1.0)
}

pub fn sorensen_dice_trigrams_matches_strict_test() {
  let assert Ok(strict) = similarity.sorensen_dice("context", "contact", 3)
  similarity.sorensen_dice_trigrams("context", "contact")
  |> should.equal(strict)
}

pub fn sorensen_dice_bigrams_pipes_into_threshold_test() {
  // The lenient signature exists so callers can pipe directly into
  // thresholds. Pin the call-site shape with a trivial threshold
  // helper to make sure the type plumbing stays Float-shaped.
  let threshold = fn(score: Float, t: Float) { score >=. t }
  similarity.sorensen_dice_bigrams("hello", "hello")
  |> threshold(0.5)
  |> should.be_true
}
