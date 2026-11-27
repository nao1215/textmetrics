import gleam/float
import gleeunit/should
import textmetrics.{PrefixMaxNegative, PrefixScaleOutOfRange}

const tolerance = 0.000_001

fn approx_equal(actual: Float, expected: Float) -> Bool {
  float.absolute_value(actual -. expected) <=. tolerance
}

pub fn jaro_empty_pair_is_one_test() {
  textmetrics.jaro("", "") |> should.equal(1.0)
}

pub fn jaro_empty_left_is_zero_test() {
  textmetrics.jaro("", "abc") |> should.equal(0.0)
}

pub fn jaro_empty_right_is_zero_test() {
  textmetrics.jaro("abc", "") |> should.equal(0.0)
}

pub fn jaro_identical_is_one_test() {
  textmetrics.jaro("abc", "abc") |> should.equal(1.0)
}

pub fn jaro_single_char_match_test() {
  textmetrics.jaro("a", "a") |> should.equal(1.0)
}

pub fn jaro_single_char_mismatch_test() {
  textmetrics.jaro("a", "b") |> should.equal(0.0)
}

pub fn jaro_winkler_empty_pair_is_one_test() {
  {
    textmetrics.jaro_winkler("", "", prefix_scale: 0.1, prefix_max: 4)
    |> should.be_ok
  }
  |> should.equal(1.0)
}

pub fn jaro_winkler_identical_is_one_test() {
  {
    textmetrics.jaro_winkler("abc", "abc", prefix_scale: 0.1, prefix_max: 4)
    |> should.be_ok
  }
  |> should.equal(1.0)
}

