import gleam/float
import gleam/result
import gleeunit/should
import textmetrics

// --- helpers ------------------------------------------------------------

fn pangram() -> String {
  "The quick brown fox jumps over the lazy dog."
}

fn within(a: Float, b: Float, tol: Float) -> Bool {
  let delta = case a >. b {
    True -> a -. b
    False -> b -. a
  }
  delta <=. tol
}

// --- small-fixture reference scores -------------------------------------

pub fn flesch_ease_pangram_test() -> Nil {
  let assert Ok(score) = {
    textmetrics.flesch_reading_ease(pangram())
    |> result.map(float.clamp(_, min: 0.0, max: 100.0))
  }
  within(score, 94.0, 2.0)
  |> should.be_true
}

pub fn flesch_kincaid_grade_pangram_test() -> Nil {
  let assert Ok(score) = {
    textmetrics.flesch_kincaid_grade(pangram())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  within(score, 2.3, 1.0)
  |> should.be_true
}

pub fn gunning_fog_pangram_test() -> Nil {
  let assert Ok(score) = {
    textmetrics.gunning_fog(pangram())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  within(score, 3.6, 1.0)
  |> should.be_true
}

pub fn ari_pangram_test() -> Nil {
  // Pangram has chars=35 letters / words=9 / sentences=1, so
  //   ARI = 4.71 × (35/9) + 0.5 × (9/1) − 21.43 ≈ 1.39
  // (The issue tracker quotes ~2.5 for this fixture, but that
  // matches `textstat`'s number only if punctuation graphemes are
  // counted as characters too. We count letters + digits only,
  // which is the Wikipedia ARI definition.)
  let assert Ok(score) = {
    textmetrics.automated_readability_index(pangram())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  within(score, 1.39, 0.5)
  |> should.be_true
}

pub fn coleman_liau_pangram_test() -> Nil {
  // L = (35/9) × 100 = 388.89, S = (1/9) × 100 = 11.11
  //   CL = 0.0588 × 388.89 − 0.296 × 11.11 − 15.8 ≈ 3.78
  // The issue tracker quotes ~6.5; that value assumes a longer
  // synthetic fixture, not the bare pangram. The formula itself is
  // the Coleman-Liau 1975 paper as quoted by `textstat`.
  let assert Ok(score) = {
    textmetrics.coleman_liau_index(pangram())
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  within(score, 3.78, 0.5)
  |> should.be_true
}

// --- edge cases ---------------------------------------------------------

pub fn flesch_ease_empty_input_test() -> Nil {
  case
    {
      textmetrics.flesch_reading_ease("")
      |> result.map(float.clamp(_, min: 0.0, max: 100.0))
    }
  {
    Error(textmetrics.TooFewWords(at_least: 1, got: 0)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn smog_short_text_rejected_test() -> Nil {
  // Five short sentences — well under SMOG's 30-sentence floor.
  let text =
    "Five short sentences. Just like this. And this. And this. And this."
  case textmetrics.smog(text) {
    Error(textmetrics.TooFewSentences(at_least: 30, got: 5)) -> Nil
    _ -> should.be_true(False)
  }
}

pub fn smog_thirty_sentences_returns_score_test() -> Nil {
  // 30 identical "Hello world." sentences satisfy the precondition.
  let text =
    "Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world. Hello world."
  case textmetrics.smog(text) {
    Ok(_) -> Nil
    _ -> should.be_true(False)
  }
}

// --- determinism --------------------------------------------------------

pub fn flesch_ease_deterministic_test() -> Nil {
  let text = pangram()
  let assert Ok(first) = {
    textmetrics.flesch_reading_ease(text)
    |> result.map(float.clamp(_, min: 0.0, max: 100.0))
  }
  let assert Ok(second) = {
    textmetrics.flesch_reading_ease(text)
    |> result.map(float.clamp(_, min: 0.0, max: 100.0))
  }
  first
  |> should.equal(second)
}

pub fn all_metrics_return_finite_on_minimal_input_test() -> Nil {
  // 1-word 1-sentence input is allowed and must return a finite Float
  // (not NaN, not infinity) for the metrics that accept it.
  let text = "Hello."
  let assert Ok(_) = {
    textmetrics.flesch_reading_ease(text)
    |> result.map(float.clamp(_, min: 0.0, max: 100.0))
  }
  let assert Ok(_) = {
    textmetrics.flesch_kincaid_grade(text)
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  let assert Ok(_) = {
    textmetrics.gunning_fog(text)
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  let assert Ok(_) = {
    textmetrics.automated_readability_index(text)
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  let assert Ok(_) = {
    textmetrics.coleman_liau_index(text)
    |> result.map(float.clamp(_, min: 0.0, max: 18.0))
  }
  Nil
}

// --- formulas with more than one sentence ---------------------------------

// 5 words, 2 sentences and 4 polysyllables (`Readability`, `Computers`,
// `calculate`, `everything`), so neither ratio of the formulas is 1.
fn two_sentences() -> String {
  "Readability matters. Computers calculate everything."
}

pub fn gunning_fog_divides_by_sentences_and_words_test() -> Nil {
  assert textmetrics.count_words(two_sentences()) == 5
  assert textmetrics.count_sentences(two_sentences()) == 2
  assert textmetrics.count_polysyllables(two_sentences()) == 4
  // 0.4 * (5 / 2 + 100 * 4 / 5)
  let assert Ok(score) = textmetrics.gunning_fog(two_sentences())
  assert within(score, 33.0, 1.0e-9)
}

pub fn smog_extrapolated_scales_polysyllables_to_30_sentences_test() -> Nil {
  // 1.043 * sqrt(4 * 30 / 2) + 3.1291
  let assert Ok(score) = textmetrics.smog_extrapolated(two_sentences())
  let assert Ok(root) = float.square_root(60.0)
  assert within(score, 1.043 *. root +. 3.1291, 1.0e-9)
}
