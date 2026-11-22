import gleam/string
import gleeunit/should
import textmetrics

fn assert_counts(text: String, words: Int, characters: Int, syllables: Int) {
  textmetrics.count_words(text) |> should.equal(words)
  textmetrics.count_characters(text) |> should.equal(characters)
  textmetrics.count_syllables(text) |> should.equal(syllables)
}

fn noncharacter_ffff() -> String {
  // Gleam 1.14 emits a literal U+FFFF that OTP 27's lexer rejects.
  let assert Ok(codepoint) = string.utf_codepoint(0xffff)
  string.from_utf_codepoints([codepoint])
}

pub fn fdd0_noncharacter_is_not_a_word_test() {
  assert_counts("\u{FDD0}", 0, 0, 0)
}

pub fn fdd0_noncharacter_separates_words_test() {
  assert_counts("a\u{FDD0}b", 2, 2, 2)
}

pub fn ffff_noncharacter_is_not_a_word_test() {
  assert_counts(noncharacter_ffff(), 0, 0, 0)
}

pub fn ffff_noncharacter_separates_words_test() {
  assert_counts("a" <> noncharacter_ffff() <> "b", 2, 2, 2)
}

pub fn unassigned_greek_codepoint_is_not_a_word_test() {
  assert_counts("\u{0378}", 0, 0, 0)
}

pub fn unassigned_greek_codepoint_separates_words_test() {
  assert_counts("a\u{0378}b", 2, 2, 2)
}

pub fn cn_runs_at_word_edges_do_not_add_words_or_characters_test() {
  assert_counts("\u{FDD0}" <> noncharacter_ffff() <> "\u{0378}", 0, 0, 0)
  assert_counts(
    "\u{FDD0}" <> noncharacter_ffff() <> "a\u{0378}\u{FDD0}",
    1,
    1,
    1,
  )
}

pub fn assigned_greek_neighbors_remain_letter_like_test() {
  assert_counts("\u{0377}", 1, 1, 1)
  assert_counts("\u{0379}", 0, 0, 0)
  assert_counts("\u{037A}", 1, 1, 1)
}

pub fn letters_marks_decimal_digits_and_letter_numbers_remain_counted_test() {
  assert_counts("α", 1, 1, 1)
  assert_counts("\u{0301}", 1, 1, 1)
  assert_counts("\u{0661}", 1, 1, 1)
  assert_counts("\u{2160}", 1, 1, 1)
}

pub fn punctuation_symbols_and_other_numbers_remain_excluded_test() {
  assert_counts(".", 0, 0, 0)
  assert_counts("+", 0, 0, 0)
  assert_counts("²", 0, 0, 0)
  assert_counts("a.b+c²d", 4, 4, 4)
}

pub fn syllables_in_word_keeps_nonempty_fallback_for_cn_test() {
  textmetrics.count_syllables_in_word("\u{FDD0}") |> should.equal(1)
  textmetrics.count_syllables_in_word(noncharacter_ffff()) |> should.equal(1)
  textmetrics.count_syllables_in_word("\u{0378}") |> should.equal(1)
}

pub fn syllables_in_word_keeps_other_fallbacks_and_empty_zero_test() {
  textmetrics.count_syllables_in_word("123") |> should.equal(1)
  textmetrics.count_syllables_in_word("日本") |> should.equal(1)
  textmetrics.count_syllables_in_word("!!!") |> should.equal(1)
  textmetrics.count_syllables_in_word("") |> should.equal(0)
}
