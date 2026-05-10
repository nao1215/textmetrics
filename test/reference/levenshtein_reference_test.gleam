//// Spec §12.1 / §12.2: reference values from the original papers and
//// Wikipedia. Every value must pass exactly.

import gleeunit/should
import textmetrics/distance

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

pub fn levenshtein_a_b_test() {
  distance.levenshtein("a", "b") |> should.equal(1)
}

pub fn levenshtein_ca_abc_test() {
  distance.levenshtein("ca", "abc") |> should.equal(3)
}

pub fn levenshtein_ab_ba_test() {
  distance.levenshtein("ab", "ba") |> should.equal(2)
}

pub fn separating_witness_ca_abc_test() {
  // Spec §12.2: this triple distinguishes Damerau-Levenshtein from OSA.
  distance.levenshtein("CA", "ABC") |> should.equal(3)
  distance.osa("CA", "ABC") |> should.equal(3)
  distance.damerau_levenshtein("CA", "ABC") |> should.equal(2)
}
