// Phase 5 — NPC FSM (Neko)
// Module: TGUI panel plumbing

#define ADMIN_VERB_CATEGORY "NPC FSM"

// Open verb
ADMIN_VERB(npc_fsm_panel, R_DEBUG, "NPC FSM (TGUI)", "Observe and control NPC FSM state.", ADMIN_CATEGORY_DEBUG)
    var/datum/npc_fsm_panel/P = new(user)
    P.ui_interact(user.mob)

/datum/npc_fsm_panel
    var/client/holder

/datum/npc_fsm_panel/New(user)
    if(istype(user, /client))
        holder = user
    else
        var/mob/M = user
        holder = M?.client
    ..()

/datum/npc_fsm_panel/ui_state(mob/user)
    return ADMIN_STATE(R_DEBUG)

/datum/npc_fsm_panel/ui_close()
    qdel(src)

/datum/npc_fsm_panel/ui_interact(mob/user, datum/tgui/ui)
    ui = SStgui.try_update_ui(user, src, ui)
    if(!ui)
        ui = new(user, src, "NpcAIState")
        ui.open()

/datum/npc_fsm_panel/ui_data(mob/user)
    var/list/data = list()
    data["alert_level"] = npc_fsm_alert_level
    data["evac_enabled"] = !!npc_fsm_evac_enabled
    data["rows"] = npc_ai_fsm_panel_rows(50, 0)
    return data

/datum/npc_fsm_panel/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
    . = ..()
    if(.) return
    if(!check_rights(R_DEBUG)) return
    switch(action)
        if("set_alert")
            var/level = params["level"]
            npc_ai_broadcast_alert(level)
            return TRUE
        if("set_evac")
            var/en = text2num(params["enabled"]) ? TRUE : FALSE
            npc_ai_signal_evac(en)
            return TRUE
        if("force_state")
            var/refid = params["id"]
            var/new_state = params["state"]
            var/mob/living/M = locate(refid)
            if(M)
                npc_ai_fsm_force(M, new_state, "panel")
                return TRUE
    return FALSE
