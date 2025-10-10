// gurtstation: NPC Perception hearing — US3
#include "config.dm"

// Local speech handler — logs for NPCs within HEARING_RADIUS (not LoS-blocked)
/proc/OnHeardLocal(mob/source, text, turf/loc)
    if (!NPC_PERCEPTION_ENABLED || !NPC_PERCEPTION_HEARING_ENABLED)
        return
    if (!loc)
        loc = get_turf(source)
    var/now = world.time
    for (var/mob/living/N in hearers(HEARING_RADIUS, loc))
        var/datum/perception_memory/M = get_perception_memory(N, TRUE)
        if (!M)
            continue
        if (!M.can_log_message(now))
            continue
        M.add_heard_message("local", null, source, loc, now)
    return

// Radio handler — called on radio dispatch; filtering to subscribers is wired in T025
/proc/OnHeardRadio(channel, text, mob/source)
    if (!NPC_PERCEPTION_ENABLED || !NPC_PERCEPTION_HEARING_ENABLED)
        return
    var/now = world.time
    // As a stub: log to the speaker only; registration will be per-recipient in T025
    if (source)
        var/datum/perception_memory/M = get_perception_memory(source, TRUE)
        if (M && M.can_log_message(now))
            M.add_heard_message("radio", channel, source, null, now)
    return

// Internal: hook for COMSIG_MOB_SAY to dispatch to local/radio listeners
/mob/living/proc/_npc_perception_on_mob_say(datum/source, list/args)
    SIGNAL_HANDLER
    if (!islist(args) || args.len < SPEECH_MODS)
        return
    var/message = args[SPEECH_MESSAGE]
    var/list/mods = args[SPEECH_MODS]
    var/channel = mods ? mods[RADIO_EXTENSION] : null
    if (channel || mods[MODE_HEADSET])
        // Treat as radio; channel may be null which we consider common
        OnHeardRadio(channel, message, src)
    else
        OnHeardLocal(src, message, get_turf(src))
    return

// Note: Radio messages are captured via COMSIG_MOB_SAY handler; no radio override here
