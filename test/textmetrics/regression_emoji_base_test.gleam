import gleam/float
import gleam/list
import gleeunit/should
import textmetrics

fn assert_close(actual: Float, expected: Float) {
  should.be_true(float.absolute_value(actual -. expected) <=. 0.000_000_000_001)
}

fn assert_retained(text: String) {
  #(
    textmetrics.count_words(text),
    textmetrics.count_characters(text),
    textmetrics.count_syllables(text),
    textmetrics.count_syllables_in_word(text),
  )
  |> should.equal(#(1, 1, 1, 1))
}

pub fn ascii_letters_with_variation_selector_are_retained_test() {
  list.each(["a\u{FE0F}", "Z\u{FE0F}"], assert_retained)
}

pub fn ascii_letters_with_enclosing_keycap_are_retained_test() {
  list.each(["a\u{20E3}", "Z\u{20E3}", "a\u{FE0F}\u{20E3}"], assert_retained)
}

pub fn greek_letter_with_enclosing_keycap_is_retained_test() {
  assert_retained("α\u{20E3}")
}

pub fn non_ascii_decimal_digit_with_enclosing_keycap_is_retained_test() {
  assert_retained("١\u{20E3}")
}

pub fn non_emoji_letter_graphemes_do_not_split_a_word_test() {
  list.each(["a\u{FE0F}", "a\u{20E3}", "α\u{20E3}", "١\u{20E3}"], fn(g) {
    let text = "x" <> g <> "y"
    #(textmetrics.count_words(text), textmetrics.count_characters(text))
    |> should.equal(#(1, 3))
  })
}

pub fn ascii_digit_emoji_exclusions_keep_word_boundaries_test() {
  list.each(
    ["1\u{FE0F}\u{20E3}", "9\u{20E3}", "9\u{FE0F}", "9\u{301}\u{FE0F}"],
    fn(g) {
      #(
        textmetrics.count_words(g),
        textmetrics.count_characters(g),
        textmetrics.count_syllables(g),
        textmetrics.count_syllables_in_word(g),
      )
      |> should.equal(#(0, 0, 0, 1))
      let text = "x" <> g <> "y"
      #(
        textmetrics.count_words(text),
        textmetrics.count_characters(text),
        textmetrics.count_syllables(text),
      )
      |> should.equal(#(2, 2, 2))
    },
  )
}

pub fn plain_digits_and_standalone_marks_remain_letter_like_test() {
  list.each(["9", "١", "\u{301}", "\u{FE0F}", "\u{20E3}"], assert_retained)
}

pub fn keycap_punctuation_stays_outside_words_test() {
  list.each(["#\u{FE0F}\u{20E3}", "*\u{FE0F}\u{20E3}"], fn(text) {
    #(textmetrics.count_words(text), textmetrics.count_characters(text))
    |> should.equal(#(0, 0))
  })
}

pub fn retained_grapheme_after_period_keeps_the_word_continuation_test() {
  textmetrics.count_sentences("x.a\u{FE0F}") |> should.equal(1)
}

pub fn retained_word_reaches_the_raw_ari_formula_test() {
  let assert Ok(score) = textmetrics.automated_readability_index("a\u{FE0F}")
  // One character, one word, one sentence: 4.71 + 0.5 - 21.43.
  assert_close(score, -16.22)
}

pub fn retained_word_reaches_the_flesch_syllable_formula_test() {
  let assert Ok(score) = textmetrics.flesch_reading_ease("a\u{20E3}")
  // One word, one sentence, one fallback syllable.
  assert_close(score, 121.22)
}

pub fn retained_word_preserves_neighboring_polysyllables_test() {
  let text = "banana a\u{FE0F} banana"
  #(
    textmetrics.count_words(text),
    textmetrics.count_characters(text),
    textmetrics.count_syllables(text),
    textmetrics.count_polysyllables(text),
  )
  |> should.equal(#(3, 13, 7, 2))
  let assert Ok(score) = textmetrics.flesch_reading_ease(text)
  // 206.835 - 1.015 * 3 - 84.6 * (7 / 3).
  assert_close(score, 6.39)
}
