// Phase 4 — NPC Perception & Sensing: Core datums and NPC API stubs
// Foundational scaffolding: datums, blackboard, event hooks, Sense() cadence/budgeting

// -----------------------------
// Datums (in-memory structures)
// -----------------------------

/datum/perception_entry
    var/kind                  // e.g., "hazard", "actor", "object", "signal"
    var/id                    // identity key (ref or stable id)
    var/x
    var/y
    var/z
    var/last_seen             // world.time of last update
    var/confidence = 1.0      // 0..1 confidence (decays over time)
    var/list/tags             // optional labels (strings)

    New(kind, id, x, y, z, list/tags=null)
        src.kind = kind
        src.id = id
        src.x = x
        src.y = y
        src.z = z
        src.last_seen = world.time
        if(tags)
            src.tags = tags.Copy()
        else
            src.tags = list()
        ..()

/datum/speech_entry
    var/speaker_ref           // string REF() to avoid strong references
    var/text
    var/channel
    var/x
    var/y
    var/z
    var/at                    // world.time

    New(mob/speaker, text, channel)
        speaker_ref = REF(speaker)
        src.text = text
        src.channel = channel
        if(isturf(speaker.loc))
            var/turf/T = speaker.loc
            x = T.x; y = T.y; z = T.z
        at = world.time
        ..()

/datum/perception_blackboard
	var/list/entries          // list of /datum/perception_entry
	var/list/speech_queue     // list of /datum/speech_entry
	var/list/index            // id -> /datum/perception_entry
	var/list/kinds            // kind -> list of entries

	New()
		entries = list()
		speech_queue = list()
		index = list()
		kinds = list()
		..()

	proc/AddEntry(datum/perception_entry/E)
		if(!E) return
		entries += E
		if(!isnull(E.id))
			index[E.id] = E
		if(E.kind)
			var/list/b = kinds[E.kind]
			if(!islist(b))
				b = list()
				kinds[E.kind] = b
			b += E

	proc/Upsert(kind, id, x, y, z, list/tags=null)
		if(isnull(id)) return null
		var/datum/perception_entry/E = index[id]
		if(!E)
			E = new /datum/perception_entry(kind, id, x, y, z, tags)
			AddEntry(E)
		else
			E.kind = kind
			E.x = x; E.y = y; E.z = z
			if(tags)
				// merge tags (unique)
				if(!E.tags) E.tags = list()
				for(var/t in tags)
					if(!(t in E.tags)) E.tags += t
			E.last_seen = world.time
		return E

	proc/RemoveById(id)
		var/datum/perception_entry/E = index[id]
		if(E)
			index -= id
			entries -= E
			if(E.kind)
				var/list/b = kinds[E.kind]
				if(islist(b)) b -= E

	proc/AddSpeech(mob/speaker, text, channel)
		var/datum/speech_entry/S = new /datum/speech_entry(speaker, text, channel)
		speech_queue += S
		// Bound the queue length by config
		var/maxq = npc_speech_queue_max
		while(length(speech_queue) > maxq)
			// drop oldest
			speech_queue.Cut(1, 2)

	proc/Get(filter_or_null)
		// Simple passthrough for now; filter can be string kind only
		if(isnull(filter_or_null))
			return entries
		var/list/out = list()
		if(istext(filter_or_null))
			for(var/datum/perception_entry/E in entries)
				if(E.kind == filter_or_null)
					out += E
		else
			// unsupported filter type in foundational pass — return all
			out = entries.Copy()
		return out

	proc/Maintain()
		// Apply TTL expiry and confidence decay
		var/ttl_ds = max(1, npc_perception_ttl_seconds) * 10
		var/now = world.time
		var/list/to_remove = list()
		for(var/datum/perception_entry/E in entries)
			var/age = now - (E.last_seen || now)
			if(age < 0) age = 0
			if(age >= ttl_ds)
				to_remove += E
			else
				var/conf = 1.0 - (age / ttl_ds)
				if(conf < 0) conf = 0
				E.confidence = conf
				// Prune hazards that have decayed to zero confidence to avoid stale clutter
				if(E.kind == "hazard" && conf <= 0)
					to_remove += E
		if(length(to_remove))
			for(var/datum/perception_entry/R in to_remove)
				if(!isnull(R.id)) index -= R.id
				entries -= R

