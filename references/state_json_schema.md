# State JSON schema

Path: `./tmp/research_executor_state.json` — written/updated at the end of every phase. Used for resumability (re-invoking with the same `goal_hash` resumes from `last_completed_phase + 1`) and for the P10 gate-check (which walks every `*_passed` flag).

## Full schema with field-by-field comments

```json
{
  "skill_version": "1.0",
  "goal_hash": "<sha256 hex of the goal text>",
  "goal_text_first_200_chars": "...",
  "field_detected": "mechanistic interpretability",
  "field_exemplars": ["Neel Nanda", "Chris Olah", "..."],
  "last_completed_phase": "P9",
  "phase_timings_seconds": {"P1": 30, "P2": 600, "...": "..."},

  // P2 — Field Advisor cache
  "field_advisor_cache": {
    "path": "./.research_executor/field_knowledge_<slug>.md",
    "mode": "cold|warm",
    "created_utc": "<ISO timestamp from index>"
  },
  "field_advisor_cache_gate_passed": true,        // post-spawn verification gate
  "field_advisor_cache_gate_attempts": 1,
  "field_advisor_cache_age_days": 0,              // computed on every warm hit
  "field_advisor_cache_staleness_warning_issued": false,
  "field_advisor_cache_staleness_user_choice": "use_anyway | regenerate | delta_sweep | timeout",

  // P3 — advisor() pre-flight + abort gate
  "p3_advisor_traps": [{"text": "…", "severity": "block|warn"}],
  "p3_block_severity_count": 0,
  "p3_abort_gate_decision": "no_blocks | proceed_despite_block_traps | amended_and_rerun | aborted",
  "p3_abort_gate_user_response_utc": "<ISO timestamp or null>",

  // P4 — Author phase
  "contract_check_passed": true,                  // P4c syntactic AST check
  "contract_roundtrip_diff_lines": 0,             // P4d semantic round-trip
  "contract_roundtrip_passed": true,
  "contract_roundtrip_attempts": 1,

  // P5 — Runner
  "runner_retries_used": 0,
  "runner_max_retries": 3,
  "reproducibility_manifest": {
    "env_txt": "results/<phase>/env.txt",
    "git_rev_txt": "results/<phase>/git_rev.txt",
    "git_status_txt": "results/<phase>/git_status.txt",
    "inputs_sha256": "results/<phase>/inputs.sha256",
    "outputs_sha256": "results/<phase>/outputs.sha256",
    "all_present": true
  },

  // P6 — mid-flight advisor + DQ scan
  "p6_unresolved_dq_flags": [],
  "p6_blocking_issues_surfaced": false,

  // P7 — Verifier
  "verifier_exit_code": 0,

  // P8 — reconcile
  "p8_disagreement_resolutions": [],              // [{topic, resolution, user_response_utc}, ...]

  // P9 — Summarizer
  "summary_strict_phrasing_enabled": true,        // default true; false only on "direct summary" / "no phrasing constraints" opt-out

  // P10 — final gate-check
  "p10_gate_check_passed": true,
  "p10_gate_check_overrides": [],                 // [{gate_name, user_response_utc, justification}, ...]

  // Pre-flight model vigilance
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

  // Cumulative artifact paths
  "artifacts": {
    "codebase_digest": "./tmp/codebase_digest.md",
    "field_advisor_pre": "./tmp/field_advisor_pre.md",
    "field_advisor_pre_distilled": "./tmp/field_advisor_pre_distilled.md",
    "field_advisor_post": "./tmp/field_advisor_post.md",
    "field_knowledge_cache": "./.research_executor/field_knowledge_<slug>.md",
    "field_advisor_index": "./.research_executor/field_advisor_index.json",
    "api_contract": "./tmp/api_contract.md",
    "api_contract_reconstructed": "./tmp/api_contract_reconstructed.md",
    "api_contract_diff": "./tmp/api_contract_diff.txt",
    "workload_files": ["..."],
    "test_files": ["..."],
    "result_dirs": ["..."],
    "plot_dirs": ["..."],
    "summary_md": "..."
  },

  "phase_8_directives": [],
  "deviations": [],
  "assumptions_made_without_user_confirmation": []
}
```

## Notes

- All ISO timestamps are UTC (`Z` suffix), second precision.
- `phase_timings_seconds` is keyed by short phase ID (`P1` through `P10`) and stores integer seconds.
- `model_overrides` defaults to the hardcoded model IDs; the pre-flight model vigilance check may swap entries before P1 begins.
- Every `*_passed` boolean field is consumed by the P10 gate-check. A `false` value blocks final-message emission unless overridden in `p10_gate_check_overrides`.
