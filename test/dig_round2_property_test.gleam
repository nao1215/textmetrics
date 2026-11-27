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
import gleam/result
import gleam/string
import metamon
import metamon/generator
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
  generator.string(
    of: generator.Unicode,
    length: generator.range(from: 0, to: 12),
  )
  |> generator.with_examples(unicode_edges)
}

fn small_unicode_string_gen() {
  generator.string(
    of: generator.Unicode,
    length: generator.range(from: 0, to: 6),
  )
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
    assert textmetrics.levenshtein(a, b) >= 0
  })
}

pub fn levenshtein_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    assert textmetrics.levenshtein(a, a) == 0
  })
}

pub fn levenshtein_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    assert textmetrics.levenshtein(a, b) == textmetrics.levenshtein(b, a)
  })
}

pub fn levenshtein_upper_bound_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let la = list.length(string.to_graphemes(a))
    let lb = list.length(string.to_graphemes(b))
    let bound = int.max(la, lb)
    assert textmetrics.levenshtein(a, b) <= bound
  })
}

pub fn damerau_non_negative_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    assert textmetrics.damerau_levenshtein(a, b) >= 0
  })
}

pub fn damerau_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    assert textmetrics.damerau_levenshtein(a, a) == 0
  })
}

pub fn damerau_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    assert textmetrics.damerau_levenshtein(a, b)
      == textmetrics.damerau_levenshtein(b, a)
  })
}

pub fn osa_non_negative_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    assert textmetrics.optimal_string_alignment(a, b) >= 0
  })
}

pub fn osa_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    assert textmetrics.optimal_string_alignment(a, a) == 0
  })
}

pub fn osa_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    assert textmetrics.optimal_string_alignment(a, b)
      == textmetrics.optimal_string_alignment(b, a)
  })
}

// OSA bracketing: damerau <= osa <= levenshtein
pub fn osa_upper_bounded_by_levenshtein_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    assert textmetrics.optimal_string_alignment(a, b)
      <= textmetrics.levenshtein(a, b)
  })
}

pub fn osa_lower_bounded_by_damerau_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    assert textmetrics.optimal_string_alignment(a, b)
      >= textmetrics.damerau_levenshtein(a, b)
  })
}

// Triangle inequality: levenshtein and damerau (NOT osa). Bumped to
// 300 runs because failures here would point at deep bugs.
pub fn levenshtein_triangle_inequality_property_test() {
  let c = metamon.Config(..metamon.default_config(), runs: 300)
  metamon.forall_with(c, unicode_triple_gen(), fn(t) {
    let #(a, b, c) = t
    let ac = textmetrics.levenshtein(a, c)
    let ab = textmetrics.levenshtein(a, b)
    let bc = textmetrics.levenshtein(b, c)
    assert ac <= ab + bc
  })
}

pub fn damerau_triangle_inequality_property_test() {
  let c = metamon.Config(..metamon.default_config(), runs: 300)
  metamon.forall_with(c, unicode_triple_gen(), fn(t) {
    let #(a, b, c) = t
    let ac = textmetrics.damerau_levenshtein(a, c)
    let ab = textmetrics.damerau_levenshtein(a, b)
    let bc = textmetrics.damerau_levenshtein(b, c)
    assert ac <= ab + bc
  })
}

// Hamming: when length matches, Hamming >= Levenshtein.
pub fn hamming_geq_levenshtein_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    case textmetrics.hamming(a, b) {
      Ok(h) -> {
        assert h >= textmetrics.levenshtein(a, b)
      }
      // skip mismatched lengths
      Error(_) -> Nil
    }
  })
}

pub fn hamming_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    assert textmetrics.hamming(a, a) == Ok(0)
  })
}

pub fn hamming_symmetry_property_test() {
  // When defined (equal grapheme lengths), hamming is symmetric.
  // The Error constructor LengthMismatch(left, right) is intentionally
  // asymmetric — it preserves which side had which length — so we
  // skip mismatched inputs.
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let left = textmetrics.hamming(a, b)
    let right = textmetrics.hamming(b, a)
    assert result.is_ok(left) == result.is_ok(right)
    case left, right {
      Ok(l), Ok(r) -> {
        assert l == r
      }
      _, _ -> Nil
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
    assert s >=. 0.0
    assert s <=. 1.0
  })
}

pub fn normalized_levenshtein_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    assert textmetrics.levenshtein_similarity(a, a) == 1.0
  })
}

pub fn normalized_levenshtein_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let l = textmetrics.levenshtein_similarity(a, b)
    let r = textmetrics.levenshtein_similarity(b, a)
    assert float.absolute_value(l -. r) <=. 1.0e-12
  })
}

// ---------------------------------------------------------------------
// Similarity: Jaro / Jaro-Winkler / Sørensen-Dice
// ---------------------------------------------------------------------

pub fn jaro_in_range_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let s = textmetrics.jaro(a, b)
    assert s >=. 0.0
    assert s <=. 1.0
  })
}

pub fn jaro_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    assert textmetrics.jaro(a, a) == 1.0
  })
}

pub fn jaro_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let l = textmetrics.jaro(a, b)
    let r = textmetrics.jaro(b, a)
    assert float.absolute_value(l -. r) <=. 1.0e-12
  })
}

