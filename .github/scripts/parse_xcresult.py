#!/usr/bin/env python3
import argparse
import json
import os
import subprocess
import sys


def load_json(path: str) -> dict | None:
    if not path or not os.path.exists(path) or os.path.getsize(path) == 0:
        print("xcresult JSON is empty.")
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle)


def emit_issues(issues: dict, key: str, label: str) -> bool:
    items = issues.get(key, {}).get("_values") or []
    for item in items:
        name = item.get("testCaseName", {}).get("_value")
        message = item.get("message", {}).get("_value")
        location = item.get("documentLocationInCreatingWorkspace", {}).get("url", {}).get("_value")
        if name or message:
            prefix = f"{label} {name}:" if name else f"{label}:"
            print(f"- {prefix} {message}")
        if location:
            print(f"  {location}")
    return bool(items)


def emit_all_issues(issues: dict) -> bool:
    printed = False
    for key, label in (
        ("testFailureSummaries", "Test"),
        ("errorSummaries", "Error"),
        ("warningSummaries", "Warning"),
        ("globalIssueSummaries", "Global"),
        ("analyzerWarningSummaries", "Analyzer"),
    ):
        printed = emit_issues(issues, key, label) or printed
    return printed


def extract_tests_ref(data: dict) -> str:
    for action in data.get("actions", {}).get("_values") or []:
        ref = action.get("actionResult", {}).get("testsRef", {}).get("id", {}).get("_value", "")
        if ref:
            return ref
    return ""


def load_tests_ref(bundle_path: str, tests_ref: str) -> dict | None:
    if not bundle_path or not tests_ref:
        return None
    try:
        result = subprocess.run(
            [
                "xcrun",
                "xcresulttool",
                "get",
                "object",
                "--legacy",
                "--path",
                bundle_path,
                "--format",
                "json",
                "--id",
                tests_ref,
            ],
            check=True,
            capture_output=True,
            text=True,
        )
    except subprocess.CalledProcessError:
        print(f"xcresulttool failed to read testsRef {tests_ref}")
        return None
    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        print("Failed to decode testsRef JSON.")
        return None


def collect_failing_tests(node: object, failures: set[str]) -> None:
    if isinstance(node, dict):
        status = node.get("testStatus", {}).get("_value")
        if status in {"Failure", "Failed"}:
            name = node.get("identifier", {}).get("_value") or node.get("name", {}).get("_value")
            if name:
                failures.add(name)
        for value in node.values():
            collect_failing_tests(value, failures)
    elif isinstance(node, list):
        for value in node:
            collect_failing_tests(value, failures)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--xcresult-json", required=True)
    parser.add_argument("--bundle", required=True)
    args = parser.parse_args()

    data = load_json(args.xcresult_json)
    if data is None:
        return 0

    printed_any = False
    actions = data.get("actions", {}).get("_values") or []
    if not actions:
        print("No actions found in xcresult.")

    for action in actions:
        if emit_all_issues(action.get("actionResult", {}).get("issues", {})):
            printed_any = True
        if emit_all_issues(action.get("buildResult", {}).get("issues", {})):
            printed_any = True

    if not printed_any:
        print("No issue summaries found in xcresult.")

    tests_ref = extract_tests_ref(data)
    if not tests_ref:
        print("No testsRef found in xcresult.")
        return 0

    tests_data = load_tests_ref(args.bundle, tests_ref)
    if tests_data is None:
        return 0

    failures: set[str] = set()
    collect_failing_tests(tests_data, failures)
    if failures:
        print("Failing tests (testsRef):")
        for name in sorted(failures):
            print(f"- {name}")
    else:
        print("No failing tests found in testsRef.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
