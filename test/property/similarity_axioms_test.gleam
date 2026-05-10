//// Spec §13.2: range, identity, symmetry, and Jaro-Winkler floor/cap
//// over a curated set of inputs.

import gleam/list
import gleeunit/should
import textmetrics/similarity

const cases: List(#(String, String)) = [
  #("", ""),
  #("a", "a"),
  #("a", "b"),
  #("abc", "abc"),
  #("abc", "xyz"),
  #("MARTHA", "MARHTA"),
  #("DIXON", "DICKSONX"),
  #("DWAYNE", "DUANE"),
  #("JELLYFISH", "SMELLYFISH"),
  #("café", "cafe"),
  #("あいう", "あえう"),
]

const non_empty_cases: List(String) = [
  "a", "abc", "MARTHA", "DIXON", "JELLYFISH", "café", "あいう",
]

fn in_range(score: Float) -> Bool {
  score >=. 0.0 && score <=. 1.0
}

pub fn jaro_in_range_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    case in_range(similarity.jaro(a, b)) {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn jaro_winkler_in_range_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    case in_range(similarity.jaro_winkler(a, b)) {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn sorensen_dice_in_range_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    let assert Ok(score) = similarity.sorensen_dice(a, b, 2)
    case in_range(score) {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn jaro_identity_test() {
  list.each(non_empty_cases, fn(s) {
    similarity.jaro(s, s) |> should.equal(1.0)
  })
  similarity.jaro("", "") |> should.equal(1.0)
}

pub fn jaro_winkler_identity_test() {
  list.each(non_empty_cases, fn(s) {
    similarity.jaro_winkler(s, s) |> should.equal(1.0)
  })
  similarity.jaro_winkler("", "") |> should.equal(1.0)
}

pub fn jaro_symmetry_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    similarity.jaro(a, b) |> should.equal(similarity.jaro(b, a))
  })
}

pub fn jaro_winkler_symmetry_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    similarity.jaro_winkler(a, b)
    |> should.equal(similarity.jaro_winkler(b, a))
  })
}

pub fn sorensen_dice_symmetry_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    let assert Ok(ab) = similarity.sorensen_dice(a, b, 2)
    let assert Ok(ba) = similarity.sorensen_dice(b, a, 2)
    ab |> should.equal(ba)
  })
}

pub fn jaro_winkler_floor_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    let j = similarity.jaro(a, b)
    let jw = similarity.jaro_winkler(a, b)
    case jw +. 1.0e-9 >=. j {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn jaro_winkler_cap_long_prefix_test() {
  // Strings sharing more than `prefix_max` graphemes still cap at 1.0.
  let score = similarity.jaro_winkler("AAAAAAAAAA", "AAAAAAAAAA")
  score |> should.equal(1.0)
  let bounded = similarity.jaro_winkler("AAAAAAAAAB", "AAAAAAAAAC")
  case bounded <=. 1.0 && bounded >=. 0.0 {
    True -> Nil
    False -> should.fail()
  }
}
