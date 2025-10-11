// NPC Perception — Admin TGUI panel

// Open verb
ADMIN_VERB(npc_perception_panel, R_DEBUG, "NPC Perception (TGUI)", "Manage NPC perception settings and overlay.", ADMIN_CATEGORY_DEBUG)
    var/datum/npc_perception_panel/P = new(user)
    P.ui_interact(user.mob)

/datum/npc_perception_panel
    var/client/holder

/datum/npc_perception_panel/New(user)
    if(istype(user, /client))
        holder = user
    else
        var/mob/M = user
        holder = M?.client
    ..()

/datum/npc_perception_panel/ui_state(mob/user)
    return ADMIN_STATE(R_DEBUG)

/datum/npc_perception_panel/ui_close()
    qdel(src)

/datum/npc_perception_panel/ui_interact(mob/user, datum/tgui/ui)
    ui = SStgui.try_update_ui(user, src, ui)
    if(!ui)
        ui = new(user, src, "NpcPerception")
        ui.open()

/datum/npc_perception_panel/ui_data(mob/user)
    var/list/data = list()
    var/list/cfg = npc_perception_get_config()
    data["config"] = cfg
    data["overlay_enabled"] = !!npc_perception_overlay_enabled
    data["timer_active"] = !!NPC_PERCEPTION_TIMER_ACTIVE
    var/crew = 0
    var/list/hazards = list()
    var/maxn = isnum(cfg["overlay_max_npcs"]) ? cfg["overlay_max_npcs"] : 15
    for(var/mob/living/M in world)
        if(!M.npc_is_crew) continue
        crew++
        if(length(hazards) >= maxn) continue
        if(!M.perception) continue
        var/list/hz = islist(M.perception.kinds) ? M.perception.kinds["hazard"] : null
        if(!islist(hz)) continue
        var/list/row = list()
        row["mob"] = "[M]"
        row["ref"] = REF(M)
        row["count"] = length(hz)
        var/list/entries = list()
        var/limit = min(20, row["count"]) // per-NPC cap in UI data
        var/now = world.time
        for(var/i=1 to limit)
            var/datum/perception_entry/E = hz[i]
            if(!E) continue
            var/age_ds = now - (E.last_seen || now)
            if(age_ds < 0) age_ds = 0
            var/list/item = list(
                "x" = E.x,
                "y" = E.y,
                "z" = E.z,
                "age_s" = round(age_ds / 10),
                "confidence" = E.confidence,
            )
            entries += list(item)
        row["hazards"] = entries
        hazards += list(row)
    data["crew_count"] = crew
    data["hazards"] = hazards
    return data

/datum/npc_perception_panel/ui_act(action, list/params, datum/tgui/ui, datum/ui_state/state)
    . = ..()
    if(.) return
    if(!check_rights(R_DEBUG)) return
    switch(action)
        if("toggle_overlay")
            var/enable = text2num(params["enable"]) ? "on" : "off"
            ai_perception_overlay(enable)
            return TRUE
        if("refresh")
            var/limit = text2num(params["limit"])
            if(limit <= 0) limit = null
            npc_perception_overlay_refresh(limit)
            return TRUE
        if("profile")
            var/ticks = clamp(text2num(params["ticks"]), 1, 100)
            ai_perception_profile(ticks)
            return TRUE
        if("set_config")
            var/key = params["key"]
            var/value = params["value"]
            npc_perception_config_set(key, "[value]")
            return TRUE
        if("ensure_timer")
            npc_perception_ensure_timer()
            return TRUE
    return FALSE
