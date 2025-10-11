// Cost Providers & Configuration

// Configurable penalties (safe defaults)
var/global/dslite_harm_penalty = 1000
var/global/dslite_lava_penalty = 10000
var/global/dslite_door_penalty_factor = 2
var/global/dslite_crowd_penalty_factor = 2
// Small epsilon used to tie-break in favor of fewer harmful steps
var/global/dslite_harm_step_epsilon = 0.001
// Base cost for taking a vertical connector (stairs/ladder)
var/global/dslite_connector_base_cost = 2
// Debug logging toggle (set to FALSE for production; enable only during diagnostics)
var/global/dslite_debug_logging = FALSE
// Default async behavior for requests
var/global/dslite_async_default = TRUE

// Return default options used by the facade when none are provided.
proc/dslite_default_options()
	return list(
		"avoid_harm" = TRUE,
		"avoid_lava" = TRUE,
		"harm_penalty" = dslite_harm_penalty,
		"lava_penalty" = dslite_lava_penalty,
		"door_penalty_factor" = dslite_door_penalty_factor,
		"crowd_penalty_factor" = dslite_crowd_penalty_factor,
		"crowd_threshold" = 2,
		"enforce_access" = TRUE,
		"async" = dslite_async_default,
		"max_sync_pops" = 100
	)

// Merge provided options onto defaults and validate
proc/dslite_merge_options(var/list/options)
	var/list/merged = dslite_default_options()
	if (islist(options))
		for (var/k in options)
			merged[k] = options[k]
	return dslite_validate_options(merged)

// Coerce, clamp, and ensure presence of supported option keys
proc/dslite_validate_options(var/list/opts)
	if (!islist(opts)) opts = dslite_default_options()
	// Booleans
	if (opts["avoid_harm"] == null) opts["avoid_harm"] = TRUE
	if (opts["avoid_lava"] == null) opts["avoid_lava"] = TRUE
	if (opts["enforce_access"] == null) opts["enforce_access"] = TRUE
	// Numbers with sane minimums
	if (!isnum(opts["harm_penalty"])) opts["harm_penalty"] = dslite_harm_penalty
	if (!isnum(opts["lava_penalty"])) opts["lava_penalty"] = dslite_lava_penalty
	if (!isnum(opts["door_penalty_factor"])) opts["door_penalty_factor"] = dslite_door_penalty_factor
	if (!isnum(opts["crowd_penalty_factor"])) opts["crowd_penalty_factor"] = dslite_crowd_penalty_factor
	if (!isnum(opts["crowd_threshold"])) opts["crowd_threshold"] = 2
	// Clamp
	if (opts["harm_penalty"] < 0) opts["harm_penalty"] = 0
	if (opts["lava_penalty"] < 0) opts["lava_penalty"] = 0
	if (opts["door_penalty_factor"] < 1) opts["door_penalty_factor"] = 1
	if (opts["crowd_penalty_factor"] < 1) opts["crowd_penalty_factor"] = 1
	if (opts["crowd_threshold"] < 0) opts["crowd_threshold"] = 0
	return opts

// Lava tile detection (best effort; refined by map specifics)
proc/is_tile_lava(turf/T)
	if (!T) return FALSE
	if (istype(T, /turf/open/lava)) return TRUE
	// Some codebases represent lava as a hotspot-only tile; treat heavy hotspot as lava via type path if available
	return FALSE

// Harmful atmos detection using turf air and thresholds
// Treats: active hotspot, space/vacuum, extreme pressure, extreme temperature as harmful
proc/is_tile_harmful(turf/T)
	if (!T) return FALSE
	// Fast path: fire hotspot present
	if (locate(/obj/effect/hotspot) in T) return TRUE
	// If the tile exposes an explicit hazardous/safe signal, honor it
	if (hascall(T, "is_hazardous_tile"))
		var/res = call(T, "is_hazardous_tile")()
		if (res) return TRUE
	if (hascall(T, "is_safe"))
		var/safe = call(T, "is_safe")()
		if (!safe) return TRUE
	// Space or no air mixture available → treat as harmful (vacuum/unsimulated)
	if (isspaceturf(T)) return TRUE
	var/datum/gas_mixture/environment = T.return_air()
	if (isnull(environment)) return TRUE
	// Pressure outside safe hazard thresholds
	var/pressure = environment.return_pressure()
	if (pressure < HAZARD_LOW_PRESSURE || pressure > HAZARD_HIGH_PRESSURE)
		return TRUE
	// Temperature well outside survivable band
	var/temp = environment.temperature
	if (temp <= BODYTEMP_COLD_WARNING_2 || temp >= BODYTEMP_HEAT_WARNING_2)
		return TRUE
	return FALSE

