"""Offline contract and harness regression tests; not a replacement Sigma engine."""

import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location("detection_runner", ROOT / "scripts/test_detections.py")
RUNNER = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(RUNNER)
TITLE = "AWS WAF Blocked Admin Request"


class RepositoryContracts(unittest.TestCase):
    def test_all_checked_in_contracts(self):
        self.assertEqual(len(RUNNER.contract_check()), 4)

    def test_absolute_path_is_rejected(self):
        with self.assertRaises(ValueError):
            RUNNER.safe_file(str(ROOT / "tests/detection-tests.json"))

    def test_path_traversal_is_rejected(self):
        with self.assertRaises(ValueError):
            RUNNER.safe_file("../Website-redesign/package.json")

    def test_missing_file_is_rejected(self):
        with self.assertRaises(ValueError):
            RUNNER.safe_file("fixtures/does-not-exist.ndjson")

    def test_missing_and_null_never_match_string(self):
        rule = {"detection": {"selection": {"a.b": "value"}, "condition": "selection"}}
        for event in ({}, {"a": None}, {"a": {"b": None}}, {"a": {"b": "other"}}):
            with self.subTest(event=event):
                self.assertFalse(RUNNER.simple_contract_match(rule, event))

    def test_contract_evaluator_rejects_unsupported_condition(self):
        rule = {"detection": {"selection": {"a": "value"}, "condition": "not selection"}}
        with self.assertRaises(ValueError):
            RUNNER.simple_contract_match(rule, {"a": "value"})

    def test_contract_evaluator_rejects_unsupported_modifier(self):
        rule = {"detection": {"selection": {"a|contains": "value"}, "condition": "selection"}}
        with self.assertRaises(ValueError):
            RUNNER.simple_contract_match(rule, {"a": "value"})

    def test_empty_ndjson_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix=".runreveal-test-", dir=ROOT) as directory:
            path = Path(directory) / "empty.ndjson"
            path.write_text("", encoding="utf-8")
            with self.assertRaises(ValueError):
                RUNNER.read_events(path)

    def test_non_object_json_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix=".runreveal-test-", dir=ROOT) as directory:
            path = Path(directory) / "array.ndjson"
            path.write_text("[]\n", encoding="utf-8")
            with self.assertRaises(ValueError):
                RUNNER.read_events(path)

    def test_blank_input_line_is_rejected(self):
        with tempfile.TemporaryDirectory(prefix=".runreveal-test-", dir=ROOT) as directory:
            path = Path(directory) / "blank.ndjson"
            path.write_text('{}\n\n{}\n', encoding="utf-8")
            with self.assertRaises(ValueError):
                RUNNER.read_events(path)

    def test_numeric_expected_result_is_rejected(self):
        data = json.loads(RUNNER.MANIFEST.read_text(encoding="utf-8"))
        data["cases"][0]["expected_matches"][0] = 1
        with tempfile.TemporaryDirectory(prefix=".runreveal-test-", dir=ROOT) as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaises(ValueError):
                RUNNER.load_cases(path)

    def test_duplicate_case_name_is_rejected(self):
        data = json.loads(RUNNER.MANIFEST.read_text(encoding="utf-8"))
        data["cases"][1]["name"] = data["cases"][0]["name"]
        with tempfile.TemporaryDirectory(prefix=".runreveal-test-", dir=ROOT) as directory:
            path = Path(directory) / "manifest.json"
            path.write_text(json.dumps(data), encoding="utf-8")
            with self.assertRaises(ValueError):
                RUNNER.load_cases(path)


class NativeOutputContracts(unittest.TestCase):
    def validate(self, code, output, expected, stderr=""):
        RUNNER.validate_native_result(code, output, stderr, TITLE, expected)

    def test_matching_exit_one_is_success(self):
        self.validate(1, f"line 1 matches detection {TITLE}\n", [True])

    def test_nonmatching_exit_zero_is_success(self):
        self.validate(0, f"line 1 does not match detection {TITLE}\n", [False])

    def test_mixed_lines_are_checked_individually(self):
        self.validate(1, f"line 1 does not match detection {TITLE}\nline 2 matches detection {TITLE}\n", [False, True])

    def test_documented_output_on_stderr_is_accepted(self):
        self.validate(1, "", [True], f"line 1 matches detection {TITLE}")

    def test_error_exit_one_is_not_match_success(self):
        with self.assertRaises(ValueError):
            self.validate(1, "", [True], "Error: invalid detection syntax")

    def test_empty_output_never_passes(self):
        with self.assertRaises(ValueError):
            self.validate(0, "", [False])

    def test_correct_exit_without_all_lines_fails(self):
        with self.assertRaises(ValueError):
            self.validate(1, f"line 1 matches detection {TITLE}", [True, False])

    def test_match_plus_error_fails(self):
        with self.assertRaises(ValueError):
            self.validate(1, f"line 1 matches detection {TITLE}", [True], "Error: malformed second event")

    def test_extra_unknown_output_fails(self):
        with self.assertRaises(ValueError):
            self.validate(1, f"line 1 matches detection {TITLE}\nSkipped malformed event", [True])

    def test_duplicate_line_fails(self):
        with self.assertRaises(ValueError):
            self.validate(1, f"line 1 matches detection {TITLE}\nline 1 matches detection {TITLE}", [True])

    def test_wrong_per_event_result_fails(self):
        with self.assertRaises(ValueError):
            self.validate(1, f"line 1 matches detection {TITLE}\nline 2 matches detection {TITLE}", [True, False])

    def test_unexpected_exit_two_fails(self):
        with self.assertRaises(ValueError):
            self.validate(2, f"line 1 matches detection {TITLE}", [True])

    def test_wrong_title_fails(self):
        with self.assertRaises(ValueError):
            self.validate(1, "line 1 matches detection Another Rule", [True])

    def test_extra_event_fails(self):
        with self.assertRaises(ValueError):
            self.validate(1, f"line 1 matches detection {TITLE}\nline 2 matches detection {TITLE}", [True])

    def test_negative_signal_exit_one_fails(self):
        with self.assertRaises(ValueError):
            self.validate(1, f"line 1 does not match detection {TITLE}", [False])


if __name__ == "__main__":
    unittest.main()
