// Phase 5 — NPC FSM (Neko)
// Module: Admin API procs (force, rows)

// Force a specific NPC into a state
/proc/npc_ai_fsm_force(mob/living/M, state as text, reason as text)
    if(!istype(M, /mob/living)) return FALSE
    return M.AI_FSM_ForceState(state, istext(reason) ? reason : "admin")

// Build compact rows for TGUI panel
/proc/npc_ai_fsm_panel_rows(limit = null, offset = 0)
    var/list/rows = list()
    var/maxn = isnum(limit) && limit > 0 ? limit : 100
    var/off = isnum(offset) && offset > 0 ? offset : 0
    var/i = 0
    var/now = world.time
    for(var/mob/living/M in world)
        if(!M.npc_is_crew) continue
        i++
        if(i <= off) continue
        var/list/row = list()
        row["id"] = REF(M)
        row["name"] = "[M]"
        var/st = istext(M.ai_state) ? M.ai_state : (M.ai?.state || "normal")
        row["state"] = st
        var/entered = M.ai_state_entered_ds || now
        var/age_ds = now - entered
        if(age_ds < 0) age_ds = 0
        row["time_in_state_s"] = round(age_ds / 10)
        var/ehp = M.ai ? (M.ai.ehp_cache_value || 0) : 0
        row["ehp_rounded"] = round(ehp, 0.01)
        var/alar = FALSE
        var/area/A = get_area(get_turf(M))
        if(A && A.fire) alar = TRUE
        row["alarm_nearby"] = alar
        var/list/reason = islist(M.ai_state_reason) ? M.ai_state_reason : M.ai?.last_reason
        row["last_reason_code"] = islist(reason) ? (reason["code"] || "") : ""
        var/rtime = islist(reason) ? (reason["time_ds"] || now) : now
        var/rage = now - rtime
        if(rage < 0) rage = 0
        row["last_reason_age_s"] = round(rage / 10)
        var/list/pol = M.ai ? M.ai.PolicyFor(st) : list("perception_tick_skip"=2, "speech_hearing_radius"=0)
        row["tick_skip"] = pol["perception_tick_skip"] || 0
        row["speech_radius"] = pol["speech_hearing_radius"] || 0
        rows += list(row)
        if(length(rows) >= maxn) break
    return rows
