import gleam/float
import gleam/list
import gleeunit/should
import textmetrics.{LengthMismatch}

const tolerance = 0.000_001

fn approx_equal(a: Float, b: Float) -> Bool {
  float.absolute_value(a -. b) <=. tolerance
}

pub fn levenshtein_kitten_sitting_test() {
  textmetrics.levenshtein("kitten", "sitting") |> should.equal(3)
}

pub fn levenshtein_saturday_sunday_test() {
  textmetrics.levenshtein("Saturday", "Sunday") |> should.equal(3)
}

pub fn levenshtein_flaw_lawn_test() {
  textmetrics.levenshtein("flaw", "lawn") |> should.equal(2)
}

pub fn levenshtein_gumbo_gambol_test() {
  textmetrics.levenshtein("gumbo", "gambol") |> should.equal(2)
}

pub fn levenshtein_book_back_test() {
  textmetrics.levenshtein("book", "back") |> should.equal(2)
}

pub fn levenshtein_empty_pair_is_zero_test() {
  textmetrics.levenshtein("", "") |> should.equal(0)
}

pub fn levenshtein_empty_left_test() {
  textmetrics.levenshtein("", "abc") |> should.equal(3)
}

pub fn levenshtein_empty_right_test() {
  textmetrics.levenshtein("abc", "") |> should.equal(3)
}

pub fn levenshtein_identical_test() {
  textmetrics.levenshtein("abc", "abc") |> should.equal(0)
}

pub fn levenshtein_a_b_test() {
  textmetrics.levenshtein("a", "b") |> should.equal(1)
}

pub fn levenshtein_ca_abc_test() {
  textmetrics.levenshtein("ca", "abc") |> should.equal(3)
}

pub fn levenshtein_ab_ba_test() {
  textmetrics.levenshtein("ab", "ba") |> should.equal(2)
}

pub fn levenshtein_list_generic_test() {
  textmetrics.levenshtein_list([1, 2, 3], [1, 2, 4]) |> should.equal(1)
  textmetrics.levenshtein_list([], [1, 2]) |> should.equal(2)
  textmetrics.levenshtein_list(["a", "b"], ["a", "b"]) |> should.equal(0)
}

pub fn damerau_ca_abc_is_two_test() {
  textmetrics.damerau_levenshtein("CA", "ABC") |> should.equal(2)
}

pub fn damerau_ab_ba_is_one_test() {
  textmetrics.damerau_levenshtein("ab", "ba") |> should.equal(1)
}

pub fn damerau_abcd_acbd_is_one_test() {
  textmetrics.damerau_levenshtein("abcd", "acbd") |> should.equal(1)
}

pub fn damerau_a_cat_an_act_test() {
  textmetrics.damerau_levenshtein("a cat", "an act") |> should.equal(2)
}

pub fn damerau_empty_test() {
  textmetrics.damerau_levenshtein("", "") |> should.equal(0)
  textmetrics.damerau_levenshtein("", "abc") |> should.equal(3)
  textmetrics.damerau_levenshtein("abc", "") |> should.equal(3)
  textmetrics.damerau_levenshtein("abc", "abc") |> should.equal(0)
}

pub fn osa_ca_abc_is_three_test() {
  textmetrics.optimal_string_alignment("CA", "ABC") |> should.equal(3)
}

pub fn osa_ab_ba_is_one_test() {
  textmetrics.optimal_string_alignment("ab", "ba") |> should.equal(1)
}

pub fn osa_ca_ac_is_one_test() {
  textmetrics.optimal_string_alignment("ca", "ac") |> should.equal(1)
}

pub fn osa_abcd_acbd_is_one_test() {
  textmetrics.optimal_string_alignment("abcd", "acbd") |> should.equal(1)
}

pub fn osa_a_cat_an_act_test() {
  textmetrics.optimal_string_alignment("a cat", "an act") |> should.equal(2)
}

