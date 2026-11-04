class_name SimLocalLight
extends RefCounted
## Instantaneous relative light. Original objects, locations, heat slopes and
## structures remain authoritative. No photon stock, settlement or knowledge.

const MAX_SOURCES: int = 128
const MAX_CELLS: int = 441
const MAX_RELATIVE: int = 40000


static func _failure(reason: String) -> Dictionary:
	return {"supported": false, "reason": reason}


static func _sources(world: RegionalSimulation) -> Dictionary:
	if world == null or world.map_data == null or world.construction == null or world.artifacts == null or world.local_heat == null:
		return _failure("missing_world")
	if world.local_heat.world != world or world.artifacts.world != world or world.construction.world != world:
		return _failure("invalid_world")
	if world.elapsed_ms != world.target_ms:
		return _failure("pending_time")
	var output: Dictionary = world.local_heat.device_emission_rates(world.elapsed_ms)
	if not bool(output.supported):
		return output
	var rates: Dictionary = output.rates
	if rates.size() > MAX_SOURCES:
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
	return {"supported": true, "rows": rows}


static func local_patch(world: RegionalSimulation, cells: Array[Vector2i]) -> Dictionary:
	if cells.size() > MAX_CELLS:
		return _failure("cell_budget")
	var sources: Dictionary = _sources(world)
	if not bool(sources.supported):
		return sources
	for cell: Vector2i in cells:
		if not world.map_data.in_bounds(cell):
			return _failure("outside_map")
	# One synchronous bounded query. Only pure geometric projections are reused
	# within it; no field or source position survives into another world step.
	var blockers: Dictionary[Vector2i, bool] = {}
	var opaque: Callable = func(cell: Vector2i) -> bool:
		if not blockers.has(cell):
			blockers[cell] = not world.map_data.in_bounds(cell) or world.map_data.get_terrain(cell) == WorldMapData.TERRAIN_ROCK or world.construction.blocks_sight(cell)
		return blockers[cell]
	var values: Dictionary[Vector2i, int] = {}
	for cell: Vector2i in cells:
		var relative: int = 0
		for source: Dictionary in sources.rows:
			relative = mini(MAX_RELATIVE, relative + SimLightPropagation.contribution(source.cell, cell, int(source.radius), int(source.peak), opaque))
		values[cell] = relative
	return {"supported": true, "at_ms": world.elapsed_ms, "relative_scale": SimLightPropagation.SCALE, "values": values}


static func at_cell(world: RegionalSimulation, cell: Vector2i) -> Dictionary:
	var cells: Array[Vector2i] = [cell]
	var patch: Dictionary = local_patch(world, cells)
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
