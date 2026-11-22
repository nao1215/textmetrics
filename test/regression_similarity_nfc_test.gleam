import gleeunit/should
import textmetrics/search.{Ranked}
import textmetrics/similarity

// Canonically-equivalent strings (precomposed vs decomposed) must score
// as identical, the same way `distance` treats them.

pub fn jaro_nfc_nfd_identical_test() {
  similarity.jaro("\u{00C1}", "A\u{0301}") |> should.equal(1.0)
}

pub fn jaro_winkler_nfc_nfd_identical_test() {
  similarity.jaro_winkler("caf\u{00E9}", "cafe\u{0301}") |> should.equal(1.0)
}

pub fn jaro_winkler_with_nfc_nfd_identical_test() {
  let assert Ok(config) =
    similarity.jaro_winkler_config(prefix_scale: 0.2, prefix_max: 6)
  similarity.jaro_winkler_with("caf\u{00E9}", "cafe\u{0301}", config)
  |> should.equal(1.0)
}

pub fn sorensen_dice_nfc_nfd_single_grapheme_test() {
  similarity.sorensen_dice("\u{00E9}", "e\u{0301}", 2) |> should.equal(Ok(1.0))
}

pub fn sorensen_dice_bigrams_nfc_nfd_identical_test() {
  similarity.sorensen_dice_bigrams("caf\u{00E9}s", "cafe\u{0301}s")
  |> should.equal(1.0)
}

pub fn sorensen_dice_trigrams_nfc_nfd_identical_test() {
  similarity.sorensen_dice_trigrams("caf\u{00E9}s", "cafe\u{0301}s")
  |> should.equal(1.0)
}

pub fn rank_jaro_winkler_nfc_nfd_identical_test() {
  search.rank_jaro_winkler("\u{00C1}", ["A\u{0301}"], 1)
  |> should.equal([Ranked(label: "A\u{0301}", score: 1.0)])
}
