import gleam/string
import gleeunit/should
import textmetrics

// Every period of a long token used to rebuild the whole token, which
// made dotted text quadratic: 40 KB of "a." took more than 10 seconds.

pub fn sentences_long_dotted_token_test() {
  textmetrics.count_sentences(string.repeat("a.", 100_000)) |> should.equal(1)
}

// Each "a." ends a sentence before the ",", and the last "," is a
// trailing fragment.
pub fn sentences_long_token_with_period_and_comma_test() {
  textmetrics.count_sentences(string.repeat("a.,", 100_000))
  |> should.equal(100_001)
}
