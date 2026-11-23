#!/usr/bin/env python3
"""Generate the Unicode 17.0.0 tables used for word and sentence counting.

Usage:
  python3 scripts/gen_unicode_category.py --unicode-data UnicodeData.txt \
      --word-break-property WordBreakProperty.txt \
      --sentence-break-property SentenceBreakProperty.txt [--check]

The inputs are explicitly downloaded, hash-checked UCD files. Generation never
uses the host's Unicode database and never downloads data. Gleam 1.19.2 formats
a temporary file before an atomic replacement of the output.
"""

import argparse
import hashlib
import os
from pathlib import Path
import subprocess
import sys
import tempfile

UNICODE_VERSION = "17.0.0"
UCD_URL = f"https://www.unicode.org/Public/{UNICODE_VERSION}/ucd"
UNICODE_URL = f"{UCD_URL}/UnicodeData.txt"
UNICODE_SHA256 = "2e1efc1dcb59c575eedf5ccae60f95229f706ee6d031835247d843c11d96470c"
WORD_BREAK_URL = f"{UCD_URL}/auxiliary/WordBreakProperty.txt"
WORD_BREAK_SHA256 = "72274cac1e6b919507db35655c3e175aa27274668a1ece95c28d2069f2ad9852"
SENTENCE_BREAK_URL = f"{UCD_URL}/auxiliary/SentenceBreakProperty.txt"
SENTENCE_BREAK_SHA256 = "871c0c985ad95125e25b302414065a10839d068970bceb383ecec138f22a0a18"
GLEAM_VERSION = "1.19.2"
DEFAULT_OUTPUT = Path(__file__).resolve().parents[1] / "src/textmetrics/internal/unicode_category.gleam"
CATEGORIES = frozenset(
    "Lu Ll Lt Lm Lo Mn Mc Me Nd Nl No Pc Pd Ps Pe Pi Pf Po Sm Sc Sk So Zs Zl Zp Cc Cf Cs Co Cn".split()
)
WORD_BREAK_VALUES = frozenset(
    "CR LF Newline Extend ZWJ Regional_Indicator Format Katakana Hebrew_Letter ALetter "
    "Single_Quote Double_Quote MidNumLet MidLetter MidNum Numeric ExtendNumLet WSegSpace".split()
)
SENTENCE_BREAK_VALUES = frozenset(
    "CR LF Extend Sep Format Sp Lower Upper OLetter Numeric ATerm SContinue STerm Close".split()
)


def parse_unicode_data(text):
    """Expand assigned rows and First/Last ranges; omitted points remain Cn."""
    categories = ["Cn"] * 0x110000
    previous = -1
    pending = None
    for number, line in enumerate(text.splitlines(), 1):
        fields = line.split(";")
        if len(fields) != 15:
            raise ValueError(f"UnicodeData line {number}: expected 15 fields")
        try:
            code = int(fields[0], 16)
        except ValueError as error:
            raise ValueError(f"UnicodeData line {number}: invalid code point") from error
        if not 0 <= code <= 0x10FFFF or code <= previous:
            raise ValueError(f"UnicodeData line {number}: code points must be in range and strictly increasing")
        previous = code
        name, category = fields[1:3]
        if category not in CATEGORIES:
            raise ValueError(f"UnicodeData line {number}: unknown category {category!r}")
        if name.startswith("<") and name.endswith(", First>"):
            if pending is not None:
                raise ValueError(f"UnicodeData line {number}: nested First range")
            pending = (code, name[:-8], category)
        elif name.startswith("<") and name.endswith(", Last>"):
            if pending is None:
                raise ValueError(f"UnicodeData line {number}: Last without First")
            start, first_name, first_category = pending
            if name[:-7] != first_name or category != first_category:
                raise ValueError(f"UnicodeData line {number}: First/Last name or category mismatch")
            categories[start : code + 1] = [category] * (code - start + 1)
            pending = None
        else:
            if pending is not None:
                raise ValueError(f"UnicodeData line {number}: First range missing Last")
            categories[code] = category
    if pending is not None:
        raise ValueError("UnicodeData ended with an unterminated First range")
    return categories


def parse_property_file(text, label, values):
    """Map each listed code point to its property value; unlisted points are absent."""
    properties = {}
    for number, line in enumerate(text.splitlines(), 1):
        content = line.split("#", 1)[0].strip()
        if not content:
            continue
        fields = [field.strip() for field in content.split(";")]
        if len(fields) != 2:
            raise ValueError(f"{label} line {number}: expected two fields")
        span, value = fields
        if value not in values:
            raise ValueError(f"{label} line {number}: unknown value {value!r}")
        try:
            if ".." in span:
                low, high = (int(part, 16) for part in span.split(".."))
            else:
                low = high = int(span, 16)
        except ValueError as error:
            raise ValueError(f"{label} line {number}: invalid code point range") from error
        if not 0 <= low <= high <= 0x10FFFF:
            raise ValueError(f"{label} line {number}: code point range out of order or out of range")
        for code in range(low, high + 1):
            if code in properties:
                raise ValueError(f"{label} line {number}: U+{code:04X} listed twice")
            properties[code] = value
    return properties


def ranges_where(predicate, start=0):
    ranges = []
    low = None
    for code in range(start, 0x110000):
        if predicate(code) and low is None:
            low = code
        elif not predicate(code) and low is not None:
            ranges.append((low, code - 1))
            low = None
    if low is not None:
        ranges.append((low, 0x10FFFF))
    return ranges


def non_letter_ranges(categories):
    def non_letter(code):
        category = categories[code]
        return not (category[0] in "LM" or category in ("Nd", "Nl"))

    return ranges_where(non_letter, start=0x80)


