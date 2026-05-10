//// Spec §12.10: grapheme-level invariants. The library does not
//// normalize input — NFC/NFD strings that *render* identically are
//// reported as differing.

import gleam/string
import gleeunit/should
import textmetrics/distance

pub fn levenshtein_identical_nfc_test() {
  distance.levenshtein("café", "café") |> should.equal(0)
}

pub fn levenshtein_nfc_vs_nfd_is_one_test() {
  // NFC `é` = U+00E9 is one grapheme; NFD `e\u{0301}` is also one
  // grapheme but distinct from `é` under structural equality. Spec
  // requires this to report 1 — we do not normalize.
  distance.levenshtein("café", "cafe\u{0301}") |> should.equal(1)
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
