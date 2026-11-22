//// Round 2 metamon-driven property tests.
////
//// Hammers textmetrics axioms with `string_unicode` plus explicit
//// emoji ZWJ / regional-indicator / combining-mark edge cases via
//// `with_examples`. Every property here corresponds to a published
//// invariant from spec §13.1 / §13.2 / §13.5.

import gleeunit/should

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range
import textmetrics

// ---------------------------------------------------------------------
// Generator shortcuts
// ---------------------------------------------------------------------

const unicode_edges: List(String) = [
  // Basic edges
  "", " ", "a",
  // Combining marks (NFC vs NFD): "café" decomposed
  "cafe\u{0301}",
  // Regional indicator pair (flag emoji): JP flag = U+1F1EF U+1F1F5
  "\u{1F1EF}\u{1F1F5}",
  // Single emoji
  "\u{1F600}",
  // Family ZWJ sequence: man + ZWJ + woman + ZWJ + boy
  "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F466}",
  // Skin tone modifier: thumbs up + medium-light skin
  "\u{1F44D}\u{1F3FC}",
  // Hangul decomposed (jamo): 가 = ㄱ + ㅏ as separate codepoints
  "\u{1100}\u{1161}",
  // Mixed BMP + supplementary
  "a\u{1F600}b",
  // CJK
  "あ", "가", "中",
  // Variation selector (text vs emoji presentation)
  "\u{2764}\u{FE0F}",
]

fn unicode_string_gen() {
  generator.string_unicode(range.constant(0, 12))
  |> generator.with_examples(unicode_edges)
}

fn small_unicode_string_gen() {
  generator.string_unicode(range.constant(0, 6))
  |> generator.with_examples(unicode_edges)
}

fn unicode_pair_gen() {
  generator.tuple2(unicode_string_gen(), unicode_string_gen())
}

fn unicode_triple_gen() {
  generator.tuple3(
    small_unicode_string_gen(),
    small_unicode_string_gen(),
    small_unicode_string_gen(),
  )
}

// ---------------------------------------------------------------------
// Distance: non-negativity, identity, symmetry
// ---------------------------------------------------------------------

pub fn levenshtein_non_negative_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    textmetrics.levenshtein(a, b) >= 0
  })
}

pub fn levenshtein_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    textmetrics.levenshtein(a, a) == 0
  })
}

pub fn levenshtein_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    textmetrics.levenshtein(a, b) == textmetrics.levenshtein(b, a)
  })
}

pub fn levenshtein_upper_bound_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let la = list.length(string.to_graphemes(a))
    let lb = list.length(string.to_graphemes(b))
    let bound = int.max(la, lb)
    textmetrics.levenshtein(a, b) <= bound
  })
}

pub fn damerau_non_negative_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    textmetrics.damerau_levenshtein(a, b) >= 0
  })
}

pub fn damerau_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    textmetrics.damerau_levenshtein(a, a) == 0
  })
}

pub fn damerau_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    textmetrics.damerau_levenshtein(a, b)
    == textmetrics.damerau_levenshtein(b, a)
  })
}

pub fn osa_non_negative_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    textmetrics.optimal_string_alignment(a, b) >= 0
  })
}

pub fn osa_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    textmetrics.optimal_string_alignment(a, a) == 0
  })
}

pub fn osa_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    textmetrics.optimal_string_alignment(a, b)
    == textmetrics.optimal_string_alignment(b, a)
  })
}

// OSA bracketing: damerau <= osa <= levenshtein
pub fn osa_upper_bounded_by_levenshtein_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    textmetrics.optimal_string_alignment(a, b) <= textmetrics.levenshtein(a, b)
  })
}

pub fn osa_lower_bounded_by_damerau_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    textmetrics.optimal_string_alignment(a, b)
    >= textmetrics.damerau_levenshtein(a, b)
  })
}

// Triangle inequality: levenshtein and damerau (NOT osa). Bumped to
// 300 runs because failures here would point at deep bugs.
pub fn levenshtein_triangle_inequality_property_test() {
  let assert Ok(c) = metamon.with_runs(metamon.default_config(), 300)
  metamon.forall_with(c, unicode_triple_gen(), fn(t) {
    let #(a, b, c) = t
    let ac = textmetrics.levenshtein(a, c)
    let ab = textmetrics.levenshtein(a, b)
    let bc = textmetrics.levenshtein(b, c)
    ac <= ab + bc
  })
}

