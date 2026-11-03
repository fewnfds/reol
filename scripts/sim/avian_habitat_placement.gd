class_name AvianHabitatPlacement
extends RefCounted
## New-world assembly only. Existing saved birds, sites and food remain authoritative.
## Natural potential chooses a safe landing place; it never supplies extra seed stock.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func assemble(scenario: Dictionary, centers: Dictionary, map_data: WorldMapData, flock_scenario: Dictionary = {}, landing_check: Callable = Callable()) -> Dictionary:
	var result: Dictionary = scenario.duplicate(true)
	if flock_scenario.is_empty():
		return result
	if map_data == null or scenario.get("version") != 1 or not scenario.get("regions") is Dictionary or flock_scenario.get("version") != 1 or not flock_scenario.get("regions") is Dictionary or not _placement_valid(flock_scenario.get("placement")):
		return {}
	var rules: Dictionary = flock_scenario.placement
	for region: Variant in flock_scenario.regions:
		var patch: Variant = flock_scenario.regions[region]
		if not region is String or not result.regions.has(region) or not result.regions[region] is Dictionary or not centers.get(region) is Vector2i or not patch is Dictionary or not patch.get("flock") is Array:
			return {}
		var section: Dictionary = result.regions[region]
		if not section.get("sites") is Dictionary or not section.sites.get("roost") is Dictionary or not Shape.cell_valid(section.sites.roost.get("offset"), true) or not section.get("flock", []) is Array:
			return {}
		var flock: Array = section.get("flock", []).duplicate(true)
		for bird: Variant in patch.flock:
			if not bird is Dictionary:
				return {}
			flock.append(bird.duplicate(true))
		section.flock = flock
		var center: Vector2i = centers[region]
		var roost: Vector2i = center + SimRouteTravel.cell(section.sites.roost.offset)
		var used: Dictionary = {roost: true}
		var ids: Array = section.sites.keys()
		ids.sort()
		for id: String in ids:
			var row: Variant = section.sites[id]
			if not row is Dictionary or row.get("type") != "seeds":
				continue
			if not Shape.cell_valid(row.get("offset"), true):
				return {}
			var selected: Vector2i = _seed_cell(center + SimRouteTravel.cell(row.offset), center, roost, used, map_data, rules, landing_check)
			if selected.x < 0:
				return {}
			var offset: Vector2i = selected - center
			row.offset = [offset.x, offset.y]
			used[selected] = true
	return result


static func _placement_valid(data: Variant) -> bool:
	if not Shape.keys(data, ["search_radius", "near_roost_cells", "minimum_center_distance", "seed_surfaces", "seed_flora"]):
		return false
	if not Shape.count(data.search_radius, 1, 32) or not Shape.count(data.near_roost_cells, 1, 32) or not Shape.count(data.minimum_center_distance, 0, 32):
		return false
	for field: String in ["seed_surfaces", "seed_flora"]:
		if not data[field] is Array or data[field].is_empty():
			return false
		for id: Variant in data[field]:
			if not SimInventory._nonempty(id):
				return false
	return true


static func _seed_cell(origin: Vector2i, center: Vector2i, roost: Vector2i, used: Dictionary, map_data: WorldMapData, rules: Dictionary, landing_check: Callable) -> Vector2i:
	var best := Vector2i(-1, -1)
	var best_rank: int = 3
	var best_distance: int = SimInventory.MAX_COUNT
	var radius: int = int(rules.search_radius)
	for y: int in range(origin.y - radius, origin.y + radius + 1):
		for x: int in range(origin.x - radius, origin.x + radius + 1):
			var cell := Vector2i(x, y)
			if used.has(cell) or not map_data.terrain_is_walkable(cell) or cell.distance_squared_to(roost) > int(rules.near_roost_cells) * int(rules.near_roost_cells) or cell.distance_squared_to(center) < int(rules.minimum_center_distance) * int(rules.minimum_center_distance):
				continue
			if landing_check.is_valid() and not bool(landing_check.call(cell)):
				continue
			var natural: Dictionary = map_data.natural_cell(cell)
			if natural.is_empty():
				continue
			var rank: int = 2
			if rules.seed_flora.has(natural.get("flora", {}).get("id", "")):
				rank = 0
			elif rules.seed_surfaces.has(map_data.natural_surface(cell)):
				rank = 1
			var distance: int = int(cell.distance_squared_to(origin))
			if rank < best_rank or rank == best_rank and distance < best_distance:
				best = cell
				best_rank = rank
				best_distance = distance
	return best
