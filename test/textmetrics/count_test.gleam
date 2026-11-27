import gleeunit/should
import textmetrics

// --- words --------------------------------------------------------------

pub fn words_empty_test() -> Nil {
  textmetrics.count_words("")
  |> should.equal(0)
}

pub fn words_single_test() -> Nil {
  textmetrics.count_words("hello")
  |> should.equal(1)
}

pub fn words_two_test() -> Nil {
  textmetrics.count_words("hello world")
  |> should.equal(2)
}

pub fn words_punctuation_test() -> Nil {
  textmetrics.count_words("hello, world!")
  |> should.equal(2)
}

pub fn words_collapses_whitespace_test() -> Nil {
  textmetrics.count_words("hello   world")
  |> should.equal(2)
}

pub fn words_handles_newlines_test() -> Nil {
  textmetrics.count_words("hello\nworld")
  |> should.equal(2)
}

pub fn words_cjk_with_space_test() -> Nil {
  // Two whitespace-separated tokens, each a CJK + Katakana run.
  textmetrics.count_words("日本語 テスト")
  |> should.equal(2)
}

// --- sentences ----------------------------------------------------------

pub fn sentences_empty_test() -> Nil {
  textmetrics.count_sentences("")
  |> should.equal(0)
}

pub fn sentences_single_test() -> Nil {
  textmetrics.count_sentences("Hello.")
  |> should.equal(1)
}

pub fn sentences_two_test() -> Nil {
  textmetrics.count_sentences("Hello. World.")
  |> should.equal(2)
}

pub fn sentences_consecutive_terminators_test() -> Nil {
  // !! and ? collapse into single boundaries → two sentences.
  textmetrics.count_sentences("Hello!! World?")
  |> should.equal(2)
}

pub fn sentences_no_terminator_still_counts_test() -> Nil {
  textmetrics.count_sentences("Hello, world")
  |> should.equal(1)
}

pub fn sentences_recognises_mr_abbreviation_test() -> Nil {
  // Issue #19: common English abbreviations no longer over-segment.
  textmetrics.count_sentences("Mr. Smith went home.")
  |> should.equal(1)
}

pub fn sentences_whitespace_only_input_test() -> Nil {
  textmetrics.count_sentences("   \n\t  ")
  |> should.equal(0)
}

// --- syllables_in_word --------------------------------------------------

pub fn syllables_empty_test() -> Nil {
  textmetrics.count_syllables_in_word("")
  |> should.equal(0)
}

pub fn syllables_a_test() -> Nil {
  textmetrics.count_syllables_in_word("a")
  |> should.equal(1)
}

pub fn syllables_the_test() -> Nil {
  textmetrics.count_syllables_in_word("the")
  |> should.equal(1)
}

pub fn syllables_hello_test() -> Nil {
  textmetrics.count_syllables_in_word("hello")
  |> should.equal(2)
}

pub fn syllables_syllable_test() -> Nil {
  textmetrics.count_syllables_in_word("syllable")
  |> should.equal(3)
}

pub fn syllables_queue_test() -> Nil {
  // Vowel-cluster heuristic: "ueue" is one group, silent-e not
  // subtracted because preceding letter is a vowel.
  textmetrics.count_syllables_in_word("queue")
  |> should.equal(1)
}

pub fn syllables_rhythm_test() -> Nil {
  // No vowels — heuristic floors at 1.
  textmetrics.count_syllables_in_word("rhythm")
  |> should.equal(1)
}

pub fn syllables_strawberry_test() -> Nil {
  textmetrics.count_syllables_in_word("strawberry")
  |> should.equal(3)
}

pub fn syllables_mississippi_test() -> Nil {
  textmetrics.count_syllables_in_word("Mississippi")
  |> should.equal(4)
}

pub fn syllables_readability_test() -> Nil {
  // r e-a d-a b-i l-i-t y
  textmetrics.count_syllables_in_word("readability")
  |> should.equal(5)
}

pub fn syllables_cjk_fallback_test() -> Nil {
  // Non-English word: heuristic falls back to 1 (treated as a token).
  textmetrics.count_syllables_in_word("日本語")
  |> should.equal(1)
}

pub fn syllables_count_each_latin1_accented_vowel_family_test() -> Nil {
  // One word per accented-vowel family, each relying on that family to
  // reach its count (found by mutation testing: only é and ü were used).
  textmetrics.count_syllables_in_word("voilà") |> should.equal(2)
  textmetrics.count_syllables_in_word("nïnï") |> should.equal(2)
  textmetrics.count_syllables_in_word("côté") |> should.equal(2)
  textmetrics.count_syllables_in_word("týtý") |> should.equal(2)
}

