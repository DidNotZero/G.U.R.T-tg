// Phase 1 NPC Autospawn – Roundstart spawning



// Subsystem used only to register the roundstart hook
SUBSYSTEM_DEF(gurt_npc_phase1)
	name = "NPC Autospawn (Phase 1)"
	flags = SS_NO_FIRE

/datum/controller/subsystem/gurt_npc_phase1/Initialize()
    SSticker.OnPreRoundstart(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(npc_spawn_roundstart)))
    // Ensure perception timer is running to drive Sense() cadence for NPCs
    npc_perception_ensure_timer()
    return SS_INIT_SUCCESS

// Public entrypoint (contract): spawns 1 NPC per unfilled role
/proc/npc_spawn_roundstart()
	if(!npc_autospawn_enabled())
		return null
	var/list/summary = list()
	for(var/datum/job/J as anything in SSjob.joinable_occupations)
		var/missing = missing_spawn_slots(J)
		if(missing <= 0)
			continue
		for(var/i = 1, i <= missing, i++)
			var/mob/living/carbon/human/H = spawn_npc_for_job(J)
			if(H)
				summary[J.title] = (summary[J.title] || 0) + 1
			CHECK_TICK
	log_spawn_summary(summary)
	return summary

// Pick the spawn turf for the job, falling back to nearest safe turf
/proc/choose_spawn_turf(datum/job/J)
	var/atom/loc_choice = J?.get_roundstart_spawn_point()
	var/turf/T = get_turf(loc_choice)
	if(!T || !is_turf_safe(T))
		T = nearest_safe_turf(T || pick(GLOB.start_landmarks_list) || locate(1,1,1))
	return T

// Create and equip a human to the given job, at a chosen turf
/proc/spawn_npc_for_job(datum/job/J)
	var/turf/T = choose_spawn_turf(J)
	if(!T)
		return null
	var/mob/living/carbon/human/H = new /mob/living/carbon/human(T)
	// Mind + role
	H.mind_initialize()
	if(H?.mind)
		H.mind.set_assigned_role(J)
	// Equip standard outfit/access
	SSjob.equip_rank(H, J, H.client)
	// Name via generators if unset (before manifest injection)
	if(!H.real_name)
		H.real_name = H.generate_random_mob_name()
		H.name = H.real_name
	// Mark as NPC crew
	H.npc_is_crew = TRUE
	// Ensure NPC appears on crew manifest
	GLOB.manifest.inject(H, null, H.client)
	// Count this NPC toward filled positions
	J.current_positions++

	// Start idle presence (US3)
	start_npc_idle(H, T)
	return H
