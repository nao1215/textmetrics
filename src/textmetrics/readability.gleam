//// Canonical English-language readability scores.
////
//// All six scores in this module — Flesch Reading Ease, Flesch–Kincaid
//// Grade Level, Gunning Fog, SMOG, Automated Readability Index, and
//// Coleman–Liau Index — are computed from the count primitives
//// exposed by [`textmetrics/count`](./count.html). The functions are
//// pure, deterministic, and `O(n)` in input length.
////
//// Returned scores are `Float` values; callers should round or
//// quantise to fit their reporting needs. Input with no words returns
//// [`TooFewWords`](#ReadabilityError) instead of a non-finite number.
////
//// The syllable counter consumed by these formulas is an
//// English-tuned heuristic (see
//// [`count.syllables_in_word`](./count.html#syllables_in_word)).
//// Scores for non-English text should not be interpreted as meaningful
//// grade-level estimates.

import gleam/float
import gleam/int
import gleam/result

import textmetrics/count

/// Errors returned when a readability score cannot be computed
/// because the input does not meet the minimum-size precondition
/// of the underlying formula.
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
  Counts(
    words: count.words(text),
    sentences: count.sentences(text),
    syllables: count.syllables(text),
    characters: count.characters(text),
    polysyllables: count.polysyllables(text),
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

/// Flesch Reading Ease, original Flesch (1948) formula.
///
/// ```text
/// 206.835 − 1.015 × (words/sentences) − 84.6 × (syllables/words)
/// ```
///
/// Higher is easier. The classic interpretation bands:
///
/// - `90–100` — 5th grade reader
/// - `80–90`  — 6th grade
/// - `70–80`  — 7th grade
/// - `60–70`  — 8th–9th grade ("plain English")
/// - `50–60`  — 10th–12th grade
/// - `30–50`  — college
/// - `0–30`   — college graduate
///
/// The result is clamped to `[0.0, 100.0]` to match the standard
/// reporting convention used by Wikipedia, Microsoft Word, Python
/// `textstat`'s default, and most readability UIs. Use
/// [`flesch_reading_ease_unbounded`](#flesch_reading_ease_unbounded)
/// when you need the raw formula output (which can exceed `100` for
/// unusually short or syllable-poor text, and drop below `0` for
/// unusually dense academic prose).
///
/// Returns [`TooFewWords`](#ReadabilityError) for input with no words.
pub fn flesch_reading_ease(text: String) -> Result(Float, ReadabilityError) {
  use raw <- result.try(flesch_reading_ease_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 100.0))
}

/// Flesch Reading Ease without the standard `[0.0, 100.0]` clamp.
/// Returns the raw 206.835 − 1.015 × (words/sentences) − 84.6 ×
/// (syllables/words) value, which can exceed `100` for unusually
/// short text and drop below `0` for unusually dense prose.
pub fn flesch_reading_ease_unbounded(
  text: String,
) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let words_per_sentence =
    int.to_float(counts.words) /. int.to_float(counts.sentences)
  let syllables_per_word =
    int.to_float(counts.syllables) /. int.to_float(counts.words)
  Ok(206.835 -. 1.015 *. words_per_sentence -. 84.6 *. syllables_per_word)
}

fn clamp_float(value: Float, lo lo: Float, hi hi: Float) -> Float {
  case value <. lo {
    True -> lo
    False ->
      case value >. hi {
        True -> hi
        False -> value
      }
  }
}

// --- Flesch–Kincaid Grade Level ------------------------------------------

/// Flesch–Kincaid Grade Level.
///
/// ```text
/// 0.39 × (words/sentences) + 11.8 × (syllables/words) − 15.59
/// ```
///
/// The output approximates the US school grade required to comprehend
/// the text. The result is clamped to `[0.0, 18.0]` (US K–12 plus
/// graduate range) so synthetic inputs cannot produce `-2.88` or
/// `49+`. Use
/// [`flesch_kincaid_grade_unbounded`](#flesch_kincaid_grade_unbounded)
/// for the raw value.
pub fn flesch_kincaid_grade(text: String) -> Result(Float, ReadabilityError) {
  use raw <- result.try(flesch_kincaid_grade_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 18.0))
}

/// Flesch–Kincaid Grade Level without the `[0.0, 18.0]` clamp.
pub fn flesch_kincaid_grade_unbounded(
  text: String,
) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let words_per_sentence =
    int.to_float(counts.words) /. int.to_float(counts.sentences)
  let syllables_per_word =
    int.to_float(counts.syllables) /. int.to_float(counts.words)
  Ok(0.39 *. words_per_sentence +. 11.8 *. syllables_per_word -. 15.59)
}

// --- Gunning Fog ---------------------------------------------------------

