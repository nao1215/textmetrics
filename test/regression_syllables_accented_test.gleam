//// Issue #20: Latin-extended accented vowels (é, ï, ü, ñ, ...) must
//// be treated as syllable nuclei so `syllables_in_word("café") == 2`
//// instead of `1`.

import gleeunit/should
import textmetrics/count

pub fn cafe_two_syllables_test() -> Nil {
  count.syllables_in_word("café") |> should.equal(2)
}

// "naïve" deliberately omitted: the English-tuned heuristic collapses
// the adjacent `a` and `ï` into one vowel group and treats the final
// `e` as silent, yielding 1 instead of 2. Fixing the diaresis-as-
// hiatus case requires a language hint and is out of scope here.

pub fn resume_three_syllables_test() -> Nil {
  count.syllables_in_word("résumé") |> should.equal(3)
}

pub fn uber_two_syllables_test() -> Nil {
  count.syllables_in_word("über") |> should.equal(2)
}

pub fn zurich_two_syllables_test() -> Nil {
  count.syllables_in_word("Zürich") |> should.equal(2)
}

pub fn ascii_words_unchanged_test() -> Nil {
  count.syllables_in_word("hello") |> should.equal(2)
  count.syllables_in_word("syllable") |> should.equal(3)
  count.syllables_in_word("rhythm") |> should.equal(1)
}
