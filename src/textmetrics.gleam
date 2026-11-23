//// Compare text, build edit scripts, and estimate English readability.
////
//// String comparisons normalize to NFC using the target runtime and compare grapheme clusters. Generic list operations compare elements directly. Word, character, and sentence classification uses Unicode 17.0 data; runtime normalization and grapheme segmentation may use another Unicode version.
////
//// Readability functions return raw formula values and use an English syllable heuristic. Use `myers` or `patience` to build an edit script, then `to_unified` to render individual lines.

import gleam/dict.{type Dict}
import gleam/float
import gleam/int
import gleam/list
import gleam/option.{None, Some}
import gleam/order
import gleam/result
import gleam/set.{type Set}
import gleam/string
import textmetrics/internal/unicode
import textmetrics/internal/unicode_category

// --- words --------------------------------------------------------------

/// Count words: runs of letter-like graphemes.
///
/// After NFC normalization, a grapheme is letter-like when its first code point has Unicode 17.0 category Letter, Mark, Decimal_Number, or Letter_Number. An ASCII digit followed within its grapheme by a keycap mark (U+20E3) or emoji presentation selector (U+FE0F) is not. Following UAX #29, the punctuation it allows between two letters, such as an apostrophe, colon, or period (`don't`, `U.S.A`), and between two digits, such as a period, comma, semicolon, or apostrophe (`3.50`, `1,000`), keeps one word. Format characters such as the soft hyphen do not split a word, and Word_Break=Numeric characters such as U+066B ARABIC DECIMAL SEPARATOR count as digits. Whitespace, other punctuation including hyphens, symbols, and unassigned code points separate words. Empty input returns zero.
///
/// ## Examples
///
/// ```gleam
/// count_words("hello, world!")
/// // 2
/// count_words("don't stop")
/// // 2
/// count_words("")
/// // 0
/// ```
pub fn count_words(text: String) -> Int {
  fold_words(nfc_graphemes(text), 0, fn(count, _) { count + 1 })
}

fn is_letter_like(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [] -> False
    [first, ..rest] -> {
      let code = string.utf_codepoint_to_int(first)
      case is_letter_like_code(code) {
        True -> !is_emoji_sequence(code, rest)
        // Word_Break=Numeric outside the letter-like categories, such as
        // U+066B ARABIC DECIMAL SEPARATOR and the Prepend number signs
        // U+0600..U+0605 that begin a grapheme with the digits after them.
        False -> code >= 0x80 && unicode_category.is_word_numeric(code)
      }
    }
  }
}

// How a grapheme takes part in a word, from its first code point.
type WordClass {
  WordLetter
  WordDigit
  // Word_Break=Format: ignored inside a word (UAX #29 WB4).
  WordFormat
  // Joins two letters (WB6, WB7).
  JoinsLetters
  // Joins two digits (WB11, WB12).
  JoinsNumbers
  JoinsBoth
  WordSeparator
}