// --- characters / paragraphs / polysyllables ----------------------------

pub fn characters_letters_only_test() -> Nil {
  // "Hello, World!" → H e l l o W o r l d (10 letters; comma, space,
  // exclamation excluded).
  textmetrics.count_characters("Hello, World!")
  |> should.equal(10)
}

pub fn characters_digits_included_test() -> Nil {
  // Digits count, space does not.
  textmetrics.count_characters("123 abc")
  |> should.equal(6)
}

pub fn polysyllables_single_test() -> Nil {
  // Only "readable" reaches three syllables.
  textmetrics.count_polysyllables("a fast cat runs through the readable garden")
  |> should.equal(1)
}

pub fn paragraphs_three_test() -> Nil {
  textmetrics.count_paragraphs("a\n\nb\n\nc")
  |> should.equal(3)
}

pub fn paragraphs_one_test() -> Nil {
  textmetrics.count_paragraphs("one line only")
  |> should.equal(1)
}

pub fn paragraphs_empty_test() -> Nil {
  textmetrics.count_paragraphs("")
  |> should.equal(0)
}

pub fn paragraphs_trailing_blank_test() -> Nil {
  // Trailing blank lines do not produce extra paragraphs.
  textmetrics.count_paragraphs("first\n\nsecond\n\n")
  |> should.equal(2)
}

// --- Unicode / determinism ----------------------------------------------

pub fn words_unicode_accent_single_word_test() -> Nil {
  textmetrics.count_words("naïve")
  |> should.equal(1)
}

pub fn words_mixed_script_single_word_test() -> Nil {
  textmetrics.count_words("naïve123")
  |> should.equal(1)
}

pub fn words_deterministic_test() -> Nil {
  let text = "The quick brown fox jumps over the lazy dog."
  textmetrics.count_words(text)
  |> should.equal(textmetrics.count_words(text))
}

// --- boundaries found by mutation testing ---------------------------------

pub fn paragraphs_keep_consecutive_lines_together_test() -> Nil {
  assert textmetrics.count_paragraphs("a\nb") == 1
  assert textmetrics.count_paragraphs("a\nb\nc\n\nd\ne") == 2
}

pub fn syllables_drop_a_silent_e_after_a_consonant_test() -> Nil {
  assert textmetrics.count_syllables_in_word("make") == 1
}

pub fn syllables_treat_y_before_le_as_a_vowel_test() -> Nil {
  // "...yle" counts the `y`, so the final `e` is silent.
  assert textmetrics.count_syllables_in_word("style") == 1
}

pub fn syllables_keep_the_e_after_a_noninitial_y_test() -> Nil {
  assert textmetrics.count_syllables_in_word("goodbye") == 2
}

pub fn syllables_do_not_count_an_initial_y_test() -> Nil {
  assert textmetrics.count_syllables_in_word("Ypres") == 1
}

pub fn words_join_digits_up_to_nine_test() -> Nil {
  assert textmetrics.count_words("1,9") == 1
  assert textmetrics.count_words("9.0") == 1
}

pub fn words_skip_keycap_emoji_test() -> Nil {
  assert textmetrics.count_words("0\u{FE0F}\u{20E3}") == 0
  assert textmetrics.count_words("9\u{FE0F}\u{20E3}") == 0
}

pub fn sentences_recognise_month_and_day_abbreviations_test() -> Nil {
  assert textmetrics.count_sentences("Paid in Dec. and kept.") == 1
  assert textmetrics.count_sentences("Open on Sat. and closed.") == 1
}

pub fn sentences_continue_after_e_g_before_a_digit_test() -> Nil {
  // A caseless grapheme after a multi-period abbreviation is not a
  // capital letter, so the sentence goes on.
  assert textmetrics.count_sentences("Buy e.g. 5 apples.") == 1
}

pub fn sentences_skip_unicode_spaces_before_a_capital_test() -> Nil {
  assert textmetrics.count_sentences("We met in the U.S.\u{2000}She left.") == 2
  assert textmetrics.count_sentences("We met in the U.S.\u{200A}She left.") == 2
}

pub fn sentences_keep_several_closing_marks_test() -> Nil {
  assert textmetrics.count_sentences("He said (\"stop.\") Then he left.") == 2
  assert textmetrics.count_sentences("He said (\"stop.\")") == 1
}

pub fn sentences_end_after_dotted_digits_test() -> Nil {
  // Only one- or two-letter parts make a multi-period abbreviation, so
  // the period after `1.2` ends the sentence.
  assert textmetrics.count_sentences("Use 1.2. then stop.") == 2
}
