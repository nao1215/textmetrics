//// Jaro counts transpositions as half the mismatched matched pairs,
//// rounded down, as Winkler's strcmp95 reference code and the rapidfuzz,
//// jellyfish, and textdistance libraries do. 0.11.0 kept the fraction
//// and so disagreed with all of them whenever the mismatch count was odd.

import gleam/float
import gleam/string
import gleeunit/should
import legacy/v0_9_0
import textmetrics.{Ranked}

fn assert_close(actual: Float, expected: Float) {
  should.be_true(float.absolute_value(actual -. expected) <=. 0.000_000_000_001)
}

fn jaro_winkler(left: String, right: String) -> Float {
  textmetrics.jaro_winkler(left, right, prefix_scale: 0.1, prefix_max: 4)
  |> should.be_ok
}

pub fn three_mismatches_count_as_one_transposition_test() {
  textmetrics.jaro("abcdef", "bcadef") |> assert_close(17.0 /. 18.0)
  v0_9_0.jaro(string.to_graphemes("abcdef"), string.to_graphemes("bcadef"))
  |> assert_close(17.0 /. 18.0)
  textmetrics.jaro("bcadef", "abcdef") |> assert_close(17.0 /. 18.0)
  jaro_winkler("abcdef", "bcadef") |> assert_close(17.0 /. 18.0)
}

pub fn prefixed_three_mismatches_match_rapidfuzz_test() {
  textmetrics.jaro("xabcdef", "xbcadef") |> assert_close(20.0 /. 21.0)
  textmetrics.jaro("xbcadef", "xabcdef") |> assert_close(20.0 /. 21.0)
  jaro_winkler("xabcdef", "xbcadef") |> assert_close(67.0 /. 70.0)
  jaro_winkler("xbcadef", "xabcdef") |> assert_close(67.0 /. 70.0)
}

pub fn differential_pairs_match_rapidfuzz_and_jellyfish_test() {
  // Values from rapidfuzz 3.14 and jellyfish 1.3.
  textmetrics.jaro("bdab", "daabcbbc") |> assert_close(0.75)
  textmetrics.jaro("cacabb", "abacabba") |> assert_close(271.0 /. 360.0)
  textmetrics.jaro("aabcdef", "abcadef") |> assert_close(20.0 /. 21.0)
  textmetrics.jaro("abcadef", "aabcdef") |> assert_close(20.0 /. 21.0)
  jaro_winkler("aabcdef", "abcadef") |> assert_close(67.0 /. 70.0)
}

pub fn even_mismatches_are_unchanged_test() {
  textmetrics.jaro("abcdef", "bacdef") |> assert_close(17.0 /. 18.0)
  jaro_winkler("abcdef", "bacdef") |> assert_close(17.0 /. 18.0)
  textmetrics.jaro("abcdef", "badcef") |> assert_close(8.0 /. 9.0)
  jaro_winkler("abcdef", "badcef") |> assert_close(8.0 /. 9.0)
}

pub fn repeated_letters_do_not_reuse_matches_test() {
  textmetrics.jaro("aabbcc", "ab") |> assert_close(7.0 /. 9.0)
  textmetrics.jaro("ab", "aabbcc") |> assert_close(7.0 /. 9.0)
  jaro_winkler("aabbcc", "ab") |> assert_close(4.0 /. 5.0)
}

pub fn empty_identical_and_unmatched_scores_remain_defined_test() {
  textmetrics.jaro("", "") |> should.equal(1.0)
  textmetrics.jaro("", "a") |> should.equal(0.0)
  textmetrics.jaro("a", "") |> should.equal(0.0)
  textmetrics.jaro("aaaa", "aaaa") |> should.equal(1.0)
  textmetrics.jaro("abc", "xyz") |> should.equal(0.0)
  jaro_winkler("", "") |> should.equal(1.0)
  jaro_winkler("", "a") |> should.equal(0.0)
  jaro_winkler("a", "") |> should.equal(0.0)
}

pub fn ranking_keeps_input_order_for_tied_scores_test() {
  // rapidfuzz gives all three candidates 67/70.
  let ranked =
    textmetrics.rank_jaro_winkler(
      "xabcdef",
      ["xbcadef", "xbacdef", "xcabdef"],
      3,
    )
  let assert [
    Ranked(label: "xbcadef", score: first),
    Ranked(label: "xbacdef", score: second),
    Ranked(label: "xcabdef", score: third),
  ] = ranked
  first |> assert_close(67.0 /. 70.0)
  second |> assert_close(67.0 /. 70.0)
  third |> assert_close(67.0 /. 70.0)
}