fn word_class(g: String) -> WordClass {
  case string.to_utf_codepoints(g) {
    [] -> WordSeparator
    [first, ..rest] -> {
      let code = string.utf_codepoint_to_int(first)
      case is_letter_like_code(code) {
        True ->
          case is_emoji_sequence(code, rest), is_digit_code(code) {
            True, _ -> WordSeparator
            False, True -> WordDigit
            False, False -> WordLetter
          }
        False ->
          case code >= 0x80 && unicode_category.is_word_numeric(code) {
            True -> WordDigit
            False -> non_letter_class(code)
          }
      }
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
    _ -> !unicode_category.is_non_letter(n)
  }
}

fn is_digit_code(n: Int) -> Bool {
  case n < 0x80 {
    True -> n >= 0x30 && n <= 0x39
    False -> unicode_category.is_word_numeric(n)
  }
}

fn non_letter_class(n: Int) -> WordClass {
  case
    unicode_category.is_word_format(n),
    unicode_category.joins_letters(n),
    unicode_category.joins_numbers(n)
  {
    True, _, _ -> WordFormat
    False, True, True -> JoinsBoth
    False, True, False -> JoinsLetters
    False, False, True -> JoinsNumbers
    False, False, False -> WordSeparator
  }
}

// Keep the existing digit emoji exclusion without discarding letters or
// non-ASCII decimal digits that happen to carry the same suffix marks.
fn is_emoji_sequence(first: Int, rest: List(UtfCodepoint)) -> Bool {
  first >= 0x30
  && first <= 0x39
  && list.any(rest, fn(codepoint) {
    let code = string.utf_codepoint_to_int(codepoint)
    code == 0x20e3 || code == 0xfe0f
  })
}

// The words of `graphemes`, each with the joining punctuation and format
// characters inside it.
fn word_chunks(graphemes: List(String)) -> List(String) {
  fold_words(graphemes, [], fn(words, reversed) {
    [reversed |> list.reverse |> string.concat, ..words]
  })
  |> list.reverse
}

// Calls `add` with each word's graphemes in reverse order.
fn fold_words(
  graphemes: List(String),
  initial: acc,
  add: fn(acc, List(String)) -> acc,
) -> acc {
  graphemes
  |> list.map(fn(g) { #(g, word_class(g)) })
  |> fold_words_loop([], WordSeparator, initial, add)
}

// `current` is the word so far in reverse, and `last` the class of its
// last letter or digit.
fn fold_words_loop(
  items: List(#(String, WordClass)),
  current: List(String),
  last: WordClass,
  acc: acc,
  add: fn(acc, List(String)) -> acc,
) -> acc {
  case items {
    [] -> finish_word(current, acc, add)
    [#(g, class), ..rest] ->
      case class, current {
        WordLetter, _ | WordDigit, _ ->
          fold_words_loop(rest, [g, ..current], class, acc, add)
        WordFormat, [] -> fold_words_loop(rest, [], last, acc, add)
        WordFormat, _ -> fold_words_loop(rest, [g, ..current], last, acc, add)
        WordSeparator, _ | _, [] ->
          fold_words_loop(
            rest,
            [],
            WordSeparator,
            finish_word(current, acc, add),
            add,
          )
        joiner, _ ->
          case joins(joiner, last, next_word_class(rest)) {
            True -> fold_words_loop(rest, [g, ..current], last, acc, add)
            False ->
              fold_words_loop(
                rest,
                [],
                WordSeparator,
                finish_word(current, acc, add),
                add,
              )
          }
      }
  }
}

fn finish_word(
  current: List(String),
  acc: acc,
  add: fn(acc, List(String)) -> acc,
) -> acc {
  case current {
    [] -> acc
    _ -> add(acc, current)
  }
}

fn next_word_class(items: List(#(String, WordClass))) -> WordClass {
  case items {
    [] -> WordSeparator
    [#(_, WordFormat), ..rest] -> next_word_class(rest)
    [#(_, class), ..] -> class
  }
}

fn joins(joiner: WordClass, before: WordClass, after: WordClass) -> Bool {
  case joiner, before, after {
    JoinsLetters, WordLetter, WordLetter
    | JoinsBoth, WordLetter, WordLetter
    | JoinsNumbers, WordDigit, WordDigit
    | JoinsBoth, WordDigit, WordDigit
    -> True
    _, _, _ -> False
  }
}

fn nfc_graphemes(text: String) -> List(String) {
  string.to_graphemes(unicode.to_nfc(text))
}

// --- sentences -----------------------------------------------------------

/// Count sentence boundaries and an unfinished final sentence.
///
/// Recognize `.`, `!`, `?`, `…`, `。`, `．`, `！`, `？`, `।`, and `॥`. Consecutive terminators count as one boundary, and quotation marks or brackets directly after a terminator belong to the sentence it ends, as in `He said "Hi."`. A trailing nonempty fragment counts as a sentence. Empty input returns zero.
///
/// A period followed directly by a letter or digit does not end a sentence, as in `3.50` or `example.com`. Common English abbreviations such as `Dr.`, `Mrs.`, and weekday or month abbreviations also keep their period. For multi-period abbreviations such as `e.g.`, `p.m.`, and `U.S.A.`, a following capitalized word starts a new sentence; a lowercase word continues the current one.
pub fn count_sentences(text: String) -> Int {
  sentences_from_graphemes(nfc_graphemes(text))
}

fn sentences_from_graphemes(graphemes: List(String)) -> Int {
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
          case in_terminator && is_sentence_close(g) {
            // Closing quotes and brackets belong to the sentence that
            // just ended (UAX #29 SB9).
            True -> sentence_loop(rest, saw_content, True, empty_word, acc)
            False ->
              sentence_loop(
                rest,
                True,
                False,
                push_grapheme(current_word, g),
                acc,
              )
          }
      }
    }
  }
}

fn is_sentence_close(g: String) -> Bool {
  case string.to_utf_codepoints(g) {
    [first, ..] ->
      unicode_category.is_sentence_close(string.utf_codepoint_to_int(first))
    [] -> False
  }
}

fn is_terminator(g: String) -> Bool {
  case g {
    "." | "!" | "?" | "…" | "。" | "．" | "！" | "？" | "।" | "॥" -> True
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

// Looks past closing quotes and brackets as well as whitespace, so
// `U.S.A." She` starts a new sentence.
fn starts_capitalised(rest: List(String)) -> Bool {
  case
    list.drop_while(rest, fn(g) { is_whitespace(g) || is_sentence_close(g) })
  {
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

/// Estimate a word's syllable count with an English heuristic.
///
/// Normalize to NFC and lowercase, keep ASCII letters and the supported accented Latin vowels, then count vowel groups. A noninitial `y` counts as a vowel. Subtract a trailing silent `e` except after consonant-plus-`l`, as in `table`. Return at least one for every nonempty input, including input with no retained letters. Empty input returns zero.
///
/// This function does not detect language. Applying the heuristic to a non-English word can return more than one syllable.
pub fn count_syllables_in_word(word: String) -> Int {
  word_syllables(unicode.to_nfc(word))
}

fn word_syllables(word: String) -> Int {
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
  int.max(with_silent_e, 1)
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
    // Latin-1 accented vowels (Issue #20). Callers lowercase first.
    "à" | "á" | "â" | "ã" | "ä" | "å" | "ā" | "ă" | "ą" -> True
    "è" | "é" | "ê" | "ë" | "ē" | "ĕ" | "ė" | "ę" | "ě" -> True
    "ì" | "í" | "î" | "ï" | "ĩ" | "ī" | "ĭ" | "į" -> True
    "ò" | "ó" | "ô" | "õ" | "ö" | "ø" | "ō" | "ŏ" | "ő" -> True
    "ù" | "ú" | "û" | "ü" | "ũ" | "ū" | "ŭ" | "ů" | "ű" | "ų" -> True
    "ý" | "ÿ" -> True
    "y" -> !at_start
    _ -> False
  }
}

fn ends_with_silent_e(letters: List(String)) -> Bool {
  case last_three(letters) {
    // "...Cle" (consonant + l + e, as in "syllable" or "table") ends in
    // the syllable /-əl/, so the `e` is not silent. After a vowel
    // ("...Vle") the vowel already counted, so it is.
    [before_l, "l", "e"] -> is_vowel_letter(before_l, False)
    [_, previous, "e"] | [previous, "e"] -> !is_vowel_letter(previous, False)
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

/// Sum syllable estimates over the words in a text.
///
/// Use `count_words`'s boundaries and `count_syllables_in_word`'s heuristic. Input without words returns zero.
pub fn count_syllables(text: String) -> Int {
  word_chunks(nfc_graphemes(text))
  |> list.fold(0, fn(acc, w) { acc + word_syllables(w) })
}

// --- characters / polysyllables / paragraphs ----------------------------

/// Count letter-like graphemes used by the readability formulas.
///
/// Use the same Unicode categories and exclusions as `count_words`, counting individual graphemes rather than runs. Letters and decimal digits from different scripts count. Empty input returns zero.
pub fn count_characters(text: String) -> Int {
  characters_from_graphemes(nfc_graphemes(text))
}

fn characters_from_graphemes(graphemes: List(String)) -> Int {
  graphemes
  |> list.fold(0, fn(acc, g) {
    case is_letter_like(g) {
      True -> acc + 1
      False -> acc
    }
  })
}

/// Count words whose estimated syllable count is at least three.
///
/// Use the same word boundaries and syllable heuristic as `count_syllables`. Do not exclude proper nouns or inflected words.
pub fn count_polysyllables(text: String) -> Int {
  word_chunks(nfc_graphemes(text))
  |> list.fold(0, fn(acc, w) {
    case word_syllables(w) >= 3 {
      True -> acc + 1
      False -> acc
    }
  })
}

/// Count runs of nonblank lines separated by blank lines.
///
/// Ignore leading and trailing blank lines. Empty input returns zero.
pub fn count_paragraphs(text: String) -> Int {
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

/// Report unequal grapheme counts after NFC normalization.
pub type HammingError {
  LengthMismatch(left: Int, right: Int)
}

/// Count the minimum single-grapheme insertions, deletions, and substitutions between two strings.
///
/// Normalize both strings to NFC before comparing graphemes. Two empty strings have distance zero; the distance from an empty string is the other's grapheme count.
///
/// ## Examples
///
/// ```gleam
/// levenshtein("kitten", "sitting")
/// // 3
/// levenshtein("Á", "A\u{0301}")
/// // 0
/// ```
pub fn levenshtein(left: String, right: String) -> Int {
  levenshtein_list(nfc_graphemes(left), nfc_graphemes(right))
}

/// Convert Levenshtein distance to a similarity score from zero to one.
///
/// Return `1 - distance / max_length`, using NFC-normalized grapheme counts. Two empty strings return `1.0`; exactly one empty string returns `0.0`. A score of `1.0` means the normalized strings are equal.
pub fn levenshtein_similarity(left: String, right: String) -> Float {
  let a_graphemes = nfc_graphemes(left)
  let b_graphemes = nfc_graphemes(right)
  case int.max(list.length(a_graphemes), list.length(b_graphemes)) {
    0 -> 1.0
    longest -> {
      let distance = levenshtein_list(a_graphemes, b_graphemes)
      1.0 -. int.to_float(distance) /. int.to_float(longest)
    }
  }
}

/// Count the minimum insertions, deletions, and substitutions between two lists.
///
/// Compare elements with equality. Do not normalize strings stored inside the lists. Empty lists follow the same rules as `levenshtein`.
pub fn levenshtein_list(left: List(t), right: List(t)) -> Int {
  let m = list.length(left)
  let n = list.length(right)
  case m, n {
    0, _ -> n
    _, 0 -> m
    // The distance is symmetric; the shorter list sets the row length.
    _, _ if m < n -> levenshtein_outer(right, left, int_range_inclusive(0, m), 1)
    _, _ -> levenshtein_outer(left, right, int_range_inclusive(0, n), 1)
  }
}

fn levenshtein_outer(
  remaining_a: List(t),
  right_items: List(t),
  previous_row: List(Int),
  i: Int,
) -> Int {
  case remaining_a {
    [] -> last_or_zero(previous_row)
    [left_item, ..rest] -> {
      let current_row = case previous_row {
        [previous_first, ..previous_tail] ->
          levenshtein_inner(
            left_item,
            right_items,
            previous_first,
            previous_tail,
            i,
            [i],
          )
        [] -> [i]
      }
      levenshtein_outer(rest, right_items, current_row, i + 1)
    }
  }
}

fn levenshtein_inner(
  left_item: t,
  right_items: List(t),
  prev_diag: Int,
  previous_cells: List(Int),
  curr_left: Int,
  acc: List(Int),
) -> List(Int) {
  case right_items, previous_cells {
    [], _ -> list.reverse(acc)
    _, [] -> list.reverse(acc)
    [right_item, ..bs_rest], [prev_above, ..prev_more] -> {
      let sub_cost = case left_item == right_item {
        True -> 0
        False -> 1
      }
      let curr_j = min3(prev_above + 1, curr_left + 1, prev_diag + sub_cost)
      levenshtein_inner(left_item, bs_rest, prev_above, prev_more, curr_j, [
        curr_j,
        ..acc
      ])
    }
  }
}

/// Count edits including adjacent transpositions between NFC-normalized strings.
///
/// Insertion, deletion, substitution, and transposition each cost one. A substring may participate in more than one edit. For example, `"CA"` to `"ABC"` has distance two; `optimal_string_alignment` gives three.
pub fn damerau_levenshtein(left: String, right: String) -> Int {
  damerau_levenshtein_graphemes(nfc_graphemes(left), nfc_graphemes(right))
}

// Lowrance-Wagner. Row `i` of the table needs, besides row `i - 1`, the
// row before the last occurrence of `b[j]` in `a`; only those rows are
// kept, one per distinct grapheme of `a`, indexed for random access.
fn damerau_levenshtein_graphemes(a: List(String), b: List(String)) -> Int {
  case a, b {
    [], _ -> list.length(b)
    _, [] -> list.length(a)
    _, _ ->
      damerau_levenshtein_rows(
        a,
        b,
        1,
        int_range_inclusive(0, list.length(b)),
        dict.new(),
      )
  }
}

fn damerau_levenshtein_rows(
  remaining_a: List(t),
  b: List(t),
  i: Int,
  previous: List(Int),
  rows_before_last: Dict(t, #(Int, Array(Int))),
) -> Int {
  case remaining_a, previous {
    [], _ -> last_or_zero(previous)
    [item, ..rest], [previous_first, ..previous_rest] -> {
      let row =
        damerau_levenshtein_row(
          DamerauRow(item:, i:, rows_before_last:, j: 1, last_match_column: 0),
          b,
          previous_first,
          previous_rest,
          i,
          [i],
        )
      damerau_levenshtein_rows(
        rest,
        b,
        i + 1,
        row,
        dict.insert(rows_before_last, item, #(i, array_from_list(previous))),
      )
    }
    [_, ..], [] -> 0
  }
}

type DamerauRow(t) {
  DamerauRow(
    item: t,
    i: Int,
    rows_before_last: Dict(t, #(Int, Array(Int))),
    j: Int,
    // The last column `j' < j` of this row where `b[j'] == item`, or 0.
    last_match_column: Int,
  )
}

fn damerau_levenshtein_row(
  state: DamerauRow(t),
  b: List(t),
  previous_diagonal: Int,
  previous_rest: List(Int),
  left: Int,
  acc: List(Int),
) -> List(Int) {
  case b, previous_rest {
    [item_b, ..b_rest], [above, ..previous_more] -> {
      let DamerauRow(item:, i:, rows_before_last:, j:, last_match_column:) =
        state
      let cost = case item == item_b {
        True -> 0
        False -> 1
      }
      let best = min3(previous_diagonal + cost, left + 1, above + 1)
      // Transposition through the last `item_b` in `a` (row `k`) and the
      // last `item` in `b` (column `last_match_column`).
      let best = case dict.get(rows_before_last, item_b), last_match_column {
        Ok(#(k, row_before_k)), l if l > 0 ->
          case array_get(row_before_k, l - 1) {
            Ok(value) ->
              int.min(best, value + { i - k - 1 } + 1 + { j - l - 1 })
            Error(Nil) -> best
          }
        _, _ -> best
      }
      let last_match_column = case cost {
        0 -> j
        _ -> last_match_column
      }
      damerau_levenshtein_row(
        DamerauRow(..state, j: j + 1, last_match_column:),
        b_rest,
        above,
        previous_more,
        best,
        [best, ..acc],
      )
    }
    _, _ -> list.reverse(acc)
  }
}

/// Count insertions, deletions, substitutions, and adjacent transpositions with each substring edited at most once.
///
/// Normalize strings to NFC and compare graphemes. This restricted distance can exceed `damerau_levenshtein` and does not satisfy the triangle inequality.
pub fn optimal_string_alignment(left: String, right: String) -> Int {
  osa_graphemes(nfc_graphemes(left), nfc_graphemes(right))
}

fn osa_graphemes(a: List(String), b: List(String)) -> Int {
  let m = list.length(a)
  let n = list.length(b)
  case m, n {
    0, _ -> n
    _, 0 -> m
    // OSA is symmetric; the shorter list sets the row length.
    _, _ if m < n -> osa_rows(b, a, [], int_range_inclusive(0, m), [])
    _, _ -> osa_rows(a, b, [], int_range_inclusive(0, n), [])
  }
}

// `previous` and `before_previous` are rows `i - 1` and `i - 2` of the
// table; `previous_a` starts with `a[i - 1]`, or is empty in row 1.
// Carrying list cells instead of `Result`s avoids an allocation per cell.
fn osa_rows(
  remaining_a: List(t),
  b: List(t),
  previous_a: List(t),
  previous: List(Int),
  before_previous: List(Int),
) -> Int {
  case remaining_a, previous {
    [], _ -> last_or_zero(previous)
    [item, ..rest], [previous_first, ..previous_rest] -> {
      let i = previous_first + 1
      let row =
        osa_row(
          OsaRow(item:, previous_a:, previous_b: [], j: 1),
          b,
          previous_first,
          previous_rest,
          before_previous,
          i,
          [i],
        )
      osa_rows(rest, b, remaining_a, row, previous)
    }
    [_, ..], [] -> 0
  }
}

type OsaRow(t) {
  OsaRow(item: t, previous_a: List(t), previous_b: List(t), j: Int)
}

// `two_back` starts at column `j - 2` of row `i - 2` once `j >= 2`.
fn osa_row(
  state: OsaRow(t),
  b: List(t),
  previous_diagonal: Int,
  previous_rest: List(Int),
  two_back: List(Int),
  left: Int,
  acc: List(Int),
) -> List(Int) {
  case b, previous_rest {
    [item_b, ..b_rest], [above, ..previous_more] -> {
      let OsaRow(item:, previous_a:, previous_b:, j:) = state
      let cost = case item == item_b {
        True -> 0
        False -> 1
      }
      let best = min3(above + 1, left + 1, previous_diagonal + cost)
      let #(best, two_back) = case j >= 2, two_back {
        True, [diagonal_two_back, ..two_back_rest] -> {
          let best = case previous_a, previous_b {
            [before_item, ..], [before_item_b, ..]
              if item == before_item_b && before_item == item_b
            -> int.min(best, diagonal_two_back + 1)
            _, _ -> best
          }
          #(best, two_back_rest)
        }
        _, _ -> #(best, two_back)
      }
      osa_row(
        OsaRow(..state, previous_b: b, j: j + 1),
        b_rest,
        above,
        previous_more,
        two_back,
        best,
        [best, ..acc],
      )
    }
    _, _ -> list.reverse(acc)
  }
}

/// Count differing positions in two strings with equal grapheme counts.
///
/// Normalize both inputs to NFC first. Return `Error(LengthMismatch(left, right))` when their normalized grapheme counts differ. Two empty inputs return `Ok(0)`.
///
/// ## Examples
///
/// ```gleam
/// hamming("karolin", "kathrin")
/// // Ok(3)
/// hamming("ab", "abc")
/// // Error(LengthMismatch(2, 3))
/// ```
pub fn hamming(left: String, right: String) -> Result(Int, HammingError) {
  let a_graphemes = nfc_graphemes(left)
  let b_graphemes = nfc_graphemes(right)
  let a_length = list.length(a_graphemes)
  let b_length = list.length(b_graphemes)
  case a_length == b_length {
    False -> Error(LengthMismatch(a_length, b_length))
    True -> Ok(count_diffs(a_graphemes, b_graphemes, 0))
  }
}

fn count_diffs(a: List(String), b: List(String), acc: Int) -> Int {
  case a, b {
    [], [] -> acc
    [x, ..xs], [y, ..ys] ->
      case x == y {
        True -> count_diffs(xs, ys, acc)
        False -> count_diffs(xs, ys, acc + 1)
      }
    _, _ -> acc
  }
}

// ---------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------

fn last_or_zero(row: List(Int)) -> Int {
  result.unwrap(list.last(row), 0)
}

fn int_range_inclusive(start: Int, end: Int) -> List(Int) {
  int_range_inclusive_loop(start, end, [])
}

fn int_range_inclusive_loop(
  current: Int,
  end: Int,
  acc: List(Int),
) -> List(Int) {
  case current > end {
    True -> list.reverse(acc)
    False -> int_range_inclusive_loop(current + 1, end, [current, ..acc])
  }
}

fn min3(a: Int, b: Int, c: Int) -> Int {
  int.min(a, int.min(b, c))
}

/// Report a non-finite prefix scale, a scale outside `0.0..0.25`, or a negative prefix cap.
pub type JaroWinklerError {
  PrefixScaleOutOfRange(got: Float)
  PrefixMaxNegative(got: Int)
}

/// Calculate Jaro similarity over NFC-normalized graphemes.
///
/// Return a score from zero to one based on matching graphemes and the transpositions between their matched sequences. A transposition count is half the mismatched positions, rounded down, as in Winkler's reference code and the rapidfuzz and jellyfish libraries. Two empty inputs return `1.0`; exactly one empty input returns `0.0`.
pub fn jaro(left: String, right: String) -> Float {
  jaro_graphemes(nfc_graphemes(left), nfc_graphemes(right))
}

/// Calculate Jaro similarity with a boost for a shared prefix.
///
/// Require a finite `prefix_scale` in `0.0..0.25` and `prefix_max >= 0`. Validate the scale, then the cap, before checking the input strings. Apply the boost only when the Jaro score is greater than `0.7`. Cap the prefix contribution so that scale times prefix length does not exceed one. Conventional parameters are `0.1` and `4`.
///
/// Normalize inputs to NFC. Two empty inputs return `Ok(1.0)`; exactly one empty input returns `Ok(0.0)`. A zero scale or zero prefix cap gives the Jaro score. Different strings can score `1.0` when the prefix boost saturates.
pub fn jaro_winkler(
  left: String,
  right: String,
  prefix_scale scale: Float,
  prefix_max maximum: Int,
) -> Result(Float, JaroWinklerError) {
  case scale >=. 0.0 && scale <=. 0.25 {
    False -> Error(PrefixScaleOutOfRange(scale))
    True ->
      case maximum < 0 {
        True -> Error(PrefixMaxNegative(maximum))
        False ->
          Ok(jaro_winkler_graphemes(
            nfc_graphemes(left),
            nfc_graphemes(right),
            scale,
            maximum,
          ))
      }
  }
}

/// Compare multisets of NFC-normalized grapheme n-grams with the Sørensen-Dice coefficient.
///
/// Require `ngram_size >= 1`; otherwise return `Error(Nil)`. Count repeated n-grams with their multiplicity. If both inputs are shorter than the n-gram size, return `Ok(1.0)` for equal normalized strings and `Ok(0.0)` otherwise. If only one lacks n-grams, return `Ok(0.0)`.
///
/// Different strings can have the same n-gram multiset and score `1.0`.
///
/// ## Examples
///
/// ```gleam
/// sorensen_dice("night", "nacht", ngram_size: 2)
/// // Ok(0.25)
/// sorensen_dice("a", "b", ngram_size: 0)
/// // Error(Nil)
/// ```
pub fn sorensen_dice(
  left: String,
  right: String,
  ngram_size size: Int,
) -> Result(Float, Nil) {
  case size < 1 {
    True -> Error(Nil)
    False -> {
      let a_graphemes = nfc_graphemes(left)
      let b_graphemes = nfc_graphemes(right)
      let a_ngrams = build_ngrams(a_graphemes, size)
      let b_ngrams = build_ngrams(b_graphemes, size)
      case list.length(a_ngrams) + list.length(b_ngrams) {
        0 ->
          case a_graphemes == b_graphemes {
            True -> Ok(1.0)
            False -> Ok(0.0)
          }
        total -> {
          let a_multiset = list.fold(a_ngrams, dict.new(), increment_count)
          let b_multiset = list.fold(b_ngrams, dict.new(), increment_count)
          let shared = intersection_size(a_multiset, b_multiset)
          Ok(int.to_float(2 * shared) /. int.to_float(total))
        }
      }
    }
  }
}

// --- Sørensen-Dice internals ---------------------------------------------

fn build_ngrams(graphemes: List(String), size: Int) -> List(String) {
  list.window(graphemes, by: size) |> list.map(string.concat)
}

fn increment_count(acc: Dict(String, Int), key: String) -> Dict(String, Int) {
  dict.upsert(acc, key, fn(existing) {
    case existing {
      Some(count) -> count + 1
      None -> 1
    }
  })
}

fn intersection_size(a: Dict(String, Int), b: Dict(String, Int)) -> Int {
  dict.fold(a, 0, fn(acc, key, count_a) {
    case dict.get(b, key) {
      Ok(count_b) -> acc + int.min(count_a, count_b)
      Error(_) -> acc
    }
  })
}

/// Return the length of a longest subsequence shared by two lists.
///
/// Compare elements directly without string normalization. Return zero when either list is empty.
pub fn longest_common_subsequence_length(left: List(t), right: List(t)) -> Int {
  let n = list.length(right)
  case left, right {
    [], _ -> 0
    _, [] -> 0
    _, _ -> {
      let initial_prev = list.repeat(0, n + 1)
      lcs_length_outer(left, right, initial_prev)
    }
  }
}

fn lcs_length_outer(
  remaining_a: List(t),
  right_items: List(t),
  previous_row: List(Int),
) -> Int {
  case remaining_a {
    [] ->
      case list.last(previous_row) {
        Ok(v) -> v
        Error(_) -> 0
      }
    [left_item, ..rest] -> {
      let current_row = case previous_row {
        [_, ..previous_tail] ->
          lcs_length_inner(left_item, right_items, 0, previous_tail, 0, [0])
        [] -> [0]
      }
      lcs_length_outer(rest, right_items, current_row)
    }
  }
}

fn lcs_length_inner(
  left_item: t,
  right_items: List(t),
  prev_diag: Int,
  previous_cells: List(Int),
  curr_left: Int,
  acc: List(Int),
) -> List(Int) {
  case right_items, previous_cells {
    [], _ -> list.reverse(acc)
    _, [] -> list.reverse(acc)
    [right_item, ..bs_rest], [prev_above, ..prev_more] -> {
      let curr_j = case left_item == right_item {
        True -> prev_diag + 1
        False -> int.max(prev_above, curr_left)
      }
      lcs_length_inner(left_item, bs_rest, prev_above, prev_more, curr_j, [
        curr_j,
        ..acc
      ])
    }
  }
}

/// Return one longest subsequence shared by two lists.
///
/// Preserve element order and compare elements directly. If several longest subsequences exist, do not rely on which is chosen. Empty input on either side returns an empty list.
pub fn longest_common_subsequence(left: List(t), right: List(t)) -> List(t) {
  let m = list.length(left)
  let n = list.length(right)
  case m == 0 || n == 0 {
    True -> []
    False -> {
      let block = block_size(m, 1)
      let first_row = list.repeat(0, n + 1)
      let checkpoints =
        forward_checkpoints(left, right, block, 0, first_row, [
          Checkpoint(index: 0, row: first_row, rest_of_a: left),
        ])
      backtrack_blocks(
        checkpoints,
        m,
        n,
        n,
        list.reverse(left),
        list.reverse(right),
        right,
        [],
      )
    }
  }
}

// The table is never held in full. The forward pass keeps every
// `block`-th row; the backtrack then recomputes one block of rows at a
// time, from the last block up, and walks it with the same rule as a
// full-table backtrack: take a match, otherwise move up when that keeps
// the length, otherwise move left.
type Checkpoint(t) {
  Checkpoint(index: Int, row: List(Int), rest_of_a: List(t))
}

fn block_size(m: Int, size: Int) -> Int {
  case size * size >= m {
    True -> size
    False -> block_size(m, size + 1)
  }
}

// Row `i + 1` of the table from row `i`, where `item` is `a[i]`.
fn next_row(item: t, b: List(t), row: List(Int)) -> List(Int) {
  case row {
    [_, ..rest] -> lcs_length_inner(item, b, 0, rest, 0, [0])
    [] -> [0]
  }
}

// Returns the checkpoints with the latest first. Row `m` is not kept.
fn forward_checkpoints(
  remaining_a: List(t),
  b: List(t),
  block: Int,
  index: Int,
  row: List(Int),
  checkpoints: List(Checkpoint(t)),
) -> List(Checkpoint(t)) {
  case remaining_a {
    [] -> checkpoints
    [item, ..rest] -> {
      let row = next_row(item, b, row)
      let index = index + 1
      let checkpoints = case rest, index % block {
        [_, ..], 0 -> [Checkpoint(index:, row:, rest_of_a: rest), ..checkpoints]
        _, _ -> checkpoints
      }
      forward_checkpoints(rest, b, block, index, row, checkpoints)
    }
  }
}

// `i` and `j` are the current cell; `reversed_a` and `reversed_b` start
// with `a[i - 1]` and `b[j - 1]`.
fn backtrack_blocks(
  checkpoints: List(Checkpoint(t)),
  i: Int,
  j: Int,
  n: Int,
  reversed_a: List(t),
  reversed_b: List(t),
  b: List(t),
  acc: List(t),
) -> List(t) {
  case checkpoints, i > 0 && j > 0 {
    [Checkpoint(index: lower, row:, rest_of_a:), ..earlier], True -> {
      // Rows `i` down to `lower`, each reversed so that it is read from
      // column `n` down to column 0.
      let rows =
        list.take(rest_of_a, i - lower)
        |> list.fold(#(row, [list.reverse(row)]), fn(state, item) {
          let #(previous, rows) = state
          let next = next_row(item, b, previous)
          #(next, [list.reverse(next), ..rows])
        })
      case rows.1 {
        [current, above, ..rest] -> {
          let #(i, j, reversed_a, reversed_b, acc) =
            backtrack_block(
              Cursor(i:, j:, reversed_a:, reversed_b:, acc:),
              lower,
              n,
              list.drop(current, n - j),
              list.drop(above, n - j),
              rest,
            )
          backtrack_blocks(earlier, i, j, n, reversed_a, reversed_b, b, acc)
        }
        _ -> acc
      }
    }
    _, _ -> acc
  }
}

type Cursor(t) {
  Cursor(i: Int, j: Int, reversed_a: List(t), reversed_b: List(t), acc: List(t))
}

// `current` and `above` are rows `i` and `i - 1` from column `j` down;
// `rest` holds the full reversed rows `i - 2` down to `lower`.
fn backtrack_block(
  cursor: Cursor(t),
  lower: Int,
  n: Int,
  current: List(Int),
  above: List(Int),
  rest: List(List(Int)),
) -> #(Int, Int, List(t), List(t), List(t)) {
  let Cursor(i:, j:, reversed_a:, reversed_b:, acc:) = cursor
  case i > lower && j > 0, reversed_a, reversed_b {
    True, [item_a, ..more_a], [item_b, ..more_b] ->
      case item_a == item_b {
        True -> {
          let #(next_above, next_rest) = row_at(rest, n - j + 1)
          backtrack_block(
            Cursor(
              i: i - 1,
              j: j - 1,
              reversed_a: more_a,
              reversed_b: more_b,
              acc: [item_a, ..acc],
            ),
            lower,
            n,
            list.drop(above, 1),
            next_above,
            next_rest,
          )
        }
        False ->
          case first(above) >= first(list.drop(current, 1)) {
            True -> {
              let #(next_above, next_rest) = row_at(rest, n - j)
              backtrack_block(
                Cursor(..cursor, i: i - 1, reversed_a: more_a),
                lower,
                n,
                above,
                next_above,
                next_rest,
              )
            }
            False ->
              backtrack_block(
                Cursor(..cursor, j: j - 1, reversed_b: more_b),
                lower,
                n,
                list.drop(current, 1),
                list.drop(above, 1),
                rest,
              )
          }
      }
    _, _, _ -> #(i, j, reversed_a, reversed_b, acc)
  }
}

fn row_at(rows: List(List(Int)), skip: Int) -> #(List(Int), List(List(Int))) {
  case rows {
    [row, ..rest] -> #(list.drop(row, skip), rest)
    [] -> #([], [])
  }
}

fn first(row: List(Int)) -> Int {
  case row {
    [value, ..] -> value
    [] -> 0
  }
}

/// Represent one element of an edit script.
///
/// `Equal` retains an element present in both inputs, `Delete` removes an old element, and `Insert` adds a new element. A script is a `List(Edit(a))`.
pub type Edit(a) {
  Equal(item: a)
  Insert(item: a)
  Delete(item: a)
}

/// Group consecutive edit steps of the same kind.
///
/// Each variant holds its elements in their original order. `edit_runs` produces nonempty runs.
pub type Run(a) {
  EqualRun(items: List(a))
  InsertRun(items: List(a))
  DeleteRun(items: List(a))
}

/// Recover the original list from an edit script's Equal and Delete steps.
pub fn recover_old(script: List(Edit(a))) -> List(a) {
  do_recover_old(script, [])
}

fn do_recover_old(script: List(Edit(a)), acc: List(a)) -> List(a) {
  case script {
    [] -> list.reverse(acc)
    [Equal(item), ..rest] -> do_recover_old(rest, [item, ..acc])
    [Delete(item), ..rest] -> do_recover_old(rest, [item, ..acc])
    [Insert(_), ..rest] -> do_recover_old(rest, acc)
  }
}

/// Recover the new list from an edit script's Equal and Insert steps.
pub fn recover_new(script: List(Edit(a))) -> List(a) {
  do_recover_new(script, [])
}

fn do_recover_new(script: List(Edit(a)), acc: List(a)) -> List(a) {
  case script {
    [] -> list.reverse(acc)
    [Equal(item), ..rest] -> do_recover_new(rest, [item, ..acc])
    [Insert(item), ..rest] -> do_recover_new(rest, [item, ..acc])
    [Delete(_), ..rest] -> do_recover_new(rest, acc)
  }
}

/// Count insertion and deletion steps in an edit script.
///
/// Equal steps contribute zero. For a script from `myers`, this is the minimum insertion-and-deletion distance.
pub fn edit_cost(script: List(Edit(a))) -> Int {
  do_cost(script, 0)
}

fn do_cost(script: List(Edit(a)), acc: Int) -> Int {
  case script {
    [] -> acc
    [Equal(_), ..rest] -> do_cost(rest, acc)
    [Insert(_), ..rest] -> do_cost(rest, acc + 1)
    [Delete(_), ..rest] -> do_cost(rest, acc + 1)
  }
}

/// Group consecutive edits of the same kind, preserving their element order.
///
/// Empty input returns an empty list.
pub fn edit_runs(script: List(Edit(a))) -> List(Run(a)) {
  do_runs(script, [])
}

fn do_runs(script: List(Edit(a)), acc: List(Run(a))) -> List(Run(a)) {
  case script {
    [] -> list.reverse(acc)
    [Equal(item), ..rest] -> {
      let #(items, remaining) = take_while_equal(rest, [item])
      do_runs(remaining, [EqualRun(items), ..acc])
    }
    [Insert(item), ..rest] -> {
      let #(items, remaining) = take_while_insert(rest, [item])
      do_runs(remaining, [InsertRun(items), ..acc])
    }
    [Delete(item), ..rest] -> {
      let #(items, remaining) = take_while_delete(rest, [item])
      do_runs(remaining, [DeleteRun(items), ..acc])
    }
  }
}

fn take_while_equal(
  script: List(Edit(a)),
  acc: List(a),
) -> #(List(a), List(Edit(a))) {
  case script {
    [Equal(item), ..rest] -> take_while_equal(rest, [item, ..acc])
    [Insert(_), ..] | [Delete(_), ..] | [] -> #(list.reverse(acc), script)
  }
}

fn take_while_insert(
  script: List(Edit(a)),
  acc: List(a),
) -> #(List(a), List(Edit(a))) {
  case script {
    [Insert(item), ..rest] -> take_while_insert(rest, [item, ..acc])
    [Equal(_), ..] | [Delete(_), ..] | [] -> #(list.reverse(acc), script)
  }
}

fn take_while_delete(
  script: List(Edit(a)),
  acc: List(a),
) -> #(List(a), List(Edit(a))) {
  case script {
    [Delete(item), ..rest] -> take_while_delete(rest, [item, ..acc])
    [Equal(_), ..] | [Insert(_), ..] | [] -> #(list.reverse(acc), script)
  }
}

/// Report an invalid filename, context-line count, or line for unified diff output.
pub type UnifiedError {
  ContextLinesNegative(got: Int)
  NameContainsForbiddenBytes(field: NameField, value: String)
  /// A script element contained a line feed, so it was not a single line.
  LineContainsNewline(line: String)
}

/// Identify the old or new filename rejected by unified diff validation.
pub type NameField {
  OldName
  NewName
}

/// Build a shortest insertion-and-deletion edit script between two lists.
///
/// Use Myers' algorithm and compare elements directly. Applying `recover_old` and `recover_new` to the script reconstructs the inputs. Substitution is represented by a deletion and an insertion.
pub fn myers(old: List(a), new: List(a)) -> List(Edit(a)) {
  // The forward search always matches the common prefix first, so it
  // is taken off before the O(ND) search. The common suffix is left in:
  // stripping it would change which of several optimal scripts the
  // search returns.
  let #(reversed_prefix, old, new) = split_common_prefix(old, new, [])
  list.fold(reversed_prefix, myers_middle(old, new), fn(script, item) {
    [item, ..script]
  })
}

// Returns the common prefix as `Equal` edits in reverse order, and the
// rest of both lists.
fn split_common_prefix(
  old: List(a),
  new: List(a),
  reversed_prefix: List(Edit(a)),
) -> #(List(Edit(a)), List(a), List(a)) {
  case old, new {
    [x, ..old_rest], [y, ..new_rest] if x == y ->
      split_common_prefix(old_rest, new_rest, [Equal(x), ..reversed_prefix])
    _, _ -> #(reversed_prefix, old, new)
  }
}

fn myers_middle(old: List(a), new: List(a)) -> List(Edit(a)) {
  let old_length = list.length(old)
  let new_length = list.length(new)
  case old_length, new_length {
    0, 0 -> []
    0, _ -> list.map(new, fn(item) { Insert(item) })
    _, 0 -> list.map(old, fn(item) { Delete(item) })
    _, _ -> {
      let sides =
        Sides(
          old: array_from_list(old),
          new: array_from_list(new),
          old_length:,
          new_length:,
        )
      // Every `interval`-th frontier is kept; the backtrack recomputes the
      // frontiers between two checkpoints when it reaches them. This keeps
      // memory near O(D * sqrt(n + m)) instead of O(D^2).
      let interval = block_size(old_length + new_length, 1)
      let #(final_d, final_x, final_y, checkpoints) =
        myers_search(sides, interval, 0, Error(Nil), [])
      myers_backtrack(
        sides,
        checkpoints,
        final_d,
        final_x,
        final_y,
        final_d,
        [],
      )
    }
  }
}

type Sides(a) {
  Sides(old: Array(a), new: Array(a), old_length: Int, new_length: Int)
}

// The furthest-reaching x of every diagonal `k = -d, -d + 2, .., d` after
// `d` steps, at index `(k + d) / 2`.
type Frontier {
  Frontier(d: Int, xs: Array(Int))
}

fn frontier_get(frontier: Frontier, k: Int, default: Int) -> Int {
  let offset = k + frontier.d
  let index = offset / 2
  case offset >= 0 && offset % 2 == 0 && index < array_size(frontier.xs) {
    True -> array_at(frontier.xs, index)
    False -> default
  }
}

// Returns the number of steps, the end point, and the checkpoints with
// the latest first.
fn myers_search(
  sides: Sides(a),
  interval: Int,
  d: Int,
  previous: Result(Frontier, Nil),
  checkpoints: List(Frontier),
) -> #(Int, Int, Int, List(Frontier)) {
  case myers_step(sides, d, previous, -d, []) {
    Error(#(final_x, final_y)) -> #(d, final_x, final_y, checkpoints)
    Ok(frontier) -> {
      let checkpoints = case d % interval {
        0 -> [frontier, ..checkpoints]
        _ -> checkpoints
      }
      myers_search(sides, interval, d + 1, Ok(frontier), checkpoints)
    }
  }
}

// The frontier after step `d`, or `Error` with the end point when a
// diagonal reaches it.
fn myers_step(
  sides: Sides(a),
  d: Int,
  previous: Result(Frontier, Nil),
  k: Int,
  reversed_xs: List(Int),
) -> Result(Frontier, #(Int, Int)) {
  case k > d {
    True -> Ok(Frontier(d:, xs: array_from_list(list.reverse(reversed_xs))))
    False -> {
      let x = case previous {
        // Before the first step only diagonal 1 is known, at x = 0.
        Error(Nil) -> 0
        Ok(frontier) -> {
          let previous_diagonal = frontier_get(frontier, k - 1, -1)
          let next_diagonal = frontier_get(frontier, k + 1, -1)
          case k == -d || { k != d && previous_diagonal < next_diagonal } {
            True -> next_diagonal
            False -> previous_diagonal + 1
          }
        }
      }
      let #(final_x, final_y) = follow_snake(sides, x, x - k)
      case final_x >= sides.old_length && final_y >= sides.new_length {
        True -> Error(#(final_x, final_y))
        False -> myers_step(sides, d, previous, k + 2, [final_x, ..reversed_xs])
      }
    }
  }
}

fn follow_snake(sides: Sides(a), x: Int, y: Int) -> #(Int, Int) {
  case x >= 0 && y >= 0 && x < sides.old_length && y < sides.new_length {
    False -> #(x, y)
    // Both indices are in range here.
    True ->
      case array_at(sides.old, x) == array_at(sides.new, y) {
        True -> follow_snake(sides, x + 1, y + 1)
        False -> #(x, y)
      }
  }
}

// Walks back from step `d` at `(x, y)`. `checkpoints` (latest first) hold
// frontiers up to `available`; the frontiers in between are rebuilt one
// block at a time.
fn myers_backtrack(
  sides: Sides(a),
  checkpoints: List(Frontier),
  d: Int,
  x: Int,
  y: Int,
  available: Int,
  acc: List(Edit(a)),
) -> List(Edit(a)) {
  case d, checkpoints {
    0, _ | _, [] -> walk_diagonal_back(sides, x, y, 0, 0, acc).2
    _, [checkpoint, ..earlier] -> {
      // Frontiers `available - 1` down to the checkpoint, latest first.
      let block =
        rebuild_frontiers(sides, checkpoint, available - 1, [checkpoint])
      let #(d, x, y, acc) = myers_backtrack_block(sides, block, d, x, y, acc)
      myers_backtrack(sides, earlier, d, x, y, checkpoint.d, acc)
    }
  }
}

fn rebuild_frontiers(
  sides: Sides(a),
  latest: Frontier,
  last: Int,
  acc: List(Frontier),
) -> List(Frontier) {
  case latest.d >= last {
    True -> acc
    False ->
      case myers_step(sides, latest.d + 1, Ok(latest), -latest.d - 1, []) {
        Ok(next) -> rebuild_frontiers(sides, next, last, [next, ..acc])
        // Only the final step reaches the end, and it is never rebuilt.
        Error(_) -> acc
      }
  }
}

// `frontiers` starts with the frontier after step `d - 1`.
fn myers_backtrack_block(
  sides: Sides(a),
  frontiers: List(Frontier),
  d: Int,
  x: Int,
  y: Int,
  acc: List(Edit(a)),
) -> #(Int, Int, Int, List(Edit(a))) {
  case d, frontiers {
    0, _ | _, [] -> #(d, x, y, acc)
    _, [frontier, ..earlier] -> {
      let k = x - y
      let previous_diagonal = frontier_get(frontier, k - 1, -1)
      let next_diagonal = frontier_get(frontier, k + 1, -1)
      let previous_k = case
        k == -d || { k != d && previous_diagonal < next_diagonal }
      {
        True -> k + 1
        False -> k - 1
      }
      let previous_x = frontier_get(frontier, previous_k, 0)
      let previous_y = previous_x - previous_k
      let #(x2, y2, acc) =
        walk_diagonal_back(sides, x, y, previous_x, previous_y, acc)
      let #(x, y, acc) = case x2 > previous_x, y2 > previous_y {
        True, _ ->
          case array_get(sides.old, x2 - 1) {
            Ok(item) -> #(x2 - 1, y2, [Delete(item), ..acc])
            Error(_) -> #(previous_x, previous_y, acc)
          }
        False, True ->
          case array_get(sides.new, y2 - 1) {
            Ok(item) -> #(x2, y2 - 1, [Insert(item), ..acc])
            Error(_) -> #(previous_x, previous_y, acc)
          }
        False, False -> #(previous_x, previous_y, acc)
      }
      myers_backtrack_block(sides, earlier, d - 1, x, y, acc)
    }
  }
}

fn walk_diagonal_back(
  sides: Sides(a),
  x: Int,
  y: Int,
  low_x: Int,
  low_y: Int,
  acc: List(Edit(a)),
) -> #(Int, Int, List(Edit(a))) {
  case x > low_x && y > low_y {
    False -> #(x, y, acc)
    True ->
      case array_get(sides.old, x - 1) {
        Ok(item) ->
          walk_diagonal_back(sides, x - 1, y - 1, low_x, low_y, [
            Equal(item),
            ..acc
          ])
        Error(_) -> #(x, y, acc)
      }
  }
}

// A fixed-size array with constant-time reads: a tuple on Erlang and an
// Array on JavaScript.
type Array(a)

@external(erlang, "textmetrics_ffi", "array_from_list")
@external(javascript, "./textmetrics_ffi.mjs", "array_from_list")
fn array_from_list(items: List(a)) -> Array(a)

@external(erlang, "textmetrics_ffi", "array_size")
@external(javascript, "./textmetrics_ffi.mjs", "array_size")
fn array_size(array: Array(a)) -> Int

// Reads an index that the caller has checked against `array_size`.
@external(erlang, "textmetrics_ffi", "array_at")
@external(javascript, "./textmetrics_ffi.mjs", "array_at")
fn array_at(array: Array(a), index: Int) -> a

fn array_get(array: Array(a), index: Int) -> Result(a, Nil) {
  case index >= 0 && index < array_size(array) {
    True -> Ok(array_at(array, index))
    False -> Error(Nil)
  }
}

/// Build an edit script using unique common lines as anchors.
///
/// Use patience diff for `List(String)` and Myers diff between anchors. Compare strings directly without NFC normalization. The script reconstructs both inputs, but need not minimize the edit count.
pub fn patience(old: List(String), new: List(String)) -> List(Edit(String)) {
  patience_loop([Segment(old:, new:)], [])
}

// Work still to do, in output order. Segments are expanded in place
// instead of recursing, so deeply nested inputs do not grow the stack.
type PatienceTask {
  Segment(old: List(String), new: List(String))
  Anchor(line: String)
}

fn patience_loop(
  tasks: List(PatienceTask),
  acc: List(List(Edit(String))),
) -> List(Edit(String)) {
  case tasks {
    [] -> list.reverse(acc) |> list.flatten
    [Anchor(line:), ..rest] -> patience_loop(rest, [[Equal(line)], ..acc])
    [Segment(old: [], new: []), ..rest] -> patience_loop(rest, acc)
    [Segment(old: [], new:), ..rest] ->
      patience_loop(rest, [list.map(new, Insert), ..acc])
    [Segment(old:, new: []), ..rest] ->
      patience_loop(rest, [list.map(old, Delete), ..acc])
    [Segment(old:, new:), ..rest] ->
      case longest_increasing_subseq(find_unique_pairs(old, new)) {
        [] -> patience_loop(rest, [myers(old, new), ..acc])
        anchors ->
          split_at_anchors(old, new, anchors, 0, 0, [])
          |> list.fold(rest, fn(tasks, task) { [task, ..tasks] })
          |> patience_loop(acc)
      }
  }
}

// Splits `old` and `new` around the anchors, whose positions are
// absolute within the segment. Returns the tasks in reverse order.
fn split_at_anchors(
  old: List(String),
  new: List(String),
  anchors: List(#(Int, Int)),
  old_position: Int,
  new_position: Int,
  reversed_tasks: List(PatienceTask),
) -> List(PatienceTask) {
  case anchors {
    [] -> [Segment(old:, new:), ..reversed_tasks]
    [#(old_index, new_index), ..rest] -> {
      let #(old_before, old_after) = list.split(old, old_index - old_position)
      let #(new_before, new_after) = list.split(new, new_index - new_position)
      let reversed_tasks = [
        Segment(old: old_before, new: new_before),
        ..reversed_tasks
      ]
      case old_after, new_after {
        [line, ..old_rest], [_, ..new_rest] ->
          split_at_anchors(
            old_rest,
            new_rest,
            rest,
            old_index + 1,
            new_index + 1,
            [Anchor(line:), ..reversed_tasks],
          )
        _, _ -> reversed_tasks
      }
    }
  }
}

// Pairs `#(old_index, new_index)` of the lines that occur exactly once
// in each input, in increasing old-index order.
fn find_unique_pairs(
  old: List(String),
  new: List(String),
) -> List(#(Int, Int)) {
  let counts =
    list.index_fold(old, dict.new(), fn(counts, line, index) {
      dict.upsert(counts, line, fn(existing) {
        case existing {
          Some(count) -> LineCount(..count, in_old: count.in_old + 1)
          None ->
            LineCount(in_old: 1, old_index: index, in_new: 0, new_index: 0)
        }
      })
    })
  let counts =
    list.index_fold(new, counts, fn(counts, line, index) {
      case dict.get(counts, line) {
        Ok(count) ->
          dict.insert(
            counts,
            line,
            LineCount(..count, in_new: count.in_new + 1, new_index: index),
          )
        Error(Nil) -> counts
      }
    })
  dict.fold(counts, [], fn(pairs, _line, count) {
    case count {
      LineCount(in_old: 1, old_index:, in_new: 1, new_index:) -> [
        #(old_index, new_index),
        ..pairs
      ]
      LineCount(..) -> pairs
    }
  })
  |> list.sort(fn(left, right) { int.compare(left.0, right.0) })
}

type LineCount {
  LineCount(in_old: Int, old_index: Int, in_new: Int, new_index: Int)
}

// Longest increasing subsequence (by new index) of `pairs`, which are in
// increasing old-index order, via patience sorting: `O(k log² k)` for
// `k` pairs. Among equally long subsequences it picks the same one as a
// quadratic scan that takes, for each pair, the earliest predecessor
// of maximal length, and ends at the earliest pair of maximal length.
fn longest_increasing_subseq(pairs: List(#(Int, Int))) -> List(#(Int, Int)) {
  let #(dealt, pile_count) = deal_into_piles(pairs, dict.new(), 0, [])
  // Each pile lists its pairs in increasing old-index order; within a
  // pile the new indices decrease.
  let piles =
    list.fold(dealt, dict.new(), fn(piles, entry) {
      let #(pile, pair) = entry
      dict.upsert(piles, pile, fn(existing) {
        case existing {
          Some(pairs) -> [pair, ..pairs]
          None -> [pair]
        }
      })
    })
  case dict.get(piles, pile_count - 1) {
    Ok([last, ..]) -> collect_lis(piles, pile_count - 2, last, [last])
    Ok([]) | Error(Nil) -> []
  }
}

// Places each pair on the leftmost pile whose top has a larger new
// index, and returns `#(pile, pair)` for every pair in reverse order.
fn deal_into_piles(
  pairs: List(#(Int, Int)),
  tops: Dict(Int, Int),
  pile_count: Int,
  dealt: List(#(Int, #(Int, Int))),
) -> #(List(#(Int, #(Int, Int))), Int) {
  case pairs {
    [] -> #(dealt, pile_count)
    [pair, ..rest] -> {
      let #(_, new_index) = pair
      let pile = first_pile_above(tops, new_index, 0, pile_count)
      let pile_count = int.max(pile_count, pile + 1)
      deal_into_piles(rest, dict.insert(tops, pile, new_index), pile_count, [
        #(pile, pair),
        ..dealt
      ])
    }
  }
}

// Binary search over the pile tops, which increase from left to right.
fn first_pile_above(
  tops: Dict(Int, Int),
  value: Int,
  low: Int,
  high: Int,
) -> Int {
  case low >= high {
    True -> low
    False -> {
      let middle = { low + high } / 2
      case dict.get(tops, middle) {
        Ok(top) if top < value -> first_pile_above(tops, value, middle + 1, high)
        Ok(_) | Error(Nil) -> first_pile_above(tops, value, low, middle)
      }
    }
  }
}

// Walks back from the chosen last pair, taking from each earlier pile
// the earliest pair whose new index is smaller.
fn collect_lis(
  piles: Dict(Int, List(#(Int, Int))),
  pile: Int,
  next: #(Int, Int),
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case pile < 0 {
    True -> acc
    False -> {
      let #(_, next_new_index) = next
      let candidates = result.unwrap(dict.get(piles, pile), [])
      case list.find(candidates, fn(pair) { pair.1 < next_new_index }) {
        Ok(pair) -> collect_lis(piles, pile - 1, pair, [pair, ..acc])
        Error(Nil) -> acc
      }
    }
  }
}

/// Render an edit script of individual lines as a unified diff.
///
/// Each element must be one line without its line terminator; a carriage return is kept as part of the line. To diff two texts, split each on `"\n"` and drop the empty element that a final newline leaves. Output uses LF-terminated lines and does not mark a file that lacked its final newline.
///
/// Reject filenames containing LF, CR, NUL, or tab, a negative context count, and an element containing LF. Validate the old name, new name, context count, then the elements in order, even for an unchanged script. Zero context is valid. An unchanged script returns `Ok("")`.
pub fn to_unified(
  script: List(Edit(String)),
  old_name old_name: String,
  new_name new_name: String,
  context_lines context: Int,
) -> Result(String, UnifiedError) {
  use _ <- result.try(validate_unified_name(OldName, old_name))
  use _ <- result.try(validate_unified_name(NewName, new_name))
  use _ <- result.try(case context < 0 {
    True -> Error(ContextLinesNegative(context))
    False -> Ok(Nil)
  })
  use _ <- result.try(validate_unified_lines(script))
  case has_changes(script) {
    False -> Ok("")
    True -> {
      let header = "--- " <> old_name <> "\n+++ " <> new_name <> "\n"
      let events = script_to_events(script, 1, 1, [])
      let hunks = build_hunks(events, context)
      let body = list.map(hunks, emit_hunk) |> string.concat
      Ok(header <> body)
    }
  }
}

// The unified-diff header — `--- <old_name>\n+++ <new_name>\n` — is
// line-oriented and tab-delimited from the optional trailing date,
// so embedded `\n` / `\r` break the header into multiple physical
// lines that downstream `patch(1)` / `git apply` reject. NUL bytes
// truncate the line for any POSIX C string consumer. Tabs are
// folded into the same set because `diff -u` uses them to separate
// the filename from the date stamp.
// `string.contains` matches code points rather than graphemes: "\r\n" is a single
// grapheme cluster and would slip through a grapheme-wise check.

fn validate_unified_name(
  field: NameField,
  name: String,
) -> Result(Nil, UnifiedError) {
  case
    string.contains(name, "\n")
    || string.contains(name, "\r")
    || string.contains(name, "\u{0000}")
    || string.contains(name, "\t")
  {
    True -> Error(NameContainsForbiddenBytes(field, name))
    False -> Ok(Nil)
  }
}

fn validate_unified_lines(
  script: List(Edit(String)),
) -> Result(Nil, UnifiedError) {
  case script {
    [] -> Ok(Nil)
    [edit, ..rest] ->
      case string.contains(edit.item, "\n") {
        True -> Error(LineContainsNewline(edit.item))
        False -> validate_unified_lines(rest)
      }
  }
}

fn has_changes(script: List(Edit(String))) -> Bool {
  case script {
    [] -> False
    [Equal(_), ..rest] -> has_changes(rest)
    [Insert(_), ..] | [Delete(_), ..] -> True
  }
}

type LineEvent {
  ContextEvent(line: String, old_pos: Int, new_pos: Int)
  DeleteEvent(line: String, old_pos: Int, new_pos: Int)
  InsertEvent(line: String, old_pos: Int, new_pos: Int)
}

fn script_to_events(
  script: List(Edit(String)),
  old_pos: Int,
  new_pos: Int,
  acc: List(LineEvent),
) -> List(LineEvent) {
  case script {
    [] -> list.reverse(acc)
    [Equal(line), ..rest] ->
      script_to_events(rest, old_pos + 1, new_pos + 1, [
        ContextEvent(line, old_pos, new_pos),
        ..acc
      ])
    [Delete(line), ..rest] ->
      script_to_events(rest, old_pos + 1, new_pos, [
        DeleteEvent(line, old_pos, new_pos),
        ..acc
      ])
    [Insert(line), ..rest] ->
      script_to_events(rest, old_pos, new_pos + 1, [
        InsertEvent(line, old_pos, new_pos),
        ..acc
      ])
  }
}

fn build_hunks(
  events: List(LineEvent),
  context_lines: Int,
) -> List(List(LineEvent)) {
  let last_index = list.length(events) - 1
  let change_indices =
    list.index_fold(events, [], fn(indices, event, index) {
      case event {
        InsertEvent(..) | DeleteEvent(..) -> [index, ..indices]
        ContextEvent(..) -> indices
      }
    })
    |> list.reverse
  let ranges =
    list.map(change_indices, fn(index) {
      #(
        int.max(0, index - context_lines),
        int.min(last_index, index + context_lines),
      )
    })
  slice_ranges(events, 0, merge_ranges(ranges), [], [])
}

fn merge_ranges(ranges: List(#(Int, Int))) -> List(#(Int, Int)) {
  case ranges {
    [] -> []
    [first, ..rest] -> merge_ranges_loop(rest, first, [])
  }
}

fn merge_ranges_loop(
  remaining: List(#(Int, Int)),
  current: #(Int, Int),
  acc: List(#(Int, Int)),
) -> List(#(Int, Int)) {
  case remaining {
    [] -> list.reverse([current, ..acc])
    [#(lo, hi), ..rest] -> {
      let #(current_low, current_high) = current
      case lo <= current_high + 1 {
        True ->
          merge_ranges_loop(
            rest,
            #(current_low, int.max(current_high, hi)),
            acc,
          )
        False -> merge_ranges_loop(rest, #(lo, hi), [current, ..acc])
      }
    }
  }
}

// Cuts the events at the given ranges, which are sorted and disjoint.
fn slice_ranges(
  events: List(LineEvent),
  index: Int,
  ranges: List(#(Int, Int)),
  current: List(LineEvent),
  hunks: List(List(LineEvent)),
) -> List(List(LineEvent)) {
  case ranges, events {
    [#(low, high), ..later_ranges], [event, ..later_events] ->
      case index < low, index == high {
        True, _ -> slice_ranges(later_events, index + 1, ranges, current, hunks)
        False, True ->
          slice_ranges(later_events, index + 1, later_ranges, [], [
            list.reverse([event, ..current]),
            ..hunks
          ])
        False, False ->
          slice_ranges(
            later_events,
            index + 1,
            ranges,
            [event, ..current],
            hunks,
          )
      }
    [], _ | [_, ..], [] -> list.reverse(hunks)
  }
}

fn emit_hunk(events: List(LineEvent)) -> String {
  let #(first_old, first_new) = case events {
    [first, ..] -> #(first.old_pos, first.new_pos)
    [] -> #(1, 1)
  }
  let old_lines =
    list.filter_map(events, fn(event) {
      case event {
        ContextEvent(old_pos:, ..) | DeleteEvent(old_pos:, ..) -> Ok(old_pos)
        InsertEvent(..) -> Error(Nil)
      }
    })
  let new_lines =
    list.filter_map(events, fn(event) {
      case event {
        ContextEvent(new_pos:, ..) | InsertEvent(new_pos:, ..) -> Ok(new_pos)
        DeleteEvent(..) -> Error(Nil)
      }
    })
  let header =
    "@@ -"
    <> format_range(hunk_side(old_lines, first_old))
    <> " +"
    <> format_range(hunk_side(new_lines, first_new))
    <> " @@\n"
  let body = list.map(events, event_to_line) |> string.concat
  header <> body
}

// Start and line count of one side of a hunk. A side with no lines
// starts at the line before the hunk, as in `diff -u` (`-0,0`).
fn hunk_side(positions: List(Int), first_position: Int) -> #(Int, Int) {
  case positions {
    [start, ..] -> #(start, list.length(positions))
    [] -> #(int.max(0, first_position - 1), 0)
  }
}

fn format_range(side: #(Int, Int)) -> String {
  let #(start, count) = side
  case count {
    1 -> int.to_string(start)
    _ -> int.to_string(start) <> "," <> int.to_string(count)
  }
}

fn event_to_line(event: LineEvent) -> String {
  case event {
    ContextEvent(line, _, _) -> " " <> line <> "\n"
    DeleteEvent(line, _, _) -> "-" <> line <> "\n"
    InsertEvent(line, _, _) -> "+" <> line <> "\n"
  }
}

/// Pair an original candidate string with its similarity score.
pub type Ranked {
  Ranked(label: String, score: Float)
}

/// Select candidates within a whole-string Levenshtein distance and sort them by distance.
///
/// Compare NFC-normalized graphemes, returning the original candidate strings. Keep input order for equal distances and retain duplicate candidates. Empty candidates or a negative distance limit return an empty list. Use `list.first` on the result when only one suggestion is needed.
pub fn did_you_mean(
  query: String,
  candidates: List(String),
  max_distance: Int,
) -> List(String) {
  case max_distance < 0 {
    True -> []
    False -> {
      // The query is normalised and split once, not once per candidate.
      let query_graphemes = nfc_graphemes(query)
      candidates
      |> list.index_map(fn(candidate, index) {
        let distance =
          levenshtein_list(query_graphemes, nfc_graphemes(candidate))
        #(candidate, distance, index)
      })
      |> list.filter(fn(scored) { scored.1 <= max_distance })
      |> list.sort(by: fn(left, right) {
        int.compare(left.1, right.1)
        |> order.break_tie(int.compare(left.2, right.2))
      })
      |> list.map(fn(scored) { scored.0 })
    }
  }
}

/// Return up to the requested number of candidates in descending Jaro-Winkler score order.
///
/// Use prefix scale `0.1` and cap `4`. Compare NFC-normalized graphemes, retain original candidate strings, and preserve input order on ties. Empty candidates or a nonpositive result limit return an empty list.
pub fn rank_jaro_winkler(
  query: String,
  candidates: List(String),
  top_n: Int,
) -> List(Ranked) {
  case top_n <= 0 {
    True -> []
    False -> {
      let query_graphemes = nfc_graphemes(query)
      let prefix_scale = 0.1
      let prefix_max = 4
      candidates
      |> list.index_map(fn(candidate, index) {
        let score =
          jaro_winkler_graphemes(
            query_graphemes,
            nfc_graphemes(candidate),
            prefix_scale,
            prefix_max,
          )
        #(candidate, score, index)
      })
      |> list.sort(by: fn(left, right) {
        float.compare(right.1, left.1)
        |> order.break_tie(int.compare(left.2, right.2))
      })
      |> list.take(top_n)
      |> list.map(fn(scored) { Ranked(label: scored.0, score: scored.1) })
    }
  }
}

/// Report input that has too few words or sentences for a formula.
///
/// `at_least` is the required count and `got` is the observed count.
pub type ReadabilityError {
  /// The input had fewer than `at_least` words. `got` is the actual
  /// count.
  TooFewWords(at_least: Int, got: Int)
  /// The input had fewer than `at_least` sentences. `got` is the
  /// actual count.
  TooFewSentences(at_least: Int, got: Int)
}

type Counts {
  Counts(
    words: Int,
    sentences: Int,
    syllables: Int,
    characters: Int,
    polysyllables: Int,
  )
}

fn build_counts(text: String) -> Counts {
  let graphemes = nfc_graphemes(text)
  let words = word_chunks(graphemes)
  let #(syllables, polysyllables) =
    list.fold(words, #(0, 0), fn(totals, word) {
      let syllables = word_syllables(word)
      let polysyllabic = case syllables >= 3 {
        True -> 1
        False -> 0
      }
      #(totals.0 + syllables, totals.1 + polysyllabic)
    })
  Counts(
    words: list.length(words),
    sentences: sentences_from_graphemes(graphemes),
    syllables:,
    characters: characters_from_graphemes(graphemes),
    polysyllables:,
  )
}

// The counts of `text`, or `TooFewWords` when it has no words. Text
// with a word always has a sentence, so the sentence check never fails
// here; it guards the divisions below.
fn counts_with_a_word(text: String) -> Result(Counts, ReadabilityError) {
  let counts = build_counts(text)
  use _ <- result.try(require_words(counts, 1))
  use _ <- result.try(require_sentences(counts, 1))
  Ok(counts)
}

fn require_words(
  counts: Counts,
  at_least: Int,
) -> Result(Nil, ReadabilityError) {
  case counts.words >= at_least {
    True -> Ok(Nil)
    False -> Error(TooFewWords(at_least: at_least, got: counts.words))
  }
}

fn require_sentences(
  counts: Counts,
  at_least: Int,
) -> Result(Nil, ReadabilityError) {
  case counts.sentences >= at_least {
    True -> Ok(Nil)
    False -> Error(TooFewSentences(at_least: at_least, got: counts.sentences))
  }
}

// --- Flesch Reading Ease -------------------------------------------------

/// Calculate the raw Flesch Reading Ease score.
///
/// Use `206.835 - 1.015 * words / sentences - 84.6 * syllables / words`. Higher values indicate easier English text. The result can be below zero or above 100; no clamping is applied. Input without words returns `TooFewWords`.
pub fn flesch_reading_ease(text: String) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let words_per_sentence =
    int.to_float(counts.words) /. int.to_float(counts.sentences)
  let syllables_per_word =
    int.to_float(counts.syllables) /. int.to_float(counts.words)
  Ok(206.835 -. 1.015 *. words_per_sentence -. 84.6 *. syllables_per_word)
}

// --- Flesch–Kincaid Grade Level ------------------------------------------

/// Calculate the raw Flesch-Kincaid grade estimate for English text.
///
/// Use `0.39 * words / sentences + 11.8 * syllables / words - 15.59`. Return the formula value without clamping. Input without words returns `TooFewWords`.
pub fn flesch_kincaid_grade(text: String) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let words_per_sentence =
    int.to_float(counts.words) /. int.to_float(counts.sentences)
  let syllables_per_word =
    int.to_float(counts.syllables) /. int.to_float(counts.words)
  Ok(0.39 *. words_per_sentence +. 11.8 *. syllables_per_word -. 15.59)
}

// --- Gunning Fog ---------------------------------------------------------

/// Calculate the raw Gunning Fog index for English text.
///
/// Use `0.4 * (words / sentences + 100 * polysyllables / words)`. A polysyllable has at least three estimated syllables. Do not apply the original formula's exclusions for proper nouns, compounds, or inflected words. Return the formula value without clamping. Input without words returns `TooFewWords`.
pub fn gunning_fog(text: String) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let words_per_sentence =
    int.to_float(counts.words) /. int.to_float(counts.sentences)
  let poly_ratio =
    100.0 *. int.to_float(counts.polysyllables) /. int.to_float(counts.words)
  Ok(0.4 *. { words_per_sentence +. poly_ratio })
}

// --- SMOG ----------------------------------------------------------------

/// Calculate the SMOG grade estimate for English text with at least 30 sentences.
///
/// Use `1.043 * sqrt(30 * polysyllables / sentences) + 3.1291`. First reject input without words with `TooFewWords`, then reject fewer than 30 sentences with `TooFewSentences`.
pub fn smog(text: String) -> Result(Float, ReadabilityError) {
  let counts = build_counts(text)
  use _ <- result.try(require_words(counts, 1))
  use _ <- result.try(require_sentences(counts, 30))
  Ok(smog_from_counts(counts))
}

/// Apply the SMOG formula to an English sample without the 30-sentence minimum.
///
/// Require at least one word and one sentence, returning `TooFewWords` or `TooFewSentences` when the corresponding requirement fails. Short samples extrapolate the formula beyond the sample size required by `smog`.
pub fn smog_extrapolated(text: String) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  Ok(smog_from_counts(counts))
}

fn smog_from_counts(counts: Counts) -> Float {
  let polysyllables = int.to_float(counts.polysyllables)
  let scale = 30.0 /. int.to_float(counts.sentences)
  // `polysyllables × scale` is always >= 0 (polysyllables ≥ 0, sentences > 0
  // by the precondition), so `float.square_root` cannot return Error
  // here. Default the unreachable branch to 0.0 so the surrounding
  // Result chain stays in the ReadabilityError domain.
  let root = case float.square_root(polysyllables *. scale) {
    Ok(r) -> r
    Error(_) -> 0.0
  }
  1.043 *. root +. 3.1291
}

// --- Automated Readability Index -----------------------------------------

/// Calculate the raw Automated Readability Index for English text.
///
/// Use `4.71 * characters / words + 0.5 * words / sentences - 21.43`. Characters follow `count_characters`'s letter-like grapheme definition. Return the formula value without clamping. Input without words returns `TooFewWords`.
pub fn automated_readability_index(
  text: String,
) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let characters_per_word =
    int.to_float(counts.characters) /. int.to_float(counts.words)
  let words_per_sentence =
    int.to_float(counts.words) /. int.to_float(counts.sentences)
  Ok(4.71 *. characters_per_word +. 0.5 *. words_per_sentence -. 21.43)
}

// --- Coleman–Liau --------------------------------------------------------

/// Calculate the raw Coleman-Liau index for English text.
///
/// Use `0.0588 * L - 0.296 * S - 15.8`, where `L` and `S` are letter-like graphemes and sentences per 100 words. Return the formula value without clamping. Input without words returns `TooFewWords`.
pub fn coleman_liau_index(text: String) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let letters_per_100 =
    int.to_float(counts.characters) /. int.to_float(counts.words) *. 100.0
  let sentences_per_100 =
    int.to_float(counts.sentences) /. int.to_float(counts.words) *. 100.0
  Ok(0.0588 *. letters_per_100 -. 0.296 *. sentences_per_100 -. 15.8)
}

/// Jaro-Winkler with the prefix boost applied only when the Jaro score
/// is above 0.7. The caller validates `prefix_scale` and `prefix_max`.
fn jaro_winkler_graphemes(
  left_graphemes: List(String),
  right_graphemes: List(String),
  prefix_scale: Float,
  prefix_max: Int,
) -> Float {
  let jaro_score = jaro_graphemes(left_graphemes, right_graphemes)
  case jaro_score >. boost_threshold {
    False -> jaro_score
    True -> {
      let prefix =
        common_prefix_length(
          left_graphemes,
          right_graphemes,
          0,
          prefix_scale,
          prefix_max,
        )
        |> int.to_float
      jaro_score +. prefix *. prefix_scale *. { 1.0 -. jaro_score }
    }
  }
}

const boost_threshold = 0.7

/// Jaro similarity; `1.0` for two empty lists and `0.0` when exactly
/// one is empty.
fn jaro_graphemes(
  left_graphemes: List(String),
  right_graphemes: List(String),
) -> Float {
  let left_length = list.length(left_graphemes)
  let right_length = list.length(right_graphemes)
  case left_length, right_length {
    0, 0 -> 1.0
    0, _ -> 0.0
    _, 0 -> 0.0
    _, _ -> {
      let window = int.max(0, int.max(left_length, right_length) / 2 - 1)
      let indexed_right =
        list.index_map(right_graphemes, fn(item, index) { #(index, item) })
      let #(left_matches, matched_right_indices) =
        find_matches(
          left_graphemes,
          0,
          indexed_right,
          window,
          right_length,
          [],
          set.new(),
        )
      case left_matches {
        [] -> 0.0
        _ -> {
          // Matched graphemes of `b` in `b` order, paired with those of
          // `a` in `a` order.
          let right_matches =
            list.filter_map(indexed_right, fn(entry) {
              case set.contains(matched_right_indices, entry.0) {
                True -> Ok(entry.1)
                False -> Error(Nil)
              }
            })
          let half_transpositions =
            list.map2(left_matches, right_matches, fn(x, y) { x != y })
            |> list.count(fn(differs) { differs })
          let matches = int.to_float(list.length(left_matches))
          // Half the mismatches, rounded down, as in Winkler's strcmp95.
          let transpositions = int.to_float(half_transpositions / 2)
          {
            matches
            /. int.to_float(left_length)
            +. matches
            /. int.to_float(right_length)
            +. { matches -. transpositions }
            /. matches
          }
          /. 3.0
        }
      }
    }
  }
}

// Matches every grapheme of `a` at index `i` with the first unmatched
// equal grapheme of `b` within `window` of `i`. `window_start` is
// `indexed_b` from index `i - window` on. Returns the matched graphemes
// of `a` in order and the matched indices of `b`.
fn find_matches(
  left_graphemes: List(String),
  i: Int,
  window_start: List(#(Int, String)),
  window: Int,
  right_length: Int,
  left_matches: List(String),
  matched_right_indices: Set(Int),
) -> #(List(String), Set(Int)) {
  case left_graphemes {
    [] -> #(list.reverse(left_matches), matched_right_indices)
    [item, ..rest] -> {
      let #(left_matches, matched_right_indices) = case
        find_match_in_window(
          item,
          window_start,
          int.min(right_length - 1, i + window),
          matched_right_indices,
        )
      {
        Ok(j) -> #([item, ..left_matches], set.insert(matched_right_indices, j))
        Error(Nil) -> #(left_matches, matched_right_indices)
      }
      let window_start = case i >= window, window_start {
        True, [_, ..later] -> later
        _, _ -> window_start
      }
      find_matches(
        rest,
        i + 1,
        window_start,
        window,
        right_length,
        left_matches,
        matched_right_indices,
      )
    }
  }
}

fn find_match_in_window(
  item: String,
  candidates: List(#(Int, String)),
  last_index: Int,
  matched_right_indices: Set(Int),
) -> Result(Int, Nil) {
  case candidates {
    [#(j, candidate), ..rest] if j <= last_index ->
      case candidate == item && !set.contains(matched_right_indices, j) {
        True -> Ok(j)
        False ->
          find_match_in_window(item, rest, last_index, matched_right_indices)
      }
    _ -> Error(Nil)
  }
}

// Stops at `prefix_max`, and also before `prefix_scale * count` would
// exceed 1, which keeps the boosted score at or below 1.0.
fn common_prefix_length(
  left_graphemes: List(String),
  right_graphemes: List(String),
  count: Int,
  prefix_scale: Float,
  prefix_max: Int,
) -> Int {
  let at_limit =
    count >= prefix_max || int.to_float(count + 1) *. prefix_scale >. 1.0
  case at_limit, left_graphemes, right_graphemes {
    True, _, _ -> count
    False, [x, ..xs], [y, ..ys] if x == y ->
      common_prefix_length(xs, ys, count + 1, prefix_scale, prefix_max)
    False, _, _ -> count
  }
}
