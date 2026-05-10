//// Round 2 metamon-driven property tests.
////
//// Hammers textmetrics axioms with `string_unicode` plus explicit
//// emoji ZWJ / regional-indicator / combining-mark edge cases via
//// `with_examples`. Every property here corresponds to a published
//// invariant from spec §13.1 / §13.2 / §13.5.

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range
import textmetrics/distance
import textmetrics/lcs
import textmetrics/search
import textmetrics/similarity

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
    distance.levenshtein(a, b) >= 0
  })
}

pub fn levenshtein_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) { distance.levenshtein(a, a) == 0 })
}

pub fn levenshtein_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    distance.levenshtein(a, b) == distance.levenshtein(b, a)
  })
}

pub fn levenshtein_upper_bound_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let la = list.length(string.to_graphemes(a))
    let lb = list.length(string.to_graphemes(b))
    let bound = int.max(la, lb)
    distance.levenshtein(a, b) <= bound
  })
}

pub fn damerau_non_negative_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    distance.damerau_levenshtein(a, b) >= 0
  })
}

pub fn damerau_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    distance.damerau_levenshtein(a, a) == 0
  })
}

pub fn damerau_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    distance.damerau_levenshtein(a, b) == distance.damerau_levenshtein(b, a)
  })
}

pub fn osa_non_negative_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    distance.osa(a, b) >= 0
  })
}

pub fn osa_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) { distance.osa(a, a) == 0 })
}

pub fn osa_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    distance.osa(a, b) == distance.osa(b, a)
  })
}

// OSA bracketing: damerau <= osa <= levenshtein
pub fn osa_upper_bounded_by_levenshtein_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    distance.osa(a, b) <= distance.levenshtein(a, b)
  })
}

pub fn osa_lower_bounded_by_damerau_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    distance.osa(a, b) >= distance.damerau_levenshtein(a, b)
  })
}

// Triangle inequality: levenshtein and damerau (NOT osa). Bumped to
// 300 runs because failures here would point at deep bugs.
pub fn levenshtein_triangle_inequality_property_test() {
  let assert Ok(c) = metamon.with_runs(metamon.default_config(), 300)
  metamon.forall_with(c, unicode_triple_gen(), fn(t) {
    let #(a, b, c) = t
    let ac = distance.levenshtein(a, c)
    let ab = distance.levenshtein(a, b)
    let bc = distance.levenshtein(b, c)
    ac <= ab + bc
  })
}

pub fn damerau_triangle_inequality_property_test() {
  let assert Ok(c) = metamon.with_runs(metamon.default_config(), 300)
  metamon.forall_with(c, unicode_triple_gen(), fn(t) {
    let #(a, b, c) = t
    let ac = distance.damerau_levenshtein(a, c)
    let ab = distance.damerau_levenshtein(a, b)
    let bc = distance.damerau_levenshtein(b, c)
    ac <= ab + bc
  })
}

// Hamming: when length matches, Hamming >= Levenshtein.
pub fn hamming_geq_levenshtein_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case distance.hamming(a, b) {
      Ok(h) -> h >= distance.levenshtein(a, b)
      Error(_) -> True
      // skip mismatched lengths
    }
  })
}

pub fn hamming_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) { distance.hamming(a, a) == Ok(0) })
}

pub fn hamming_symmetry_property_test() {
  // When defined (equal grapheme lengths), hamming is symmetric.
  // The Error constructor LengthMismatch(left, right) is intentionally
  // asymmetric — it preserves which side had which length — so we
  // skip mismatched inputs.
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case distance.hamming(a, b), distance.hamming(b, a) {
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
    let s = distance.normalized_levenshtein(a, b)
    s >=. 0.0 && s <=. 1.0
  })
}

pub fn normalized_levenshtein_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    distance.normalized_levenshtein(a, a) == 1.0
  })
}

pub fn normalized_levenshtein_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let l = distance.normalized_levenshtein(a, b)
    let r = distance.normalized_levenshtein(b, a)
    float.absolute_value(l -. r) <=. 1.0e-12
  })
}

// ---------------------------------------------------------------------
// Similarity: Jaro / Jaro-Winkler / Sørensen-Dice
// ---------------------------------------------------------------------

pub fn jaro_in_range_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let s = similarity.jaro(a, b)
    s >=. 0.0 && s <=. 1.0
  })
}

pub fn jaro_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) { similarity.jaro(a, a) == 1.0 })
}

pub fn jaro_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let l = similarity.jaro(a, b)
    let r = similarity.jaro(b, a)
    float.absolute_value(l -. r) <=. 1.0e-12
  })
}

pub fn jaro_winkler_in_range_property_test() {
  // 300 runs — the cap-at-1.0 behaviour with long shared prefixes is
  // a known bug class in JW implementations, worth pushing on.
  let assert Ok(c) = metamon.with_runs(metamon.default_config(), 300)
  metamon.forall_with(c, unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let s = similarity.jaro_winkler(a, b)
    s >=. 0.0 && s <=. 1.0
  })
}

pub fn jaro_winkler_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    similarity.jaro_winkler(a, a) == 1.0
  })
}

pub fn jaro_winkler_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let l = similarity.jaro_winkler(a, b)
    let r = similarity.jaro_winkler(b, a)
    float.absolute_value(l -. r) <=. 1.0e-12
  })
}

pub fn jaro_winkler_floor_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let j = similarity.jaro(a, b)
    let jw = similarity.jaro_winkler(a, b)
    jw +. 1.0e-12 >=. j
  })
}

pub fn sorensen_dice_in_range_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case similarity.sorensen_dice(a, b, 2) {
      Ok(s) -> s >=. 0.0 && s <=. 1.0
      Error(_) -> False
    }
  })
}

pub fn sorensen_dice_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    case similarity.sorensen_dice(a, a, 2) {
      Ok(s) -> s == 1.0
      Error(_) -> False
    }
  })
}

pub fn sorensen_dice_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case similarity.sorensen_dice(a, b, 2), similarity.sorensen_dice(b, a, 2) {
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
    let l = lcs.length(ga, gb)
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
    lcs.length(ga, gb) == lcs.length(gb, ga)
  })
}

pub fn lcs_sequence_length_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    list.length(lcs.sequence(ga, gb)) == lcs.length(ga, gb)
  })
}

pub fn lcs_sequence_is_subsequence_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    let seq = lcs.sequence(ga, gb)
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
    let result = search.did_you_mean(query, candidates, max_d)
    let dists = list.map(result, fn(c) { distance.levenshtein(query, c) })
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
    let result = search.did_you_mean(query, candidates, max_d)
    list.all(result, fn(c) { distance.levenshtein(query, c) <= max_d })
  })
}

pub fn closest_equals_did_you_mean_head_property_test() {
  metamon.forall(search_input_gen(), fn(t) {
    let #(query, candidates, max_d) = t
    case search.did_you_mean(query, candidates, max_d) {
      [] ->
        case search.closest(query, candidates, max_d) {
          Error(Nil) -> True
          Ok(_) -> False
        }
      [head, ..] ->
        case search.closest(query, candidates, max_d) {
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
    let result = search.rank_jaro_winkler(query, candidates, top_n)
    let scores = list.map(result, fn(r: search.Ranked) { r.score })
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
    let result = search.rank_jaro_winkler(query, candidates, top_n)
    let n = case top_n < 0 {
      True -> 0
      False -> top_n
    }
    list.length(result) <= n && list.length(result) <= list.length(candidates)
  })
}
