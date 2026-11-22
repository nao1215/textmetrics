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
/// ASCII letter (`a-z` / `A-Z`), an ASCII digit, or a non-ASCII
/// letter, digit or mark (Latin-1 letters, CJK ideographs, accented
/// letters delivered as a single grapheme, etc.). Whitespace,
/// punctuation, symbols and emoji are word boundaries.
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
    _ if n < 0x80 -> False
    // Above ASCII: letters, digits and marks of any script, but not
    // punctuation, symbols, spaces or emoji.
    _ -> !is_non_letter_code(n)
  }
}

// Punctuation, symbol, space and control code points above U+007F, by
// block: Latin-1, General Punctuation, currency, arrows to control
// pictures, box drawing to miscellaneous symbols and arrows,
// Supplemental Punctuation, CJK punctuation, vertical and small forms,
// full-width ASCII punctuation, specials and the emoji and symbol blocks.
fn is_non_letter_code(n: Int) -> Bool {
  case n {
    _ if n >= 0x80 && n <= 0xa9 -> True
    _ if n >= 0xab && n <= 0xb1 -> True
    0xb4 | 0xbb | 0xbf | 0xd7 | 0xf7 | 0x1680 | 0x3030 | 0xfeff -> True
    _ if n >= 0xb6 && n <= 0xb8 -> True
    _ if n >= 0x2000 && n <= 0x206f -> True
    _ if n >= 0x20a0 && n <= 0x20cf -> True
    _ if n >= 0x2190 && n <= 0x245f -> True
    _ if n >= 0x2500 && n <= 0x2bff -> True
    _ if n >= 0x2e00 && n <= 0x2e7f -> True
    _ if n >= 0x3000 && n <= 0x3004 -> True
    _ if n >= 0x3008 && n <= 0x3020 -> True
    _ if n >= 0x3036 && n <= 0x3037 -> True
    _ if n >= 0x303d && n <= 0x303f -> True
    _ if n >= 0xfe10 && n <= 0xfe1f -> True
    _ if n >= 0xfe30 && n <= 0xfe6f -> True
    _ if n >= 0xff00 && n <= 0xff0f -> True
    _ if n >= 0xff1a && n <= 0xff20 -> True
    _ if n >= 0xff3b && n <= 0xff40 -> True
    _ if n >= 0xff5b && n <= 0xff65 -> True
    _ if n >= 0xfff0 && n <= 0xffff -> True
    _ if n >= 0x1f000 && n <= 0x1faff -> True
    _ -> False
  }
}

// --- sentences -----------------------------------------------------------

/// Count sentences. Sentence terminators are `.`, `!`, `?`. A run of
/// consecutive terminators counts as one boundary (so `"What?!"` is
/// one sentence). A trailing non-empty fragment that lacks a
/// terminator still counts as a sentence (`"hello"` → 1).
///
/// A `.` does not end a sentence when:
///
/// - a letter or digit follows it directly, as inside `3.50`,
///   `example.com`, or the first period of `p.m.`;
/// - it follows a common English abbreviation — `Mr.`, `Mrs.`, `Ms.`,
///   `Dr.`, `Prof.`, `Jr.`, `Sr.`, `St.`, `Ave.`, `Blvd.`, `vs.`,
///   `etc.`, `Inc.`, `Ltd.`, `Mon.` ... `Sun.`, `Jan.` ... `Dec.` and a
///   few more (case-insensitive);
/// - it closes a multi-period abbreviation made of one- or two-letter
///   parts — `e.g.`, `i.e.`, `a.m.`, `p.m.`, `U.S.`, `U.S.A.`, `Ph.D.` —
///   unless the next word starts with a capital letter, so
///   `"at 5 p.m. yesterday."` is one sentence and
///   `"at 5 p.m. Then he left."` is two.
///
/// Empty input returns `0`.
pub fn sentences(text: String) -> Int {
  let graphemes = string.to_graphemes(text)
  case has_non_whitespace(graphemes) {
    False -> 0
    True -> sentence_loop(graphemes, False, False, empty_word, 0)
  }
}

