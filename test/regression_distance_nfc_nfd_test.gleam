import gleeunit/should
import textmetrics/distance

// Issue #18: canonically-equivalent strings — NFC `"\u{00C1}"` and
// NFD `"A\u{0301}"` both render as `Á` and are a single grapheme
// cluster under UAX #29 — must compare as equal under every
// distance / similarity function.

pub fn levenshtein_nfc_nfd_compare_equal_test() {
  distance.levenshtein("\u{00C1}", "A\u{0301}")
  |> should.equal(0)
}

pub fn levenshtein_nfc_nfd_reversed_compare_equal_test() {
  distance.levenshtein("A\u{0301}", "\u{00C1}")
  |> should.equal(0)
}

pub fn hamming_nfc_nfd_compare_equal_test() {
  distance.hamming("\u{00C1}", "A\u{0301}")
  |> should.equal(Ok(0))
}

pub fn damerau_levenshtein_nfc_nfd_compare_equal_test() {
  distance.damerau_levenshtein("\u{00C1}", "A\u{0301}")
  |> should.equal(0)
}

pub fn osa_nfc_nfd_compare_equal_test() {
  distance.osa("\u{00C1}", "A\u{0301}")
  |> should.equal(0)
}

pub fn normalized_levenshtein_nfc_nfd_compare_identical_test() {
  distance.normalized_levenshtein("\u{00C1}", "A\u{0301}")
  |> should.equal(1.0)
}

// A longer canonically-equivalent pair: "café" precomposed vs decomposed.
pub fn levenshtein_cafe_nfc_nfd_test() {
  distance.levenshtein("café", "cafe\u{0301}")
  |> should.equal(0)
}

// Distinct characters that happen to look similar must still differ
// (regression guard so the NFC pass does not silently fold non-equivalent
// characters together).

pub fn levenshtein_distinct_diacritics_still_differ_test() {
  // À (U+00C0, grave) vs Á (U+00C1, acute) — different characters,
  // not canonically equivalent.
  distance.levenshtein("\u{00C0}", "\u{00C1}")
  |> should.equal(1)
}