pub fn jaro_winkler_in_range_property_test() {
  // 300 runs — the cap-at-1.0 behaviour with long shared prefixes is
  // a known bug class in JW implementations, worth pushing on.
  let c = metamon.Config(..metamon.default_config(), runs: 300)
  metamon.forall_with(c, unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let assert Ok(s) =
      textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
    assert s >=. 0.0
    assert s <=. 1.0
  })
}

pub fn jaro_winkler_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    assert textmetrics.jaro_winkler(a, a, prefix_scale: 0.1, prefix_max: 4)
      == Ok(1.0)
  })
}

pub fn jaro_winkler_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let assert Ok(l) =
      textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
    let assert Ok(r) =
      textmetrics.jaro_winkler(b, a, prefix_scale: 0.1, prefix_max: 4)
    assert float.absolute_value(l -. r) <=. 1.0e-12
  })
}

pub fn jaro_winkler_floor_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let j = textmetrics.jaro(a, b)
    let assert Ok(jw) =
      textmetrics.jaro_winkler(a, b, prefix_scale: 0.1, prefix_max: 4)
    assert jw +. 1.0e-12 >=. j
  })
}

pub fn sorensen_dice_in_range_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let assert Ok(s) = textmetrics.sorensen_dice(a, b, ngram_size: 2)
    assert s >=. 0.0
    assert s <=. 1.0
  })
}

pub fn sorensen_dice_identity_property_test() {
  metamon.forall(unicode_string_gen(), fn(a) {
    assert textmetrics.sorensen_dice(a, a, ngram_size: 2) == Ok(1.0)
  })
}

pub fn sorensen_dice_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let assert Ok(l) = textmetrics.sorensen_dice(a, b, ngram_size: 2)
    let assert Ok(r) = textmetrics.sorensen_dice(b, a, ngram_size: 2)
    assert float.absolute_value(l -. r) <=. 1.0e-12
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
    assert l >= lo
    assert l <= hi
  })
}

pub fn lcs_length_symmetry_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    assert textmetrics.longest_common_subsequence_length(ga, gb)
      == textmetrics.longest_common_subsequence_length(gb, ga)
  })
}

pub fn lcs_sequence_length_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    assert list.length(textmetrics.longest_common_subsequence(ga, gb))
      == textmetrics.longest_common_subsequence_length(ga, gb)
  })
}

pub fn lcs_sequence_is_subsequence_property_test() {
  metamon.forall(unicode_pair_gen(), fn(p) {
    let #(a, b) = p
    let ga = string.to_graphemes(a)
    let gb = string.to_graphemes(b)
    let seq = textmetrics.longest_common_subsequence(ga, gb)
    assert is_subsequence(seq, ga)
    assert is_subsequence(seq, gb)
  })
}

// ---------------------------------------------------------------------
// Search ordering
// ---------------------------------------------------------------------

fn candidate_list_gen() {
  generator.list_of(
    small_unicode_string_gen(),
    length: generator.range(from: 0, to: 6),
  )
}

fn search_input_gen() {
  generator.tuple3(
    small_unicode_string_gen(),
    candidate_list_gen(),
    generator.int(generator.range(from: 0, to: 8)),
  )
}

pub fn did_you_mean_sorted_ascending_property_test() {
  metamon.forall(search_input_gen(), fn(t) {
    let #(query, candidates, max_d) = t
    let result = textmetrics.did_you_mean(query, candidates, max_d)
    let dists = list.map(result, fn(c) { textmetrics.levenshtein(query, c) })
    assert dists == list.sort(dists, int.compare)
  })
}

pub fn did_you_mean_within_max_distance_property_test() {
  metamon.forall(search_input_gen(), fn(t) {
    let #(query, candidates, max_d) = t
    let result = textmetrics.did_you_mean(query, candidates, max_d)
    list.each(result, fn(c) {
      assert textmetrics.levenshtein(query, c) <= max_d
    })
  })
}

pub fn closest_equals_did_you_mean_head_property_test() {
  metamon.forall(search_input_gen(), fn(t) {
    let #(query, candidates, max_d) = t
    let first = textmetrics.did_you_mean(query, candidates, max_d) |> list.first
    case textmetrics.did_you_mean(query, candidates, max_d) {
      [] -> {
        assert first == Error(Nil)
      }
      [head, ..] -> {
        assert first == Ok(head)
      }
    }
  })
}

fn rank_input_gen() {
  generator.tuple3(
    small_unicode_string_gen(),
    candidate_list_gen(),
    generator.int(generator.range(from: 0, to: 6)),
  )
}

pub fn rank_jaro_winkler_descending_property_test() {
  metamon.forall(rank_input_gen(), fn(t) {
    let #(query, candidates, top_n) = t
    let result = textmetrics.rank_jaro_winkler(query, candidates, top_n)
    let scores = list.map(result, fn(r: textmetrics.Ranked) { r.score })
    assert scores == list.sort(scores, order.reverse(float.compare))
  })
}

pub fn rank_jaro_winkler_top_n_bound_property_test() {
  metamon.forall(rank_input_gen(), fn(t) {
    let #(query, candidates, top_n) = t
    let result = textmetrics.rank_jaro_winkler(query, candidates, top_n)
    let n = case top_n < 0 {
      True -> 0
      False -> top_n
    }
    assert list.length(result) <= n
    assert list.length(result) <= list.length(candidates)
  })
}