// -----------------------------
// NPC-facing API (stubs)
// -----------------------------

/mob/living
    var/datum/perception_blackboard/perception
    var/perception_tick_offset = null
    var/last_perception_sense_time = 0
    var/last_perception_sense_ms = 0
    var/list/_perception_invalidation_times // key: ref/turf -> world.time last marked
    var/list/_perception_hazard_prev // key: id -> 0/1
    var/list/perception_counters // assoc: processed, capped, throttled

/mob/living/proc/EnsurePerceptionBlackboard()
    if(!perception)
        perception = new /datum/perception_blackboard()
    if(!_perception_invalidation_times)
        _perception_invalidation_times = list()
    if(!_perception_hazard_prev)
        _perception_hazard_prev = list()
    if(!perception_counters)
        perception_counters = list("processed"=0, "capped"=0, "throttled"=0)

/mob/living/proc/Sense()
    if(!npc_perception_enabled)
        return FALSE

    EnsurePerceptionBlackboard()

    // Stagger cadence: only run when our offset aligns with world.time
    var/mob_tick_skip = npc_perception_tick_skip
    if(ai && istype(ai, /datum/ai_fsm))
        var/list/pol = ai.PolicyFor(ai.state)
        if(islist(pol) && isnum(pol["perception_tick_skip"]))
            mob_tick_skip = max(0, pol["perception_tick_skip"]) // US4 override
    if(isnull(perception_tick_offset))
        var/skip = max(0, mob_tick_skip)
        perception_tick_offset = (skip > 0) ? rand(0, skip) : 0
    var/period = (mob_tick_skip + 1)
    if(period > 1)
        if(((world.time + perception_tick_offset) % period) != 0)
            return FALSE

    // Measure runtime
    var/ds0 = world.timeofday

    // Budget placeholder (limit entities per cycle)
    var/max_entities = npc_perception_max_entities

    // Minimal hazard sensing (US1 T012/T013 foundation)
    var/turf/origin = get_turf(src)
    if(origin)
        var/r = max(1, npc_perception_range)
        var/processed = 0
        // Scan a Chebyshev diamond around the origin, same Z only
        for(var/dx = -r, dx <= r, dx++)
            for(var/dy = -r, dy <= r, dy++)
                if(max(abs(dx), abs(dy)) > r) continue
                var/turf/T = locate(origin.x + dx, origin.y + dy, origin.z)
                if(!T) continue
                var/id = "tile:[REF(T)]"
                var/is_harm = is_tile_harmful(T)
                var/prev = _perception_hazard_prev[id]
                if(is_harm)
                    // Upsert hazard entry
                    perception.Upsert("hazard", id, T.x, T.y, T.z, list("kind=hazard"))
                    _perception_hazard_prev[id] = 1
                    if(!prev)
                        // Newly harmful → notify pathfinder
                        MarkTileChanged(T)
                else
                    if(prev)
                        // No longer harmful → remove entry and notify
                        perception.RemoveById(id)
                        _perception_hazard_prev[id] = 0
                        MarkTileChanged(T)
                processed++
                if(processed >= max_entities)
                    break
            if(processed >= max_entities)
                break
        // Actors & Objects sensing within remaining budget
        var/ent_budget = max_entities - processed
        if(ent_budget > 0)
            var/added = 0
            for(var/atom/A as anything in orange(origin, r))
                if(isturf(A)) continue
                if(ismob(A))
                    var/mob/living/L = A
                    if(!istype(L, /mob/living)) continue
                    if(L == src) continue
                    var/turf/lt = get_turf(L)
                    if(!lt || lt.z != origin.z) continue
                    var/list/tags = list("actor")
                    var/role = null
                    if(L.mind && L.mind.assigned_role)
                        role = L.mind.assigned_role.title
                    if(istext(role) && length(role)) tags += "role=[role]"
                    var/id = "actor:[REF(L)]"
                    perception.Upsert("actor", id, lt.x, lt.y, lt.z, tags)
                    added++
                else if(isobj(A))
                    var/obj/O = A
                    var/turf/ot = get_turf(O)
                    if(!ot || ot.z != origin.z) continue
                    var/list/tags2 = list("object")
                    // Identify categories: machinery, door, connector
                    var/path_mach = text2path("/obj/machinery")
                    var/path_door = text2path("/obj/machinery/door")
                    var/path_airlock = text2path("/obj/machinery/door/airlock")
                    var/path_ladder = text2path("/obj/structure/ladder")
                    var/path_stairs = text2path("/obj/structure/stairs")
                    if(path_mach && istype(O, path_mach))
                        tags2 += "machinery"
                    if((path_door && istype(O, path_door)) || (path_airlock && istype(O, path_airlock)))
                        tags2 += "door"
                    if((path_ladder && istype(O, path_ladder)) || (path_stairs && istype(O, path_stairs)))
                        tags2 += "connector"
                        tags2 += "transit:z"
                    var/id2 = "obj:[REF(O)]"
                    perception.Upsert("object", id2, ot.x, ot.y, ot.z, tags2)
                    added++
                if(added >= ent_budget) break
            if(added >= ent_budget)
                perception_counters["capped"] += 1
            perception_counters["processed"] = processed + added

        // Memory maintenance: TTL & decay
        perception.Maintain()

    last_perception_sense_time = world.time
    // Compute elapsed ms
    var/ds1 = world.timeofday
    var/delta = ds1 - ds0
    if(delta < 0) delta += 864000 // midnight wrap
    last_perception_sense_ms = delta * 100
    // If real-time overlay is enabled, emit a compact line for admins
    if(npc_perception_overlay_enabled && npc_perception_overlay_realtime)
        var/list/pc = perception_counters
        if(!islist(pc)) pc = list("processed"=0, "capped"=0, "throttled"=0)
        var/p_proc = pc["processed"]
        var/p_cap = pc["capped"]
        var/p_thr = pc["throttled"]
        to_world_log("[ADMIN_VERB_CATEGORY]: [src] sense= [last_perception_sense_ms]ms proc=[p_proc] capped=[p_cap] thr=[p_thr]")
    return TRUE

