import gleeunit/should
import textmetrics/edit.{Delete, DeleteRun, Equal, EqualRun, Insert, InsertRun}

pub fn recover_old_test() {
  let script = [Equal("a"), Delete("b"), Insert("c"), Equal("d")]
  edit.recover_old(script) |> should.equal(["a", "b", "d"])
}

pub fn recover_new_test() {
  let script = [Equal("a"), Delete("b"), Insert("c"), Equal("d")]
  edit.recover_new(script) |> should.equal(["a", "c", "d"])
}

pub fn cost_counts_inserts_and_deletes_test() {
  let script = [Equal("a"), Delete("b"), Insert("c"), Equal("d"), Delete("e")]
  edit.cost(script) |> should.equal(3)
}

pub fn cost_of_only_equals_is_zero_test() {
  edit.cost([Equal("a"), Equal("b")]) |> should.equal(0)
}

pub fn cost_of_empty_script_is_zero_test() {
  edit.cost([]) |> should.equal(0)
}

pub fn runs_groups_consecutive_edits_test() {
  let script = [
    Equal("a"),
    Equal("b"),
    Delete("c"),
    Delete("d"),
    Insert("e"),
    Equal("f"),
  ]
  edit.runs(script)
  |> should.equal([
    EqualRun(["a", "b"]),
    DeleteRun(["c", "d"]),
    InsertRun(["e"]),
    EqualRun(["f"]),
  ])
}

pub fn runs_of_empty_script_is_empty_test() {
  edit.runs([]) |> should.equal([])
}

pub fn round_trip_invariant_test() {
  let script = [
    Equal("hello"),
    Delete("old"),
    Insert("new"),
    Equal("world"),
  ]
  edit.recover_old(script) |> should.equal(["hello", "old", "world"])
  edit.recover_new(script) |> should.equal(["hello", "new", "world"])
}