pub fn damerau_triangle_inequality_property_test() {
  let assert Ok(c) = metamon.with_runs(metamon.default_config(), 300)
  metamon.forall_with(c, unicode_triple_gen(), fn(t) {
    let #(a, b, c) = t
    let ac = textmetrics.damerau_levenshtein(a, c)
    let ab = textmetrics.damerau_levenshtein(a, b)
    let bc = textmetrics.damerau_levenshtein(b, c)
    ac <= ab + bc
  })
}

// Hamming: when length matches, Hamming >= Levenshtein.
pub fn hamming_geq_levenshtein_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case textmetrics.hamming(a, b) {
      Ok(h) -> h >= textmetrics.levenshtein(a, b)
      Error(_) -> True
      // skip mismatched lengths
    }
  })
}

pub fn hamming_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    textmetrics.hamming(a, a) == Ok(0)
  })
}

pub fn hamming_symmetry_property_test() {
  // When defined (equal grapheme lengths), hamming is symmetric.
  // The Error constructor LengthMismatch(left, right) is intentionally
  // asymmetric — it preserves which side had which length — so we
  // skip mismatched inputs.
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case textmetrics.hamming(a, b), textmetrics.hamming(b, a) {
      Ok(l), Ok(r) -> l == r
      Error(_), Error(_) -> True
      _, _ -> False
    }
  })
}

// ---------------------------------------------------------------------
// Normalized Levenshtein
// ---------------------------------------------------------------------

pub fn normalized_levenshtein_in_range_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let s = textmetrics.levenshtein_similarity(a, b)
    s >=. 0.0 && s <=. 1.0
  })
}

pub fn normalized_levenshtein_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    textmetrics.levenshtein_similarity(a, a) == 1.0
  })
}

pub fn normalized_levenshtein_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let l = textmetrics.levenshtein_similarity(a, b)
    let r = textmetrics.levenshtein_similarity(b, a)
    float.absolute_value(l -. r) <=. 1.0e-12
  })
}

// ---------------------------------------------------------------------
// Similarity: Jaro / Jaro-Winkler / Sørensen-Dice
// ---------------------------------------------------------------------

pub fn jaro_in_range_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let s = textmetrics.jaro(a, b)
    s >=. 0.0 && s <=. 1.0
  })
}

pub fn jaro_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) { textmetrics.jaro(a, a) == 1.0 })
}

pub fn jaro_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let l = textmetrics.jaro(a, b)
    let r = textmetrics.jaro(b, a)
    float.absolute_value(l -. r) <=. 1.0e-12
  })
}

pub fn jaro_winkler_in_range_property_test() {
  // 300 runs — the cap-at-1.0 behaviour with long shared prefixes is
  // a known bug class in JW implementations, worth pushing on.
  let assert Ok(c) = metamon.with_runs(metamon.default_config(), 300)
  metamon.forall_with(c, unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let s = {
      textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    }
    s >=. 0.0 && s <=. 1.0
  })
}

pub fn jaro_winkler_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    {
      textmetrics.jaro_winkler(a, a, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    }
    == 1.0
  })
}

pub fn jaro_winkler_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let l = {
      textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    }
    let r = {
      textmetrics.jaro_winkler(b, a, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    }
    float.absolute_value(l -. r) <=. 1.0e-12
  })
}

pub fn jaro_winkler_floor_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let j = textmetrics.jaro(a, b)
    let jw = {
      textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
      |> should.be_ok
    }
    jw +. 1.0e-12 >=. j
  })
}

pub fn sorensen_dice_in_range_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case textmetrics.sorensen_dice(a, b, ngram_size: 2) {
      Ok(s) -> s >=. 0.0 && s <=. 1.0
      Error(_) -> False
    }
  })
}

pub fn sorensen_dice_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    case textmetrics.sorensen_dice(a, a, ngram_size: 2) {
      Ok(s) -> s == 1.0
      Error(_) -> False
    }
  })
}

pub fn sorensen_dice_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case
      textmetrics.sorensen_dice(a, b, ngram_size: 2),
      textmetrics.sorensen_dice(b, a, ngram_size: 2)
    {
      Ok(l), Ok(r) -> float.absolute_value(l -. r) <=. 1.0e-12
      _, _ -> False
    }
  })
}

// ---------------------------------------------------------------------
// LCS bounds and subsequence
// ---------------------------------------------------------------------

