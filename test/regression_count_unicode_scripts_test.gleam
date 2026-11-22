import gleeunit/should
import textmetrics/count

// Letters are General_Category L*, M*, Nd and Nl. Punctuation and
// symbols of every script, other numbers and keycap emoji are not.

pub fn words_katakana_middle_dot_separates_words_test() {
  count.words("カタカナ・テスト") |> should.equal(2)
}

pub fn characters_trade_mark_sign_test() {
  count.characters("™") |> should.equal(0)
}

pub fn characters_enclosed_numbers_test() {
  count.characters("①②⑳") |> should.equal(0)
}

pub fn characters_circled_ideographs_test() {
  count.characters("㊗㊙") |> should.equal(0)
}

pub fn characters_arabic_punctuation_test() {
  count.characters("،؟") |> should.equal(0)
}

pub fn characters_devanagari_dandas_test() {
  count.characters("।॥") |> should.equal(0)
}

pub fn words_keycap_emoji_are_not_words_test() {
  count.words("1️⃣ 2️⃣ #️⃣ go") |> should.equal(1)
}

pub fn characters_emoji_presentation_digit_test() {
  count.characters("9\u{FE0F}") |> should.equal(0)
}

// Counts do not depend on the normalisation form.
pub fn syllables_in_word_nfd_equals_nfc_test() {
  count.syllables_in_word("cafe\u{0301}") |> should.equal(2)
}

pub fn syllables_nfd_equals_nfc_test() {
  count.syllables("re\u{0301}sume\u{0301} cafe\u{0301}")
  |> should.equal(count.syllables("r\u{00E9}sum\u{00E9} caf\u{00E9}"))
}

// Sentence terminators of other scripts end a sentence.
pub fn sentences_ideographic_full_stop_test() {
  count.sentences("こんにちは。元気？") |> should.equal(2)
}

pub fn sentences_full_width_terminators_test() {
  count.sentences("Ｈｉ．Ｂｙｅ！Ｏｋ？") |> should.equal(3)
}

pub fn sentences_devanagari_danda_test() {
  count.sentences("नमस्ते। कैसे हो॥") |> should.equal(2)
}

pub fn sentences_ellipsis_test() {
  count.sentences("Wait… what") |> should.equal(2)
}

// Abbreviation rules stay limited to the ASCII period.
pub fn sentences_full_width_stop_after_abbreviation_test() {
  count.sentences("Mr． Smith") |> should.equal(2)
}
