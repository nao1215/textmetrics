//// Counts of words, sentences, syllables, characters, paragraphs and
//// polysyllables — the primitives consumed by readability scores in
//// [`textmetrics/readability`](./readability.html).
////
//// Functions in this module are pure, deterministic, and `O(n)` in
//// the length of their input. They iterate over **extended grapheme
//// clusters** (via `gleam/string.to_graphemes`), not raw bytes, so
//// `"naïve"` is 5 graphemes and 1 word regardless of whether the
//// diacritic is encoded as a single codepoint or `a` + combining
//// mark.
////
//// All language-specific heuristics in this module are tuned for
//// **English**. Behaviour on other scripts is documented per
//// function and biased towards "do nothing surprising": CJK without
//// whitespace stays one word; non-English text in
//// [`syllables_in_word`](#syllables_in_word) returns `1`.

import gleam/list
import gleam/string

// --- words --------------------------------------------------------------

/// Count words. A word is a maximal run of "letter-like" graphemes
/// separated by whitespace or punctuation.
///
/// A grapheme counts as letter-like when its first code point is an
/// ASCII letter (`a-z` / `A-Z`), an ASCII digit, or any non-ASCII
/// character (covering Latin-1 letters, CJK ideographs, accented
/// letters delivered as a single grapheme, etc.). Whitespace and
/// ASCII punctuation are word boundaries.
///
/// Examples:
///
/// ```gleam
/// count.words("")              // 0
/// count.words("hello")         // 1
/// count.words("hello world")   // 2
/// count.words("hello, world!") // 2
/// count.words("hello   world") // 2 (whitespace collapses)
/// ```
pub fn words(text: String) -> Int {
  let graphemes = string.to_graphemes(text)
  count_runs(graphemes, False, 0)
}

fn count_runs(items: List(String), in_run: Bool, acc: Int) -> Int {
  case items {
    [] -> acc
    [g, ..rest] -> {
      case is_letter_like(g) {
        True ->
          case in_run {
            True -> count_runs(rest, True, acc)
            False -> count_runs(rest, True, acc + 1)
          }
        False -> count_runs(rest, False, acc)
      }
    }
  }
}

fn is_letter_like(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [] -> False
    [cp, ..] -> {
      let n = string.utf_codepoint_to_int(cp)
      is_letter_like_code(n)
    }
  }
}

fn is_letter_like_code(n: Int) -> Bool {
  case n {
    // ASCII letters
    _ if n >= 0x41 && n <= 0x5a -> True
    _ if n >= 0x61 && n <= 0x7a -> True
    // ASCII digits
    _ if n >= 0x30 && n <= 0x39 -> True
    // Anything above ASCII — Latin-1 letters, CJK, accented graphemes
    _ if n >= 0x80 -> True
    _ -> False
  }
}

// --- sentences -----------------------------------------------------------

/// Count sentences. Sentence terminators are `.`, `!`, `?`. A run of
/// consecutive terminators counts as one boundary (so `"What?!"` is
/// one sentence). A trailing non-empty fragment that lacks a
/// terminator still counts as a sentence (`"hello"` → 1).
///
/// This implementation does **not** special-case abbreviations like
/// `Mr.`, `Dr.`, `e.g.`. Text dense in such abbreviations will be
/// over-segmented. Callers that need abbreviation-aware segmentation
/// should pre-process.
///
/// Empty input returns `0`.
pub fn sentences(text: String) -> Int {
  let graphemes = string.to_graphemes(text)
  case has_non_whitespace(graphemes) {
    False -> 0
    True -> sentence_loop(graphemes, False, False, 0)
  }
}

fn sentence_loop(
  items: List(String),
  saw_content: Bool,
  in_terminator: Bool,
  acc: Int,
) -> Int {
  case items {
    [] ->
      case saw_content {
        True -> acc + 1
        False -> acc
      }
    [g, ..rest] -> {
      case is_terminator(g), is_whitespace(g) {
        True, _ -> {
          let next_acc = case in_terminator {
            True -> acc
            False ->
              case saw_content {
                True -> acc + 1
                False -> acc
              }
          }
          sentence_loop(rest, False, True, next_acc)
        }
        False, True -> sentence_loop(rest, saw_content, False, acc)
        False, False -> sentence_loop(rest, True, False, acc)
      }
    }
  }
}

