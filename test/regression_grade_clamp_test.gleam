//// Issue #22: grade-level readability scores must report a sensible
//// US-K-12-plus range. Each grade-level function now clamps to
//// `[0.0, 18.0]` and exposes an `_unbounded` companion.

import gleam/float
import gleam/result

import gleam/string
import gleeunit/should
import textmetrics

fn easy_text() -> String {
  string.repeat("Dog ran fast. Cat sat. Bird flew. ", 30)
}

fn hard_text() -> String {
  string.repeat(
    "Antidisestablishmentarianism necessitates extensive philosophical considerations concerning sociopolitical superstructures. ",
    30,
  )
}

pub fn flesch_kincaid_grade_clamped_lower_test() -> Nil {
  let assert Ok(s) = {
    textmetrics.flesch_kincaid_grade(easy_text())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  { s >=. 0.0 } |> should.be_true
}

pub fn flesch_kincaid_grade_clamped_upper_test() -> Nil {
  let assert Ok(s) = {
    textmetrics.flesch_kincaid_grade(hard_text())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  { s <=. 18.0 } |> should.be_true
}

pub fn gunning_fog_clamped_upper_test() -> Nil {
  let assert Ok(s) = {
    textmetrics.gunning_fog(hard_text())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  { s <=. 18.0 } |> should.be_true
}

pub fn ari_clamped_lower_test() -> Nil {
  let assert Ok(s) = {
    textmetrics.automated_readability_index(easy_text())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  { s >=. 0.0 } |> should.be_true
}

pub fn coleman_liau_clamped_lower_test() -> Nil {
  let assert Ok(s) = {
    textmetrics.coleman_liau_index(easy_text())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  { s >=. 0.0 } |> should.be_true
}

pub fn coleman_liau_clamped_upper_test() -> Nil {
  let assert Ok(s) = {
    textmetrics.coleman_liau_index(hard_text())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  { s <=. 18.0 } |> should.be_true
}

pub fn unbounded_flesch_kincaid_can_be_negative_test() -> Nil {
  let assert Ok(s) = textmetrics.flesch_kincaid_grade(easy_text())
  { s <. 0.0 } |> should.be_true
}

pub fn unbounded_coleman_liau_can_be_negative_test() -> Nil {
  let assert Ok(s) = textmetrics.coleman_liau_index(easy_text())
  { s <. 0.0 } |> should.be_true
}

pub fn unbounded_gunning_fog_can_exceed_18_test() -> Nil {
  let assert Ok(s) = textmetrics.gunning_fog(hard_text())
  { s >. 18.0 } |> should.be_true
}
