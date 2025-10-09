// Phase 1 NPC Autospawn – Admin verbs


// View current configuration
ADMIN_VERB(show_npc_autospawn_config, R_ADMIN, "NPC Autospawn Config", "View current NPC autospawn settings.", ADMIN_CATEGORY_DEBUG)
	var/enabled = npc_autospawn_enabled()
	var/radius = npc_idle_radius()
	to_chat(user, span_adminnotice("NPC Autospawn is [enabled ? span_bold("ENABLED") : span_bolddanger("DISABLED")]"), confidential = TRUE)
	to_chat(user, span_adminnotice("Idle radius = [radius] (clamped 1–10). Changes apply next round."), confidential = TRUE)

// Show last round's spawn summary
ADMIN_VERB(show_npc_spawn_summary, R_ADMIN, "NPC Autospawn Summary", "View last per-role NPC spawn summary.", ADMIN_CATEGORY_DEBUG)
	var/list/summary = GLOB.gurt_npc_last_spawn_summary
	if(!islist(summary) || !length(summary))
		to_chat(user, span_notice("No autospawn this round."), confidential = TRUE)
		return
	var/list/parts = list()
	for(var/role_title in summary)
		parts += "[role_title]: [summary[role_title]]"
	to_chat(user, span_adminnotice("Spawned → [parts.Join(", ")]"), confidential = TRUE)
