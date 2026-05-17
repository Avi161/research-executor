---
name: research-executor
description: >-
  ONLY invoke when the user explicitly types `/research-executor` (or asks to
  "run research-executor" / "use the research-executor skill" by name). Do NOT
  auto-activate based on goal text, METHODOLOGY sections, plan files, or task
  specs appearing in the conversation — even when the content looks like a
  perfect fit. The user controls when this skill runs because the full 10-phase
  orchestration consumes Opus 4.7 plus extensive WebSearch budget across multiple
  subagents. If the user pastes a research spec without naming the skill, ask
  whether they want to invoke `/research-executor` rather than launching it.
  Runtime behavior once invoked — always on (non-negotiable): maximal test
  coverage, plot generation, phase timing instrumentation, reproducibility
  manifest (pip freeze + git rev + sha256 hashes), project-relative paths only.
  Configurable: torch+numpy+python determinism stack (default ON), read-only
  fences (default ON), strict-phrasing audit on the Summarizer output only
  (default ON, workload code/tests/logs exempt; disable with "direct summary"
  or "no phrasing constraints" in goal text). Pipeline: Field Advisor (Opus) +
  2 parallel authors (Sonnet) + Runner (Sonnet) + Verifier (Sonnet) +
  Summarizer (Opus) + two advisor() checkpoints.
---

# research-executor

A 10-phase orchestrated workflow for non-trivial research / implementation tasks. SKILL.md is a router — long prompt templates live in `references/prompts/`, Bash/Python helpers live in `scripts/`, full procedures live in `references/`. Read those on-demand when a phase needs them.

## Activation

**User-invoked only.** Runs exclusively when the user types `/research-executor` or names it in a request. Never auto-activate from inferred fit. If a pasted goal spec or METHODOLOGY section looks like a perfect candidate but the user hasn't named the skill, ask first.

Bow out (and say why) when the task is a single-file script, a read-only analysis (use `advisor()` directly), or a mid-iteration tweak (Edit + targeted tests beats the pipeline).

### Clarification gate (MANDATORY before Phase 1)

Audit the invocation against the required-fields checklist below. If any field is missing AND not covered by a linked doc, **STOP and ask** — do not proceed.

A spec is "specific enough to run" if either (a) the user's prompt names every required field, or (b) the prompt cites a specific doc (a `/goal` output, a METHODOLOGY section by number/line range, a plan file path) and that doc names every required field.

**Required fields:**

1. **Goal statement** — what the task accomplishes and why.
2. **Deliverable shape** — each CSV's columns, each plot's content, each JSON's schema.
3. **Output destinations** — exact paths under `results/` and `plots/`.
4. **Read-only inputs** — files/dirs the skill may read but not modify.
5. **Hard rules / constraints** — determinism overrides, seed, version pins, runtime budget, strict-phrasing opt-out (`direct summary` / `no phrasing constraints`) if you want a verdict-form final summary.
6. **Definitions** — task-specific terms (e.g. `best_C`, `Wilson interval`, `selectivity`) defined inline or by linked-doc section.
7. **Success criteria** — concrete pass/fail, not "looks good."
8. **Test scope** — test count target OR list of invariants the suite must cover.

If fields are missing: send a single message with a numbered list of EVERY missing field, each with a concrete question. Offer 2–3 options when sensible defaults exist. Do not guess. Do not half-start Phase 1.

If the user replies "just run it" after being asked, comply — but log assumptions in `tmp/research_executor_state.json` under `assumptions_made_without_user_confirmation` and surface them at P10.

## Defaults

