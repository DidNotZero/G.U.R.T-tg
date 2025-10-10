// D* Lite Core (foundational implementation)

var/global/DSLITE_INF = 1.0e31
var/global/DSLITE_TIE_EPS = 1.0e-6

// Time helpers (deciseconds-based to ms)
proc/dslite_now_ds()
	return world.timeofday

proc/dslite_elapsed_ms(var/start_ds)
	var/now = world.timeofday
	var/delta = now - start_ds
	if (delta < 0)
		// Wrap around midnight: 24*60*60*10 deciseconds
		delta += 864000
	return delta * 100

// Construct a new planner state
proc/dslite_new_state()
	var/list/state = list(
		"g" = list(),
		"rhs" = list(),
		"queue" = list(),
		"km" = 0,
		"start" = null,
		"goal" = null,
		"last" = null
	)
	return state

// Helpers to get/set g/rhs
proc/dslite_get_g(var/list/state, node)
	var/list/g = state["g"]
	var/v = g[node]
	return (v == null) ? DSLITE_INF : v

proc/dslite_set_g(var/list/state, node, value)
	var/list/g = state["g"]
	g[node] = value

proc/dslite_get_rhs(var/list/state, node)
	var/list/rhs = state["rhs"]
	var/v = rhs[node]
	return (v == null) ? DSLITE_INF : v

proc/dslite_set_rhs(var/list/state, node, value)
	var/list/rhs = state["rhs"]
	rhs[node] = value

// Priority queue helpers (assoc: node -> key[list( k1, k2 )])
proc/dslite_pq_insert(var/list/state, node, var/list/key)
	var/list/q = state["queue"]
	q[node] = key

proc/dslite_pq_remove(var/list/state, node)
	var/list/q = state["queue"]
	q -= node

proc/dslite_key_lt(var/list/a, var/list/b)
	if (a[1] < b[1]) return TRUE
	if (a[1] > b[1]) return FALSE
	return a[2] < b[2]

proc/dslite_top_key(var/list/state)
	var/list/q = state["queue"]
	var/list/min_key = list(DSLITE_INF, DSLITE_INF)
	for (var/node in q)
		var/list/k = q[node]
		if (dslite_key_lt(k, min_key))
			min_key = k
	return min_key

proc/dslite_pq_pop_min(var/list/state)
	var/list/q = state["queue"]
	var/node_min = null
	var/list/min_key = null
	for (var/node in q)
		var/list/k = q[node]
		if (!min_key || dslite_key_lt(k, min_key))
			min_key = k
			node_min = node
	if (!node_min) return null
	q -= node_min
	return list(node_min, min_key)

// Heuristic and CalculateKey
proc/dslite_calculate_key(var/list/state, node)
	var/turf/s_start = state["start"]
	var/km = state["km"]
	var/min_gr = dslite_get_g(state, node)
	var/r = dslite_get_rhs(state, node)
	if (r < min_gr) min_gr = r
	var/h = dslite_heuristic(s_start, node)
	var/k1 = min_gr + h + km
	var/k2 = min_gr
	return list(k1, k2)

// Initialize state for start/goal
proc/dslite_initialize(var/list/state, turf/start, turf/goal)
	state["start"] = start
	state["goal"] = goal
	state["last"] = start
	state["km"] = 0
	// reset maps
	state["g"] = list()
	state["rhs"] = list()
	state["queue"] = list()
	state["neicache"] = list()
	// rhs(goal) = 0; insert goal
	dslite_set_rhs(state, goal, 0)
	var/list/k = dslite_calculate_key(state, goal)
	dslite_pq_insert(state, goal, k)

// UpdateVertex per D* Lite
proc/dslite_update_vertex(var/list/state, turf/s, mob/M, var/list/options)
	var/turf/goal = state["goal"]
	if (s != goal)
		var/list/neis = dslite_neighbors_cached(state, s, M)
		var/min_rhs = DSLITE_INF
		for (var/turf/n in neis)
			var/c = dslite_edge_cost(s, n, options, M)
			var/gn = dslite_get_g(state, n)
			var/t = c + gn
			if (t < min_rhs)
				min_rhs = t
		dslite_set_rhs(state, s, min_rhs)
	// Maintain queue
	var/list/q = state["queue"]
	if (q[s])
		dslite_pq_remove(state, s)
	var/gs = dslite_get_g(state, s)
	var/rss = dslite_get_rhs(state, s)
	if (gs != rss)
		var/list/k = dslite_calculate_key(state, s)
		dslite_pq_insert(state, s, k)

