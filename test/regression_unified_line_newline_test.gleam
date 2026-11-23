//// An element holding a line feed would render as two diff lines with a
//// single prefix, which `patch` applies to the wrong lines. `to_unified`
//// rejects such elements instead of emitting a corrupt diff.

import gleeunit/should
import textmetrics.{Delete, Equal, Insert, LineContainsNewline}

fn render(script) {
  textmetrics.to_unified(script, old_name: "a", new_name: "b", context_lines: 3)
}

pub fn inserted_line_with_line_feed_is_rejected_test() {
  render([Equal("x"), Insert("y\nz")])
  |> should.equal(Error(LineContainsNewline("y\nz")))
}

pub fn deleted_and_context_lines_with_line_feed_are_rejected_test() {
  render([Delete("a\n"), Insert("b")])
  |> should.equal(Error(LineContainsNewline("a\n")))
  render([Equal("a\nb"), Insert("c")])
  |> should.equal(Error(LineContainsNewline("a\nb")))
}

pub fn unchanged_script_is_validated_too_test() {
  render([Equal("a\nb")])
  |> should.equal(Error(LineContainsNewline("a\nb")))
}

pub fn names_and_context_are_validated_before_lines_test() {
  textmetrics.to_unified(
    [Insert("a\nb")],
    old_name: "a\n",
    new_name: "b",
    context_lines: 3,
  )
  |> should.be_error
  |> should.not_equal(LineContainsNewline("a\nb"))
  textmetrics.to_unified(
    [Insert("a\nb")],
    old_name: "a",
    new_name: "b",
    context_lines: -1,
  )
  |> should.equal(Error(textmetrics.ContextLinesNegative(-1)))
}

pub fn carriage_returns_inside_lines_are_kept_test() {
  render([Delete("a\r"), Insert("b\r")])
  |> should.equal(Ok("--- a\n+++ b\n@@ -1 +1 @@\n-a\r\n+b\r\n"))
}