pub fn jaro_winkler_no_common_prefix_equals_jaro_test() {
  // JELLYFISH vs SMELLYFISH share no prefix, so jw == j.
  let j = textmetrics.jaro("JELLYFISH", "SMELLYFISH")
  let jw = {
    textmetrics.jaro_winkler(
      "JELLYFISH",
      "SMELLYFISH",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  approx_equal(jw, j) |> should.be_true
}

pub fn jaro_winkler_parameters_accepts_valid_test() {
  textmetrics.jaro_winkler("MARTHA", "MARHTA", prefix_scale: 0.1, prefix_max: 4)
  |> should.be_ok
  textmetrics.jaro_winkler("MARTHA", "MARHTA", prefix_scale: 0.0, prefix_max: 0)
  |> should.be_ok
  textmetrics.jaro_winkler(
    "MARTHA",
    "MARHTA",
    prefix_scale: 0.25,
    prefix_max: 10,
  )
  |> should.be_ok
}

pub fn jaro_winkler_parameters_rejects_high_scale_test() {
  textmetrics.jaro_winkler(
    "MARTHA",
    "MARHTA",
    prefix_scale: 0.26,
    prefix_max: 4,
  )
  |> should.equal(Error(PrefixScaleOutOfRange(0.26)))
}

pub fn jaro_winkler_parameters_rejects_negative_scale_test() {
  textmetrics.jaro_winkler(
    "MARTHA",
    "MARHTA",
    prefix_scale: -0.01,
    prefix_max: 4,
  )
  |> should.equal(Error(PrefixScaleOutOfRange(-0.01)))
}

pub fn jaro_winkler_parameters_rejects_negative_max_test() {
  textmetrics.jaro_winkler(
    "MARTHA",
    "MARHTA",
    prefix_scale: 0.1,
    prefix_max: -1,
  )
  |> should.equal(Error(PrefixMaxNegative(-1)))
}

pub fn sorensen_dice_identical_test() {
  textmetrics.sorensen_dice("abc", "abc", ngram_size: 2)
  |> should.equal(Ok(1.0))
}

pub fn sorensen_dice_empty_pair_is_one_test() {
  textmetrics.sorensen_dice("", "", ngram_size: 2) |> should.equal(Ok(1.0))
}

pub fn sorensen_dice_disjoint_is_zero_test() {
  textmetrics.sorensen_dice("abc", "xyz", ngram_size: 2)
  |> should.equal(Ok(0.0))
}

pub fn sorensen_dice_one_grapheme_a_a_test() {
  textmetrics.sorensen_dice("a", "a", ngram_size: 2) |> should.equal(Ok(1.0))
}

pub fn sorensen_dice_one_grapheme_a_b_test() {
  textmetrics.sorensen_dice("a", "b", ngram_size: 2) |> should.equal(Ok(0.0))
}

pub fn sorensen_dice_night_nacht_test() {
  let assert Ok(score) =
    textmetrics.sorensen_dice("night", "nacht", ngram_size: 2)
  approx_equal(score, 0.25) |> should.be_true
}

pub fn sorensen_dice_context_contact_test() {
  let assert Ok(score) =
    textmetrics.sorensen_dice("context", "contact", ngram_size: 2)
  approx_equal(score, 0.5) |> should.be_true
}

pub fn sorensen_dice_rejects_zero_n_test() {
  textmetrics.sorensen_dice("abc", "xyz", ngram_size: 0)
  |> should.equal(Error(Nil))
}

pub fn sorensen_dice_rejects_negative_n_test() {
  textmetrics.sorensen_dice("abc", "xyz", ngram_size: -1)
  |> should.equal(Error(Nil))
}

// --- Sørensen-Dice n-gram fixtures ---

pub fn sorensen_dice_bigrams_identical_test() {
  { textmetrics.sorensen_dice("abc", "abc", ngram_size: 2) |> should.be_ok }
  |> should.equal(1.0)
}

pub fn sorensen_dice_bigrams_empty_pair_test() {
  { textmetrics.sorensen_dice("", "", ngram_size: 2) |> should.be_ok }
  |> should.equal(1.0)
}

pub fn sorensen_dice_bigrams_disjoint_test() {
  { textmetrics.sorensen_dice("abc", "xyz", ngram_size: 2) |> should.be_ok }
  |> should.equal(0.0)
}

pub fn sorensen_dice_bigrams_night_nacht_test() {
  // One shared bigram out of four on each side.
  approx_equal(
    {
      textmetrics.sorensen_dice("night", "nacht", ngram_size: 2) |> should.be_ok
    },
    0.25,
  )
  |> should.be_true
}

pub fn sorensen_dice_context_contact_bigrams_test() {
  // co, on, nt are shared; each side has six bigrams.
  textmetrics.sorensen_dice("context", "contact", ngram_size: 2)
  |> should.equal(Ok(0.5))
}

pub fn sorensen_dice_trigrams_identical_test() {
  { textmetrics.sorensen_dice("abcd", "abcd", ngram_size: 3) |> should.be_ok }
  |> should.equal(1.0)
}

pub fn sorensen_dice_context_contact_trigrams_test() {
  // con, ont are shared; each side has five trigrams.
  textmetrics.sorensen_dice("context", "contact", ngram_size: 3)
  |> should.equal(Ok(0.4))
}

pub fn sorensen_dice_bigrams_pipes_into_threshold_test() {
  // Inspect a valid score after handling the Result.
  let threshold = fn(score: Float, t: Float) { score >=. t }
  { textmetrics.sorensen_dice("hello", "hello", ngram_size: 2) |> should.be_ok }
  |> threshold(0.5)
  |> should.be_true
}

pub fn sorensen_dice_counts_the_one_ngram_of_a_string_of_length_n_test() {
  // "ab" has exactly one bigram; it is shared with "abc" (ab, bc).
  let assert Ok(score) = textmetrics.sorensen_dice("ab", "abc", ngram_size: 2)
  approx_equal(score, 2.0 /. 3.0) |> should.be_true
}

pub fn sorensen_dice_counts_a_repeated_ngram_once_per_occurrence_test() -> Nil {
  // "abab" has the bigrams ab, ba, ab and "ab" has ab: one shared bigram
  // out of four.
  assert textmetrics.sorensen_dice("abab", "ab", ngram_size: 2) == Ok(0.5)
  assert textmetrics.sorensen_dice("abab", "abab", ngram_size: 2) == Ok(1.0)
}