def property_ranges(properties, wanted):
    return ranges_where(lambda code: properties.get(code) in wanted)


def render_function(name, doc_lines, ranges):
    buckets = {}
    for low, high in ranges:
        while low <= high:
            block = low >> 8
            end = min(high, (block << 8) | 0xFF)
            buckets.setdefault(block, []).append((low, end))
            low = end + 1
    full, partial = [], []
    for block, parts in sorted(buckets.items()):
        if parts == [(block << 8, (block << 8) | 0xFF)]:
            if full and full[-1][1] == block - 1:
                full[-1] = (full[-1][0], block)
            else:
                full.append((block, block))
        else:
            partial.append((block, parts))
    lines = [f"/// {line}" for line in doc_lines]
    lines += [f"pub fn {name}(code: Int) -> Bool {{", "  case code / 256 {"]
    for block, parts in partial:
        tests = []
        for low, high in parts:
            if low == high:
                tests.append(f"code == 0x{low:x}")
            else:
                tests.append(f"{{ code >= 0x{low:x} && code <= 0x{high:x} }}")
        lines.append(f"    0x{block:x} -> " + " || ".join(tests))
    for low, high in full:
        if low == high:
            lines.append(f"    0x{low:x} -> True")
        else:
            lines.append(f"    block if block >= 0x{low:x} && block <= 0x{high:x} -> True")
    lines += ["    _ -> False", "  }", "}", ""]
    return lines


def render(categories, word_break, sentence_break):
    lines = [
        f"//// Generated by scripts/gen_unicode_category.py from Unicode {UNICODE_VERSION}. Do not edit.",
        "//// Sources and SHA-256:",
        f"//// {UNICODE_URL} {UNICODE_SHA256}",
        f"//// {WORD_BREAK_URL} {WORD_BREAK_SHA256}",
        f"//// {SENTENCE_BREAK_URL} {SENTENCE_BREAK_SHA256}",
        "",
    ]
    lines += render_function(
        "is_non_letter",
        ["True for code points above U+007F that are not letters, marks,",
         "decimal digits or letter numbers, including unassigned code points."],
        non_letter_ranges(categories),
    )
    lines += render_function(
        "is_word_format",
        ["True for Word_Break=Format code points, which do not split a word (WB4)."],
        property_ranges(word_break, {"Format"}),
    )
    lines += render_function(
        "is_word_numeric",
        ["True for Word_Break=Numeric code points."],
        property_ranges(word_break, {"Numeric"}),
    )
    lines += render_function(
        "joins_letters",
        ["True for Word_Break=MidLetter, MidNumLet and Single_Quote code points,",
         "which join two letters into one word (WB6, WB7)."],
        property_ranges(word_break, {"MidLetter", "MidNumLet", "Single_Quote"}),
    )
    lines += render_function(
        "joins_numbers",
        ["True for Word_Break=MidNum, MidNumLet and Single_Quote code points,",
         "which join two digits into one number (WB11, WB12)."],
        property_ranges(word_break, {"MidNum", "MidNumLet", "Single_Quote"}),
    )
    lines += render_function(
        "is_sentence_close",
        ["True for Sentence_Break=Close code points, the quotation marks and",
         "brackets that may follow a sentence terminator (SB9)."],
        property_ranges(sentence_break, {"Close"}),
    )
    return "\n".join(lines)


def read_checked(path, label, expected):
    data = path.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    if digest != expected:
        raise ValueError(f"Unicode {UNICODE_VERSION} {label} SHA-256 mismatch: expected {expected}, got {digest}")
    return data.decode("utf-8")


def generate(unicode_data, word_break_property, sentence_break_property, output, check=False):
    unicode_text = read_checked(unicode_data, "UnicodeData.txt", UNICODE_SHA256)
    word_text = read_checked(word_break_property, "WordBreakProperty.txt", WORD_BREAK_SHA256)
    sentence_text = read_checked(sentence_break_property, "SentenceBreakProperty.txt", SENTENCE_BREAK_SHA256)
    source = render(
        parse_unicode_data(unicode_text),
        parse_property_file(word_text, "WordBreakProperty", WORD_BREAK_VALUES),
        parse_property_file(sentence_text, "SentenceBreakProperty", SENTENCE_BREAK_VALUES),
    )
    version = subprocess.run(["gleam", "--version"], check=True, capture_output=True, text=True).stdout.strip()
    if version != f"gleam {GLEAM_VERSION}":
        raise ValueError(f"generation requires gleam {GLEAM_VERSION}; found {version!r}")
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w", encoding="utf-8", newline="\n", suffix=".gleam",
            prefix=f".{output.name}.", dir=None if check else output.parent, delete=False,
        ) as handle:
            temporary = Path(handle.name)
            handle.write(source)
        subprocess.run(["gleam", "format", str(temporary)], check=True, capture_output=True, text=True)
        if check:
            if temporary.read_bytes() != output.read_bytes():
                raise ValueError(f"generated output differs from {output}; regenerate it")
        else:
            mode = output.stat().st_mode & 0o777 if output.exists() else 0o644
            temporary.chmod(mode)
            os.replace(temporary, output)
    finally:
        if temporary is not None:
            temporary.unlink(missing_ok=True)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--unicode-data", type=Path, required=True)
    parser.add_argument("--word-break-property", type=Path, required=True)
    parser.add_argument("--sentence-break-property", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args(argv)
    try:
        generate(
            arguments.unicode_data,
            arguments.word_break_property,
            arguments.sentence_break_property,
            arguments.output,
            arguments.check,
        )
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        detail = error.stderr if isinstance(error, subprocess.CalledProcessError) else str(error)
        print(f"Unicode table generation failed: {detail or error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
