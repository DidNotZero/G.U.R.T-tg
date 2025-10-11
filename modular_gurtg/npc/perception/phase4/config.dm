// Phase 4 — NPC Perception & Sensing: Configuration
// This file defines runtime-tunable configuration variables and simple accessors.

// Global configuration variables with safe defaults
// Note: Access via the helper procs below to enable validation and live updates.

var/global/npc_perception_enabled = TRUE
var/global/npc_perception_range = 9
var/global/npc_perception_use_los = FALSE
var/global/npc_perception_max_entities = 80
var/global/npc_hearing_local_radius = 7
var/global/npc_speech_queue_max = 20
var/global/npc_perception_tick_skip = 2
var/global/npc_perception_across_z_default = FALSE
var/global/npc_perception_ttl_seconds = 60
var/global/npc_perception_overlay_realtime = FALSE
var/global/npc_perception_overlay_max_npcs = 15

// Accessors

/proc/npc_perception_get_config()
    // Returns an associative list of all configuration values
    var/list/cfg = list()
    cfg["enabled"] = npc_perception_enabled
    cfg["range"] = npc_perception_range
    cfg["use_los"] = npc_perception_use_los
    cfg["max_entities"] = npc_perception_max_entities
    cfg["hearing_local_radius"] = npc_hearing_local_radius
    cfg["speech_queue_max"] = npc_speech_queue_max
    cfg["tick_skip"] = npc_perception_tick_skip
    cfg["across_z_default"] = npc_perception_across_z_default
    cfg["ttl_seconds"] = npc_perception_ttl_seconds
    cfg["overlay_realtime"] = npc_perception_overlay_realtime
    cfg["overlay_max_npcs"] = npc_perception_overlay_max_npcs
    return cfg

/proc/npc_perception_get(key)
    switch(lowertext("[key]"))
        if("enabled")
            return npc_perception_enabled
        if("range")
            return npc_perception_range
        if("use_los")
            return npc_perception_use_los
        if("max_entities")
            return npc_perception_max_entities
        if("hearing_local_radius")
            return npc_hearing_local_radius
        if("speech_queue_max")
            return npc_speech_queue_max
        if("tick_skip")
            return npc_perception_tick_skip
        if("across_z_default")
            return npc_perception_across_z_default
        if("ttl_seconds")
            return npc_perception_ttl_seconds
    return null

/proc/npc_perception_set(key, value)
    // Returns TRUE on success; FALSE on invalid input
    switch(lowertext("[key]"))
        if("enabled")
            npc_perception_enabled = _npc_perception_as_bool(value)
            return TRUE
        if("range")
            var/n = clamp(text2num("[value]"), 1, 32)
            if(!isnum(n)) return FALSE
            npc_perception_range = n
            return TRUE
        if("use_los")
            npc_perception_use_los = _npc_perception_as_bool(value)
            return TRUE
        if("max_entities")
            var/n2 = clamp(text2num("[value]"), 1, 500)
            if(!isnum(n2)) return FALSE
            npc_perception_max_entities = n2
            return TRUE
        if("hearing_local_radius")
            var/n3 = clamp(text2num("[value]"), 0, 32)
            if(!isnum(n3)) return FALSE
            npc_hearing_local_radius = n3
            return TRUE
        if("speech_queue_max")
            var/n4 = clamp(text2num("[value]"), 1, 200)
            if(!isnum(n4)) return FALSE
            npc_speech_queue_max = n4
            return TRUE
        if("tick_skip")
            var/n5 = clamp(text2num("[value]"), 0, 10)
            if(!isnum(n5)) return FALSE
            npc_perception_tick_skip = n5
            return TRUE
        if("across_z_default")
            npc_perception_across_z_default = _npc_perception_as_bool(value)
            return TRUE
        if("ttl_seconds")
            var/n6 = clamp(text2num("[value]"), 5, 600)
            if(!isnum(n6)) return FALSE
            npc_perception_ttl_seconds = n6
            return TRUE
        if("overlay_realtime")
            npc_perception_overlay_realtime = _npc_perception_as_bool(value)
            return TRUE
        if("overlay_max_npcs")
            var/n7 = clamp(text2num("[value]"), 1, 200)
            if(!isnum(n7)) return FALSE
            npc_perception_overlay_max_npcs = n7
            return TRUE
    return FALSE
/proc/_npc_perception_as_bool(value)
    // Coerce common forms to boolean
    if (isnum(value)) return value != 0
    var/t = lowertext("[value]")
    if (t == "1" || t == "true" || t == "on" || t == "yes") return TRUE
    if (t == "0" || t == "false" || t == "off" || t == "no" || t == "") return FALSE
    return !!value
