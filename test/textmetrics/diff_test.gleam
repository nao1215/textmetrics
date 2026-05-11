import gleeunit/should
import textmetrics/diff.{
  ContextLinesNegative, NameContainsForbiddenBytes, NewName, OldName,
}
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

// Issue #3: names with embedded newlines / CR / NUL / tab corrupt the
// unified-diff header. The non-strict constructors and setters now
// silently strip those bytes; the `_checked` variants surface them
// as `NameContainsForbiddenBytes` errors.

pub fn unified_options_strips_newline_from_old_name_test() {
  let opts = diff.unified_options(old_name: "old\nfake-line", new_name: "new")
  diff.old_name(opts) |> should.equal("oldfake-line")
}

pub fn unified_options_strips_cr_from_new_name_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "new\rextra")
  diff.new_name(opts) |> should.equal("newextra")
}

pub fn unified_options_strips_nul_from_new_name_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "new\u{0000}null")
  diff.new_name(opts) |> should.equal("newnull")
}

pub fn unified_options_strips_tab_from_old_name_test() {
  let opts = diff.unified_options(old_name: "old\tdate", new_name: "new")
  diff.old_name(opts) |> should.equal("olddate")
}

pub fn with_old_name_strips_forbidden_bytes_test() {
  let base = diff.unified_options(old_name: "a", new_name: "b")
  let updated = diff.with_old_name(base, "renamed\n\rextra\u{0000}\tend")
  diff.old_name(updated) |> should.equal("renamedextraend")
}

pub fn with_new_name_strips_forbidden_bytes_test() {
  let base = diff.unified_options(old_name: "a", new_name: "b")
  let updated = diff.with_new_name(base, "renamed\n\rextra\u{0000}\tend")
  diff.new_name(updated) |> should.equal("renamedextraend")
}

pub fn unified_options_checked_accepts_clean_names_test() {
  let assert Ok(opts) =
    diff.unified_options_checked(old_name: "old", new_name: "new")
  diff.old_name(opts) |> should.equal("old")
  diff.new_name(opts) |> should.equal("new")
  diff.context_lines(opts) |> should.equal(3)
}

pub fn unified_options_checked_rejects_newline_in_old_name_test() {
  diff.unified_options_checked(old_name: "old\nfake", new_name: "new")
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "old\nfake")))
}

pub fn unified_options_checked_rejects_nul_in_new_name_test() {
  diff.unified_options_checked(old_name: "old", new_name: "new\u{0000}null")
  |> should.equal(Error(NameContainsForbiddenBytes(NewName, "new\u{0000}null")))
}

pub fn unified_options_checked_reports_old_name_first_when_both_bad_test() {
  // Mirrors how `result.try` short-circuits: the first failing field
  // is the one reported, and `old_name` is checked first.
  diff.unified_options_checked(old_name: "bad\nold", new_name: "bad\nnew")
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "bad\nold")))
}

pub fn with_old_name_checked_rejects_tab_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  diff.with_old_name_checked(opts, "old\tdate")
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "old\tdate")))
}

pub fn with_old_name_checked_preserves_other_fields_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let assert Ok(with_ctx) = diff.with_context_lines(opts, 5)
  let assert Ok(updated) = diff.with_old_name_checked(with_ctx, "renamed-a")
  diff.old_name(updated) |> should.equal("renamed-a")
  diff.new_name(updated) |> should.equal("b")
  diff.context_lines(updated) |> should.equal(5)
}

pub fn with_new_name_checked_rejects_cr_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  diff.with_new_name_checked(opts, "new\rextra")
  |> should.equal(Error(NameContainsForbiddenBytes(NewName, "new\rextra")))
}

pub fn with_new_name_checked_preserves_other_fields_test() {
  let opts = diff.unified_options(old_name: "a", new_name: "b")
  let assert Ok(with_ctx) = diff.with_context_lines(opts, 7)
  let assert Ok(updated) = diff.with_new_name_checked(with_ctx, "renamed-b")
  diff.old_name(updated) |> should.equal("a")
  diff.new_name(updated) |> should.equal("renamed-b")
  diff.context_lines(updated) |> should.equal(7)
}

pub fn to_unified_header_stays_two_lines_after_sanitization_test() {
  let script = diff.myers(["a"], ["b"])
  let opts = diff.unified_options(old_name: "old\nfake", new_name: "new")
  let out = diff.to_unified(script, opts)
  // The first two lines must be `--- ` and `+++ ` — i.e. no orphan
  // line between them. After sanitization the header reads
  // `--- oldfake\n+++ new\n@@ -1 +1 @@\n-a\n+b\n`.
  out |> should.equal("--- oldfake\n+++ new\n@@ -1 +1 @@\n-a\n+b\n")
}
