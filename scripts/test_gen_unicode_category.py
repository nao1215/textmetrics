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


class OutputSafetyTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.input = self.root / "UnicodeData.txt"
        self.output = self.root / "category.gleam"
        self.input.write_text(row(0x100, "LETTER", "Lo") + "\n", encoding="utf-8")
        self.output.write_bytes(b"sentinel\n")
        self.digest = hashlib.sha256(self.input.read_bytes()).hexdigest()

    def run_cli(self, check=False):
        arguments = ["--unicode-data", str(self.input), "--output", str(self.output)]
        if check:
            arguments.append("--check")
        with contextlib.redirect_stderr(io.StringIO()) as messages:
            status = generator.main(arguments)
        return status, messages.getvalue()

    def assert_preserved(self):
        self.assertEqual(self.output.read_bytes(), b"sentinel\n")
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ["UnicodeData.txt", "category.gleam"])

    def formatter(self, arguments, **kwargs):
        if arguments == ["gleam", "--version"]:
            return subprocess.CompletedProcess(arguments, 0, "gleam 1.19.2\n", "")
        self.assertEqual(arguments[:2], ["gleam", "format"])
        temporary = Path(arguments[2])
        self.assertEqual(temporary.parent, self.output.parent)
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
        self.assertEqual(list(self.root.iterdir()), [self.output])

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
        self.assertIn(b"Unicode 15.1.0", first)
        self.assertIn(self.digest.encode(), first)
        self.assertEqual(sorted(path.name for path in self.root.iterdir()), ["UnicodeData.txt", "category.gleam"])


if __name__ == "__main__":
    unittest.main()
