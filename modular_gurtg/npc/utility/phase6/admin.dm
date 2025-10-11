// Phase 6 — NPC Utility (Neko)
// Module: Admin helpers and global procs (scaffold)

// Broadcast current utility config to admins
/proc/npc_ai_utility_broadcast_config()
    var/list/cfg = npc_utility_get_config()
    var/list/parts = list()
    for(var/k in cfg)
        parts += "[k]=[cfg[k]]"
    npc_utility_log_admin("config → [parts.Join(", ")]")
    return TRUE

// Set a utility config key
/proc/npc_ai_utility_set_config(key as text, value)
    var/ok = npc_utility_set(key, value)
    if(ok)
        npc_utility_log_admin("set [key]=[value]")
    return ok

// Force a goal on a specific NPC (override gating)
/proc/npc_ai_utility_force_goal(mob/living/M, goal_id as text)
    if(!istype(M, /mob/living)) return FALSE
    if(!istext(goal_id) || !length(goal_id)) return FALSE
    var/override_note = ""
    if(M.ai)
        var/list/pol = M.ai.PolicyFor(M.ai.state)
        if(islist(pol) && lowertext("[pol["goal_mask"]]") == "evac_only")
            override_note = " (override gating: evac_only)"
    M.ai_forced_goal = "[goal_id]"
    M.ai_forced_active = TRUE
    M.ai_current_goal = "[goal_id]"
    npc_utility_log_admin("force goal '[goal_id]' on [M][override_note]")
    return TRUE

// Trigger re-evaluation for one or all NPCs
/proc/npc_ai_utility_re_eval(target=null)
    if(isnull(target))
        var/ct = 0
        for(var/mob/living/M in world)
            if(!M.npc_is_crew) continue
            if(hascall(M, "AI_UTILITY_Tick"))
                M.AI_UTILITY_Tick()
                ct++
        npc_utility_log_admin("re-eval all ([ct])")
        return TRUE
    else
        var/mob/living/M = target
        if(!istype(M, /mob/living)) return FALSE
        if(hascall(M, "AI_UTILITY_Tick"))
            M.AI_UTILITY_Tick()
            npc_utility_log_admin("re-eval [M]")
            return TRUE
    return FALSE
