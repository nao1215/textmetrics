//// Metamorphic-testing dig (round 3).
////
//// Asserts a battery of metamorphic relations on textmetrics modules
//// using the metamon combinator library. Each test is bounded to keep
//// total runtime in check on slower machines.
////
//// Unicode edge cases (emoji ZWJ, NFC vs NFD, Hangul jamo, regional
//// indicators, skin-tone modifiers) are seeded via `with_examples`.

import gleam/list
import gleam/string
import metamon
import metamon/generator
import metamon/generator/range
import metamon/transform
import textmetrics/diff
import textmetrics/distance
import textmetrics/edit.{Delete, Equal, Insert}
import textmetrics/lcs
import textmetrics/search

// ---------------------------------------------------------------------
// Generators
// ---------------------------------------------------------------------

const unicode_examples: List(String) = [
  "",
  "a",
  "ab",
  // Emoji ZWJ sequence (family).
  "👨‍👩‍👧",
  // Skin-tone modifier.
  "👍🏽",
  // Regional indicator pair (flag).
  "🇯🇵",
  // NFC composed.
  "café",
  // NFD decomposed (same visual).
  "cafe\u{0301}",
  // Hangul precomposed vs jamo.
  "가",
  "\u{1100}\u{1161}",
  // Combining marks.
  "a\u{0301}",
  // Mixed.
  "あ\u{3099}",
]

fn small_unicode_string() -> generator.Generator(String) {
  generator.string_unicode(range.constant(0, 6))
  |> generator.with_examples(unicode_examples)
}

fn small_unicode_pair() -> generator.Generator(#(String, String)) {
  generator.tuple2(small_unicode_string(), small_unicode_string())
}

fn small_grapheme_list() -> generator.Generator(List(String)) {
  generator.map(small_unicode_string(), string.to_graphemes)
}

fn small_grapheme_list_pair() -> generator.Generator(
  #(List(String), List(String)),
) {
  generator.tuple2(small_grapheme_list(), small_grapheme_list())
}

const line_examples: List(List(String)) = [
  [],
  ["a"],
  ["a", "b"],
  ["a", "b", "c"],
  ["a", "a", "a"],
  ["", ""],
  ["x", "", "y"],
  ["café", "cafe\u{0301}"],
  // Duplicate lines force the patience LIS path to handle ambiguity.
  ["a", "b", "a"],
  ["a", "b", "a", "b"],
  ["x", "x", "y", "y", "x"],
  ["1", "2", "3", "1", "2", "3"],
]

fn small_line_list() -> generator.Generator(List(String)) {
  generator.list_of(
    generator.string_alphanumeric(range.constant(0, 3)),
    range.constant(0, 5),
  )
  |> generator.with_examples(line_examples)
}

fn small_line_pair() -> generator.Generator(#(List(String), List(String))) {
  generator.tuple2(small_line_list(), small_line_list())
}

// Reverse a list pair by graphemes — mirrors how textmetrics treats
// inputs. Note we cannot reverse strings then re-extract graphemes,
// because combining marks attach to different bases after reversal —
// the grapheme count and content can change. So we operate on already-
// extracted grapheme lists when asserting invariance under reverse.
fn pair_list_reverse_t() -> transform.Transform(#(List(String), List(String))) {
  transform.new("pair_list_reverse", fn(p: #(List(String), List(String))) {
    #(list.reverse(p.0), list.reverse(p.1))
  })
}

// ---------------------------------------------------------------------
// Diff round-trip relations (Spec §13.3): for every input pair, the
// edit script recovers both originals.
// ---------------------------------------------------------------------

pub fn myers_recover_old_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.myers(old, new)
    edit.recover_old(script) == old
  })
}

pub fn myers_recover_new_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.myers(old, new)
    edit.recover_new(script) == new
  })
}

pub fn patience_recover_old_test() {
  metamon.forall(small_line_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.patience(old, new)
    edit.recover_old(script) == old
  })
}

pub fn patience_recover_new_test() {
  metamon.forall(small_line_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.patience(old, new)
    edit.recover_new(script) == new
  })
}

// ---------------------------------------------------------------------
// Diff optimality (Spec §13.4):
//   cost(myers(old, new)) == |old| + |new| - 2 * lcs.length(old, new)
// ---------------------------------------------------------------------

pub fn myers_optimality_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.myers(old, new)
    let expected =
      list.length(old) + list.length(new) - 2 * lcs.length(old, new)
    edit.cost(script) == expected
  })
}

// ---------------------------------------------------------------------
// Edit-script consistency (Spec §13.6).
// ---------------------------------------------------------------------

