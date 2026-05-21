//// Spec §12.10: grapheme-level invariants. Post-#18 the library
//// pre-normalises inputs to Unicode Normalization Form C (NFC), so
//// canonically-equivalent NFC/NFD strings compare as equal.

import gleam/string
import gleeunit/should
import textmetrics/distance

pub fn levenshtein_identical_nfc_test() {
  distance.levenshtein("café", "café") |> should.equal(0)
}

pub fn levenshtein_nfc_vs_nfd_compares_equal_test() {
  // NFC `é` = U+00E9 is one grapheme; NFD `e\u{0301}` is also one
  // grapheme and canonically equivalent. Post-#18 the distance
  // functions pre-normalise to NFC, so the two forms compare as equal.
  distance.levenshtein("café", "cafe\u{0301}") |> should.equal(0)
}

pub fn levenshtein_emoji_zwj_family_test() {
  let family_a = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
  let family_b = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}"
  distance.levenshtein(family_a, family_b) |> should.equal(1)
}

pub fn levenshtein_hiragana_test() {
  distance.levenshtein("あいう", "あえう") |> should.equal(1)
}

pub fn levenshtein_hangul_drop_test() {
  distance.levenshtein("가나다", "가나") |> should.equal(1)
}

pub fn hamming_hangul_test() {
  distance.hamming("가나다", "가나라") |> should.equal(Ok(1))
}

pub fn graphemes_count_test() {
  // Sanity: a Hiragana string of three characters is three graphemes
  // (so distance functions count them as three units).
  string.to_graphemes("あいう") |> should.equal(["あ", "い", "う"])
}
