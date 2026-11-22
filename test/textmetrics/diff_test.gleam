import gleeunit/should
import textmetrics.{
  ContextLinesNegative, NameContainsForbiddenBytes, NewName, OldName,
}

pub fn myers_round_trip_basic_test() {
  let old = ["a", "b", "c"]
  let new = ["a", "x", "c"]
  let script = textmetrics.myers(old, new)
  textmetrics.recover_old(script) |> should.equal(old)
  textmetrics.recover_new(script) |> should.equal(new)
}

pub fn myers_empty_inputs_test() {
  textmetrics.myers([], []) |> should.equal([])
}

pub fn myers_insert_only_test() {
  textmetrics.myers([], ["a", "b"])
  |> should.equal([textmetrics.Insert("a"), textmetrics.Insert("b")])
}

pub fn myers_delete_only_test() {
  textmetrics.myers(["a", "b"], [])
  |> should.equal([textmetrics.Delete("a"), textmetrics.Delete("b")])
}

pub fn myers_no_changes_test() {
  let old = ["a", "b", "c"]
  let script = textmetrics.myers(old, old)
  textmetrics.edit_cost(script) |> should.equal(0)
  textmetrics.recover_old(script) |> should.equal(old)
}

pub fn patience_round_trip_test() {
  let old = ["the quick brown", "fox jumps over", "the lazy dog"]
  let new = ["the quick brown", "fox leaps over", "the lazy dog"]
  let script = textmetrics.patience(old, new)
  textmetrics.recover_old(script) |> should.equal(old)
  textmetrics.recover_new(script) |> should.equal(new)
}

pub fn patience_empty_test() {
  textmetrics.patience([], []) |> should.equal([])
}

pub fn patience_no_unique_anchors_falls_back_test() {
  // Both lists contain only duplicates so there are no unique anchors.
  let old = ["a", "a", "a"]
  let new = ["a", "a"]
  let script = textmetrics.patience(old, new)
  textmetrics.recover_old(script) |> should.equal(old)
  textmetrics.recover_new(script) |> should.equal(new)
}

pub fn unified_context_accepts_zero_test() {
  textmetrics.to_unified(
    [textmetrics.Insert("added")],
    old_name: "a",
    new_name: "b",
    context_lines: 0,
  )
  |> should.equal(Ok("--- a\n+++ b\n@@ -0,0 +1 @@\n+added\n"))
}

pub fn unified_context_accepts_positive_test() {
  textmetrics.to_unified(
    [textmetrics.Insert("added")],
    old_name: "a",
    new_name: "b",
    context_lines: 100,
  )
  |> should.equal(Ok("--- a\n+++ b\n@@ -0,0 +1 @@\n+added\n"))
}

pub fn unified_context_rejects_negative_test() {
  textmetrics.to_unified([], old_name: "a", new_name: "b", context_lines: -1)
  |> should.equal(Error(ContextLinesNegative(-1)))
}

pub fn to_unified_no_changes_is_empty_test() {
  let old = ["one", "two", "three"]

  {
    textmetrics.to_unified(
      textmetrics.myers(old, old),
      old_name: "a",
      new_name: "b",
      context_lines: 3,
    )
    |> should.be_ok
  }
  |> should.equal("")
}

pub fn to_unified_spec_example_test() {
  let old = ["the quick brown", "fox jumps over", "the lazy dog"]
  let new = ["the quick brown", "fox leaps over", "the lazy dog"]

  let expected =
    "--- a
+++ b
@@ -1,3 +1,3 @@
 the quick brown
-fox jumps over
+fox leaps over
 the lazy dog
"
  {
    textmetrics.to_unified(
      textmetrics.myers(old, new),
      old_name: "a",
      new_name: "b",
      context_lines: 3,
    )
    |> should.be_ok
  }
  |> should.equal(expected)
}

pub fn to_unified_zero_context_test() {
  let old = ["a", "b", "c"]
  let new = ["a", "B", "c"]

  let out = {
    textmetrics.to_unified(
      textmetrics.myers(old, new),
      old_name: "old",
      new_name: "new",
      context_lines: 0,
    )
    |> should.be_ok
  }
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

pub fn unified_rejects_newline_from_old_name_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old\nfake-line",
    new_name: "new",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "old\nfake-line")))
}

pub fn unified_rejects_cr_from_new_name_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old",
    new_name: "new\rextra",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(NewName, "new\rextra")))
}

pub fn unified_rejects_nul_from_new_name_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old",
    new_name: "new\u{0000}null",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(NewName, "new\u{0000}null")))
}

pub fn unified_rejects_tab_from_old_name_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old\tdate",
    new_name: "new",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "old\tdate")))
}

pub fn unified_old_name_rejects_forbidden_bytes_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "renamed\n\rextra\u{0000}\tend",
    new_name: "new",
    context_lines: 3,
  )
  |> should.equal(
    Error(NameContainsForbiddenBytes(OldName, "renamed\n\rextra\u{0000}\tend")),
  )
}

pub fn unified_new_name_rejects_forbidden_bytes_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old",
    new_name: "renamed\n\rextra\u{0000}\tend",
    context_lines: 3,
  )
  |> should.equal(
    Error(NameContainsForbiddenBytes(NewName, "renamed\n\rextra\u{0000}\tend")),
  )
}

pub fn unified_clean_names_are_preserved_test() {
  textmetrics.to_unified(
    [textmetrics.Insert("added")],
    old_name: "old",
    new_name: "new",
    context_lines: 3,
  )
  |> should.equal(Ok("--- old\n+++ new\n@@ -0,0 +1 @@\n+added\n"))
}

pub fn unified_checked_rejects_newline_in_old_name_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old\nfake",
    new_name: "new",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "old\nfake")))
}

pub fn unified_checked_rejects_nul_in_new_name_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old",
    new_name: "new\u{0000}null",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(NewName, "new\u{0000}null")))
}

pub fn unified_reports_old_name_first_when_both_bad_test() {
  textmetrics.to_unified(
    [],
    old_name: "bad\nold",
    new_name: "bad\nnew",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "bad\nold")))
}

pub fn unified_old_name_checked_rejects_tab_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old\tdate",
    new_name: "new",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "old\tdate")))
}

pub fn unified_new_name_checked_rejects_cr_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old",
    new_name: "new\rextra",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(NewName, "new\rextra")))
}

pub fn to_unified_rejects_header_injection_test() {
  textmetrics.to_unified(
    [textmetrics.Delete("a"), textmetrics.Insert("b")],
    old_name: "old\nfake",
    new_name: "new",
    context_lines: 3,
  )
  |> should.equal(Error(NameContainsForbiddenBytes(OldName, "old\nfake")))
}
