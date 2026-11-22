//// Spec §12.1 / §12.2: reference values from the original papers and
//// Wikipedia. Every value must pass exactly.

import gleeunit/should
import textmetrics

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

pub fn levenshtein_a_b_test() {
  textmetrics.levenshtein("a", "b") |> should.equal(1)
}

pub fn levenshtein_ca_abc_test() {
  textmetrics.levenshtein("ca", "abc") |> should.equal(3)
}

pub fn levenshtein_ab_ba_test() {
  textmetrics.levenshtein("ab", "ba") |> should.equal(2)
}

pub fn separating_witness_ca_abc_test() {
  // Spec §12.2: this triple distinguishes Damerau-Levenshtein from OSA.
  textmetrics.levenshtein("CA", "ABC") |> should.equal(3)
  textmetrics.optimal_string_alignment("CA", "ABC") |> should.equal(3)
  textmetrics.damerau_levenshtein("CA", "ABC") |> should.equal(2)
}
