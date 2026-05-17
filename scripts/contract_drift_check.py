#!/usr/bin/env python3
"""contract_drift_check.py — syntactic contract-drift gate for research-executor P4c.

Confirms that every name the test file imports from the workload module is actually
defined in the workload. This catches the parallelization failure mode where
Author-Code and Author-Tests disagree on a function name and the test file's
imports would fail at pytest-collection time.

Usage:
    contract_drift_check.py --workload <workload.py> --tests <tests/test_x.py> \\
                            --module-name <workload_module_basename>

Arguments:
    --workload        Path to the workload .py file written by Author-Code.
    --tests           Path to the test .py file written by Author-Tests.
    --module-name     Module name as it appears in `from <name> import ...` in the
                      test file. Typically the workload filename without ".py".

Exit codes:
    0   agreement — every test-imported name is defined in the workload.
    1   contract drift — at least one test import does not resolve. The drifted
        names are printed to stdout (one per line) for the orchestrator to relay
        back into the re-spawn prompt.
    2   bad arguments or unreadable files.

Referenced by SKILL.md Phase 4 Step 4c (cross-cutting rule informally implied by P4 design).
"""

import argparse
import ast
import sys


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--workload", required=True)
    ap.add_argument("--tests", required=True)
    ap.add_argument("--module-name", required=True)
    args = ap.parse_args()

    try:
        workload_src = open(args.workload).read()
        tests_src = open(args.tests).read()
    except OSError as e:
        print(f"could not read input file: {e}", file=sys.stderr)
        sys.exit(2)

    try:
        workload_tree = ast.parse(workload_src)
        tests_tree = ast.parse(tests_src)
    except SyntaxError as e:
        print(f"syntax error in input: {e}", file=sys.stderr)
        sys.exit(2)

    workload_names = {
        n.name
        for n in ast.walk(workload_tree)
        if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))
    }

    test_imports = set()
    for n in ast.walk(tests_tree):
        if isinstance(n, ast.ImportFrom) and n.module and n.module.endswith(args.module_name):
            test_imports.update(a.name for a in n.names)

    missing = test_imports - workload_names

    if missing:
        print("CONTRACT DRIFT — tests import names workload does not expose:")
        for name in sorted(missing):
            print(name)
        sys.exit(1)

    print("contract check passed")
    sys.exit(0)


if __name__ == "__main__":
    main()
