"""Tests for fixed Unicode input parsing and failure-safe table generation."""

import contextlib
import hashlib
import io
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest import mock

import gen_unicode_category as generator

WORD_BREAK = "0027 ; Single_Quote # Po APOSTROPHE\n00AD ; Format # Cf SOFT HYPHEN\n0030..0039 ; Numeric # Nd DIGITS\n"
SENTENCE_BREAK = "0022 ; Close # Po QUOTATION MARK\n"


def row(code, name, category):
    return ";".join([f"{code:04X}", name, category] + [""] * 12)


class UnicodeDataTests(unittest.TestCase):
    def test_first_last_interiors_boundaries_and_omitted_points(self):
        data = "\n".join([
            row(0x100, "BEFORE", "Po"),
            row(0x101, "<Example, First>", "Lo"),
            row(0x103, "<Example, Last>", "Lo"),
            row(0x104, "AFTER", "No"),
        ])
        categories = generator.parse_unicode_data(data)
        self.assertEqual(categories[0xFF:0x106], ["Cn", "Po", "Lo", "Lo", "Lo", "No", "Cn"])
        self.assertEqual(categories[0x10FFFF], "Cn")
        ranges = generator.non_letter_ranges(categories)
        self.assertEqual(ranges, [(0x80, 0x100), (0x104, 0x10FFFF)])

    def test_category_policy_keeps_only_letters_marks_and_two_number_classes(self):
        categories = generator.parse_unicode_data("\n".join(
            row(0x100 + index, f"ITEM {index}", category)
            for index, category in enumerate(["Lu", "Ll", "Lt", "Lm", "Lo", "Mn", "Mc", "Me", "Nd", "Nl", "No", "So", "Cf", "Cn"])
        ))
        self.assertEqual(generator.non_letter_ranges(categories), [(0x80, 0xFF), (0x10A, 0x10FFFF)])

    def test_invalid_ranges_are_rejected(self):
        first = row(0x100, "<Example, First>", "Lo")
        cases = [
            first,
            row(0x102, "<Example, Last>", "Lo"),
            first + "\n" + row(0x102, "<Other, Last>", "Lo"),
            first + "\n" + row(0x102, "<Example, Last>", "Mn"),
            first + "\n" + row(0x102, "<Other, First>", "Lo"),
            first + "\n" + row(0x102, "NORMAL", "Lo"),
            first + "\n" + row(0xFF, "<Example, Last>", "Lo"),
            first + "\n" + row(0x100, "<Example, Last>", "Lo"),
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                generator.parse_unicode_data(text)

    def test_malformed_rows_are_rejected(self):
        cases = [
            "0041;A;Lu", row(0x110000, "OUTSIDE", "Lo"),
            row(0x100, "BAD CATEGORY", "Unknown"),
            row(0x100, "A", "Lo") + "\n" + row(0x100, "B", "Lo"),
            row(0x102, "A", "Lo") + "\n" + row(0x101, "B", "Lo"),
            row(0x100, "A", "Lo").replace("0100;", "NOTHEX;"),
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                generator.parse_unicode_data(text)


class PropertyFileTests(unittest.TestCase):
    def test_ranges_single_points_and_comments(self):
        properties = generator.parse_property_file(
            "# header\n\n0041..0043 ; ALetter # Lu\n0027 ; Single_Quote\n",
            "WordBreakProperty", generator.WORD_BREAK_VALUES,
        )
        self.assertEqual(properties, {0x41: "ALetter", 0x42: "ALetter", 0x43: "ALetter", 0x27: "Single_Quote"})
        self.assertEqual(generator.property_ranges(properties, {"ALetter"}), [(0x41, 0x43)])

    def test_malformed_property_rows_are_rejected(self):
        cases = [
            "0041 ; Unknown",
            "0041",
            "0043..0041 ; ALetter",
            "110000 ; ALetter",
            "XYZ ; ALetter",
            "0041 ; ALetter\n0041 ; Numeric",
        ]
        for text in cases:
            with self.subTest(text=text), self.assertRaises(ValueError):
                generator.parse_property_file(text, "WordBreakProperty", generator.WORD_BREAK_VALUES)

    def test_rendered_module_has_every_table(self):
        source = generator.render(
            generator.parse_unicode_data(row(0x100, "LETTER", "Lo")),
            generator.parse_property_file(WORD_BREAK, "WordBreakProperty", generator.WORD_BREAK_VALUES),
            generator.parse_property_file(SENTENCE_BREAK, "SentenceBreakProperty", generator.SENTENCE_BREAK_VALUES),
        )
        for name in ["is_non_letter", "is_word_format", "is_word_numeric", "joins_letters", "joins_numbers", "is_sentence_close"]:
            self.assertIn(f"pub fn {name}(code: Int) -> Bool", source)
        self.assertIn("0x0 -> code == 0x22", source)
        self.assertIn("0x0 -> { code >= 0x30 && code <= 0x39 }", source)


class OutputSafetyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.input = self.root / "UnicodeData.txt"
        self.word_break = self.root / "WordBreakProperty.txt"
        self.sentence_break = self.root / "SentenceBreakProperty.txt"
        self.output = self.root / "category.gleam"
        self.input.write_text(row(0x100, "LETTER", "Lo") + "\n", encoding="utf-8")
        self.word_break.write_text(WORD_BREAK, encoding="utf-8")
        self.sentence_break.write_text(SENTENCE_BREAK, encoding="utf-8")
        self.output.write_bytes(b"sentinel\n")
        self.digest = hashlib.sha256(self.input.read_bytes()).hexdigest()
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(generator, "WORD_BREAK_SHA256", hashlib.sha256(self.word_break.read_bytes()).hexdigest()).start()
        mock.patch.object(generator, "SENTENCE_BREAK_SHA256", hashlib.sha256(self.sentence_break.read_bytes()).hexdigest()).start()

    def run_cli(self, check=False):
        self.expected_candidate_parent = Path(tempfile.gettempdir()) if check else self.output.parent
        arguments = [
            "--unicode-data", str(self.input),
            "--word-break-property", str(self.word_break),
            "--sentence-break-property", str(self.sentence_break),
            "--output", str(self.output),
        ]
        if check:
            arguments.append("--check")
        with contextlib.redirect_stderr(io.StringIO()) as messages:
            status = generator.main(arguments)
        return status, messages.getvalue()

    def assert_preserved(self):
        self.assertEqual(self.output.read_bytes(), b"sentinel\n")
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), INPUT_NAMES)

    def formatter(self, arguments, **kwargs):
        if arguments == ["gleam", "--version"]:
            return subprocess.CompletedProcess(arguments, 0, "gleam 1.19.2\n", "")
        self.assertEqual(arguments[:2], ["gleam", "format"])
        temporary = Path(arguments[2])
        self.assertEqual(temporary.parent, self.expected_candidate_parent)
        self.assertEqual(temporary.suffix, ".gleam")
        self.assertNotIn(b"\r", temporary.read_bytes())
        # Reopening also checks that the writer is closed before formatting.
        temporary.write_bytes(temporary.read_bytes())
        return subprocess.CompletedProcess(arguments, 0, "", "")

    def test_hash_mismatch_preserves_output_without_starting_formatter(self):
        with mock.patch.object(generator.subprocess, "run") as run:
            status, message = self.run_cli()
        self.assertEqual(status, 1)
        self.assertIn("SHA-256 mismatch", message)
        run.assert_not_called()
        self.assert_preserved()

    def test_missing_input_preserves_output(self):
        self.input.unlink()
        status, _ = self.run_cli()
        self.assertEqual(status, 1)
        self.assertEqual(self.output.read_bytes(), b"sentinel\n")
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), [name for name in INPUT_NAMES if name != "UnicodeData.txt"])

    def test_invalid_input_preserves_output_before_formatter(self):
        self.input.write_text(row(0x100, "<Example, First>", "Lo"), encoding="utf-8")
        with mock.patch.object(generator, "UNICODE_SHA256", hashlib.sha256(self.input.read_bytes()).hexdigest()), mock.patch.object(generator.subprocess, "run") as run:
            status, message = self.run_cli()
        self.assertEqual(status, 1)
        self.assertIn("unterminated", message)
        run.assert_not_called()
        self.assert_preserved()

    def test_wrong_formatter_version_preserves_output(self):
        with mock.patch.object(generator, "UNICODE_SHA256", self.digest), mock.patch.object(generator.subprocess, "run", return_value=subprocess.CompletedProcess([], 0, "gleam 1.14.0\n", "")):
            status, message = self.run_cli()
        self.assertEqual(status, 1)
        self.assertIn("requires gleam 1.19.2", message)
        self.assert_preserved()

    def test_formatter_failure_removes_temporary_and_preserves_output(self):
        def fail_format(arguments, **kwargs):
            result = self.formatter(arguments, **kwargs)
            if arguments[1] == "format":
                raise subprocess.CalledProcessError(1, arguments, stderr="format failed")
            return result
        with mock.patch.object(generator, "UNICODE_SHA256", self.digest), mock.patch.object(generator.subprocess, "run", side_effect=fail_format):
            status, message = self.run_cli()
        self.assertEqual(status, 1)
        self.assertIn("format failed", message)
        self.assert_preserved()

    def test_check_mismatch_removes_temporary_and_preserves_output(self):
        with mock.patch.object(generator, "UNICODE_SHA256", self.digest), mock.patch.object(generator.subprocess, "run", side_effect=self.formatter):
            status, message = self.run_cli(check=True)
        self.assertEqual(status, 1)
        self.assertIn("differs", message)
        self.assert_preserved()

    def test_replace_failure_removes_temporary_and_preserves_output(self):
        with mock.patch.object(generator, "UNICODE_SHA256", self.digest), mock.patch.object(generator.subprocess, "run", side_effect=self.formatter), mock.patch.object(generator.os, "replace", side_effect=PermissionError("replace denied")):
            status, _ = self.run_cli()
        self.assertEqual(status, 1)
        self.assert_preserved()

    def test_success_is_reproducible_and_check_does_not_replace_output(self):
        with mock.patch.object(generator, "UNICODE_SHA256", self.digest), mock.patch.object(generator.subprocess, "run", side_effect=self.formatter):
            self.assertEqual(self.run_cli()[0], 0)
            first = self.output.read_bytes()
            self.assertEqual(self.run_cli()[0], 0)
            self.assertEqual(self.output.read_bytes(), first)
            with mock.patch.object(generator.os, "replace") as replace:
                self.assertEqual(self.run_cli(check=True)[0], 0)
                replace.assert_not_called()
        self.assertIn(b"Unicode 17.0.0", first)
        self.assertIn(self.digest.encode(), first)
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), INPUT_NAMES)

    def test_property_hash_mismatch_preserves_output_without_starting_formatter(self):
        self.word_break.write_text(WORD_BREAK + "0041 ; ALetter\n", encoding="utf-8")
        with mock.patch.object(generator, "UNICODE_SHA256", self.digest), mock.patch.object(generator.subprocess, "run") as run:
            status, message = self.run_cli()
        self.assertEqual(status, 1)
        self.assertIn("WordBreakProperty.txt SHA-256 mismatch", message)
        run.assert_not_called()
        self.assert_preserved()


INPUT_NAMES = ["SentenceBreakProperty.txt", "UnicodeData.txt", "WordBreakProperty.txt", "category.gleam"]


if __name__ == "__main__":
    unittest.main()
