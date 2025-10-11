// Graph Adapter (same-level + vertical connectors)

// Return cardinal neighbors for a given turf (same Z only)
proc/dslite_neighbors(turf/T, mob/M)
	if (!T) return list()
	var/list/out = list()
	var/dirs = list(NORTH, SOUTH, EAST, WEST)
	// Build pass_info for proper link checks (windows, border blockers, doors)
	var/list/access = null
	if (M && hascall(M, "get_access")) access = call(M, "get_access")()
	var/datum/can_pass_info/pass_info = new(M, access)
	for (var/d in dirs)
		var/turf/N = get_step(T, d)
		if (!N) continue
		if (N.z != T.z) continue
		if (!dslite_is_passable(N, M)) continue
		if (T.LinkBlockedWithAccess(N, pass_info)) continue
		if (dslite_link_blocked_by_plasticflaps(T, N, M)) continue
		out += N
	// Vertical neighbors via connectors (stairs/ladders)
	for (var/turf/V in dslite_vertical_neighbors(T, M))
		out += V
	return out

// Cached neighbor lookup using planner state cache
proc/dslite_neighbors_cached(var/list/state, turf/T, mob/M)
	var/list/cache = state ? state["neicache"] : null
	if (!islist(cache)) return dslite_neighbors(T, M)
	var/list/cached = cache[T]
	if (islist(cached)) return cached
	var/list/neis = dslite_neighbors(T, M)
	cache[T] = neis
	return neis

// Passability check (basic). Doors/access refined later.
proc/dslite_is_passable(turf/T, mob/M)
	if (!isturf(T)) return FALSE
	// Hard terrain constraints
	if (is_space_or_openspace(T) || ischasm(T)) return FALSE
	// Dense turfs (walls, etc.) are not walkable
	if (T.density) return FALSE
	// Do NOT check dense contents here (doors, windows). These are handled by
	// link-level checks via LinkBlockedWithAccess so access/open-state is respected.
	return TRUE

// Edge traversal cost (base step + tile costs)
proc/dslite_edge_cost(turf/from_turf, turf/to_turf, var/list/options, mob/M)
	if (!from_turf || !to_turf) return DSLITE_INF
	// Base cost encourages fewer steps
	var/c = 1
	// Link blockers (windows/airlocks/railings) prevent traversal
	var/list/access = null
	if (M && hascall(M, "get_access")) access = call(M, "get_access")()
	var/datum/can_pass_info/pass_info = new(M, access)
	if (from_turf.LinkBlockedWithAccess(to_turf, pass_info)) return DSLITE_INF
	if (dslite_link_blocked_by_plasticflaps(from_turf, to_turf, M)) return DSLITE_INF
	// Add tile traversal penalties for destination tile
	c += tile_traversal_cost(to_turf, options)
	// Enforce access constraints if configured
	if (options && options["enforce_access"]) 
		if (!dslite_has_tile_access(to_turf, M)) return DSLITE_INF
	// Connector penalty when crossing z or known connector
	if (from_turf.z != to_turf.z)
		var/conn = dslite_find_connector_link(from_turf, to_turf)
		c += dslite_step_connector_penalty(conn, options)
	// Apply transient multipliers (doors/crowds)
	c *= dslite_transient_multiplier(M, from_turf, to_turf, options)
	return c

// Heuristic (Manhattan with z penalty)
proc/dslite_heuristic(turf/a, turf/b)
	if (!a || !b) return 0
	var/dx = (a.x > b.x) ? (a.x - b.x) : (b.x - a.x)
	var/dy = (a.y > b.y) ? (a.y - b.y) : (b.y - a.y)
	var/dz = (a.z > b.z) ? (a.z - b.z) : (b.z - a.z)
	// Moderate penalty for z difference approximating connector base cost
	return dx + dy + 10 * dz

// --- Vertical connector helpers ---

