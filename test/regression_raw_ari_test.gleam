import gleam/float
import gleam/result
import gleeunit/should
import textmetrics.{TooFewWords}

fn assert_close(actual: Float, expected: Float) {
  should.be_true(float.absolute_value(actual -. expected) <=. 0.000_000_000_001)
}

pub fn raw_ari_preserves_negative_formula_result_test() {
  let raw = textmetrics.automated_readability_index("Go.")
  let assert Ok(score) = raw
  score
  |> assert_close(4.71 *. { 2.0 /. 1.0 } +. 0.5 *. { 1.0 /. 1.0 } -. 21.43)
  raw
  |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  |> should.equal(Ok(0.0))
}

pub fn raw_ari_preserves_formula_result_above_eighteen_test() {
  let raw = textmetrics.automated_readability_index("abcdefghij.")
  let assert Ok(score) = raw
  score
  |> assert_close(4.71 *. { 10.0 /. 1.0 } +. 0.5 *. { 1.0 /. 1.0 } -. 21.43)
  raw
  |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  |> should.equal(Ok(18.0))
}

pub fn raw_ari_uses_independently_counted_multiple_sentences_test() {
  let raw =
    textmetrics.automated_readability_index("Bright birds fly. Small cats nap.")
  let assert Ok(score) = raw
  let expected = 4.71 *. { 26.0 /. 6.0 } +. 0.5 *. { 6.0 /. 2.0 } -. 21.43
  score |> assert_close(expected)
  let assert Ok(clamped) =
    raw |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  clamped |> assert_close(expected)
}

pub fn raw_ari_rejects_empty_and_punctuation_only_text_test() {
  textmetrics.automated_readability_index("")
  |> should.equal(Error(TooFewWords(at_least: 1, got: 0)))
  textmetrics.automated_readability_index("...!?")
  |> should.equal(Error(TooFewWords(at_least: 1, got: 0)))
}
