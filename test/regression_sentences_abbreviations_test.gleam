//// Common English abbreviations (Mr., Dr., e.g., p.m., U.S., Jan., etc.)
//// must not be treated as sentence terminators.

import gleam/list
import gleeunit/should
import textmetrics/count

pub fn mr_smith_one_sentence_test() -> Nil {
  count.sentences("Mr. Smith went to Washington.") |> should.equal(1)
}

pub fn dr_who_one_sentence_test() -> Nil {
  count.sentences("Dr. Who lives.") |> should.equal(1)
}

pub fn multi_period_abbreviations_test() -> Nil {
  [
    #("He left at 5 p.m. yesterday.", 1),
    #("He left at 9 a.m. yesterday.", 1),
    #("Many fruits, e.g. apples, are sweet.", 1),
    #("Many fruits, i.e. apples, are sweet.", 1),
    #("E.g. apples are sweet.", 1),
    #("He left for U.S. yesterday.", 1),
    #("He lives on Park Ave. now.", 1),
    #("She has a Ph.D. in physics.", 1),
    #("The U.S.A. is large.", 1),
    #("Open at 9 a.m. and close at 5 p.m.", 1),
    #("Mr. Smith met Dr. Jones at 5 p.m. Then he left.", 2),
    #("We moved to the U.K. It rained.", 2),
  ]
  |> list.each(fn(pair) {
    let #(text, expected) = pair
    #(text, count.sentences(text)) |> should.equal(#(text, expected))
  })
}

pub fn period_inside_a_token_does_not_terminate_test() -> Nil {
  // A period followed directly by another character is part of the
  // token (a decimal, a version, a domain), not the end of a sentence.
  [
    #("It costs 3.50 dollars.", 1),
    #("Version 1.2.3 is out. Update now.", 2),
    #("Visit example.com today.", 1),
    #("Pi is about 3.14159.", 1),
  ]
  |> list.each(fn(pair) {
    let #(text, expected) = pair
    #(text, count.sentences(text)) |> should.equal(#(text, expected))
  })
}

pub fn single_period_abbreviations_unchanged_test() -> Nil {
  [
    #("Mr. Smith left.", 1),
    #("Dr. Jones left.", 1),
    #("Mrs. Smith left.", 1),
    #("Apples, oranges, etc. are fruit.", 1),
    #("Apple Inc. is large.", 1),
    #("On Jan. 5 he left.", 1),
    #("Cats vs. dogs is a classic.", 1),
  ]
  |> list.each(fn(pair) {
    let #(text, expected) = pair
    #(text, count.sentences(text)) |> should.equal(#(text, expected))
  })
}

pub fn january_first_one_sentence_test() -> Nil {
  count.sentences("On Jan. 1st we ship.") |> should.equal(1)
}

pub fn two_sentences_with_abbreviations_test() -> Nil {
  count.sentences("Mr. Smith left. Dr. Jones arrived.")
  |> should.equal(2)
}

pub fn case_insensitive_mr_test() -> Nil {
  count.sentences("MR. SMITH WENT HOME.") |> should.equal(1)
}

pub fn normal_period_still_terminates_test() -> Nil {
  count.sentences("Hello world. Goodbye.") |> should.equal(2)
}

pub fn questions_and_bangs_still_terminate_test() -> Nil {
  count.sentences("What?! Now go.") |> should.equal(2)
}

pub fn empty_input_test() -> Nil {
  count.sentences("") |> should.equal(0)
}
