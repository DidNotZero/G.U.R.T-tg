// Phase 1 NPC Autospawn – Minimal idle controller (stub for US3)


// Starts a simple interior-bound idle behavior around an anchor
/proc/start_npc_idle(mob/living/carbon/human/H, turf/anchor)
	set waitfor = FALSE
	if(!H || !anchor)
		return
	var/radius = npc_idle_radius()
	while(H && !QDELETED(H))
		var/target = pick_idle_target(anchor, radius)
		if(target)
			step_towards(H, target)
		sleep(2 SECONDS)

/proc/pick_idle_target(turf/anchor, radius)
	// Choose a random point within radius that is interior and safe
	for(var/i = 1, i <= 10, i++)
		var/dx = rand(-radius, radius)
		var/dy = rand(-radius, radius)
		var/turf/T = locate(max(1, anchor.x + dx), max(1, anchor.y + dy), anchor.z)
		if(is_turf_safe(T))
			return T
	return null