/mob/living/proc/PerceptionHas(kind, within=0, include_unreachable=FALSE, across_z=null)
    EnsurePerceptionBlackboard()
    // Special case: speech checks pull from speech queue with hearing semantics
    if(istext(kind) && lowertext(kind) == "speech")
        return perception_has_speech(within, include_unreachable, across_z)
    var/list/es = perception.Get(kind)
    if(!length(es)) return FALSE
    var/turf/start = get_turf(src)
    if(!start) return FALSE
    var/allow_across = (across_z == TRUE) ? TRUE : ((across_z == FALSE) ? FALSE : npc_perception_across_z_default)
    // Filter same-Z if across-Z not allowed
    var/list/cands = list()
    for(var/datum/perception_entry/E in es)
        if(!allow_across && E.z != start.z) continue
        // Optional cheap LOS filter (default off)
        if(npc_perception_use_los && !perception_los_clear(src, start, locate(E.x, E.y, E.z))) continue
        cands += E
    if(!length(cands)) return FALSE
    // If no distance constraint
    if(!isnum(within) || within <= 0)
        if(include_unreachable) return TRUE
        // Require at least one reachable candidate
        for(var/datum/perception_entry/E2 in cands)
            var/steps = perception_path_steps_to(src, locate(E2.x, E2.y, E2.z))
            if(steps >= 0 && steps < DSLITE_INF)
                return TRUE
        return FALSE
    // Distance-limited: use path steps (reachable only)
    for(var/datum/perception_entry/E3 in cands)
        var/steps2 = perception_path_steps_to(src, locate(E3.x, E3.y, E3.z))
        if(steps2 >= 0 && steps2 <= within)
            return TRUE
    return FALSE

