# When to deviate from the full 10-phase flow

The 10-phase pattern is for tasks that produce shippable artifacts under hard constraints (correctness, reproducibility, field quality). For everything else, lighter is better.

- **Single-file pure-function task.** Collapse Author + Runner into one subagent; skip Verifier. The full flow earns its overhead on ≥ 200-line workloads with ≥ 5 output artifacts.
- **Exploratory / open-ended task.** Skip Phase 4–7 entirely; just do Phase 1 (intake) + Phase 2 (Field Advisor) and report back.
- **Pure read-only analysis.** No Runner needed; `advisor()` does the work directly.
- **User explicitly disables a phase** ("skip the Field Advisor for this one"). Honor it; record the deviation in state JSON under `deviations`.

Always record deviations in state JSON so the P10 gate-check knows which gates are intentionally skipped.