// Return list of reachable turfs via connectors at T for M
proc/dslite_vertical_neighbors(turf/T, mob/M)
    var/list/out = list()
    if (!T) return out
    // Ladders directly on this turf
    for (var/obj/structure/ladder/L in T)
        if (!dslite_has_connector_access(L, M)) continue
        // Upwards
        if (L.up)
            var/turf/U = get_turf(L.up)
            if (U && dslite_is_passable(U, M)) out += U
        // Downwards
        if (L.down)
            var/turf/D = get_turf(L.down)
            if (D && dslite_is_passable(D, M)) out += D
    // Stairs ascend from a stair tile to (dir|UP)
    for (var/obj/structure/stairs/S in T)
        if (!dslite_has_connector_access(S, M)) continue
        if (hascall(S, "isTerminator") && call(S, "isTerminator")())
            var/turf/U2 = get_step_multiz(T, (S.dir|UP))
            if (istype(U2) && dslite_is_passable(U2, M)) out += U2
    // Descend: from the current upper tile, consider candidate tiles below and below-adjacent
    var/list/dirs = list(0, NORTH, SOUTH, EAST, WEST)
    for (var/d in dirs)
        var/turf/C = get_step_multiz(T, (d|DOWN))
        if (!istype(C)) continue
        // Look for a stair on C that would ascend back to T
        for (var/obj/structure/stairs/SB in C)
            if (!dslite_has_connector_access(SB, M)) continue
            if (hascall(SB, "isTerminator") && !call(SB, "isTerminator")()) continue
            var/turf/up_target = get_step_multiz(C, (SB.dir|UP))
            if (up_target == T && dslite_is_passable(C, M))
                out += C
                break
    return out

// Collect connectors that include turf T as an endpoint
proc/dslite_collect_connectors_at(turf/T)
	var/list/accum = list()
	// Stairs
	if (!isnull(GLOB) && islist(GLOB.stairs))
		for (var/conn in GLOB.stairs)
			if (dslite_connector_includes_turf(conn, T)) accum += conn
	// Ladders
	if (!isnull(GLOB) && islist(GLOB.ladders))
		for (var/conn2 in GLOB.ladders)
			if (dslite_connector_includes_turf(conn2, T)) accum += conn2
	return accum

// Whether a connector includes a given turf among its endpoints
proc/dslite_connector_includes_turf(datum/conn, turf/T)
	var/list/eps = dslite_connector_endpoints(conn)
	if (!islist(eps)) return FALSE
	for (var/turf/E in eps)
		if (E == T) return TRUE
	return FALSE

// Return the other end turf for a connector given one end
proc/dslite_connector_other_end_turf(datum/conn, turf/T)
	var/list/eps = dslite_connector_endpoints(conn)
	if (!islist(eps) || length(eps) < 2) return null
	if (eps[1] == T) return eps[2]
	if (eps[2] == T) return eps[1]
	// If endpoint list contains more, try find index
	for (var/turf/E in eps)
		if (E == T)
			for (var/turf/E2 in eps)
				if (E2 != T) return E2
	return null

// Extract connector endpoints using common vars or procs
proc/dslite_connector_endpoints(datum/conn)
	if (isnull(conn)) return null
	var/list/eps = list()
	// Common patterns: top/bottom, A/B, up/down (use dynamic vars access)
	if ("top" in conn.vars)
		var/t = conn.vars["top"]
		if (istype(t, /turf)) eps += t
	if ("bottom" in conn.vars)
		var/b = conn.vars["bottom"]
		if (istype(b, /turf)) eps += b
	if (length(eps) >= 2) return eps
	var/list/tmp = list()
	if ("A" in conn.vars)
		var/a = conn.vars["A"]
		if (istype(a, /turf)) tmp += a
	if ("B" in conn.vars)
		var/b2 = conn.vars["B"]
		if (istype(b2, /turf)) tmp += b2
	if (length(tmp) >= 2) return tmp
	if (hascall(conn, "endpoints"))
		var/list/from_call = call(conn, "endpoints")()
		if (islist(from_call) && length(from_call) >= 2) return from_call
	if ("up" in conn.vars)
		var/u = conn.vars["up"]
		if (istype(u, /turf)) eps += u
	if ("down" in conn.vars)
		var/dw = conn.vars["down"]
		if (istype(dw, /turf)) eps += dw
	if (length(eps) >= 2) return eps
	return null

// Access check via mob.get_access() if connector declares requirements
proc/dslite_has_connector_access(datum/conn, mob/M)
	// No explicit requirements → allowed
	var/list/req = null
	if ("req_access" in conn.vars) req = conn.vars["req_access"]
	else if ("access" in conn.vars) req = conn.vars["access"]
	if (!islist(req) || length(req) == 0) return TRUE
	if (!M || !hascall(M, "get_access")) return TRUE
	var/list/have = call(M, "get_access")()
	if (!islist(have)) return TRUE
	// Require at least one overlap
	for (var/x in req)
		if (x in have) return TRUE
	return FALSE

