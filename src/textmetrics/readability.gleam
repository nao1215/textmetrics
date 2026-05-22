//// Canonical English-language readability scores.
////
//// All six scores in this module — Flesch Reading Ease, Flesch–Kincaid
//// Grade Level, Gunning Fog, SMOG, Automated Readability Index, and
//// Coleman–Liau Index — are computed from the count primitives
//// exposed by [`textmetrics/count`](./count.html). The functions are
//// pure, deterministic, and `O(n)` in input length.
////
//// Returned scores are `Float` values; callers should round or
//// quantise to fit their reporting needs. Empty or extremely small
//// inputs return [`ReadabilityError`](#ReadabilityError) instead of
//// non-finite numbers.
////
//// The syllable counter consumed by these formulas is an
//// English-tuned heuristic (see
//// [`count.syllables_in_word`](./count.html#syllables_in_word)).
//// Non-English text will produce scores that match `textstat`'s
//// fallback behaviour but should not be interpreted as meaningful
//// grade-level estimates.
////
//// Reference scores produced by these implementations agree with
//// Python `textstat` (the de-facto reference) to within roughly
//// ±2 on the Reading Ease 0–100 scale and ±1 on grade-level scales,
//// over a corpus of fixtures from the Wikipedia readability articles.

import gleam/float
import gleam/int

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

fn require_words(c: Counts, at_least: Int) -> Result(Nil, ReadabilityError) {
  case c.words >= at_least {
    True -> Ok(Nil)
    False -> Error(TooFewWords(at_least: at_least, got: c.words))
  }
}

fn require_sentences(c: Counts, at_least: Int) -> Result(Nil, ReadabilityError) {
  case c.sentences >= at_least {
    True -> Ok(Nil)
    False -> Error(TooFewSentences(at_least: at_least, got: c.sentences))
  }
}

fn to_float(n: Int) -> Float {
  int.to_float(n)
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
/// Returns [`TooFewWords`](#ReadabilityError) for input with no words,
/// and [`TooFewSentences`](#ReadabilityError) for input with no
/// sentence-shaped content.
pub fn flesch_reading_ease(text: String) -> Result(Float, ReadabilityError) {
  use raw <- result_try(flesch_reading_ease_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 100.0))
}

/// Flesch Reading Ease without the standard `[0.0, 100.0]` clamp.
/// Returns the raw 206.835 − 1.015 × (words/sentences) − 84.6 ×
/// (syllables/words) value, which can exceed `100` for unusually
/// short text and drop below `0` for unusually dense prose.
pub fn flesch_reading_ease_unbounded(
  text: String,
) -> Result(Float, ReadabilityError) {
  let c = build_counts(text)
  use _ <- result_try(require_words(c, 1))
  use _ <- result_try(require_sentences(c, 1))
  let wps = to_float(c.words) /. to_float(c.sentences)
  let spw = to_float(c.syllables) /. to_float(c.words)
  Ok(206.835 -. 1.015 *. wps -. 84.6 *. spw)
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
  use raw <- result_try(flesch_kincaid_grade_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 18.0))
}

/// Flesch–Kincaid Grade Level without the `[0.0, 18.0]` clamp.
pub fn flesch_kincaid_grade_unbounded(
  text: String,
) -> Result(Float, ReadabilityError) {
  let c = build_counts(text)
  use _ <- result_try(require_words(c, 1))
  use _ <- result_try(require_sentences(c, 1))
  let wps = to_float(c.words) /. to_float(c.sentences)
  let spw = to_float(c.syllables) /. to_float(c.words)
  Ok(0.39 *. wps +. 11.8 *. spw -. 15.59)
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
/// follows Python `textstat` and does **not** apply those
/// exclusions, so scores match `textstat` rather than the strict
/// 1952 paper. Callers needing the strict variant can subtract their
/// own exclusion count from
/// [`count.polysyllables`](./count.html#polysyllables) before applying
/// the formula directly.
///
/// Output approximates the years of formal education required to
/// understand the text on first reading. The result is clamped to
/// `[0.0, 18.0]`; use [`gunning_fog_unbounded`](#gunning_fog_unbounded)
/// for the raw value.
pub fn gunning_fog(text: String) -> Result(Float, ReadabilityError) {
  use raw <- result_try(gunning_fog_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 18.0))
}

