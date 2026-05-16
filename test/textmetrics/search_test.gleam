import gleam/float
import gleam/option.{None, Some}
import gleeunit/should
import textmetrics/search

const tolerance = 0.000_001

fn approx_equal(a: Float, b: Float) -> Bool {
  float.absolute_value(a -. b) <=. tolerance
}

pub fn did_you_mean_basic_test() {
  // Spec §12.11 lists "uninstall" as distance 2 from "instal", but the
  // actual Levenshtein distance is 3 (the comment in the spec is
  // mistaken). With max_distance=2 only "install" survives. With
  // max_distance=3 both candidates appear, ordered by ascending
  // distance.
  search.did_you_mean("instal", ["install", "uninstall", "tail"], 2)
  |> should.equal(["install"])
  search.did_you_mean("instal", ["install", "uninstall", "tail"], 3)
  |> should.equal(["install", "uninstall"])
}

pub fn did_you_mean_no_matches_test() {
  search.did_you_mean("xyz", ["install"], 2) |> should.equal([])
}

pub fn did_you_mean_empty_candidates_test() {
  search.did_you_mean("a", [], 5) |> should.equal([])
}

pub fn did_you_mean_ordering_by_distance_test() {
  // exact match before close match before farther one
  search.did_you_mean("foo", ["fool", "foo", "fox"], 5)
  |> should.equal(["foo", "fool", "fox"])
}

pub fn did_you_mean_tie_uses_input_order_test() {
  search.did_you_mean("a", ["x", "y", "z"], 1) |> should.equal(["x", "y", "z"])
}

pub fn rank_jaro_winkler_basic_test() {
  let result =
    search.rank_jaro_winkler("MARTHA", ["MARHTA", "DICKSONX", "DUANE"], 2)
  case result {
    [search.Ranked(label: top_label, score: _), _] ->
      top_label |> should.equal("MARHTA")
    _ -> should.fail()
  }
}

pub fn rank_jaro_winkler_top_n_zero_test() {
  search.rank_jaro_winkler("a", ["a", "b"], 0) |> should.equal([])
}

pub fn rank_jaro_winkler_top_n_more_than_candidates_test() {
  let result = search.rank_jaro_winkler("MARTHA", ["MARHTA"], 10)
  case result {
    [search.Ranked(label: label, score: score)] -> {
      label |> should.equal("MARHTA")
      approx_equal(score, 0.961_111_111) |> should.be_true
    }
    _ -> should.fail()
  }
}

pub fn rank_jaro_winkler_empty_candidates_test() {
  search.rank_jaro_winkler("a", [], 5) |> should.equal([])
}

pub fn rank_jaro_winkler_uses_labeled_fields_test() {
  // Probe that the returned record exposes its values via labelled
  // accessors so callers can write `r.label` / `r.score`.
  let assert [r, ..] = search.rank_jaro_winkler("foo", ["foo", "bar"], 5)
  r.label |> should.equal("foo")
  r.score |> should.equal(1.0)
}

// `closest`: the dominant CLI use case is the single best match for an
// "Unknown command" message. These tests pin the contract.

pub fn closest_returns_single_best_match_test() {
  search.closest("instal", ["install", "uninstall", "tail"], 2)
  |> should.equal(Some("install"))
}

pub fn closest_returns_none_when_no_match_within_distance_test() {
  search.closest("xyz", ["install"], 2) |> should.equal(None)
}

pub fn closest_empty_candidates_returns_none_test() {
  search.closest("a", [], 5) |> should.equal(None)
}

pub fn closest_breaks_ties_by_input_order_test() {
  // Three single-character candidates all distance 1 from "a"; the
  // first one in candidate order wins.
  search.closest("a", ["x", "y", "z"], 1) |> should.equal(Some("x"))
}

pub fn closest_prefers_exact_match_over_close_test() {
  search.closest("foo", ["fool", "foo", "fox"], 5) |> should.equal(Some("foo"))
}
