---
name: research-executor
description: ONLY invoke when the user explicitly types `/research-executor` (or asks to "run research-executor" / "use the research-executor skill" by name). Do NOT auto-activate based on goal text, METHODOLOGY sections, plan files, or task specs appearing in the conversation — even when the content looks like a perfect fit. The user controls when this skill runs because the full 10-phase orchestration consumes Opus 4.7 plus extensive WebSearch budget across multiple subagents. If the user pastes a research spec without naming the skill, ask whether they want to invoke `/research-executor` rather than launching it. Runtime behavior once invoked — always on (non-negotiable): maximal test coverage, plot generation, phase timing instrumentation, reproducibility manifest (pip freeze + git rev + sha256 hashes), project-relative paths only. Configurable: torch+numpy+python determinism stack (default ON), read-only fences (default ON), strict-phrasing audit on the Summarizer output only (default ON, workload code/tests/logs exempt; disable with "direct summary" or "no phrasing constraints" in goal text). Pipeline: Field Advisor (Opus) + 2 parallel authors (Sonnet) + Runner (Sonnet) + Verifier (Sonnet) + Summarizer (Opus) + two advisor() checkpoints.
---

# research-executor

A 10-phase orchestrated workflow for non-trivial research/implementation tasks that produce shippable artifacts under correctness, reproducibility, and field-quality constraints.

The user supplies the goal (a `/goal` output, a METHODOLOGY section, a paper-style brief). The skill executes the orchestration end-to-end and produces:
1. Workload code + author test file.
2. Verifier test file (independent assertions).
3. Result artifacts (CSVs, JSONs, NPY tensors — whatever the task dictates).
4. Plots whenever the data supports visualization.
5. A human-readable summary markdown.
6. Two field-expert reviews and two general-advisor reviews.

## Activation

**User-invoked only.** This skill runs exclusively when the user types `/research-executor` or names it in a request ("run the research-executor skill"). Never auto-activate from inferred fit. If a pasted goal spec or METHODOLOGY section looks like a perfect candidate but the user hasn't named the skill, ask first.

Bow out (and say why) when the task is a single-file script, a read-only analysis (use `advisor()` directly), or a mid-iteration tweak (Edit + targeted tests beats the pipeline).

### Clarification gate (MANDATORY before Phase 1)

Before Phase 1, audit the invocation against the required-fields checklist below. If any field is missing AND not covered by a linked doc, **STOP and ask** — do not proceed.

A spec is "specific enough to run" if either (a) the user's prompt names every required field, or (b) the prompt cites a specific doc (a `/goal` output, a METHODOLOGY section by number/line range, a plan file path) and that doc names every required field. "See the methodology" is not specific; "execute METHODOLOGY.md §6 lines 181–198" is.

**Required fields (every one must be answered):**

1. **Goal statement.** What the task accomplishes and why.
2. **Deliverable shape.** Each CSV's columns, each plot's content, each JSON's schema, each markdown's structure.
3. **Output destinations.** Exact paths under `results/` and `plots/`.
4. **Read-only inputs.** Files/dirs the skill may read but not modify.
5. **Hard rules / constraints.** Determinism overrides, seed, library version pins, runtime budget, strict-phrasing opt-out (`direct summary` / `no phrasing constraints`) if you want a verdict-form final summary.
6. **Definitions.** Any task-specific term (e.g. `best_C`, `Wilson interval`, `selectivity`) defined in spec or linked-doc section.
7. **Success criteria.** Concrete pass/fail, not "looks good."
8. **Test scope.** Either a test count target or a list of invariants the suite must cover.

**Behavior when fields are missing:** send a single message with a numbered list of EVERY missing field, each with a concrete question. Offer 2–3 options when sensible defaults exist. If the user named a doc but didn't cite the section/line range, ask for it. Read any linked doc first and ask only about gaps. Do not guess. Do not half-start Phase 1.

If the user replies "just run it" after being asked, comply — but log the assumptions in `./tmp/research_executor_state.json` under `assumptions_made_without_user_confirmation` and surface them in the Phase 10 final message.

Skill is **resumable**: re-invoking with the same goal hash resumes from `last_completed_phase + 1` (see Resumability below).

## Defaults

Two categories: always-on rules (no disable) and configurable rules (opt-out or opt-in via goal text).

