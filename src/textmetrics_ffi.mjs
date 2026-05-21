// Normalise an arbitrary Unicode string to Normalization Form C.
//
// Used by `textmetrics/internal/unicode.to_nfc/1` so that distance
// functions compare canonically-equivalent inputs as equal. The
// runtime guarantees `String.prototype.normalize` for any conformant
// ECMAScript 2015+ host, which matches Gleam's published JavaScript
// target floor.
export function to_nfc(s) {
  return s.normalize("NFC");
}
