# Example — puzzle / contest invocation (strict-summary default)

This shows a typical `/research-executor` invocation for a puzzle-style task where the user wants to drive the analytical conclusion themselves. The Summarizer applies strict phrasing by default; the workload code is direct.

> **Note:** the candidate feature is referenced as `i*` throughout — per the project's `CLAUDE.md` rule "do not propose puzzle answers."

---

## Goal text (what the user pastes after `/research-executor`)

```
Execute METHODOLOGY.md §6 lines 181–198 (geometric characterisation of i*).

Goal: produce the full §6 artifact set characterising the geometry of i* in
layer-L activation space, using intrinsic-dim estimators, PCA, k-means audit,
falsification grid, and a patching causal check.

Deliverables (each CSV with explicit column order; each plot with labeled axes):
  - results/phase1_geometry/intrinsic_dim.csv
      columns: feature, twonn_dim, mle_dim, pca_95_dim, n_samples
  - results/phase1_geometry/per_pc_acc.csv
      columns: feature, pc_index, accuracy, ci_low, ci_high
  - results/phase1_geometry/kmeans_audit.csv
      columns: feature, k, silhouette, ari, n_clusters_recovered
  - results/phase1_geometry/structural_metrics.csv
      columns: feature, metric_name, value, ci_low, ci_high
  - results/phase1_geometry/falsification_grid.csv
      columns: hypothesis, metric, observed, threshold, passes
  - results/phase1_geometry/probe_from_coords.csv
      columns: feature, coord_dim, probe_accuracy, baseline
  - results/phase1_geometry/mean_direction_probe.csv
      columns: feature, projection_accuracy, baseline_accuracy
  - results/phase1_geometry/patching.csv
      columns: source_idx, target_idx, flip_rate, n_samples
  - results/phase1_geometry/null_comparison.csv
      columns: feature, metric_name, observed, null_mean, null_p95, null_p99
  - results/phase1_geometry/reproducibility_audit.csv
      columns: claim_id, source_artifact, recomputed_value, original_value, match
  - results/phase1_geometry/GEOMETRY_SUMMARY.md  (the Summarizer's user-facing doc)

Plots (every spec'd plot, labeled axes, captions, ceiling lines where applicable):
  - plots/phase1_geometry/i_star_pca2.png
  - plots/phase1_geometry/i_star_pca3.png
  - plots/phase1_geometry/i_star_per_pc_acc.png
  - plots/phase1_geometry/i_star_umap.png
  - plots/phase1_geometry/i_star_umap_grid.png
  - plots/phase1_geometry/i_star_umap_positive_only.png
  - plots/phase1_geometry/linear_control_pca2.png
  - plots/phase1_geometry/linear_control_pca3.png
  - plots/phase1_geometry/linear_control_umap.png
  - plots/phase1_geometry/linear_control_umap_positive_only.png
  - plots/phase1_geometry/kmeans_silhouette_panel.png
  - plots/phase1_geometry/metric_panel.png
  - plots/phase1_geometry/null_comparison.png
  - plots/phase1_geometry/patching_histogram.png

Output destinations: results/phase1_geometry/, plots/phase1_geometry/, notes/phase1_geometry/.
Read-only inputs: cache/test_acts.pt, cache/train_acts.pt, results/phase1_decision/phase1_decision.csv, data/test.jsonl, feature_names.json.
Hard rules: seed=42, deterministic algorithms, max-iter ≥ 5000 for sklearn LogisticRegression.
Definitions: see METHODOLOGY.md §6.1 (intrinsic_dim variants), §6.4 (falsification thresholds), §6.5.3 (patching protocol).
Success criteria: all CSVs schema-valid, all plots > 1000 bytes, every spec invariant tested,
the §6.10 gate (5/5 conditions pass) from METHODOLOGY.md.
Test scope: ≥ 60 author tests covering every public function + every CSV schema +
every cross-file invariant from METHODOLOGY §6.10; verifier produces an independent suite ≥ 30 tests.
```

## Expected behavior

- **Activation:** prompt names all 8 required fields → clarification gate passes silently.
- **Pre-flight model vigilance:** runs at skill start; if all models current, silent.
- **P2 Field Advisor:** cold or warm mode depending on whether `./.research_executor/field_knowledge_mechanistic-interpretability.md` exists. Either way, gate verifies the deliverables non-empty post-spawn.
- **P3 advisor() pre-flight:** classifies traps; if any block-severity flag, surfaces to user and waits.
- **P4 Author phase:** distiller + contract author (Opus) → parallel Author-Code + Author-Tests (Sonnet) → contract-drift Python check → contract-reconstructor (Opus) → diff.
- **P5 Runner:** writes reproducibility manifest (env.txt, git_rev.txt, inputs.sha256) before the workload, hashes outputs after.
- **P6 advisor() mid-flight:** runs `scripts/data_quality_scan.sh` first, then calls advisor() with the scan results.
- **P7 Verifier:** spec-only context, independent assertions.
- **P8 Field Advisor post + advisor() + reconcile:** if active disagreements, surfaces to user.
- **P9 Summarizer:** writes `GEOMETRY_SUMMARY.md` with strict-phrasing default ON — verdict-form language forbidden, the table speaks.
- **P10 Main agent:** walks state JSON, asserts every `*_passed` flag, emits final message.

## Sample summary opening (strict-phrasing default ON)

```
# §6 — Geometric characterisation of i*

## 1. TL;DR

§6 ran the full intrinsic-dim + PCA + k-means + falsification + patching suite on
the layer-L candidate feature i*. The intrinsic-dimension estimators returned
TwoNN=3.1 (CI 2.7–3.5), MLE=2.8, PCA-95% retains 5 dims; the seven linear-control
features cluster around TwoNN=1.0–1.4, MLE=1.0–1.3, PCA-95%=1. The k-means
silhouette panel shows i* with a substantially higher silhouette at k=3 than at
k=2; controls show the opposite ordering. The falsification grid §6.4 reports 4/5
hypotheses passing for i*, with the "linear-rotation" hypothesis failing. Linear
patching of i* between class-positive and class-negative neighbourhoods produces
a 0.18 flip rate; controls produce 0.71. See per-method observations in §3.
```

Note what the TL;DR does NOT say: it does not assert "i* is non-linear" or "country is the answer." The table speaks; the user concludes.

## Where the run lands

```
results/phase1_geometry/
├── intrinsic_dim.csv
├── per_pc_acc.csv
├── kmeans_audit.csv
├── structural_metrics.csv
├── falsification_grid.csv
├── probe_from_coords.csv
├── mean_direction_probe.csv
├── patching.csv
├── null_comparison.csv
├── reproducibility_audit.csv
├── GEOMETRY_SUMMARY.md
├── env.txt
├── git_rev.txt
├── git_status.txt
├── inputs.sha256
├── outputs.sha256
└── run_log.txt

plots/phase1_geometry/
└── *.png  (14 plot files)

tests/
├── test_probe_geometry.py             (Author tests, ~109 + 17 invariants)
└── test_probe_geometry_verifier.py    (Verifier tests, ~72)

tmp/
├── codebase_digest.md
├── field_advisor_pre.md
├── field_advisor_pre_distilled.md
├── api_contract.md
├── api_contract_reconstructed.md
├── api_contract_diff.txt
├── field_advisor_post.md
├── p8_reconcile.md
├── data_quality_scan.md
├── run_log_step1.txt
├── run_log_step3.txt
├── run_log_verifier.txt
└── research_executor_state.json
```
