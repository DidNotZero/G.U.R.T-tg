// Phase 4 — NPC Perception & Sensing: Admin helpers (skeleton)
// Verbs and helpers for runtime configuration & simple profiling/overlay toggles.

#define ADMIN_VERB_CATEGORY "NPC Perception"

// Overlay state (runtime toggle)
var/global/npc_perception_overlay_enabled = FALSE

/proc/ai_perception_overlay(state as text)
    // Admin helper: "on" / "off"
    var/s = lowertext(dm_trim(state))
    if(s == "on")
        npc_perception_overlay_enabled = TRUE
        to_world_log("[ADMIN_VERB_CATEGORY]: overlay enabled")
        return TRUE
    if(s == "off")
        npc_perception_overlay_enabled = FALSE
        to_world_log("[ADMIN_VERB_CATEGORY]: overlay disabled")
        return TRUE
    return FALSE

/proc/show_npc_perception_config()
    var/list/cfg = npc_perception_get_config()
    var/text = "NPC Perception Config:\n"
    for(var/k in cfg)
        text += " - [k]: [cfg[k]]\n"
    to_world_log(text)
    return text

/proc/ai_perception_profile(ticks as num)
    // Print current summary counters for all NPCs
    var/n = clamp(round(ticks), 1, 100)
    var/count = 0
    for(var/mob/living/M in world)
        if(!M.npc_is_crew) continue
        if(!M.perception) continue
        var/list/pc = M.perception_counters
        var/p = islist(pc) ? pc["processed"] : 0
        var/c = islist(pc) ? pc["capped"] : 0
        var/t = islist(pc) ? pc["throttled"] : 0
        to_world_log("[ADMIN_VERB_CATEGORY]: [M] last=[M.last_perception_sense_ms]ms processed=[p] capped=[c] thr=[t]")
        count++
        if(count >= n) break
    return count

// Utility for admin output
/proc/to_world_log(msg)
    world.log << msg

// Local utility: simple string trim
/proc/dm_trim(t as text)
    if(isnull(t)) return ""
    // remove leading/trailing whitespace
    var/text = "[t]"
    // leading
    while(length(text) && copytext(text, 1, 2) == " ")
        text = copytext(text, 2)
    // trailing
    while(length(text) && copytext(text, length(text), 0) == " ")
        text = copytext(text, 1, length(text))
    return text

// Admin verbs removed in favor of consolidated TGUI panel (NpcPerception)

// --- Config verbs ---

/proc/npc_perception_config_set(key as text, value as text)
    var/ok = npc_perception_set(key, value)
    if(ok)
        to_world_log("[ADMIN_VERB_CATEGORY]: set [key]=[npc_perception_get(key)]")
    else
        to_world_log("[ADMIN_VERB_CATEGORY]: failed to set [key] to [value]")
    return ok

/proc/npc_perception_config_get(key as text)
    var/val = npc_perception_get(key)
    to_world_log("[ADMIN_VERB_CATEGORY]: [key]=[val]")
    return val

// --- Overlay helpers (textual) ---

/proc/npc_perception_overlay_refresh(limit as num)
    if(!npc_perception_overlay_enabled)
        to_world_log("[ADMIN_VERB_CATEGORY]: overlay is disabled")
        return FALSE
    var/total_shown = 0
    var/maxn = isnum(limit) && limit > 0 ? limit : npc_perception_overlay_max_npcs
    for(var/mob/living/M in world)
        if(!M.npc_is_crew) continue
        if(!M.perception) continue
        var/list/hz = null
        if(islist(M.perception.kinds)) hz = M.perception.kinds["hazard"]
        if(!islist(hz))
            hz = list()
            for(var/datum/perception_entry/E in M.perception.entries)
                if(E.kind == "hazard") hz += E
        var/hcount = length(hz)
        var/line = "[M] hazards=[hcount] last=[M.last_perception_sense_ms]ms"
        if(hcount > 0)
            var/preview = min(3, hcount)
            line += " preview:"
            for(var/i=1 to preview)
                var/datum/perception_entry/H = hz[i]
                line += " ([H.x],[H.y],[H.z])"
        to_world_log("[ADMIN_VERB_CATEGORY]: [line]")
        message_admins(span_adminnotice("[ADMIN_VERB_CATEGORY]: [line]"))
        total_shown++
        if(total_shown >= maxn) break
    return total_shown