// ComputeShortestPath main loop
proc/dslite_compute_shortest_path(var/list/state, mob/M, var/list/options, var/budget)
	if (isnull(budget)) budget = 0
	var/turf/start = state["start"]
	var/pops = 0
	while (1)
		var/list/topk = dslite_top_key(state)
		var/list/startk = dslite_calculate_key(state, start)
		if (!dslite_key_lt(topk, startk) && (dslite_get_rhs(state, start) == dslite_get_g(state, start)))
			break
		var/list/pop = dslite_pq_pop_min(state)
		if (!pop) break
		pops++
		var/turf/u = pop[1]
		var/list/k_old = pop[2]
		var/list/k_new = dslite_calculate_key(state, u)
		if (dslite_key_lt(k_old, k_new))
			// key outdated, reinsert with new key
			dslite_pq_insert(state, u, k_new)
		else
			var/gu = dslite_get_g(state, u)
			var/ru = dslite_get_rhs(state, u)
			if (gu > ru)
				// improve g
				dslite_set_g(state, u, ru)
				for (var/turf/p in dslite_neighbors_cached(state, u, M))
					dslite_update_vertex(state, p, M, options)
			else
				dslite_set_g(state, u, DSLITE_INF)
				for (var/turf/p2 in dslite_neighbors_cached(state, u, M))
					dslite_update_vertex(state, p2, M, options)
				dslite_update_vertex(state, u, M, options)
		if (budget > 0 && pops >= budget)
			break
	// done if termination condition met
	var/list/topk2 = dslite_top_key(state)
	var/list/startk2 = dslite_calculate_key(state, start)
	var/done = (!dslite_key_lt(topk2, startk2) && (dslite_get_rhs(state, start) == dslite_get_g(state, start)))
	return done

// Update start position (km adjustment) for incremental replans
proc/dslite_update_start(var/list/state, turf/new_start)
	var/turf/last = state["last"]
	if (new_start && last)
		state["km"] += dslite_heuristic(last, new_start)
	state["start"] = new_start
	state["last"] = new_start

// Extract path by greedy successor selection using current g-values
proc/dslite_extract_path(var/list/state, turf/start, turf/goal, mob/M, var/list/options)
	if (dslite_get_g(state, start) >= DSLITE_INF && dslite_get_rhs(state, start) >= DSLITE_INF)
		return null
	var/list/path = list()
	path += start
	var/turf/current = start
	var/i = 0
	var/harmful_steps = 0
	var/lava_steps = 0
	var/list/step_connectors = list() // connector id per step into tile i>1
	while (current && current != goal && i < 10000)
		i++
		var/list/neis = dslite_neighbors_cached(state, current, M)
		var/turf/best = null
		var/best_cost = DSLITE_INF
		for (var/turf/n in neis)
			var/c = dslite_edge_cost(current, n, options, M) + dslite_get_g(state, n)
			if (c + DSLITE_TIE_EPS < best_cost)
				best_cost = c
				best = n
			else if (abs(c - best_cost) <= DSLITE_TIE_EPS)
				// Tie-breaker: prefer non-harmful over harmful, then non-lava over lava
				var/nh = is_tile_harmful(n)
				var/bh = best ? is_tile_harmful(best) : FALSE
				if (bh && !nh)
					best = n
					best_cost = c
				else if (bh == nh)
					var/nl = is_tile_lava(n)
					var/bl = best ? is_tile_lava(best) : FALSE
					if (bl && !nl)
						best = n
						best_cost = c
		if (!best || best_cost >= DSLITE_INF)
			return null
		// Metrics based on stepping into best
		if (is_tile_lava(best))
			lava_steps++
		else if (is_tile_harmful(best))
			harmful_steps++
		// Track connector usage
		var/cid = dslite_connector_id_for_step(current, best)
		step_connectors += cid
		path += best
		current = best
	// Save metrics into state for consumers
	var/list/metrics = state["metrics"]
	if (!islist(metrics)) metrics = list()
	metrics["harmful_steps"] = harmful_steps
	metrics["lava_steps"] = lava_steps
	// Unique set of used connectors
	var/list/used = list()
	for (var/i2 = 1 to length(step_connectors))
		var/id = step_connectors[i2]
		if (id)
			if (!(id in used)) used += id
	metrics["used_connectors"] = used
	state["metrics"] = metrics
	state["step_connectors"] = step_connectors
	return path