/mob/living/proc/Nearest(kind, list/tags=list(), within=0, include_unreachable=FALSE, across_z=null)
    EnsurePerceptionBlackboard()
    if(istext(kind) && lowertext(kind) == "speech")
        var/datum/perception_entry/Se = perception_nearest_speech(within, include_unreachable, across_z)
        return Se
    var/list/es = perception.Get(kind)
    if(!length(es)) return null
    // Tag filter first
    var/list/cands = list()
    for(var/datum/perception_entry/E in es)
        var/matches = TRUE
        if(tags && length(tags))
            for(var/t in tags)
                if(!(t in E.tags))
                    matches = FALSE
                    break
        if(matches) cands += E
    if(!length(cands)) return null
    var/turf/start = get_turf(src)
    if(!start) return null
    var/allow_across = (across_z == TRUE) ? TRUE : ((across_z == FALSE) ? FALSE : npc_perception_across_z_default)
    // Filter same-Z unless across-Z allowed
    var/list/cands2 = list()
    for(var/datum/perception_entry/E2 in cands)
        if(!allow_across && E2.z != start.z) continue
        if(npc_perception_use_los && !perception_los_clear(src, start, locate(E2.x, E2.y, E2.z))) continue
        cands2 += E2
    if(!length(cands2)) return null

    var/datum/perception_entry/best = null
    var/best_steps = DSLITE_INF
    var/datum/perception_entry/best_unreach = null
    var/best_manh = 1.0e9
    for(var/datum/perception_entry/E3 in cands2)
        var/turf/goal = locate(E3.x, E3.y, E3.z)
        var/steps = perception_path_steps_to(src, goal)
        if(steps >= 0 && steps < DSLITE_INF)
            if(steps < best_steps)
                best_steps = steps
                best = E3
        else if(include_unreachable)
            // Track nearest by Manhattan distance as a tiebreaker for unreachable
            var/md = abs(start.x - goal.x) + abs(start.y - goal.y) + (start.z == goal.z ? 0 : 1000)
            if(md < best_manh)
                best_manh = md
                best_unreach = E3
    var/datum/perception_entry/ret = best ? best : (include_unreachable ? best_unreach : null)
    if(!ret) return null
    if(isnum(within) && within > 0 && best)
        if(best_steps > within) return null
    return ret

/mob/living/proc/GetPercepts(filter_or_null)
    if(!perception) return list()
    return perception.Get(filter_or_null)

// -----------------------------
// Helpers: path steps and LOS
// -----------------------------

/proc/perception_path_steps_to(mob/M, turf/goal)
    if(!M || !goal) return -1
    var/turf/start = get_turf(M)
    if(!start) return -1
    if(start == goal) return 0
    // Guard: avoid spamming DSLITE when start or goal are not walkable for M
    if(!dslite_is_passable(start, M) || !dslite_is_passable(goal, M))
        return DSLITE_INF
    // Use synchronous facade request with a small pop budget
    var/list/opts = list("async"=FALSE, "max_sync_pops"=10)
    var/list/res = dslite_request_path(M, start, goal, opts)
    if(!islist(res)) return -1
    if(res["error"]) return -1
    if(res["unreachable"]) return DSLITE_INF
    if(res["queued"]) return -1
    var/list/wps = res["waypoints"]
    if(!islist(wps)) return -1
    return max(0, length(wps)-1)

