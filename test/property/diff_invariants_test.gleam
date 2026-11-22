//// Spec §13.3 / §13.4 / §13.6: diff round-trip, optimality, and
//// edit-script consistency over a curated set of input pairs.

import gleam/list
import gleam/string
import gleeunit/should
import textmetrics.{Delete, Equal, Insert}

const string_pairs: List(#(String, String)) = [
  #("", ""),
  #("a", "b"),
  #("kitten", "sitting"),
  #("Saturday", "Sunday"),
  #("flaw", "lawn"),
  #("gumbo", "gambol"),
  #("book", "back"),
  #("ca", "abc"),
  #("ab", "ba"),
  #("abc", "abc"),
  #("café", "cafe"),
  #("あいう", "あえう"),
  #("가나다", "가나"),
]

const line_pairs: List(#(List(String), List(String))) = [
  #([], []),
  #([], ["a"]),
  #(["a"], []),
  #(["a", "b", "c"], ["a", "b", "c"]),
  #(["a", "b", "c"], ["a", "x", "c"]),
  #(["the quick brown", "fox jumps over", "the lazy dog"], [
    "the quick brown",
    "fox leaps over",
    "the lazy dog",
  ]),
  #(["one", "two", "three"], ["zero", "one", "two", "three", "four"]),
  #(["a", "a", "a"], ["a", "a"]),
]

fn count_kind(script: List(textmetrics.Edit(a)), kind: String) -> Int {
  list.fold(script, 0, fn(acc, e) {
    case e, kind {
      Equal(_), "equal" -> acc + 1
      Delete(_), "delete" -> acc + 1
      Insert(_), "insert" -> acc + 1
      _, _ -> acc
    }
  })
}

pub fn myers_round_trip_string_graphemes_test() {
  list.each(string_pairs, fn(pair) {
    let #(a, b) = pair
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    let script = textmetrics.myers(ga, gb)
    textmetrics.recover_old(script) |> should.equal(ga)
    textmetrics.recover_new(script) |> should.equal(gb)
  })
}

pub fn myers_round_trip_lines_test() {
  list.each(line_pairs, fn(pair) {
    let #(old, new) = pair
    let script = textmetrics.myers(old, new)
    textmetrics.recover_old(script) |> should.equal(old)
    textmetrics.recover_new(script) |> should.equal(new)
  })
}

pub fn patience_round_trip_test() {
  list.each(line_pairs, fn(pair) {
    let #(old, new) = pair
    let script = textmetrics.patience(old, new)
    textmetrics.recover_old(script) |> should.equal(old)
    textmetrics.recover_new(script) |> should.equal(new)
  })
}

pub fn myers_optimality_against_lcs_test() {
  // Spec §13.4: the cost of an optimal Myers script equals
  // |old| + |new| - 2 · |LCS(old, new)|.
  list.each(line_pairs, fn(pair) {
    let #(old, new) = pair
    let script = textmetrics.myers(old, new)
    let expected =
      list.length(old)
      + list.length(new)
      - 2
      * textmetrics.longest_common_subsequence_length(old, new)
    textmetrics.edit_cost(script) |> should.equal(expected)
  })
}

pub fn myers_optimality_string_graphemes_test() {
  list.each(string_pairs, fn(pair) {
    let #(a, b) = pair
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    let script = textmetrics.myers(ga, gb)
    let expected =
      list.length(ga)
      + list.length(gb)
      - 2
      * textmetrics.longest_common_subsequence_length(ga, gb)
    textmetrics.edit_cost(script) |> should.equal(expected)
    // Sanity: id-only cost is bounded above by 2 × Levenshtein.
    case textmetrics.edit_cost(script) <= 2 * textmetrics.levenshtein(a, b) {
      True -> Nil
      False -> should.fail()
    }
  })
}

pub fn edit_script_consistency_test() {
  list.each(line_pairs, fn(pair) {
    let #(old, new) = pair
    let script = textmetrics.myers(old, new)
    let equals = count_kind(script, "equal")
    let inserts = count_kind(script, "insert")
    let deletes = count_kind(script, "delete")
    list.length(old) |> should.equal(equals + deletes)
    list.length(new) |> should.equal(equals + inserts)
    textmetrics.edit_cost(script) |> should.equal(inserts + deletes)
  })
}
