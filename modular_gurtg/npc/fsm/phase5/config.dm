// Phase 5 — NPC FSM (Neko)
// Module: Configuration surface and defaults
// Files in this module are included after Phase 4 perception.

// Global configuration map (runtime-adjustable)
var/global/list/npc_fsm_config = null

// Initialize defaults on world startup
/world/New()
    ..()
    if(!islist(npc_fsm_config))
        npc_fsm_config = npc_fsm_default_config()

// Defaults per research.md and data-model.md
/proc/npc_fsm_default_config()
    var/list/c = list()
    c["npc_fsm_hazard_pressure_threshold"] = 0.60
    c["npc_fsm_clear_seconds"] = 30
    c["npc_fsm_critical_levels"] = list("red", "delta", "evac")
    c["npc_fsm_ehp_cache_seconds"] = 1
    c["npc_fsm_ehp_max_considered"] = 10
    c["npc_fsm_exposure_require_same_atmos_region"] = TRUE
    c["npc_fsm_exposure_max_steps"] = 12
    c["npc_fsm_exposure_max_barriers"] = 0
    c["npc_fsm_hazard_require_would_harm"] = TRUE
    c["npc_fsm_critical_tick_skip"] = 0
    // String area paths for documentation-friendly defaults; can be typepaths at runtime
    c["npc_fsm_contained_area_types"] = list("/area/server", "/area/datacenter")
    return c

// Public API: get one key
/proc/npc_fsm_get(key)
    if(!islist(npc_fsm_config)) npc_fsm_config = npc_fsm_default_config()
    return npc_fsm_config[key]

// Public API: get a shallow copy of the config
/proc/npc_fsm_get_config()
    if(!islist(npc_fsm_config)) npc_fsm_config = npc_fsm_default_config()
    return npc_fsm_config.Copy()

// Public API: set a key with validation; returns TRUE on success
/proc/npc_fsm_set(key, value)
    if(!islist(npc_fsm_config)) npc_fsm_config = npc_fsm_default_config()
    var/normalized = npc_fsm_validate(key, value)
    if(isnull(normalized))
        npc_fsm_log_admin("Invalid config: [key]=[value]")
        return FALSE
    npc_fsm_config[key] = normalized
    return TRUE

// Validation helper: returns normalized value or null if invalid
/proc/npc_fsm_validate(key, value)
    if(!istext(key)) return null
    switch(lowertext(key))
        if("npc_fsm_hazard_pressure_threshold")
            if(!isnum(value)) return null
            if(value < 0) value = 0
            if(value > 1) value = 1
            return value
        if("npc_fsm_clear_seconds")
            if(!isnum(value)) return null
            return max(0, round(value))
        if("npc_fsm_critical_levels")
            if(!islist(value)) return null
            var/list/out = list()
            for(var/v in value)
                if(isnull(v)) continue
                if(istext(v))
                    var/t = lowertext("[v]")
                    if(!(t in out)) out += t
            if(!length(out)) return null
            return out
        if("npc_fsm_exposure_require_same_atmos_region")
            return value ? TRUE : FALSE
        if("npc_fsm_exposure_max_steps")
            if(!isnum(value)) return null
            return max(0, round(value))
        if("npc_fsm_exposure_max_barriers")
            if(!isnum(value)) return null
            return max(0, round(value))
        if("npc_fsm_hazard_require_would_harm")
            return value ? TRUE : FALSE
        if("npc_fsm_ehp_cache_seconds")
            if(!isnum(value)) return null
            return max(0, round(value))
        if("npc_fsm_ehp_max_considered")
            if(!isnum(value)) return null
            return max(1, round(value))
        if("npc_fsm_critical_tick_skip")
            if(!isnum(value)) return null
            return max(0, round(value))
        if("npc_fsm_contained_area_types")
            if(!islist(value)) return null
            // Accept strings or type paths; store as provided
            var/list/out2 = list()
            for(var/v2 in value)
                if(isnull(v2)) continue
                if(istext(v2) || ispath(v2)) out2 += v2
            return out2
        else
            // Unknown key → reject
            return null

// Admin-visible logging helper (transition/config)
/proc/npc_fsm_log_admin(msg)
    // Admin-visible + world log
    world.log << "NPC FSM: [msg]"
    message_admins(span_adminnotice("NPC FSM: [msg]"))
