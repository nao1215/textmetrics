//// Spec §13.1: metric axioms over a curated set of inputs. The
//// inputs cover empty strings, identical strings, single graphemes,
//// transposition shapes, multibyte / grapheme-cluster characters, and
//// inputs of different lengths.

import gleam/list
import gleam/string
import gleeunit/should
import textmetrics/distance

const cases: List(#(String, String)) = [
  #("", ""),
  #("a", ""),
  #("", "abc"),
  #("a", "a"),
  #("a", "b"),
  #("ab", "ba"),
  #("ca", "ac"),
  #("ca", "abc"),
  #("kitten", "sitting"),
  #("Saturday", "Sunday"),
  #("flaw", "lawn"),
  #("gumbo", "gambol"),
  #("abcd", "acbd"),
  #("a cat", "an act"),
  #("café", "cafe"),
  #("あいう", "あえう"),
  #("가나다", "가나"),
]

fn each(f: fn(String, String) -> Nil) -> Nil {
  list.each(cases, fn(pair) {
    let #(a, b) = pair
    f(a, b)
  })
}

pub fn levenshtein_non_negative_test() {
  use a, b <- each
  case distance.levenshtein(a, b) >= 0 {
    True -> Nil
    False -> should.fail()
  }
}

pub fn levenshtein_identity_test() {
  use a, _ <- each
  distance.levenshtein(a, a) |> should.equal(0)
}

pub fn levenshtein_symmetry_test() {
  use a, b <- each
  let lhs = distance.levenshtein(a, b)
  let rhs = distance.levenshtein(b, a)
  lhs |> should.equal(rhs)
}

pub fn damerau_symmetry_test() {
  use a, b <- each
  distance.damerau_levenshtein(a, b)
  |> should.equal(distance.damerau_levenshtein(b, a))
}

pub fn osa_symmetry_test() {
  use a, b <- each
  distance.osa(a, b) |> should.equal(distance.osa(b, a))
}

pub fn levenshtein_upper_bound_test() {
  use a, b <- each
  let d = distance.levenshtein(a, b)
  let bound = case
    list.length(string.to_graphemes(a)) >= list.length(string.to_graphemes(b))
  {
    True -> list.length(string.to_graphemes(a))
    False -> list.length(string.to_graphemes(b))
  }
  case d <= bound {
    True -> Nil
    False -> should.fail()
  }
}

pub fn osa_lower_bound_against_levenshtein_test() {
  use a, b <- each
  case distance.osa(a, b) <= distance.levenshtein(a, b) {
    True -> Nil
    False -> should.fail()
  }
}

pub fn damerau_lower_bound_against_osa_test() {
  use a, b <- each
  case distance.damerau_levenshtein(a, b) <= distance.osa(a, b) {
    True -> Nil
    False -> should.fail()
  }
}

const triangle_triples: List(#(String, String, String)) = [
  #("kitten", "sitting", "fitting"),
  #("abc", "xyz", "abz"),
  #("flaw", "lawn", "fawn"),
  #("", "abc", "abcd"),
  #("a", "ab", "abc"),
  #("café", "cafe", "fade"),
]

pub fn levenshtein_triangle_inequality_test() {
  list.each(triangle_triples, fn(triple) {
    let #(a, b, c) = triple
    let ac = distance.levenshtein(a, c)
    let ab = distance.levenshtein(a, b)
    let bc = distance.levenshtein(b, c)
    case ac <= ab + bc {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn damerau_triangle_inequality_test() {
  list.each(triangle_triples, fn(triple) {
    let #(a, b, c) = triple
    let ac = distance.damerau_levenshtein(a, c)
    let ab = distance.damerau_levenshtein(a, b)
    let bc = distance.damerau_levenshtein(b, c)
    case ac <= ab + bc {
      True -> Nil
      False -> should.fail()
    }
  })
}

const equal_length_pairs: List(#(String, String)) = [
  #("karolin", "kathrin"),
  #("karolin", "kerstin"),
  #("1011101", "1001001"),
  #("abc", "abc"),
  #("", ""),
  #("가나다", "가나라"),
]

pub fn hamming_at_least_levenshtein_test() {
  list.each(equal_length_pairs, fn(pair) {
    let #(a, b) = pair
    let assert Ok(h) = distance.hamming(a, b)
    let l = distance.levenshtein(a, b)
    case h >= l {
      True -> Nil
      False -> should.fail()
    }
  })
}
