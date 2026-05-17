#!/usr/bin/env bash
# data_quality_scan.sh — mechanical data-quality scan for research-executor P6 Step 6.1.
#
# Runs five deterministic checks across the output dirs and plot dirs of a completed P5 run,
# writes a markdown report to ./tmp/data_quality_scan.md with three sections:
#   - Flags raised
#   - All-clear checks
#   - What to ask advisor about
#
# Usage:
#   data_quality_scan.sh --output-dirs <dir1> [<dir2> ...] --plot-dirs <dir1> [<dir2> ...]
#
# Exit codes:
#   0 always — this is an audit, never an error. Caller reads the markdown for findings.
#
# Referenced by SKILL.md Phase 6 (cross-cutting rule #15).

set -u

OUTPUT_DIRS=()
PLOT_DIRS=()
REPORT="./tmp/data_quality_scan.md"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output-dirs)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do OUTPUT_DIRS+=("$1"); shift; done
      ;;
    --plot-dirs)
      shift
      while [[ $# -gt 0 && "$1" != --* ]]; do PLOT_DIRS+=("$1"); shift; done
      ;;
    --report) REPORT="$2"; shift 2 ;;
    *) echo "unknown arg: $1" >&2; exit 1 ;;
  esac
done

mkdir -p "$(dirname "$REPORT")"

python3 - "$REPORT" "${OUTPUT_DIRS[@]}" "--plot-dirs--" "${PLOT_DIRS[@]}" <<'PY'
import sys, os, glob
import pandas as pd
import numpy as np

report_path = sys.argv[1]
sep = sys.argv.index("--plot-dirs--")
output_dirs = sys.argv[2:sep]
plot_dirs = sys.argv[sep + 1:]

flags = []
all_clear = []

suspicious_values = [0.95, 0.99, 1.00, 0.90, 0.50]

# 1. NaN / Inf scan
nan_inf_clean = True
for d in output_dirs:
    for f in glob.glob(os.path.join(d, "*.csv")):
        try:
            df = pd.read_csv(f)
        except Exception as e:
            flags.append(f"`{f}` failed to parse as CSV: {e}")
            continue
        n_nan = int(df.isna().sum().sum())
        n_inf = int(np.isinf(df.select_dtypes(include=[np.number])).sum().sum())
        if n_nan or n_inf:
            flags.append(f"`{f}` contains NaN={n_nan} Inf={n_inf}")
            nan_inf_clean = False
if nan_inf_clean:
    all_clear.append("NaN/Inf scan: all CSVs clean")

# 2. Plot file sizes — flag every PNG < 5 KB
small_plots = []
for d in plot_dirs:
    for f in glob.glob(os.path.join(d, "*.png")):
        size = os.path.getsize(f)
        if size < 5 * 1024:
            small_plots.append(f"`{f}` is only {size} bytes — likely broken render")
if small_plots:
    flags.extend(small_plots)
else:
    all_clear.append("Plot file sizes: all PNGs ≥ 5 KB")

# 3. Single-class predictions
single_class_clean = True
for d in output_dirs:
    for f in glob.glob(os.path.join(d, "*.csv")):
        try:
            df = pd.read_csv(f)
        except Exception:
            continue
        for col in df.columns:
            if df[col].dtype in ["int64", "bool"] and df[col].nunique() == 1:
                v = df[col].iloc[0]
                flags.append(f"`{f}::{col}` is constant (value={v}) — possible degenerate prediction")
                single_class_clean = False
if single_class_clean:
    all_clear.append("Single-class scan: no constant integer/bool columns found")

# 4. Suspiciously round numbers
suspicious_clean = True
for d in output_dirs:
    for f in glob.glob(os.path.join(d, "*.csv")):
        try:
            df = pd.read_csv(f)
        except Exception:
            continue
        for col in df.select_dtypes(include=["float64"]).columns:
            for v in suspicious_values:
                n = int((df[col] == v).sum())
                if n >= 2:
                    flags.append(
                        f"`{f}::{col}` has {n} rows exactly equal to {v} — verify real value, not floor/ceiling clipping"
                    )
                    suspicious_clean = False
if suspicious_clean:
    all_clear.append("Suspicious-round-number scan: no telltale clipping patterns")

# 5. Row count sanity (advisory only — we just report)
row_counts = []
for d in output_dirs:
    for f in sorted(glob.glob(os.path.join(d, "*.csv"))):
        try:
            with open(f) as fh:
                n = sum(1 for _ in fh)
        except Exception:
            continue
        row_counts.append(f"  - `{f}`: {n} lines (incl. header)")

ask_advisor = []
if flags:
    ask_advisor.append("Are any of the flagged issues genuine quality problems vs expected artifacts of the experimental design?")
if row_counts:
    ask_advisor.append("Do the row counts above match what the goal spec expects per CSV?")

with open(report_path, "w") as out:
    out.write("# Data-quality scan\n\n")
    out.write("## Flags raised\n\n")
    if flags:
        for line in flags:
            out.write(f"- {line}\n")
    else:
        out.write("_None._\n")
    out.write("\n## All-clear checks\n\n")
    for line in all_clear:
        out.write(f"- {line}\n")
    out.write("\n## Row counts (advisory)\n\n")
    for line in row_counts:
        out.write(line + "\n")
    out.write("\n## What to ask advisor about\n\n")
    if ask_advisor:
        for line in ask_advisor:
            out.write(f"- {line}\n")
    else:
        out.write("_No follow-up questions — all checks clean._\n")

print(f"wrote {report_path}: {len(flags)} flag(s), {len(all_clear)} all-clear check(s)")
PY
