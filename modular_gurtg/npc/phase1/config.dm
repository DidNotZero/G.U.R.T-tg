// Phase 1 NPC Autospawn – Configuration and accessors

// Config entries
/datum/config_entry/flag/npc_autospawn_enabled
	default = TRUE

/datum/config_entry/number/npc_idle_radius
	default = 4
	min_val = 1
	max_val = 10

// Accessors
/proc/npc_autospawn_enabled()
	return CONFIG_GET(flag/npc_autospawn_enabled)

/proc/npc_idle_radius()
	var/r = CONFIG_GET(number/npc_idle_radius)
	return clamp(r, 1, 10)

