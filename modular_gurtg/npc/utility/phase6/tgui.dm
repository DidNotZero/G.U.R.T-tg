// Phase 6 — NPC Utility (Neko)
// Module: TGUI panel plumbing (scaffold)

#define ADMIN_VERB_CATEGORY "NPC Utility"

// Open verb
ADMIN_VERB(npc_utility_panel, R_DEBUG, "NPC Utility (TGUI)", "Observe and tune NPC Utility.", ADMIN_CATEGORY_DEBUG)
    var/datum/npc_utility_panel/P = new(user)
    P.ui_interact(user.mob)

/datum/npc_utility_panel
    var/client/holder

/datum/npc_utility_panel/New(user)
    if(istype(user, /client))
        holder = user
    else
        var/mob/M = user
        holder = M?.client
    ..()

/datum/npc_utility_panel/ui_state(mob/user)
    return ADMIN_STATE(R_DEBUG)

/datum/npc_utility_panel/ui_close()
    qdel(src)

/datum/npc_utility_panel/ui_interact(mob/user, datum/tgui/ui)
    ui = SStgui.try_update_ui(user, src, ui)
    if(!ui)
        ui = new(user, src, "NpcUtility")
        ui.open()

/datum/npc_utility_panel/ui_data(mob/user)
    var/list/data = list()
    data["config"] = npc_utility_get_config()
    data["rows"] = npc_ai_utility_panel_rows(50, 0)
    return data

/datum/npc_utility_panel/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
    . = ..()
    if(.) return
    if(!check_rights(R_DEBUG)) return
    switch(action)
        if("set_config")
            var/key = params["key"]
            var/value = params["value"]
            npc_ai_utility_set_config(key, value)
            return TRUE
        if("force_goal")
            var/refid = params["id"]
            var/goal = params["goal"]
            var/mob/living/M = locate(refid)
            if(M)
                npc_ai_utility_force_goal(M, goal)
                return TRUE
        if("re_eval")
            var/refid2 = params["id"]
            if(refid2)
                var/mob/living/N = locate(refid2)
                if(N) npc_ai_utility_re_eval(N)
            else
                npc_ai_utility_re_eval(null)
            return TRUE
    return FALSE

// Build panel rows (placeholder fields)
/proc/npc_ai_utility_panel_rows(limit = null, offset = 0)
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
        row["fsm_state"] = istext(M.ai_state) ? M.ai_state : (M.ai?.state || "normal")
        row["current_goal"] = istext(M.ai_current_goal) ? M.ai_current_goal : ""
        var/age_ds = now - (M.ai_goal_age_ds || now)
        if(age_ds < 0) age_ds = 0
        row["goal_age_s"] = round(age_ds / 10)
        // Top-3 candidates (placeholder)
        var/list/top = islist(M.ai_utility_top_candidates) ? M.ai_utility_top_candidates : list()
        row["top"] = top
        // Forced-goal indicators and warning
        row["forced_active"] = !!M.ai_forced_active
        row["forced_goal"] = istext(M.ai_forced_goal) ? M.ai_forced_goal : ""
        row["can_emerg_interrupt"] = !!npc_utility_get("npc_utility_emerg_preempt")
        row["forced_warning"] = (row["forced_active"] && row["can_emerg_interrupt"]) ? "Emergency can interrupt" : ""
        // Performance counters
        row["utility_eval_ms"] = M.ai_utility_last_eval_ms || 0
        var/up_s = 0
        if(istype(M.ai_utility, /datum/ai_utility))
            var/sds = M.ai_utility.started_ds || now
            var/uds = now - sds
            if(uds < 0) uds = 0
            up_s = round(uds / 10)
        row["utility_uptime_s"] = up_s
        var/list/ctr = islist(M.ai_utility?.counters) ? M.ai_utility.counters : list("evals"=0, "switches"=0, "preempts"=0)
        row["evals"] = ctr["evals"] || 0
        row["switches"] = ctr["switches"] || 0
        row["preempts"] = ctr["preempts"] || 0
        rows += list(row)
        if(length(rows) >= maxn) break
    return rows
