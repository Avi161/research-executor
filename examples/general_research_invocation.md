# Example — general research invocation (direct-summary opt-out)

This shows a `/research-executor` invocation for a non-puzzle task: a comparative benchmark where the user wants the Summarizer to state findings directly. The goal text contains the literal phrase `"direct summary"`, which toggles the strict-phrasing rule OFF for P9 and P10.

---

## Goal text (what the user pastes after `/research-executor`)

```
direct summary

Goal: compare three optimizers (SGD with momentum, Adam, AdamW) on CIFAR-10
classification with a ResNet-18, fixed compute budget of 200 epochs, three seeds
per condition. Identify which optimizer wins on test accuracy and characterise
the per-optimizer training dynamics.

Deliverables:
  - results/optimizer_bench/test_accuracy.csv
      columns: optimizer, seed, epoch, test_accuracy, test_loss
  - results/optimizer_bench/training_dynamics.csv
      columns: optimizer, seed, epoch, train_loss, train_acc, lr, grad_norm
  - results/optimizer_bench/summary_stats.csv
      columns: optimizer, mean_final_test_acc, std_final_test_acc, mean_best_epoch, n_seeds
  - results/optimizer_bench/SUMMARY.md  (Summarizer's user-facing doc, direct verdict allowed)

Plots:
  - plots/optimizer_bench/test_accuracy_curves.png
  - plots/optimizer_bench/train_loss_curves.png
  - plots/optimizer_bench/lr_schedules.png
  - plots/optimizer_bench/grad_norm_distribution.png
  - plots/optimizer_bench/per_seed_final_acc_bar.png

Output destinations: results/optimizer_bench/, plots/optimizer_bench/, notes/optimizer_bench/.
Read-only inputs: data/cifar10/ (standard CIFAR-10 download dir), configs/resnet18.yaml.
Hard rules: seed ∈ {0, 1, 2}, deterministic algorithms, max compute 200 epochs/run, batch=128.
Definitions: "winner" = highest mean final test accuracy across seeds; "robust winner" = winner whose
  per-seed accuracy 95% CI does not overlap the runner-up's CI.
Success criteria: all three optimizers complete 3 seeds × 200 epochs; SUMMARY.md states the
  winner directly and gives a 1-paragraph mechanistic explanation citing the training dynamics.
Test scope: ≥ 40 author tests, ≥ 20 verifier tests, all CSV schemas validated, every plot non-empty.
```

## Effect of the `direct summary` opt-out

Because the goal text contains the literal string `"direct summary"`, the orchestrator records `summary_strict_phrasing_enabled: false` in state JSON. Downstream:

- **P9 Summarizer prompt** uses the OFF branch — "Write findings-first. State the verdict where the evidence supports one."
- **P9 self-verification grep** is skipped.
- **P10 re-grep** is skipped.
- **P10 final-message TL;DR** can name the verdict directly.

## Sample summary opening (direct-summary opt-out)

```
# Optimizer benchmark on CIFAR-10 / ResNet-18

## 1. TL;DR

AdamW is the robust winner — mean final test accuracy 94.3% (CI 94.0–94.6) vs
Adam at 93.4% (CI 93.0–93.7) and SGD-momentum at 92.8% (CI 92.4–93.1). The CIs do
not overlap, so the win is statistically meaningful at the 3-seed scale. The
mechanistic story: AdamW's decoupled weight decay produces a flatter gradient-norm
distribution in the second half of training (see plots/grad_norm_distribution.png),
which correlates with the smaller train/test gap at convergence. SGD-momentum
catches up to Adam by epoch 180 on a single seed but never closes the gap to
AdamW. Recommendation: use AdamW as the default for this architecture / dataset.
```

Note the explicit verdict (`AdamW is the robust winner`), the direct mechanistic claim (`AdamW's decoupled weight decay produces…which correlates with…`), and the explicit recommendation. None of these would pass the strict-phrasing grep, but the grep is intentionally skipped because the goal opted out.

## What stays unchanged from puzzle mode

Even with strict phrasing off:

- Author-Code, Author-Tests, Runner, Verifier all behave identically — they were never under strict-phrasing in the first place. Direct variable names and prints throughout.
- Pre-flight model vigilance still runs.
- Reproducibility manifest still writes (`env.txt`, `git_rev.txt`, `inputs.sha256`, `outputs.sha256`).
- All gates still apply: contract drift check, contract round-trip, P8 reconcile, P10 final gate-check.
- The only behavior change is the Summarizer's tone and the grep skip.
