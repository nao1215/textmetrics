import gleeunit/should
import textmetrics

pub fn unified_rejects_crlf_in_both_names_test() {
  textmetrics.to_unified(
    [],
    old_name: "a\tb\r\n\u{0000}c",
    new_name: "x\r\ny",
    context_lines: 3,
  )
  |> should.equal(
    Error(textmetrics.NameContainsForbiddenBytes(
      textmetrics.OldName,
      "a\tb\r\n\u{0000}c",
    )),
  )
}

pub fn unified_rejects_crlf_in_old_name_test() {
  textmetrics.to_unified(
    [],
    old_name: "old\r\nname",
    new_name: "new",
    context_lines: 3,
  )
  |> should.equal(
    Error(textmetrics.NameContainsForbiddenBytes(
      textmetrics.OldName,
      "old\r\nname",
    )),
  )
}

pub fn unified_rejects_crlf_in_new_name_test() {
  textmetrics.to_unified(
    [],
    old_name: "old",
    new_name: "new\r\nname\r",
    context_lines: 3,
  )
  |> should.equal(
    Error(textmetrics.NameContainsForbiddenBytes(
      textmetrics.NewName,
      "new\r\nname\r",
    )),
  )
}
