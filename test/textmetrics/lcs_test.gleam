import gleam/list
import gleeunit/should
import textmetrics/lcs

fn is_subsequence(sub: List(t), of full: List(t)) -> Bool {
  case sub {
    [] -> True
    [head, ..tail] ->
      case full {
        [] -> False
        [first, ..rest] ->
          case head == first {
            True -> is_subsequence(tail, of: rest)
            False -> is_subsequence(sub, of: rest)
          }
      }
  }
}

pub fn length_empty_pair_test() {
  lcs.length([], []) |> should.equal(0)
}

pub fn length_one_empty_test() {
  lcs.length(["a", "b", "c"], []) |> should.equal(0)
  lcs.length([], ["a", "b", "c"]) |> should.equal(0)
}

pub fn length_identical_test() {
  lcs.length(["a", "b", "c"], ["a", "b", "c"]) |> should.equal(3)
}

pub fn length_clrs_example_test() {
  lcs.length(["A", "B", "C", "B", "D", "A", "B"], ["B", "D", "C", "A", "B", "A"])
  |> should.equal(4)
}

pub fn length_two_lcs_example_test() {
  lcs.length(["A", "G", "C", "A", "T"], ["G", "A", "C"]) |> should.equal(2)
}

pub fn sequence_empty_test() {
  lcs.sequence([], []) |> should.equal([])
}

pub fn sequence_one_empty_test() {
  lcs.sequence(["a", "b"], []) |> should.equal([])
  lcs.sequence([], ["a", "b"]) |> should.equal([])
}

pub fn sequence_identical_test() {
  lcs.sequence(["a", "b", "c"], ["a", "b", "c"])
  |> should.equal(["a", "b", "c"])
}

pub fn sequence_is_valid_subsequence_test() {
  let a = ["A", "B", "C", "B", "D", "A", "B"]
  let b = ["B", "D", "C", "A", "B", "A"]
  let result = lcs.sequence(a, b)
  list.length(result) |> should.equal(4)
  is_subsequence(result, of: a) |> should.be_true
  is_subsequence(result, of: b) |> should.be_true
}

pub fn sequence_two_lcs_is_valid_test() {
  let a = ["A", "G", "C", "A", "T"]
  let b = ["G", "A", "C"]
  let result = lcs.sequence(a, b)
  list.length(result) |> should.equal(2)
  is_subsequence(result, of: a) |> should.be_true
  is_subsequence(result, of: b) |> should.be_true
}
