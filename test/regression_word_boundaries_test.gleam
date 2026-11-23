//// Word boundaries follow the UAX #29 rules that keep a word together
//// across an apostrophe or period between letters (WB6, WB7), across a
//// comma or period between digits (WB11, WB12), and across format
//// characters such as the soft hyphen (WB4). Before, `don't` was the two
//// words `don` and `t`, which inflated word counts for readability.

import gleam/float
import gleam/list
import gleeunit/should
import textmetrics

fn words(text: String) -> Int {
  textmetrics.count_words(text)
}

pub fn apostrophes_between_letters_keep_one_word_test() {
  words("don't stop") |> should.equal(2)
  words("it\u{2019}s here") |> should.equal(2)
  words("rock'n'roll") |> should.equal(1)
  words("O'Brien said") |> should.equal(2)
}

pub fn apostrophes_at_word_edges_still_separate_test() {
  words("James' book") |> should.equal(2)
  words("'quoted'") |> should.equal(1)
  words("a'' b") |> should.equal(2)
}

pub fn periods_between_letters_keep_one_word_test() {
  words("U.S.A. rocks") |> should.equal(2)
  words("e.g. this") |> should.equal(2)
  words("example.com works") |> should.equal(2)
  words("a..b") |> should.equal(2)
}

pub fn separators_between_digits_keep_one_number_test() {
  words("3.50 dollars") |> should.equal(2)
  words("1,000 people") |> should.equal(2)
  words("x1.5") |> should.equal(1)
  words("10:30") |> should.equal(2)
  words("a.1") |> should.equal(2)
  words("1, 2") |> should.equal(2)
}

pub fn hyphens_and_other_punctuation_still_separate_test() {
  words("e-mail me") |> should.equal(3)
  words("x_y") |> should.equal(2)
  words("a/b") |> should.equal(2)
}

pub fn format_characters_do_not_split_a_word_test() {
  let text = "co\u{00AD}operate"
  words(text) |> should.equal(1)
  textmetrics.count_characters(text) |> should.equal(9)
  words("a\u{2060}b") |> should.equal(1)
  words("\u{200E}word") |> should.equal(1)
  words("\u{00AD}") |> should.equal(0)
}

pub fn joined_words_reach_syllables_and_readability_test() {
  textmetrics.count_syllables("don't") |> should.equal(1)
  textmetrics.count_syllables("I don't know.") |> should.equal(3)
  textmetrics.count_polysyllables("it's beautiful") |> should.equal(1)
  let assert Ok(score) = textmetrics.flesch_reading_ease("I don't know.")
  // 206.835 - 1.015 * (3 / 1) - 84.6 * (3 / 3).
  should.be_true(float.absolute_value(score -. 119.19) <. 0.000_000_001)
}

pub fn characters_still_count_letters_only_test() {
  list.each(
    [#("don't", 4), #("3.50", 3), #("U.S.A.", 3), #("co\u{00AD}op", 4)],
    fn(pair) { textmetrics.count_characters(pair.0) |> should.equal(pair.1) },
  )
}

pub fn other_uax29_number_separators_join_digits_test() {
  words("1;2;3") |> should.equal(1)
  words("1'000") |> should.equal(1)
  words("a;b") |> should.equal(2)
}

pub fn word_break_numeric_outside_digit_categories_counts_as_digit_test() {
  // U+066B ARABIC DECIMAL SEPARATOR is Word_Break=Numeric.
  words("\u{0663}\u{066B}\u{0665}") |> should.equal(1)
  // U+0600 ARABIC NUMBER SIGN is Prepend, so it starts the digits' grapheme.
  words("\u{0600}\u{0661}\u{0662}\u{0663}") |> should.equal(1)
}
