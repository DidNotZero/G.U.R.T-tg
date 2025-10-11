// Phase 5 — NPC FSM (Neko)
// Module: FSM datum and mob/living procs

// Valid states helper
/proc/npc_fsm_valid_state(s)
    if(!istext(s)) return FALSE
    var/t = lowertext("[s]")
    return (t == "normal" || t == "alert" || t == "critical")

// Per-mob controller
/datum/ai_fsm
    var/mob/living/owner
    var/state = "normal"
    var/last_eval_ds = 0
    var/cooldown_until_ds = 0
    var/list/policy = null
    var/list/counters = null
    var/list/last_reason = null  // {from,to,code,msg,time_ds}
    var/ehp_cache_value = 0.0
    var/ehp_cache_ds = 0
    var/ehp_next_eval_ds = 0

    New(mob/living/M)
        owner = M
        policy = list()
        counters = list()
        last_reason = list()
        ..()

    proc/Tick()
        // Evaluate global first to allow immediate Critical without local cost
        var/list/gstimuli = ComputeGlobalStimuli()
        if(IsCriticalWanted(gstimuli))
            if(state != "critical")
                Enter("critical", "GLOBAL_ALERT", "")
            last_eval_ds = world.time
            return
        // If already in Critical, do not compute local stimuli or de-escalate in Phase 5
        if(state == "critical")
            last_eval_ds = world.time
            return
        // Compute local stimuli with EHP caching
        var/list/local = ComputeLocalStimuli()
        MaybeTransition(local, gstimuli)
        last_eval_ds = world.time

    proc/IsCriticalWanted(list/gstimuli)
        if(!islist(gstimuli)) return FALSE
        var/glvl = lowertext("[gstimuli["alert_level"]]")
        var/evac = gstimuli["evac_flag"] ? TRUE : FALSE
        var/list/clvls = npc_fsm_get("npc_fsm_critical_levels")
        if(islist(clvls) && glvl && (glvl in clvls)) return TRUE
        if(evac) return TRUE
        return FALSE

    proc/MaybeTransition(list/local, list/gstimuli)
        if(!islist(local)) local = list("ehp"=0, "area_alarm_nearby"=FALSE)
        var/ehp = local["ehp"]
        var/alar = local["area_alarm_nearby"]
        var/threshold = npc_fsm_get("npc_fsm_hazard_pressure_threshold")
        if(!isnum(threshold)) threshold = 0.60
        var/clear_s = npc_fsm_get("npc_fsm_clear_seconds")
        if(!isnum(clear_s)) clear_s = 30
        var/now = world.time
        // Global stimuli (US2)
        var/crit_from_alert = FALSE
        if(islist(gstimuli))
            var/glvl = lowertext("[gstimuli["alert_level"]]")
            var/evac = gstimuli["evac_flag"] ? TRUE : FALSE
            var/list/clvls = npc_fsm_get("npc_fsm_critical_levels")
            if(islist(clvls) && glvl && (glvl in clvls))
                if(state != "critical")
                    Enter("critical", "GLOBAL_ALERT", "lvl=[glvl]")
                    return
            if(evac)
                crit_from_alert = TRUE
        if(crit_from_alert)
            Enter("critical", "EVAC", "")
            return
        if(state == "critical")
            // Do not auto de-escalate from Critical in Phase 5
            return
        if(state == "normal")
            if((isnum(ehp) && ehp >= threshold) || alar)
                cooldown_until_ds = now + (clear_s * 10)
                Enter("alert", "EHP_OR_ALARM", "ehp=[isnum(ehp)?round(ehp,0.01):0] alar=[alar]")
                return
        else if(state == "alert")
            var/clear_cond = (isnum(ehp) ? (ehp <= 0.01) : TRUE) && !alar
            if(clear_cond && now >= (cooldown_until_ds||0))
                Enter("normal", "CLEAR", "cooldown=[clear_s]s")
                return
        // US2 (Critical) handled later
        return

    proc/Enter(new_state, code="INIT", msg="")
        if(!npc_fsm_valid_state(new_state)) return FALSE
        if(owner)
            var/old = state
            state = lowertext("[new_state]")
            last_reason = list("from"=old, "to"=state, "code"=code, "msg"=msg, "time_ds"=world.time)
            npc_fsm_log_admin("[owner] [old]->[state] code=[code] [msg]")
            // Stamp on owner and update stats
            if(!islist(owner.ai_state_stats))
                owner.ai_state_stats = list("normal_ms"=0, "alert_ms"=0, "critical_ms"=0, "transitions"=0)
            var/prev_enter = owner.ai_state_entered_ds || world.time
            var/delta = world.time - prev_enter
            if(delta < 0) delta = 0
            var/k = "[owner.ai_state]_ms"
            if(istext(owner.ai_state) && (k in owner.ai_state_stats))
                owner.ai_state_stats[k] = max(0, (owner.ai_state_stats[k]||0)) + (delta * 100)
            owner.ai_state = state
            owner.ai_state_entered_ds = world.time
            owner.ai_state_stats["transitions"] = max(0, (owner.ai_state_stats["transitions"]||0)) + 1
            owner.ai_state_reason = last_reason.Copy()
            // Apply policy-derived preferences to mob (store-only for future phases)
            var/list/p = PolicyFor(state)
            if(islist(p))
                owner.ai_nav_avoid_harm = !!(p["nav_avoid_harm"])
                owner.ai_nav_door_penalty_factor = isnum(p["nav_door_penalty_factor"]) ? p["nav_door_penalty_factor"] : owner.ai_nav_door_penalty_factor
                owner.ai_nav_goal_mask = istext(p["goal_mask"]) ? p["goal_mask"] : owner.ai_nav_goal_mask
                owner.ai_nav_allow_offduty = !!(p["allow_offduty"])
        return TRUE

    proc/Exit()
        return TRUE

    proc/PolicyFor(st)
        var/t = istext(st) ? lowertext("[st]") : state
        // Defaults per data-model; nav_* stored only for future phases
        if(t == "critical")
            return list(
                "perception_tick_skip"=(isnum(npc_fsm_get("npc_fsm_critical_tick_skip")) ? npc_fsm_get("npc_fsm_critical_tick_skip") : 0),
                "speech_hearing_radius"=4,
                "nav_avoid_harm"=FALSE,
                "nav_door_penalty_factor"=1.0,
                "goal_mask"="evac_only",
                "allow_offduty"=FALSE
            )
        if(t == "alert")
            return list(
                "perception_tick_skip"=1,
                "speech_hearing_radius"=2,
                "nav_avoid_harm"=TRUE,
                "nav_door_penalty_factor"=1.5,
                "goal_mask"="base∪emerg",
                "allow_offduty"=FALSE
            )
        // normal
        return list(
            "perception_tick_skip"=2,
            "speech_hearing_radius"=0,
            "nav_avoid_harm"=TRUE,
            "nav_door_penalty_factor"=2.0,
            "goal_mask"="base",
            "allow_offduty"=TRUE
        )

    proc/ComputeLocalStimuli()
        // Prefer cheap checks (alarm) and EHP caching to reduce path queries
        var/ehp = ehp_cache_value
        var/alar = FALSE
        if(owner)
            var/turf/T = get_turf(owner)
            if(T)
                var/area/A = get_area(T)
                if(A && A.fire) alar = TRUE
            // Skip EHP recompute if an alarm is nearby (alarm alone triggers Alert)
            if(!alar)
                var/ttl_s = npc_fsm_get("npc_fsm_ehp_cache_seconds")
                if(!isnum(ttl_s)) ttl_s = 1
                var/ttl_ds = max(1, round(ttl_s)) * 10
                var/now = world.time
                if(ehp_next_eval_ds <= 0)
                    // Initialize with jitter to avoid herd effects
                    ehp_next_eval_ds = now + rand(0, ttl_ds)
                if(now >= ehp_next_eval_ds)
                    ehp = UpdateEhpCache()
                    // Schedule next with jitter window
                    ehp_next_eval_ds = now + ttl_ds + rand(0, ttl_ds)
        return list("ehp"=ehp, "area_alarm_nearby"=alar)

    proc/UpdateEhpCache()
        if(!owner) return 0.0
        var/v = npc_fsm_effective_hazard_pressure(owner)
        ehp_cache_value = v
        ehp_cache_ds = world.time
        return v

    proc/ComputeGlobalStimuli()
        // Read global helpers
        return list("alert_level"=npc_fsm_alert_level, "evac_flag"=npc_fsm_evac_enabled)

