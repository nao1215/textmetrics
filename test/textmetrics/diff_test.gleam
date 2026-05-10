import gleeunit/should
import textmetrics/diff.{ContextLinesNegative}
import textmetrics/edit

pub fn myers_round_trip_basic_test() {
  let old = ["a", "b", "c"]
  let new = ["a", "x", "c"]
  let script = diff.myers(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn myers_empty_inputs_test() {
  diff.myers([], []) |> should.equal([])
}

pub fn myers_insert_only_test() {
  diff.myers([], ["a", "b"])
  |> should.equal([edit.Insert("a"), edit.Insert("b")])
}

pub fn myers_delete_only_test() {
  diff.myers(["a", "b"], [])
  |> should.equal([edit.Delete("a"), edit.Delete("b")])
}

pub fn myers_no_changes_test() {
  let old = ["a", "b", "c"]
  let script = diff.myers(old, old)
  edit.cost(script) |> should.equal(0)
  edit.recover_old(script) |> should.equal(old)
}

pub fn patience_round_trip_test() {
  let old = ["the quick brown", "fox jumps over", "the lazy dog"]
  let new = ["the quick brown", "fox leaps over", "the lazy dog"]
  let script = diff.patience(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn patience_empty_test() {
  diff.patience([], []) |> should.equal([])
}

pub fn patience_no_unique_anchors_falls_back_test() {
  // Both lists contain only duplicates so there are no unique anchors.
  let old = ["a", "a", "a"]
  let new = ["a", "a"]
  let script = diff.patience(old, new)
  edit.recover_old(script) |> should.equal(old)
  edit.recover_new(script) |> should.equal(new)
}

pub fn unified_options_default_context_lines_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  diff.context_lines(opts) |> should.equal(3)
  diff.old_name(opts) |> should.equal("a")
  diff.new_name(opts) |> should.equal("b")
}

pub fn with_context_lines_accepts_zero_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let assert Ok(updated) = diff.with_context_lines(opts, 0)
  diff.context_lines(updated) |> should.equal(0)
}

pub fn with_context_lines_accepts_positive_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let assert Ok(updated) = diff.with_context_lines(opts, 100)
  diff.context_lines(updated) |> should.equal(100)
}

pub fn with_context_lines_rejects_negative_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  diff.with_context_lines(opts, -1)
  |> should.equal(Error(ContextLinesNegative(-1)))
}

pub fn to_unified_no_changes_is_empty_test() {
  let old = ["one", "two", "three"]
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  diff.to_unified(diff.myers(old, old), opts) |> should.equal("")
}

pub fn to_unified_spec_example_test() {
  let old = ["the quick brown", "fox jumps over", "the lazy dog"]
  let new = ["the quick brown", "fox leaps over", "the lazy dog"]
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let expected =
    "--- a
+++ b
@@ -1,3 +1,3 @@
 the quick brown
-fox jumps over
+fox leaps over
 the lazy dog
"
  diff.to_unified(diff.myers(old, new), opts) |> should.equal(expected)
}

pub fn to_unified_zero_context_test() {
  let old = ["a", "b", "c"]
  let new = ["a", "B", "c"]
  let opts = diff.unified_options(old_name: "old", new_name: "new")
  let assert Ok(opts0) = diff.with_context_lines(opts, 0)
  let out = diff.to_unified(diff.myers(old, new), opts0)
  // Single-line change with zero context: a `1` range omits the count.
  let expected =
    "--- old
+++ new
@@ -2 +2 @@
-b
+B
"
  out |> should.equal(expected)
}
