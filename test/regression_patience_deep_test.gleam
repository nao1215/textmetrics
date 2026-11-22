import gleam/int
import gleam/list
import gleeunit/should
import textmetrics.{Equal}

// ["1", "2", "1", "3", "2", ..., "k", "k-1"]: only one line is unique at
// each level, so patience nests about `k` segments deep. The recursive
// version overflowed the JavaScript stack at about 4,400 lines.
fn nested_lines(k: Int) -> List(String) {
  ["1", ..nested_lines_loop(k, [])]
}

fn nested_lines_loop(i: Int, acc: List(String)) -> List(String) {
  case i < 2 {
    True -> acc
    False ->
      nested_lines_loop(i - 1, [int.to_string(i), int.to_string(i - 1), ..acc])
  }
}

pub fn patience_deeply_nested_segments_test() {
  let lines = nested_lines(2500)
  textmetrics.patience(lines, lines)
  |> should.equal(list.map(lines, Equal))
}