// -----------------------------------------
// Exposure and hazard helpers (US1)
// -----------------------------------------

// Whether movement between adjacent turfs is permeable for atmos exposure purposes
/proc/atmos_edge_permeable(turf/A, turf/B)
    if(!A || !B) return FALSE
    var/datum/can_pass_info/pass_info = new(null, null)
    return !A.LinkBlockedWithAccess(B, pass_info) && !dslite_link_blocked_by_plasticflaps(A, B, null)

// Return steps between start and goal using path facade; fallback to inf if blocked
/proc/exposure_steps_same_region(mob/M, turf/start, turf/goal)
    if(!M || !start || !goal) return -1
    if(start.z != goal.z) return DSLITE_INF
    if(!dslite_is_passable(start, M) || !dslite_is_passable(goal, M)) return DSLITE_INF
    var/list/opts = list("async"=FALSE, "max_sync_pops"=100)
    var/list/res = dslite_request_path(M, start, goal, opts)
    if(!islist(res)) return -1
    if(res["unreachable"]) return DSLITE_INF
    if(res["queued"]) return -1
    var/list/wps = res["waypoints"]
    if(!islist(wps)) return -1
    return max(0, length(wps)-1)

// Heuristic: consider an area exposed if any turf borders space by a permeable edge
/proc/area_currently_exposed(area/A)
    if(!A) return FALSE
    for(var/zkey in A.turfs_by_zlevel)
        var/list/turfs = A.turfs_by_zlevel[zkey]
        if(!islist(turfs)) continue
        var/ct = 0
        for(var/turf/T as anything in turfs)
            // Check 4-neighborhood for space with permeable edge
            for(var/dir in list(NORTH, SOUTH, EAST, WEST))
                var/turf/N = get_step(T, dir)
                if(!N) continue
                if(istype(N, /turf/open/space) && atmos_edge_permeable(T, N))
                    return TRUE
            ct++
            if(ct >= 100) break // bound work on large areas
    return FALSE

