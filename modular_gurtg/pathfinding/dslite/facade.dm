// Facade: Public API
// Contracts mapping:
//   - /planner/path     -> dslite_request_path(mob, start, goal, options)
//   - /planner/cancel   -> dslite_cancel(mob)
//   - /planner/metrics  -> dslite_metrics(mob)
//   - (internal)        -> dslite_replan(mob, current, goal?, options?)

// Request a path for an actor from start to goal.
// Returns {waypoints[], total_cost, metrics} on success.
// On invalid input: returns {error="invalid_input"}
// On non-walkable:  returns {error="non_walkable"}
// On unreachable:   returns {unreachable=TRUE}
proc/dslite_request_path(mob/M, turf/start, turf/goal, var/list/options)
	if (!options) options = dslite_default_options()
	options = dslite_merge_options(options)
	var/async = options["async"]
	if (!M || !isturf(start) || !isturf(goal))
		world.log << "DSLITE: invalid_input: M=[M] start=[start] goal=[goal]"
		return list("error"="invalid_input")
	if (!dslite_is_passable(start, M) || !dslite_is_passable(goal, M))
		world.log << "DSLITE: non_walkable: start or goal blocked"
		return list("error"="non_walkable")

	var/ah = options["avoid_harm"]
	var/al = options["avoid_lava"]
	if (dslite_debug_logging)
		world.log << "DSLITE: request: [M] ([start.x],[start.y],[start.z]) -> ([goal.x],[goal.y],[goal.z]) opts: avoid_harm=[ah] avoid_lava=[al]"
	if (async)
		// Queue and return immediately
		if (dslite_schedule(M, start, goal, options))
			return list("queued"=TRUE)
		else
			return list("error"="invalid_input")

	var/ds0 = dslite_now_ds()
	var/list/state = dslite_new_state()
	dslite_initialize(state, start, goal)
	// Synchronous compute with a pop budget to avoid long stalls
	var/max_sync = isnum(options["max_sync_pops"]) ? options["max_sync_pops"] : 100
	dslite_compute_shortest_path(state, M, options, max_sync)
	var/done_now = (dslite_get_rhs(state, start) == dslite_get_g(state, start))
	var/list/path = dslite_extract_path(state, start, goal, M, options)
	if (!path)
		if (dslite_debug_logging) world.log << "DSLITE: unreachable"
		return list("unreachable"=TRUE)
	// If not done within budget, schedule the remainder and return queued
	if (!done_now)
		// Persist partial state and queue
		if (islist(DSLITE_PLANNERS))
			state["options"] = options
			DSLITE_PLANNERS[M] = state
		// schedule from current state start/goal
		if (!(M in DSLITE_QUEUE)) DSLITE_QUEUE += M
		return list("queued"=TRUE)

	// Compute total cost over path edges and convert waypoints to coords
	var/total = 0
	var/list/coords = list()
	var/prev = null
	var/list/step_connectors = state["step_connectors"]
	var/idx = 0
	for (var/turf/T in path)
		idx++
		var/list/tref = list("x"=T.x, "y"=T.y, "z"=T.z)
		if (prev)
			total += dslite_edge_cost(prev, T, options, M)
			var/cid = null
			if (islist(step_connectors) && idx > 1)
				cid = step_connectors[idx-1]
			if (cid)
				tref["via_connector"] = cid
		prev = T
		coords += tref

	// Merge metrics from state and ensure required fields
	var/list/metrics = state["metrics"]
	if (!islist(metrics)) metrics = list()
	if (metrics["latency_ms"] == null) metrics["latency_ms"] = dslite_elapsed_ms(ds0)

	// Store per-actor state for integration layer use
	if (islist(DSLITE_PLANNERS))
		state["options"] = options
		DSLITE_PLANNERS[M] = state

	var/hs = metrics["harmful_steps"]
	var/ls = metrics["lava_steps"]
	if (dslite_debug_logging)
		world.log << "DSLITE: success: steps=[length(coords)] total_cost=[round(total,0.001)] harm_steps=[hs] lava_steps=[ls]"

	return list("waypoints"=coords, "total_cost"=total, "metrics"=metrics)