// Traversal cost for stepping INTO turf T
proc/tile_traversal_cost(turf/T, var/list/options)
	if (!options) options = dslite_default_options()
	var/c = 0
	if (options["avoid_lava"] && is_tile_lava(T))
		c += options["lava_penalty"]
	else if (is_tile_harmful(T))
		// Keep harmful tiles pathable with high cost when configured
		if (options["avoid_harm"]) c += options["harm_penalty"]
		// Always add tiny epsilon so equal-cost paths prefer fewer harmful steps
		c += dslite_harm_step_epsilon
	return c

// --- Transient cost multipliers (doors/crowds) ---

// Detect if stepping into T involves a door interaction
proc/dslite_tile_has_door(turf/T)
    if (!T) return FALSE
    for (var/obj/O in T)
        // Use text2path to avoid compile-time type path errors if paths don't exist
        var/p1 = text2path("/obj/machinery/door")
        if (p1 && istype(O, p1)) return TRUE
        var/p2 = text2path("/obj/machinery/door/airlock")
        if (p2 && istype(O, p2)) return TRUE
        if ("is_door" in O.vars)
            var/v = O.vars["is_door"]
            if (v) return TRUE
    return FALSE

// Compute multiplier for transient effects when stepping from->to

// Note: avoid reserved keywords like 'from'/'to' in arg names
proc/dslite_transient_multiplier(mob/M, turf/from_turf, turf/to_turf, var/list/options)
	if (!options) options = dslite_default_options()
	var/mult = 1.0
	// Doors: apply factor if a door is present
	var/dpf = options["door_penalty_factor"]
	if (isnum(dpf) && dpf > 1 && dslite_tile_has_door(to_turf))
		mult *= dpf
	// Crowds: count mobs on destination
	var/ct = 0
	for (var/mob/other in to_turf)
		if (other != M) ct++
	var/threshold = options["crowd_threshold"]
	var/cpf = options["crowd_penalty_factor"]
	if (!isnum(threshold)) threshold = 2
	if (!isnum(cpf)) cpf = dslite_crowd_penalty_factor
	if (ct >= threshold && cpf > 1)
		mult *= cpf
	return mult

// Extra penalty applied when traversing a connector
proc/dslite_step_connector_penalty(connector, var/list/options)
	// connector may be null; allow simple base penalty
	return dslite_connector_base_cost

// --- Global config API ---

proc/dslite_get_config()
	return list(
		"harm_penalty" = dslite_harm_penalty,
		"lava_penalty" = dslite_lava_penalty,
		"door_penalty_factor" = dslite_door_penalty_factor,
		"crowd_penalty_factor" = dslite_crowd_penalty_factor,
		"connector_base_cost" = dslite_connector_base_cost,
		"debug_logging" = dslite_debug_logging
	)

proc/dslite_set_config(var/list/cfg)
	if (!islist(cfg)) return FALSE
	if (isnum(cfg["harm_penalty"])) dslite_harm_penalty = max(0, cfg["harm_penalty"]) 
	if (isnum(cfg["lava_penalty"])) dslite_lava_penalty = max(0, cfg["lava_penalty"]) 
	if (isnum(cfg["door_penalty_factor"])) dslite_door_penalty_factor = max(1, cfg["door_penalty_factor"]) 
	if (isnum(cfg["crowd_penalty_factor"])) dslite_crowd_penalty_factor = max(1, cfg["crowd_penalty_factor"]) 
	if (isnum(cfg["connector_base_cost"])) dslite_connector_base_cost = max(0, cfg["connector_base_cost"]) 
	if (isnum(cfg["debug_logging"])) dslite_debug_logging = cfg["debug_logging"]
	return TRUE
