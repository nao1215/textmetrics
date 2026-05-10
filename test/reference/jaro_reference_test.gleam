//// Reference values from Winkler (1990) and Wikipedia's
//// "Jaro-Winkler distance" article. Tolerance: 1.0e-6.

import gleam/float
import gleeunit/should
import textmetrics/similarity

const tolerance = 0.000_001

fn approx_equal(actual: Float, expected: Float) -> Bool {
  float.absolute_value(actual -. expected) <=. tolerance
}

pub fn jaro_martha_marhta_test() {
  let score = similarity.jaro("MARTHA", "MARHTA")
  approx_equal(score, 0.944_444_444) |> should.be_true
}

pub fn jaro_dixon_dicksonx_test() {
  let score = similarity.jaro("DIXON", "DICKSONX")
  approx_equal(score, 0.766_666_666) |> should.be_true
}

pub fn jaro_jellyfish_smellyfish_test() {
  let score = similarity.jaro("JELLYFISH", "SMELLYFISH")
  approx_equal(score, 0.896_296_296) |> should.be_true
}

pub fn jaro_dwayne_duane_test() {
  let score = similarity.jaro("DWAYNE", "DUANE")
  approx_equal(score, 0.822_222_222) |> should.be_true
}

pub fn jaro_winkler_martha_marhta_test() {
  let score = similarity.jaro_winkler("MARTHA", "MARHTA")
  approx_equal(score, 0.961_111_111) |> should.be_true
}

pub fn jaro_winkler_dixon_dicksonx_test() {
  let score = similarity.jaro_winkler("DIXON", "DICKSONX")
  approx_equal(score, 0.813_333_333) |> should.be_true
}

pub fn jaro_winkler_jellyfish_smellyfish_test() {
  let score = similarity.jaro_winkler("JELLYFISH", "SMELLYFISH")
  approx_equal(score, 0.896_296_296) |> should.be_true
}

pub fn jaro_winkler_dwayne_duane_test() {
  let score = similarity.jaro_winkler("DWAYNE", "DUANE")
  approx_equal(score, 0.84) |> should.be_true
}
