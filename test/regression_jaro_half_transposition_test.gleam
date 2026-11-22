import gleam/float
import gleam/string
import gleeunit/should
import legacy/v0_9_0
import textmetrics.{Ranked}

fn assert_close(actual: Float, expected: Float) {
  should.be_true(float.absolute_value(actual -. expected) <=. 0.000_000_000_001)
}

pub fn odd_three_mismatches_keep_fractional_transpositions_test() {
  textmetrics.jaro("abcdef", "bcadef") |> assert_close(11.0 /. 12.0)
  v0_9_0.jaro(string.to_graphemes("abcdef"), string.to_graphemes("bcadef"))
  |> assert_close(11.0 /. 12.0)
  textmetrics.jaro("bcadef", "abcdef") |> assert_close(11.0 /. 12.0)
}

pub fn odd_mismatches_without_prefix_do_not_receive_winkler_boost_test() {
  {
    textmetrics.jaro_winkler(
      "abcdef",
      "bcadef",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> assert_close(11.0 /. 12.0)
}

pub fn prefixed_odd_mismatches_keep_fractional_transpositions_test() {
  textmetrics.jaro("xabcdef", "xbcadef") |> assert_close(13.0 /. 14.0)
  v0_9_0.jaro(string.to_graphemes("xabcdef"), string.to_graphemes("xbcadef"))
  |> assert_close(13.0 /. 14.0)
  textmetrics.jaro("xbcadef", "xabcdef") |> assert_close(13.0 /. 14.0)
}

pub fn default_winkler_boost_uses_fractional_jaro_score_test() {
  {
    textmetrics.jaro_winkler(
      "xabcdef",
      "xbcadef",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> assert_close(131.0 /. 140.0)
  {
    textmetrics.jaro_winkler(
      "xbcadef",
      "xabcdef",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> assert_close(131.0 /. 140.0)
}

pub fn two_mismatches_keep_one_transposition_test() {
  textmetrics.jaro("abcdef", "bacdef") |> assert_close(17.0 /. 18.0)
  {
    textmetrics.jaro_winkler(
      "abcdef",
      "bacdef",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> assert_close(17.0 /. 18.0)
}

pub fn four_mismatches_keep_two_transpositions_test() {
  textmetrics.jaro("abcdef", "badcef") |> assert_close(8.0 /. 9.0)
  {
    textmetrics.jaro_winkler(
      "abcdef",
      "badcef",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> assert_close(8.0 /. 9.0)
}

pub fn repeated_letters_with_three_mismatches_use_fractional_score_test() {
  textmetrics.jaro("aabcdef", "abcadef") |> assert_close(13.0 /. 14.0)
  textmetrics.jaro("abcadef", "aabcdef") |> assert_close(13.0 /. 14.0)
  {
    textmetrics.jaro_winkler(
      "aabcdef",
      "abcadef",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> assert_close(131.0 /. 140.0)
}

pub fn repeated_letters_do_not_reuse_matches_test() {
  textmetrics.jaro("aabbcc", "ab") |> assert_close(7.0 /. 9.0)
  textmetrics.jaro("ab", "aabbcc") |> assert_close(7.0 /. 9.0)
  {
    textmetrics.jaro_winkler("aabbcc", "ab", prefix_scale: 0.1, prefix_max: 4)
    |> should.be_ok
  }
  |> assert_close(4.0 /. 5.0)
}

pub fn empty_identical_and_unmatched_scores_remain_defined_test() {
  textmetrics.jaro("", "") |> should.equal(1.0)
  textmetrics.jaro("", "a") |> should.equal(0.0)
  textmetrics.jaro("a", "") |> should.equal(0.0)
  textmetrics.jaro("aaaa", "aaaa") |> should.equal(1.0)
  textmetrics.jaro("abc", "xyz") |> should.equal(0.0)
  {
    textmetrics.jaro_winkler("", "", prefix_scale: 0.1, prefix_max: 4)
    |> should.be_ok
  }
  |> should.equal(1.0)
  {
    textmetrics.jaro_winkler("", "a", prefix_scale: 0.1, prefix_max: 4)
    |> should.be_ok
  }
  |> should.equal(0.0)
  {
    textmetrics.jaro_winkler("a", "", prefix_scale: 0.1, prefix_max: 4)
    |> should.be_ok
  }
  |> should.equal(0.0)
}

pub fn ranking_uses_corrected_scores_and_preserves_real_ties_test() {
  let ranked =
    textmetrics.rank_jaro_winkler(
      "xabcdef",
      ["xbcadef", "xbacdef", "xcabdef"],
      3,
    )
  let assert [
    Ranked(label: "xbacdef", score: first),
    Ranked(label: "xbcadef", score: second),
    Ranked(label: "xcabdef", score: third),
  ] = ranked
  first |> assert_close(67.0 /. 70.0)
  second |> assert_close(131.0 /. 140.0)
  third |> assert_close(131.0 /. 140.0)
}
