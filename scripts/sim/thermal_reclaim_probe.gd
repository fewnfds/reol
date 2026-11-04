class_name SimThermalReclaimProbe
extends RefCounted
## Explicit development inspection only. A complete scan is not a proof of
## future error or a permission to reclaim. No world state is copied or changed.
## max_work bounds logical record/patch visits, not CPU time; sorting is limited
## to already paid derived results. complete means the scan finished, while
## status may still be unknown for a pending source, backlog or custom boundary.


static func inspect(heat: SimLocalHeat, max_work: int = 4096) -> Dictionary:
	var work: Dictionary = {"used": 0, "limit": maxi(0, max_work)}
	if heat == null or heat.world == null:
		return _unknown("missing_world", work)
	var owner: RefCounted = heat.world
	if int(owner.get("elapsed_ms")) != heat.last_ms or heat._geometry_dirty:
		return _unknown("unsynchronized", work, heat.last_ms)
	# Arbitrary Callables can have side effects and do not promise a climate
	# envelope. Never invoke one from this read-only inspection.
	if heat._background_query.is_valid():
		return _unknown("custom_background", work, heat.last_ms)
	if not owner is RegionalSimulation:
		return _unknown("unsupported_authority", work, heat.last_ms)
	var world: RegionalSimulation = owner
	if world._content == null or world.weather == null or world.artifacts == null or heat.definitions.is_empty():
		return _unknown("missing_bound_domains", work, heat.last_ms)
	if world.local_heat != heat:
		return _unknown("detached_field", work, heat.last_ms)
	var climate: Dictionary = world._content.climate
	var weather: Dictionary = world.weather.definitions
	if not climate.get("regions") is Dictionary or climate.regions.is_empty() or not climate.get("fallback_region") is String or not climate.regions.has(climate.fallback_region) or not weather.get("regions") is Dictionary or not weather.get("phases") is Array or not climate.get("calendar") is Dictionary or not climate.calendar.get("seasons") is Array:
		return _unknown("invalid_bound_climate", work, heat.last_ms)
	if not _spend(work, climate.calendar.seasons.size()):
		return _unknown("work_budget_exhausted", work, heat.last_ms)
	if not SimWorldCalendar.valid_definitions(climate.calendar) or not SimWorldCalendar._integer(world.weather.epoch_ms, 0, SimWorldCalendar.MAX_TIMESTAMP) or weather.phases.is_empty():
		return _unknown("invalid_bound_climate", work, heat.last_ms)
	if not SimWorldCalendar._integer(heat.definitions.get("world_size"), 1, 100000) or not SimWorldCalendar._integer(heat.definitions.get("source_radius"), 0, 8) or not SimWorldCalendar._integer(heat.definitions.get("capacity_per_tenth"), 1, 1000000000) or not SimWorldCalendar._integer(heat.definitions.get("reference_tenths"), -10000, -10000):
		return _unknown("invalid_heat_definitions", work, heat.last_ms)
	var cycle: int = 0
	for phase: Variant in weather.phases:
		if not _spend(work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		if not phase is Dictionary or phase.get("kind") not in ["clear", "rain"] or not SimWorldCalendar._integer(phase.get("duration_ms"), SimWeather.MINUTE_MS, 86400000):
			return _unknown("invalid_bound_climate", work, heat.last_ms)
		var duration: int = int(phase.duration_ms)
		if duration % SimWeather.MINUTE_MS != 0 or cycle > SimWorldCalendar.MAX_TIMESTAMP - duration:
			return _unknown("invalid_bound_climate", work, heat.last_ms)
		cycle += duration

	var rows: Dictionary = {}
	var region_cache: Dictionary = {}
	for raw_key: Variant in heat.cells:
		if not _spend(work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		var row: Variant = heat.cells[raw_key]
		if not raw_key is String or not row is Dictionary or not heat._cell_array(row.get("cell")) or not row.get("energy") is int:
			return _unknown("invalid_cell", work, heat.last_ms)
		var point := Vector2i(int(row.cell[0]), int(row.cell[1]))
		if heat._key(point) != raw_key:
			return _unknown("invalid_cell", work, heat.last_ms)
		# Match the production region lookup while charging each examined region
		# and rejecting malformed local bounds before accessing them.
		var location: Dictionary = _region_at(climate, point, work)
		if not bool(location.get("ok", false)):
			return _unknown(str(location.get("reason", "invalid_bound_climate")), work, heat.last_ms)
		var region: String = str(location.region)
		if not region_cache.has(region):
			var computed: Dictionary = _region_context(climate, weather, world.weather.epoch_ms, region, heat.last_ms, work)
			if not bool(computed.get("ok", false)):
				return _unknown(str(computed.get("reason", "invalid_bound_climate")), work, heat.last_ms)
			region_cache[region] = computed
		var context: Dictionary = region_cache[region]
		var background_q: int = (int(context.temperature_tenths) - int(heat.definitions.reference_tenths)) * int(heat.definitions.capacity_per_tenth)
		rows[raw_key] = {"key": str(raw_key), "cell": [point.x, point.y], "q": int(row.energy),
			"background_q": background_q, "residual_q": int(row.energy) - background_q,
			"region": region, "background_envelope": context.envelope.duplicate(true),
			"frozen_flows": [], "enabled_devices": [], "receipt_refs": [],
			"switch_refs": [], "activation_refs": [], "legacy_ref": false, "sample_ref": false}

	for raw_flow: Variant in heat.flows:
		if not _spend(work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		if not raw_flow is Dictionary or not raw_flow.get("from") is String or not raw_flow.get("to") is String or not raw_flow.get("rate") is int:
			return _unknown("invalid_flow", work, heat.last_ms)
		var flow: Dictionary = {"from": str(raw_flow.from), "to": str(raw_flow.to), "rate": int(raw_flow.rate)}
		for endpoint: String in [flow.from, flow.to]:
			if endpoint.is_empty() or endpoint.begins_with(SimLocalHeat.DEVICE_PREFIX):
				continue
			if not rows.has(endpoint):
				return _unknown("invalid_flow_endpoint", work, heat.last_ms)
			rows[endpoint].frozen_flows.append(flow)

	for id: Variant in world.artifacts.objects:
		if not _spend(work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		var item: Variant = world.artifacts.objects[id]
		if not id is String or not item is Dictionary:
			return _unknown("invalid_artifact", work, heat.last_ms)
		var definition: Variant = world.artifacts.definitions.get("types", {}).get(item.get("definition"), {})
		if not definition is Dictionary or not definition.get("capabilities", []) is Array:
			return _unknown("invalid_artifact", work, heat.last_ms)
		if not definition.get("capabilities", []).has("thermal_exchange") or not bool(item.get("enabled", false)):
			continue
		var point: Vector2i = heat._device_cell(item)
		if not heat._valid_cell(point):
			return _unknown("invalid_device_location", work, heat.last_ms)
		if not _cover(rows, heat, point, "enabled_devices", str(id), work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)

	var pending: Array[Dictionary] = []
	for actor: Variant in world.artifacts.active:
		if not _spend(work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		var job: Variant = world.artifacts.active[actor]
		if not actor is String or not job is Dictionary:
			return _unknown("invalid_action", work, heat.last_ms)
		if job.get("verb") in ["warm", "enable", "disable"]:
			pending.append({"action": str(job.get("id", "")), "actor": str(actor),
				"object": str(job.get("object", "")), "verb": str(job.verb),
				"due_ms": int(job.get("due_ms", -1)), "target": "unknown"})

	for action: Variant in heat.receipts:
		if not _spend(work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		var receipt: Variant = heat.receipts[action]
		if not action is String or not receipt is Dictionary or not heat._cell_array(receipt.get("cell")):
			return _unknown("invalid_receipt", work, heat.last_ms)
		var point := Vector2i(int(receipt.cell[0]), int(receipt.cell[1]))
		if not _cover(rows, heat, point, "receipt_refs", str(action), work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)

	for action: Variant in heat.device_switches:
		if not _spend(work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		var change: Variant = heat.device_switches[action]
		if not action is String or not change is Dictionary or not heat._cell_array(change.get("cell")) or not change.get("enabled") is bool:
			return _unknown("invalid_switch", work, heat.last_ms)
		var point := Vector2i(int(change.cell[0]), int(change.cell[1]))
		if not _cover(rows, heat, point, "switch_refs", str(action), work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		if bool(change.enabled) and not _cover(rows, heat, point, "activation_refs", str(action), work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)

	if not heat.legacy_limits.is_empty():
		if not heat.legacy_limits.get("cells") is Array:
			return _unknown("invalid_legacy_bounds", work, heat.last_ms)
		for key: Variant in heat.legacy_limits.cells:
			if not _spend(work):
				return _unknown("work_budget_exhausted", work, heat.last_ms)
			if not key is String or not rows.has(key):
				return _unknown("invalid_legacy_reference", work, heat.last_ms)
			rows[key].legacy_ref = true
	for key: Variant in heat.last_sample_cells:
		if not _spend(work):
			return _unknown("work_budget_exhausted", work, heat.last_ms)
		if not key is String or not rows.has(key):
			return _unknown("invalid_sample_reference", work, heat.last_ms)
		rows[key].sample_ref = true

	# Everything sorted here was already bounded by the paid scans above. In
	# particular, no unbounded event history is sorted or copied before budget.
	# Reserve the two remaining passes over the bounded result rows as well.
	if not _spend(work, rows.size()) or not _spend(work, rows.size()):
		return _unknown("work_budget_exhausted", work, heat.last_ms)
	var ordered: Array[String] = []
	for key: String in rows:
		ordered.append(key)
	ordered.sort()
	pending.sort_custom(func(left: Dictionary, right: Dictionary) -> bool: return str(left.action) < str(right.action))
	var result_cells: Array[Dictionary] = []
	for key: String in ordered:
		var row: Dictionary = rows[key]
		for field: String in ["enabled_devices", "receipt_refs", "switch_refs", "activation_refs"]:
			row[field].sort()
		row.frozen_flows.sort_custom(func(left: Dictionary, right: Dictionary) -> bool:
			return str(left.from) < str(right.from) or (left.from == right.from and str(left.to) < str(right.to)))
		var blockers: Array[String] = ["lifecycle_unproved", "future_climate_unproved"]
		if absi(int(row.residual_q)) > int(heat.definitions.capacity_per_tenth) - 1:
			blockers.append("instant_residual")
		if not row.frozen_flows.is_empty():
			blockers.append("frozen_flow")
		if not row.enabled_devices.is_empty():
			blockers.append("enabled_device")
		if not pending.is_empty():
			blockers.append("pending_target_unknown")
		if not row.receipt_refs.is_empty():
			blockers.append("receipt_history")
		if not row.activation_refs.is_empty():
			blockers.append("switch_history")
		if bool(row.legacy_ref):
			blockers.append("legacy_reference")
		if bool(row.sample_ref):
			blockers.append("sample_reference")
		row["blockers"] = blockers
		row["can_reclaim"] = false
		result_cells.append(row)
	var unresolved: String = "pending_target_unknown" if not pending.is_empty() else ""
	if unresolved.is_empty() and world.target_ms > world.elapsed_ms:
		unresolved = "world_backlog"
	if unresolved.is_empty() and heat._background_boundary.is_valid():
		unresolved = "custom_background_boundary"
	return {"status": "complete" if unresolved.is_empty() else "unknown", "complete": true,
		"reason": unresolved, "at_ms": heat.last_ms, "work_used": int(work.used),
		"can_reclaim": false, "cells": result_cells, "pending": pending}


static func _region_at(climate: Dictionary, point: Vector2i, work: Dictionary) -> Dictionary:
	for id: Variant in climate.regions:
		if not _spend(work):
			return {"ok": false, "reason": "work_budget_exhausted"}
		var rule: Variant = climate.regions[id]
		if not id is String or not rule is Dictionary or not SimClimateRules._bounds(rule.get("bounds")):
			return {"ok": false, "reason": "invalid_bound_climate"}
		var bounds: Array = rule.bounds
		if Rect2i(int(bounds[0]), int(bounds[1]), int(bounds[2]), int(bounds[3])).has_point(point):
			return {"ok": true, "region": id}
	return {"ok": true, "region": climate.fallback_region}


static func _region_context(climate: Dictionary, weather: Dictionary, epoch: int, region: String, at_ms: int, work: Dictionary) -> Dictionary:
	if not climate.regions.has(region) or not weather.regions.has(region):
		return {"ok": false, "reason": "unknown_region"}
	var rule: Variant = climate.regions[region]
	var weather_region: Variant = weather.regions[region]
	if not rule is Dictionary or not rule.get("daily_curve") is Array or not rule.get("seasonal_curve") is Array or not rule.get("weather_offsets") is Dictionary or not weather_region is Dictionary:
		return {"ok": false, "reason": "invalid_bound_climate"}
	if not SimWorldCalendar._integer(rule.get("base_tenths"), -1000, 1000) or rule.weather_offsets.get("clear") != 0 or not SimWorldCalendar._integer(rule.weather_offsets.get("rain"), -500, 0) or not SimWorldCalendar._integer(weather_region.get("offset_ms"), 0, 86400000) or int(weather_region.offset_ms) % SimWeather.MINUTE_MS != 0:
		return {"ok": false, "reason": "invalid_bound_climate"}
	# Curve validation scans them once, the envelope once, and current
	# temperature once. Weather is read once by the envelope and twice by
	# kind_at. Reserve all of those visits before invoking the helpers.
	for values: Array in [rule.daily_curve, rule.daily_curve, rule.daily_curve, rule.seasonal_curve, rule.seasonal_curve, rule.seasonal_curve, weather.phases, weather.phases, weather.phases]:
		if not _spend(work, values.size()):
			return {"ok": false, "reason": "work_budget_exhausted"}
	if not SimClimateRules._curve(rule.daily_curve, SimWorldCalendar.DAY_MINUTES) or not SimClimateRules._curve(rule.seasonal_curve, SimWorldCalendar.days_per_year(climate.calendar)):
		return {"ok": false, "reason": "invalid_bound_climate"}
	var envelope: Dictionary = SimClimateRules.bound_region_envelope(rule, weather.phases)
	if not bool(envelope.get("supported", false)):
		return {"ok": false, "reason": "invalid_bound_climate"}
	var current: Dictionary = SimClimateRules.background_for_region(climate, weather, epoch, region, at_ms)
	if current.is_empty():
		return {"ok": false, "reason": "invalid_bound_climate"}
	return {"ok": true, "temperature_tenths": int(current.temperature_tenths), "envelope": envelope}


static func _cover(rows: Dictionary, heat: SimLocalHeat, center: Vector2i, field: String, id: String, work: Dictionary) -> bool:
	var radius: int = int(heat.definitions.source_radius)
	var size: int = int(heat.definitions.world_size)
	for y: int in range(maxi(0, center.y - radius), mini(size, center.y + radius + 1)):
		for x: int in range(maxi(0, center.x - radius), mini(size, center.x + radius + 1)):
			if not _spend(work):
				return false
			var key: String = heat._key(Vector2i(x, y))
			if rows.has(key):
				rows[key][field].append(id)
	return true


static func _spend(work: Dictionary, amount: int = 1) -> bool:
	if amount < 0 or amount > int(work.limit) - int(work.used):
		return false
	work.used = int(work.used) + amount
	return true


static func _unknown(reason: String, work: Dictionary, at_ms: int = -1) -> Dictionary:
	return {"status": "unknown", "complete": false, "reason": reason, "at_ms": at_ms,
		"work_used": int(work.used), "can_reclaim": false, "cells": [], "pending": []}