**Always on — non-negotiable:**
- Maximal test coverage (Author-Tests + Verifier both exhaustive).
- Plot generation whenever data is plottable.
- Project-relative paths only — never `/tmp/`.
- Phase timing instrumentation (cross-cutting rule #11).
- Reproducibility manifest in P5 (cross-cutting rule #12).

**Configurable via goal text:**

| Rule | Default | Toggle phrase |
|---|---|---|
| Determinism stack (torch + numpy + python seeding, deterministic algorithms) | ON | disable with `non-deterministic ok` |
| Read-only fences on upstream phase outputs | ON | disable with `may modify upstream` |
| Strict-phrasing audit on Summarizer output only (workload code/tests/logs exempt) | **ON** | disable with `direct summary` or `no phrasing constraints` |

## Phase order

```
P1.  Codebase intake             (main agent: Read + Glob + Grep)
P2.  Field Advisor — pre         (Opus 4.7 subagent: domain expert plan review)
P3.  advisor() pre-flight        (catches code-level traps; abort gate if any block-severity trap)
P4.  Author phase                (Opus prep → 2 Sonnet 4.6 authors in PARALLEL → Opus round-trip)
P5.  Runner subagent             (Sonnet 4.6: executes, up to 3 fix-retries, writes manifest)
P6.  advisor() mid-flight        (mechanical data-quality scan → advisor reviews scan + artifacts)
P7.  Verifier subagent           (Sonnet 4.6: independent tests, spec-only context)
P8.  Field Advisor — post  +  advisor() final review  (parallel → reconcile pass)
P9.  Summarizer subagent         (Opus 4.7: writes user-facing markdown)
P10. Main-agent final pass       (gate-check on every *_passed flag; refuses to declare done on failure)
```

## Resumability

State is at `tmp/research_executor_state.json`. On every re-invocation, hash the incoming goal text and compare to `goal_hash`. If match, resume from `last_completed_phase + 1`. If mismatch, ask: restart fresh or keep prior state. Full schema: `references/state_json_schema.md`.

## Field Advisor cache (persistent, project-level)

Cache directory: `./.research_executor/`. Field-knowledge file: `field_knowledge_{field_slug}.md`. Index: `field_advisor_index.json`. Survives across invocations and across goals within the same project. Cold sweep (5–30 min) only on first invocation per field. Staleness warning (non-blocking) when cache > 30 days old. **Full layout + 4-step branching gate + staleness procedure: `references/cache_layout_and_staleness.md`. Companion script: `scripts/cache_staleness_check.sh`.**

## Pre-flight model vigilance

Before P1, the orchestrator enumerates the model IDs the skill hardcodes and compares against currently-available Claude models. If a newer model exists for any high-reasoning phase (Field Advisor, P4 prep, P4d reconstructor, Summarizer), surface a non-blocking 4-option prompt (NO_SWAP / SWAP_ALL / SWAP_OPUS_ONLY / SWAP_CUSTOM). Decisions are recorded in `state.model_overrides`; downstream phases read from there, not from the hardcoded defaults. Silent on no-upgrade. **Full procedure: `references/model_vigilance_procedure.md`.**

## TodoList scaffold

At skill start, create a TodoList with one entry per phase (P1–P10). Mark each `in_progress` → `completed` in sequence. Update state JSON in parallel.

---

## Phase 1 — Codebase intake

**Goal:** produce `./tmp/codebase_digest.md` containing a summary of every relevant project file so downstream subagents have full context without re-reading.

**Precondition:** Clarification gate passed.

**Steps:**

1. `mkdir -p ./tmp` (if absent).
2. Read in parallel via Glob + Read:
   - Top-level `*.md` in the working dir and one level up.
   - `PAPERS.md`, `METHODOLOGY.md`, `README.md`, `CLAUDE.md` and any relevant `.md` at any depth.
   - `**/*_SUMMARY.md` and `**/SUMMARY.md` (prior-phase chains).
   - `detailed_steps.md`, `notes/**/*.md`, `*.bib`, `references.md` if present.
3. If any file > 2000 lines, read in chunks and summarize.
4. Write digest to `./tmp/codebase_digest.md` with sections: project overview, methodology pointers, prior-phase summaries, reading list / papers, conventions, critical user instructions.
5. Detect **field** from goal text + digest (e.g. mech-interp, AI safety, transformers/NLP, vision, RL, Bayesian). Record in state JSON as `field_detected`.

**Output:** `./tmp/codebase_digest.md` + state JSON.

---

## Phase 2 — Field Advisor (pre)

**Goal:** a senior domain expert's review of the goal + plan, with full WebSearch access.

Two layers per call:

- **Field-level knowledge** — papers, canonical pitfalls, verification checks the field expects, exemplars. Same every run for this field, in this project. **Cached persistently.**
- **Goal-level review** — review of THIS specific goal's approach. Different every run. **Always regenerated.**

**Procedure:** the 4-step branching gate (mkdir → existence check → spawn → post-spawn verification) is the canonical control flow. **Full procedure: `references/cache_layout_and_staleness.md`.**

**Prompts:**
- Cold mode (no cache hit): `references/prompts/field_advisor_cold.md`
- Warm mode (cache hit): `references/prompts/field_advisor_warm.md`

Model: `state.model_overrides.field_advisor` (default `claude-opus-4-7`).

**Outputs:** cold → 3 files (cache + index + goal-review); warm → 1 file (goal-review). State JSON gets `field_advisor_cache_*` fields. Post-spawn gate re-spawns on missing deliverables.

---

## Phase 3 — advisor() pre-flight (with abort gate)

Call `advisor()` with no parameters. The advisor sees the full conversation including the goal, codebase digest, and Field Advisor's review.

### Step 3.1 — Classify every flagged trap by severity

- **block** — uncorrected, this makes P4–P10 likely wasted. Examples: wrong metric, train/test leakage, cited paper says the opposite, required read-only input doesn't exist, hard rules contradict, deliverable spec impossible from inputs.
- **warn** — addressable inside workload/tests; can proceed. Examples: "use Wilson not Wald," "add shuffled-label control," "cap `max_iter` higher."

When in doubt: "would a top-venue reviewer reject?" → block. "Would they ask for revision?" → warn.

### Step 3.2 — Abort gate (BLOCKING if any block-severity trap is present)

- **Zero block traps** → proceed silently to P4.
- **One or more block traps** → STOP, do not spawn P4. Emit a structured message to the user with each block trap (verbatim quote + why it blocks + suggested resolution) and three options:
  1. PROCEED — accept and run P4–P10 anyway (recorded as `proceed_despite_block_traps`).
  2. AMEND — give corrected goal text, re-run P3 once, re-evaluate.
  3. ABORT — halt the skill.

Wait for explicit reply. Do NOT silently proceed on timeout. Conflicts between Field Advisor and goal are **always** block-severity.

### Step 3.3 — Record in state JSON

`p3_advisor_traps[]`, `p3_block_severity_count`, `p3_abort_gate_decision`, `p3_abort_gate_user_response_utc`. If `aborted`, halt the skill; do NOT touch P4+.

Surviving traps (warn + PROCEED-past blocks) become `{advisor_traps}` injected into the Author prompts.

---

## Phase 4 — Author phase (prep → 2 parallel authors → round-trip)

The most expensive phase, most context-rot-prone if done as one subagent. Broken into four steps:

- **Step 4a — Prep (Opus, serial, ~60s).** Two cheap Opus prep calls produce small shared inputs.
- **Step 4b — Authors (Sonnet, PARALLEL).** Author-Code and Author-Tests spawn in the SAME message (two tool-call blocks). Each reads only the distilled file + API contract + goal.
- **Step 4c — Joint verification (main agent).** AST check that test imports resolve to workload symbols.
- **Step 4d — Contract round-trip (Opus).** Anti-Goodharting: reconstructor reads ONLY the test file, diffs against the real contract.

### Step 4a-i — Distill the Field Advisor pre file

Prompt: `references/prompts/distiller.md`. Model: `state.model_overrides.p4_prep_distiller` (default `claude-opus-4-7`). Output: `./tmp/field_advisor_pre_distilled.md` (≤ 6 KB).

### Step 4a-ii — Emit the API contract

Prompt: `references/prompts/api_contract_author.md`. Model: `state.model_overrides.p4_prep_contract` (default `claude-opus-4-7`). Output: `./tmp/api_contract.md` (one row per signature/output/flag; length scales with deliverable count).

### Step 4b — Spawn Author-Code and Author-Tests IN PARALLEL

**CRITICAL: spawn both in the SAME message (two `Agent` tool calls in one assistant turn).** Sequential spawn defeats the parallelization.

Prompts: `references/prompts/author_code.md` + `references/prompts/author_tests.md`. Models: `state.model_overrides.author_code` + `state.model_overrides.author_tests` (defaults `claude-sonnet-4-6`).

Author-Code writes the workload `.py`. Author-Tests writes `tests/<test_file>.py` and is forbidden to Read the workload until after its own file is written.

### Step 4c — Joint verification

After both authors return:

```bash
scripts/contract_drift_check.py --workload <workload>.py --tests tests/<test_file>.py --module-name <workload_module>
```

Exit 0 = agreement. Exit 1 = drift; re-spawn the offending author with the missing names. The real `api_contract.md` is the tie-breaker.

### Step 4d — Contract round-trip (semantic anti-Goodharting)

Step 4c catches syntactic drift. 4d catches semantic drift (unordered vs ordered columns, missing CSVs, extra params).

Prompt: `references/prompts/contract_reconstructor.md`. Model: `state.model_overrides.p4d_reconstructor` (default `claude-opus-4-7`). Output: `./tmp/api_contract_reconstructed.md`.

After it returns:

```bash
diff -u ./tmp/api_contract.md ./tmp/api_contract_reconstructed.md > ./tmp/api_contract_diff.txt 2>&1 || true
```

Classify: trivial (whitespace) → pass. Semantic (function name, column order, unordered set, missing output) → ROUND-TRIP FAILURE. Re-spawn whichever author drifted; the real contract is the tie-breaker.

Record `contract_roundtrip_diff_lines`, `contract_roundtrip_passed`, `contract_roundtrip_attempts`.

**P4 cumulative outputs:** workload `.py` + test file + `./tmp/api_contract.md` + `./tmp/api_contract_reconstructed.md` + `./tmp/api_contract_diff.txt` + `./tmp/field_advisor_pre_distilled.md`.

---

## Phase 5 — Runner subagent

Prompt: `references/prompts/runner.md`. Model: `state.model_overrides.runner` (default `claude-sonnet-4-6`). Up to 3 fix-and-retry iterations.

**Reproducibility manifest (cross-cutting rule #12) — REQUIRED.** Companion script: `scripts/reproducibility_manifest.sh`. Runner invokes:

- **Before workload run** (Step 0.5): `scripts/reproducibility_manifest.sh --pre --output-dir <dir> --venv .venv --read-only-inputs <files>` → writes `env.txt`, `git_rev.txt`, `git_status.txt`, `inputs.sha256`. Exit 2 if venv inactive (< 10 lines from `pip freeze`) → STOP and report.
- **After workload run** (Step 2.5): `scripts/reproducibility_manifest.sh --post --output-dir <dir>` → writes `outputs.sha256` for every `.csv`, `.json`, `.png`.

Runner sequence: Step 0 sanity → Step 0.5 pre-manifest → Step 1 non-integration tests → Step 2 workload → Step 2.5 post-manifest → Step 3 full test suite → Step 4 final verification (report only).

Fix policy: failing test → fix workload first. Spec-wrong test → fix test with written justification. Spec deviation needed → STOP and report.

**Output:** all artifact files on disk + Runner's report. State JSON gets `runner_retries_used`, `runner_max_retries`, `reproducibility_manifest.*`.

---

## Phase 6 — advisor() mid-flight (with explicit data-quality pre-check)

P6 runs a deterministic data-quality scan FIRST, then calls advisor() with those findings as additional context.

### Step 6.1 — Mechanical data-quality scan

Run: `scripts/data_quality_scan.sh --output-dirs <dirs> --plot-dirs <dirs>`. Writes `./tmp/data_quality_scan.md` with three sections: Flags raised, All-clear checks, What to ask advisor about.

Checks: NaN/Inf in CSVs, plot files < 5 KB (broken renders), single-class predictions, suspiciously round numbers (saturation/clipping), row-count sanity.

### Step 6.2 — advisor() with scan findings

Call `advisor()` with no parameters; mention the scan results are in `./tmp/data_quality_scan.md`. Advisor sees the conversation.

Each advisor observation → directive in `phase_8_directives` (merged at P8). Each unresolved DQ flag → `p6_unresolved_dq_flags` (Summarizer must mention in Caveats). Blocking issue → surface to user before P7; record decision.

**Output:** `./tmp/data_quality_scan.md` + state JSON updated with `p6_unresolved_dq_flags`, `p6_blocking_issues_surfaced`.

---

## Phase 7 — Verifier subagent

Prompt: `references/prompts/verifier.md`. Model: `state.model_overrides.verifier` (default `claude-sonnet-4-6`).

**Restricted context (by design):** Verifier sees ONLY the goal spec, `./tmp/field_advisor_pre.md`, the final `{workload_file}` source, and the produced artifacts. NOT the Author's planning, NOT the Runner's traces, NOT the pre-flight advisor traps. Reading Author reasoning would copy assumptions instead of falsifying them.

Categories: cross-file consistency, per-CSV schema, determinism, field hygiene, plot existence, sanity bounds, cross-method invariants, spec arithmetic. Exhaustive — no minimum count.

Up to 2 fix-iterations on the verifier test file. Verifier MUST NOT modify the workload or Author's test file. Real bug → STOP, report.

**Output:** Verifier test file + `tmp/run_log_verifier.txt`. State JSON gets `verifier_exit_code`.

---

## Phase 8 — Field Advisor (post) + advisor() final, in parallel, then reconcile

Three parts: 8a + 8b run in parallel (single message, two tool calls); 8c runs after both return.

### 8a. Field Advisor (post)

Prompt: `references/prompts/field_advisor_post.md`. Same persona as P2, model `state.model_overrides.field_advisor`. Reviews produced artifacts against pre-flight concerns. Output: `./tmp/field_advisor_post.md`.

### 8b. advisor() final

Call `advisor()` with no parameters. Sees the full conversation including all prior phase outputs.

### 8c. Reconcile (BLOCKING on active disagreements)

After both return, the main agent compares conclusions. Classify each load-bearing claim:

- **Both agree** → fold into directive list silently.
- **One mentions, the other silent** → fold in, note which reviewer raised it.
- **Active disagreement** → STOP. Surface to the user with both verbatim quotes and three options per disagreement: WEIGHT_FA (Field Advisor wins) / WEIGHT_ADV (advisor wins) / HEDGE (mention both).

Write `./tmp/p8_reconcile.md` with three sections (Both agree / Only one raised / Active disagreements). Wait for user reply if disagreements present. Record `p8_disagreement_resolutions[]` in state JSON.

P9 may not begin until reconcile passed (zero disagreements OR all resolved).

---

## Phase 9 — Summarizer subagent

Prompt: `references/prompts/summarizer.md`. Model: `state.model_overrides.summarizer` (default `claude-opus-4-7`).

**Strict phrasing default ON for the summary output only** — forbidden patterns in the markdown: "is the answer", "the answer is X", "X is the [feature/cause]", "we have found", "confirms X is", "the feature is found to be". Allowed: report data, user concludes.

**Opt-out:** goal text contains `direct summary` or `no phrasing constraints` → Summarizer writes findings-first. Self-grep skips.

Structure: TL;DR / inputs+outputs / per-feature results / cross-method observations / skeptic checks / chain back to prior phases / hygiene / caveats / next step. Target 200–400 lines.

Self-verification gate (default): grep the summary for forbidden patterns; output MUST be empty (or borderline data-interpretation matches the Summarizer flags). On opt-out: skip the grep.

**Output:** summary markdown + state JSON gets `summary_strict_phrasing_enabled`.

---

## Phase 10 — Main agent final pass (gate-check + final message)

P10 walks every gate flag in state JSON and refuses to declare done if any failed.

### Step 10.1 — Gate-check (BLOCKING)

Assert each is true:
- `field_advisor_cache_gate_passed`
- `contract_check_passed`
- `contract_roundtrip_passed`
- `p3_abort_gate_decision ∈ {no_blocks, proceed_despite_block_traps, amended_and_rerun}`
- `p6_blocking_issues_surfaced == false`, OR user explicitly overrode
- Every `p8_disagreement_resolutions[].resolution` non-null
- `runner_retries_used < runner_max_retries`
- `verifier_exit_code == 0`
- Reproducibility manifest files (`env.txt`, `git_rev.txt`, `inputs.sha256`, `outputs.sha256`) exist in every output dir
- Unless opted out via `direct summary` / `no phrasing constraints`: Summarizer self-grep empty AND main-agent re-grep empty

On failure: structured failure report listing failed gate(s); do NOT send "done" message; ask user whether to re-run failing phase or accept deviation explicitly. Record `p10_gate_check_overrides[]`.

### Step 10.2 — Audits (don't gate, inform the final message)

1. Artifact listing with sizes (`ls -la` on output + plot dirs).
2. Test totals across Author + Verifier suites.
3. Cross-reference Summarizer report against P8 directives.
4. Independent re-grep of summary markdown for forbidden patterns (default; skip if opted out).
5. Phase-timing audit (flag any phase > 2× median historical time if priors exist).

### Step 10.3 — Final user message

Structure:
- **TL;DR** — what was produced, headline finding. Non-verdict-framed by default; verdict-form if opted out.
- **Gate-check summary** — every gate with ✅/❌ at-a-glance.
- **Phase timings table** — `P1: 30s | P2: 600s | P4: 280s | …`.
- **Artifacts** — paths + sizes.
- **Reproducibility manifest pointers** — env.txt / git_rev.txt / inputs.sha256 / outputs.sha256.
- **Flagged items** — borderline phrasing (if any), gate overrides (if any), slow phases (if any).
- **Next step** — per the goal's "next step" section.

Mark P10 completed in state JSON only after the gate-check passed (or user explicitly accepted overrides).

---

## Cross-cutting rules (one-line summary; full text in `references/cross_cutting_rules.md`)

1. **Path discipline.** Outputs under user-specified dirs; scratch in `./tmp/`; never `/tmp/`.
2. **Strict phrasing.** SUMMARIZER OUTPUT ONLY, default ON, opt-out via goal text. Pipeline (Author/Runner/Verifier) is exempt.
3. **Read-only fences.** Every subagent prompt enumerates which dirs are read-only.
4. **Determinism stack (default ON).** Full seeding, deterministic algorithms flag, single-worker DataLoader.
5. **Closed-form arithmetic checks.** Derived columns match formulas within 1e-9.
6. **Incremental writes.** Each output written before next subsection runs.
7. **Two advisor() + two Field Advisor calls.** Pre catches design traps; post catches artifact issues.
8. **Test files as contracts.** Author tests + Verifier tests together form the spec contract.
9. **Subagent isolation.** Each phase has bounded inputs and bounded scope; see `references/cross_cutting_rules.md` for the full table.
10. **Resumability.** State JSON updated at end of every phase; re-invoking with same goal_hash resumes from `last_completed_phase + 1`.
11. **Phase timing instrumentation (REQUIRED).** Every phase records `start_utc`/`end_utc` to `phase_timings_seconds`.
12. **Reproducibility manifest (REQUIRED in P5).** Companion script: `scripts/reproducibility_manifest.sh`.
13. **Model-version vigilance (REQUIRED at skill start).** Procedure: `references/model_vigilance_procedure.md`.
14. **Cache staleness > 30 days WARN.** Companion script: `scripts/cache_staleness_check.sh`.
15. **P6 mechanical DQ scan (REQUIRED).** Companion script: `scripts/data_quality_scan.sh`.
16. **P8 reconcile (BLOCKING on disagreements).** Silent merging forbidden.
17. **Contract round-trip (REQUIRED at P4d).** Reconstructor reads ONLY test file; diff against real contract.

---

## When to deviate

See `references/deviation_modes.md`. Short version: single-file pure-function tasks, exploratory analyses, and pure read-only work should NOT use the full 10-phase flow. The pattern earns its overhead on ≥ 200-line workloads with ≥ 5 output artifacts.

## Quick reference: what each phase produces

| Phase | Produces |
|---|---|
| P1 Codebase intake | `./tmp/codebase_digest.md` |
| P2 Field Advisor (pre) | `./tmp/field_advisor_pre.md` + cache files (cold) — see `references/cache_layout_and_staleness.md` |
| P3 advisor() pre-flight | classified trap list + abort-gate decision; halts on user ABORT |
| P4 Author phase | distilled + contract + workload + tests + reconstructed contract + diff |
| P5 Runner | result artifacts (CSV/JSON/PNG) + reproducibility manifest + run logs |
| P6 advisor() mid-flight | `./tmp/data_quality_scan.md` + advisor observations folded into directives |
| P7 Verifier | verifier test file + `tmp/run_log_verifier.txt` |
| P8 FA (post) + advisor() + reconcile | `./tmp/field_advisor_post.md` + `./tmp/p8_reconcile.md` + unified directives |
| P9 Summarizer | user-facing markdown (200–400 lines) |
| P10 Main final pass | user message with gate-check summary + timings + artifacts |

## State JSON schema

See `references/state_json_schema.md` for the full schema with field-by-field comments.

## Final note on invocation

When the user invokes `/research-executor` followed by a goal brief:

1. Confirm the goal is parseable (paths, deliverables, output dirs identifiable).
2. Hash the goal text. Check `./tmp/research_executor_state.json`. If hash matches and phase < P10, ask: "Resume from {last_completed_phase + 1} or restart fresh?"
3. Run pre-flight model vigilance (silent if no upgrades available).
4. Create the TodoList with 10 phase entries.
5. Walk P1 → P10, reading the corresponding `references/prompts/*.md` when spawning each subagent. Update state JSON after each phase.
6. Emit the P10 final message — artifacts + gate-check + next step.
