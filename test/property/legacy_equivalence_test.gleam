//// The diff, LCS and distance algorithms were rewritten to use less
//// time and memory. These properties check that the rewrites return
//// exactly what v0.9.0 returned (copied into `legacy/v0_9_0`), including
//// which of several equally good answers is chosen.

import gleam/list
import gleam/string
import legacy/v0_9_0
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range
import textmetrics/count
import textmetrics/diff
import textmetrics/distance
import textmetrics/internal/unicode
import textmetrics/lcs
import textmetrics/similarity

fn config() -> metamon.Config {
  metamon.default_config() |> metamon.with_runs_or_panic(400)
}

/// Lines over a small alphabet so that unique, repeated and moved
/// lines all show up.
fn lines_generator(max_length: Int) -> Generator(List(String)) {
  generator.list_of(
    generator.element_of(["a", "b", "c", "d", "e", "f", "g"]),
    range.constant(0, max_length),
  )
}

fn lines_pair_generator(
  max_length: Int,
) -> Generator(#(List(String), List(String))) {
  generator.tuple2(lines_generator(max_length), lines_generator(max_length))
}

/// A second input made by editing the first, so that long common runs
/// (and common prefixes and suffixes) are frequent.
fn edited_pair_generator() -> Generator(#(List(String), List(String))) {
  generator.tuple3(lines_generator(12), lines_generator(4), lines_generator(4))
  |> generator.map(fn(parts) {
    let #(middle, left, right) = parts
    #(
      list.flatten([left, middle, right]),
      list.flatten([right, middle, left, ["a"]]),
    )
  })
}

fn word_generator() -> Generator(String) {
  generator.list_of(
    generator.element_of(["a", "b", "c", "é", "e\u{0301}", "👍🏽"]),
    range.constant(0, 10),
  )
  |> generator.map(string.concat)
}

fn nfc_graphemes(text: String) -> List(String) {
  string.to_graphemes(unicode.to_nfc(text))
}

pub fn myers_matches_v0_9_0_test() {
  metamon.forall_with(config(), lines_pair_generator(14), fn(pair) {
    let #(old, new) = pair
    diff.myers(old, new) == v0_9_0.myers(old, new)
  })
}

pub fn myers_matches_v0_9_0_on_edited_inputs_test() {
  metamon.forall_with(config(), edited_pair_generator(), fn(pair) {
    let #(old, new) = pair
    diff.myers(old, new) == v0_9_0.myers(old, new)
  })
}

pub fn patience_matches_v0_9_0_test() {
  metamon.forall_with(config(), lines_pair_generator(14), fn(pair) {
    let #(old, new) = pair
    diff.patience(old, new) == v0_9_0.patience(old, new)
  })
}

pub fn patience_matches_v0_9_0_on_edited_inputs_test() {
  metamon.forall_with(config(), edited_pair_generator(), fn(pair) {
    let #(old, new) = pair
    diff.patience(old, new) == v0_9_0.patience(old, new)
  })
}

/// Longer inputs over a wider alphabet: more unique lines, so the
/// anchors and nested segments of patience get exercised.
fn wide_lines_generator() -> Generator(List(String)) {
  generator.list_of(
    generator.element_of([
      "a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "l", "m", "n",
    ]),
    range.constant(0, 40),
  )
}

pub fn patience_matches_v0_9_0_on_wide_inputs_test() {
  metamon.forall_with(
    config(),
    generator.tuple2(wide_lines_generator(), wide_lines_generator()),
    fn(pair) {
      let #(old, new) = pair
      diff.patience(old, new) == v0_9_0.patience(old, new)
    },
  )
}

pub fn lcs_sequence_matches_v0_9_0_test() {
  metamon.forall_with(config(), lines_pair_generator(14), fn(pair) {
    let #(a, b) = pair
    lcs.sequence(a, b) == v0_9_0.lcs_sequence(a, b)
  })
}

pub fn lcs_sequence_matches_v0_9_0_on_edited_inputs_test() {
  metamon.forall_with(config(), edited_pair_generator(), fn(pair) {
    let #(a, b) = pair
    lcs.sequence(a, b) == v0_9_0.lcs_sequence(a, b)
  })
}

pub fn damerau_levenshtein_matches_v0_9_0_test() {
  metamon.forall_with(
    config(),
    generator.tuple2(word_generator(), word_generator()),
    fn(pair) {
      let #(a, b) = pair
      distance.damerau_levenshtein(a, b)
      == v0_9_0.damerau_levenshtein(nfc_graphemes(a), nfc_graphemes(b))
    },
  )
}

pub fn osa_matches_v0_9_0_test() {
  metamon.forall_with(
    config(),
    generator.tuple2(word_generator(), word_generator()),
    fn(pair) {
      let #(a, b) = pair
      distance.osa(a, b) == v0_9_0.osa(nfc_graphemes(a), nfc_graphemes(b))
    },
  )
}

pub fn jaro_matches_v0_9_0_test() {
  metamon.forall_with(
    config(),
    generator.tuple2(word_generator(), word_generator()),
    fn(pair) {
      let #(a, b) = pair
      similarity.jaro(a, b) == v0_9_0.jaro(nfc_graphemes(a), nfc_graphemes(b))
    },
  )
}

/// ASCII text (the letter and space rules for other code points changed
/// after v0.9.0) built from tokens that exercise the abbreviation rules:
/// periods inside and after tokens, short dotted parts, capitals and
/// punctuation that is neither a terminator nor whitespace.
fn sentence_text_generator() -> Generator(String) {
  generator.list_of(
    generator.element_of([
      "a", "b", "e", "g", "m", "p", "U", "S", "Mr", "mrs", "Dr", "thurs", "etc",
      "Jan", "x1", "3", ".", ".", ".", "!", "?", " ", " ", ",", "-", "\n",
      "Then", "ph", "D",
    ]),
    range.constant(0, 30),
  )
  |> generator.map(string.concat)
}

pub fn sentences_matches_v0_9_0_test() {
  metamon.forall_with(config(), sentence_text_generator(), fn(text) {
    count.sentences(text) == v0_9_0.sentences(text)
  })
}

/// Longer words over three letters, for wide Jaro windows and many
/// transpositions.
fn long_word_generator() -> Generator(String) {
  generator.list_of(
    generator.element_of(["a", "b", "c"]),
    range.constant(0, 40),
  )
  |> generator.map(string.concat)
}

pub fn distances_and_jaro_match_v0_9_0_on_long_words_test() {
  metamon.forall_with(
    config(),
    generator.tuple2(long_word_generator(), long_word_generator()),
    fn(pair) {
      let #(a, b) = pair
      let #(graphemes_a, graphemes_b) = #(nfc_graphemes(a), nfc_graphemes(b))
      distance.damerau_levenshtein(a, b)
      == v0_9_0.damerau_levenshtein(graphemes_a, graphemes_b)
      && distance.osa(a, b) == v0_9_0.osa(graphemes_a, graphemes_b)
      && similarity.jaro(a, b) == v0_9_0.jaro(graphemes_a, graphemes_b)
    },
  )
}