/// Gunning Fog Index — Robert Gunning (1952).
///
/// ```text
/// 0.4 × ((words/sentences) + 100 × (polysyllables/words))
/// ```
///
/// A polysyllable here is a word with three or more syllables. The
/// original Gunning rules excluded proper nouns, hyphenated compounds,
/// and inflected forms (-es / -ed / -ing) — this implementation
/// does **not** apply those exclusions. Callers needing the strict
/// variant can subtract their
/// own exclusion count from
/// [`count.polysyllables`](./count.html#polysyllables) before applying
/// the formula directly.
///
/// Output approximates the years of formal education required to
/// understand the text on first reading. The result is clamped to
/// `[0.0, 18.0]`; use [`gunning_fog_unbounded`](#gunning_fog_unbounded)
/// for the raw value.
pub fn gunning_fog(text: String) -> Result(Float, ReadabilityError) {
  use raw <- result.try(gunning_fog_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 18.0))
}

/// Gunning Fog Index without the `[0.0, 18.0]` clamp.
pub fn gunning_fog_unbounded(text: String) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let words_per_sentence =
    int.to_float(counts.words) /. int.to_float(counts.sentences)
  let poly_ratio =
    100.0 *. int.to_float(counts.polysyllables) /. int.to_float(counts.words)
  Ok(0.4 *. { words_per_sentence +. poly_ratio })
}

// --- SMOG ----------------------------------------------------------------

/// Simple Measure of Gobbledygook (SMOG), McLaughlin (1969).
///
/// ```text
/// 1.043 × sqrt(polysyllables × (30/sentences)) + 3.1291
/// ```
///
/// SMOG is statistically reliable only for texts of 30 sentences or
/// more — McLaughlin's regression was calibrated on samples of that
/// size, and applying the formula to shorter passages compounds
/// estimation error. This implementation therefore returns
/// [`TooFewSentences`](#ReadabilityError) when the input has fewer
/// than 30 sentences.
pub fn smog(text: String) -> Result(Float, ReadabilityError) {
  let counts = build_counts(text)
  use _ <- result.try(require_words(counts, 1))
  use _ <- result.try(require_sentences(counts, 30))
  Ok(smog_from_counts(counts))
}

/// SMOG-G — the same formula as SMOG, applied to texts shorter than
/// 30 sentences via the same `30 / sentences` scaling already used
/// inside SMOG. Issue #23: real-world snippets (a Wikipedia paragraph,
/// a press release, a tweet, an email) almost never have 30 sentences,
/// so the strict SMOG gate rules them all out. SMOG-G drops the gate
/// and returns the extrapolated grade for any non-empty input with
/// at least one sentence.
///
/// Use [`smog`](#smog) when you have 30+ sentences and need the
/// statistically calibrated form; use `smog_g` for everything else.
/// For 30 or more sentences both return the same value.
pub fn smog_g(text: String) -> Result(Float, ReadabilityError) {
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

/// Automated Readability Index (ARI), Smith & Senter (1967).
///
/// ```text
/// 4.71 × (characters/words) + 0.5 × (words/sentences) − 21.43
/// ```
///
/// The `characters` count is `letters + digits + accented graphemes`
/// (i.e. [`count.characters`](./count.html#characters)) and excludes
/// whitespace and punctuation. Digits count as characters, as in
/// Coleman–Liau.
/// The result is clamped to `[0.0, 18.0]`; use
/// [`automated_readability_index_unbounded`](#automated_readability_index_unbounded)
/// for the raw value.
pub fn automated_readability_index(
  text: String,
) -> Result(Float, ReadabilityError) {
  use raw <- result.try(automated_readability_index_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 18.0))
}

/// Automated Readability Index without the `[0.0, 18.0]` clamp.
pub fn automated_readability_index_unbounded(
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

/// Coleman–Liau Index, Coleman & Liau (1975).
///
/// ```text
/// 0.0588 × L − 0.296 × S − 15.8
/// ```
///
/// where
///
/// - `L` = average number of letters per 100 words
///   (`characters / words × 100`)
/// - `S` = average number of sentences per 100 words
///   (`sentences / words × 100`)
///
/// The output approximates the US grade level expected to read the
/// text comfortably. Like ARI, this formula uses the
/// [`count.characters`](./count.html#characters) definition, so a
/// digit counts as one letter.
///
/// The result is clamped to `[0.0, 18.0]`; use
/// [`coleman_liau_index_unbounded`](#coleman_liau_index_unbounded) for
/// the raw value.
pub fn coleman_liau_index(text: String) -> Result(Float, ReadabilityError) {
  use raw <- result.try(coleman_liau_index_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 18.0))
}

/// Coleman–Liau Index without the `[0.0, 18.0]` clamp.
pub fn coleman_liau_index_unbounded(
  text: String,
) -> Result(Float, ReadabilityError) {
  use counts <- result.try(counts_with_a_word(text))
  let letters_per_100 =
    int.to_float(counts.characters) /. int.to_float(counts.words) *. 100.0
  let sentences_per_100 =
    int.to_float(counts.sentences) /. int.to_float(counts.words) *. 100.0
  Ok(0.0588 *. letters_per_100 -. 0.296 *. sentences_per_100 -. 15.8)
}
