// Phase 6 — NPC Utility (Neko)
// Module: Configuration surface and defaults
// Files in this module are included after Phase 4 perception and Phase 5 FSM.

// Global configuration map (runtime-adjustable)
var/global/list/npc_utility_config = null

// Defaults per quickstart and data-model
/proc/npc_utility_default_config()
    var/list/c = list()
    c["npc_utility_enabled"] = TRUE
    c["npc_utility_tick_skip"] = 1
    c["npc_utility_min_commit_s"] = 6
    c["npc_utility_hysteresis"] = 0.15
    c["npc_utility_emerg_preempt"] = TRUE
    c["npc_utility_weight_floor"] = 0.05
    c["npc_utility_debug"] = FALSE
    return c

// Public API: get one key
/proc/npc_utility_get(key)
    if(!islist(npc_utility_config)) npc_utility_config = npc_utility_default_config()
    return npc_utility_config[key]

// Public API: get a shallow copy of the config
/proc/npc_utility_get_config()
    if(!islist(npc_utility_config)) npc_utility_config = npc_utility_default_config()
    return npc_utility_config.Copy()

// Public API: set a key with validation; returns TRUE on success
/proc/npc_utility_set(key, value)
    if(!islist(npc_utility_config)) npc_utility_config = npc_utility_default_config()
    var/normalized = npc_utility_validate(key, value)
    if(isnull(normalized))
        npc_utility_log_admin("Invalid config: [key]=[value]")
        return FALSE
    npc_utility_config[key] = normalized
    return TRUE

// Validation helper: returns normalized value or null if invalid
/proc/npc_utility_validate(key, value)
    if(!istext(key)) return null
    switch(lowertext(key))
        if("npc_utility_enabled")
            return value ? TRUE : FALSE
        if("npc_utility_tick_skip")
            if(!isnum(value)) return null
            return max(0, round(value))
        if("npc_utility_min_commit_s")
            if(!isnum(value)) return null
            return max(0, value)
        if("npc_utility_hysteresis")
            if(!isnum(value)) return null
            var/v = value
            if(v < 0) v = 0
            if(v > 1) v = 1
            return v
        if("npc_utility_emerg_preempt")
            return value ? TRUE : FALSE
        if("npc_utility_weight_floor")
            if(!isnum(value)) return null
            var/v2 = value
            if(v2 < 0) v2 = 0
            if(v2 > 1) v2 = 1
            return v2
        if("npc_utility_debug")
            return value ? TRUE : FALSE
        else
            // Unknown key → reject
            return null

// Admin-visible logging helper (transition/config)
/proc/npc_utility_log_admin(msg)
    world.log << "NPC Utility: [msg]"
    message_admins(span_adminnotice("NPC Utility: [msg]"))