fn sentence_loop(
  items: List(String),
  saw_content: Bool,
  in_terminator: Bool,
  current_word: Word,
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
          // For `.`, suppress termination inside a token or after an
          // abbreviation. `!` and `?` always terminate.
          let suppress = case g {
            "." -> period_continues_sentence(current_word, rest)
            _ -> False
          }
          let next_acc = case suppress, in_terminator {
            True, _ -> acc
            False, True -> acc
            False, False ->
              case saw_content {
                True -> acc + 1
                False -> acc
              }
          }
          let next_in_terminator = case suppress {
            True -> False
            False -> True
          }
          let next_saw_content = case suppress {
            True -> saw_content
            False -> False
          }
          let next_word = case suppress {
            // Keep the abbreviation token attached to the period so
            // multi-period abbreviations like "e.g." chain correctly.
            True -> push_period(current_word)
            False -> empty_word
          }
          sentence_loop(
            rest,
            next_saw_content,
            next_in_terminator,
            next_word,
            next_acc,
          )
        }
        False, True -> sentence_loop(rest, saw_content, False, empty_word, acc)
        False, False ->
          sentence_loop(rest, True, False, push_grapheme(current_word, g), acc)
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

// What the abbreviation checks need to know about the token before a
// period (with the periods of a multi-period abbreviation kept in it,
// `p.m` for the second period of `p.m.`), kept in constant space so that
// long dotted tokens stay linear.
type Word {
  Word(
    // The graphemes in reverse order, while the token is no longer than
    // the longest abbreviation.
    reversed_start: List(String),
    length: Int,
    periods: Int,
    // Graphemes since the last period.
    part_length: Int,
    // Every part so far is one or two ASCII letters (the current one may
    // still be empty).
    parts_are_short_letters: Bool,
  )
}

const empty_word =
  Word(
    reversed_start: [],
    length: 0,
    periods: 0,
    part_length: 0,
    parts_are_short_letters: True,
  )

const longest_abbreviation = 5

fn push_grapheme(word: Word, g: String) -> Word {
  Word(
    reversed_start: push_start(word, g),
    length: word.length + 1,
    periods: word.periods,
    part_length: word.part_length + 1,
    parts_are_short_letters: word.parts_are_short_letters
      && word.part_length < 2
      && is_ascii_letter(string.lowercase(g)),
  )
}

fn push_period(word: Word) -> Word {
  Word(
    reversed_start: push_start(word, "."),
    length: word.length + 1,
    periods: word.periods + 1,
    part_length: 0,
    parts_are_short_letters: word.parts_are_short_letters
      && word.part_length >= 1,
  )
}

fn push_start(word: Word, g: String) -> List(String) {
  case word.length < longest_abbreviation {
    True -> [g, ..word.reversed_start]
    False -> word.reversed_start
  }
}

/// `rest` is the text after the period.
fn period_continues_sentence(word: Word, rest: List(String)) -> Bool {
  let next_is_letter_like = case rest {
    [next, ..] -> is_letter_like(next)
    [] -> False
  }
  next_is_letter_like
  || is_abbreviation(word)
  || { is_multi_period_abbreviation(word) && !starts_capitalised(rest) }
}

fn is_abbreviation(word: Word) -> Bool {
  case word.length <= longest_abbreviation {
    False -> False
    True ->
      word.reversed_start
      |> list.reverse
      |> string.concat
      |> string.lowercase
      |> is_abbreviation_text
  }
}

fn is_abbreviation_text(word: String) -> Bool {
  case word {
    "mr" | "mrs" | "ms" | "dr" | "prof" | "jr" | "sr" | "st" -> True
    "vs" | "etc" | "no" | "co" | "inc" | "ltd" | "fig" | "vol" | "ch" -> True
    "ave" | "blvd" -> True
    // Months (3-letter and 4-letter forms).
    "jan" | "feb" | "mar" | "apr" | "jun" | "jul" -> True
    "aug" | "sep" | "sept" | "oct" | "nov" | "dec" -> True
    // Days of week.
    "mon" | "tue" | "tues" | "wed" | "thu" | "thur" | "thurs" -> True
    "fri" | "sat" | "sun" -> True
    _ -> False
  }
}

/// Two or more one- or two-letter parts joined by periods: `e.g`, `a.m`,
/// `u.s.a`, `ph.d`.
fn is_multi_period_abbreviation(word: Word) -> Bool {
  word.periods >= 1 && word.parts_are_short_letters && word.part_length >= 1
}

