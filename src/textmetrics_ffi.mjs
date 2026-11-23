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

// Fixed-size arrays with constant-time reads for the Myers search. The
// Gleam caller checks the index against `array_size` first.
export function array_from_list(list) {
  return list.toArray();
}

export function array_size(array) {
  return array.length;
}

export function array_at(array, index) {
  return array[index];
}
