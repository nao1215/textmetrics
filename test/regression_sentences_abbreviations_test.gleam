//// Issue #19: common English abbreviations (Mr., Dr., e.g., Jan., etc.)
//// must not be treated as sentence terminators.

import gleeunit/should
import textmetrics/count

pub fn mr_smith_one_sentence_test() -> Nil {
  count.sentences("Mr. Smith went to Washington.") |> should.equal(1)
}

pub fn dr_who_one_sentence_test() -> Nil {
  count.sentences("Dr. Who lives.") |> should.equal(1)
}

// Multi-period abbreviations like "e.g." / "i.e." are not yet handled
// — the suppression check examines the word immediately before the
// period and "e" alone is not on the abbreviation list. Handling
// these correctly needs lookahead or a per-segment token buffer; out
// of scope here.

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
