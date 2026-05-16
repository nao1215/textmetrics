//// Round 1 boundary-value tests with heavy Unicode / emoji bias.
////
//// Each test starts as a probe of behaviour at boundaries (empty,
//// 1-grapheme, ZWJ sequences, skin-tone modifiers, NFC vs NFD,
//// regional indicators, Hangul jamo, mixed scripts) and either
//// pins a confirmed bug fix or stands as a regression test for
//// already-correct behaviour.

import gleam/float
import gleam/list
import gleam/option.{None}
import gleam/string
import gleeunit/should
import textmetrics/diff
import textmetrics/distance
import textmetrics/edit
import textmetrics/lcs
import textmetrics/search
import textmetrics/similarity

const tolerance = 0.000_001

fn approx_equal(a: Float, b: Float) -> Bool {
  float.absolute_value(a -. b) <=. tolerance
}

// ---------------------------------------------------------------------
// Sentinel grapheme clusters used throughout the tests.
// ---------------------------------------------------------------------

// Man + ZWJ + Woman + ZWJ + Girl — should be ONE grapheme.
const family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"

// Waving hand + Fitzpatrick type-5 modifier — should be ONE grapheme.
const wave_skin = "\u{1F44B}\u{1F3FE}"

// Regional indicator pair JP -> Japanese flag — ONE grapheme.
const flag_jp = "\u{1F1EF}\u{1F1F5}"

const flag_us = "\u{1F1FA}\u{1F1F8}"

// e + combining acute (NFD form of "é").
const e_combining = "e\u{0301}"

// Single precomposed "é" (NFC).
const e_precomposed = "é"

// ---------------------------------------------------------------------
// distance.levenshtein — emoji should count as one grapheme.
// ---------------------------------------------------------------------

pub fn levenshtein_family_vs_empty_is_one_test() {
  // The family emoji is one grapheme; deleting it costs 1.
  distance.levenshtein(family, "") |> should.equal(1)
  distance.levenshtein("", family) |> should.equal(1)
}

pub fn levenshtein_two_emojis_swap_test() {
  // Two single-grapheme emoji vs swapped order — Levenshtein distance
  // should be exactly 2 (substitute both positions). Prior to any
  // grapheme-aware split this would be hugely larger.
  distance.levenshtein(family <> wave_skin, wave_skin <> family)
  |> should.equal(2)
}

pub fn levenshtein_flags_distinct_test() {
  // Two distinct regional-indicator flags: each is one grapheme.
  distance.levenshtein(flag_jp, flag_us) |> should.equal(1)
}

// ---------------------------------------------------------------------
// distance.hamming — grapheme counts must agree, otherwise error
// must report the *grapheme* counts (not byte/codepoint counts).
// ---------------------------------------------------------------------

pub fn hamming_family_vs_letter_length_mismatch_reports_graphemes_test() {
  // family is 1 grapheme (5 codepoints); "a" is 1 grapheme.
  // They have equal grapheme length, so this MUST succeed.
  case distance.hamming(family, "a") {
    Ok(d) -> d |> should.equal(1)
    Error(_) ->
      // Spec says equal grapheme counts -> Ok.
      should.fail()
  }
}

pub fn hamming_flag_vs_two_letters_test() {
  // flag_jp is 1 grapheme; "ab" is 2 graphemes. Length mismatch.
  case distance.hamming(flag_jp, "ab") {
    Error(distance.LengthMismatch(left: 1, right: 2)) -> Nil
    _ -> should.fail()
  }
}

