import gleam/list
import gleeunit/should
import textmetrics.{
  ContextLinesNegative, Delete, Equal, Insert, NameContainsForbiddenBytes,
  NewName, OldName, PrefixMaxNegative, PrefixScaleOutOfRange,
}

fn shortcut_inputs() -> List(#(String, String)) {
  [#("", ""), #("same", "same"), #("", "a"), #("a", ""), #("abc", "XYZ")]
}

pub fn winkler_scale_is_validated_before_max_and_input_shortcuts_test() {
  list.each(shortcut_inputs(), fn(pair) {
    list.each([-0.000_001, 0.250_001], fn(scale) {
      textmetrics.jaro_winkler(
        pair.0,
        pair.1,
        prefix_scale: scale,
        prefix_max: -1,
      )
      |> should.equal(Error(PrefixScaleOutOfRange(scale)))
    })
  })
}

pub fn winkler_max_is_validated_even_with_zero_scale_or_input_shortcuts_test() {
  list.each(shortcut_inputs(), fn(pair) {
    list.each([0.0, 0.1, 0.25], fn(scale) {
      textmetrics.jaro_winkler(
        pair.0,
        pair.1,
        prefix_scale: scale,
        prefix_max: -1,
      )
      |> should.equal(Error(PrefixMaxNegative(-1)))
    })
  })
}

pub fn winkler_valid_boundary_settings_keep_shortcut_results_test() {
  list.each([#(0.0, 0), #(0.0, 1_000_000), #(0.25, 0)], fn(settings) {
    list.each([#("", "", 1.0), #("a", "a", 1.0), #("", "a", 0.0)], fn(input) {
      textmetrics.jaro_winkler(
        input.0,
        input.1,
        prefix_scale: settings.0,
        prefix_max: settings.1,
      )
      |> should.equal(Ok(input.2))
    })
  })
}

fn scripts() -> List(List(textmetrics.Edit(String))) {
  [[], [Equal("same")], [Delete("before"), Insert("after")]]
}

pub fn unified_rejects_every_forbidden_byte_in_either_original_name_test() {
  list.each(["\n", "\r", "\u{0000}", "\t", "\r\n"], fn(forbidden) {
    let invalid = "before" <> forbidden <> "after"
    list.each(scripts(), fn(script) {
      textmetrics.to_unified(
        script,
        old_name: invalid,
        new_name: "new",
        context_lines: 0,
      )
      |> should.equal(Error(NameContainsForbiddenBytes(OldName, invalid)))
      textmetrics.to_unified(
        script,
        old_name: "old",
        new_name: invalid,
        context_lines: 0,
      )
      |> should.equal(Error(NameContainsForbiddenBytes(NewName, invalid)))
    })
  })
}

pub fn unified_validates_old_then_new_then_context_before_unchanged_test() {
  list.each(scripts(), fn(script) {
    textmetrics.to_unified(
      script,
      old_name: "old\n",
      new_name: "new\r",
      context_lines: -1,
    )
    |> should.equal(Error(NameContainsForbiddenBytes(OldName, "old\n")))
    textmetrics.to_unified(
      script,
      old_name: "old",
      new_name: "new\r",
      context_lines: -1,
    )
    |> should.equal(Error(NameContainsForbiddenBytes(NewName, "new\r")))
    textmetrics.to_unified(
      script,
      old_name: "old",
      new_name: "new",
      context_lines: -1,
    )
    |> should.equal(Error(ContextLinesNegative(-1)))
  })
}

pub fn unified_accepts_empty_names_and_zero_context_test() {
  textmetrics.to_unified(
    [Equal("same")],
    old_name: "",
    new_name: "",
    context_lines: 0,
  )
  |> should.equal(Ok(""))
  textmetrics.to_unified(
    [Insert("added")],
    old_name: "",
    new_name: "",
    context_lines: 0,
  )
  |> should.equal(Ok("--- \n+++ \n@@ -0,0 +1 @@\n+added\n"))
}

pub fn dice_rejects_invalid_ngram_size_before_empty_or_equal_shortcuts_test() {
  list.each(shortcut_inputs(), fn(pair) {
    list.each([-1, 0], fn(size) {
      textmetrics.sorensen_dice(pair.0, pair.1, ngram_size: size)
      |> should.equal(Error(Nil))
    })
  })
}

pub fn dice_valid_ngram_size_keeps_empty_input_results_test() {
  list.each([1, 100], fn(size) {
    textmetrics.sorensen_dice("", "", ngram_size: size) |> should.equal(Ok(1.0))
    textmetrics.sorensen_dice("", "a", ngram_size: size)
    |> should.equal(Ok(0.0))
    textmetrics.sorensen_dice("a", "", ngram_size: size)
    |> should.equal(Ok(0.0))
  })
}
