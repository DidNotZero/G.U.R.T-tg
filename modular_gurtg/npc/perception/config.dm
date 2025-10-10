#ifndef NPC_PERCEPTION_CONFIG
#define NPC_PERCEPTION_CONFIG

// Visual/hearing radii
#define VISUAL_RADIUS 7
#define HEARING_RADIUS 7

// Work bounding
#define MAX_OBJECTS_PER_UPDATE 10

// Hearing rate limit
#define HEARD_RATE_MAX 3
#define HEARD_RATE_WINDOW (5 SECONDS)

// Memory TTLs (deciseconds via SECONDS macro)
#define TTL_HAZARD   (30 SECONDS)
#define TTL_ACTOR    (10 SECONDS)
#define TTL_OBJECT   (15 SECONDS)
#define TTL_MESSAGE  (60 SECONDS)

// Feature toggles
#define NPC_PERCEPTION_ENABLED 1
#define NPC_PERCEPTION_HEARING_ENABLED 1
#define NPC_PERCEPTION_DEBUG 0

// Per-NPC memory handle
/mob/var/datum/perception_memory/npc_perception

#endif // NPC_PERCEPTION_CONFIG

