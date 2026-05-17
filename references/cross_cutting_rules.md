# Cross-cutting rules (apply throughout all phases)

These rules are enforced across every phase of `/research-executor`. SKILL.md carries a one-line summary of each; this file is the canonical full statement.

---

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

12. **Reproducibility manifest (REQUIRED in P5).** Runner writes `env.txt` (pip freeze), `git_rev.txt` (git rev-parse HEAD), `inputs.sha256` (hashes of read-only inputs the workload consumed), and `outputs.sha256` (hashes of every produced CSV/JSON/PNG) into every output directory the workload writes to. Cost: ~2 seconds, near-zero token. Payoff: re-running a phase weeks later, you can prove whether numerical drift is real or a silently-upgraded dep. Companion script: `scripts/reproducibility_manifest.sh`.

13. **Model-version vigilance (REQUIRED at skill start).** See `references/model_vigilance_procedure.md`. The skill hardcodes specific model IDs; at every invocation the orchestrator compares them against currently-available Claude models and surfaces a non-blocking upgrade prompt to the user if a meaningfully newer model is available for any high-reasoning phase (Field Advisor, P4 prep, P4d reconstructor, Summarizer). The user picks NO_SWAP / SWAP_ALL / SWAP_OPUS_ONLY / SWAP_CUSTOM. Decision is recorded in state JSON under `model_overrides`.

14. **Field-knowledge cache staleness (WARN, not block).** On every cache hit, the orchestrator computes `age_days` from the index's `created_utc`. If > 30 days, surface a non-blocking warning to the user with three options (use anyway / regenerate / delta-sweep). Default on timeout is "use anyway, log staleness." 30-day cadence is tuned for fast-moving fields (mech-interp, AI safety); slow-moving fields can be manually extended. Companion script: `scripts/cache_staleness_check.sh`. Full procedure: `references/cache_layout_and_staleness.md`.

15. **P6 mechanical data-quality scan (REQUIRED before P6 advisor call).** Main agent runs five checks via Bash (NaN/Inf in CSVs, plot files < 5 KB, single-class predictions, suspiciously round numbers, row-count sanity), writes results to `./tmp/data_quality_scan.md`, and includes the findings in advisor()'s context. Unresolved flags are logged for the Summarizer's caveats section. Companion script: `scripts/data_quality_scan.sh`.

16. **P8 reconcile (BLOCKING on active disagreements).** After Field Advisor (post) and advisor() both return, the main agent diffs their conclusions and surfaces any active disagreements to the user before P9 begins. Silent merging is forbidden. Resolution recorded in state JSON.

17. **Contract round-trip (REQUIRED at P4d).** After Author-Tests writes its file, a small Opus call reads ONLY the test file and reconstructs what it thinks the contract is. The orchestrator diffs against the real `api_contract.md`. Semantic drift (unordered-vs-ordered columns, missing/extra outputs) triggers a re-spawn of whichever author diverged. The real contract is the tie-breaker. Companion prompt: `references/prompts/contract_reconstructor.md`.
