//// search normalises and splits the query once; its scores and
//// distances must still equal the per-pair public functions.

import gleam/list
import gleam/string
import metamon
import metamon/generator.{type Generator}
import metamon/generator/range
import textmetrics/distance
import textmetrics/search.{Ranked}
import textmetrics/similarity

fn word_generator() -> Generator(String) {
  generator.list_of(
    generator.element_of(["a", "b", "c", "é", "e\u{0301}", "👍🏽"]),
    range.constant(0, 8),
  )
  |> generator.map(string.concat)
}

fn input_generator() -> Generator(#(String, List(String))) {
  generator.tuple2(
    word_generator(),
    generator.list_of(word_generator(), range.constant(0, 6)),
  )
}

pub fn rank_jaro_winkler_scores_match_jaro_winkler_test() {
  metamon.forall(input_generator(), fn(input) {
    let #(query, candidates) = input
    search.rank_jaro_winkler(query, candidates, list.length(candidates))
    |> list.all(fn(ranked) {
      let Ranked(label:, score:) = ranked
      score == similarity.jaro_winkler(query, label)
    })
  })
}

pub fn did_you_mean_matches_levenshtein_filter_test() {
  metamon.forall(input_generator(), fn(input) {
    let #(query, candidates) = input
    let expected =
      list.filter(candidates, fn(candidate) {
        distance.levenshtein(query, candidate) <= 2
      })
    list.sort(search.did_you_mean(query, candidates, 2), string.compare)
    == list.sort(expected, string.compare)
  })
}
