# Field Advisor cache — layout, branching gate, staleness

This file is the canonical full statement for the persistent field-knowledge cache used by P2 (Field Advisor pre). SKILL.md carries only a one-paragraph summary and points here.

---

## Why the cache exists

The Field Advisor takes 5–30 min on a cold run because the web/citation sweep dominates. On warm runs (cache hit), the cached knowledge is reused and only the goal-level delta is produced — typically under 2 min.

## Cache layout

- **Project-scoped cache directory:** `./.research_executor/` (create with `mkdir -p` if absent — this is a stable project-level folder, NOT `./tmp/`).
- **Field-knowledge file:** `./.research_executor/field_knowledge_{field_slug}.md` where `field_slug` is kebab-case of `field_detected` (e.g. `mechanistic-interpretability`, `bayesian-statistics`, `reinforcement-learning`).
- **Cache index:** `./.research_executor/field_advisor_index.json` — maps `field_slug → {created_utc, exemplars, paper_count, file_size}`. The `created_utc` field powers the staleness check.
- **Goal-level review (always fresh):** `./tmp/field_advisor_pre.md` — unchanged path. Always references the cache file by relative path.
- **To force regeneration:** the user deletes `./.research_executor/field_knowledge_<slug>.md`. The skill never overwrites an existing cache file automatically; on cache-miss it creates, on cache-hit it reads.

## Cache staleness (WARN, not block) — cross-cutting rule #14

On every cache hit, the orchestrator checks the age of the cache file:

```bash
scripts/cache_staleness_check.sh --cache-file ./.research_executor/field_knowledge_<slug>.md --threshold-days 30
```

The script prints `age_days=<N>` and `created_utc=<ISO>`, exits 0 if age ≤ 30 days (silent, proceed warm), exits 1 if age > 30 days (orchestrator surfaces warning), exits 2 if the cache file is missing (cold path, no warning needed).

On exit 1 — emit a non-blocking warning to the user:

```
⚠ Field-knowledge cache for "{field_detected}" is {age_days} days old (created {created_utc}). Field knowledge may have shifted — new papers, retractions, new state-of-the-art methods. Options:
  1. Use the cache anyway (default — fast).
  2. Regenerate by deleting ./.research_executor/field_knowledge_<slug>.md and re-running. The next P2 will produce a fresh cache (5–30 min cold sweep).
  3. Keep cache but ask the Field Advisor to perform a "delta sweep" — read the existing cache and only WebSearch for what's changed since `created_utc`. Records updates as an addendum.
```

Wait briefly for user input; if no reply, proceed with option 1 (use cache) and log staleness to state JSON: `field_advisor_cache_age_days`, `field_advisor_cache_staleness_warning_issued` (bool), `field_advisor_cache_staleness_user_choice` (1|2|3|"timeout").

**Why 30 days, not 90:** mech-interp / AI-safety publishes weekly; a quarter-old "canonical pitfalls list" misses recent work like the latest steering / manifold methods. 30 is the right cadence for a fast-moving field. For slow-moving fields (Bayesian methods, classical ML), the user can manually extend the threshold by editing `--threshold-days` in their copy of the skill.

---

## Branching gate (MANDATORY — all four steps must execute, in order)

A skipped cache write is a **P2 phase failure**, not a soft warning. Phase 3 may not begin until the post-spawn gate (step 4) passes. The persistent cache lives outside `./tmp/`, and no other phase touches it — if P2 doesn't write it, nothing does.

### Step 1 — Pre-spawn directory creation (unconditional)

Before any check, every invocation, run via Bash:

```bash
mkdir -p ./.research_executor
```

Do NOT skip this on the assumption the directory exists. `mkdir -p` is idempotent and cheap. Skipping it is the single most common cause of cold-mode failure.

### Step 2 — Cache existence check via real Bash filesystem test (not pseudocode, not memory)

```bash
field_slug=<slugify(field_detected)>   # e.g. mechanistic-interpretability
cache_path="./.research_executor/field_knowledge_${field_slug}.md"
if test -s "$cache_path"; then mode="warm"; else mode="cold"; fi
```

`test -s` (not `test -f`) — the file must exist **and** be non-empty. An empty file from an aborted prior run must be treated as cache-miss. Do NOT infer mode from prior conversation state, prior phase outputs, or recollection — only from the filesystem at this instant.

### Step 3 — Spawn ONE Agent with the matching mode-specific prompt

- Cold mode prompt: `references/prompts/field_advisor_cold.md`
- Warm mode prompt: `references/prompts/field_advisor_warm.md`
- Both spawn via `Agent` tool with `subagent_type: general-purpose`, `model: opus` (resolved via `state.model_overrides.field_advisor`), all tools available.

### Step 4 — Post-spawn verification gate (BLOCKING)

After the subagent returns, verify via Bash:

- **Cold mode:** all three of `./.research_executor/field_knowledge_${field_slug}.md`, `./.research_executor/field_advisor_index.json`, and `./tmp/field_advisor_pre.md` must exist and be non-empty (`test -s`).
- **Warm mode:** `./tmp/field_advisor_pre.md` must exist and be non-empty.

If the gate fails: **DO NOT proceed to Phase 3.** Re-spawn the Field Advisor with an explicit "you did not produce file X — produce it now, the existing artifacts are present at Y/Z" prompt. Repeat until the gate passes. Record `field_advisor_cache_gate_passed: true` and `field_advisor_cache_gate_attempts: <int>` in state JSON. If three re-spawn attempts all fail, halt the skill and surface to the user — do not silently advance.

---

## Placeholder fillers (referenced by the cold/warm prompts)

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

## Outputs (verified by the post-spawn gate in step 4)

- **Cold run (MANDATORY all three):** `./.research_executor/field_knowledge_{field_slug}.md` (new), `./.research_executor/field_advisor_index.json` (created or merged), `./tmp/field_advisor_pre.md` (new). If any is missing or zero-byte after the Field Advisor returns, the gate re-spawns the subagent until all three exist on disk. Three failed re-spawn attempts halt the skill.
- **Warm run (MANDATORY):** `./tmp/field_advisor_pre.md`.
- **State JSON** gets `field_advisor_cache_path`, `field_advisor_cache_mode` ("cold"/"warm"), `field_advisor_cache_gate_passed` (bool), `field_advisor_cache_gate_attempts` (int), and `field_advisor_pre_notes`.
