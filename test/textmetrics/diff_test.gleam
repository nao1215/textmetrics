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

// `with_old_name` / `with_new_name`: builder-style setters mirroring
// `with_context_lines`. The original constructor uses labelled
// arguments, so callers wanting to derive a new value from an existing
// one previously had to call `unified_options(...)` and re-apply
// `with_context_lines`. These setters close that asymmetry.

pub fn with_old_name_overrides_old_name_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let updated = diff.with_old_name(opts, "renamed-a")
  diff.old_name(updated) |> should.equal("renamed-a")
  diff.new_name(updated) |> should.equal("b")
}

pub fn with_old_name_preserves_context_lines_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let assert Ok(with_ctx) = diff.with_context_lines(opts, 5)
  let renamed = diff.with_old_name(with_ctx, "renamed-a")
  diff.context_lines(renamed) |> should.equal(5)
}

pub fn with_new_name_overrides_new_name_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let updated = diff.with_new_name(opts, "renamed-b")
  diff.old_name(updated) |> should.equal("a")
  diff.new_name(updated) |> should.equal("renamed-b")
}

pub fn with_new_name_preserves_context_lines_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let assert Ok(with_ctx) = diff.with_context_lines(opts, 7)
  let renamed = diff.with_new_name(with_ctx, "renamed-b")
  diff.context_lines(renamed) |> should.equal(7)
}

pub fn with_old_and_new_name_compose_test() {
  let base = diff.unified_options(old_name: "a", new_name: "b")
  let updated =
    base
    |> diff.with_old_name("a-v1")
    |> diff.with_new_name("a-v2")
  diff.old_name(updated) |> should.equal("a-v1")
  diff.new_name(updated) |> should.equal("a-v2")
}
