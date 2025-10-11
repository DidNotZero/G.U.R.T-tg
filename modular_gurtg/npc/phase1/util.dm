// Phase 1 NPC Autospawn – Shared utilities

// Phase 4 Perception is included via tgstation.dme
// Include TGUI backend here to avoid missing panel if DME not updated in some forks
#include "../perception/phase4/tgui.dm"


// Global last-round summary for admin verb access
GLOBAL_LIST(gurt_npc_last_spawn_summary)

// Marker for NPC crew (autospawned/managed NPCs)
/mob/living
    var/npc_is_crew = FALSE

/proc/is_interior_area(area/A)
	if(!A)
		return FALSE
	// Interior if not space/nearstation/asteroid (station exterior)
	return !is_area_nearby_station(A)

/proc/is_turf_safe(turf/T)
	if(!isturf(T))
		return FALSE
	if(is_space_or_openspace(T))
		return FALSE
	var/area/A = get_area(T)
	if(!is_interior_area(A))
		return FALSE
	// Basic check for enterability: avoid dense walls/closed turfs
	if(isclosedturf(T))
		return FALSE
	return TRUE

// Find a nearby safe turf using expanding radius search
/proc/nearest_safe_turf(turf/from)
	if(is_turf_safe(from))
		return from
	// Search up to 10 tiles away
	for(var/r = 1, r <= 10, r++)
		for(var/atom/A as anything in orange(from, r))
			if(!isturf(A))
				continue
			var/turf/T = A
			if(is_turf_safe(T))
				return T
	return null

// True if a joinable job has an unfilled spawn slot (finite only)
/proc/role_is_unfilled(datum/job/J)
	if(!J)
		return FALSE
	// Unfilled means no one has this role at roundstart (spawn exactly one NPC)
	return J.current_positions <= 0

// Disallow certain roles from NPC autospawn (e.g., AI, Cyborg)
/proc/role_is_disallowed(datum/job/J)
	if(!J)
		return TRUE
	if(istype(J, /datum/job/ai))
		return TRUE
	if(istype(J, /datum/job/cyborg))
		return TRUE
	if(istype(J, /datum/job/prisoner))
		return TRUE
	return FALSE

// Collect jobs that need exactly one NPC spawned
/proc/collect_unfilled_roles(list/jobs)
	var/list/out = list()
	if(!islist(jobs))
		return out
	for(var/datum/job/J as anything in jobs)
		if(role_is_unfilled(J) && !role_is_disallowed(J))
			out += J
	return out

// How many NPCs are needed to fill roundstart spawn slots for this job
/proc/missing_spawn_slots(datum/job/J)
	if(!J)
		return 0
	if(role_is_disallowed(J))
		return 0
	// Prefer filling roundstart spawn slots; if zero, fall back to total positions
	var/desired = 0
	if(J.spawn_positions > 0)
		desired = J.spawn_positions
	else if(J.total_positions > 0)
		desired = J.total_positions
	else
		return 0
	var/missing = desired - J.current_positions
	return max(missing, 0)

/proc/rebuild_manifest()
	GLOB.manifest.build()
	return TRUE

/proc/log_spawn_summary(list/summary)
	if(!islist(summary))
		return
	var/list/parts = list()
	for(var/role_title in summary)
		parts += "[role_title]: [summary[role_title]]"
	var/text = "NPC autospawn summary → [parts.Join(", ")]"
	log_world(text)
	message_admins(span_notice(text))
	GLOB.gurt_npc_last_spawn_summary = summary.Copy()
	return TRUE
