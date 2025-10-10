// gurtstation: NPC Perception sensors — hazards (US1) and stubs for others
#include "config.dm"

// Hazard sensing — US1 implementation
/proc/sense_hazards(mob/N)
    if (!N)
        return
    var/datum/perception_memory/M = get_perception_memory(N, TRUE)
    if (!M)
        return
    var/now = world.time

    // Scan visible tiles using LoS radius
    for (var/atom/A in view(VISUAL_RADIUS, N))
        var/turf/T = get_turf(A)
        if (!T)
            continue

        // Fire hotspots
        var/obj/effect/hotspot/fire = locate(/obj/effect/hotspot) in T
        if (fire)
            var/sev = 100
            if (isnum(fire:temperature))
                // Normalize temperature relative to a warning threshold when available
                // BODYTEMP_HEAT_WARNING_1 is defined in atmos_mob_interaction.dm
                sev = clamp(round((fire:temperature - BODYTEMP_HEAT_WARNING_1) / 5), 10, 100)
            M.add_or_update_hazard("fire", T, sev, now)
            continue

        // Space/void exposure
        if (istype(T, /turf/open/space))
            M.add_or_update_hazard("void", T, 100, now)
            continue

        // Harmful gases (pressure/temperature extremes)
        var/datum/gas_mixture/environment = T.return_air()
        if (environment)
            var/pressure = environment.return_pressure()
            var/temp = environment.temperature
            var/severity = 0
            if (pressure > HAZARD_HIGH_PRESSURE)
                severity = max(severity, clamp(round(((pressure - HAZARD_HIGH_PRESSURE) / 10)), 10, 100))
            else if (pressure < HAZARD_LOW_PRESSURE)
                severity = max(severity, clamp(round(((HAZARD_LOW_PRESSURE - pressure) / 2)), 10, 100))

            if (temp >= BODYTEMP_HEAT_WARNING_1)
                severity = max(severity, clamp(round((temp - BODYTEMP_HEAT_WARNING_1) / 5), 10, 100))
            else if (temp <= BODYTEMP_COLD_WARNING_1)
                severity = max(severity, clamp(round((BODYTEMP_COLD_WARNING_1 - temp) / 5), 10, 100))

            if (severity >= 10)
                M.add_or_update_hazard("gas", T, severity, now)

    // Hostile critters (simplemobs) in sight
    for (var/mob/living/simple_animal/hostile/H in view(VISUAL_RADIUS, N))
        var/turf/ht = get_turf(H)
        if (ht)
            M.add_or_update_hazard("hostile", ht, 75, now)

    return

// Actor sensing — to be implemented in US2
/proc/sense_actors(mob/N)
    if (!N)
        return
    var/datum/perception_memory/M = get_perception_memory(N, TRUE)
    if (!M)
        return
    var/now = world.time
    var/turf/nt = get_turf(N)
    for (var/mob/living/A in view(VISUAL_RADIUS, N))
        if (A == N)
            continue
        var/role = A:job ? "[A:job]" : "unknown"
        var/relation = "unknown"
        var/dist = (nt && get_turf(A)) ? get_dist(nt, get_turf(A)) : 0
        M.add_or_update_actor(A, role, relation, dist, now)
    return

// Object sensing — to be implemented in US2
/proc/sense_objects(mob/N)
    if (!N)
        return
    var/datum/perception_memory/M = get_perception_memory(N, TRUE)
    if (!M)
        return
    var/now = world.time
    var/turf/nt = get_turf(N)
    var/list/candidates = list()

    for (var/atom/movable/A in view(VISUAL_RADIUS, N))
        var/turf/T = get_turf(A)
        if (!T)
            continue
        // Skip mobs (handled by sensors_actors)
        if (ismob(A))
            continue
        var/category = null
        var/status = null

        if (istype(A, /obj/item))
            category = "item"
            status = (A:anchored ? "fixed" : "pickable")
        else if (istype(A, /obj/machinery/computer))
            category = "console"
        else if (istype(A, /obj/machinery/door))
            category = "door"
            status = (A:density ? "closed" : "open")
        else if (istype(A, /obj/machinery))
            category = "machine"
        else
            continue

        var/dist = (nt && T) ? get_dist(nt, T) : 0
        candidates += list(list(
            "category" = category,
            "status" = status,
            "turf" = T,
            "dist" = dist
        ))

    // Sort by distance ascending
    if (candidates.len)
        candidates = sort_list(candidates, /proc/cmp_obj_candidate)

    // Keep top N
    var/limit = MAX_OBJECTS_PER_UPDATE
    var/count = min(limit, candidates.len)
    for (var/i = 1, i <= count, i++)
        var/list/c = candidates[i]
        M.add_or_update_object(c["category"], c["turf"], c["status"], now)
    return

// Helper compare for sorting candidates by distance
/proc/cmp_obj_candidate(a, b)
    if (!islist(a) || !islist(b))
        return 0
    var/da = a["dist"] || 0
    var/db = b["dist"] || 0
    return da - db
