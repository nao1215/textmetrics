import gleeunit/should
import textmetrics/count

// Every code point above U+007F used to count as a letter, so dashes,
// curly quotes, the ellipsis, emoji, no-break and ideographic spaces and
// full-width punctuation all made words and characters.

pub fn words_em_dash_is_not_a_word_test() {
  count.words("hello — world") |> should.equal(2)
}

pub fn words_no_break_space_separates_words_test() {
  count.words("a\u{00A0}b") |> should.equal(2)
}

pub fn words_em_space_separates_words_test() {
  count.words("a\u{2003}b") |> should.equal(2)
}

pub fn words_curly_quotes_and_ellipsis_test() {
  count.words("“Hi,” she said …") |> should.equal(3)
}

pub fn words_emoji_are_not_words_test() {
  count.words("🎉 party 🎉 👍🏽 🇯🇵") |> should.equal(1)
}

pub fn words_full_width_punctuation_separates_words_test() {
  count.words("こんにちは。世界！") |> should.equal(2)
}

pub fn characters_skip_punctuation_symbols_and_emoji_test() {
  count.characters("— … 🎉 “” ¿¡ © ×") |> should.equal(0)
}

// Real letters above ASCII still count.
pub fn words_accented_and_cjk_letters_unchanged_test() {
  count.words("café naïve Ünïcödé 日本語 한국어 ª º") |> should.equal(7)
}

pub fn characters_accented_and_cjk_letters_unchanged_test() {
  count.characters("café日本語") |> should.equal(7)
}

pub fn characters_iteration_mark_is_a_letter_test() {
  count.characters("人々") |> should.equal(2)
}

// "\r\n" is one grapheme and is whitespace, so it does not start a
// trailing sentence fragment.
pub fn sentences_crlf_is_whitespace_test() {
  count.sentences("Hello.\r\n") |> should.equal(1)
}

pub fn sentences_ideographic_space_is_whitespace_test() {
  count.sentences("Hello.\u{3000}") |> should.equal(1)
}

pub fn paragraphs_ideographic_space_line_is_blank_test() {
  count.paragraphs("a\n\u{3000}\nb") |> should.equal(2)
}
