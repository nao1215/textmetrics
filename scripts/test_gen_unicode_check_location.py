"""Check-mode isolation and generation-mode atomicity regressions."""

import contextlib
import hashlib
import io
import os
from pathlib import Path
import stat
import subprocess
import tempfile
import unittest
from unittest import mock

import gen_unicode_category as generator


class CandidateLocationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.checkout = self.root / "checkout"
        self.checkout.mkdir()
        self.system_tmp = self.root / "system_tmp"
        self.system_tmp.mkdir()
        self.output = self.checkout / "category.gleam"
        self.output.write_bytes(b"formatted candidate\n")
        self.output.chmod(0o640)
        self.input = self.root / "UnicodeData.txt"
        row = ";".join(["0100", "LETTER", "Lo"] + [""] * 12)
        self.input.write_text(row + "\n", encoding="utf-8")
        self.digest = hashlib.sha256(self.input.read_bytes()).hexdigest()
        self.word_break = self.root / "WordBreakProperty.txt"
        self.word_break.write_text("0027 ; Single_Quote\n", encoding="utf-8")
        self.sentence_break = self.root / "SentenceBreakProperty.txt"
        self.sentence_break.write_text("0022 ; Close\n", encoding="utf-8")
        self.addCleanup(mock.patch.stopall)
        mock.patch.object(generator, "WORD_BREAK_SHA256", hashlib.sha256(self.word_break.read_bytes()).hexdigest()).start()
        mock.patch.object(generator, "SENTENCE_BREAK_SHA256", hashlib.sha256(self.sentence_break.read_bytes()).hexdigest()).start()
        self.candidates = []

    def snapshot(self):
        status = self.output.stat()
        return (self.output.read_bytes(), stat.S_IMODE(status.st_mode), status.st_ino, status.st_mtime_ns)

    def formatter(self, arguments, **kwargs):
        if arguments == ["gleam", "--version"]:
            return subprocess.CompletedProcess(arguments, 0, "gleam 1.19.2\n", "")
        self.assertEqual(arguments[:2], ["gleam", "format"])
        candidate = Path(arguments[2])
        self.assertTrue(candidate.exists())
        self.assertEqual(candidate.suffix, ".gleam")
        self.candidates.append(candidate)
        candidate.write_bytes(b"formatted candidate\n")
        return subprocess.CompletedProcess(arguments, 0, "", "")

    def run_cli(self, check, formatter=None):
        arguments = [
            "--unicode-data", str(self.input),
            "--word-break-property", str(self.word_break),
            "--sentence-break-property", str(self.sentence_break),
            "--output", str(self.output),
        ]
        if check:
            arguments.append("--check")
        with mock.patch.object(generator, "UNICODE_SHA256", self.digest), \
             mock.patch.object(generator.subprocess, "run", side_effect=formatter or self.formatter), \
             mock.patch.object(tempfile, "tempdir", str(self.system_tmp)), \
             contextlib.redirect_stderr(io.StringIO()) as messages:
            status = generator.main(arguments)
        return status, messages.getvalue()

    def make_checkout_read_only(self):
        if os.name != "posix" or os.geteuid() == 0:
            self.skipTest("requires POSIX permissions without root bypass")
        self.checkout.chmod(0o555)
        self.output.chmod(0o444)
        self.addCleanup(self.checkout.chmod, 0o755)
        self.addCleanup(self.output.chmod, 0o640)
        probe = self.checkout / "write_probe"
        try:
            probe.write_bytes(b"permission probe")
        except PermissionError:
            return
        probe.unlink()
        self.skipTest("filesystem does not enforce the read-only directory mode")

    def assert_candidate_cleaned(self, expected_parent):
        self.assertEqual(len(self.candidates), 1)
        self.assertEqual(self.candidates[0].parent, expected_parent)
        self.assertFalse(self.candidates[0].exists())
        self.assertEqual(list(self.system_tmp.iterdir()), [])
        self.assertEqual(list(self.checkout.iterdir()), [self.output])

    def test_check_succeeds_without_writing_read_only_checkout(self):
        self.make_checkout_read_only()
        before = self.snapshot()
        with mock.patch.object(generator.os, "replace", side_effect=AssertionError("check must not replace output")):
            status, message = self.run_cli(check=True)
        self.assertEqual((status, message), (0, ""))
        self.assertEqual(self.snapshot(), before)
        self.assert_candidate_cleaned(self.system_tmp)

    def test_check_mismatch_in_read_only_checkout_preserves_output_and_cleans_candidate(self):
        self.output.write_bytes(b"outdated output\n")
        self.make_checkout_read_only()
        before = self.snapshot()
        status, message = self.run_cli(check=True)
        self.assertEqual(status, 1)
        self.assertIn("differs", message)
        self.assertEqual(self.snapshot(), before)
        self.assert_candidate_cleaned(self.system_tmp)

    def test_check_formatter_failure_cleans_system_candidate_and_preserves_output(self):
        before = self.snapshot()

        def fail_format(arguments, **kwargs):
            result = self.formatter(arguments, **kwargs)
            if arguments[1] == "format":
                raise subprocess.CalledProcessError(1, arguments, stderr="format failed")
            return result

        status, message = self.run_cli(check=True, formatter=fail_format)
        self.assertEqual(status, 1)
        self.assertIn("format failed", message)
        self.assertEqual(self.snapshot(), before)
        self.assert_candidate_cleaned(self.system_tmp)

    def test_generation_keeps_atomic_same_directory_replace_and_output_mode(self):
        self.output.write_bytes(b"old output\n")
        with mock.patch.object(generator.os, "replace", wraps=os.replace) as replace:
            status, message = self.run_cli(check=False)
        self.assertEqual((status, message), (0, ""))
        replace.assert_called_once_with(self.candidates[0], self.output)
        self.assertEqual(self.output.read_bytes(), b"formatted candidate\n")
        self.assertEqual(stat.S_IMODE(self.output.stat().st_mode), 0o640)
        self.assert_candidate_cleaned(self.checkout)


if __name__ == "__main__":
    unittest.main()
