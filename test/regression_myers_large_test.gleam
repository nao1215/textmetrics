//// Myers kept a persistent Dict for every edit distance step, so two
//// unrelated 3,000-line inputs took 16 seconds on Erlang and 25 on
//// JavaScript. The search now keeps compact frontiers and only a
//// few checkpoints; the scripts are unchanged (see the legacy tests).

import gleam/int
import gleam/list
import gleeunit/should
import legacy/v0_9_0
import textmetrics

fn lines(prefix: String, count: Int) -> List(String) {
  int.range(from: count, to: 0, with: [], run: fn(acc, i) {
    [prefix <> int.to_string(i), ..acc]
  })
}

pub fn unrelated_large_inputs_finish_quickly_test() {
  let old = lines("a", 3000)
  let new = lines("b", 3000)
  let script = textmetrics.myers(old, new)
  textmetrics.edit_cost(script) |> should.equal(6000)
  textmetrics.recover_old(script) |> should.equal(old)
  textmetrics.recover_new(script) |> should.equal(new)
}

pub fn medium_inputs_match_v0_9_0_test() {
  let old =
    list.map(lines("", 400), fn(line) {
      case int.parse(line) {
        Ok(n) -> int.to_string(n % 7)
        Error(Nil) -> line
      }
    })
  let new =
    list.map(lines("", 380), fn(line) {
      case int.parse(line) {
        Ok(n) -> int.to_string(n % 5)
        Error(Nil) -> line
      }
    })
  textmetrics.myers(old, new) |> should.equal(v0_9_0.myers(old, new))
}
