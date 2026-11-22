//// Spec §13.2: range, identity, symmetry, and Jaro-Winkler floor/cap
//// over a curated set of inputs.

import gleam/list
import gleeunit/should
import textmetrics

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
    case in_range(textmetrics.jaro(a, b)) {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn jaro_winkler_in_range_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    case
      in_range({
        textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
        |> should.be_ok
      })
    {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn sorensen_dice_in_range_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    let assert Ok(score) = textmetrics.sorensen_dice(a, b, ngram_size: 2)
    case in_range(score) {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn jaro_identity_test() {
  list.each(non_empty_cases, fn(s) {
    textmetrics.jaro(s, s) |> should.equal(1.0)
  })
  textmetrics.jaro("", "") |> should.equal(1.0)
}

pub fn jaro_winkler_identity_test() {
  list.each(non_empty_cases, fn(s) {
    {
      textmetrics.jaro_winkler(s, s, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    }
    |> should.equal(1.0)
  })
  {
    textmetrics.jaro_winkler("", "", prefix_scale: 0.1, prefix_max: 4)
    |> should.be_ok
  }
  |> should.equal(1.0)
}

pub fn jaro_symmetry_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    textmetrics.jaro(a, b) |> should.equal(textmetrics.jaro(b, a))
  })
}

pub fn jaro_winkler_symmetry_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    {
      textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    }
    |> should.equal({
      textmetrics.jaro_winkler(b, a, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    })
  })
}

pub fn sorensen_dice_symmetry_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    let assert Ok(ab) = textmetrics.sorensen_dice(a, b, ngram_size: 2)
    let assert Ok(ba) = textmetrics.sorensen_dice(b, a, ngram_size: 2)
    ab |> should.equal(ba)
  })
}

pub fn jaro_winkler_floor_test() {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    let j = textmetrics.jaro(a, b)
    let jw = {
      textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    }
    case jw +. 1.0e-9 >=. j {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn jaro_winkler_cap_long_prefix_test() {
  // Strings sharing more than `prefix_max` graphemes still cap at 1.0.
  let score = {
    textmetrics.jaro_winkler(
      "AAAAAAAAAA",
      "AAAAAAAAAA",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  score |> should.equal(1.0)
  let bounded = {
    textmetrics.jaro_winkler(
      "AAAAAAAAAB",
      "AAAAAAAAAC",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  case bounded <=. 1.0 && bounded >=. 0.0 {
    True -> Nil
    False -> should.fail()
  }
}
