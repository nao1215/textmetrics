//// The functions in this file are the exact snippets shown in
//// `README.md`. Tests assert that each snippet still produces the
//// documented output, so README examples cannot drift from the
//// implementation.

import gleam/list
import gleeunit/should
import textmetrics.{LengthMismatch}

// ---------------------------------------------------------------------
// Suggesting a similar command name
// ---------------------------------------------------------------------

pub fn suggest_command(typed: String) -> List(String) {
  let known = ["install", "uninstall", "remove", "update", "help"]
  textmetrics.did_you_mean(typed, known, 2)
}

pub fn readme_suggest_command_test() {
  suggest_command("instal") |> should.equal(["install"])
  suggest_command("updat") |> should.equal(["update"])
  suggest_command("xyz") |> should.equal([])
}

pub fn one_suggestion(typed: String) -> Result(String, Nil) {
  let known = ["install", "uninstall", "remove", "update", "help"]
  { textmetrics.did_you_mean(typed, known, 2) |> list.first }
}

pub fn readme_one_suggestion_test() {
  one_suggestion("instal") |> should.equal(Ok("install"))
  one_suggestion("xyz") |> should.equal(Error(Nil))
}

// ---------------------------------------------------------------------
// Comparing strings: Levenshtein, Damerau-Levenshtein, OSA
// ---------------------------------------------------------------------

pub fn distances() -> #(Int, Int, Int) {
  let l = textmetrics.levenshtein("CA", "ABC")
  let dl = textmetrics.damerau_levenshtein("CA", "ABC")
  let o = textmetrics.optimal_string_alignment("CA", "ABC")
  #(l, dl, o)
}

pub fn readme_distances_test() {
  distances() |> should.equal(#(3, 2, 3))
}

pub fn levenshtein_similarity() -> Float {
  // levenshtein = 3, max graphemes = 7 → 1 - 3/7 = 4/7.
  textmetrics.levenshtein_similarity("kitten", "sitting")
}

pub fn readme_levenshtein_similarity_test() {
  let s = levenshtein_similarity()
  case s >. 0.571 && s <. 0.572 {
    True -> Nil
    False -> should.fail()
  }
}

// ---------------------------------------------------------------------
// Hamming requires equal-length inputs
// ---------------------------------------------------------------------

pub fn hamming_check(
  a: String,
  b: String,
) -> Result(Int, textmetrics.HammingError) {
  textmetrics.hamming(a, b)
}

pub fn readme_hamming_test() {
  hamming_check("karolin", "kathrin") |> should.equal(Ok(3))
  hamming_check("ab", "abc")
  |> should.equal(Error(LengthMismatch(left: 2, right: 3)))
}

// ---------------------------------------------------------------------
// Similarity scores
// ---------------------------------------------------------------------

pub fn jaro_score() -> Float {
  textmetrics.jaro("MARTHA", "MARHTA")
}

pub fn jaro_winkler_score() -> Float {
  {
    textmetrics.jaro_winkler(
      "MARTHA",
      "MARHTA",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
}

pub fn dice_score() -> Result(Float, Nil) {
  textmetrics.sorensen_dice("night", "nacht", ngram_size: 2)
}

pub fn readme_similarity_test() {
  let j = jaro_score()
  case j >. 0.944_44 && j <. 0.944_45 {
    True -> Nil
    False -> should.fail()
  }
  let jw = jaro_winkler_score()
  case jw >. 0.961_11 && jw <. 0.961_12 {
    True -> Nil
    False -> should.fail()
  }
  dice_score() |> should.equal(Ok(0.25))
}

// ---------------------------------------------------------------------
// Custom Jaro-Winkler parameters
// ---------------------------------------------------------------------

pub fn aggressive_winkler() -> Result(Float, textmetrics.JaroWinklerError) {
  textmetrics.jaro_winkler("MARTHA", "MARHTA", prefix_scale: 0.2, prefix_max: 6)
}

pub fn readme_aggressive_winkler_test() {
  let assert Ok(score) = aggressive_winkler()
  case score >=. 0.0 && score <=. 1.0 {
    True -> Nil
    False -> should.fail()
  }
}

// ---------------------------------------------------------------------
// Producing a unified diff
// ---------------------------------------------------------------------

pub fn render_diff() -> String {
  let old = ["the quick brown", "fox jumps over", "the lazy dog"]
  let new = ["the quick brown", "fox leaps over", "the lazy dog"]

  {
    textmetrics.to_unified(
      textmetrics.myers(old, new),
      old_name: "a",
      new_name: "b",
      context_lines: 3,
    )
    |> should.be_ok
  }
}

pub fn readme_render_diff_test() {
  let expected =
    "--- a
+++ b
@@ -1,3 +1,3 @@
 the quick brown
-fox jumps over
+fox leaps over
 the lazy dog
"
  render_diff() |> should.equal(expected)
}

// ---------------------------------------------------------------------
// Edit-script round trip
// ---------------------------------------------------------------------

pub fn round_trip_holds() -> Bool {
  let old = ["a", "b", "c"]
  let new = ["a", "x", "c"]
  let script = textmetrics.myers(old, new)
  textmetrics.recover_old(script) == old
  && textmetrics.recover_new(script) == new
}

pub fn readme_round_trip_test() {
  round_trip_holds() |> should.be_true
}

// ---------------------------------------------------------------------
// Longest common subsequence
// ---------------------------------------------------------------------

pub fn lcs_example() -> #(Int, List(String)) {
  let a = ["A", "B", "C", "B", "D", "A", "B"]
  let b = ["B", "D", "C", "A", "B", "A"]
  #(
    textmetrics.longest_common_subsequence_length(a, b),
    textmetrics.longest_common_subsequence(a, b),
  )
}

pub fn readme_lcs_test() {
  let #(len, seq) = lcs_example()
  len |> should.equal(4)
  list.length(seq) |> should.equal(4)
}
