//// Issue #23: SMOG-G applies the SMOG formula to texts shorter than
//// 30 sentences, where strict SMOG would reject.

import gleam/string
import gleeunit/should
import textmetrics

pub fn smog_g_short_text_test() -> Nil {
  let short = "Gleam is functional. It compiles to Erlang. Syntax is clean."
  let assert Ok(score) = textmetrics.smog_extrapolated(short)
  { score >=. 0.0 } |> should.be_true
}

pub fn smog_g_long_text_matches_smog_test() -> Nil {
  let long = string.repeat("Dog ran fast today. ", 30)
  let assert Ok(g) = textmetrics.smog_extrapolated(long)
  let assert Ok(s) = textmetrics.smog(long)
  // 30+ 文では SMOG-G と SMOG はほぼ一致
  let diff = case g >. s {
    True -> g -. s
    False -> s -. g
  }
  { diff <. 1.0 } |> should.be_true
}

pub fn smog_short_text_still_errors_test() -> Nil {
  let short = "Dog ran. Cat sat."
  case textmetrics.smog(short) {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}

pub fn smog_g_rejects_empty_test() -> Nil {
  case textmetrics.smog_extrapolated("") {
    Error(_) -> Nil
    Ok(_) -> should.fail()
  }
}
