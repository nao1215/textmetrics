import gleam/float
import gleam/result
import gleeunit/should
import textmetrics.{Delete, DeleteRun, Equal, EqualRun, Insert, InsertRun}

fn assert_close(actual: Float, expected: Float) {
  should.be_true(float.absolute_value(actual -. expected) <=. 0.000_000_000_001)
}

// "banana." has 1 word, 1 sentence, 6 characters, 3 syllables and
// 1 polysyllabic word. The expected constants below are hand-calculated.
fn assert_raw_and_clamped(
  calculate: fn(String) -> Result(Float, textmetrics.ReadabilityError),
  expected: Float,
  clamped: Float,
  maximum: Float,
) {
  let score_result = calculate("banana.")
  let assert Ok(raw) = score_result
  assert_close(raw, expected)
  let assert Ok(displayed) =
    score_result |> result.map(float.clamp(_, min: 0.0, max: maximum))
  assert_close(displayed, clamped)
}

pub fn canonical_flesch_keeps_negative_raw_and_caller_clamp_test() {
  // 206.835 - 1.015 - 84.6 * 3.
  assert_raw_and_clamped(textmetrics.flesch_reading_ease, -47.98, 0.0, 100.0)
}

pub fn canonical_flesch_kincaid_keeps_raw_above_eighteen_test() {
  // 0.39 + 11.8 * 3 - 15.59.
  assert_raw_and_clamped(textmetrics.flesch_kincaid_grade, 20.2, 18.0, 18.0)
}

pub fn canonical_gunning_fog_keeps_raw_above_eighteen_test() {
  // 0.4 * (1 + 100).
  assert_raw_and_clamped(textmetrics.gunning_fog, 40.4, 18.0, 18.0)
}

pub fn canonical_ari_keeps_direct_formula_and_caller_composition_test() {
  // 4.71 * 6 + 0.5 - 21.43. Other regressions cover out-of-range ARI.
  assert_raw_and_clamped(
    textmetrics.automated_readability_index,
    7.33,
    7.33,
    18.0,
  )
}

pub fn canonical_coleman_liau_keeps_negative_raw_and_caller_clamp_test() {
  // 0.0588 * 600 - 0.296 * 100 - 15.8.
  assert_raw_and_clamped(textmetrics.coleman_liau_index, -10.12, 0.0, 18.0)
}

pub fn generic_list_algorithms_keep_integer_elements_test() {
  let old = [1, 2, 3]
  let new = [1, 4, 3]
  textmetrics.levenshtein_list(old, new) |> should.equal(1)
  textmetrics.longest_common_subsequence_length(old, new) |> should.equal(2)
  textmetrics.longest_common_subsequence(old, new) |> should.equal([1, 3])
  let script = textmetrics.myers(old, new)
  textmetrics.recover_old(script) |> should.equal(old)
  textmetrics.recover_new(script) |> should.equal(new)
  textmetrics.edit_cost(script) |> should.equal(2)
}

type Token {
  Token(id: Int, text: String)
}

pub fn generic_records_use_raw_equality_and_keep_edit_run_elements_test() {
  let composed = Token(1, "Á")
  let decomposed = Token(1, "A\u{0301}")
  let tail = Token(2, "tail")
  let old = [composed, tail]
  let new = [decomposed, tail]
  textmetrics.levenshtein_list(old, new) |> should.equal(1)
  textmetrics.longest_common_subsequence_length(old, new) |> should.equal(1)
  textmetrics.longest_common_subsequence(old, new) |> should.equal([tail])
  let diff = textmetrics.myers(old, new)
  textmetrics.recover_old(diff) |> should.equal(old)
  textmetrics.recover_new(diff) |> should.equal(new)
  textmetrics.edit_cost(diff) |> should.equal(2)
  // A literal script checks run grouping without constraining Myers ties.
  let script = [Delete(composed), Insert(decomposed), Equal(tail)]
  textmetrics.edit_runs(script)
  |> should.equal([
    DeleteRun([composed]),
    InsertRun([decomposed]),
    EqualRun([tail]),
  ])
}