// Would the tile harm this mob now? (gear gating placeholder)
/proc/would_harm_now(mob/living/M, turf/T)
    if(!M || !T) return TRUE
    // Low-pressure gating: if tile is vacuum/very low pressure, allow protective gear/internals to suppress harm
    var/datum/gas_mixture/env = T.return_air()
    var/pressure_low = FALSE
    if(isnull(env))
        pressure_low = TRUE
    else
        var/pressure = env.return_pressure()
        if(pressure < HAZARD_LOW_PRESSURE) pressure_low = TRUE
    if(pressure_low)
        if(istype(M, /mob/living/carbon))
            var/mob/living/carbon/C = M
            // Breathing apparatus allows safe breathing in low pressure
            if(hascall(C, "can_breathe_internals") && call(C, "can_breathe_internals")())
                return FALSE
            // Full pressure protection also prevents damage (requires both suit and head coverage)
            var/mob/living/carbon/human/H = M
            if(istype(H))
                var/head_ok = (H.head && (H.head.clothing_flags & STOPSPRESSUREDAMAGE))
                var/suit_ok = (H.wear_suit && (H.wear_suit.clothing_flags & STOPSPRESSUREDAMAGE))
                if(head_ok && suit_ok) return FALSE
        // Not protected — would harm now
        return TRUE
    // High-heat gating: if the environment is very hot or on fire, allow heat protection to suppress harm
    var/temp_high = FALSE
    if(locate(/obj/effect/hotspot) in T) temp_high = TRUE
    if(!temp_high && env)
        var/temp = env.temperature
        if(temp >= BODYTEMP_HEAT_WARNING_2)
            temp_high = TRUE
    if(temp_high)
        if(istype(M, /mob/living/carbon/human))
            var/mob/living/carbon/human/H = M
            // Full coverage heat protection at current temperature
            if(hascall(H, "get_heat_protection"))
                var/prot = call(H, "get_heat_protection")(env ? env.temperature : BODYTEMP_HEAT_WARNING_2)
                if(isnum(prot) && prot >= 1)
                    return FALSE
        // Not fully protected against heat — would harm now
        return TRUE
    // Other hazard types not gated here
    return TRUE

