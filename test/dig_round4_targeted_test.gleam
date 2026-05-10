//// Round 4: targeted probes at the algorithm internals that the
//// first three rounds did not directly attack.

import gleam/list
import gleam/string
import gleeunit/should
import textmetrics/diff
import textmetrics/edit
import textmetrics/lcs
import textmetrics/similarity

// ---------------------------------------------------------------------
// `to_unified` hunk-merge boundary
// ---------------------------------------------------------------------
// Two changes at indices i1 < i2 with context=c produce ranges
// [i1-c, i1+c] and [i2-c, i2+c]. They merge into one hunk iff
// (i2 - c) <= (i1 + c) + 1, i.e. iff i2 - i1 <= 2c + 1.
// With c = 3 the merge boundary is at distance 7.

fn count_at_at_headers(out: String) -> Int {
  out
  |> string.split("\n")
  |> list.filter(fn(line) { string.starts_with(line, "@@") })
  |> list.length
}

pub fn unified_hunks_merge_at_boundary_test() {
  // Changes at indices 1 and 8 (zero-indexed) → distance = 7.
  // With default context_lines = 3, this is exactly the merge boundary
  // and the spec/POSIX convention is to merge.
  let old = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j"]
  let new = ["a", "B", "c", "d", "e", "f", "g", "h", "I", "j"]
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let out = diff.to_unified(diff.myers(old, new), opts)
  count_at_at_headers(out) |> should.equal(1)
}

pub fn unified_hunks_split_just_past_boundary_test() {
  // Changes at indices 1 and 9 → distance = 8 > 2*3+1, so two hunks.
  let old = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k"]
  let new = ["a", "B", "c", "d", "e", "f", "g", "h", "i", "J", "k"]
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let out = diff.to_unified(diff.myers(old, new), opts)
  count_at_at_headers(out) |> should.equal(2)
}

pub fn unified_hunks_zero_context_adjacent_changes_test() {
  // With context_lines = 0, ranges are just the change index itself.
  // Two changes at indices 1 and 2 (adjacent) should still merge.
  let old = ["a", "b", "c", "d"]
  let new = ["a", "B", "C", "d"]
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let assert Ok(opts0) = diff.with_context_lines(opts, 0)
  let out = diff.to_unified(diff.myers(old, new), opts0)
  count_at_at_headers(out) |> should.equal(1)
}

pub fn unified_hunks_zero_context_separated_changes_test() {
  // With context_lines = 0 and changes at indices 1 and 3 (gap 2),
  // distance = 2 > 2*0+1 = 1, so two hunks.
  let old = ["a", "b", "c", "d", "e"]
  let new = ["a", "B", "c", "D", "e"]
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let assert Ok(opts0) = diff.with_context_lines(opts, 0)
  let out = diff.to_unified(diff.myers(old, new), opts0)
  count_at_at_headers(out) |> should.equal(2)
}

// ---------------------------------------------------------------------
// patience diff with stressed anchor patterns
// ---------------------------------------------------------------------

pub fn patience_anchors_only_at_extremes_test() {
  // Two unique anchors, one at the start and one at the end of both
  // inputs. LIS must pick both; the middle is shuffled.
  let old = ["start", "x", "y", "z", "end"]
  let new = ["start", "p", "q", "end"]
  let script = diff.patience(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn patience_unique_pairs_in_reversed_order_test() {
  // Two unique anchors that appear in opposite order in old vs new.
  // LIS on the new-positions should pick exactly one — patience must
  // still produce a valid round-trippable script.
  let old = ["a-once", "b-once"]
  let new = ["b-once", "a-once"]
  let script = diff.patience(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn patience_many_anchors_partly_increasing_test() {
  // Unique anchors at old indices 0,1,2,3,4 with new indices 0,3,1,4,2.
  // LIS of new-positions = [0, 3, 4] (length 3). The non-LIS anchors
  // become inserts/deletes inside the segments.
  let old = ["A", "B", "C", "D", "E"]
  let new = ["A", "C", "E", "B", "D"]
  let script = diff.patience(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn patience_no_unique_anchors_falls_back_test() {
  // All lines duplicated → no unique anchors → patience must fall
  // back to myers and still round-trip.
  let old = ["x", "x", "x", "y", "y"]
  let new = ["x", "x", "y", "y", "y"]
  let script = diff.patience(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

// ---------------------------------------------------------------------
// Jaro window edge cases
// ---------------------------------------------------------------------
// window = max(0, max(la, lb) / 2 - 1). For (1, 1) and (1, 2) the
// window is 0, so matching is position-strict.

pub fn jaro_window_zero_la1_lb1_match_test() {
  similarity.jaro("a", "a") |> should.equal(1.0)
}

pub fn jaro_window_zero_la1_lb1_mismatch_test() {
  similarity.jaro("a", "b") |> should.equal(0.0)
}

pub fn jaro_window_zero_la1_lb2_first_matches_test() {
  // window = max(1,2)/2 - 1 = 0. b="ab": position 0 is 'a', so a[0]
  // matches at b[0]. m=1, t=0 → (1/1 + 1/2 + 1/1)/3 = 2.5/3.
  let s = similarity.jaro("a", "ab")
  case s >. 0.833_3 && s <. 0.833_4 {
    True -> Nil
    False -> should.fail()
  }
}

pub fn jaro_window_zero_la1_lb2_no_match_test() {
  // window=0, b="ba", b[0]='b' ≠ a[0]='a'. m=0 → 0.0.
  similarity.jaro("a", "ba") |> should.equal(0.0)
}

pub fn jaro_window_one_la3_lb3_test() {
  // window = max(3,3)/2 - 1 = 0. Strict-position match.
  // "abc" vs "bca": a[0]='a' vs b[0]='b' (no), b[1]='c' (out of window=0). No match.
  // a[1]='b' vs b[1]='c' (no). a[2]='c' vs b[2]='a' (no).
  // matches = 0 → 0.0.
  similarity.jaro("abc", "bca") |> should.equal(0.0)
}

// ---------------------------------------------------------------------
// `lcs.sequence` determinism
// ---------------------------------------------------------------------

pub fn lcs_sequence_deterministic_test() {
  // Multiple valid LCS exist — the same call must return the same
  // sequence on repeat invocation.
  let a = ["A", "B", "C", "B", "D", "A", "B"]
  let b = ["B", "D", "C", "A", "B", "A"]
  let s1 = lcs.sequence(a, b)
  let s2 = lcs.sequence(a, b)
  let s3 = lcs.sequence(a, b)
  s1 |> should.equal(s2)
  s2 |> should.equal(s3)
}

pub fn lcs_sequence_deterministic_under_arg_swap_check_test() {
  // length is symmetric, but the sequence chosen by backtracking is
  // not necessarily the "same" in a/b — only the lengths match.
  let a = ["A", "G", "C", "A", "T"]
  let b = ["G", "A", "C"]
  let len_ab = lcs.length(a, b)
  let len_ba = lcs.length(b, a)
  len_ab |> should.equal(len_ba)
  list.length(lcs.sequence(a, b)) |> should.equal(len_ab)
  list.length(lcs.sequence(b, a)) |> should.equal(len_ba)
}