// Find connector object that directly links from -> to
proc/dslite_find_connector_link(turf/from_turf, turf/to_turf)
    if (!from_turf || !to_turf) return null
    // Ladders on from_turf
    for (var/obj/structure/ladder/L in from_turf)
        if (L.up && get_turf(L.up) == to_turf) return L
        if (L.down && get_turf(L.down) == to_turf) return L
    // Stairs ascend from 'from_turf' to (dir|UP)
    for (var/obj/structure/stairs/S in from_turf)
        if (hascall(S, "isTerminator") && call(S, "isTerminator")())
            var/turf/U = get_step_multiz(from_turf, (S.dir|UP))
            if (U == to_turf) return S
    // Descend case: stepping from an upper tile to a stair base that would ascend back here
    for (var/obj/structure/stairs/SB in to_turf)
        if (hascall(SB, "isTerminator") && call(SB, "isTerminator")())
            var/turf/target = get_step_multiz(to_turf, (SB.dir|UP))
            if (target == from_turf) return SB
    return null

// Generate a connector id for telemetry
proc/dslite_connector_id(datum/conn, turf/from_turf, turf/to_turf)
	if (!conn)
		return "zlink@([from_turf.x],[from_turf.y],[from_turf.z])->([to_turf.x],[to_turf.y],[to_turf.z])"
	var/id = null
	if ("id" in conn.vars) id = conn.vars["id"]
	else if ("uid" in conn.vars) id = conn.vars["uid"]
	else if ("identifier" in conn.vars) id = conn.vars["identifier"]
	else if ("name" in conn.vars)
		var/nm = conn.vars["name"]
		if (istext(nm)) id = nm
	if (id)
		return "[id]@([from_turf.x],[from_turf.y],[from_turf.z])->([to_turf.x],[to_turf.y],[to_turf.z])"
	return "[conn.type]@([from_turf.x],[from_turf.y],[from_turf.z])->([to_turf.x],[to_turf.y],[to_turf.z])"

// Resolve a connector id for a step if any
proc/dslite_connector_id_for_step(turf/from_turf, turf/to_turf)
	var/conn = dslite_find_connector_link(from_turf, to_turf)
	if (conn)
		return dslite_connector_id(conn, from_turf, to_turf)
	if (from_turf && to_turf && from_turf.z != to_turf.z)
		return dslite_connector_id(null, from_turf, to_turf)
	return null

// --- General access checks for doors/areas ---

// true if mob M has required access for T (area/doors)
proc/dslite_has_tile_access(turf/T, mob/M)
	if (!M) return TRUE
	if (!hascall(M, "get_access")) return TRUE
	var/list/have = call(M, "get_access")()
	if (!islist(have)) return TRUE
	// Check area requirements
	var/area/A = T.loc
	if (istype(A))
		var/list/req_a = dslite_access_requirements_from(A)
		if (islist(req_a) && length(req_a) > 0)
			if (!dslite_access_overlap(have, req_a)) return FALSE
	// Check objects on tile (e.g., doors)
	for (var/obj/O in T)
		var/list/req_o = dslite_access_requirements_from(O)
		if (islist(req_o) && length(req_o) > 0)
			if (!dslite_access_overlap(have, req_o)) return FALSE
	return TRUE

// Extract an access requirement list from a datum if present
proc/dslite_access_requirements_from(datum/D)
	if (!D) return null
	var/list/candidates = list("req_access", "access", "access_list", "requires_access", "req_one_access")
	for (var/k in candidates)
		if (k in D.vars)
			var/v = D.vars[k]
			if (islist(v) && length(v) > 0) return v
	return null

// Any overlap between have and req lists
proc/dslite_access_overlap(var/list/have, var/list/req)
	if (!islist(have) || !islist(req)) return TRUE
	for (var/x in req)
		if (x in have) return TRUE
	return FALSE
// --- Special link blockers ---

// Airtight plastic flaps: treat as blocked for normal actors unless they explicitly can pass
proc/dslite_link_blocked_by_plasticflaps(turf/from_turf, turf/to_turf, mob/M)
	if (!to_turf) return FALSE
	for (var/obj/structure/plasticflaps/F in to_turf)
		// Only block anchored, resting-required flaps
		if (!F.anchored) continue
		if (F.require_resting == FALSE) continue
		// Actors with PASSFLAPS may pass
		if (M && (M.pass_flags & PASSFLAPS)) return FALSE
		// Otherwise block
		return TRUE
	return FALSE
