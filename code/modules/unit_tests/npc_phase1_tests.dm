/// Unit tests for Phase 1 NPC helpers and public procs

/datum/unit_test/npc_phase1_config
	priority = TEST_DEFAULT

/datum/unit_test/npc_phase1_config/Run()
	// Accessors should exist and clamp correctly
	var/r = npc_idle_radius()
	TEST_ASSERT(r >= 1 && r <= 10, "npc_idle_radius() should clamp to [1,10]")
	// Enabled by default
	TEST_ASSERT(npc_autospawn_enabled() == TRUE, "npc_autospawn_enabled() should default TRUE")
	return UNIT_TEST_PASSED

/datum/unit_test/npc_phase1_utils
	priority = TEST_DEFAULT

/datum/unit_test/npc_phase1_utils/Run()
	// is_interior_area should be FALSE for space
	var/area/space/space_area = new
	TEST_ASSERT(is_interior_area(space_area) == FALSE, "Space is not interior")
	// role_is_unfilled() finite check
	var/datum/job/J = new /datum/job/assistant
	J.spawn_positions = 2
	J.current_positions = 1
	TEST_ASSERT(role_is_unfilled(J) == TRUE, "Unfilled when current < spawn and finite")
	J.spawn_positions = -1
	J.current_positions = 100
	TEST_ASSERT(role_is_unfilled(J) == FALSE, "Unlimited spawn positions do not count as unfilled")
	return UNIT_TEST_PASSED

/datum/unit_test/npc_phase1_public
	priority = TEST_DEFAULT

/datum/unit_test/npc_phase1_public/Run()
	// Ensure disabling returns null and does not crash
	var/was_enabled = npc_autospawn_enabled()
	CONFIG_SET(flag/npc_autospawn_enabled, FALSE)
	var/res = npc_spawn_roundstart()
	TEST_ASSERT(isnull(res), "npc_spawn_roundstart() should return null when disabled")
	// Restore
	CONFIG_SET(flag/npc_autospawn_enabled, was_enabled)
	return UNIT_TEST_PASSED
