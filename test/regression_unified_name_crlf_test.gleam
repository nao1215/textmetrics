import gleeunit/should
import textmetrics/diff

// "\r\n" is a single grapheme cluster, so a grapheme-wise filter used to
// keep it and the header broke across lines.

pub fn unified_options_strips_crlf_test() {
  diff.unified_options(old_name: "a\tb\r\n\u{0000}c", new_name: "x\r\ny")
  |> fn(options) { #(diff.old_name(options), diff.new_name(options)) }
  |> should.equal(#("abc", "xy"))
}

pub fn with_old_name_strips_crlf_test() {
  diff.unified_options(old_name: "a", new_name: "b")
  |> diff.with_old_name("old\r\nname")
  |> diff.old_name
  |> should.equal("oldname")
}

pub fn with_new_name_strips_crlf_test() {
  diff.unified_options(old_name: "a", new_name: "b")
  |> diff.with_new_name("new\r\nname\r")
  |> diff.new_name
  |> should.equal("newname")
}
