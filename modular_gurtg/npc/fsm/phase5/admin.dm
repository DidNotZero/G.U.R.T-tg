// Phase 5 — NPC FSM (Neko)
// Module: Admin helpers and global signals

// Global state for station alert and evacuation flag
var/global/npc_fsm_alert_level = null  // e.g., "green", "blue", "red", "delta"
var/global/npc_fsm_evac_enabled = FALSE

// Set the station alert level (case-insensitive)
/proc/npc_ai_broadcast_alert(level)
    if(isnull(level))
        npc_fsm_alert_level = null
        npc_fsm_log_admin("alert cleared")
        return TRUE
    var/t = lowertext("[level]")
    npc_fsm_alert_level = t
    npc_fsm_log_admin("alert set to [t]")
    return TRUE

// Toggle evacuation flag (0/1, FALSE/TRUE)
/proc/npc_ai_signal_evac(onoff)
    npc_fsm_evac_enabled = onoff ? TRUE : FALSE
    npc_fsm_log_admin("evac set to [npc_fsm_evac_enabled ? "ON" : "OFF"]")
    return TRUE

