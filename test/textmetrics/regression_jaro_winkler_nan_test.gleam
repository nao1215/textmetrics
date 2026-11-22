import gleam/float
import gleam/list
import gleeunit/should
import textmetrics

@target(javascript)
fn infinity() -> Float {
  let assert Ok(finite) = float.parse("1.0e308")
  finite *. finite
}

@target(javascript)
fn nan() -> Float {
  let infinite = infinity()
  let value = infinite /. infinite
  should.be_true(!{ value >=. 0.0 || value <. 0.0 })
  value
}

@target(javascript)
fn assert_nan_scale_rejected(left: String, right: String, cap: Int) {
  let assert Error(textmetrics.PrefixScaleOutOfRange(got)) =
    textmetrics.jaro_winkler(left, right, prefix_scale: nan(), prefix_max: cap)
  should.be_true(!{ got >=. 0.0 || got <. 0.0 })
}

@target(javascript)
pub fn nan_scale_is_rejected_for_empty_inputs_and_zero_cap_test() {
  assert_nan_scale_rejected("", "", 0)
}

@target(javascript)
pub fn nan_scale_is_rejected_for_equal_nonempty_inputs_test() {
  assert_nan_scale_rejected("same", "same", 4)
}

@target(javascript)
pub fn nan_scale_is_rejected_before_zero_score_shortcut_test() {
  assert_nan_scale_rejected("abc", "xyz", 4)
}

@target(javascript)
pub fn nan_scale_is_rejected_for_normal_prefix_boost_test() {
  assert_nan_scale_rejected("martha", "marhta", 4)
}

@target(javascript)
pub fn nan_scale_error_precedes_negative_cap_test() {
  assert_nan_scale_rejected("", "", -1)
}

@target(javascript)
pub fn infinite_scales_are_rejected_before_negative_cap_test() {
  list.each([infinity(), 0.0 -. infinity()], fn(scale) {
    let assert Error(textmetrics.PrefixScaleOutOfRange(got)) =
      textmetrics.jaro_winkler("", "", prefix_scale: scale, prefix_max: -1)
    should.equal(got, scale)
  })
}

pub fn finite_scale_endpoints_and_negative_zero_remain_valid_test() {
  list.each([0.0, -0.0], fn(scale) {
    let assert Ok(score) =
      textmetrics.jaro_winkler(
        "martha",
        "marhta",
        prefix_scale: scale,
        prefix_max: 4,
      )
    should.be_true(
      float.absolute_value(score -. 17.0 /. 18.0) <=. 0.000_000_000_001,
    )
  })
  let assert Ok(quarter) =
    textmetrics.jaro_winkler(
      "martha",
      "marhta",
      prefix_scale: 0.25,
      prefix_max: 4,
    )
  should.be_true(
    float.absolute_value(quarter -. 71.0 /. 72.0) <=. 0.000_000_000_001,
  )
  textmetrics.jaro_winkler("", "", prefix_scale: 0.25, prefix_max: 0)
  |> should.equal(Ok(1.0))
}