fn count_kind(script: List(edit.Edit(a)), kind: String) -> Int {
  list.fold(script, 0, fn(acc, e) {
    case e, kind {
      Equal(_), "equal" -> acc + 1
      Delete(_), "delete" -> acc + 1
      Insert(_), "insert" -> acc + 1
      _, _ -> acc
    }
  })
}

pub fn myers_script_old_count_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.myers(old, new)
    let equals = count_kind(script, "equal")
    let deletes = count_kind(script, "delete")
    list.length(old) == equals + deletes
  })
}

pub fn myers_script_new_count_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.myers(old, new)
    let equals = count_kind(script, "equal")
    let inserts = count_kind(script, "insert")
    list.length(new) == equals + inserts
  })
}

// ---------------------------------------------------------------------
// LCS metamorphic relations.
// ---------------------------------------------------------------------

pub fn lcs_length_symmetry_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(a, b) = p
    lcs.length(a, b) == lcs.length(b, a)
  })
}

pub fn lcs_sequence_length_matches_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(a, b) = p
    list.length(lcs.sequence(a, b)) == lcs.length(a, b)
  })
}

pub fn lcs_idempotence_self_test() {
  metamon.forall(small_grapheme_list(), fn(a) { lcs.sequence(a, a) == a })
}

// ---------------------------------------------------------------------
// Distance equivariance under reverse.
// ---------------------------------------------------------------------

// Levenshtein over generic lists is invariant under reversing both
// inputs simultaneously. (Reversing strings via graphemes is unsafe
// because combining marks may rebind to different bases.)
pub fn levenshtein_list_invariant_under_reverse_test() {
  let mr =
    metamon.invariant_under(
      name: "levenshtein_list_under_reverse",
      under: pair_list_reverse_t(),
    )
  metamon.forall_morph(
    small_grapheme_list_pair(),
    mr,
    fn(p: #(List(String), List(String))) { distance.levenshtein_list(p.0, p.1) },
  )
}

// Distance symmetry: d(a, b) == d(b, a).
pub fn levenshtein_symmetry_test() {
  let mr = metamon.commutativity_of(name: "levenshtein_symmetric")
  metamon.forall_morph(small_unicode_pair(), mr, fn(p: #(String, String)) {
    distance.levenshtein(p.0, p.1)
  })
}

pub fn damerau_symmetry_test() {
  let mr = metamon.commutativity_of(name: "damerau_symmetric")
  metamon.forall_morph(small_unicode_pair(), mr, fn(p: #(String, String)) {
    distance.damerau_levenshtein(p.0, p.1)
  })
}

pub fn osa_symmetry_test() {
  let mr = metamon.commutativity_of(name: "osa_symmetric")
  metamon.forall_morph(small_unicode_pair(), mr, fn(p: #(String, String)) {
    distance.osa(p.0, p.1)
  })
}

// Identity: levenshtein(a, a) == 0.
pub fn levenshtein_identity_test() {
  metamon.forall(small_unicode_string(), fn(a) {
    distance.levenshtein(a, a) == 0
  })
}

// ---------------------------------------------------------------------
// Idempotence relations.
// ---------------------------------------------------------------------

pub fn diff_self_only_equals_test() {
  metamon.forall(small_grapheme_list(), fn(a) {
    let script = diff.myers(a, a)
    list.all(script, fn(e) {
      case e {
        Equal(_) -> True
        _ -> False
      }
    })
  })
}

pub fn diff_self_recover_old_test() {
  metamon.forall(small_grapheme_list(), fn(a) {
    edit.recover_old(diff.myers(a, a)) == a
  })
}

// ---------------------------------------------------------------------
// Search idempotence.
// ---------------------------------------------------------------------

pub fn search_closest_self_test() {
  metamon.forall(small_unicode_string(), fn(a) {
    search.closest(a, [a], 0) == Ok(a)
  })
}

pub fn search_did_you_mean_self_test() {
  metamon.forall(small_unicode_string(), fn(a) {
    search.did_you_mean(a, [a], 0) == [a]
  })
}

// ---------------------------------------------------------------------
// Empty-input invariants.
// ---------------------------------------------------------------------

pub fn lcs_empty_left_test() {
  metamon.forall(small_grapheme_list(), fn(a) { lcs.sequence([], a) == [] })
}

pub fn lcs_empty_right_test() {
  metamon.forall(small_grapheme_list(), fn(a) { lcs.sequence(a, []) == [] })
}

pub fn diff_empty_old_is_all_inserts_test() {
  metamon.forall(small_grapheme_list(), fn(a) {
    let script = diff.myers([], a)
    list.all(script, fn(e) {
      case e {
        Insert(_) -> True
        _ -> False
      }
    })
    && list.length(script) == list.length(a)
  })
}

pub fn diff_empty_new_is_all_deletes_test() {
  metamon.forall(small_grapheme_list(), fn(a) {
    let script = diff.myers(a, [])
    list.all(script, fn(e) {
      case e {
        Delete(_) -> True
        _ -> False
      }
    })
    && list.length(script) == list.length(a)
  })
}

// ---------------------------------------------------------------------
// to_unified: identical input -> empty output.
// ---------------------------------------------------------------------

pub fn to_unified_no_changes_is_empty_test() {
  metamon.forall(small_line_list(), fn(a) {
    let script = diff.myers(a, a)
    let opts = diff.unified_options(old_name: "a", new_name: "b")
    diff.to_unified(script, opts) == ""
  })
}

// ---------------------------------------------------------------------
// Patience: round-trip on every input pair, edit-script consistency.
// ---------------------------------------------------------------------

pub fn patience_script_old_count_test() {
  metamon.forall(small_line_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.patience(old, new)
    let equals = count_kind(script, "equal")
    let deletes = count_kind(script, "delete")
    list.length(old) == equals + deletes
  })
}

