import gleeunit/should

import textmetrics/count

// --- words --------------------------------------------------------------

pub fn words_empty_test() -> Nil {
  count.words("")
  |> should.equal(0)
}

pub fn words_single_test() -> Nil {
  count.words("hello")
  |> should.equal(1)
}

pub fn words_two_test() -> Nil {
  count.words("hello world")
  |> should.equal(2)
}

pub fn words_punctuation_test() -> Nil {
  count.words("hello, world!")
  |> should.equal(2)
}

pub fn words_collapses_whitespace_test() -> Nil {
  count.words("hello   world")
  |> should.equal(2)
}

pub fn words_handles_newlines_test() -> Nil {
  count.words("hello\nworld")
  |> should.equal(2)
}

pub fn words_cjk_with_space_test() -> Nil {
  // Two whitespace-separated tokens, each a CJK + Katakana run.
  count.words("日本語 テスト")
  |> should.equal(2)
}

// --- sentences ----------------------------------------------------------

pub fn sentences_empty_test() -> Nil {
  count.sentences("")
  |> should.equal(0)
}

pub fn sentences_single_test() -> Nil {
  count.sentences("Hello.")
  |> should.equal(1)
}

pub fn sentences_two_test() -> Nil {
  count.sentences("Hello. World.")
  |> should.equal(2)
}

pub fn sentences_consecutive_terminators_test() -> Nil {
  // !! and ? collapse into single boundaries → two sentences.
  count.sentences("Hello!! World?")
  |> should.equal(2)
}

pub fn sentences_no_terminator_still_counts_test() -> Nil {
  count.sentences("Hello, world")
  |> should.equal(1)
}

pub fn sentences_over_segments_abbreviations_test() -> Nil {
  // Documented limitation: "Mr." is treated as a terminator.
  count.sentences("Mr. Smith went home.")
  |> should.equal(2)
}

pub fn sentences_whitespace_only_input_test() -> Nil {
  count.sentences("   \n\t  ")
  |> should.equal(0)
}

// --- syllables_in_word --------------------------------------------------

pub fn syllables_empty_test() -> Nil {
  count.syllables_in_word("")
  |> should.equal(0)
}

pub fn syllables_a_test() -> Nil {
  count.syllables_in_word("a")
  |> should.equal(1)
}

pub fn syllables_the_test() -> Nil {
  count.syllables_in_word("the")
  |> should.equal(1)
}

pub fn syllables_hello_test() -> Nil {
  count.syllables_in_word("hello")
  |> should.equal(2)
}

pub fn syllables_syllable_test() -> Nil {
  count.syllables_in_word("syllable")
  |> should.equal(3)
}

pub fn syllables_queue_test() -> Nil {
  // Vowel-cluster heuristic: "ueue" is one group, silent-e not
  // subtracted because preceding letter is a vowel.
  count.syllables_in_word("queue")
  |> should.equal(1)
}

pub fn syllables_rhythm_test() -> Nil {
  // No vowels — heuristic floors at 1.
  count.syllables_in_word("rhythm")
  |> should.equal(1)
}

pub fn syllables_strawberry_test() -> Nil {
  count.syllables_in_word("strawberry")
  |> should.equal(3)
}

pub fn syllables_mississippi_test() -> Nil {
  count.syllables_in_word("Mississippi")
  |> should.equal(4)
}

pub fn syllables_readability_test() -> Nil {
  // r e-a d-a b-i l-i-t y
  count.syllables_in_word("readability")
  |> should.equal(5)
}

pub fn syllables_cjk_fallback_test() -> Nil {
  // Non-English word: heuristic falls back to 1 (treated as a token).
  count.syllables_in_word("日本語")
  |> should.equal(1)
}

// --- characters / paragraphs / polysyllables ----------------------------

pub fn characters_letters_only_test() -> Nil {
  // "Hello, World!" → H e l l o W o r l d (10 letters; comma, space,
  // exclamation excluded).
  count.characters("Hello, World!")
  |> should.equal(10)
}

pub fn characters_digits_included_test() -> Nil {
  // Digits count, space does not.
  count.characters("123 abc")
  |> should.equal(6)
}

pub fn polysyllables_single_test() -> Nil {
  // Only "readable" reaches three syllables.
  count.polysyllables("a fast cat runs through the readable garden")
  |> should.equal(1)
}

pub fn paragraphs_three_test() -> Nil {
  count.paragraphs("a\n\nb\n\nc")
  |> should.equal(3)
}

pub fn paragraphs_one_test() -> Nil {
  count.paragraphs("one line only")
  |> should.equal(1)
}

pub fn paragraphs_empty_test() -> Nil {
  count.paragraphs("")
  |> should.equal(0)
}

pub fn paragraphs_trailing_blank_test() -> Nil {
  // Trailing blank lines do not produce extra paragraphs.
  count.paragraphs("first\n\nsecond\n\n")
  |> should.equal(2)
}

// --- Unicode / determinism ----------------------------------------------

pub fn words_unicode_accent_single_word_test() -> Nil {
  count.words("naïve")
  |> should.equal(1)
}

pub fn words_mixed_script_single_word_test() -> Nil {
  count.words("naïve123")
  |> should.equal(1)
}

pub fn words_deterministic_test() -> Nil {
  let text = "The quick brown fox jumps over the lazy dog."
  count.words(text)
  |> should.equal(count.words(text))
}