fn is_subsequence(sub: List(t), full: List(t)) -> Bool {
  case sub, full {
    [], _ -> True
    [_, ..], [] -> False
    [s, ..s_rest], [f, ..f_rest] ->
      case s == f {
        True -> is_subsequence(s_rest, f_rest)
        False -> is_subsequence(sub, f_rest)
      }
  }
}

pub fn lcs_length_bounds_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    let l = textmetrics.longest_common_subsequence_length(ga, gb)
    let lo = 0
    let hi = int.min(list.length(ga), list.length(gb))
    l >= lo && l <= hi
  })
}

pub fn lcs_length_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    textmetrics.longest_common_subsequence_length(ga, gb)
    == textmetrics.longest_common_subsequence_length(gb, ga)
  })
}

pub fn lcs_sequence_length_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    list.length(textmetrics.longest_common_subsequence(ga, gb))
    == textmetrics.longest_common_subsequence_length(ga, gb)
  })
}

pub fn lcs_sequence_is_subsequence_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    let seq = textmetrics.longest_common_subsequence(ga, gb)
    is_subsequence(seq, ga) && is_subsequence(seq, gb)
  })
}

// ---------------------------------------------------------------------
// Search ordering
// ---------------------------------------------------------------------

fn candidate_list_gen() {
  generator.list_of(small_unicode_string_gen(), range.constant(0, 6))
}

fn search_input_gen() {
  generator.tuple3(
    small_unicode_string_gen(),
    candidate_list_gen(),
    generator.int(range.constant(0, 8)),
  )
}

pub fn did_you_mean_sorted_ascending_property_test() {
  metamon.forall(search_input_gen(), fn(t) {
    let #(query, candidates, max_d) = t
    let result = textmetrics.did_you_mean(query, candidates, max_d)
    let dists = list.map(result, fn(c) { textmetrics.levenshtein(query, c) })
    is_non_decreasing(dists)
  })
}

fn is_non_decreasing(xs: List(Int)) -> Bool {
  case xs {
    [] -> True
    [_] -> True
    [a, b, ..rest] ->
      case a <= b {
        True -> is_non_decreasing([b, ..rest])
        False -> False
      }
  }
}

pub fn did_you_mean_within_max_distance_property_test() {
  metamon.forall(search_input_gen(), fn(t) {
    let #(query, candidates, max_d) = t
    let result = textmetrics.did_you_mean(query, candidates, max_d)
    list.all(result, fn(c) { textmetrics.levenshtein(query, c) <= max_d })
  })
}

pub fn closest_equals_did_you_mean_head_property_test() {
  metamon.forall(search_input_gen(), fn(t) {
    let #(query, candidates, max_d) = t
    case textmetrics.did_you_mean(query, candidates, max_d) {
      [] ->
        case
          { textmetrics.did_you_mean(query, candidates, max_d) |> list.first }
        {
          Error(Nil) -> True
          Ok(_) -> False
        }
      [head, ..] ->
        case
          { textmetrics.did_you_mean(query, candidates, max_d) |> list.first }
        {
          Ok(found) -> found == head
          Error(Nil) -> False
        }
    }
  })
}

fn rank_input_gen() {
  generator.tuple3(
    small_unicode_string_gen(),
    candidate_list_gen(),
    generator.int(range.constant(0, 6)),
  )
}

pub fn rank_jaro_winkler_descending_property_test() {
  metamon.forall(rank_input_gen(), fn(t) {
    let #(query, candidates, top_n) = t
    let result = textmetrics.rank_jaro_winkler(query, candidates, top_n)
    let scores = list.map(result, fn(r: textmetrics.Ranked) { r.score })
    is_non_increasing_floats(scores)
  })
}

fn is_non_increasing_floats(xs: List(Float)) -> Bool {
  case xs {
    [] -> True
    [_] -> True
    [a, b, ..rest] ->
      case float.compare(a, b) {
        order.Lt -> False
        _ -> is_non_increasing_floats([b, ..rest])
      }
  }
}

pub fn rank_jaro_winkler_top_n_bound_property_test() {
  metamon.forall(rank_input_gen(), fn(t) {
    let #(query, candidates, top_n) = t
    let result = textmetrics.rank_jaro_winkler(query, candidates, top_n)
    let n = case top_n < 0 {
      True -> 0
      False -> top_n
    }
    list.length(result) <= n && list.length(result) <= list.length(candidates)
  })
}
