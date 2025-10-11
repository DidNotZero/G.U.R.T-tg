Phase 6 — NPC Utility (Neko)

This module introduces a utility-based goal selection layer for NPCs.
Files are included after Phase 4 Perception and Phase 5 FSM.

Key concepts
- Current goal: one of `safety`, `ack`, `patrol`, or `idle` (initial catalog)
- Emergency pre-emption: hazards immediately override routine/forced goals
- Policy gating: respects FSM `goal_mask` (e.g., `evac_only` suppresses commit)
- Commit window + hysteresis: reduce thrash under small signal changes

Runtime config (admin)
- `npc_utility_enabled` (bool)
- `npc_utility_tick_skip` (int≥0)
- `npc_utility_min_commit_s` (seconds≥0)
- `npc_utility_hysteresis` (0..1)
- `npc_utility_emerg_preempt` (bool)
- `npc_utility_weight_floor` (0..1)
- `npc_utility_debug` (bool)

Admin/TGUI
- Verb: "NPC Utility (TGUI)"; interface name `NpcUtility`
- Rows show: FSM state, current goal, age, Top‑3 candidates, perf (`utility_eval_ms`), counters (evals/switches/preempts), forced override warnings
- Actions: set config, Force Goal (override gating), Re‑evaluate (single/all)

Performance
- Per‑evaluation timing captured in `ai_utility_last_eval_ms` on each mob
- Counters maintained per NPC (`evals`, `switches`, `preempts`) for observational checks

See specs/005-neko-md/ for tasks, plan, and quickstart.
