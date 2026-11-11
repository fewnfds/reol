class_name SimLocalLight
extends RefCounted
## Instantaneous relative light. Original objects, locations, heat slopes and
## structures remain authoritative. No photon stock, settlement or knowledge.

const MAX_SOURCES: int = 128
const MAX_CELLS: int = 441
const MAX_RELATIVE: int = 40000


static func _failure(reason: String) -> Dictionary:
	return {"supported": false, "reason": reason}


static func _sources(world: RegionalSimulation, simulation: bool = false) -> Dictionary:
	if world == null or world.map_data == null or world.construction == null or world.artifacts == null or world.environment_fields == null:
		return _failure("missing_world")
	if world.environment_fields.world != world or world.artifacts.world != world or world.construction.world != world:
		return _failure("invalid_world")
	if not simulation and world.elapsed_ms != world.target_ms:
		return _failure("pending_time")
	var output: Dictionary = world.environment_fields.device_emission_rates(world.elapsed_ms)
	if not bool(output.supported):
		return output
	var rates: Dictionary = output.rates
	var intrinsic_ids: Array[String] = world.artifacts.intrinsic_light_ids()
	if rates.size() + intrinsic_ids.size() > MAX_SOURCES:
		return _failure("source_budget")
	var rows: Array[Dictionary] = []
	for id: String in rates:
		if not world.artifacts.objects.has(id):
			return _failure("missing_source")
		var item: Dictionary = world.artifacts.objects[id]
		var rule: Dictionary = world.artifacts.definitions.types[item.definition]
		if not rule.has("lighting"):
			continue
		if not bool(item.enabled) or not world.artifacts.thermal_fixed_location(item) or int(item.stored_q) <= 0:
			return _failure("invalid_source")
		var location: Dictionary = SimEntityQuery.locate(world, {"kind": "artifact", "id": id})
		# A fixed place does not travel with its lazily settled inventory owner.
		# The active thermal port already validates this same immutable anchor;
		# never wake a far village merely to re-stamp a stationary coordinate.
		if not bool(location.ok) or not world.map_data.in_bounds(location.cell):
			return _failure("unsettled_location")
		var peak: int = SimLightPropagation.emission_peak(int(rule.lighting.peak_relative), int(rates[id]), int(rule.thermal.rate_q_per_ms))
		if peak > 0:
			rows.append({"cell": location.cell, "radius": int(rule.lighting.radius_cells), "peak": peak})
	for id: String in intrinsic_ids:
		if not world.artifacts.has_capability(id, "intrinsic_light"):
			return _failure("missing_source")
		var item: Dictionary = world.artifacts.objects[id]
		var location: Dictionary = SimEntityQuery.locate(world, {"kind": "artifact", "id": id})
		# A fixed place stays fixed while its village is lazily settled. A held
		# source must use the carrier's accepted present; never project old motion
		# or wake a region from a read-only illumination query.
		if not bool(location.ok) or not world.map_data.in_bounds(location.cell):
			return _failure("unsettled_location")
		var fixed: bool = world.regions[item.region].places.has(item.container) or str(item.container).begins_with("site:")
		if bool(location.stale) and not fixed and not simulation:
			return _failure("unsettled_location")
		var rule: Dictionary = world.artifacts.definitions.types[item.definition].lighting
		var factor: int = SimEnvironmentLayout.container_transmission(world, str(item.container), "light")
		rows.append({"cell": location.cell, "radius": int(rule.radius_cells), "peak": int(rule.peak_relative) * factor / 10000})
	return {"supported": true, "rows": rows}


static func local_patch(world: RegionalSimulation, cells: Array[Vector2i], simulation: bool = false) -> Dictionary:
	if cells.size() > MAX_CELLS:
		return _failure("cell_budget")
	var sources: Dictionary = _sources(world, simulation)
	if not bool(sources.supported):
		return sources
	for cell: Vector2i in cells:
		if not world.map_data.in_bounds(cell):
			return _failure("outside_map")
	# One synchronous bounded query. Only pure geometric projections are reused
	# within it; no field or source position survives into another world step.
	var blockers: Dictionary[Vector2i, int] = {}
	var permeability: Callable = func(cell: Vector2i) -> int:
		if not blockers.has(cell):
			var value: int = 10000
			if not world.map_data.in_bounds(cell) or world.map_data.get_terrain(cell) == WorldMapData.TERRAIN_ROCK:
				value = 0
			else:
				var id: String = world.construction.project_at(cell)
				if not id.is_empty() and world.construction.projects[id].state == "built":
					var row: Dictionary = world.construction.projects[id]
					var rule: Dictionary = world.construction.definitions.types[row.type]
					value = int(SimEnvironmentLayout.terms(rule).light)
				elif world.construction.blocks_light(cell):
					value = 0
			blockers[cell] = value
		return blockers[cell]
	var values: Dictionary[Vector2i, int] = {}
	# Identical instantaneous sources have the same *integer* contribution at
	# every target. Reuse that result, then multiply its rounded value, never
	# merge peaks before rounding. All original IDs/budgets were checked above.
	var grouped: Dictionary[Vector4i, int] = {}
	for source: Dictionary in sources.rows:
		var key := Vector4i(source.cell.x, source.cell.y, int(source.radius), int(source.peak))
		grouped[key] = grouped.get(key, 0) + 1
	for cell: Vector2i in cells:
		var relative: int = 0
		for source: Vector4i in grouped:
			var from := Vector2i(source.x, source.y)
			var distance: int = (cell - from).length_squared()
			if distance >= source.z * source.z:
				continue
			var factor: int = SimLightPropagation.transmission(from, cell, permeability)
			var contribution: int = (source.w * (source.z * source.z - distance) / (source.z * source.z)) * factor / 10000
			relative = mini(MAX_RELATIVE, relative + contribution * grouped[source])
			if relative == MAX_RELATIVE:
				break
		values[cell] = relative
	return {"supported": true, "at_ms": world.elapsed_ms, "relative_scale": SimLightPropagation.SCALE, "values": values}


static func at_cell(world: RegionalSimulation, cell: Vector2i) -> Dictionary:
	return _at_cell(world, cell, false)


static func at_simulation_cell(world: RegionalSimulation, cell: Vector2i) -> Dictionary:
	# An explicit committed simulation boundary may have retained future debt.
	# UI still refuses that debt. Neither path advances the clock or a source.
	if world.environment_fields.last_ms != world.elapsed_ms:
		return _failure("unsettled_environment")
	return _at_cell(world, cell, true)


static func _at_cell(world: RegionalSimulation, cell: Vector2i, simulation: bool) -> Dictionary:
	var cells: Array[Vector2i] = [cell]
	var patch: Dictionary = local_patch(world, cells, simulation)
	if not bool(patch.supported):
		return patch
	var natural: Dictionary = SimNaturalLight.at_cell(world, cell)
	if not bool(natural.supported):
		return natural
	@warning_ignore("integer_division")
	var artificial: int = int(patch.values[cell]) * int(natural.relative_scale) / SimLightPropagation.SCALE
	return {"supported": true, "at_ms": world.elapsed_ms, "natural": natural,
		"natural_relative": int(natural.local_relative), "artificial_relative": artificial,
		"total_relative": int(natural.local_relative) + artificial, "relative_scale": int(natural.relative_scale)}


static func description(light: Dictionary) -> String:
	if not bool(light.get("supported", false)):
		return "近旁的明暗眼下尚难分辨。"
	return "近旁暖光照亮了这里。" if int(light.artificial_relative) > 0 else ""