// Cancel a pending or active plan for an actor.
proc/dslite_cancel(mob/M)
	if (!M) return FALSE
	var/cleared = FALSE
	if (islist(DSLITE_PLANNERS) && DSLITE_PLANNERS[M])
		DSLITE_PLANNERS -= M
		cleared = TRUE
	if (islist(DSLITE_QUEUE) && (M in DSLITE_QUEUE))
		DSLITE_QUEUE -= M
		cleared = TRUE
	return cleared

// Get latest metrics for an actor's planner instance.
proc/dslite_metrics(mob/M)
	if (!M) return null
	var/list/state = null
	if (islist(DSLITE_PLANNERS)) state = DSLITE_PLANNERS[M]
	if (!islist(state)) return null
	return state["metrics"]

// Replan using existing planner state (US3)
// Inputs:
//   M: actor, current: new start; goal optional (defaults to existing goal)
//   options optional: overrides; otherwise use state options
// Returns same shape as dslite_request_path

proc/dslite_replan(mob/M, turf/current, turf/goal, var/list/options)
	if (!M || !isturf(current))
		world.log << "DSLITE: replan invalid_input"
		return list("error"="invalid_input")
	var/list/state = islist(DSLITE_PLANNERS) ? DSLITE_PLANNERS[M] : null
	if (!islist(state))
		// No existing state: fall back to fresh request
		return dslite_request_path(M, current, goal, options)
	if (!isturf(goal)) goal = state["goal"]
	if (!isturf(goal))
		world.log << "DSLITE: replan missing goal"
		return list("error"="invalid_input")
	var/list/opt = options ? options : (islist(state["options"]) ? state["options"] : dslite_default_options())
	opt = dslite_merge_options(opt)
	var/async = opt["async"]
	// Update start and (if changed) reinitialize for new goal conservatively
	if (goal != state["goal"]) 
		// Simpler: reinitialize on goal change
		dslite_initialize(state, current, goal)
	else
		dslite_update_start(state, current)
	if (async)
		// Persist and queue
		state["options"] = opt
		if (!(M in DSLITE_QUEUE)) DSLITE_QUEUE += M
		return list("queued"=TRUE)
	// Compute and extract path synchronously under a budget
	var/ds0 = dslite_now_ds()
	var/max_sync = isnum(opt["max_sync_pops"]) ? opt["max_sync_pops"] : 100
	dslite_compute_shortest_path(state, M, opt, max_sync)
	var/list/path = dslite_extract_path(state, current, goal, M, opt)
	if (!path)
		if (dslite_debug_logging) world.log << "DSLITE: replan unreachable"
		return list("unreachable"=TRUE)
	var/total = 0
	var/list/coords = list()
	var/prev = null
	var/list/step_connectors = state["step_connectors"]
	var/idx = 0
	for (var/turf/T in path)
		idx++
		var/list/tref = list("x"=T.x, "y"=T.y, "z"=T.z)
		if (prev)
			total += dslite_edge_cost(prev, T, opt, M)
			var/cid = null
			if (islist(step_connectors) && idx > 1)
				cid = step_connectors[idx-1]
			if (cid) tref["via_connector"] = cid
		prev = T
		coords += tref
	var/list/metrics = state["metrics"]
	if (!islist(metrics)) metrics = list()
	if (metrics["latency_ms"] == null) metrics["latency_ms"] = dslite_elapsed_ms(ds0)
	// Persist state and options
	state["options"] = opt
	if (islist(DSLITE_PLANNERS)) DSLITE_PLANNERS[M] = state
	if (dslite_debug_logging)
		world.log << "DSLITE: replan success: steps=[length(coords)] total_cost=[round(total,0.001)]"
	return list("waypoints"=coords, "total_cost"=total, "metrics"=metrics)

// Return latest finished result for an actor if any
proc/dslite_latest_result(mob/M)
	if (!M) return null
	var/list/state = islist(DSLITE_PLANNERS) ? DSLITE_PLANNERS[M] : null
	if (!islist(state)) return null
	return state["last_result"]