fn starts_capitalised(rest: List(String)) -> Bool {
  case list.drop_while(rest, is_whitespace) {
    [next, ..] ->
      string.uppercase(next) == next && string.lowercase(next) != next
    [] -> False
  }
}

// Unicode white space (`White_Space=yes`). Checks every code point, so
// the single grapheme "\r\n" is whitespace too.
fn is_whitespace(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [] -> False
    codepoints ->
      list.all(codepoints, fn(codepoint) {
        is_whitespace_code(string.utf_codepoint_to_int(codepoint))
      })
  }
}

fn is_whitespace_code(n: Int) -> Bool {
  case n {
    0x20 | 0x85 | 0xa0 | 0x1680 | 0x2028 | 0x2029 | 0x202f | 0x205f | 0x3000 ->
      True
    _ if n >= 0x09 && n <= 0x0d -> True
    _ if n >= 0x2000 && n <= 0x200a -> True
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
/// 2. Keep only ASCII letters and accented Latin vowels (`é`, `ü`, ...).
/// 3. Count maximal vowel groups in `a e i o u y` and the accented
///    vowels, with `y` only counting at non-initial position.
/// 4. Subtract one if the word ends in a silent `e` (the preceding
///    letter being a consonant), except after consonant + `l`
///    (`table`, `syllable`).
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
/// Returns `0` for an empty input. Returns `1` for any other input with
/// none of the letters kept in step 2 (`"123"`, `"日本"`).
pub fn syllables_in_word(word: String) -> Int {
  let lowered = string.lowercase(word)
  let letters =
    lowered
    |> string.to_graphemes
    |> list.filter(keeping: is_syllable_relevant_letter)
  case letters {
    [] ->
      case has_any_grapheme(lowered) {
        True -> 1
        False -> 0
      }
    _ -> syllables_from_letters(letters)
  }
}

/// Letters that participate in the syllable heuristic — ASCII a–z
/// plus Latin-extended accented vowels. Accented consonants like
/// `ñ` / `ç` are out of scope here; they get filtered out the same
/// way uncommon graphemes do. See issue #20.
fn is_syllable_relevant_letter(g: String) -> Bool {
  case is_ascii_letter(g) {
    True -> True
    False -> is_vowel_letter(g, False)
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
    // Latin-1 accented vowels (Issue #20). The lower-case forms cover
    // input because the count pipeline lowercases letters before this
    // check, but the upper-case set is included for callers that
    // bypass that pipeline.
    "à" | "á" | "â" | "ã" | "ä" | "å" | "ā" | "ă" | "ą" -> True
    "è" | "é" | "ê" | "ë" | "ē" | "ĕ" | "ė" | "ę" | "ě" -> True
    "ì" | "í" | "î" | "ï" | "ĩ" | "ī" | "ĭ" | "į" -> True
    "ò" | "ó" | "ô" | "õ" | "ö" | "ø" | "ō" | "ŏ" | "ő" -> True
    "ù" | "ú" | "û" | "ü" | "ũ" | "ū" | "ŭ" | "ů" | "ű" | "ų" -> True
    "ý" | "ÿ" -> True
    "À" | "Á" | "Â" | "Ã" | "Ä" | "Å" | "Ā" | "Ă" | "Ą" -> True
    "È" | "É" | "Ê" | "Ë" | "Ē" | "Ĕ" | "Ė" | "Ę" | "Ě" -> True
    "Ì" | "Í" | "Î" | "Ï" | "Ĩ" | "Ī" | "Ĭ" | "Į" -> True
    "Ò" | "Ó" | "Ô" | "Õ" | "Ö" | "Ø" | "Ō" | "Ŏ" | "Ő" -> True
    "Ù" | "Ú" | "Û" | "Ü" | "Ũ" | "Ū" | "Ŭ" | "Ů" | "Ű" | "Ų" -> True
    "Ý" | "Ÿ" -> True
    "y" | "Y" ->
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
/// letters plus ASCII digits, **excluding** whitespace, punctuation,
/// symbols and emoji. Non-ASCII letters (Latin-1 accents, CJK
/// ideographs) also count.
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

/// Count words with three or more syllables in `text`. SMOG and
/// [`readability.gunning_fog`](./readability.html#gunning_fog) both use
/// this count with **no** exclusions.
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
