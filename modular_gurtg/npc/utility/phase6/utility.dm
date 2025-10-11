// Phase 6 — NPC Utility (Neko)
// Module: Utility controller datum and mob/living procs/vars (scaffold)

// Routine goal catalog (base weights)
var/global/list/npc_utility_routine_catalog = list(
    // id = base_weight
    "idle" = 0.08,
    "patrol" = 0.10
)

// Per-mob utility controller
/datum/ai_utility
    var/mob/living/owner
    var/last_eval_ds = 0
    var/tick_offset = null
    var/list/counters = null // {evals, switches, preempts}
    var/started_ds = 0

    New(mob/living/M)
        owner = M
        counters = list("evals"=0, "switches"=0, "preempts"=0)
        started_ds = world.time
        ..()

    proc/Tick()
        if(!owner) return FALSE
        // Config gating
        if(!npc_utility_get("npc_utility_enabled")) return FALSE
        var/ds0 = world.timeofday
        var/skip = npc_utility_get("npc_utility_tick_skip")
        if(!isnum(skip)) skip = 1
        if(isnull(tick_offset))
            tick_offset = (skip > 0) ? rand(0, skip) : 0
        // Run every (skip + 1) ticks to match perception semantics
        var/period = max(1, skip + 1)
        if(((world.time + tick_offset) % period) != 0)
            return FALSE
        // Policy gating: respect evac-only by leaving goal unset (unless admin forced)
        var/allow_commit = TRUE
        var/policy_mask = ""
        if(owner.ai)
            var/list/pol = owner.ai.PolicyFor(owner.ai.state)
            if(islist(pol) && istext(pol["goal_mask"]))
                policy_mask = lowertext("[pol["goal_mask"]]")
                if(policy_mask == "evac_only")
                    allow_commit = FALSE
        // Evaluate hazards (US1) using Phase-5 helper; under evac_only use cached EHP to avoid heavy work
        var/hscore = 0.0
        if(policy_mask == "evac_only")
            hscore = istype(owner.ai, /datum/ai_fsm) ? (owner.ai.ehp_cache_value || 0) : 0
        else
            hscore = npc_fsm_effective_hazard_pressure(owner)
        // Selection logic (US1 minimal): choose emergency safety goal when hazard exceeds floor
        var/floor = npc_utility_get("npc_utility_weight_floor")
        if(!isnum(floor)) floor = 0.05
        var/hyst = npc_utility_get("npc_utility_hysteresis")
        if(!isnum(hyst)) hyst = 0.15
        var/min_commit_s = npc_utility_get("npc_utility_min_commit_s")
        if(!isnum(min_commit_s)) min_commit_s = 6
        var/now = world.time
        var/age_ds = now - (owner.ai_goal_age_ds || now)
        if(age_ds < 0) age_ds = 0
        var/age_s = round(age_ds / 10)
        var/may_switch = (age_s >= min_commit_s)
        var/emerg_preempt = npc_utility_get("npc_utility_emerg_preempt") ? TRUE : FALSE
        var/prev_goal = istext(owner.ai_current_goal) ? owner.ai_current_goal : null
        var/selected_goal = prev_goal
        var/selected_score = 0.0
        var/reason = "idle"
        // Emergency pre-emption (ignores commit window)
        if(emerg_preempt && isnum(hscore) && hscore >= floor)
            selected_goal = "safety"
            selected_score = hscore
            reason = "EHP>=floor"
            // Interrupt forced goal if active
            if(owner.ai_forced_active)
                owner.ai_forced_active = FALSE
                counters["preempts"] = max(0, (counters["preempts"]||0)) + 1
                npc_utility_log_admin("emergency pre-empt interrupted forced goal '[owner.ai_forced_goal]' on [owner]")
        else
            // No emergency: if forced goal active, respect it
            if(owner.ai_forced_active && istext(owner.ai_forced_goal))
                selected_goal = owner.ai_forced_goal
                reason = "forced"
            else
                // Calm selection: candidates are ack (speech) and routine (patrol)
                var/ack_score = ComputeAckScore()
                // Routine base from catalog (patrol as default routine)
                var/routine_score = isnum(npc_utility_routine_catalog["patrol"]) ? npc_utility_routine_catalog["patrol"] : 0.10
                // Gate by policy mask (base goals only unless alert allows emerg which we already handled)
                var/allow_base = TRUE
                if(owner.ai)
                    var/list/p2 = owner.ai.PolicyFor(owner.ai.state)
                    if(islist(p2) && istext(p2["goal_mask"]))
                        var/mask = lowertext("[p2["goal_mask"]]")
                        if(mask == "evac_only") allow_base = FALSE
                if(!allow_base)
                    // Policy forbids base goals; clear goal (handled by allow_commit later)
                    selected_goal = null
                    reason = "policy_gate"
                else
                    // Prefer ack when present; apply commit window for switching
                    if(isnum(ack_score) && ack_score >= floor)
                        if(prev_goal != "ack")
                            if(may_switch)
                                selected_goal = "ack"
                                selected_score = ack_score
                                reason = "speech"
                            else
                                selected_goal = prev_goal
                                reason = "commit_window"
                        else
                            selected_goal = prev_goal
                            selected_score = ack_score
                            reason = "ack_hold"
                    else
                        // Routine fallback
                        // If no routine beats the floor, choose idle fallback for stability
                        var/any_over_floor = (routine_score >= floor)
                        if(prev_goal == "ack")
                            // Short-lived ack: yield quickly when no longer present
                            var/ack_clear_s = min(2, max(0, min_commit_s))
                            if(age_s >= ack_clear_s)
                                any_over_floor = (routine_score >= floor)
                                if(!any_over_floor)
                                    var/idle_w = isnum(npc_utility_routine_catalog["idle"]) ? npc_utility_routine_catalog["idle"] : 0.08
                                    selected_goal = "idle"
                                    selected_score = idle_w
                                    reason = "ack_yield_idle"
                                else
                                    selected_goal = "patrol"
                                    selected_score = routine_score
                                    reason = "ack_yield_patrol"
                            else
                                // hold a bit more if under ack_clear_s
                                selected_goal = prev_goal
                                reason = "ack_grace"
                        else if(!any_over_floor)
                            var/idle_w = isnum(npc_utility_routine_catalog["idle"]) ? npc_utility_routine_catalog["idle"] : 0.08
                            if(prev_goal != "idle")
                                if(may_switch || isnull(prev_goal))
                                    selected_goal = "idle"
                                    selected_score = idle_w
                                    reason = "idle_fallback"
                                else
                                    selected_goal = prev_goal
                                    reason = "commit_window"
                            else
                                selected_goal = prev_goal
                                selected_score = idle_w
                                reason = "idle_hold"
                        else
                            if(prev_goal != "patrol")
                                if(may_switch || isnull(prev_goal))
                                    selected_goal = "patrol"
                                    selected_score = routine_score
                                    reason = isnull(prev_goal) ? "routine_init" : "routine_switch"
                                else
                                    selected_goal = prev_goal
                                    reason = "commit_window"
                            else
                                selected_goal = prev_goal
                                selected_score = routine_score
                                reason = "routine_hold"
        // Commit if allowed by policy (forced goal overrides gating)
        if(!allow_commit)
            if(!(owner.ai_forced_active && istext(owner.ai_forced_goal)))
                selected_goal = null
                reason = "evac_only"
        var/did_switch = ("[selected_goal]" != "[prev_goal]")
        if(did_switch)
            owner.ai_current_goal = selected_goal
            owner.ai_goal_age_ds = now
            counters["switches"] = max(0, (counters["switches"]||0)) + 1
        // Prepare top candidates list (placeholder): safety vs none
        var/list/top = list()
        // Candidate scores
        var/ack_score2 = ComputeAckScore()
        var/routine_score2 = isnum(npc_utility_routine_catalog["patrol"]) ? npc_utility_routine_catalog["patrol"] : 0.10
        top += list(list("id"="safety", "score"=hscore))
        top += list(list("id"="ack", "score"=ack_score2))
        top += list(list("id"="patrol", "score"=routine_score2))
        // Keep at most 3; already 3 items
        owner.ai_utility_top_candidates = top
        // Telemetry record
        owner.ai_utility_eval_record = list(
            "chosen" = selected_goal ? list("id"=selected_goal, "score"=selected_score) : null,
            "top" = top,
            "reason" = reason,
            "policy" = allow_commit ? (policy_mask||"normal") : "evac_only",
            "timestamp" = now
        )
        counters["evals"] = max(0, (counters["evals"]||0)) + 1
        last_eval_ds = now
        // Measure elapsed ms for observability
        var/ds1 = world.timeofday
        var/delta = ds1 - ds0
        if(delta < 0) delta += 864000 // midnight wrap
        if(owner)
            owner.ai_utility_last_eval_ms = delta * 100
        return TRUE

    // Compute acknowledgment score based on nearest speech proximity and age
    proc/ComputeAckScore()
        if(!owner) return 0.0
        if(!hascall(owner, "perception_nearest_speech")) return 0.0
        var/datum/perception_entry/E = owner.perception_nearest_speech()
        if(!E) return 0.0
        var/turf/goal = locate(E.x, E.y, E.z)
        if(!goal) return 0.0
        var/steps = perception_path_steps_to(owner, goal)
        if(steps < 0) return 0.0
        // Age decay: newer is stronger
        var/now = world.time
        var/age_ds = now - (E.last_seen || now)
        if(age_ds < 0) age_ds = 0
        var/age_s = age_ds / 10.0
        var/max_age_s = max(1, npc_perception_ttl_seconds)
        var/age_factor = max(0.0, 1.0 - min(1.0, age_s / max_age_s))
        // Distance factor: closer yields more
        var/dist_factor = 1.0 / (1.0 + steps)
        // Base weight for ack
        var/base = 0.30
        var/score = base * age_factor * dist_factor
        // Clamp
        if(score < 0) score = 0
        if(score > 1) score = 1
        // If previous goal is ack and speech disappeared, allow short-lived stickiness only
        return score

// Attach on mob
/mob/living
    var/datum/ai_utility/ai_utility = null
    var/ai_current_goal = null // string|null
    var/ai_goal_age_ds = 0
    var/ai_forced_goal = null // string|null
    var/ai_forced_active = FALSE
    // Ephemeral evaluation telemetry
    var/list/ai_utility_eval_record = null
    var/list/ai_utility_top_candidates = null // list of up to 3 {id, score}
    var/ai_utility_last_eval_ms = 0

/mob/living/proc/AI_UTILITY_Ensure()
    if(!ai_utility)
        ai_utility = new /datum/ai_utility(src)
    if(!islist(ai_utility_top_candidates)) ai_utility_top_candidates = list()
    return ai_utility

/mob/living/proc/AI_UTILITY_Tick()
    var/datum/ai_utility/U = AI_UTILITY_Ensure()
    if(U) U.Tick()
    return TRUE
