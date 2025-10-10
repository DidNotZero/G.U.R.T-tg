// gurtstation: NPC Perception debug — admin verbs
#include "config.dm"

// Admin verb: Show Perception (uses admin verb system)
ADMIN_VERB(show_npc_perception, R_ADMIN, "NPC: Show Perception", "Show perception summary for a target mob.", ADMIN_CATEGORY_DEBUG, mob/target in world)
    if (!target)
        return
    var/list/snap = PerceptionSnapshot(target)
    if (!islist(snap))
        to_chat(user, "No perception data for [target]. Try forcing a sense update.", confidential = TRUE)
        return
    var/hcount = islist(snap["hazards"]) ? length(snap["hazards"]) : 0
    var/acount = islist(snap["actors"]) ? length(snap["actors"]) : 0
    var/ocount = islist(snap["objects"]) ? length(snap["objects"]) : 0
    var/mcount = islist(snap["messages"]) ? length(snap["messages"]) : 0
    var/datum/perception_memory/M = get_perception_memory(target, FALSE)
    var/datum/perceived_hazard/h_nearest = null
    var/h_nearest_dist = 1.0e9
    var/datum/perceived_hazard/h_max = null
    var/h_max_sev = -1
    if (M)
        var/turf/tt = get_turf(target)
        for (var/datum/perceived_hazard/h in M.hazards)
            if (h.severity > h_max_sev)
                h_max_sev = h.severity; h_max = h
            if (tt && h.location)
                var/d = get_dist(tt, h.location)
                if (d < h_nearest_dist)
                    h_nearest_dist = d; h_nearest = h
    var/nearest_txt = "none"
    if (h_nearest)
        var/turf/hl = h_nearest.location
        var/loc_near = hl ? "[hl.x],[hl.y],[hl.z]" : "?"
        nearest_txt = "[h_nearest.type]@[loc_near] (d=[h_nearest_dist])"
    var/max_txt = h_max ? "[h_max.type](sev=[h_max.severity])" : "none"
    var/perf_txt = ""
    var/list/perf = snap["perf"]
    var/danger = snap["dangerFlag"]
    if (islist(perf))
        var/lastDs = perf["lastDs"]
        var/avgDs = perf["avgDs"]
        var/samples = perf["samples"]
        perf_txt = " | perf last=[lastDs]ds avg=[avgDs]ds n=[samples]"
    to_chat(user, "Perception for [target]: danger=[danger], hazards=[hcount] (nearest=[nearest_txt], highest=[max_txt]), actors=[acount], objects=[ocount], messages=[mcount][perf_txt]", confidential = TRUE)

    // Nearest actor summary
    var/datum/perceived_actor/a_nearest = null
    if (M && length(M.actors))
        for (var/datum/perceived_actor/aa in M.actors)
            if (!a_nearest || aa.distance < a_nearest.distance)
                a_nearest = aa
    if (a_nearest)
        to_chat(user, "Nearest actor: id=[a_nearest.actor_ref], role=[a_nearest.role], d=[a_nearest.distance]", confidential = TRUE)

    // Top 3 objects summary (most recently seen first)
    if (M && length(M.objects))
        var/list/objs = sort_list(M.objects.Copy(), /proc/cmp_obj_lastseen_dsc)
        var/limit = min(3, objs.len)
        var/line = "Objects: "
        for (var/i=1, i<=limit, i++)
            var/datum/perceived_object/o = objs[i]
            var/turf/ot = o.location
            var/loc_obj = ot ? "[ot.x],[ot.y],[ot.z]" : "?"
            line += "[o.category]@[loc_obj]"
            if (i < limit)
                line += ", "
        to_chat(user, line, confidential = TRUE)

    // Recent heard messages
    if (M && length(M.messages))
        var/list/recent = M.last_heard(5)
        var/msgline = "Heard: "
        for (var/i=1, i<=recent.len, i++)
            var/datum/heard_message/hm = recent[i]
            var/chan = hm.channel ? ": [hm.channel]" : ""
            msgline += "[hm.msg_type][chan]"
            if (i < recent.len)
                msgline += ", "
        to_chat(user, msgline, confidential = TRUE)

// Admin verb: Force immediate Sense()
ADMIN_VERB(force_npc_sense_update, R_ADMIN, "NPC: Force Sense Update", "Trigger an immediate Sense() cycle for a target mob.", ADMIN_CATEGORY_DEBUG, mob/target in world)
    if (!target)
        return
    Sense(target)
    to_chat(user, "Forced perception update for [target].", confidential = TRUE)

// Comparators for debug presentation
/proc/cmp_obj_lastseen_dsc(datum/perceived_object/a, datum/perceived_object/b)
    return b.last_seen_ts - a.last_seen_ts

/proc/cmp_obj_lastseen_asc(datum/perceived_object/a, datum/perceived_object/b)
    return a.last_seen_ts - b.last_seen_ts