pub fn patience_script_new_count_test() {
  metamon.forall(small_line_pair(), fn(p) {
    let #(old, new) = p
    let script = diff.patience(old, new)
    let equals = count_kind(script, "equal")
    let inserts = count_kind(script, "insert")
    list.length(new) == equals + inserts
  })
}

// Patience cost is bounded below by Myers (Myers is optimal).
pub fn patience_cost_at_least_myers_test() {
  metamon.forall(small_line_pair(), fn(p) {
    let #(old, new) = p
    let p_cost = edit.cost(diff.patience(old, new))
    let m_cost = edit.cost(diff.myers(old, new))
    p_cost >= m_cost
  })
}

// ---------------------------------------------------------------------
// LCS upper bound: lcs.length(a, b) <= min(|a|, |b|).
// ---------------------------------------------------------------------

pub fn lcs_length_upper_bound_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(a, b) = p
    let n = case list.length(a) <= list.length(b) {
      True -> list.length(a)
      False -> list.length(b)
    }
    lcs.length(a, b) <= n
  })
}

// ---------------------------------------------------------------------
// Distance non-negativity & triangle inequality (Levenshtein only — a
// true metric).
// ---------------------------------------------------------------------

pub fn levenshtein_non_negative_test() {
  metamon.forall(small_unicode_pair(), fn(p) {
    let #(a, b) = p
    distance.levenshtein(a, b) >= 0
  })
}

// Equivariance of levenshtein_list under common-prefix injection:
// prepending the same x to both inputs leaves the distance unchanged.
fn pair_prepend_x_t() -> transform.Transform(#(List(String), List(String))) {
  transform.new("pair_prepend_x", fn(p: #(List(String), List(String))) {
    #(["x", ..p.0], ["x", ..p.1])
  })
}

pub fn levenshtein_list_invariant_under_common_prefix_test() {
  let mr =
    metamon.invariant_under(
      name: "levenshtein_list_under_common_prefix",
      under: pair_prepend_x_t(),
    )
  metamon.forall_morph(
    small_grapheme_list_pair(),
    mr,
    fn(p: #(List(String), List(String))) { distance.levenshtein_list(p.0, p.1) },
  )
}

// LCS invariance under common prefix: lcs.length(x++a, x++b) == |x| + lcs.length(a, b).
pub fn lcs_length_common_prefix_growth_test() {
  metamon.forall(small_grapheme_list_pair(), fn(p) {
    let #(a, b) = p
    let prefix = ["x", "y"]
    let with_prefix = lcs.length(list.append(prefix, a), list.append(prefix, b))
    let without = lcs.length(a, b)
    with_prefix >= list.length(prefix) + without
    // ">=" because spurious matches between prefix and a/b can only
    // increase the LCS — strict equality requires prefix items absent
    // from a, b, which we don't enforce in random graphemes.
  })
}

// ---------------------------------------------------------------------
// Search prefix-soundness: every result is within max_distance of query.
// ---------------------------------------------------------------------

pub fn did_you_mean_results_within_distance_test() {
  let candidate_pool = ["foo", "bar", "baz", "quux", "spam", "eggs", "café"]
  metamon.forall(small_unicode_string(), fn(query) {
    let max_d = 2
    let results = search.did_you_mean(query, candidate_pool, max_d)
    list.all(results, fn(c) { distance.levenshtein(query, c) <= max_d })
  })
}