/// Gunning Fog Index without the `[0.0, 18.0]` clamp.
pub fn gunning_fog_unbounded(text: String) -> Result(Float, ReadabilityError) {
  let c = build_counts(text)
  use _ <- result_try(require_words(c, 1))
  use _ <- result_try(require_sentences(c, 1))
  let wps = to_float(c.words) /. to_float(c.sentences)
  let poly_ratio = 100.0 *. to_float(c.polysyllables) /. to_float(c.words)
  Ok(0.4 *. { wps +. poly_ratio })
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
  let c = build_counts(text)
  use _ <- result_try(require_words(c, 1))
  use _ <- result_try(require_sentences(c, 30))
  Ok(smog_from_counts(c))
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
/// The two agree to within ~1 grade for 30+ sentences.
pub fn smog_g(text: String) -> Result(Float, ReadabilityError) {
  let c = build_counts(text)
  use _ <- result_try(require_words(c, 1))
  use _ <- result_try(require_sentences(c, 1))
  Ok(smog_from_counts(c))
}

fn smog_from_counts(c: Counts) -> Float {
  let polys = to_float(c.polysyllables)
  let scale = 30.0 /. to_float(c.sentences)
  // `polys × scale` is always >= 0 (polysyllables ≥ 0, sentences > 0
  // by the precondition), so `float.square_root` cannot return Error
  // here. Default the unreachable branch to 0.0 so the surrounding
  // Result chain stays in the ReadabilityError domain.
  let root = case float.square_root(polys *. scale) {
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
/// whitespace and punctuation. ARI is the only formula in this
/// module that treats digits as score-bearing characters; texts
/// containing large numeric runs will score correspondingly higher.
/// The result is clamped to `[0.0, 18.0]`; use
/// [`automated_readability_index_unbounded`](#automated_readability_index_unbounded)
/// for the raw value.
pub fn automated_readability_index(
  text: String,
) -> Result(Float, ReadabilityError) {
  use raw <- result_try(automated_readability_index_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 18.0))
}

/// Automated Readability Index without the `[0.0, 18.0]` clamp.
pub fn automated_readability_index_unbounded(
  text: String,
) -> Result(Float, ReadabilityError) {
  let c = build_counts(text)
  use _ <- result_try(require_words(c, 1))
  use _ <- result_try(require_sentences(c, 1))
  let cpw = to_float(c.characters) /. to_float(c.words)
  let wps = to_float(c.words) /. to_float(c.sentences)
  Ok(4.71 *. cpw +. 0.5 *. wps -. 21.43)
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
/// [`count.characters`](./count.html#characters) definition (letters
/// + digits), so digit-heavy text scores slightly higher than its
/// pure-prose equivalent.
///
/// The result is clamped to `[0.0, 18.0]`; use
/// [`coleman_liau_index_unbounded`](#coleman_liau_index_unbounded) for
/// the raw value.
pub fn coleman_liau_index(text: String) -> Result(Float, ReadabilityError) {
  use raw <- result_try(coleman_liau_index_unbounded(text))
  Ok(clamp_float(raw, lo: 0.0, hi: 18.0))
}

/// Coleman–Liau Index without the `[0.0, 18.0]` clamp.
pub fn coleman_liau_index_unbounded(
  text: String,
) -> Result(Float, ReadabilityError) {
  let c = build_counts(text)
  use _ <- result_try(require_words(c, 1))
  use _ <- result_try(require_sentences(c, 1))
  let letters_per_100 = to_float(c.characters) /. to_float(c.words) *. 100.0
  let sentences_per_100 = to_float(c.sentences) /. to_float(c.words) *. 100.0
  Ok(0.0588 *. letters_per_100 -. 0.296 *. sentences_per_100 -. 15.8)
}

// --- internal `result.try` shim ------------------------------------------
//
// The full `gleam/result` module isn't imported here because we only need
// the `try` combinator and the rest of this module's surface is
// arithmetic. Keeping the helper local makes the formula functions read
// as straight arithmetic without an extra qualified-import line.

fn result_try(r: Result(a, b), cont: fn(a) -> Result(c, b)) -> Result(c, b) {
  case r {
    Ok(v) -> cont(v)
    Error(e) -> Error(e)
  }
}
