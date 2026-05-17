# Pre-flight model vigilance (runs at skill start, before P1)

Cross-cutting rule #13. SKILL.md carries a one-paragraph summary; this file is the canonical full procedure.

---

## Why this exists

The skill hardcodes specific Claude model IDs. These choices were made when the skill was written. Newer models may exist by the time the user invokes the skill — and for the high-reasoning phases (Field Advisor, Summarizer, contract reconstructor) a meaningfully better model can change the quality ceiling. The orchestrator surfaces model-version vigilance at skill start so the user can opt into upgrades.

## Hardcoded defaults

- Field Advisor: **Opus 4.7** (`claude-opus-4-7`)
- P4 prep (distiller + API contract author): **Opus 4.7**
- Author-Code / Author-Tests: **Sonnet 4.6** (`claude-sonnet-4-6`)
- Runner: **Sonnet 4.6**
- Verifier: **Sonnet 4.6**
- P4d contract reconstructor: **Opus 4.7**
- Summarizer: **Opus 4.7**

These are mirrored in `state.model_overrides` as the starting values. The pre-flight check may swap entries before P1 begins; downstream phases read from `state.model_overrides`, not from these hardcoded defaults.

## Steps

1. **At skill start** (immediately after the Activation check passes), the main agent enumerates the model IDs the skill currently uses (above list).

2. **Compare** against what the main agent knows about currently-available Claude models. Specifically check whether a newer model exists for the Opus tier (since Field Advisor + Summarizer + contract reconstructor are the most quality-sensitive). Examples of meaningful upgrades to look for:
   - A higher version-number Opus (5.x, 4.8, 4.9) is publicly available.
   - A new model tier purpose-built for reasoning (think "extended thinking" successor) that would help Field Advisor's citation sweep or Summarizer's structuring.
   - The hardcoded Sonnet version is several releases behind current.

3. **If a meaningful upgrade exists for one or more phases**, emit a single non-blocking message:

```
Model vigilance — newer model(s) may improve specific phases of this run.

Phase                        Current        Newer available    Why swap?
Field Advisor (P2)           Opus 4.7       <newer if exists>  Citation-sweep quality dominates this phase.
Contract reconstructor (P4d) Opus 4.7       <newer if exists>  Semantic round-trip quality matters here.
Summarizer (P9)              Opus 4.7       <newer if exists>  Narrative structuring is the bottleneck.
Authors (P4) / Runner / Verifier  Sonnet 4.6  <newer if exists>  Marginal — only swap if user wants.

Options:
  1. NO_SWAP — use the skill's defaults (recommended if you trust the hardcoded versions).
  2. SWAP_ALL — use the newest available model for each phase.
  3. SWAP_OPUS_ONLY — upgrade only the Opus phases (Field Advisor, P4 prep, P4d, Summarizer).
  4. SWAP_CUSTOM — specify per-phase overrides.
```

4. **Wait briefly for user reply.** If no reply within a reasonable time, proceed with NO_SWAP (the safe default). Record decision in state JSON under `model_vigilance_decision` and `model_overrides` (the map of phase → model_id).

5. **For the rest of the run**, use the resolved model IDs from `model_overrides` instead of the hardcoded defaults.

## When to surface this check

- **Always run the comparison.**
- **Surface to user** ONLY if at least one phase has a newer model worth recommending.
- If everything is current, log `"model vigilance: all phases up to date"` to state JSON and proceed silently.

## When NOT to surface

- **Resumed runs** — the model decision from the prior session persists via state JSON's `model_overrides`.
- **User has set `--no-model-vigilance`** in the goal text (record as `model_vigilance_decision: skipped_per_goal`).

## Why this matters

This check is the skill's way of avoiding silent obsolescence. It's also why the skill's frontmatter lists model IDs explicitly — when a maintainer reads the skill a year from now, they can see what was current at write-time and what's been auto-overridden since.