// Compute effective hazard pressure around M using perception hazards and reachability
/proc/npc_fsm_effective_hazard_pressure(mob/living/M)
    if(!M) return 0
    if(!hascall(M, "EnsurePerceptionBlackboard")) return 0
    M.EnsurePerceptionBlackboard()
    var/list/hz = null
    if(islist(M.perception?.kinds)) hz = M.perception.kinds["hazard"]
    if(!islist(hz)) hz = list()
    var/turf/origin = get_turf(M)
    if(!origin) return 0
    var/max_steps = npc_fsm_get("npc_fsm_exposure_max_steps")
    if(!isnum(max_steps)) max_steps = 12
    var/require_harm = npc_fsm_get("npc_fsm_hazard_require_would_harm")
    var/score = 0.0
    var/considered = 0
    var/max_considered = npc_fsm_get("npc_fsm_ehp_max_considered")
    if(!isnum(max_considered) || max_considered <= 0) max_considered = 10
    var/idx = 0
    var/len = length(hz)
    var/stride = (len > max_considered) ? max(1, round(len / max_considered)) : 1
    for(var/datum/perception_entry/E in hz)
        idx++
        if(stride > 1 && (idx % stride) != 0) continue
        if(!E) continue
        if(E.z != origin.z) continue
        var/turf/goal = locate(E.x, E.y, E.z)
        if(!goal) continue
        // Skip clearly non-walkable goals quickly
        if(!dslite_is_passable(goal, M))
            continue
        // Cheap precheck: skip far goals by Manhattan distance before pathing
        var/md = abs(origin.x - goal.x) + abs(origin.y - goal.y) + (origin.z == goal.z ? 0 : 1000)
        if(md > max_steps) continue
        var/steps = perception_path_steps_to(M, goal)
        if(steps >= 0 && steps <= max_steps)
            if(!require_harm || would_harm_now(M, goal))
                // Confidence-weighted contribution
                var/conf = isnum(E.confidence) ? E.confidence : 1.0
                score += conf
                considered++
        if(considered >= max_considered) break // cap work per tick to reduce load
    // Normalize softly: 0 if none; else cap ~2.0
    if(score <= 0) return 0
    return min(2.0, score)

// Attach on mob
/mob/living
    var/datum/ai_fsm/ai = null
    var/ai_state = "normal"
    var/ai_state_entered_ds = 0
    var/list/ai_state_stats = null
    var/list/ai_state_reason = null
    // Stored navigation preferences (Phase 5 stores only; later phases may consume)
    var/ai_nav_avoid_harm = TRUE
    var/ai_nav_door_penalty_factor = 2.0
    var/ai_nav_goal_mask = "base"
    var/ai_nav_allow_offduty = TRUE

/mob/living/proc/AI_FSM_Ensure()
    if(!ai)
        ai = new /datum/ai_fsm(src)
    return ai

/mob/living/proc/AI_FSM_Tick()
    var/datum/ai_fsm/F = AI_FSM_Ensure()
    if(F) F.Tick()
    return TRUE

/mob/living/proc/AI_FSM_ForceState(state, reason="admin")
    var/datum/ai_fsm/F = AI_FSM_Ensure()
    if(!npc_fsm_valid_state(state))
        npc_fsm_log_admin("force invalid state '[state]' on [src]")
        return FALSE
    if(F)
        var/ok = F.Enter(state, "ADMIN", reason)
        return ok
    return FALSE
