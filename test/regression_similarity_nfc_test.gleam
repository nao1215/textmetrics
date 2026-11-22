import gleeunit/should
import textmetrics.{Ranked}

// Canonically-equivalent strings (precomposed vs decomposed) must score
// as identical, the same way `distance` treats them.

pub fn jaro_nfc_nfd_identical_test() {
  textmetrics.jaro("\u{00C1}", "A\u{0301}") |> should.equal(1.0)
}

pub fn jaro_winkler_nfc_nfd_identical_test() {
  {
    textmetrics.jaro_winkler(
      "caf\u{00E9}",
      "cafe\u{0301}",
      prefix_scale: 0.1,
      prefix_max: 4,
    )
    |> should.be_ok
  }
  |> should.equal(1.0)
}

pub fn jaro_winkler_with_nfc_nfd_identical_test() {
  let config = #(0.2, 6)
  {
    textmetrics.jaro_winkler(
      "caf\u{00E9}",
      "cafe\u{0301}",
      prefix_scale: config.0,
      prefix_max: config.1,
    )
    |> should.be_ok
  }
  |> should.equal(1.0)
}

pub fn sorensen_dice_nfc_nfd_single_grapheme_test() {
  textmetrics.sorensen_dice("\u{00E9}", "e\u{0301}", ngram_size: 2)
  |> should.equal(Ok(1.0))
}

pub fn sorensen_dice_bigrams_nfc_nfd_identical_test() {
  {
    textmetrics.sorensen_dice("caf\u{00E9}s", "cafe\u{0301}s", ngram_size: 2)
    |> should.be_ok
  }
  |> should.equal(1.0)
}

pub fn sorensen_dice_trigrams_nfc_nfd_identical_test() {
  {
    textmetrics.sorensen_dice("caf\u{00E9}s", "cafe\u{0301}s", ngram_size: 3)
    |> should.be_ok
  }
  |> should.equal(1.0)
}

pub fn rank_jaro_winkler_nfc_nfd_identical_test() {
  textmetrics.rank_jaro_winkler("\u{00C1}", ["A\u{0301}"], 1)
  |> should.equal([Ranked(label: "A\u{0301}", score: 1.0)])
}
