//// search normalises and splits the query once; its scores and
//// distances must still equal the per-pair public functions.

import gleam/list
import gleam/string
import metamon
import metamon/generator.{type Generator}
import textmetrics.{Ranked}

fn word_generator() -> Generator(String) {
  generator.list_of(
    generator.element_of(["a", "b", "c", "é", "e\u{0301}", "👍🏽"]),
    length: generator.range(from: 0, to: 8),
  )
  |> generator.map(string.concat)
}

fn input_generator() -> Generator(#(String, List(String))) {
  generator.tuple2(
    word_generator(),
    generator.list_of(word_generator(), length: generator.range(from: 0, to: 6)),
  )
}

pub fn rank_jaro_winkler_scores_match_jaro_winkler_test() {
  metamon.forall(input_generator(), fn(input) {
    let #(query, candidates) = input
    textmetrics.rank_jaro_winkler(query, candidates, list.length(candidates))
    |> list.each(fn(ranked) {
      let Ranked(label:, score:) = ranked
      assert Ok(score)
        == textmetrics.jaro_winkler(
          query,
          label,
          prefix_scale: 0.1,
          prefix_max: 4,
        )
    })
  })
}

pub fn did_you_mean_matches_levenshtein_filter_test() {
  metamon.forall(input_generator(), fn(input) {
    let #(query, candidates) = input
    let expected =
      list.filter(candidates, fn(candidate) {
        textmetrics.levenshtein(query, candidate) <= 2
      })
    assert list.sort(
        textmetrics.did_you_mean(query, candidates, 2),
        string.compare,
      )
      == list.sort(expected, string.compare)
  })
}
