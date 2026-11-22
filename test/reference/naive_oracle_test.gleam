//// Differential tests against textbook definitions.
////
//// The library computes the distances with rolling rows and a
//// dictionary-backed matrix. The oracles below are the plain recursive
//// definitions, exponential but obviously correct on inputs of up to
//// six graphemes, so any disagreement points at the optimised code.

import gleam/int
import gleam/list
import gleam/string
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range
import textmetrics
import textmetrics/internal/unicode

/// Short strings over a small alphabet, plus a multi-code-point
/// grapheme, so repeated letters and transpositions are common.
fn word_generator() -> Generator(String) {
  generator.list_of(
    generator.element_of(["a", "b", "c", "é", "e\u{0301}", "👍🏽"]),
    range.constant(0, 6),
  )
  |> generator.map(string.concat)
}

fn pair_generator() -> Generator(#(String, String)) {
  generator.tuple2(word_generator(), word_generator())
}

/// The string functions compare NFC graphemes (README, Unicode policy).
fn nfc_graphemes(s: String) -> List(String) {
  string.to_graphemes(unicode.to_nfc(s))
}

fn naive_levenshtein(a: List(String), b: List(String)) -> Int {
  case a, b {
    [], _ -> list.length(b)
    _, [] -> list.length(a)
    [x, ..xs], [y, ..ys] -> {
      let cost = case x == y {
        True -> 0
        False -> 1
      }
      int.min(
        naive_levenshtein(xs, ys) + cost,
        int.min(naive_levenshtein(xs, b) + 1, naive_levenshtein(a, ys) + 1),
      )
    }
  }
}

/// Optimal string alignment: Levenshtein plus the swap of two adjacent
/// graphemes, where no substring is edited more than once.
fn naive_osa(a: List(String), b: List(String)) -> Int {
  case a, b {
    [], _ -> list.length(b)
    _, [] -> list.length(a)
    [x, ..xs], [y, ..ys] -> {
      let cost = case x == y {
        True -> 0
        False -> 1
      }
      let plain =
        int.min(
          naive_osa(xs, ys) + cost,
          int.min(naive_osa(xs, b) + 1, naive_osa(a, ys) + 1),
        )
      case a, b {
        [x1, x2, ..xs2], [y1, y2, ..ys2] if x1 == y2 && x2 == y1 && x1 != x2 ->
          int.min(plain, naive_osa(xs2, ys2) + 1)
        _, _ -> plain
      }
    }
  }
}

fn naive_lcs_length(a: List(String), b: List(String)) -> Int {
  case a, b {
    [], _ | _, [] -> 0
    [x, ..xs], [y, ..ys] ->
      case x == y {
        True -> naive_lcs_length(xs, ys) + 1
        False -> int.max(naive_lcs_length(xs, b), naive_lcs_length(a, ys))
      }
  }
}

pub fn levenshtein_matches_the_recursive_definition_test() -> Nil {
  metamon.forall(pair_generator(), fn(pair) {
    let #(a, b) = pair
    textmetrics.levenshtein(a, b)
    == naive_levenshtein(nfc_graphemes(a), nfc_graphemes(b))
  })
}

pub fn osa_matches_the_recursive_definition_test() -> Nil {
  metamon.forall(pair_generator(), fn(pair) {
    let #(a, b) = pair
    textmetrics.optimal_string_alignment(a, b)
    == naive_osa(nfc_graphemes(a), nfc_graphemes(b))
  })
}

/// True Damerau-Levenshtein may edit a transposed pair again, so it is
/// never above OSA, never above Levenshtein, and at least half of
/// Levenshtein (one swap replaces at most two substitutions).
pub fn damerau_levenshtein_is_bounded_by_osa_and_levenshtein_test() -> Nil {
  metamon.forall(pair_generator(), fn(pair) {
    let #(a, b) = pair
    let dl = textmetrics.damerau_levenshtein(a, b)
    let lev = textmetrics.levenshtein(a, b)
    dl <= textmetrics.optimal_string_alignment(a, b)
    && dl <= lev
    && 2 * dl >= lev
  })
}

pub fn lcs_length_matches_the_recursive_definition_test() -> Nil {
  metamon.forall(pair_generator(), fn(pair) {
    let #(a, b) = pair
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    textmetrics.longest_common_subsequence_length(ga, gb)
    == naive_lcs_length(ga, gb)
  })
}

pub fn lcs_sequence_is_a_common_subsequence_of_maximal_length_test() -> Nil {
  metamon.forall(pair_generator(), fn(pair) {
    let #(a, b) = pair
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    let seq = textmetrics.longest_common_subsequence(ga, gb)
    is_subsequence(seq, ga)
    && is_subsequence(seq, gb)
    && list.length(seq) == naive_lcs_length(ga, gb)
  })
}

fn is_subsequence(sub: List(String), of: List(String)) -> Bool {
  case sub, of {
    [], _ -> True
    _, [] -> False
    [s, ..ss], [o, ..os] ->
      case s == o {
        True -> is_subsequence(ss, os)
        False -> is_subsequence(sub, os)
      }
  }
}
