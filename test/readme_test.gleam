//// The functions in this file are the exact snippets shown in
//// `README.md`. Tests assert that each snippet still produces the
//// documented output, so README examples cannot drift from the
//// implementation.

import gleam/list
import gleam/result
import gleeunit/should
import textmetrics/diff
import textmetrics/distance.{LengthMismatch}
import textmetrics/edit
import textmetrics/lcs
import textmetrics/search
import textmetrics/similarity

// ---------------------------------------------------------------------
// Suggesting a similar command name
// ---------------------------------------------------------------------

pub fn suggest_command(typed: String) -> List(String) {
  let known = ["install", "uninstall", "remove", "update", "help"]
  search.did_you_mean(typed, known, 2)
}

pub fn readme_suggest_command_test() {
  suggest_command("instal") |> should.equal(["install"])
  suggest_command("updat") |> should.equal(["update"])
  suggest_command("xyz") |> should.equal([])
}

// ---------------------------------------------------------------------
// Comparing strings: Levenshtein, Damerau-Levenshtein, OSA
// ---------------------------------------------------------------------

pub fn distances() -> #(Int, Int, Int) {
  let l = distance.levenshtein("CA", "ABC")
  let dl = distance.damerau_levenshtein("CA", "ABC")
  let o = distance.osa("CA", "ABC")
  #(l, dl, o)
}

pub fn readme_distances_test() {
  distances() |> should.equal(#(3, 2, 3))
}

// ---------------------------------------------------------------------
// Hamming requires equal-length inputs
// ---------------------------------------------------------------------

pub fn hamming_check(a: String, b: String) -> Result(Int, distance.HammingError) {
  distance.hamming(a, b)
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
  similarity.jaro("MARTHA", "MARHTA")
}

pub fn jaro_winkler_score() -> Float {
  similarity.jaro_winkler("MARTHA", "MARHTA")
}

pub fn dice_score() -> Result(Float, similarity.SorensenDiceError) {
  similarity.sorensen_dice("night", "nacht", 2)
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

pub fn aggressive_winkler() -> Result(Float, similarity.JaroWinklerConfigError) {
  use cfg <- result.map(similarity.jaro_winkler_config(
    prefix_scale: 0.2,
    prefix_max: 6,
  ))
  similarity.jaro_winkler_with("MARTHA", "MARHTA", cfg)
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
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  diff.to_unified(diff.myers(old, new), opts)
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
  let script = diff.myers(old, new)
  edit.recover_old(script) == old && edit.recover_new(script) == new
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
  #(lcs.length(a, b), lcs.sequence(a, b))
}

pub fn readme_lcs_test() {
  let #(len, seq) = lcs_example()
  len |> should.equal(4)
  list.length(seq) |> should.equal(4)
}
