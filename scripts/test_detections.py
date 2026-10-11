#!/usr/bin/env python3
"""Local contracts plus optional native CLI tests. Never authenticates or syncs."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile

import yaml

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "tests/detection-tests.json"


def safe_file(relative: str, root: Path = ROOT) -> Path:
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise ValueError("Expected a repository-relative file")
    path = (root / relative).resolve()
    if not path.is_relative_to(root.resolve()) or not path.is_file():
        raise ValueError(f"Missing file or path outside repository: {relative}")
    return path


def load_cases(manifest: Path = MANIFEST, root: Path = ROOT) -> list[dict]:
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if data.get("schema_version") != 1 or not isinstance(data.get("cases"), list) or not data["cases"]:
        raise ValueError("Manifest requires schema_version 1 and non-empty cases")
    names = set()
    for case in data["cases"]:
        if set(case) != {"name", "detection_file", "input_file", "expected_matches"}:
            raise ValueError("Unknown or missing case fields")
        if not isinstance(case["name"], str) or not case["name"] or case["name"] in names:
            raise ValueError("Case names must be non-empty and unique")
        names.add(case["name"])
        safe_file(case["detection_file"], root)
        events = read_events(safe_file(case["input_file"], root))
        expected = case["expected_matches"]
        if not isinstance(expected, list) or len(expected) != len(events) or any(type(x) is not bool for x in expected):
            raise ValueError("Every input line needs one boolean expected_matches entry")
    return data["cases"]


def read_events(path: Path) -> list[dict]:
    lines = path.read_text(encoding="utf-8").splitlines()
    if not lines or any(not line.strip() for line in lines):
        raise ValueError("Fixtures must contain non-empty NDJSON object lines")
    events = [json.loads(line) for line in lines]
    if any(not isinstance(event, dict) for event in events):
        raise ValueError("Every fixture line must be a JSON object")
    return events


def simple_contract_match(rule: dict, event: dict) -> bool:
    """Only this demo's exact-equality selection, NOT a Sigma engine."""
    detection = rule["detection"]
    if set(detection) != {"selection", "condition"} or detection["condition"] != "selection":
        raise ValueError("Contract evaluator only supports a single selection")
    for field, wanted in detection["selection"].items():
        if "|" in field:
            raise ValueError("Contract evaluator does not support Sigma modifiers")
        actual = event
        for key in field.split("."):
            if not isinstance(actual, dict) or key not in actual:
                return False
            actual = actual[key]
        if isinstance(wanted, list):
            if actual not in wanted:
                return False
        elif actual != wanted:
            return False
    return True


def validate_native_result(returncode: int, stdout: str, stderr: str, title: str, expected: list[bool]) -> None:
    """Expected match is rc=1, but an rc=1 engine error must never pass."""
    expected_code = 1 if any(expected) else 0
    if returncode != expected_code:
        raise ValueError(f"Expected exit {expected_code}, received {returncode}")
    line_pattern = re.compile(r"line ([1-9][0-9]*) (matches|does not match) detection " + re.escape(title))
    observed = {}
    # Curated CLI output is documented as one text result per input line. API commands
    # use JSON instead. Fail closed if this contract changes; never guess success.
    for line in (stdout + "\n" + stderr).splitlines():
        if not line.strip():
            continue
        match = line_pattern.fullmatch(line.strip())
        if not match:
            raise ValueError("Unexpected native output (possible engine error or CLI format change): " + line[:240])
        number = int(match.group(1))
        if number in observed:
            raise ValueError("Duplicate native event result")
        observed[number] = match.group(2) == "matches"
    wanted = dict(enumerate(expected, 1))
    if observed != wanted:
        raise ValueError(f"Per-event outcomes differ: expected {wanted}, received {observed}")


