#!/usr/bin/env bash
# reproducibility_manifest.sh — emit provenance + hash files for a research-executor P5 Runner step.
#
# Modes:
#   --pre   Run before the workload executes. Writes env.txt, git_rev.txt, git_status.txt,
#           inputs.sha256 (hashes of read-only inputs) into the output directory.
#   --post  Run after the workload executes. Writes outputs.sha256 (hashes of every produced
#           .csv, .json, .png) into the output directory.
#
# Usage:
#   reproducibility_manifest.sh --pre  --output-dir <path> --venv <path/to/.venv> [--read-only-inputs <f1> <f2> ...]
#   reproducibility_manifest.sh --post --output-dir <path>
#
# Exit codes:
#   0 success
#   2 pip freeze returned < 10 lines (venv not activated) — caller should STOP
#   3 unknown mode or missing args
#
# Referenced by SKILL.md Phase 5 steps 0.5 and 2.5 (cross-cutting rule #12).

set -u

MODE=""
OUTPUT_DIR=""
VENV=".venv"
READ_ONLY_INPUTS=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --pre) MODE="pre"; shift ;;
    --post) MODE="post"; shift ;;
    --output-dir) OUTPUT_DIR="$2"; shift 2 ;;
    --venv) VENV="$2"; shift 2 ;;
    --read-only-inputs)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do
        READ_ONLY_INPUTS+=("$1"); shift
      done
      ;;
    *) echo "unknown arg: $1" >&2; exit 3 ;;
  esac
done

if [[ -z "$MODE" || -z "$OUTPUT_DIR" ]]; then
  echo "usage: $0 --pre|--post --output-dir <path> [--venv <path>] [--read-only-inputs <files...>]" >&2
  exit 3
fi

mkdir -p "$OUTPUT_DIR"

if [[ "$MODE" == "pre" ]]; then
  "$VENV/bin/python" -m pip freeze > "$OUTPUT_DIR/env.txt"
  n_lines=$(wc -l < "$OUTPUT_DIR/env.txt")
  if [[ "$n_lines" -lt 10 ]]; then
    echo "pip freeze returned $n_lines lines — venv at $VENV not activated. Aborting." >&2
    exit 2
  fi

  git -C . rev-parse HEAD > "$OUTPUT_DIR/git_rev.txt" 2>/dev/null \
    || echo "not a git repo or no commits" > "$OUTPUT_DIR/git_rev.txt"

  git -C . status --porcelain > "$OUTPUT_DIR/git_status.txt" 2>/dev/null \
    || echo "n/a" > "$OUTPUT_DIR/git_status.txt"

  if [[ ${#READ_ONLY_INPUTS[@]} -gt 0 ]]; then
    shasum -a 256 "${READ_ONLY_INPUTS[@]}" > "$OUTPUT_DIR/inputs.sha256" 2>&1
  else
    : > "$OUTPUT_DIR/inputs.sha256"
  fi

  echo "pre-manifest written to $OUTPUT_DIR/{env.txt,git_rev.txt,git_status.txt,inputs.sha256}"
  exit 0
fi

if [[ "$MODE" == "post" ]]; then
  ( cd "$OUTPUT_DIR" && shasum -a 256 *.csv *.json *.png 2>/dev/null > outputs.sha256 ) || true
  echo "post-manifest written to $OUTPUT_DIR/outputs.sha256"
  exit 0
fi

exit 3