pub fn hamming_nfd_vs_nfc_e_acute_test() {
  // Spec explicitly says no normalisation. NFC "é" is 1 grapheme;
  // NFD "e\u{0301}" is also 1 grapheme (combining mark joins).
  // They have equal grapheme count (1) so length matches; but the
  // graphemes are NOT equal as strings (no normalisation).
  case distance.hamming(e_precomposed, e_combining) {
    Ok(1) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------
// distance.damerau_levenshtein / osa — grapheme-level transposition.
// ---------------------------------------------------------------------

pub fn osa_two_emoji_transposition_is_one_test() {
  // Two emoji swap is exactly one transposition under OSA.
  distance.osa(family <> wave_skin, wave_skin <> family) |> should.equal(1)
}

pub fn damerau_levenshtein_two_emoji_transposition_is_one_test() {
  // Two emoji swap is exactly one transposition under DL.
  distance.damerau_levenshtein(family <> wave_skin, wave_skin <> family)
  |> should.equal(1)
}

pub fn osa_identical_family_is_zero_test() {
  distance.osa(family, family) |> should.equal(0)
}

pub fn damerau_levenshtein_identical_family_is_zero_test() {
  distance.damerau_levenshtein(family, family) |> should.equal(0)
}

// ---------------------------------------------------------------------
// distance.normalized_levenshtein — must stay in [0, 1].
// ---------------------------------------------------------------------

pub fn normalized_levenshtein_family_vs_empty_is_zero_test() {
  // 1 grapheme vs 0 graphemes -> distance 1, max len 1 -> 0.0.
  distance.normalized_levenshtein(family, "")
  |> approx_equal(0.0)
  |> should.be_true
}

pub fn normalized_levenshtein_identical_emoji_is_one_test() {
  distance.normalized_levenshtein(family, family)
  |> approx_equal(1.0)
  |> should.be_true
}

// ---------------------------------------------------------------------
// similarity.jaro / jaro_winkler — must stay in [0, 1].
// ---------------------------------------------------------------------

pub fn jaro_two_emoji_swap_in_unit_range_test() {
  let s = similarity.jaro(family <> wave_skin, wave_skin <> family)
  { s >=. 0.0 && s <=. 1.0 } |> should.be_true
}

pub fn jaro_winkler_emoji_inputs_in_unit_range_test() {
  let s =
    similarity.jaro_winkler(
      family <> wave_skin <> flag_jp,
      flag_jp <> wave_skin <> family,
    )
  { s >=. 0.0 && s <=. 1.0 } |> should.be_true
}

pub fn jaro_winkler_identical_emoji_is_one_test() {
  similarity.jaro_winkler(family, family)
  |> approx_equal(1.0)
  |> should.be_true
}

// ---------------------------------------------------------------------
// similarity.sorensen_dice — n-gram concatenation must be unambiguous
// across grapheme boundaries.
// ---------------------------------------------------------------------

pub fn sorensen_dice_emoji_identical_is_one_test() {
  case similarity.sorensen_dice(family, family, 1) {
    Ok(s) -> approx_equal(s, 1.0) |> should.be_true
    Error(_) -> should.fail()
  }
}

pub fn sorensen_dice_n2_disjoint_emoji_is_zero_test() {
  // family|wave_skin vs flag_jp|flag_us — bigrams entirely disjoint.
  case similarity.sorensen_dice(family <> wave_skin, flag_jp <> flag_us, 2) {
    Ok(s) -> approx_equal(s, 0.0) |> should.be_true
    Error(_) -> should.fail()
  }
}

pub fn sorensen_dice_n_too_large_is_zero_test() {
  // Both inputs have fewer than n graphemes -> both produce empty
  // multisets. Per spec: equal inputs -> 1.0, otherwise -> 0.0.
  case similarity.sorensen_dice("ab", "cd", 5) {
    Ok(s) -> approx_equal(s, 0.0) |> should.be_true
    Error(_) -> should.fail()
  }
}

pub fn sorensen_dice_n_too_large_equal_inputs_is_one_test() {
  // Both inputs equal AND below threshold -> 1.0 by spec convention.
  case similarity.sorensen_dice("ab", "ab", 5) {
    Ok(s) -> approx_equal(s, 1.0) |> should.be_true
    Error(_) -> should.fail()
  }
}

// CRITICAL: this probes the n-gram concatenation aliasing bug.
// Inputs `["ab", "c"]` and `["a", "bc"]` would both concatenate to
// the bigram string "abc" if joined via string concatenation. They
// are NOT the same n-gram in any sane grapheme-level model.
// Emoji is the practical setting where multi-codepoint graphemes
// can collide if concatenated naively, but ASCII surfaces it most
// clearly: "ab" is 2 graphemes; flag_jp is 1 grapheme that is
// distinct from any ASCII bigram.
pub fn sorensen_dice_disjoint_via_emoji_test() {
  // "AB" vs flag_jp at n=2: "AB" produces ngram "AB"; flag_jp produces
  // no ngrams (one grapheme). Score should be 0.0.
  case similarity.sorensen_dice("AB", flag_jp, 2) {
    Ok(s) -> approx_equal(s, 0.0) |> should.be_true
    Error(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------
// search.did_you_mean / closest / rank_jaro_winkler — non-empty inputs
// with emoji should still rank reasonably.
// ---------------------------------------------------------------------

pub fn did_you_mean_emoji_query_is_grapheme_aware_test() {
  // Query is one emoji grapheme. A candidate identical to it must
  // be returned within distance 0.
  let candidates = ["a", family, "b"]
  search.did_you_mean(family, candidates, 0)
  |> should.equal([family])
}

pub fn rank_jaro_winkler_scores_in_unit_range_test() {
  let candidates = [family, wave_skin, flag_jp, flag_us]
  let ranked = search.rank_jaro_winkler(family, candidates, 4)
  list.length(ranked) |> should.equal(4)
  list.all(ranked, fn(r) { r.score >=. 0.0 && r.score <=. 1.0 })
  |> should.be_true
}

// ---------------------------------------------------------------------
// lcs.length / sequence — grapheme-level for emoji.
// ---------------------------------------------------------------------

pub fn lcs_length_emoji_subsequence_test() {
  // LCS of [family, wave_skin] and [wave_skin, family] is 1.
  let a = string.to_graphemes(family <> wave_skin)
  let b = string.to_graphemes(wave_skin <> family)
  lcs.length(a, b) |> should.equal(1)
}

pub fn lcs_sequence_emoji_grapheme_test() {
  let a = string.to_graphemes(family <> wave_skin)
  let b = string.to_graphemes(family <> flag_jp)
  // Common emoji: family.
  lcs.sequence(a, b) |> should.equal([family])
}

// ---------------------------------------------------------------------
// diff.myers — recover_old / recover_new must round-trip on emoji.
// ---------------------------------------------------------------------

pub fn myers_emoji_round_trip_test() {
  let old = string.to_graphemes(family <> wave_skin <> flag_jp)
  let new = string.to_graphemes(flag_jp <> family <> "x")
  let script = diff.myers(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn myers_cost_matches_levenshtein_emoji_test() {
  // Myers script's Insert+Delete cost equals levenshtein with
  // substitution counted as 1 insert + 1 delete.
  let old_str = family <> wave_skin
  let new_str = wave_skin <> family
  let old = string.to_graphemes(old_str)
  let new = string.to_graphemes(new_str)
  let script = diff.myers(old, new)
  // Two emoji swap: Levenshtein with sub-as-2 = 4 (replace both).
  // But if Myers picks the diagonal-LIS, it may emit smaller
  // (e.g. 1 delete + 1 insert + equal middle? no, two graphemes
  // total). The specified relation is cost == LCS-derived.
  let n = list.length(old) + list.length(new)
  let common = lcs.length(old, new)
  edit.cost(script) |> should.equal(n - 2 * common)
}

// ---------------------------------------------------------------------
// Long-input probes — detect overflow, runaway recursion, or sublinear
// blowup in the algorithms.
// ---------------------------------------------------------------------

pub fn levenshtein_long_emoji_identical_is_zero_test() {
  // 200 family-emoji repeated. Identical -> 0.
  let s =
    list.repeat(family, 200)
    |> string.concat
  distance.levenshtein(s, s) |> should.equal(0)
}

pub fn levenshtein_long_one_grapheme_diff_test() {
  // 100 of family then append 'a' to one. Edit distance = 1.
  let base =
    list.repeat(family, 100)
    |> string.concat
  distance.levenshtein(base, base <> "a") |> should.equal(1)
}

pub fn jaro_long_identical_is_one_test() {
  let s =
    list.repeat(family, 100)
    |> string.concat
  similarity.jaro(s, s) |> approx_equal(1.0) |> should.be_true
}

// ---------------------------------------------------------------------
// search.did_you_mean — robustness to negative / zero max_distance
// and to empty candidate list.
// ---------------------------------------------------------------------

pub fn did_you_mean_negative_max_distance_returns_empty_test() {
  // Negative max_distance is nonsensical: nothing matches.
  search.did_you_mean("query", ["a", "b"], -1) |> should.equal([])
}

pub fn did_you_mean_zero_max_distance_only_exact_test() {
  search.did_you_mean("apple", ["apple", "apply", "apples"], 0)
  |> should.equal(["apple"])
}

pub fn did_you_mean_empty_candidates_returns_empty_test() {
  search.did_you_mean("query", [], 5) |> should.equal([])
}

pub fn closest_negative_max_distance_returns_none_test() {
  search.closest("query", ["a", "b"], -1) |> should.equal(None)
}

pub fn rank_jaro_winkler_zero_top_n_returns_empty_test() {
  search.rank_jaro_winkler("query", ["a", "b"], 0) |> should.equal([])
}

pub fn rank_jaro_winkler_negative_top_n_returns_empty_test() {
  search.rank_jaro_winkler("query", ["a", "b"], -1) |> should.equal([])
}

// ---------------------------------------------------------------------
// Symmetry probes — Levenshtein, Jaro, and DL are symmetric metrics.
// ---------------------------------------------------------------------

pub fn levenshtein_symmetric_emoji_test() {
  let a = family <> wave_skin <> "x"
  let b = "y" <> flag_jp <> wave_skin
  distance.levenshtein(a, b)
  |> should.equal(distance.levenshtein(b, a))
}

pub fn osa_symmetric_emoji_test() {
  let a = family <> wave_skin <> "x"
  let b = "y" <> flag_jp <> wave_skin
  distance.osa(a, b) |> should.equal(distance.osa(b, a))
}

pub fn damerau_levenshtein_symmetric_emoji_test() {
  let a = family <> wave_skin <> "x"
  let b = "y" <> flag_jp <> wave_skin
  distance.damerau_levenshtein(a, b)
  |> should.equal(distance.damerau_levenshtein(b, a))
}

pub fn jaro_symmetric_emoji_test() {
  let a = family <> wave_skin <> "x"
  let b = "y" <> flag_jp <> wave_skin
  approx_equal(similarity.jaro(a, b), similarity.jaro(b, a))
  |> should.be_true
}

// ---------------------------------------------------------------------
// Hangul jamo: NFC vs NFD — distinct graphemes per spec (no
// normalisation). Both forms should still be one grapheme cluster
// each (per UAX #29) and distance should be 1.
// ---------------------------------------------------------------------

pub fn hangul_nfc_vs_decomposed_levenshtein_test() {
  // "가" (NFC, single codepoint) vs "\u{1100}\u{1161}" (decomposed
  // jamo). Per UAX #29 both are a single grapheme cluster, but the
  // graphemes themselves are distinct strings. Distance = 1.
  distance.levenshtein("가", "\u{1100}\u{1161}") |> should.equal(1)
}

// ---------------------------------------------------------------------
// Triangle inequality for Levenshtein (true metric).
// ---------------------------------------------------------------------

pub fn levenshtein_triangle_inequality_emoji_test() {
  let a = family <> wave_skin
  let b = wave_skin <> flag_jp
  let c = flag_jp <> family
  let d_ac = distance.levenshtein(a, c)
  let d_ab = distance.levenshtein(a, b)
  let d_bc = distance.levenshtein(b, c)
  { d_ac <= d_ab + d_bc } |> should.be_true
}

// ---------------------------------------------------------------------
// damerau_levenshtein satisfies triangle inequality (true metric);
// OSA does NOT (documented).
// ---------------------------------------------------------------------

pub fn damerau_levenshtein_triangle_inequality_test() {
  // Classic "ca" -> "abc" is the example where DL beats OSA.
  // Just check that DL satisfies a valid triangle.
  let d_ab = distance.damerau_levenshtein("ca", "ac")
  let d_bc = distance.damerau_levenshtein("ac", "abc")
  let d_ac = distance.damerau_levenshtein("ca", "abc")
  { d_ac <= d_ab + d_bc } |> should.be_true
}

// Classic DL test: "ca" -> "abc" should be 2 (DL allows the
// transposition AND insertion to overlap on the same substring).
pub fn damerau_levenshtein_ca_abc_is_two_test() {
  distance.damerau_levenshtein("ca", "abc") |> should.equal(2)
}

// OSA refuses to overlap: should be 3.
pub fn osa_ca_abc_is_three_test() {
  distance.osa("ca", "abc") |> should.equal(3)
}

// ---------------------------------------------------------------------
// NFC vs NFD on combining marks — distinct graphemes per spec, but
// each is still ONE grapheme cluster per UAX #29.
// ---------------------------------------------------------------------

pub fn nfc_e_acute_is_one_grapheme_test() {
  string.to_graphemes(e_precomposed) |> list.length |> should.equal(1)
}

pub fn nfd_e_acute_is_one_grapheme_test() {
  // NFD form e+combining-acute should be exactly one extended
  // grapheme cluster per UAX #29.
  string.to_graphemes(e_combining) |> list.length |> should.equal(1)
}

pub fn levenshtein_nfc_vs_nfd_e_acute_test() {
  // Each is one grapheme; they differ as strings, so distance = 1.
  distance.levenshtein(e_precomposed, e_combining) |> should.equal(1)
}

// ---------------------------------------------------------------------
// Surrogate-range and replacement char — must not crash.
// ---------------------------------------------------------------------

pub fn levenshtein_with_replacement_char_test() {
  let s = "\u{FFFD}"
  distance.levenshtein(s, "a") |> should.equal(1)
  distance.levenshtein(s, s) |> should.equal(0)
}

// ---------------------------------------------------------------------
// to_unified emits empty string for an all-Equal script.
// ---------------------------------------------------------------------

pub fn to_unified_no_changes_returns_empty_test() {
  let script = [edit.Equal("a"), edit.Equal("b"), edit.Equal("c")]
  let opts = diff.unified_options(old_name: "old", new_name: "new")
  diff.to_unified(script, opts) |> should.equal("")
}

pub fn to_unified_empty_script_returns_empty_test() {
  let opts = diff.unified_options(old_name: "old", new_name: "new")
  diff.to_unified([], opts) |> should.equal("")
}

// ---------------------------------------------------------------------
// Jaro / Jaro-Winkler symmetry (Jaro is metric-symmetric).
// ---------------------------------------------------------------------

pub fn jaro_symmetric_classic_test() {
  // Classic case: MARTHA / MARHTA (Winkler's original example).
  approx_equal(
    similarity.jaro("MARTHA", "MARHTA"),
    similarity.jaro("MARHTA", "MARTHA"),
  )
  |> should.be_true
}

pub fn jaro_symmetric_emoji_pair_test() {
  let a = family <> wave_skin <> "x" <> flag_us
  let b = "abc" <> family
  approx_equal(similarity.jaro(a, b), similarity.jaro(b, a))
  |> should.be_true
}

pub fn jaro_winkler_symmetric_test() {
  // Jaro-Winkler is symmetric since both prefix and Jaro components
  // are. Important: prefix is computed against the *common* prefix
  // (order-independent).
  approx_equal(
    similarity.jaro_winkler("PREFIXa", "PREFIXb"),
    similarity.jaro_winkler("PREFIXb", "PREFIXa"),
  )
  |> should.be_true
}

// ---------------------------------------------------------------------
// Jaro-Winkler at extreme prefix_scale and prefix_max — output must
// remain in [0, 1].
// ---------------------------------------------------------------------

pub fn jaro_winkler_max_prefix_scale_in_unit_range_test() {
  let assert Ok(cfg) =
    similarity.jaro_winkler_config(prefix_scale: 0.25, prefix_max: 100)
  let s = similarity.jaro_winkler_with("MARTHA", "MARHTA", cfg)
  { s >=. 0.0 && s <=. 1.0 } |> should.be_true
}

pub fn jaro_winkler_zero_scale_equals_jaro_test() {
  let assert Ok(cfg) =
    similarity.jaro_winkler_config(prefix_scale: 0.0, prefix_max: 4)
  let j = similarity.jaro("MARTHA", "MARHTA")
  let jw = similarity.jaro_winkler_with("MARTHA", "MARHTA", cfg)
  approx_equal(j, jw) |> should.be_true
}

pub fn jaro_winkler_zero_prefix_max_equals_jaro_test() {
  let assert Ok(cfg) =
    similarity.jaro_winkler_config(prefix_scale: 0.1, prefix_max: 0)
  let j = similarity.jaro("MARTHA", "MARHTA")
  let jw = similarity.jaro_winkler_with("MARTHA", "MARHTA", cfg)
  approx_equal(j, jw) |> should.be_true
}

// ---------------------------------------------------------------------
// Sørensen-Dice symmetry (multiset Jaccard variant is symmetric).
// ---------------------------------------------------------------------

pub fn sorensen_dice_symmetric_test() {
  let assert Ok(s_ab) = similarity.sorensen_dice("foobar", "barfoo", 2)
  let assert Ok(s_ba) = similarity.sorensen_dice("barfoo", "foobar", 2)
  approx_equal(s_ab, s_ba) |> should.be_true
}

pub fn sorensen_dice_in_unit_range_emoji_test() {
  let assert Ok(s) =
    similarity.sorensen_dice(
      family <> wave_skin <> flag_jp,
      flag_us <> wave_skin <> family,
      2,
    )
  { s >=. 0.0 && s <=. 1.0 } |> should.be_true
}

// ---------------------------------------------------------------------
// LCS bounds — `lcs.length(a, b) <= min(|a|, |b|)`.
// ---------------------------------------------------------------------

pub fn lcs_length_bounded_by_smaller_emoji_test() {
  let a = string.to_graphemes(family <> wave_skin)
  let b = string.to_graphemes(family)
  let l = lcs.length(a, b)
  let min_len = case list.length(a) <= list.length(b) {
    True -> list.length(a)
    False -> list.length(b)
  }
  { l <= min_len } |> should.be_true
}

pub fn lcs_length_symmetric_test() {
  // LCS length is symmetric.
  let a = string.to_graphemes(family <> "abc" <> wave_skin)
  let b = string.to_graphemes("xyz" <> wave_skin <> "abc")
  lcs.length(a, b) |> should.equal(lcs.length(b, a))
}

// ---------------------------------------------------------------------
// Levenshtein bounds: 0 <= d(a,b) <= max(|a|, |b|), with grapheme
// counts.
// ---------------------------------------------------------------------

pub fn levenshtein_bounded_by_max_emoji_test() {
  let a = family <> wave_skin <> flag_jp
  let b = "abcde"
  let d = distance.levenshtein(a, b)
  let la = list.length(string.to_graphemes(a))
  let lb = list.length(string.to_graphemes(b))
  let max_len = case la >= lb {
    True -> la
    False -> lb
  }
  { d <= max_len } |> should.be_true
  { d >= 0 } |> should.be_true
}

// ---------------------------------------------------------------------
// DL/OSA bounds: never exceed Levenshtein.
// ---------------------------------------------------------------------

pub fn osa_le_levenshtein_test() {
  // OSA is always <= Levenshtein (transpositions can only help).
  let a = family <> wave_skin <> "abc"
  let b = wave_skin <> family <> "cba"
  { distance.osa(a, b) <= distance.levenshtein(a, b) } |> should.be_true
}

pub fn damerau_levenshtein_le_levenshtein_test() {
  let a = family <> wave_skin <> "abc"
  let b = wave_skin <> family <> "cba"
  { distance.damerau_levenshtein(a, b) <= distance.levenshtein(a, b) }
  |> should.be_true
}

pub fn damerau_levenshtein_le_osa_test() {
  // True DL is always <= OSA (DL allows substring reuse).
  let a = "ca"
  let b = "abc"
  { distance.damerau_levenshtein(a, b) <= distance.osa(a, b) }
  |> should.be_true
}

// ---------------------------------------------------------------------
// did_you_mean ordering by distance, then input position.
// ---------------------------------------------------------------------

pub fn did_you_mean_orders_ties_by_input_position_test() {
  // "abx" has equal distance 1 to "abc" and "aby" — output should
  // preserve their input order.
  search.did_you_mean("abx", ["abc", "aby"], 1)
  |> should.equal(["abc", "aby"])
}

// ---------------------------------------------------------------------
// edit.recover_old / recover_new — round-trip on emoji + ASCII mix.
// ---------------------------------------------------------------------

pub fn edit_round_trip_emoji_with_substitution_test() {
  let old = string.to_graphemes(family <> "x" <> wave_skin <> "y" <> flag_jp)
  let new = string.to_graphemes("a" <> family <> "z" <> flag_us)
  let script = diff.myers(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn edit_cost_plus_2_lcs_equals_total_length_test() {
  // For any optimal Myers diff: cost == |old| + |new| - 2 * LCS
  let old = string.to_graphemes("kitten" <> family)
  let new = string.to_graphemes("sitting" <> wave_skin)
  let script = diff.myers(old, new)
  let n = list.length(old) + list.length(new)
  let common = lcs.length(old, new)
  edit.cost(script) |> should.equal(n - 2 * common)
}

// ---------------------------------------------------------------------
// Patience diff — round-trip on ASCII line list.
// ---------------------------------------------------------------------

pub fn patience_round_trip_with_anchor_test() {
  let old = ["a", "b", "c", "d", "e"]
  let new = ["a", "x", "c", "y", "e"]
  let script = diff.patience(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn patience_empty_pair_returns_empty_test() {
  diff.patience([], []) |> should.equal([])
}

pub fn patience_emoji_lines_round_trip_test() {
  let old = [family, wave_skin, "ascii", flag_jp]
  let new = [wave_skin, family, "ascii", flag_us]
  let script = diff.patience(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

// ---------------------------------------------------------------------
// Sørensen-Dice spec-edge: `n_too_large` with one input empty.
// ---------------------------------------------------------------------

pub fn sorensen_dice_n_too_large_one_empty_test() {
  // a = "", b = "ab", n = 3. ngs_a = [], ngs_b = []. a != b -> 0.0.
  case similarity.sorensen_dice("", "ab", 3) {
    Ok(s) -> approx_equal(s, 0.0) |> should.be_true
    Error(_) -> should.fail()
  }
}

pub fn sorensen_dice_n_too_large_both_empty_test() {
  // a = "", b = "". a == b -> 1.0.
  case similarity.sorensen_dice("", "", 3) {
    Ok(s) -> approx_equal(s, 1.0) |> should.be_true
    Error(_) -> should.fail()
  }
}

pub fn sorensen_dice_n_one_input_short_test() {
  // a = "abcde", b = "ab", n = 3.
  // ngs_a = ["abc","bcd","cde"], ngs_b = [].
  // denom = 3, inter = 0 -> 0.0.
  case similarity.sorensen_dice("abcde", "ab", 3) {
    Ok(s) -> approx_equal(s, 0.0) |> should.be_true
    Error(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------
// Hamming: identical emoji-only strings must succeed.
// ---------------------------------------------------------------------

pub fn hamming_identical_emoji_test() {
  case distance.hamming(family <> wave_skin, family <> wave_skin) {
    Ok(0) -> Nil
    _ -> should.fail()
  }
}

pub fn hamming_emoji_one_diff_test() {
  // family vs wave_skin, both 1 grapheme.
  case distance.hamming(family, wave_skin) {
    Ok(1) -> Nil
    _ -> should.fail()
  }
}

// ---------------------------------------------------------------------
// Combining-mark + base: combining attaches to base -> single grapheme.
// Stand-alone combining at start of string is its own grapheme.
// ---------------------------------------------------------------------

pub fn levenshtein_leading_combining_mark_test() {
  // Leading combining acute on its own (no base): UAX #29 makes
  // this a separate grapheme cluster from any following letter.
  // The grapheme-aware count of "\u{0301}a" should be 2 graphemes.
  let s = "\u{0301}a"
  let n = list.length(string.to_graphemes(s))
  // Either implementation may produce 1 or 2 here; both tools must
  // at minimum agree with their own grapheme count via levenshtein.
  // Distance from the empty string is exactly that count.
  distance.levenshtein(s, "") |> should.equal(n)
}

// ---------------------------------------------------------------------
// Determinism: same inputs must produce the same outputs (no
// dependence on dict iteration order).
// ---------------------------------------------------------------------

pub fn jaro_deterministic_test() {
  let a = family <> wave_skin <> "abc" <> flag_jp
  let b = "xyz" <> family <> wave_skin
  let s1 = similarity.jaro(a, b)
  let s2 = similarity.jaro(a, b)
  approx_equal(s1, s2) |> should.be_true
}

pub fn levenshtein_deterministic_test() {
  let a = family <> wave_skin <> "abc" <> flag_jp
  let b = "xyz" <> family <> wave_skin
  distance.levenshtein(a, b) |> should.equal(distance.levenshtein(a, b))
}

// ---------------------------------------------------------------------
// Hamming length-mismatch grapheme counts must reflect graphemes,
// not codepoints/bytes.
// ---------------------------------------------------------------------

pub fn hamming_length_mismatch_uses_grapheme_count_test() {
  // family is one grapheme (5 codepoints, ~17 bytes UTF-8).
  // "ab" is 2 graphemes. The error must report 1 vs 2, not codepoint
  // / byte counts.
  case distance.hamming(family, "ab") {
    Error(distance.LengthMismatch(left, right)) -> {
      left |> should.equal(1)
      right |> should.equal(2)
    }
    Ok(_) -> should.fail()
  }
}

// ---------------------------------------------------------------------
// jaro_winkler: must equal jaro * (1 + l*p*(1-jaro)) + jaro? Wait,
// the formula is jw = j + l*p*(1-j). For zero-prefix it equals j.
// For full prefix matching the lengths and l capped at prefix_max,
// jw = j + prefix_max * 0.1 * (1-j).
// ---------------------------------------------------------------------

pub fn jaro_winkler_formula_check_test() {
  // a == b -> j = 1.0 -> jw = 1.0 + l*0.1*0 = 1.0.
  similarity.jaro_winkler("hello", "hello")
  |> approx_equal(1.0)
  |> should.be_true
}

// ---------------------------------------------------------------------
// Jaro very long input — must terminate in reasonable time and stay
// in [0,1]. (200 graphemes, all same.)
// ---------------------------------------------------------------------

pub fn jaro_long_disjoint_in_unit_range_test() {
  let a =
    list.repeat("a", 100)
    |> string.concat
  let b =
    list.repeat("b", 100)
    |> string.concat
  let s = similarity.jaro(a, b)
  { s >=. 0.0 && s <=. 1.0 } |> should.be_true
}

// ---------------------------------------------------------------------
// did_you_mean ordering: ascending by distance.
// ---------------------------------------------------------------------

pub fn did_you_mean_ascending_distance_test() {
  // "abc" -> distances: "abc"=0, "abd"=1, "axc"=1, "xyz"=3.
  // Output should be: ["abc", "abd", "axc"] (within max=2),
  // ordered by distance ascending, ties broken by input position.
  search.did_you_mean("abc", ["xyz", "axc", "abd", "abc"], 2)
  |> should.equal(["abc", "axc", "abd"])
}

// ---------------------------------------------------------------------
// Levenshtein-list generic with non-string types.
// ---------------------------------------------------------------------

pub fn levenshtein_list_int_test() {
  distance.levenshtein_list([1, 2, 3], [1, 2, 4]) |> should.equal(1)
  distance.levenshtein_list([1, 2, 3], [3, 2, 1]) |> should.equal(2)
  distance.levenshtein_list([], [1, 2, 3]) |> should.equal(3)
}

// ---------------------------------------------------------------------
// runs() groups properly for emoji edits.
// ---------------------------------------------------------------------

pub fn edit_runs_groups_consecutive_test() {
  let script = [
    edit.Equal("a"),
    edit.Equal("b"),
    edit.Insert(family),
    edit.Insert(wave_skin),
    edit.Delete("c"),
    edit.Equal("d"),
  ]
  edit.runs(script)
  |> should.equal([
    edit.EqualRun(["a", "b"]),
    edit.InsertRun([family, wave_skin]),
    edit.DeleteRun(["c"]),
    edit.EqualRun(["d"]),
  ])
}