/proc/perception_los_clear(mob/M, turf/from_turf, turf/to_turf)
    if(!from_turf || !to_turf) return FALSE
    if(from_turf == to_turf) return TRUE
    // Build access info consistent with graph checks
    var/list/access = null
    if (M && hascall(M, "get_access")) access = call(M, "get_access")()
    var/datum/can_pass_info/pass_info = new(M, access)
    var/turf/current = from_turf
    var/limit = 0
    while(current && current != to_turf && limit < 200)
        limit++
        var/dx = to_turf.x - current.x
        var/dy = to_turf.y - current.y
        var/step_dir = 0
        if(abs(dx) >= abs(dy))
            if(dx > 0) step_dir = EAST
            else if(dx < 0) step_dir = WEST
            else if(dy > 0) step_dir = NORTH
            else if(dy < 0) step_dir = SOUTH
        else
            if(dy > 0) step_dir = NORTH
            else if(dy < 0) step_dir = SOUTH
            else if(dx > 0) step_dir = EAST
            else if(dx < 0) step_dir = WEST
        var/turf/next = get_step(current, step_dir)
        if(!next) return FALSE
        if(current.LinkBlockedWithAccess(next, pass_info)) return FALSE
        if (dslite_link_blocked_by_plasticflaps(current, next, M)) return FALSE
        current = next
    return (current == to_turf)

// -----------------------------
// Scheduler: drive Sense() for NPCs
// -----------------------------

var/global/NPC_PERCEPTION_TIMER_ACTIVE = FALSE

/proc/npc_perception_ensure_timer()
    if(NPC_PERCEPTION_TIMER_ACTIVE) return
    NPC_PERCEPTION_TIMER_ACTIVE = TRUE
    addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(npc_perception_timer_tick)), 1)

/proc/npc_perception_timer_tick()
    set waitfor = FALSE
    // Skip if disabled
    if(!npc_perception_enabled)
        addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(npc_perception_timer_tick)), world.tick_lag)
        return
    // Iterate NPC crew only
    for(var/mob/living/M in world)
        if(!M.npc_is_crew) continue
        // Sense() has internal cadence/staggering and returns quickly if not scheduled this tick
        var/did_sense = M.Sense()
        // Phase 5 FSM evaluation: run only when Sense() ran this tick (align cadence)
        if(did_sense && hascall(M, "AI_FSM_Tick"))
            M.AI_FSM_Tick()
    // Re-schedule
    addtimer(CALLBACK(GLOBAL_PROC, GLOBAL_PROC_REF(npc_perception_timer_tick)), world.tick_lag)

// -----------------------------
// Speech helpers
// -----------------------------

/mob/living/proc/perception_has_speech(within=0, include_unreachable=FALSE, across_z=null)
    var/ttl_ds = max(1, npc_perception_ttl_seconds) * 10
    var/now = world.time
    var/turf/start = get_turf(src)
    if(!start) return FALSE
    var/allow_across = (across_z == TRUE) ? TRUE : ((across_z == FALSE) ? FALSE : npc_perception_across_z_default)
    var/r_base = (isnum(within) && within > 0) ? within : npc_hearing_local_radius
    var/r_delta = 0
    if(ai && istype(ai, /datum/ai_fsm))
        var/list/pol = ai.PolicyFor(ai.state)
        if(islist(pol) && isnum(pol["speech_hearing_radius"]))
            r_delta = pol["speech_hearing_radius"]
    var/r = max(0, r_base + r_delta)
    var/list/qs = perception.speech_queue
    if(!islist(qs) || !length(qs)) return FALSE
    for(var/datum/speech_entry/S in qs)
        var/age = now - (S.at || now)
        if(age < 0) age = 0
        if(age >= ttl_ds) continue
        if(!allow_across && S.z != start.z) continue
        var/turf/goal = locate(S.x, S.y, S.z)
        if(!goal) continue
        var/steps = perception_path_steps_to(src, goal)
        if(steps >= 0 && steps <= r) return TRUE
        if(include_unreachable && steps == DSLITE_INF)
            // fallback to manhattan within r for unreachable
            var/md = abs(start.x - goal.x) + abs(start.y - goal.y) + (start.z == goal.z ? 0 : 1000)
            if(md <= r) return TRUE
    return FALSE