fn is_terminator(g: String) -> Bool {
  case g {
    "." | "!" | "?" -> True
    _ -> False
  }
}

fn is_whitespace(g: String) -> Bool {
  case g {
    " " | "\t" | "\n" | "\r" | "\u{00A0}" -> True
    _ -> False
  }
}

fn has_non_whitespace(items: List(String)) -> Bool {
  case items {
    [] -> False
    [g, ..rest] ->
      case is_whitespace(g) {
        True -> has_non_whitespace(rest)
        False -> True
      }
  }
}

// --- syllables ----------------------------------------------------------

/// Count syllables in a single word using an English heuristic:
///
/// 1. Lowercase the word.
/// 2. Strip non-ASCII-letter graphemes.
/// 3. Count maximal vowel groups in `a e i o u y`, with `y` only
///    counting at non-initial position.
/// 4. Subtract one if the word ends in a silent `e` (the preceding
///    letter being a consonant).
/// 5. Floor at `1`.
///
/// Examples:
///
/// ```gleam
/// count.syllables_in_word("the")       // 1
/// count.syllables_in_word("hello")     // 2
/// count.syllables_in_word("syllable")  // 3
/// count.syllables_in_word("rhythm")    // 1 (no vowels, floors at 1)
/// ```
///
/// Returns `0` for an empty input. Returns `1` for non-English words
/// that contain no ASCII letters.
pub fn syllables_in_word(word: String) -> Int {
  let lowered = string.lowercase(word)
  let letters =
    lowered
    |> string.to_graphemes
    |> list.filter(keeping: is_ascii_letter)
  case letters {
    [] ->
      case has_any_grapheme(lowered) {
        True -> 1
        False -> 0
      }
    _ -> syllables_from_letters(letters)
  }
}

fn has_any_grapheme(s: String) -> Bool {
  case string.to_graphemes(s) {
    [] -> False
    _ -> True
  }
}

fn is_ascii_letter(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [] -> False
    [cp, ..] -> {
      let n = string.utf_codepoint_to_int(cp)
      n >= 0x61 && n <= 0x7a
    }
  }
}

fn syllables_from_letters(letters: List(String)) -> Int {
  let vowel_groups = count_vowel_groups(letters, False, True, 0)
  let with_silent_e = case ends_with_silent_e(letters) {
    True -> vowel_groups - 1
    False -> vowel_groups
  }
  max_int(with_silent_e, 1)
}

fn count_vowel_groups(
  letters: List(String),
  in_vowel: Bool,
  at_start: Bool,
  acc: Int,
) -> Int {
  case letters {
    [] -> acc
    [g, ..rest] -> {
      let vowel = is_vowel_letter(g, at_start)
      let next_acc = case vowel, in_vowel {
        True, False -> acc + 1
        _, _ -> acc
      }
      count_vowel_groups(rest, vowel, False, next_acc)
    }
  }
}

fn is_vowel_letter(g: String, at_start: Bool) -> Bool {
  case g {
    "a" | "e" | "i" | "o" | "u" -> True
    "y" ->
      case at_start {
        True -> False
        False -> True
      }
    _ -> False
  }
}

fn ends_with_silent_e(letters: List(String)) -> Bool {
  case last_three(letters) {
    // "...Cle" (consonant + l + e) is a syllabic consonant-l-e pattern
    // (e.g. "syllable", "readable", "table"). The trailing `e` is NOT
    // silent — it contributes the schwa of the final /-əl/ syllable.
    [c, "l", "e"] ->
      case is_vowel_letter(c, False) {
        True -> {
          // "...Vle" — the vowel before 'l' already counted the
          // syllable, so the 'e' here IS silent.
          True
        }
        False -> False
      }
    [_, prev, "e"] ->
      case is_vowel_letter(prev, False) {
        True -> False
        False -> True
      }
    [prev, "e"] ->
      case is_vowel_letter(prev, False) {
        True -> False
        False -> True
      }
    ["e"] -> False
    _ -> False
  }
}

