import gleeunit/should
import textmetrics/distance.{LengthMismatch}

pub fn levenshtein_kitten_sitting_test() {
  distance.levenshtein("kitten", "sitting") |> should.equal(3)
}

pub fn levenshtein_saturday_sunday_test() {
  distance.levenshtein("Saturday", "Sunday") |> should.equal(3)
}

pub fn levenshtein_flaw_lawn_test() {
  distance.levenshtein("flaw", "lawn") |> should.equal(2)
}

pub fn levenshtein_gumbo_gambol_test() {
  distance.levenshtein("gumbo", "gambol") |> should.equal(2)
}

pub fn levenshtein_book_back_test() {
  distance.levenshtein("book", "back") |> should.equal(2)
}

pub fn levenshtein_empty_pair_is_zero_test() {
  distance.levenshtein("", "") |> should.equal(0)
}

pub fn levenshtein_empty_left_test() {
  distance.levenshtein("", "abc") |> should.equal(3)
}

pub fn levenshtein_empty_right_test() {
  distance.levenshtein("abc", "") |> should.equal(3)
}

pub fn levenshtein_identical_test() {
  distance.levenshtein("abc", "abc") |> should.equal(0)
}

pub fn levenshtein_a_b_test() {
  distance.levenshtein("a", "b") |> should.equal(1)
}

pub fn levenshtein_ca_abc_test() {
  distance.levenshtein("ca", "abc") |> should.equal(3)
}

pub fn levenshtein_ab_ba_test() {
  distance.levenshtein("ab", "ba") |> should.equal(2)
}

pub fn levenshtein_list_generic_test() {
  distance.levenshtein_list([1, 2, 3], [1, 2, 4]) |> should.equal(1)
  distance.levenshtein_list([], [1, 2]) |> should.equal(2)
  distance.levenshtein_list(["a", "b"], ["a", "b"]) |> should.equal(0)
}

pub fn damerau_ca_abc_is_two_test() {
  distance.damerau_levenshtein("CA", "ABC") |> should.equal(2)
}

pub fn damerau_ab_ba_is_one_test() {
  distance.damerau_levenshtein("ab", "ba") |> should.equal(1)
}

pub fn damerau_abcd_acbd_is_one_test() {
  distance.damerau_levenshtein("abcd", "acbd") |> should.equal(1)
}

pub fn damerau_a_cat_an_act_test() {
  distance.damerau_levenshtein("a cat", "an act") |> should.equal(2)
}

pub fn damerau_empty_test() {
  distance.damerau_levenshtein("", "") |> should.equal(0)
  distance.damerau_levenshtein("", "abc") |> should.equal(3)
  distance.damerau_levenshtein("abc", "") |> should.equal(3)
  distance.damerau_levenshtein("abc", "abc") |> should.equal(0)
}

pub fn osa_ca_abc_is_three_test() {
  distance.osa("CA", "ABC") |> should.equal(3)
}

pub fn osa_ab_ba_is_one_test() {
  distance.osa("ab", "ba") |> should.equal(1)
}

pub fn osa_ca_ac_is_one_test() {
  distance.osa("ca", "ac") |> should.equal(1)
}

pub fn osa_abcd_acbd_is_one_test() {
  distance.osa("abcd", "acbd") |> should.equal(1)
}

pub fn osa_a_cat_an_act_test() {
  distance.osa("a cat", "an act") |> should.equal(2)
}

pub fn osa_empty_test() {
  distance.osa("", "") |> should.equal(0)
  distance.osa("", "abc") |> should.equal(3)
  distance.osa("abc", "") |> should.equal(3)
  distance.osa("abc", "abc") |> should.equal(0)
}

pub fn osa_vs_damerau_separating_witness_test() {
  // OSA counts the same substring edited at most once, so "CA" -> "ABC"
  // is 3 (delete C, insert A, insert B). True Damerau-Levenshtein lets
  // overlapping edits combine: 2 (transpose CA -> AC, insert B).
  distance.levenshtein("CA", "ABC") |> should.equal(3)
  distance.osa("CA", "ABC") |> should.equal(3)
  distance.damerau_levenshtein("CA", "ABC") |> should.equal(2)
}

pub fn hamming_karolin_kathrin_test() {
  distance.hamming("karolin", "kathrin") |> should.equal(Ok(3))
}

pub fn hamming_karolin_kerstin_test() {
  distance.hamming("karolin", "kerstin") |> should.equal(Ok(3))
}

pub fn hamming_binary_test() {
  distance.hamming("1011101", "1001001") |> should.equal(Ok(2))
}

pub fn hamming_numeric_test() {
  distance.hamming("2173896", "2233796") |> should.equal(Ok(3))
}

pub fn hamming_empty_test() {
  distance.hamming("", "") |> should.equal(Ok(0))
}

pub fn hamming_length_mismatch_test() {
  distance.hamming("a", "")
  |> should.equal(Error(LengthMismatch(left: 1, right: 0)))
  distance.hamming("ab", "abc")
  |> should.equal(Error(LengthMismatch(left: 2, right: 3)))
}
