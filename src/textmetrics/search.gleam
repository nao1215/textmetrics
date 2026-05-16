//// Convenience helpers for spell-correction-style search built on
//// [`distance`](textmetrics/distance.html) and
//// [`similarity`](textmetrics/similarity.html).
////
//// Both functions are deterministic: ties are broken by the
//// candidates' original input order.

import gleam/float
import gleam/int
import gleam/list
import gleam/option.{type Option, None, Some}
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
///
/// `max_distance` is measured against the whole candidate string,
/// not against substrings or tokens. The function is the right tool
/// for short single-token candidate sets (command names, enum
/// values, short labels) where the typo budget is similar in
/// magnitude to the candidate's length. For prose-style candidates
/// (multi-word titles, sentences), the length difference between a
/// short query and a long candidate dominates the Levenshtein
/// distance — `did_you_mean("vulcano", ["Volcano in Iceland"], 4)`
/// returns `[]`, not `["Volcano in Iceland"]`, because the distance
/// is ~12. Tokenise the candidate set first when the use case is
/// prose-style:
///
/// ```gleam
/// list.flat_map(titles, string.split(_, on: " "))
/// |> search.did_you_mean(query, _, 2)
/// ```
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
/// graphemes of `query`. Returns `None` when no candidate is close
/// enough or when `candidates` is empty.
///
/// This is the convenience form of [`did_you_mean`](#did_you_mean) for
/// the dominant CLI use case ("Unknown command. Did you mean `X`?").
/// Ties on distance are broken by the candidate's position in
/// `candidates` — the first qualifying candidate wins.
///
/// Returns `Option(String)` rather than `Result(String, Nil)` because
/// "no candidate within the threshold" is an expected, semantically
/// empty result rather than a failure. The matching companion
/// [`did_you_mean`](#did_you_mean) already returns a (possibly empty)
/// list for the same reason.
///
/// Inherits the whole-string measurement from
/// [`did_you_mean`](#did_you_mean): the `max_distance` budget is
/// compared against the entire candidate, not against substrings or
/// tokens. Tokenise the candidate set first when working with
/// prose-style candidates — see the `did_you_mean` doc-comment for
/// the recipe.
pub fn closest(
  query: String,
  candidates: List(String),
  max_distance: Int,
) -> Option(String) {
  case did_you_mean(query, candidates, max_distance) {
    [first, ..] -> Some(first)
    [] -> None
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
