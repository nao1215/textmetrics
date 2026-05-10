//// Convenience helpers for spell-correction-style search built on
//// [`distance`](textmetrics/distance.html) and
//// [`similarity`](textmetrics/similarity.html).
////
//// Both functions are deterministic: ties are broken by the
//// candidates' original input order.

import gleam/float
import gleam/int
import gleam/list
import gleam/order
import textmetrics/distance
import textmetrics/similarity

/// A scored candidate produced by [`rank_jaro_winkler`](#rank_jaro_winkler).
///
/// Both fields are labelled so callers can read them directly as
/// `r.label` and `r.score` without destructuring a tuple.
pub type Ranked {
  Ranked(label: String, score: Float)
}

/// Return candidates within `max_distance` Levenshtein graphemes of
/// `query`, sorted ascending by distance. Empty list when nothing
/// matches or when `candidates` is empty.
///
/// Ties on distance are broken by the candidate's position in
/// `candidates`.
pub fn did_you_mean(
  query: String,
  candidates: List(String),
  max_distance: Int,
) -> List(String) {
  candidates
  |> list.index_map(fn(c, i) { #(c, distance.levenshtein(query, c), i) })
  |> list.filter(fn(t) {
    let #(_, d, _) = t
    d <= max_distance
  })
  |> list.sort(by: fn(a, b) {
    let #(_, da, ia) = a
    let #(_, db, ib) = b
    case int.compare(da, db) {
      order.Eq -> int.compare(ia, ib)
      o -> o
    }
  })
  |> list.map(fn(t) {
    let #(c, _, _) = t
    c
  })
}

/// Single closest candidate within `max_distance` Levenshtein
/// graphemes of `query`. Returns `Error(Nil)` when no candidate is
/// close enough or when `candidates` is empty.
///
/// This is the convenience form of [`did_you_mean`](#did_you_mean) for
/// the dominant CLI use case ("Unknown command. Did you mean `X`?").
/// Ties on distance are broken by the candidate's position in
/// `candidates` — the first qualifying candidate wins.
pub fn closest(
  query: String,
  candidates: List(String),
  max_distance: Int,
) -> Result(String, Nil) {
  case did_you_mean(query, candidates, max_distance) {
    [first, ..] -> Ok(first)
    [] -> Error(Nil)
  }
}

/// Rank `candidates` by Jaro-Winkler similarity (Winkler-1990
/// defaults) descending, returning up to `top_n` [`Ranked`](#Ranked)
/// records.
///
/// Ties on similarity are broken by the candidate's position in
/// `candidates`. When `top_n <= 0` returns an empty list.
pub fn rank_jaro_winkler(
  query: String,
  candidates: List(String),
  top_n: Int,
) -> List(Ranked) {
  candidates
  |> list.index_map(fn(c, i) { #(c, similarity.jaro_winkler(query, c), i) })
  |> list.sort(by: fn(a, b) {
    let #(_, sa, ia) = a
    let #(_, sb, ib) = b
    case float.compare(sb, sa) {
      order.Eq -> int.compare(ia, ib)
      o -> o
    }
  })
  |> list.take(top_n)
  |> list.map(fn(t) {
    let #(c, s, _) = t
    Ranked(label: c, score: s)
  })
}
