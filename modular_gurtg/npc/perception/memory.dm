// gurtstation: NPC Perception memory datums — Phase 2 implementation
#include "config.dm"

// PerceptionMemory datum
/datum/perception_memory
    var/mob/owner
    var/danger_flag = FALSE
    var/last_update_ts = 0
    var/list/hazards = list()    // list of /datum/perceived_hazard
    var/list/actors = list()     // list of /datum/perceived_actor
    var/list/objects = list()    // list of /datum/perceived_object
    var/list/messages = list()   // list of /datum/heard_message
    var/list/_rl_timestamps = list() // for heard-message rate limiting
    // perf tracking (debug)
    var/_perf_last_ds = 0
    var/_perf_total_ds = 0
    var/_perf_samples = 0

    New(mob/N)
        ..()
        owner = N

    // Remove expired entries per TTL constants
    proc/prune_expired(now)
        // Hazards
        for (var/i = hazards.len, i >= 1, i--)
            var/datum/perceived_hazard/H = hazards[i]
            if (!H) { hazards.Cut(i, i+1); continue }
            if ((now - H.last_updated_ts) > TTL_HAZARD)
                hazards.Cut(i, i+1)

        // Actors
        for (var/j = actors.len, j >= 1, j--)
            var/datum/perceived_actor/A = actors[j]
            if (!A) { actors.Cut(j, j+1); continue }
            if ((now - A.last_seen_ts) > TTL_ACTOR)
                actors.Cut(j, j+1)

        // Objects
        for (var/k = objects.len, k >= 1, k--)
            var/datum/perceived_object/O = objects[k]
            if (!O) { objects.Cut(k, k+1); continue }
            if ((now - O.last_seen_ts) > TTL_OBJECT)
                objects.Cut(k, k+1)

        // Messages
        for (var/m = messages.len, m >= 1, m--)
            var/datum/heard_message/Msg = messages[m]
            if (!Msg) { messages.Cut(m, m+1); continue }
            if ((now - Msg.timestamp) > TTL_MESSAGE)
                messages.Cut(m, m+1)

    // Hazard: add or update by key
    proc/add_or_update_hazard(h_type, turf/T, severity, now)
        var/key = "[h_type]|[T ? T.z : 0]:[T ? T.x : 0]:[T ? T.y : 0]"
        var/datum/perceived_hazard/H = null
        for (var/datum/perceived_hazard/H2 in hazards)
            if (H2.key == key)
                H = H2; break
        if (!H)
            H = new
            H.hazard_type = "[h_type]"
            H.location = T
            H.first_seen_ts = now
            H.key = key
            hazards += H
        H.severity = severity
        H.last_updated_ts = now
        return H

    // Actor: add or update by ref
    proc/add_or_update_actor(mob/A, role, relation, distance, now)
        if (!A)
            return null
        var/refkey = "[ref(A)]"
        var/datum/perceived_actor/P = null
        for (var/datum/perceived_actor/P2 in actors)
            if (P2.actor_ref == refkey)
                P = P2; break
        if (!P)
            P = new
            P.actor_ref = refkey
            actors += P
        P.role = role
        P.relation = relation
        P.distance = distance
        P.last_seen_ts = now
        return P

    // Object: add or update by category+location
    proc/add_or_update_object(category, turf/T, status, now)
        var/key = "[category]|[T ? T.z : 0]:[T ? T.x : 0]:[T ? T.y : 0]"
        var/datum/perceived_object/O = null
        for (var/datum/perceived_object/O2 in objects)
            if (O2.key == key)
                O = O2; break
        if (!O)
            O = new
            O.category = "[category]"
            O.location = T
            O.key = key
            objects += O
        O.status = status
        O.last_seen_ts = now
        return O

    // Heard message: append (rate limiting handled by hearing handlers)
    proc/add_heard_message(msg_type, channel, source, turf/approx_loc, now)
        var/datum/heard_message/M = new
        M.msg_type = "[msg_type]"
        M.channel = channel
        M.source = source ? "[ref(source)]" : null
        M.approx_location = approx_loc
        M.timestamp = now
        messages += M
        // Keep only last 30 messages
        if (messages.len > 30)
            messages.Cut(1, messages.len - 30)
        return M

    // Rate limit helper: true if we can log a message at `now`
    proc/can_log_message(now)
        // Prune timestamps outside window
        var/cutoff = now - HEARD_RATE_WINDOW
        for (var/i = _rl_timestamps.len, i >= 1, i--)
            if (_rl_timestamps[i] < cutoff)
                _rl_timestamps.Cut(i, i+1)
        if (_rl_timestamps.len >= HEARD_RATE_MAX)
            return FALSE
        _rl_timestamps += now
        return TRUE

    // Build a lightweight snapshot for debug/introspection
    proc/snapshot()
        var/list/L = list()
        L["npcId"] = owner ? "[ref(owner)]" : null
        L["dangerFlag"] = danger_flag
        L["lastUpdateTs"] = last_update_ts
        if (NPC_PERCEPTION_DEBUG)
            L["perf"] = list(
                "lastDs" = _perf_last_ds,
                "avgDs" = _perf_samples ? round((_perf_total_ds * 1.0) / _perf_samples, 0.1) : 0,
                "samples" = _perf_samples
            )

        var/list/H = list()
        for (var/datum/perceived_hazard/h in hazards)
            H += list(list(
                "type" = h.hazard_type,
                "severity" = h.severity,
                "location" = h.location ? list("x"=h.location.x, "y"=h.location.y, "z"=h.location.z) : null,
                "firstSeenTs" = h.first_seen_ts,
                "lastUpdatedTs" = h.last_updated_ts
            ))
        L["hazards"] = H

        var/list/A = list()
        for (var/datum/perceived_actor/a in actors)
            A += list(list(
                "id" = a.actor_ref,
                "role" = a.role,
                "relation" = a.relation,
                "distance" = a.distance,
                "lastSeenTs" = a.last_seen_ts
            ))
        L["actors"] = A

        var/list/O = list()
        for (var/datum/perceived_object/o in objects)
            O += list(list(
                "category" = o.category,
                "status" = o.status,
                "location" = o.location ? list("x"=o.location.x, "y"=o.location.y, "z"=o.location.z) : null,
                "lastSeenTs" = o.last_seen_ts
            ))
        L["objects"] = O

        var/list/Ms = list()
        for (var/datum/heard_message/m in messages)
            Ms += list(list(
                "type" = m.msg_type,
                "channel" = m.channel,
                "source" = m.source,
                "approxLocation" = m.approx_location ? list("x"=m.approx_location.x, "y"=m.approx_location.y, "z"=m.approx_location.z) : null,
                "timestamp" = m.timestamp
            ))
        L["messages"] = Ms
        return L

    // Return last N heard messages (most recent first)
    proc/last_heard(n)
        var/list/out = list()
        var/start = max(1, messages.len - n + 1)
        for (var/i = start, i <= messages.len, i++)
            var/datum/heard_message/m = messages[i]
            out += m
        return out


// Hazard entry
/datum/perceived_hazard
    var/key
    var/hazard_type
    var/severity = 0
    var/turf/location
    var/first_seen_ts = 0
    var/last_updated_ts = 0

// Actor entry
/datum/perceived_actor
    var/actor_ref
    var/role
    var/relation
    var/distance = 0
    var/last_seen_ts = 0

// Object entry
/datum/perceived_object
    var/key
    var/category
    var/status
    var/turf/location
    var/last_seen_ts = 0

// Heard message entry
/datum/heard_message
    var/msg_type
    var/channel
    var/source
    var/turf/approx_location
    var/timestamp = 0
