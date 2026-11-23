//// Quotation marks and brackets right after a terminator close the
//// sentence (UAX #29 SB9) instead of starting a new one. Before,
//// `He said "Hi."` counted as two sentences.

import gleeunit/should
import textmetrics

pub fn closing_quote_after_terminator_belongs_to_the_sentence_test() {
  textmetrics.count_sentences("He said \"Hi.\"") |> should.equal(1)
  textmetrics.count_sentences("End.'") |> should.equal(1)
  textmetrics.count_sentences("Yes.\u{00BB}") |> should.equal(1)
}

pub fn closing_bracket_after_terminator_belongs_to_the_sentence_test() {
  textmetrics.count_sentences("(See above.)") |> should.equal(1)
  textmetrics.count_sentences("I like it.)") |> should.equal(1)
  textmetrics.count_sentences("\u{300C}終わり。\u{300D}") |> should.equal(1)
}

pub fn several_closers_and_following_sentences_test() {
  textmetrics.count_sentences("He said \u{201C}Stop.\u{201D} She left.")
  |> should.equal(2)
  textmetrics.count_sentences("(\"Quoted.\") Next one.") |> should.equal(2)
  textmetrics.count_sentences("Hi!) ok") |> should.equal(2)
}

pub fn quotes_without_a_terminator_are_content_test() {
  textmetrics.count_sentences("\"") |> should.equal(1)
  textmetrics.count_sentences("Hi. \"") |> should.equal(2)
}

pub fn multi_period_abbreviation_before_a_closer_test() {
  textmetrics.count_sentences("He said \"I live in the U.S.A.\" She agreed.")
  |> should.equal(2)
  textmetrics.count_sentences("(e.g.) Next one.") |> should.equal(2)
  textmetrics.count_sentences("It was 5 p.m.) then more.") |> should.equal(1)
}