fn last_three(items: List(String)) -> List(String) {
  case items {
    [] -> []
    [single] -> [single]
    [a, b] -> [a, b]
    [_, ..rest] ->
      case rest {
        [a, b, c] -> [a, b, c]
        _ -> last_three(rest)
      }
  }
}

fn max_int(a: Int, b: Int) -> Int {
  case a > b {
    True -> a
    False -> b
  }
}

/// Count syllables in `text`. Sums [`syllables_in_word`](#syllables_in_word)
/// over each word found by [`words`](#words).
pub fn syllables(text: String) -> Int {
  word_chunks(string.to_graphemes(text), [], [])
  |> list.fold(0, fn(acc, w) { acc + syllables_in_word(w) })
}

fn word_chunks(
  items: List(String),
  current: List(String),
  acc: List(String),
) -> List(String) {
  case items {
    [] ->
      case current {
        [] -> list.reverse(acc)
        _ -> list.reverse([finish(current), ..acc])
      }
    [g, ..rest] -> {
      case is_letter_like(g) {
        True -> word_chunks(rest, [g, ..current], acc)
        False ->
          case current {
            [] -> word_chunks(rest, [], acc)
            _ -> word_chunks(rest, [], [finish(current), ..acc])
          }
      }
    }
  }
}

fn finish(chunk: List(String)) -> String {
  chunk
  |> list.reverse
  |> string.concat
}

// --- characters / polysyllables / paragraphs ----------------------------

/// Count characters that contribute to readability formulas: ASCII
/// letters plus ASCII digits, **excluding** whitespace and ASCII
/// punctuation. Non-ASCII graphemes that look letter-like (Latin-1
/// accents, CJK ideographs) also count, mirroring the behaviour of
/// `textstat`'s `char_count`.
///
/// Examples:
///
/// ```gleam
/// count.characters("Hello, World!") // 10
/// count.characters("123 abc")       // 6
/// ```
pub fn characters(text: String) -> Int {
  text
  |> string.to_graphemes
  |> list.fold(0, fn(acc, g) {
    case is_letter_like(g) {
      True -> acc + 1
      False -> acc
    }
  })
}

/// Count words with three or more syllables in `text`. This is the
/// "polysyllable" count consumed by SMOG with **no** exclusions; the
/// stricter Gunning-Fog "complex word" count is computed inline
/// inside [`readability.gunning_fog`](./readability.html#gunning_fog).
pub fn polysyllables(text: String) -> Int {
  word_chunks(string.to_graphemes(text), [], [])
  |> list.fold(0, fn(acc, w) {
    case syllables_in_word(w) >= 3 {
      True -> acc + 1
      False -> acc
    }
  })
}

/// Count paragraphs. A paragraph is a maximal run of non-blank lines
/// separated by one or more blank lines. Trailing blank lines do not
/// produce empty paragraphs.
///
/// Examples:
///
/// ```gleam
/// count.paragraphs("a\n\nb\n\nc")  // 3
/// count.paragraphs("one line")     // 1
/// count.paragraphs("")             // 0
/// ```
pub fn paragraphs(text: String) -> Int {
  let lines = string.split(text, "\n")
  paragraph_loop(lines, False, 0)
}

fn paragraph_loop(lines: List(String), in_para: Bool, acc: Int) -> Int {
  case lines {
    [] -> acc
    [line, ..rest] -> {
      let blank = is_blank(line)
      case blank, in_para {
        True, _ -> paragraph_loop(rest, False, acc)
        False, True -> paragraph_loop(rest, True, acc)
        False, False -> paragraph_loop(rest, True, acc + 1)
      }
    }
  }
}

fn is_blank(line: String) -> Bool {
  line
  |> string.to_graphemes
  |> list.all(is_whitespace)
}
