// SS Integration (foundational stubs)

var/global/list/DSLITE_PLANNERS = list()       // mob -> state
var/global/list/DSLITE_QUEUE = list()          // fair scheduling queue of mobs
var/global/DSLITE_TICK_BUDGET = 5              // actors per tick (placeholder)
var/global/DSLITE_POPS_BUDGET = 100            // queue pops per actor per tick
var/global/DSLITE_TIMER_ACTIVE = FALSE         // internal repeating timer flag

// Get or create per-actor planner state
proc/dslite_get_or_create_state(mob/M)
	var/list/state = DSLITE_PLANNERS[M]
	if (!islist(state))
		state = dslite_new_state()
		DSLITE_PLANNERS[M] = state
	return state

// Schedule planning for an actor (initial or replan)
proc/dslite_schedule(mob/M, turf/start, turf/goal, var/list/options)
	if (!M || !isturf(start) || !isturf(goal)) return FALSE
	var/list/state = dslite_get_or_create_state(M)
	dslite_initialize(state, start, goal)
	state["options"] = options ? options : dslite_default_options()
	state["start_time_ds"] = dslite_now_ds()
	var/already = (M in DSLITE_QUEUE)
	if (!already)
		DSLITE_QUEUE += M
	// Ensure background timer is running to advance planners
	dslite_ensure_timer()
	return TRUE

// Subsystem tick hook (to be invoked by SSpathfinder)
proc/dslite_ss_tick()
	var/processed = 0
	var/list/current_queue = DSLITE_QUEUE.Copy()
	for (var/mob/M in current_queue)
		if (processed >= DSLITE_TICK_BUDGET) break
		var/list/state = DSLITE_PLANNERS[M]
		if (!islist(state))
			DSLITE_QUEUE -= M
			continue
		var/list/options = state["options"]
		if (!islist(options)) options = dslite_default_options()
		var/done = dslite_compute_shortest_path(state, M, options, DSLITE_POPS_BUDGET)
		if (done)
			var/turf/start = state["start"]
			var/turf/goal = state["goal"]
			var/list/path = dslite_extract_path(state, start, goal, M, options)
			var/list/metrics = state["metrics"]
			if (!islist(metrics)) metrics = list()
			var/lat_ms = 0
			if (state["start_time_ds"])
				lat_ms = dslite_elapsed_ms(state["start_time_ds"])
			metrics["latency_ms"] = lat_ms
			// Serialize path to coords and total cost
			var/list/coords = list()
			var/total = 0
			var/prev = null
			var/list/step_connectors = state["step_connectors"]
			var/idx = 0
			if (islist(path))
				for (var/turf/T in path)
					idx++
					var/list/tref = list("x"=T.x, "y"=T.y, "z"=T.z)
					if (prev)
						total += dslite_edge_cost(prev, T, options, M)
						var/cid = null
						if (islist(step_connectors) && idx > 1)
							cid = step_connectors[idx-1]
						if (cid) tref["via_connector"] = cid
					prev = T
					coords += tref
				state["metrics"] = metrics
				state["last_result"] = islist(path) ? list("waypoints"=coords, "total_cost"=total, "metrics"=metrics) : list("unreachable"=TRUE)
				DSLITE_QUEUE -= M
				processed++
		else
			// Not finished; rotate M to end to avoid starvation
			DSLITE_QUEUE -= M
			DSLITE_QUEUE += M
				processed++
		return processed

// Internal repeating timer to drive planning without a dedicated SS hook
proc/dslite_ensure_timer()
	if (DSLITE_TIMER_ACTIVE) return
	DSLITE_TIMER_ACTIVE = TRUE
	addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(dslite_timer_tick)), 1)

proc/dslite_timer_tick()
	set waitfor = FALSE
	dslite_ss_tick()
	if (length(DSLITE_QUEUE) > 0)
		addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(dslite_timer_tick)), world.tick_lag)
	else
		DSLITE_TIMER_ACTIVE = FALSE

// --- Event-driven invalidation (US3) ---

// Mark cost/structure change at turf T: update that node and neighbors
proc/dslite_mark_tile_changed(turf/T)
	if (!T) return 0
	var/updated = 0
	for (var/mob/M in DSLITE_PLANNERS)
		var/list/state = DSLITE_PLANNERS[M]
		if (!islist(state)) continue
		var/list/options = state["options"]
		if (!islist(options)) options = dslite_default_options()
		// Update the affected tile and its neighbors in this planner's graph
			dslite_update_vertex(state, T, M, options)
		// Invalidate neighbor cache for this state
		state["neicache"] = list()
		for (var/turf/N in dslite_neighbors_cached(state, T, M))
			dslite_update_vertex(state, N, M, options)
		// Schedule replanning work
		if (!(M in DSLITE_QUEUE)) DSLITE_QUEUE += M
		updated++
	return updated

// Atmos or hotspot change at tile T
proc/dslite_on_atmos_change(turf/T)
	return dslite_mark_tile_changed(T)

// Connector change: endpoints altered or availability changed
proc/dslite_on_connector_change(conn)
	var/list/eps = dslite_connector_endpoints(conn)
	if (!islist(eps)) return 0
	var/n = 0
	for (var/turf/E in eps)
		n += dslite_mark_tile_changed(E)
	return n
