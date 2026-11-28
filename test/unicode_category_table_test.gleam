//// Checks every range of the generated table in
//// `textmetrics/internal/unicode_category` against ranges read straight
//// from the Unicode 17.0.0 data (`unicode_category_ranges`, written by
//// `scripts/gen_unicode_category_fixture.py`). For each range the first,
//// middle and last code points must be in it, and the code points just
//// outside it and in the middle of the gap before the next range must not.

import gleam/bool
import gleam/int
import gleam/list
import gleeunit/should
import textmetrics/internal/unicode_category
import unicode_category_ranges

const max_code_point = 0x10ffff

pub fn is_non_letter_matches_unicode_data_test() {
  mismatches(
    unicode_category.is_non_letter,
    unicode_category_ranges.non_letter(),
  )
  |> should.equal([])
}

pub fn is_word_format_matches_unicode_data_test() {
  mismatches(
    unicode_category.is_word_format,
    unicode_category_ranges.word_format(),
  )
  |> should.equal([])
}

pub fn is_word_numeric_matches_unicode_data_test() {
  mismatches(
    unicode_category.is_word_numeric,
    unicode_category_ranges.word_numeric(),
  )
  |> should.equal([])
}

pub fn joins_letters_matches_unicode_data_test() {
  mismatches(
    unicode_category.joins_letters,
    unicode_category_ranges.letter_joiners(),
  )
  |> should.equal([])
}

pub fn joins_numbers_matches_unicode_data_test() {
  mismatches(
    unicode_category.joins_numbers,
    unicode_category_ranges.number_joiners(),
  )
  |> should.equal([])
}

pub fn is_sentence_close_matches_unicode_data_test() {
  mismatches(
    unicode_category.is_sentence_close,
    unicode_category_ranges.sentence_close(),
  )
  |> should.equal([])
}

/// The code points where `predicate` disagrees with `ranges`, as
/// `"0x<code> should be True"` or `"... False"`.
fn mismatches(
  predicate: fn(Int) -> Bool,
  ranges: List(#(Int, Int)),
) -> List(String) {
  samples(ranges, -1, [])
  |> list.filter_map(fn(sample) {
    let #(code, expected) = sample
    case predicate(code) == expected {
      True -> Error(Nil)
      False ->
        Ok(
          "0x"
          <> int.to_base16(code)
          <> " should be "
          <> bool.to_string(expected),
        )
    }
  })
}

/// Pairs of code point and expected result around each range. `previous`
/// is the last code point of the range before, or -1 for the first.
fn samples(
  ranges: List(#(Int, Int)),
  previous: Int,
  acc: List(#(Int, Bool)),
) -> List(#(Int, Bool)) {
  case ranges {
    [] -> list.reverse(gap(previous, max_code_point + 1, acc))
    [#(low, high), ..rest] -> {
      let acc =
        gap(previous, low, acc)
        |> list.prepend(#(low, True))
        |> list.prepend(#({ low + high } / 2, True))
        |> list.prepend(#(high, True))
      samples(rest, high, acc)
    }
  }
}

/// Expected-False samples for the code points strictly between `previous`
/// and `next`: both ends of the gap and its middle.
fn gap(
  previous: Int,
  next: Int,
  acc: List(#(Int, Bool)),
) -> List(#(Int, Bool)) {
  case next - previous > 1 {
    False -> acc
    True ->
      acc
      |> list.prepend(#(previous + 1, False))
      |> list.prepend(#({ previous + next } / 2, False))
      |> list.prepend(#(next - 1, False))
  }
}
