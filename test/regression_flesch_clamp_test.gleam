//// Issue #21: Flesch Reading Ease is reported on the `[0, 100]`
//// scale by Wikipedia / Word / textstat default. The raw formula can
//// fall outside that range for synthetic inputs; `flesch_reading_ease`
//// now clamps, with `flesch_reading_ease_unbounded` exposing the raw
//// formula output for callers who need it.

import gleam/string
import gleeunit/should
import textmetrics/readability

pub fn flesch_reading_ease_clamped_upper_test() -> Nil {
  let easy = string.repeat("Dog ran fast. Cat sat. Bird flew. ", 30)
  let assert Ok(score) = readability.flesch_reading_ease(easy)
  { score <=. 100.0 } |> should.be_true
}

pub fn flesch_reading_ease_clamped_lower_test() -> Nil {
  let hard =
    string.repeat(
      "Antidisestablishmentarianism necessitates extensive philosophical considerations concerning sociopolitical superstructures. ",
      30,
    )
  let assert Ok(score) = readability.flesch_reading_ease(hard)
  { score >=. 0.0 } |> should.be_true
}

pub fn flesch_reading_ease_unbounded_exceeds_100_test() -> Nil {
  let easy = string.repeat("Dog ran. ", 30)
  let assert Ok(raw) = readability.flesch_reading_ease_unbounded(easy)
  { raw >. 100.0 } |> should.be_true
}

pub fn flesch_reading_ease_unbounded_below_0_test() -> Nil {
  let hard =
    string.repeat(
      "Antidisestablishmentarianism necessitates extensive philosophical considerations concerning sociopolitical superstructures. ",
      30,
    )
  let assert Ok(raw) = readability.flesch_reading_ease_unbounded(hard)
  { raw <. 0.0 } |> should.be_true
}

pub fn flesch_reading_ease_normal_text_unchanged_test() -> Nil {
  let normal =
    "Gleam is a functional programming language for building type-safe, scalable systems."
  let assert Ok(score) = readability.flesch_reading_ease(normal)
  { score >=. 0.0 && score <=. 100.0 } |> should.be_true
}