pub fn osa_empty_test() {
  textmetrics.optimal_string_alignment("", "") |> should.equal(0)
  textmetrics.optimal_string_alignment("", "abc") |> should.equal(3)
  textmetrics.optimal_string_alignment("abc", "") |> should.equal(3)
  textmetrics.optimal_string_alignment("abc", "abc") |> should.equal(0)
}

pub fn osa_vs_damerau_separating_witness_test() {
  // OSA counts the same substring edited at most once, so "CA" -> "ABC"
  // is 3 (delete C, insert A, insert B). True Damerau-Levenshtein lets
  // overlapping edits combine: 2 (transpose CA -> AC, insert B).
  textmetrics.levenshtein("CA", "ABC") |> should.equal(3)
  textmetrics.optimal_string_alignment("CA", "ABC") |> should.equal(3)
  textmetrics.damerau_levenshtein("CA", "ABC") |> should.equal(2)
}

pub fn hamming_karolin_kathrin_test() {
  textmetrics.hamming("karolin", "kathrin") |> should.equal(Ok(3))
}

pub fn hamming_karolin_kerstin_test() {
  textmetrics.hamming("karolin", "kerstin") |> should.equal(Ok(3))
}

pub fn hamming_binary_test() {
  textmetrics.hamming("1011101", "1001001") |> should.equal(Ok(2))
}

pub fn hamming_numeric_test() {
  textmetrics.hamming("2173896", "2233796") |> should.equal(Ok(3))
}

pub fn hamming_empty_test() {
  textmetrics.hamming("", "") |> should.equal(Ok(0))
}

pub fn hamming_length_mismatch_test() {
  textmetrics.hamming("a", "")
  |> should.equal(Error(LengthMismatch(left: 1, right: 0)))
  textmetrics.hamming("ab", "abc")
  |> should.equal(Error(LengthMismatch(left: 2, right: 3)))
}

// `normalized_levenshtein` is `1 - levenshtein(a, b) / max(|a|, |b|)`,
// in `[0.0, 1.0]`, with `1.0` meaning identical. Convention for the
// empty-vs-empty case is `1.0`.

pub fn normalized_levenshtein_identical_is_one_test() {
  textmetrics.levenshtein_similarity("abc", "abc") |> should.equal(1.0)
}

pub fn normalized_levenshtein_empty_pair_is_one_test() {
  textmetrics.levenshtein_similarity("", "") |> should.equal(1.0)
}

pub fn normalized_levenshtein_disjoint_single_chars_is_zero_test() {
  textmetrics.levenshtein_similarity("a", "b") |> should.equal(0.0)
}

pub fn normalized_levenshtein_kitten_sitting_test() {
  // levenshtein = 3, max graphemes = 7 → similarity = 1 - 3/7 = 4/7.
  let s = textmetrics.levenshtein_similarity("kitten", "sitting")
  approx_equal(s, 4.0 /. 7.0) |> should.be_true
}

pub fn normalized_levenshtein_one_empty_is_zero_test() {
  textmetrics.levenshtein_similarity("", "abc") |> should.equal(0.0)
  textmetrics.levenshtein_similarity("abc", "") |> should.equal(0.0)
}

pub fn normalized_levenshtein_in_unit_interval_test() {
  let pairs = [
    #("kitten", "sitting"),
    #("café", "cafe"),
    #("a", "ab"),
    #("Saturday", "Sunday"),
    #("flaw", "lawn"),
  ]
  list.each(pairs, fn(p) {
    let #(a, b) = p
    let s = textmetrics.levenshtein_similarity(a, b)
    case s >=. 0.0 && s <=. 1.0 {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn normalized_levenshtein_symmetric_test() {
  let pairs = [
    #("kitten", "sitting"),
    #("CA", "ABC"),
    #("café", "cafe"),
    #("", "abc"),
  ]
  list.each(pairs, fn(p) {
    let #(a, b) = p
    textmetrics.levenshtein_similarity(a, b)
    |> should.equal(textmetrics.levenshtein_similarity(b, a))
  })
}
