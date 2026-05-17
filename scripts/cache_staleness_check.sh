#!/usr/bin/env bash
# cache_staleness_check.sh — age check for the field-knowledge cache (research-executor P2).
#
# Computes the cache file's age in days. Used by the orchestrator's branching gate to decide
# whether to surface the staleness warning to the user (non-blocking).
#
# Usage:
#   cache_staleness_check.sh --cache-file <path> [--threshold-days 30]
#
# Behavior:
#   - Prints `age_days=<N>` and `created_utc=<ISO>` to stdout (always).
#   - Exit 0 if age ≤ threshold (silent, proceed warm).
#   - Exit 1 if age > threshold (orchestrator surfaces warning).
#   - Exit 2 if cache file missing (cold path, no warning needed).
#
# Referenced by SKILL.md Phase 2 cache-staleness block (cross-cutting rule #14).

set -u

CACHE_FILE=""
THRESHOLD_DAYS=30

while [[ $# -gt 0 ]]; do
  case "$1" in
    --cache-file) CACHE_FILE="$2"; shift 2 ;;
    --threshold-days) THRESHOLD_DAYS="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 3 ;;
  esac
done

if [[ -z "$CACHE_FILE" ]]; then
  echo "usage: $0 --cache-file <path> [--threshold-days 30]" >&2
  exit 3
fi

if [[ ! -f "$CACHE_FILE" ]]; then
  echo "age_days=0"
  echo "created_utc=missing"
  exit 2
fi

# macOS and Linux date differ on -r; below works on macOS. For Linux, replace with `stat -c %Y`.
if [[ "$(uname)" == "Darwin" ]]; then
  mtime_epoch=$(date -r "$CACHE_FILE" +%s)
  created_iso=$(date -r "$CACHE_FILE" -u +"%Y-%m-%dT%H:%M:%SZ")
else
  mtime_epoch=$(stat -c %Y "$CACHE_FILE")
  created_iso=$(date -u -d "@$mtime_epoch" +"%Y-%m-%dT%H:%M:%SZ")
fi

now_epoch=$(date +%s)
age_days=$(( (now_epoch - mtime_epoch) / 86400 ))

echo "age_days=$age_days"
echo "created_utc=$created_iso"

if (( age_days > THRESHOLD_DAYS )); then
  exit 1
fi

exit 0
