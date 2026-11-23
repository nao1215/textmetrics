import gleam/float
import gleam/list
import gleam/string
import gleeunit/should
import textmetrics

fn assert_close(actual: Float, expected: Float) {
  should.be_true(float.absolute_value(actual -. expected) <=. 0.000_000_000_001)
}

pub fn cn_after_period_does_not_suppress_sentence_boundary_test() {
  textmetrics.count_sentences("a.\u{FDD0}b") |> should.equal(2)
}

pub fn cn_between_polysyllables_preserves_both_words_test() {
  let text = "banana\u{FDD0}banana"
  #(
    textmetrics.count_words(text),
    textmetrics.count_polysyllables(text),
    textmetrics.count_syllables(text),
  )
  |> should.equal(#(2, 2, 6))
}

pub fn cn_sentence_boundaries_reach_the_thirty_sentence_smog_gate_test() {
  let text = string.repeat("a.\u{FDD0}b. ", 15)
  let assert Ok(score) = textmetrics.smog(text)
  // Thirty one-syllable words, thirty sentences, no polysyllables.
  assert_close(score, 3.1291)
  #(
    textmetrics.count_words(text),
    textmetrics.count_sentences(text),
    textmetrics.count_polysyllables(text),
  )
  |> should.equal(#(30, 30, 0))
}

pub fn cn_sentence_boundary_reaches_the_raw_flesch_formula_test() {
  let assert Ok(score) = textmetrics.flesch_reading_ease("a.\u{FDD0}b")
  // 206.835 - 1.015 * (2 / 2) - 84.6 * (2 / 2).
  assert_close(score, 121.22)
}

pub fn nonempty_cn_has_no_word_but_keeps_sentence_and_word_fallback_test() {
  let text = "\u{FDD0}"
  #(
    textmetrics.count_words(text),
    textmetrics.count_sentences(text),
    textmetrics.count_syllables_in_word(text),
  )
  |> should.equal(#(0, 1, 1))
}

pub fn unicode_17_first_last_ranges_include_interior_and_last_test() {
  // Extension I start/interior/end, Extension J (new in 17.0) start/end,
  // and a Hangul syllable range interior.
  list.each(
    [
      "\u{2EBF0}",
      "\u{2EBF1}",
      "\u{2EE5D}",
      "\u{31350}",
      "\u{33479}",
      "\u{AC01}",
    ],
    fn(text) {
      #(textmetrics.count_words(text), textmetrics.count_characters(text))
      |> should.equal(#(1, 1))
    },
  )
}

pub fn unicode_17_classifies_letters_assigned_after_15_1_test() {
  // U+1C89 (16.0) and U+088F (17.0) were unassigned in 15.1.
  list.each(["\u{1C89}", "\u{088F}"], fn(text) {
    #(textmetrics.count_words(text), textmetrics.count_characters(text))
    |> should.equal(#(1, 1))
  })
}

pub fn unicode_17_unassigned_code_points_separate_words_test() {
  list.each(["\u{1C8B}", "\u{2EE5E}", "\u{3347A}"], fn(text) {
    #(textmetrics.count_words(text), textmetrics.count_characters(text))
    |> should.equal(#(0, 0))
  })
}