def contract_check() -> list[dict]:
    cases = load_cases()
    covered = set()
    saw_match = saw_nonmatch = False
    for case in cases:
        path = safe_file(case["detection_file"])
        covered.add(path)
        rule = yaml.safe_load(path.read_text(encoding="utf-8"))
        if not rule.get("title") or rule.get("sourcetypes") != ["aws-waf"] or rule.get("disabled") is not True:
            raise ValueError("Demo rules must be named, source-scoped, and disabled for deployment")
        events = read_events(safe_file(case["input_file"]))
        actual = [simple_contract_match(rule, event) for event in events]
        if actual != case["expected_matches"]:
            raise ValueError(f"Fixture contract differs for {case['name']}")
        saw_match |= any(actual)
        saw_nonmatch |= not all(actual)
    if covered != set((ROOT / "detections/sigma").glob("*.yaml")) or not (saw_match and saw_nonmatch):
        raise ValueError("Every Sigma rule needs coverage, including positive and negative events")
    sql_configs = list((ROOT / "detections/sql").glob("*.yaml"))
    if len(sql_configs) != 2:
        raise ValueError("Expected both WAF and ALB SQL examples")
    for path in sql_configs:
        config = yaml.safe_load(path.read_text(encoding="utf-8"))
        if config.get("disabled") is not True or config.get("schedule") != "*/5 * * * *":
            raise ValueError("SQL examples must remain disabled with an explicit schedule")
        sql_path = safe_file(str((path.parent / config["file"]).relative_to(ROOT)))
        sql = sql_path.read_text(encoding="utf-8")
        if "receivedAt >= {from:DateTime}" not in sql or "receivedAt < {to:DateTime}" not in sql:
            raise ValueError("SQL examples require half-open receivedAt windows")
        if config.get("notificationNames") != [] or config.get("autoTriage") is not False:
            raise ValueError("Demos must not route alerts or enable automatic triage")
    print(f"Contract checks passed: {len(cases)} fixture cases, {sum(len(c['expected_matches']) for c in cases)} events, {len(sql_configs)} SQL configs (not SQL execution)")
    return cases


def native_check(cli: Path, cases: list[dict]) -> None:
    if not cli.is_file():
        raise ValueError("Native CLI executable does not exist")
    if os.environ.get("RUNREVEAL_TOKEN"):
        raise ValueError("Remove RUNREVEAL_TOKEN for offline native validation")
    environment = {key: value for key, value in os.environ.items() if not key.startswith("RUNREVEAL_")}
    with tempfile.TemporaryDirectory(prefix="runreveal-offline-") as config_dir:
        environment["XDG_CONFIG_HOME"] = config_dir
        # Avoid selecting a desktop user's previously authenticated keychain profile.
        environment["RUNREVEAL_PROFILE"] = Path(config_dir).name
        # v2026.9.1 checks that token/workspace settings exist even for local commands.
        # This sentinel is deliberately NOT a credential. It never goes to RunReveal:
        # bind the CLI API URL to an unusable loopback endpoint, so accidental API
        # dependencies fail closed instead of consulting a real profile or workspace.
        environment["RUNREVEAL_TOKEN"] = "offline-fixture-not-a-credential"
        environment["RUNREVEAL_WORKSPACE"] = "offline-validation"
        environment["RUNREVEAL_BASEURL"] = "http://127.0.0.1:1"
        for kind in ("sigma", "sql"):
            result = subprocess.run([str(cli), "lint", kind, f"detections/{kind}"], cwd=ROOT, env=environment,
                                    capture_output=True, text=True, timeout=60, check=False)
            if result.returncode != 0:
                raise ValueError(f"Native {kind} lint failed: {(result.stdout + result.stderr)[:2000]}")
            print(f"Native {kind} lint passed")
        for case in cases:
            rule = yaml.safe_load(safe_file(case["detection_file"]).read_text(encoding="utf-8"))
            result = subprocess.run([str(cli), "detections", "run", "-f", case["detection_file"], "-i", case["input_file"]],
                                    cwd=ROOT, env=environment, capture_output=True, text=True, timeout=60, check=False)
            validate_native_result(result.returncode, result.stdout, result.stderr, rule["title"], case["expected_matches"])
            print(f"Native fixture passed: {case['name']}")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--native", type=Path, help="Path to checksum-pinned RunReveal CLI; does not sync")
    args = parser.parse_args()
    try:
        cases = contract_check()
        if args.native:
            native_check(args.native.resolve(), cases)
    except (ValueError, KeyError, TypeError, OSError, yaml.YAMLError, subprocess.TimeoutExpired) as exc:
        print(f"FAIL: {exc}")
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