**Always on — non-negotiable:**
- Maximal test coverage (Author-Tests + Verifier both exhaustive). Tests are the spec contract — disabling them defeats the skill's purpose.
- Plot generation whenever data is plottable. Plots are the cheapest evidence for the submission narrative.
- Project-relative paths only — never `/tmp/`.
- Phase timing instrumentation (cross-cutting rule #11).
- Reproducibility manifest in P5 (cross-cutting rule #12).

**Configurable via goal text:**

| Rule | Default | Toggle phrase in goal |
|---|---|---|
| Determinism stack (torch + numpy + python random seeding, deterministic algorithms) | ON | disable with "non-deterministic ok" |
| Read-only fences on upstream phase outputs | ON | disable with "may modify upstream" |
| Strict-phrasing audit on the Summarizer output only (no verdict-form language naming the answer in the user-facing markdown; workload code/tests/logs are exempt) | **ON** | disable with "direct summary" or "no phrasing constraints" |

## Phase order

```
P1.  Codebase intake             (main agent: Read + Glob + Grep)
P2.  Field Advisor — pre         (Opus 4.7 subagent: domain expert plan review)
P3.  advisor() pre-flight        (catches code-level traps; abort gate if any block-severity trap)
P4.  Author phase                (Opus prep → 2 Sonnet 4.6 authors in PARALLEL: code + tests → Opus contract round-trip check)
P5.  Runner subagent             (Sonnet 4.6: executes, up to 3 fix-retries)
P6.  advisor() mid-flight        (mechanical data-quality scan → advisor() reviews real artifacts + scan)
P7.  Verifier subagent           (Sonnet 4.6: independent tests, spec-only context)
P8.  Field Advisor — post  +  advisor() final review  (parallel → reconcile pass, blocking on disagreements)
P9.  Summarizer subagent         (Sonnet 4.6: writes markdown summary)
P10. Main-agent final pass       (independent re-grep + artifact listing)
```

## Resumability

At the start of every phase, write/update `./tmp/research_executor_state.json`:

```json
{
  "goal_hash": "<sha256 of goal text>",
  "field_detected": "<auto-detected field>",
  "last_completed_phase": "P4",
  "artifacts_produced": {
    "codebase_digest": "./tmp/codebase_digest.md",
    "field_advisor_pre_notes": "./tmp/field_advisor_pre.md",
    "code_files": ["..."],
    "test_files": ["..."]
  },
  "timestamp_utc": "..."
}
```

When the skill is re-invoked: hash the incoming goal text, compare to `goal_hash`. If match, resume from `last_completed_phase + 1`. If mismatch, ask the user whether to restart fresh or keep the prior state.

Create `./tmp/` if absent. **Never** use `/tmp/` — agent sandboxes deny it.

### Field Advisor knowledge cache (persistent, project-level)

Separate from `./tmp/` (which is per-run scratch), the skill maintains a **persistent cache** at `./.research_executor/` for the Field Advisor's field-level output. Layout:

```
./.research_executor/
  field_knowledge_<slug>.md       # one file per field detected in this project
  field_advisor_index.json        # registry of cached fields with timestamps
```

The cache survives across invocations of the skill, across different goals, as long as the project's field doesn't change. On a cache hit, the Phase-2 Field Advisor skips the expensive paper/citation sweep (5–30 min on cold) and only produces the goal-specific delta (under 2 min). See Phase 2 for the branching logic.

Users can force a refresh by deleting `./.research_executor/field_knowledge_<slug>.md`. The skill never overwrites the cache automatically.

---

## Pre-flight model vigilance (runs at skill start, before P1)

The skill currently hardcodes:
- Field Advisor: **Opus 4.7** (`claude-opus-4-7`)
- P4 prep (distiller + API contract author): **Opus 4.7**
- Author-Code / Author-Tests: **Sonnet 4.6** (`claude-sonnet-4-6`)
- Runner: **Sonnet 4.6**
- Verifier: **Sonnet 4.6**
- P4d contract reconstructor: **Opus 4.7**
- Summarizer: **Opus 4.7**

These choices were made when the skill was written. Newer models may exist by the time the user invokes the skill — and for the high-reasoning phases (Field Advisor, Summarizer, contract reconstructor) a meaningfully better model can change the quality ceiling. The orchestrator must surface model-version vigilance at skill start so the user can opt into upgrades.

**Steps:**

1. At skill start (immediately after the Activation check passes), the main agent enumerates the model IDs the skill currently uses (above list).

2. Compare against what the main agent knows about currently-available Claude models. Specifically check whether a newer model exists for the Opus tier (since Field Advisor + Summarizer + contract reconstructor are the most quality-sensitive). Examples of meaningful upgrades to look for:
   - A higher version-number Opus (5.x, 4.8, 4.9) is publicly available.
   - A new model tier purpose-built for reasoning (think "extended thinking" successor) that would help Field Advisor's citation sweep or Summarizer's structuring.
   - The hardcoded Sonnet version is several releases behind current.

3. If a meaningful upgrade exists for one or more phases, emit a single non-blocking message:

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

If no newer models are known to be available, this section is skipped silently.
```

4. Wait briefly for user reply. If no reply within reasonable time, proceed with NO_SWAP (the safe default). Record decision in state JSON under `model_vigilance_decision` and `model_overrides` (a map of phase → model_id).

5. For the rest of the run, use the resolved model IDs from `model_overrides` instead of the hardcoded defaults.

**When to surface this check:**
- Always run the comparison.
- Surface to user ONLY if at least one phase has a newer model worth recommending.
- If everything is current, log "model vigilance: all phases up to date" to state JSON and proceed silently.

**When NOT to surface:**
- During resumed runs (the model decision from the prior session persists via state JSON's `model_overrides`).
- If the user has set a `--no-model-vigilance` flag in the goal text (record as `model_vigilance_decision: skipped_per_goal`).

This check is the skill's way of avoiding silent obsolescence. It's also why the skill's frontmatter lists model IDs explicitly — when a maintainer reads the skill a year from now, they can see what was current at write-time and what's been auto-overridden since.

---

## TodoList scaffold

At skill start, create a TodoList with one entry per phase (P1–P10). Mark each in_progress → completed in sequence. Update phase-state JSON in parallel.

---

## Phase 1 — Codebase intake

**Precondition:** the Clarification gate (see Activation section) has been passed. If the user's invocation was thin and they have not yet answered the missing-fields questions, STOP — do not begin Phase 1.

**Goal:** produce `./tmp/codebase_digest.md` containing a summary of every relevant project file so downstream subagents have full context without re-reading.

**Steps:**

1. `mkdir -p ./tmp` (if absent).
2. Read these files when present (use Glob then Read in parallel):
   - All top-level `*.md` in the working dir and one level up.
   - `PAPERS.md`, `METHODOLOGY.md`, `README.md`, `CLAUDE.md` and any relevant md files at any depth.
   - `**/*_SUMMARY.md` and `**/SUMMARY.md` (prior-phase writeups — the chain of prior work).
   - `detailed_steps.md`, `notes/**/*.md` if present.
   - Any `*.bib` or `references.md`.
3. If any file > 2000 lines, read in chunks and summarize.
4. Write a digest to `./tmp/codebase_digest.md` with sections:
   - **Project overview** — pulled from README/CLAUDE.md.
   - **Methodology pointers** — which METHODOLOGY section this task lives in.
   - **Prior-phase summaries** — one-paragraph distillation per `*_SUMMARY.md`.
   - **Reading list / papers** — annotated entries from PAPERS.md.
   - **Conventions** — output organization rules, naming, path policy.
   - **Critical user instructions** — anything in CLAUDE.md flagged as non-negotiable.
5. Detect the **field** from the goal text + digest. Examples:
   - mech-interp, sparse autoencoders, probing → "mechanistic interpretability"
   - alignment, RLHF, debate → "AI safety"
   - tokenizer, attention → "transformers / NLP"
   - convnets, ViT → "computer vision"
   - PPO, value functions → "reinforcement learning"
   - Bayesian, MCMC, prior → "Bayesian statistics"
   Record in state JSON as `field_detected`.

**Output:** `./tmp/codebase_digest.md` + updated state JSON.

---

## Phase 2 — Field Advisor (pre)

**Goal:** get a senior domain expert's review of the goal + plan, with full access to web research.

The pre-flight output has two layers:

- **Field-level knowledge** — papers, canonical pitfalls, verification checks the field expects, exemplars to emulate. Same every run for this field, in this project. **Cached persistently.**
- **Goal-level review** — review of THIS specific goal's approach. Different every run. **Always regenerated.**

The Field Advisor takes 5–30 min on a cold run because the web/citation sweep dominates. On warm runs, the cached knowledge is reused and only the goal-level delta is produced — typically under 2 min.

### Cache layout

- Project-scoped cache directory: `./.research_executor/` (create with `mkdir -p` if absent — this is a stable project-level folder, NOT `./tmp/`).
- Field-knowledge file: `./.research_executor/field_knowledge_{field_slug}.md` where `field_slug` is kebab-case of `field_detected` (e.g. `mechanistic-interpretability`, `bayesian-statistics`, `reinforcement-learning`).
- Cache index: `./.research_executor/field_advisor_index.json` — maps `field_slug → {created_utc, exemplars, paper_count, file_size}`. The `created_utc` field is what powers the staleness check.
- Goal-level review (always fresh): `./tmp/field_advisor_pre.md` — unchanged path. Always references the cache file by relative path.
- To force regeneration: the user deletes `./.research_executor/field_knowledge_<slug>.md`. The skill never overwrites an existing cache file automatically; on cache-miss it creates, on cache-hit it reads.

### Cache staleness (WARN, not block)

On every cache hit, the orchestrator checks the age of the cache file:

```bash
age_days=$(( ( $(date +%s) - $(date -r ./.research_executor/field_knowledge_<slug>.md +%s) ) / 86400 ))
```

- **age ≤ 30 days:** silent, proceed warm-mode normally.
- **age > 30 days:** emit a non-blocking warning to the user:
  ```
  ⚠ Field-knowledge cache for "{field_detected}" is {age_days} days old (created {created_utc}). Field knowledge may have shifted — new papers, retractions, new state-of-the-art methods. Options:
    1. Use the cache anyway (default — fast).
    2. Regenerate by deleting ./.research_executor/field_knowledge_<slug>.md and re-running. The next P2 will produce a fresh cache (5–30 min cold sweep).
    3. Keep cache but ask the Field Advisor to perform a "delta sweep" — read the existing cache and only WebSearch for what's changed since `created_utc`. Records updates as an addendum.
  ```
  Wait briefly for user input; if no reply, proceed with option 1 (use cache) and log the staleness to state JSON. Record in state JSON: `field_advisor_cache_age_days`, `field_advisor_cache_staleness_warning_issued` (bool), `field_advisor_cache_staleness_user_choice` (1|2|3|"timeout").

Why 30 days, not 90: mech-interp / AI-safety publishes weekly; a quarter-old "canonical pitfalls list" misses recent work like the latest steering / manifold methods. 30 is the right cadence for a fast-moving field. For slow-moving fields (Bayesian methods, classical ML), the user can manually extend by editing this threshold in their copy of the skill.

### Branching (MANDATORY — all four steps must execute, in order)

A skipped cache write is a **P2 phase failure**, not a soft warning. Phase 3 may not begin until the post-spawn gate (step 4) passes. The persistent cache lives outside `./tmp/`, and no other phase touches it — if P2 doesn't write it, nothing does.

**Step 1 — Pre-spawn directory creation (unconditional).** Before any check, every invocation, run via Bash:
```bash
mkdir -p ./.research_executor
```
Do NOT skip this on the assumption the directory exists. `mkdir -p` is idempotent and cheap. Skipping it is the single most common cause of cold-mode failure.

**Step 2 — Cache existence check via real Bash filesystem test (not pseudocode, not memory).**
```bash
field_slug=<slugify(field_detected)>   # e.g. mechanistic-interpretability
cache_path="./.research_executor/field_knowledge_${field_slug}.md"
if test -s "$cache_path"; then mode="warm"; else mode="cold"; fi
```
`test -s` (not `test -f`) — the file must exist **and** be non-empty. An empty file from an aborted prior run must be treated as cache-miss. Do NOT infer mode from prior conversation state, prior phase outputs, or recollection — only from the filesystem at this instant.

**Step 3 — Spawn ONE Agent** with the matching mode-specific prompt below (same model + tools).

**Step 4 — Post-spawn verification gate (BLOCKING).** After the subagent returns, verify via Bash:
- **Cold mode:** all three of `./.research_executor/field_knowledge_${field_slug}.md`, `./.research_executor/field_advisor_index.json`, and `./tmp/field_advisor_pre.md` must exist and be non-empty (`test -s`).
- **Warm mode:** `./tmp/field_advisor_pre.md` must exist and be non-empty.

If the gate fails: **DO NOT proceed to Phase 3.** Re-spawn the Field Advisor with an explicit "you did not produce file X — produce it now, the existing artifacts are present at Y/Z" prompt. Repeat until the gate passes. Record `field_advisor_cache_gate_passed: true` and `field_advisor_cache_gate_attempts: <int>` in state JSON. If three re-spawn attempts all fail, halt the skill and surface to the user — do not silently advance.

### Spawn via `Agent` tool with:
- `subagent_type: general-purpose`
- `model: opus`
- All tools available (the general-purpose agent has `*` access).

### Prompt template — COLD mode (no cache hit)

```
You are a senior researcher in {field_detected}. You operate at the level of {field_exemplars} — that is, you know the canonical papers, the active researchers, the standard methodologies, the field's preferred failure modes to test for, and what a reviewer at a top venue (NeurIPS, ICLR, ICML for ML; equivalent for other fields) would flag.

You have full tool access: Read, Glob, Grep, WebSearch, WebFetch, Bash. Use them generously — there is no rush. Take as much time as you need. Read papers, follow citation trails, verify claims against primary sources. The user wants depth, not speed.

# Task
The user is about to execute the following research task. Read it, the codebase digest, and any papers/methodology this depends on. Then produce TWO files:

1. `./.research_executor/field_knowledge_{field_slug}.md` — the **persistent field-knowledge cache** for this project. Future invocations of this skill on different goals in the same project will reuse this file, so it should contain only field-level content (no references to THIS specific goal). Sections:
   a. **Field exemplars.** Name 5–10 researchers / groups whose work defines the field. One sentence each on what they're known for.
   b. **Top 8–15 most relevant papers for this field.** Full citations. One sentence each on why it matters. Include both classical foundations and recent (last 2 years) work. Follow citation trails via WebFetch.
   c. **Field-standard pitfalls.** Specific failure modes the field has identified. Cite the paper that documented each. Examples for mechanistic interpretability: probe leakage, basis-rotation skeptic checks, Wilson-interval boundary FP drift, selectivity controls (Hewitt-Liang 2019), polysemantic neurons.
   d. **Field-expected verification checks.** Concrete sanity checks a domain expert always wants to see in this field's artifacts. Examples: "report Wilson 95% CI for every accuracy claim," "include a shuffled-label control for every probe class," "verify PCA is fit on train only."
   e. **Exemplar artifacts to emulate.** 2–3 papers whose method/exposition is a model to copy in this field. For each, what specifically should be borrowed.

2. `./tmp/field_advisor_pre.md` — the **goal-specific review** of THIS task's approach. Sections:
   a. **Approach review.** Prefer "this fails because X" over approval. For each component of the plan, ask: would a top reviewer accept this? Is the comparison fair? Are controls sufficient? Is the metric well-defined? What's missing? Reference the cache file's pitfall list — say which pitfalls THIS approach is exposed to.
   b. **Top 3 must-address items.** The single most important concerns specific to this goal.
   c. **Goal-specific sanity checks.** Beyond the field-standard checks in the cache, what does THIS task need?

After writing both files, also create/update `./.research_executor/field_advisor_index.json`:
```json
{
  "{field_slug}": {
    "created_utc": "<ISO timestamp>",
    "field_detected": "{field_detected}",
    "exemplars": "{field_exemplars}",
    "paper_count": <int — count of papers in section b>,
    "file_size_bytes": <int>
  }
}
```
If the file already exists with other field slugs, merge — do not overwrite other entries.

## Goal (verbatim — for the goal-level file only)
{goal_text}

## Codebase digest
{contents of ./tmp/codebase_digest.md}

# Constraints
- DO NOT modify any project files outside `./.research_executor/` and `./tmp/`.
- DO NOT propose the puzzle answer or the task conclusion. Provide method/quality feedback only.
- BE SPECIFIC. Vague approvals ("looks good") are worse than nothing. If you can't find a specific concern, say "no concerns found after checking X, Y, Z."
- Keep the cache file goal-agnostic. Anything referencing THIS specific goal belongs in `./tmp/field_advisor_pre.md`, not the cache.

# Mandatory deliverables — self-verify BEFORE returning

The persistent cache (`./.research_executor/field_knowledge_{field_slug}.md` + `./.research_executor/field_advisor_index.json`) is **co-equal** with the goal-specific review. It is not optional, not "nice to have," and not deferrable to a later phase. No other phase writes it. If you skip it, the project loses cache reuse permanently for this field.

Before sending your final message, run via Bash and confirm each file exists and is non-empty:
```bash
wc -c ./.research_executor/field_knowledge_{field_slug}.md
wc -c ./.research_executor/field_advisor_index.json
wc -c ./tmp/field_advisor_pre.md
```
If any of the three prints `0 ./...` or errors with "No such file," you have **not** completed the task. Write the missing file and re-run the check. Repeat until all three report non-zero byte counts. Do not return until all three pass.

Return only when all three files exist and are non-empty. Final message MUST include: the three paths, byte counts for each, paper count in the cache file, top-3 must-address items.
```

### Prompt template — WARM mode (cache hit)

```
You are a senior researcher in {field_detected}. The field-knowledge cache for this project already exists at `./.research_executor/field_knowledge_{field_slug}.md` (built during a previous invocation of this skill). Read it.

# Task
Produce ONLY the goal-specific review for THIS task. Do NOT re-run the full paper sweep — the cache covers field-level content. Your job is to apply the cached knowledge to this specific goal.

You may still use WebSearch / WebFetch for spot-checks if something in the goal references a specific paper or method you want to verify, but a full citation sweep is not needed.

# Inputs to read (in order)
1. `./.research_executor/field_knowledge_{field_slug}.md` — cached field knowledge. Familiarize yourself with its pitfalls and verification-checks sections before reviewing the goal.
2. `./tmp/codebase_digest.md` — current project state.
3. The goal text below.

# Goal (verbatim)
{goal_text}

# Your single deliverable: `./tmp/field_advisor_pre.md`

Sections:
a. **Cache reference.** One line: "Reading field knowledge from `./.research_executor/field_knowledge_{field_slug}.md` (cached {created_utc})." If you spot anything in the cache that looks stale (a paper retracted, a recent finding that contradicts a cached pitfall, etc.), note it here and propose what to update.
b. **Approach review.** Apply the cached pitfalls + verification checks to the goal. Say which pitfalls THIS approach is exposed to and which checks the plan honors / skips. Prefer "this fails because X" over approval.
c. **Top 3 must-address items** specific to this goal.
d. **Goal-specific sanity checks.** What does THIS task need beyond the cache's standard checks?

# Constraints
- DO NOT regenerate the cache. Leave `./.research_executor/field_knowledge_{field_slug}.md` untouched.
- DO NOT propose the puzzle answer or the task conclusion.
- BE SPECIFIC. Vague approvals are worse than nothing.

Return when `./tmp/field_advisor_pre.md` is complete. Final message: path of the file, top-3 must-address items, whether the cache appears current.
```

### Placeholder fillers:
- `{field_detected}` — from Phase 1.
- `{field_slug}` — kebab-case of `field_detected`. Examples: `mechanistic-interpretability`, `ai-safety`, `transformers-nlp`, `computer-vision`, `reinforcement-learning`, `bayesian-statistics`.
- `{field_exemplars}` — auto-generate by field. Examples:
  - mech-interp: "Neel Nanda, Chris Olah, Anthropic interpretability team, Catherine Olsson, Tom McGrath, Stefan Heimersheim"
  - alignment: "Paul Christiano, Jan Leike, Dan Hendrycks, Beth Barnes"
  - NLP: "Yoav Goldberg, Christopher Manning, Yonatan Belinkov, Sebastian Ruder"
  - vision: "Kaiming He, Lucas Beyer, Olaf Ronneberger, Oriol Vinyals"
  - RL: "John Schulman, Sergey Levine, David Silver, Joelle Pineau"
  - Bayesian: "Andrew Gelman, Michael Betancourt, Aki Vehtari"
- `{goal_text}` — the user's goal verbatim.
- `{created_utc}` — pulled from the index JSON on warm runs.

### Outputs (verified by the post-spawn gate in Branching step 4):
- **Cold run (MANDATORY all three):** `./.research_executor/field_knowledge_{field_slug}.md` (new), `./.research_executor/field_advisor_index.json` (created or merged), `./tmp/field_advisor_pre.md` (new). If any is missing or zero-byte after the Field Advisor returns, the gate re-spawns the subagent until all three exist on disk. Three failed re-spawn attempts halt the skill.
- **Warm run (MANDATORY):** `./tmp/field_advisor_pre.md`.
- **State JSON** gets `field_advisor_cache_path`, `field_advisor_cache_mode` ("cold"/"warm"), `field_advisor_cache_gate_passed` (bool), `field_advisor_cache_gate_attempts` (int), and `field_advisor_pre_notes`.

---

## Phase 3 — advisor() pre-flight (with abort gate)

Call `advisor()` with no parameters. The advisor sees the full conversation including the goal, codebase digest, and Field Advisor's review.

### Step 3.1 — Classify every flagged trap by severity

For each trap the advisor returns, classify it as **block** or **warn**:

- **block** — the trap, if uncorrected, makes the planned P4–P10 work likely wasted. Examples:
  - "Your metric doesn't measure what the goal claims it measures."
  - "The comparison is unfair: train/test leakage / probe sees its own labels / control is mis-specified."
  - "The goal cites paper X but X's result is the opposite of what the goal assumes."
  - "Required read-only input file does not exist at the path the goal names."
  - "The hard rules contradict each other (e.g. seed pinned AND non-determinism required)."
  - "The deliverable spec cannot be produced from the inputs the goal lists."
- **warn** — addressable inside the workload or tests; the run can proceed and bake the fix into P4. Examples:
  - "Use Wilson interval not Wald."
  - "Add a shuffled-label control to every probe class."
  - "Cap `max_iter` higher for class-imbalanced features."

When in doubt: ask "would a top-venue reviewer reject the submission for this?" → block. "Would they ask for a revision?" → warn.

### Step 3.2 — Abort gate (BLOCKING if any block-severity trap is present)

After classification:

- **Zero block-severity traps** → proceed to P4. Continue silently.
- **One or more block-severity traps** → **STOP. Do not spawn any P4 subagent yet.** Emit a single message to the user with this exact structure:

```
P3 abort gate — advisor() flagged N block-severity trap(s).

Each one, if uncorrected, likely makes the P4–P10 budget (Opus prep + 2 Sonnet authors + Runner + Verifier + Summarizer) wasted compute. Review and choose:

[Block trap 1]
  Advisor's wording (verbatim): "…"
  Why it blocks: <one sentence>
  Suggested resolution: <amend goal | accept and proceed anyway | abort skill>

[Block trap 2]
  …

Your options:
  1. PROCEED — accept the trap(s) and run P4–P10 anyway. (I'll record this in state JSON under `p3_abort_gate_decision: proceed_despite_block_traps`.)
  2. AMEND — give me corrected goal text or a corrected hard-rule, then I'll re-run P3 once and re-evaluate the gate.
  3. ABORT — stop the skill. State is preserved; you can re-invoke later with a fresh goal.

Warn-severity traps (will be addressed inside the workload regardless of your choice):
  - [warn trap 1]
  - [warn trap 2]
```

Wait for an explicit reply. **Do not silently proceed on timeout, do not infer intent from prior messages.** If the user replies "PROCEED" without addressing the blocks, that is a valid choice — log it, but log it loudly so they can spot it in the P10 final pass.

### Step 3.3 — Record the gate decision in state JSON

Add to `./tmp/research_executor_state.json`:
```json
{
  "p3_advisor_traps": [{"text": "…", "severity": "block|warn"}, …],
  "p3_block_severity_count": <int>,
  "p3_abort_gate_decision": "no_blocks | proceed_despite_block_traps | amended_and_rerun | aborted",
  "p3_abort_gate_user_response_utc": "<ISO timestamp or null>"
}
```

If the decision is `aborted`, halt the skill and emit a brief shutdown message. Do NOT touch P4+.

**What to do with the (surviving) traps:**
- Every warn trap (and every block trap the user chose to PROCEED past) becomes an entry in `{advisor_traps}` to be injected into the Author's prompt.
- If advisor flags conflicts between Field Advisor's review and the goal, that is **always** block-severity. The two pre-flight reviewers must agree before the skill commits Opus + Sonnet budget.

**Output:** classified trap list + abort-gate decision recorded in state JSON. No standalone file.

---

## Phase 4 — Author phase (prep → 2 parallel authors)

P4 is the most expensive phase in the skill and the most context-rot-prone if done as a single subagent (single Sonnet writing both workload and ~80+ tests against a 46 KB Field Advisor file is the historical failure mode). It is broken into three steps:

- **Step 4a — Prep (Opus, serial, ~60s).** Two cheap Opus calls that produce small shared inputs for the two parallel authors:
  - `./tmp/field_advisor_pre_distilled.md` — extracts ONLY pitfalls + verification-checks + top-3 must-address from the full Field Advisor file. Target size ≤ 6 KB.
  - `./tmp/api_contract.md` — function signatures, return shapes, CSV column orders, CLI flags, output paths. The contract both authors agree to. **Format rule: one signature / one output / one CLI flag per line, no prose explanations.** Length is whatever the goal's deliverable list demands — typically 40–150 lines for non-trivial tasks.
- **Step 4b — Authors (Sonnet, PARALLEL).** Spawn Author-Code and Author-Tests in the SAME message (two tool-call blocks). Each reads only the distilled file + API contract + goal — not the full Field Advisor pre.md, not each other's output. Cuts wall-clock ~50% and keeps each author's prompt small.
- **Step 4c — Joint verification (main agent).** After both return, confirm test file imports match workload symbols.

---

### Step 4a-i — Distill the Field Advisor pre file (Opus prep call)

**Spawn via `Agent` tool with:**
- `subagent_type: general-purpose`
- `model: opus`

**Prompt:**

```
You are the FIELD ADVISOR DISTILLER. Your only job: extract the 3 sections downstream subagents need, drop everything else.

# Inputs
Read ./tmp/field_advisor_pre.md (the full Field Advisor pre file — may be 30–60 KB).
Read ./.research_executor/field_knowledge_{field_slug}.md if present.

# Output
Write ./tmp/field_advisor_pre_distilled.md with EXACTLY these sections, in this order:

## Pitfalls (every one — bulleted, one line each)
Pull from the full file's "field-standard pitfalls" section AND any pitfalls flagged inline in the approach review. Format: "- [pitfall name] — [one-sentence description] (source: [paper or §ref])".

## Verification checks (every one — bulleted, one line each)
Pull from the "field-expected verification checks" section AND any check requested in the approach review. Each must be assertable in a test: phrase it as an invariant ("X must equal Y", "every row must have Z").

## Top-3 must-address (verbatim quotes from the full file)
Three numbered items, each one paragraph max, copied verbatim from the "Top 3 must-address items" section of the full file.

# Constraints
- Target total length ≤ 6 KB. If you exceed, you're including too much narrative — strip it.
- Do NOT add interpretation or summary text. Each line is either a pitfall, a check, or a quoted must-address item.
- Do NOT propose puzzle answers.
- Use `i*` notation for the candidate feature; never name it.

Return when written. Final message: byte count of the distilled file and the three section counts.
```

**Output:** `./tmp/field_advisor_pre_distilled.md` (≤ 6 KB).

---

### Step 4a-ii — Emit the API contract (Opus prep call)

**Spawn via `Agent` tool with:**
- `subagent_type: general-purpose`
- `model: opus`

**Prompt:**

```
You are the API CONTRACT AUTHOR. You produce the shared spec that two parallel author subagents will read. They will not see each other's work — they only agree because they both implement to your contract.

# Inputs
Read ./tmp/codebase_digest.md (conventions, prior-phase file naming).
Read ./tmp/field_advisor_pre_distilled.md.

# Goal (verbatim from user)
{goal_text}

# Read-only inputs the workload may consume
{read_only_paths_from_goal}

# Output dirs (where the workload writes)
{output_dirs_from_goal}

# Deliverables list
{deliverables_from_goal}

# Output
Write ./tmp/api_contract.md with EXACTLY these sections:

## Module(s)
List each `.py` file the workload will produce: `path/to/module.py`.

## Public functions
For each public function the workload exposes, on one line:
`function_name(arg1: type, arg2: type, ...) -> return_type  # one-line purpose`
Group by module. Include keyword-only args.

## Dataclasses / typed dicts (if any)
For each, the field name → type mapping.

## CSV outputs
For each CSV the workload writes, on one line:
`path/relative/to/output_dir.csv  — columns (in order): col1, col2, col3, ...`

## Plot outputs
For each plot, on one line:
`path.png  — [bar|line|hist|scatter|grid], x=…, y=…, what it shows`

## CLI surface (every entry-point script)
For each `python <script>.py …` invocation, list flags with their type and default:
`--results-dir PATH (required)`, `--seed INT (default 42)`, etc.

## Invariants Tests Must Assert
3–8 cross-file or cross-function invariants the test file must check (e.g. "every CSV has exactly len(features) rows", "gap_X = ceiling - probe_X within 1e-9"). Phrased as testable predicates.

# Constraints
- **Format rule: one signature / one output / one CLI flag per line, no prose explanations.** Each row is dense and machine-readable. Total length is whatever the deliverable list demands — do NOT pad and do NOT compress to fit an arbitrary budget. A goal with 4 modules × 3 functions + 6 CSVs + 4 plots will produce ~80 lines; that's correct.
- Names must be specific (`compute_intrinsic_dim`, not `compute_metric`). Both authors will use these names verbatim — drift here breaks the parallelization.
- Do NOT propose puzzle answers. Use `i*` for the candidate feature.
- Do NOT include implementation hints or pseudocode. Signatures and shapes only.

Return when written. Final message: byte count, count of public functions, count of CSV outputs, count of plot outputs, count of invariants.
```

**Output:** `./tmp/api_contract.md` (one row per signature / output / flag, length determined by deliverable count).

---

### Step 4b — Spawn Author-Code and Author-Tests IN PARALLEL

**CRITICAL: spawn both subagents in the SAME message (two `Agent` tool calls in one assistant turn).** If you spawn them sequentially the parallelization win is lost.

#### Author-Code

**Spawn via `Agent` tool with:**
- `subagent_type: general-purpose`
- `model: sonnet`

**Prompt:**

```
You are AUTHOR-CODE. You write workload code ONLY. You do NOT write tests — a parallel subagent (AUTHOR-TESTS) writes them. You do NOT execute anything — a separate Runner will run your code.

# Inputs (read in order)
1. ./tmp/api_contract.md — the contract you must implement. Function names, signatures, CSV columns, CLI flags, output paths come from here verbatim. Drift breaks the parallel test author.
2. ./tmp/field_advisor_pre_distilled.md — pitfalls and verification checks the workload must address.
3. ./tmp/codebase_digest.md — only for path conventions; do not re-derive deliverables from it.

# Goal (verbatim from user)
{goal_text}

# Read-only inputs (DO NOT modify)
{read_only_paths_from_goal}

# Hard rules
{hard_rules_from_goal}

# Advisor-flagged traps
{advisor_traps}

# Phrasing
No phrasing constraints in code, comments, prints, variable names, or plot titles. Use direct, natural language — `country_is_candidate = True` is fine, `print(f"feature {i_star} is non-linear")` is fine. The strict-phrasing rule applies ONLY to the final Summarizer output (P9), not to anything the workload writes. Internal artifacts (CSVs, JSONs, run logs) can name features and findings directly.

# Determinism stack (ON by default; disable only if goal says "non-deterministic ok")
- `seed_everything(seed)` covering numpy + python random + torch.
- `torch.use_deterministic_algorithms(True)`.
- `os.environ["CUBLAS_WORKSPACE_CONFIG"] = ":4096:8"`.
- DataLoader: `generator=torch.Generator().manual_seed(seed)`, `worker_init_fn`, `num_workers=0`.
- sklearn estimators: pass `random_state=seed`.

# Plots (ON by default; disable if goal says "no plots")
Produce every plot listed in the API contract's "Plot outputs" section. Each: labeled axes with units, legend, caption, ceiling reference lines where applicable. `matplotlib.use("Agg")` at import top.

# Path discipline
- Outputs ONLY under {output_dirs_from_goal}.
- NEVER write to `/tmp/`. Use `./tmp/` for scratch.
- CLI flags exactly as the API contract specifies.

# What you must NOT do
- Do NOT write any file under `tests/`. AUTHOR-TESTS owns that directory.
- Do NOT execute pytest or the workload. Runner will.
- Do NOT modify upstream phase outputs.
- Do NOT name the answer/suspect in code, comments, or prints.
- Do NOT deviate from the API contract — if you think the contract is wrong, write a note to ./tmp/author_code_contract_concerns.md and proceed with the contract as written.

# Self-verification before declaring done
1. Re-Read the workload file(s).
2. `python -c "import ast; ast.parse(open('<workload>.py').read())"` per file.
3. Confirm every public function in the API contract is implemented with the contract's exact name and signature.
4. Report: paths written, count of public functions, count of CSV-writing lines, count of plot-writing lines.

Begin.
```

#### Author-Tests

**Spawn via `Agent` tool with:**
- `subagent_type: general-purpose`
- `model: sonnet`

**Prompt:**

```
You are AUTHOR-TESTS. You write the test file ONLY. You do NOT write workload code — a parallel subagent (AUTHOR-CODE) writes it. You will not see the workload while writing — you assert against the API contract instead. This is intentional: independent tests catch implementation bugs that "implement-then-test" workflows miss.

# Inputs (read in order)
1. ./tmp/api_contract.md — names, signatures, CSV columns, CLI flags, output paths. Import from these names verbatim. The contract's "Invariants Tests Must Assert" section is the spine of your test file.
2. ./tmp/field_advisor_pre_distilled.md — every pitfall needs a regression test; every verification check needs an assertion test.
3. ./tmp/codebase_digest.md — only for naming conventions.

# Goal (verbatim from user)
{goal_text}

# Read-only inputs (workload reads these; tests may also read for fixtures)
{read_only_paths_from_goal}

# Hard rules
{hard_rules_from_goal}

# Advisor-flagged traps (write at least one test per trap)
{advisor_traps}

# Phrasing
No phrasing constraints in test names, docstrings, or assertions. Tests can name features and findings directly (`test_country_intrinsic_dim_above_threshold`). Do NOT write a strict-phrasing grep test against the workload source — that constraint applies to the Summarizer output, not the workload.

# Test plan (exhaustive)
Write tests/{test_filename} covering all of:
- Every public function in the API contract: schema, determinism (same seed → same output), edge cases (empty input, single-row input).
- Every CSV output in the contract: row count, column set, column order (test the contract's stated order verbatim), alphabetical/sort invariants if specified, value ranges.
- Every plot in the contract: writes a PNG > 1000 bytes given a stub workload run, or a deferred `@pytest.mark.integration` check on the real file.
- Every cross-file invariant from the contract's "Invariants Tests Must Assert" section.
- Every pitfall from the distilled Field Advisor file: one regression test each.
- Every verification check from the distilled Field Advisor file: one assertion test each.
- Integration tests gated by `@pytest.mark.integration` that skip when artifacts aren't present yet.

No fixed minimum count. Better 80 redundant tests than 40 with a missed invariant.

# What you must NOT do
- Do NOT write any non-test file. AUTHOR-CODE owns the workload.
- Do NOT Read the workload source if it exists yet. Tests must be derivable from the contract alone. (You may Read it AFTER you've written your tests, for a final sanity grep — but not before.)
- Do NOT execute pytest. Runner will.
- Do NOT name the answer/suspect in test names, docstrings, or assertions.

# Self-verification before declaring done
1. Re-Read your test file.
2. `python -c "import ast; ast.parse(open('tests/<file>.py').read())"`.
3. Confirm every import statement references a name present in the API contract (no invented names).
4. Report: path written, count of test functions, count of invariants covered, count of pitfall-regression tests.

Begin.
```

---

### Step 4c — Joint verification (main agent)

After BOTH authors return, the main agent runs via Bash:

```bash
# Confirm both authors wrote what they claimed
wc -c <workload_paths> tests/<test_file>

# Confirm test imports match workload symbols (the parallelization correctness check)
python -c "
import ast, sys
ws = ast.parse(open('<workload>.py').read())
ts = ast.parse(open('tests/<test_file>.py').read())
workload_names = {n.name for n in ast.walk(ws) if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef))}
test_imports = set()
for n in ast.walk(ts):
    if isinstance(n, ast.ImportFrom) and n.module and n.module.endswith('<workload_module>'):
        test_imports.update(a.name for a in n.names)
missing = test_imports - workload_names
if missing:
    print('CONTRACT DRIFT — tests import names workload does not expose:', missing)
    sys.exit(1)
print('contract check passed')
"
```

If contract drift is detected: re-spawn Author-Code with the missing names listed, OR re-spawn Author-Tests with a corrected import list — whichever side diverged from `api_contract.md`. The contract file is the tie-breaker.

---

### Step 4d — Contract round-trip (semantic anti-Goodharting check)

Step 4c catches **syntactic** drift (test file imports a name the workload doesn't expose). It does NOT catch **semantic** drift — e.g. the contract said "CSV columns in order: a, b, c" but Author-Tests read that as "columns {a, b, c} in any order" while Author-Code wrote them in the spec'd order. Tests pass against the looser interpretation. Both agents are internally consistent; they agree only by accident.

The round-trip catches this: a small Opus call reads ONLY the test file (not the workload, not the contract) and reconstructs what it thinks the contract is. The orchestrator then diffs that reconstruction against the real contract.

**Spawn via `Agent` tool with:**
- `subagent_type: general-purpose`
- `model: opus`

**Prompt:**

```
You are the CONTRACT RECONSTRUCTOR. You read only one input — a test file — and you reconstruct the API contract that the test file appears to assume. You will NOT see the real contract or the workload source. The orchestrator diffs your reconstruction against the real contract to catch where the test file silently disagreed.

# Input — read this file and nothing else
{test_file_path}

# Output
Write ./tmp/api_contract_reconstructed.md with EXACTLY these sections, mirroring the format used by ./tmp/api_contract.md (which you will NOT read):

## Module(s)
List the `.py` modules the tests import from. One per line.

## Public functions
For each function the tests call, on one line:
`function_name(arg1: type, arg2: type, ...) -> return_type  # one-line purpose inferred from how the test uses it`
If the test asserts on a return shape (`assert isinstance(result, pd.DataFrame)`, `assert result.shape == (8, 5)`, etc.), encode that in the return type.

## CSV outputs (inferred from any `read_csv(...)` or path-string assertions)
For each CSV path the tests read or check existence of, on one line:
`path  — columns (in the order the tests check them): col1, col2, col3, ...`
If the tests check `set(df.columns) == {...}` (unordered), say `unordered: {col1, col2, col3}` instead. This distinction is the whole point of the round-trip.

## Plot outputs
For each plot path the tests check, on one line:
`path.png  — what the tests assert about it (size, existence, content)`

## CLI surface
For each `python <script>` invocation in the tests, list the flags passed.

## Invariants the tests appear to enforce
3–8 bullets. Phrase as "tests assert that …" — e.g. "tests assert that intrinsic_dim.csv has exactly len(features) rows".

# Constraints
- Do NOT read any file other than {test_file_path}.
- Do NOT speculate beyond what the test file asserts. If a behavior isn't tested, do NOT include it.
- Use the SAME format the real contract uses (one row per signature/output/flag, no prose).
- Flag any test that uses `set()` comparisons on columns that should be ordered — list these in a final "## Ordering ambiguities" section.

Return when written. Final message: byte count, count of reconstructed functions, count of reconstructed CSVs, count of ordering-ambiguity flags.
```

**After the reconstructor returns, the main agent diffs:**

```bash
# Side-by-side diff on the two contract files
diff -u ./tmp/api_contract.md ./tmp/api_contract_reconstructed.md > ./tmp/api_contract_diff.txt 2>&1 || true
wc -l ./tmp/api_contract_diff.txt
```

**Classify diff results:**
- **Trivial** (formatting whitespace, blank-line differences, minor wording in comments): pass.
- **Semantic** (different function name, different column order, unordered-vs-ordered column set, missing CSV/plot, extra parameter): **CONTRACT ROUND-TRIP FAILURE.**

On round-trip failure:
- Open `./tmp/api_contract_diff.txt` and identify which side is wrong.
- Re-spawn Author-Tests with the corrected interpretation as an additional input ("the contract says column order is X; your tests asserted {set} equality which doesn't catch reordering — add the ordered-check"), OR re-spawn Author-Code if the workload genuinely doesn't match the contract.
- The real `api_contract.md` is the tie-breaker, not the reconstruction.

Record in state JSON: `contract_roundtrip_diff_lines` (int), `contract_roundtrip_passed` (bool), `contract_roundtrip_attempts` (int).

**Output of Step 4d:** `./tmp/api_contract_reconstructed.md` + `./tmp/api_contract_diff.txt` + updated state JSON.

---

**Phase 4 outputs (cumulative):** workload `.py` file(s) + author test file + `./tmp/api_contract.md` + `./tmp/api_contract_reconstructed.md` + `./tmp/api_contract_diff.txt` + `./tmp/field_advisor_pre_distilled.md`. Update state JSON with `api_contract_path`, `api_contract_reconstructed_path`, `field_advisor_pre_distilled_path`, `contract_check_passed`, `contract_roundtrip_passed`.

---

## Phase 5 — Runner subagent

**Spawn via `Agent` tool with:**
- `subagent_type: general-purpose`
- `model: sonnet`

**Prompt template:**

```
You are the RUNNER subagent. The Author has produced {workload_file} and {test_file}. Your job: execute. Up to 3 fix-and-retry iterations.

# Working directory
{working_dir}. Venv at .venv/ if present — use .venv/bin/python.

# Hard rules
- DO NOT modify upstream phase outputs.
- DO NOT name the answer/suspect in your fixes, comments, or log messages.
- Outputs ONLY under {output_dirs_from_goal} and ./tmp/.
- Capture ConvergenceWarning and equivalent — non-convergence is a logged finding, never silently bumped.

# Sequence (strict order)

## Step 0 — sanity
```
.venv/bin/python -c "<import statements from the workload>"
.venv/bin/python -c "import ast; ast.parse(open('{workload_file}').read()); ast.parse(open('{test_file}').read())"
```
If either fails, STOP and report.

## Step 0.5 — provenance / reproducibility manifest (REQUIRED, cross-cutting rule #12)

For every output directory the workload will write to ({output_dirs_from_goal}), produce these files BEFORE running the workload:
```
mkdir -p {output_dir}
.venv/bin/python -m pip freeze > {output_dir}/env.txt
git -C . rev-parse HEAD > {output_dir}/git_rev.txt 2>/dev/null || echo "not a git repo or no commits" > {output_dir}/git_rev.txt
git -C . status --porcelain > {output_dir}/git_status.txt 2>/dev/null || echo "n/a" > {output_dir}/git_status.txt
# Hash every read-only input the workload will consume (paths come from {read_only_paths_from_goal}):
shasum -a 256 {read_only_paths_from_goal} > {output_dir}/inputs.sha256 2>&1
```
`git_status.txt` records whether the working tree was dirty at execution time — flag if non-empty in the final report. If `pip freeze` returns < 10 lines, the venv isn't actually activated — STOP and report.

## Step 1 — non-integration tests
```
mkdir -p tmp
.venv/bin/python -m pytest {test_file} -v -m "not integration" 2>&1 | tee tmp/run_log_step1.txt
```
Fix failures up to 3 retries. Fix workload code (not tests) unless a test is provably wrong vs the goal spec. If you change a spec'd behavior to make a test pass, STOP and report.

## Step 2 — workload
```
.venv/bin/python {workload_file} {cli_args_from_goal} 2>&1 | tee {output_dirs}/run_log.txt
```
Verify every deliverable artifact exists and is > 1000 bytes for plots, > 100 bytes for CSVs.

## Step 2.5 — hash outputs (REQUIRED, cross-cutting rule #12)

For every output directory:
```
( cd {output_dir} && shasum -a 256 *.csv *.json *.png 2>/dev/null > outputs.sha256 )
```
The outputs.sha256 file is part of the artifact set — list it in step 4's reporting.

## Step 3 — full test suite incl. integration
```
.venv/bin/python -m pytest {test_file} -v 2>&1 | tee tmp/run_log_step3.txt
```
Confirm 0 skips on integration tests, 0 failures.

## Step 4 — final verification (REPORT ONLY, don't write to disk)
- Test counts at each step.
- File sizes of all output artifacts.
- Top of any comparison CSV (`pandas.read_csv(...).to_string()`).
- Total runtime of step 2.
- Any captured warnings.

# Fix policy
- Test fails → fix workload code first.
- Test is provably wrong vs spec → fix test with written justification.
- Bug requires spec deviation → STOP, report, ask main agent.

# Reporting back
- Exact pass/fail/skip counts at each step.
- Diffs applied section if you edited any file (path, what changed, why).
- File listing of output dirs with sizes.
- First 15 and last 10 lines of the main run log.
- One-paragraph "ready for verifier?" assessment.

Begin.
```

**Output:** all artifact files on disk + Runner's report. Update state JSON.

---

## Phase 6 — advisor() mid-flight (with explicit data-quality pre-check)

P6 runs a deterministic data-quality scan FIRST, then calls advisor() with those findings as additional context. The pre-check catches the mechanical red flags that don't require domain expertise; advisor() then applies field judgment on top.

### Step 6.1 — Mechanical data-quality scan (main agent, Bash)

For every artifact in the result + plot dirs, the main agent runs these checks and writes results to `./tmp/data_quality_scan.md`:

```bash
# 1. NaN / Inf scan in every CSV
for f in {output_dirs}/*.csv; do
  python -c "
import pandas as pd, sys, numpy as np
df = pd.read_csv('$f')
n_nan = df.isna().sum().sum()
n_inf = np.isinf(df.select_dtypes(include=[np.number])).sum().sum()
if n_nan or n_inf:
    print(f'$f: NaN={n_nan} Inf={n_inf}')
"
done

# 2. Plot file sizes — flag every PNG < 5 KB (likely broken render)
find {plot_dirs} -name "*.png" -size -5k -exec ls -la {} \;

# 3. Single-class predictions — for any CSV with a binary prediction column, flag if min == max
for f in {output_dirs}/*.csv; do
  python -c "
import pandas as pd
df = pd.read_csv('$f')
for col in df.columns:
    if df[col].dtype in ['int64', 'bool'] and df[col].nunique() == 1:
        print(f'$f::$col is constant (value={df[col].iloc[0]}) — possible degenerate prediction')
"
done

# 4. Suspiciously round numbers — flag accuracies / floors that are exactly 0.95, 0.99, 1.00 (often saturated / clipped)
python -c "
import pandas as pd, glob
suspicious = [0.95, 0.99, 1.00, 0.90, 0.50]
for f in glob.glob('{output_dirs}/*.csv'):
    df = pd.read_csv(f)
    for col in df.select_dtypes(include=['float64']).columns:
        for v in suspicious:
            n = (df[col] == v).sum()
            if n >= 2:
                print(f'{f}::{col} has {n} rows exactly equal to {v} — verify this is real and not floor/ceiling clipping')
"

# 5. Row count sanity — every CSV should have a reasonable row count for what it represents (e.g. per-feature CSVs should have N_features rows)
for f in {output_dirs}/*.csv; do
  wc -l "$f"
done
```

Write the scan output to `./tmp/data_quality_scan.md` with three sections: **Flags raised**, **All-clear checks**, **What to ask advisor about**.

### Step 6.2 — advisor() call with data-quality findings as context

Call `advisor()` with no parameters. The advisor sees the full conversation including the data-quality scan. Mention in the call setup that the scan results are in `./tmp/data_quality_scan.md` and advisor should weigh them.

**What to do with advisor output:**
- Run any further verification commands advisor names (greps, head of CSVs, additional plots).
- Each advisor-flagged observation becomes a directive for Phase 9 Summarizer — append to `phase_8_directives` array in state JSON (will be merged with P8's directives at Phase 8).
- Each unresolved data-quality flag (from step 6.1 or advisor) is logged in state JSON under `p6_unresolved_dq_flags`. The Summarizer must mention any unresolved flag in the "Caveats" section.
- If advisor or the mechanical scan flags a BLOCKING issue (e.g. all predictions are the same class, every plot file is broken), surface to the user before proceeding to P7. Record the user's decision in state JSON.

**Output:** `./tmp/data_quality_scan.md` + advisor findings folded into `phase_8_directives` + state JSON updated with `p6_unresolved_dq_flags`, `p6_blocking_issues_surfaced` (bool).

---

## Phase 7 — Verifier subagent

**Spawn via `Agent` tool with:**
- `subagent_type: general-purpose`
- `model: sonnet`

**CRITICAL CONSTRAINT:** the Verifier prompt must contain ONLY:
1. The original goal spec.
2. The Field Advisor's pre-flight notes (`./tmp/field_advisor_pre.md`).
3. Instructions to Read the final workload code + produced artifacts.

The Verifier must NOT see:
- The Author's planning, design choices, or self-justifications.
- The Runner's traces, fix history, or applied diffs.
- The pre-flight `advisor()` trap list.

**Why:** if the Verifier reads the Author's reasoning, it copies assumptions instead of falsifying them. Spec-only is the falsification frame.

**Prompt template:**

```
You are the VERIFIER subagent. The Author produced {workload_file} and the Runner executed it successfully. Your job: write INDEPENDENT assertions in a NEW file tests/{verifier_test_filename} and run them.

You see ONLY:
1. The goal spec below (ground truth).
2. The Field Advisor's pre-flight notes at ./tmp/field_advisor_pre.md.
3. The final {workload_file} source (Read it).
4. The produced artifacts (Read/verify them).

You do NOT see the Author's planning, the Runner's traces, or the pre-flight advisor's trap list. This is deliberate — spec-only verification frame.

# Goal (verbatim ground truth)
{goal_text}

# Read-only inputs spec
{read_only_paths_from_goal}

# Hard rules (treat as invariants to verify)
{hard_rules_from_goal}

# Deliverables expected
{deliverables_from_goal}

# Definitions (spec-mandated — verify the implementation honors them)
{spec_definitions}

# Your test file: tests/{verifier_test_filename}

Categories to cover (each is a minimum; exceed where you can name an additional invariant):

A. Cross-file consistency (per pairing of CSV/source that must agree).
B. Per-CSV schema (column set, column order, row count, sort order, value ranges).
C. Determinism — re-run public functions with same seed → IDENTICAL output (float equality).
D. Hygiene specific to the field (per Field Advisor's checklist in ./tmp/field_advisor_pre.md).
E. Plot existence + non-empty (every spec'd plot file exists and is > 1000 bytes).
F. Sanity bounds (accuracies in [0, 1], counts non-negative, dimensions match).
G. Cross-method invariants (e.g., MLP ≥ LDA where MLP is the linear method's super-class).
H. Spec arithmetic (every derived column = its formula within 1e-9).

Target: exhaustive. No fixed minimum. Cover every named invariant from the spec + every Field Advisor verification check.

# Execution
After writing, run:
```
.venv/bin/python -m pytest tests/{verifier_test_filename} -v 2>&1 | tee tmp/run_log_verifier.txt
```
Up to 2 fix-iterations on the test file itself if a test assertion is wrong vs spec. Do NOT modify {workload_file} or the Author's test file. If a test catches a real bug in the workload, STOP and report it — do not patch.

# Reporting
- Test counts: written / passed / failed / skipped.
- Any failures with brief root cause.
- Confirmation: "{workload_file} was not modified."
- One-paragraph verifier verdict on artifact trustworthiness.

Begin.
```

**Output:** Verifier test file + report. Update state JSON.

---

## Phase 8 — Field Advisor (post) + advisor() final, in parallel

**Two parallel calls in a single message:**

### 8a. Field Advisor (post)

Same persona as Phase 2 (Opus 4.7, full tools, "take your time"). Different prompt — it now reviews the produced artifacts.

**Prompt template:**

```
You are the same senior researcher in {field_detected} from the pre-flight review (./tmp/field_advisor_pre.md). The task has now been executed. Your job: verify whether the produced artifacts meet field standards. Take as much time as you need; use all tools.

# Goal (verbatim)
{goal_text}

# Your prior review
Read ./tmp/field_advisor_pre.md. Every concern you raised should have been addressed — verify each one against the produced artifacts.

# Produced artifacts to review
- Workload: {workload_file}
- Author tests: {test_file} ({author_test_count} tests, all green)
- Verifier tests: tests/{verifier_test_filename} ({verifier_test_count} tests, all green)
- Result artifacts: {list of CSVs / outputs}
- Plots: {list of PNGs}
- Run log: {run_log_path}

Read all of these.

# Your deliverable: ./tmp/field_advisor_post.md

1. **Verification of pre-flight concerns.** For each pitfall you raised in Phase 2, was it addressed? Cite the specific code / test / artifact that addresses it.

2. **What would a reviewer object to?** Be adversarial. What's the weakest piece of evidence? Is any claim over-stated? Are there missing controls? Statistical power issues? Cherry-picked metrics?

3. **What's stronger than expected?** If a result is unusually clean / striking / well-controlled, name it — the Summarizer should foreground it.

4. **Field-quality verdict.** On a scale: would this hold up at (a) an internal lab presentation, (b) a workshop submission, (c) a top-venue main track? What specifically would block the higher tier?

5. **Suggestions for the Summarizer.** What specific observations / framings / caveats should the markdown writeup hit? What should be downplayed or omitted?

# Constraints
- DO NOT modify the produced artifacts.
- DO NOT propose conclusions; review quality.
- Be specific. "Looks fine" is worse than nothing.

Return when ./tmp/field_advisor_post.md is complete.
```

### 8b. advisor()

Call `advisor()` with no parameters. The advisor sees the full conversation including all prior phase outputs.

### 8c. Reconcile (BLOCKING if reviewers disagree on a load-bearing point)

After both 8a and 8b return, the main agent compares their conclusions. Two reviewers seeing the same artifacts may disagree — silently merging hides the conflict. Reconcile explicitly:

For each load-bearing claim, classify as:
- **Both agree** — fold into the Summarizer directive list, no surfacing needed.
- **One mentions, the other silent** — fold into directives, note which reviewer raised it (the Summarizer should know).
- **Active disagreement** — Field Advisor says X, advisor() says ¬X. **STOP.** Surface to the user with both verbatim quotes and ask which view should drive the Summarizer.

Write `./tmp/p8_reconcile.md` with three sections:

```
## Both reviewers agree on
- [unified observation 1]
- [unified observation 2]

## Only one reviewer raised
- (Field Advisor) [observation] — verbatim: "..."
- (advisor) [observation] — verbatim: "..."

## Active disagreements (BLOCKING — surface to user)
- Topic: [what they disagree about]
  - Field Advisor view: "[quote]"
  - advisor() view: "[quote]"
  - Recommendation: [which reviewer to weight, and why — based on the type of disagreement]
```

If the "Active disagreements" section is non-empty, emit a message to the user:

```
P8 reconcile — the two reviewers disagree on N points. Each disagreement could change what the Summarizer foregrounds. Please resolve before P9.

[Disagreement 1]
  Field Advisor: "..."
  advisor():     "..."
  Suggested resolution: [...]

[Disagreement 2] ...

Options per disagreement:
  - WEIGHT_FA — go with Field Advisor view (domain authority).
  - WEIGHT_ADV — go with advisor view (broader trap detection).
  - HEDGE — Summarizer mentions both, takes no side.
```

Wait for explicit reply. Record decisions in state JSON under `p8_disagreement_resolutions` (array of `{topic, resolution, user_response_utc}`).

**Output:** `./tmp/p8_reconcile.md` + unified Summarizer-directives list + state JSON updated with disagreement resolutions. If 8c reconcile passed (no disagreements OR all resolved), proceed to P9. Otherwise the skill remains paused.

---

## Phase 9 — Summarizer subagent

**Spawn via `Agent` tool with:**
- `subagent_type: general-purpose`
- `model: opus`  (Opus 4.7 — summary structuring is the bottleneck, not code generation; the small wall-clock cost is worth the cleaner narrative)

**Prompt template:**

```
You are the SUMMARIZER subagent. The Author wrote the workload, the Runner executed it, the Verifier confirmed correctness, and both Field Advisor (post) and advisor() reviewed the artifacts. Your job: write the human-readable summary markdown at {summary_md_path}. That is your ONLY deliverable.

# Working directory
{working_dir}

# Inputs (read all of these)
- ./tmp/codebase_digest.md
- ./tmp/field_advisor_pre.md
- ./tmp/field_advisor_post.md
- {workload_file}
- All produced artifacts (CSVs, JSONs)
- All produced plots (confirm existence + sizes; you don't need to render)
- {run_log_path}
- Any prior-phase summary documents pointed to by codebase digest (for the chain-back argument)

# Observations to hit (locked in by Phase 8 reviews — DO NOT flatten these)
{phase_8_directives}

# Strict phrasing rule (default ON for the summary — opt-out only if the goal text contains "direct summary" or "no phrasing constraints")

This rule applies ONLY to the Summarizer output (the markdown you write) and the P10 main-agent final user message. It does NOT apply to the workload code, tests, or Runner logs — those are direct by design.

When ON (the default):
- Never use verdict-form language naming the answer in the summary markdown.
- Forbidden patterns: "is the answer", "is the suspect", "is the [feature/cause]", "the answer is", "we have found", "confirms X is", "the feature is found to be".
- Allowed: reporting data ("X has metric Y=Z; this is consistent with..."). The user concludes from the table and the per-method observations.
- This is the puzzle/contest default — the user wants to drive the analytical conclusion themselves.

When OFF (opt-out):
- Write findings-first. State the verdict where the evidence supports one. Hedge only when the data hedges.

# Structure (suggested; adapt per task)

## 1. TL;DR
One paragraph. What was asked, what was run, the headline pattern (without verdict). Tie to prior phases.

## 2. Inputs and outputs
Tables of inputs (read-only) and outputs (with sizes).

## 3. Results per [feature/condition/method]
Full comparison table. Bullet observations.

## 4. Cross-method observations (the novel signature)
The most distinctive ordering / pattern. This is where the writeup earns its credibility.

## 5. Skeptic checks
Per-method ruling-out of alternative explanations.

## 6. Chain back to prior phases
Tabular linking of each prior-phase control to a current-phase result.

## 7. Hygiene
Determinism, convergence, solver paths, computed feature counts.

## 8. Caveats
Statistical precision, scope limits, known untested alternatives.

## 9. Next step
What follows from this work; which directory the next phase's outputs go to.

# Self-verification gate (BEFORE declaring done)

By default — run this grep on your summary:
```
grep -iE "is the answer|is the suspect|the answer is|we have found|confirms .* is|the feature is found to be" {summary_md_path}
```
Output MUST be empty (or contain only borderline matches that are clearly data-interpretation, not verdicts — flag these in your final report). If anything strongly matches, rewrite the line.

Skip this grep only if the goal text explicitly contains "direct summary" or "no phrasing constraints" — then verdict-form language in the summary is expected and the grep is irrelevant.

```
wc -l {summary_md_path}
```
Target: 200–400 lines. Under 150 → underdocumenting. Over 500 → padding.

# What you must NOT do
- Modify any code, test, CSV, or plot.
- Propose what the answer "is" in verdict form.
- Speculate beyond what the artifacts show.
- Add a recommendation that names a specific answer.

# Reporting back
- Path of the file you wrote.
- Line count.
- Grep result (empty or flagged borderline matches with justification).
- One-line: "Strict phrasing audit clean; {summary_md_path} ready for user review."

Begin.
```

**Output:** summary markdown file + Summarizer's report. Update state JSON.

---

## Phase 10 — Main agent final pass (gate-check + final message)

After Summarizer completes, P10 is a HARD GATE that walks every gate flag in state JSON and refuses to declare done if any are false.

### Step 10.1 — Gate-check (BLOCKING)

Read `./tmp/research_executor_state.json` and assert each of the following is `true`:

- `field_advisor_cache_gate_passed` (from P2 — see Phase 2 step 4)
- `contract_check_passed` (from P4c — workload symbols and test imports agree)
- `contract_roundtrip_passed` (from P4d — semantic round-trip, no unresolved diffs)
- `p3_abort_gate_decision` ∈ {`no_blocks`, `proceed_despite_block_traps`, `amended_and_rerun`} — anything else means P3 aborted and P10 should not have been reached
- `p6_blocking_issues_surfaced == false`, OR if true, the user explicitly chose to proceed (recorded under `p10_gate_check_overrides`)
- `p8_disagreement_resolutions` — every entry has a non-null resolution; no pending disagreements
- Runner exited cleanly (no exhausted retries — check `runner_retries_used < runner_max_retries`)
- Verifier exited 0 (check `verifier_exit_code == 0`)
- Reproducibility manifest files exist in every output dir: `env.txt`, `git_rev.txt`, `inputs.sha256`, `outputs.sha256` (cross-cutting rule #12)
- Unless the goal opted out via "direct summary" or "no phrasing constraints": Summarizer self-grep returned empty AND main-agent re-grep returns empty.

If ANY assertion fails: emit a structured failure report listing which gate(s) failed, do NOT send the celebratory "done" message, and ask the user whether to re-run the failing phase or accept the deviation explicitly. Record the user's decision in state JSON under `p10_gate_check_overrides` (a list of {gate_name, user_response_utc, justification}).

### Step 10.2 — Audits that don't gate but inform the final message

1. **Artifact listing** with sizes — `ls -la` on every output dir + plot dir.
2. **Test totals** across Author + Verifier suites (numbers from `tmp/run_log_step*.txt` and `tmp/run_log_verifier.txt`).
3. **Cross-reference** the Summarizer's report against the Phase 8 directives — did it hit every required observation?
4. **Independent re-grep** of the summary markdown for forbidden phrasing patterns (default; skipped only if the goal opted out via "direct summary" or "no phrasing constraints").
5. **Phase-timing audit** — read `phase_timings_seconds` from state JSON; flag any phase > 2× the median historical time for that phase (if prior runs exist; otherwise no flag).

### Step 10.3 — Final user message

Structure:
- **TL;DR** — one paragraph: what was produced, headline finding. By default this is non-verdict-framed (matches the Summarizer's strict-phrasing). If the goal opted out, the TL;DR may state the verdict directly.
- **Gate-check summary** — every gate from step 10.1 with its value. Use ✅/❌ for at-a-glance reading.
- **Phase timings table** — `P1: 30s | P2: 600s | P4: 280s | …` so the user sees where compute went.
- **Artifacts** — paths + sizes.
- **Reproducibility manifest pointers** — paths to env.txt / git_rev.txt / inputs.sha256 / outputs.sha256.
- **Flagged items** — any borderline phrasing (if applicable), any gate override the user accepted, any phase that ran >2× median.
- **Next step** — per the goal's "next step" section.

Mark P10 completed in state JSON only after the gate-check passed (or the user explicitly accepted overrides).

---

## Cross-cutting rules (apply throughout)

1. **Path discipline.** All workload outputs under user-specified result/plot directories. Skill's intermediate scratch in `./tmp/`. Never `/tmp/`.

2. **Strict phrasing — scope and default.**
   - **Scope: SUMMARIZER OUTPUT ONLY** (the P9 markdown + the P10 final user message). Author-Code, Author-Tests, Runner, and Verifier are exempt — workload code, tests, prints, run logs, and CSVs use direct, natural language. Verbatim feature names and findings are fine inside the pipeline.
   - **Default: ON** (this matches the dominant puzzle/contest use case where the user wants to drive the conclusion themselves). Forbidden patterns in the summary: "is the answer", "the answer is X", "X is the [feature/cause]", "we have found", "confirms X is", "the feature is found to be".
   - **Opt-out:** goal text contains "direct summary" or "no phrasing constraints". Then the Summarizer states findings directly ("country is the non-linear feature").
   - **Verification:** Summarizer self-grep at end of P9 + main-agent re-grep at P10 step 10.2. Both run by default; both skip on opt-out.

3. **Read-only fences.** Every subagent prompt enumerates which directories are read-only.

4. **Determinism stack (default ON).** Full seeding (torch + numpy + python random), deterministic algorithms flag, single-worker DataLoader, explicit random_state.

5. **Closed-form arithmetic checks.** Tests assert derived columns match their formulas within 1e-9.

6. **Incremental writes.** Each output written before next subsection runs.

7. **Two advisor() + two Field Advisor calls.** Pre and post each. The pre-flight ones catch design traps; the post ones catch artifact issues.

8. **Test files as contracts.** Author tests + Verifier tests together form the spec contract. Any later phase can re-verify by running the suite.

9. **Subagent isolation.**
   - Field Advisor (Opus 4.7) — full tools, full context, expert persona.
   - P4 prep callers — distiller (Opus) and API contract author (Opus), small focused outputs.
   - Author-Code / Author-Tests (Sonnet 4.6, parallel) — code-only and tests-only, no execution; both read the API contract.
   - Runner (Sonnet 4.6) — execution + bounded fixes, no scope creep, writes reproducibility manifest.
   - Verifier (Sonnet 4.6) — spec + final code only, no implementer reasoning.
   - Summarizer (Opus 4.7) — artifacts + Phase 8 directives only, no execution. Summary writing benefits from Opus's structuring; the wall-clock cost is small.

10. **Resumability.** State JSON updated at end of every phase. Re-invoking the skill with same goal hash resumes from `last_completed_phase + 1`.

11. **Phase timing instrumentation (REQUIRED).** Every phase records its `start_utc` and `end_utc` to `./tmp/research_executor_state.json` under `phase_timings_seconds.{phase_id}`. This is not optional — users have no other way to spot pathological slowdowns. Format: ISO 8601 timestamps for the boundaries, integer seconds for the diff. Main agent wraps each subagent spawn (and each main-agent phase like P1/P10) with timestamps.

12. **Reproducibility manifest (REQUIRED in P5).** Runner writes `env.txt` (pip freeze), `git_rev.txt` (git rev-parse HEAD), `inputs.sha256` (hashes of read-only inputs the workload consumed), and `outputs.sha256` (hashes of every produced CSV/JSON/PNG) into every output directory the workload writes to. Cost: ~2 seconds, near-zero token. Payoff: re-running a phase weeks later, you can prove whether numerical drift is real or a silently-upgraded dep.

13. **Model-version vigilance (REQUIRED at skill start).** See the "Pre-flight model vigilance" section. The skill hardcodes specific model IDs; at every invocation the orchestrator compares them against currently-available Claude models and surfaces a non-blocking upgrade prompt to the user if a meaningfully newer model is available for any high-reasoning phase (Field Advisor, P4 prep, P4d reconstructor, Summarizer). The user picks NO_SWAP / SWAP_ALL / SWAP_OPUS_ONLY / SWAP_CUSTOM. Decision is recorded in state JSON under `model_overrides`.

14. **Field-knowledge cache staleness (WARN, not block).** On every cache hit, the orchestrator computes `age_days` from the index's `created_utc`. If > 30 days, surface a non-blocking warning to the user with three options (use anyway / regenerate / delta-sweep). Default on timeout is "use anyway, log staleness." 30-day cadence is tuned for fast-moving fields (mech-interp, AI safety); slow-moving fields can be manually extended.

15. **P6 mechanical data-quality scan (REQUIRED before P6 advisor call).** Main agent runs five checks via Bash (NaN/Inf in CSVs, plot files < 5 KB, single-class predictions, suspiciously round numbers, row-count sanity), writes results to `./tmp/data_quality_scan.md`, and includes the findings in advisor()'s context. Unresolved flags are logged for the Summarizer's caveats section.

16. **P8 reconcile (BLOCKING on active disagreements).** After Field Advisor (post) and advisor() both return, the main agent diffs their conclusions and surfaces any active disagreements to the user before P9 begins. Silent merging is forbidden. Resolution recorded in state JSON.

17. **Contract round-trip (REQUIRED at P4d).** After Author-Tests writes its file, a small Opus call reads ONLY the test file and reconstructs what it thinks the contract is. The orchestrator diffs against the real `api_contract.md`. Semantic drift (unordered-vs-ordered columns, missing/extra outputs) triggers a re-spawn of whichever author diverged. The real contract is the tie-breaker.

---

## When to deviate from the full 10-phase flow

- **Single-file pure-function task.** Collapse Author + Runner into one subagent; skip Verifier. The full flow earns its overhead on ≥ 200-line workloads with ≥ 5 output artifacts.
- **Exploratory / open-ended task.** Skip Phase 4–7 entirely; just do Phase 1 (intake) + Phase 2 (Field Advisor) and report back.
- **Pure read-only analysis.** No Runner needed; advisor() does the work.
- **User explicitly disables a phase** ("skip the Field Advisor for this one"). Honor it; record the deviation in state JSON.

The 10-phase pattern is for tasks that produce shippable artifacts under hard constraints (correctness, reproducibility, field quality). For everything else, lighter is better.

---

## Quick reference: what each phase produces

| Phase | Produces |
|---|---|
| P1 Codebase intake | `./tmp/codebase_digest.md` |
| P2 Field Advisor (pre) | `./tmp/field_advisor_pre.md` (always) + `./.research_executor/field_knowledge_<slug>.md` (cold runs only — persistent project-level cache) |
| P3 advisor() pre-flight | classified trap list (block/warn) + abort-gate decision in state JSON; halts skill if user aborts or remains paused until user replies on block traps |
| P4 Author phase | `./tmp/field_advisor_pre_distilled.md` (≤ 6 KB) + `./tmp/api_contract.md` (one-row-per-signature format) + workload `.py` + author test file + `./tmp/api_contract_reconstructed.md` + `./tmp/api_contract_diff.txt` (round-trip check) |
| P5 Runner | result artifacts (CSVs/JSONs/plots) + run_log.txt |
| P6 advisor() mid-flight | `./tmp/data_quality_scan.md` (mechanical scan) + advisor observations folded into Summarizer directives |
| P7 Verifier | verifier test file + run_log_verifier.txt |
| P8 Field Advisor (post) + advisor() + reconcile | `./tmp/field_advisor_post.md` + `./tmp/p8_reconcile.md` + unified Summarizer directives; blocks on active disagreements |
| P9 Summarizer | SUMMARY.md (200–400 lines) |
| P10 Main final pass | user message with headline + flagged issues |

## State file schema

`./tmp/research_executor_state.json`:

```json
{
  "skill_version": "1.0",
  "goal_hash": "<sha256 hex>",
  "goal_text_first_200_chars": "...",
  "field_detected": "mechanistic interpretability",
  "field_exemplars": ["Neel Nanda", "Chris Olah", ...],
  "last_completed_phase": "P9",
  "phase_timings_seconds": {"P1": 30, "P2": 600, ...},
  "field_advisor_cache": {
    "path": "./.research_executor/field_knowledge_<slug>.md",
    "mode": "cold|warm",
    "created_utc": "<ISO timestamp from index>"
  },
  "p3_advisor_traps": [{"text": "…", "severity": "block|warn"}],
  "p3_block_severity_count": 0,
  "p3_abort_gate_decision": "no_blocks | proceed_despite_block_traps | amended_and_rerun | aborted",
  "p3_abort_gate_user_response_utc": "<ISO timestamp or null>",
  "summary_strict_phrasing_enabled": true,  // default true; set false only if goal text contained "direct summary" or "no phrasing constraints"
  "runner_retries_used": 0,
  "runner_max_retries": 3,
  "verifier_exit_code": 0,
  "reproducibility_manifest": {
    "env_txt": "results/<phase>/env.txt",
    "git_rev_txt": "results/<phase>/git_rev.txt",
    "git_status_txt": "results/<phase>/git_status.txt",
    "inputs_sha256": "results/<phase>/inputs.sha256",
    "outputs_sha256": "results/<phase>/outputs.sha256",
    "all_present": true
  },
  "p10_gate_check_passed": true,
  "p10_gate_check_overrides": [],
  "contract_roundtrip_diff_lines": 0,
  "contract_roundtrip_passed": true,
  "contract_roundtrip_attempts": 1,
  "p6_unresolved_dq_flags": [],
  "p6_blocking_issues_surfaced": false,
  "p8_disagreement_resolutions": [],
  "field_advisor_cache_age_days": 0,
  "field_advisor_cache_staleness_warning_issued": false,
  "field_advisor_cache_staleness_user_choice": "use_anyway | regenerate | delta_sweep | timeout",
  "model_vigilance_decision": "no_swap | swap_all | swap_opus_only | swap_custom | skipped_per_goal",
  "model_overrides": {
    "field_advisor": "claude-opus-4-7",
    "p4_prep_distiller": "claude-opus-4-7",
    "p4_prep_contract": "claude-opus-4-7",
    "author_code": "claude-sonnet-4-6",
    "author_tests": "claude-sonnet-4-6",
    "runner": "claude-sonnet-4-6",
    "verifier": "claude-sonnet-4-6",
    "p4d_reconstructor": "claude-opus-4-7",
    "summarizer": "claude-opus-4-7"
  },
  "artifacts": {
    "codebase_digest": "./tmp/codebase_digest.md",
    "field_advisor_pre": "./tmp/field_advisor_pre.md",
    "field_advisor_pre_distilled": "./tmp/field_advisor_pre_distilled.md",
    "field_advisor_post": "./tmp/field_advisor_post.md",
    "field_knowledge_cache": "./.research_executor/field_knowledge_<slug>.md",
    "field_advisor_index": "./.research_executor/field_advisor_index.json",
    "api_contract": "./tmp/api_contract.md",
    "contract_check_passed": true,
    "workload_files": ["..."],
    "test_files": ["..."],
    "result_dirs": ["..."],
    "plot_dirs": ["..."],
    "summary_md": "..."
  },
  "phase_8_directives": [...],
  "deviations": []
}
```

---

## Final note for invocation

When the user invokes `/research-executor` followed by a goal brief:

1. Confirm the goal is parseable (paths, deliverables, output dirs identifiable).
2. Hash the goal text. Check `./tmp/research_executor_state.json`. If hash matches and phase < P10, ask: "Resume from {last_completed_phase + 1} or restart fresh?"
3. Create the TodoList with 10 phase entries.
4. Walk P1 → P10. Update state JSON after each phase.
5. Final message: artifacts + next step.
