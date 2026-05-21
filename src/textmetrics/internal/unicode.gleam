//// Internal Unicode helpers shared across the public modules.
////
//// **Not part of the public API.** Sub-modules under `internal/` are
//// excluded from semver guarantees and may change shape between minor
//// versions.

/// Normalise the given string to Unicode Normalization Form C (NFC).
///
/// On Erlang this delegates to `unicode:characters_to_nfc_binary/1`;
/// on JavaScript it delegates to `String.prototype.normalize("NFC")`.
/// Both runtimes ship NFC tables, so callers do not need an extra
/// dependency.
///
/// Distance and similarity functions call this on their inputs so
/// that canonically-equivalent strings (`"\u{00C1}"` vs
/// `"A\u{0301}"`) compare as equal, which matches the README's
/// "operates on Unicode grapheme clusters (UAX #29)" contract.
@external(erlang, "textmetrics_ffi", "to_nfc")
@external(javascript, "../../textmetrics_ffi.mjs", "to_nfc")
pub fn to_nfc(s: String) -> String