/mob/living/proc/perception_nearest_speech(within=0, include_unreachable=FALSE, across_z=null)
    var/ttl_ds = max(1, npc_perception_ttl_seconds) * 10
    var/now = world.time
    var/turf/start = get_turf(src)
    if(!start) return null
    var/allow_across = (across_z == TRUE) ? TRUE : ((across_z == FALSE) ? FALSE : npc_perception_across_z_default)
    var/r = (isnum(within) && within > 0) ? within : npc_hearing_local_radius
    var/list/qs = perception.speech_queue
    if(!islist(qs) || !length(qs)) return null
    var/datum/perception_entry/best = null
    var/best_steps = DSLITE_INF
    var/datum/perception_entry/best_unreach = null
    var/best_manh = 1.0e9
    for(var/datum/speech_entry/S in qs)
        var/age = now - (S.at || now)
        if(age < 0) age = 0
        if(age >= ttl_ds) continue
        if(!allow_across && S.z != start.z) continue
        var/turf/goal = locate(S.x, S.y, S.z)
        if(!goal) continue
        var/steps = perception_path_steps_to(src, goal)
        if(steps >= 0 && steps <= r)
            if(steps < best_steps)
                best_steps = steps
                best = new /datum/perception_entry("speech", S.speaker_ref, goal.x, goal.y, goal.z, list("text=[S.text]", "channel=[S.channel]"))
        else if(include_unreachable && steps == DSLITE_INF)
            var/md = abs(start.x - goal.x) + abs(start.y - goal.y) + (start.z == goal.z ? 0 : 1000)
            if(md < best_manh)
                best_manh = md
                best_unreach = new /datum/perception_entry("speech", S.speaker_ref, goal.x, goal.y, goal.z, list("text=[S.text]", "channel=[S.channel]"))
    if(best)
        if(isnum(within) && within > 0 && best_steps > within) return null
        return best
    if(include_unreachable) return best_unreach
    return null

// -----------------------------
// Event hooks (skeleton)
// -----------------------------

/mob/living/proc/OnSay(mob/speaker, text, channel)
    if(!npc_perception_enabled) return
    EnsurePerceptionBlackboard()
    perception.AddSpeech(speaker, text, channel)

/mob/living/proc/OnAreaAlarm(area/A, kind, state)
    if(!npc_perception_enabled) return
    EnsurePerceptionBlackboard()
    // Record a signal entry (minimal info for now)
    var/turf/T = get_turf(src)
    var/aname = A ? A.name : "unknown"
    var/id = "area:[aname]:[kind]"
    var/datum/perception_entry/E = new /datum/perception_entry("signal", id, T ? T.x : x, T ? T.y : y, T ? T.z : z, list("state=[state]"))
    perception.AddEntry(E)

/mob/living/proc/OnAlertLevelChanged(level)
    if(!npc_perception_enabled) return
    EnsurePerceptionBlackboard()
    var/datum/perception_entry/E = new /datum/perception_entry("signal", "alert:[level]", x, y, z, list("alert=[level]"))
    perception.AddEntry(E)

// -----------------------------
// Hazard invalidation helper (integration point)
// -----------------------------

/mob/living/proc/MarkTileChanged(turf/T)
    if(!T) return
    EnsurePerceptionBlackboard()
    if(!_perception_invalidation_times)
        _perception_invalidation_times = list()
    var/key = REF(T)
    var/now = world.time
    var/last = _perception_invalidation_times[key]
    // Throttle: only mark same tile again if > 3 ticks elapsed (~300ms)
    if(isnum(last) && (now - last) < 3)
        // Throttled duplicate within ~300ms
        perception_counters["throttled"] += 1
        return
    _perception_invalidation_times[key] = now
    // Call into pathfinding integration (provided elsewhere in the repo)
    // dslite_mark_tile_changed(T) is expected to exist under modular_gurtg/pathfinding
    dslite_mark_tile_changed(T)
