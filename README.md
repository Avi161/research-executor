# research-executor

A 10-phase orchestrated `/research-executor` skill for non-trivial research / implementation tasks that produce shippable artifacts (CSVs, JSONs, plots, summary markdown) under correctness, reproducibility, and field-quality constraints. The skill spends Opus + Sonnet across multiple subagents — Field Advisor, parallel Author-Code/Author-Tests, Runner, Verifier, Summarizer — and gates every transition on explicit verification rather than silent merging.

## Quick start

Install: drop this directory at `~/.claude/skills/research-executor/`. The skill registers as `/research-executor` via the `name:` field in `SKILL.md`'s frontmatter.

Invoke (after the in-context `/` prompt):

```
/research-executor

<your goal text — see examples/ for two concrete samples>
```

The skill runs only when explicitly invoked by name. It will not auto-activate on a pasted goal spec.

## What you get

1. Workload code + author test file (parallel Sonnet authors, contract-mediated agreement)
2. Verifier test file (independent assertions, spec-only context)
3. Result artifacts (CSVs / JSONs / NPY tensors — whatever the goal dictates)
4. Plots (every plottable view)
5. Summary markdown (Opus Summarizer, user-facing)
6. Reproducibility manifest (`env.txt`, `git_rev.txt`, `inputs.sha256`, `outputs.sha256`) in every output dir
7. Two Field Advisor reviews (pre + post) and two `advisor()` reviews (pre + mid)

## The 10 phases (one sentence each)

| Phase | What it does |
|---|---|
| **P1** | Codebase intake — read project markdowns + prior summaries, write `tmp/codebase_digest.md`, detect field. |
| **P2** | Field Advisor (pre) — Opus subagent with full WebSearch; cold mode writes the persistent field-knowledge cache, warm mode reuses it; staleness warning > 30 days; post-spawn gate verifies all expected files. |
| **P3** | `advisor()` pre-flight + abort gate — classify traps; if any block-severity, halt and ask the user before burning P4+ budget. |
| **P4** | Author phase — Opus distiller + API-contract author (prep); two parallel Sonnet authors (Author-Code, Author-Tests); contract drift check (AST); contract round-trip (Opus reconstructor diffs against the real contract). |
| **P5** | Runner — Sonnet, up to 3 retries, writes reproducibility manifest before + hashes outputs after. |
| **P6** | `advisor()` mid-flight — mechanical data-quality scan first (NaN/Inf, plot size, single-class, suspicious round numbers, row counts), then advisor sees the scan. |
| **P7** | Verifier — Sonnet, spec-only context, independent assertions. |
| **P8** | Field Advisor (post) + `advisor()` final, in parallel; reconcile pass blocks on active disagreements before P9. |
| **P9** | Summarizer — Opus, writes the user-facing markdown; strict-phrasing audit ON by default (opt-out via `"direct summary"` in goal text). |
| **P10** | Main agent final pass — walks every gate flag in state JSON; refuses to declare done if any failed; emits the final user message. |

## When to use vs alternatives

**Use `/research-executor` when:**
- Task is multi-stage (≥ 5 distinct steps or ≥ 3 output artifacts).
- Task produces code + data files, not just an answer.
- Correctness + reproducibility matter (publishable, contest, regulated).

**Don't use it when:**
- It's a single-file script or one-off Bash command (just write it).
- It's read-only exploratory analysis (use `advisor()` directly).
- It's a mid-iteration tweak (Edit + targeted tests beats the full pipeline).

## Project setup the skill expects

- A `./tmp/` directory at the project root (the skill creates it if absent — never uses `/tmp/`).
- A Python venv at `.venv/` if your workload runs Python (Runner uses `.venv/bin/python`).
- Project-relative output paths (`results/<phase>/`, `plots/<phase>/`, `notes/<phase>/`).
- A `CLAUDE.md` and/or `README.md` at project root so Phase 1 codebase intake has something to summarise.

## Layout

```
research-executor/
├── SKILL.md                       ← lean router (< 500 lines)
├── README.md                      ← this file
├── LICENSE                        ← MIT
├── scripts/                       ← Bash/Python helper scripts invoked by the orchestrator
├── references/                    ← long-form rules + every subagent prompt template
│   └── prompts/                   ← one .md per subagent prompt (loaded on demand)
└── examples/                      ← two concrete invocations (puzzle + general)
```

SKILL.md is the lean router. Each phase section is short and points to the relevant `references/prompts/<name>.md` for the full subagent prompt, or to `scripts/<file>` for the Bash/Python.

## Examples

- `examples/puzzle_geometry_invocation.md` — puzzle / contest task; strict-phrasing default ON; uses `i*` placeholder per "user drives the conclusion" mode.
- `examples/general_research_invocation.md` — general research task with `"direct summary"` opt-out; verdict-form language allowed.

## License

MIT. See `LICENSE`.

## Authoring notes

- The skill is **user-invoked only**. It must NOT auto-activate based on a pasted goal spec, METHODOLOGY section, or plan file in the conversation — the user controls the trigger because the orchestration burns Opus + WebSearch budget across multiple subagents.
- The skill is **resumable** via `tmp/research_executor_state.json` keyed on goal hash.
- The Summarizer's strict-phrasing rule scopes to the Summarizer output only — workload code, tests, prints, run logs, and CSVs are direct by design.
- Cross-cutting rules (17) are summarised in SKILL.md and stated in full in `references/cross_cutting_rules.md`.
