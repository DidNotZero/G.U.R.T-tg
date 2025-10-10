// gurtstation: NPC Perception module — public API and config
#include "config.dm"

// Ensure a perception memory exists on the mob
/proc/get_perception_memory(mob/N, create = TRUE)
    if (!N)
        return null
    if (!N.npc_perception && create)
        N.npc_perception = new /datum/perception_memory(N)
    return N.npc_perception

// Public API: Sense — prune TTLs and invoke sensors
/proc/Sense(mob/N)
    if (!NPC_PERCEPTION_ENABLED)
        return
    var/datum/perception_memory/M = get_perception_memory(N, TRUE)
    if (!M)
        return
    var/now = world.time
    M.prune_expired(now)
    // Invoke sensors (currently stubs; implemented in later phases)
    sense_hazards(N)
    sense_actors(N)
    sense_objects(N)
    // For now, only set bookkeeping
    M.danger_flag = (length(M.hazards) > 0)
    M.last_update_ts = now
    if (NPC_PERCEPTION_DEBUG)
        // basic perf accounting in deciseconds
        var/ds = world.time - now
        if (ds < 0) ds = 0
        M._perf_total_ds += ds
        M._perf_samples += 1
        M._perf_last_ds = ds
    return

// Public API: Snapshot of current memory
/proc/PerceptionSnapshot(mob/N)
    var/datum/perception_memory/M = get_perception_memory(N, FALSE)
    if (!M)
        return null
    return M.snapshot()

// Public API: Recent heard messages (metadata only)
/proc/LastHeard(mob/N, n as num)
    if (!n)
        n = 5
    var/datum/perception_memory/M = get_perception_memory(N, FALSE)
    if (!M)
        return list()
    return M.last_heard(n)
