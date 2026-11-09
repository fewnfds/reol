class_name SimConflictSpace
extends RefCounted
## Projectiles use height/solid cover rather than a pedestrian path mask.

static func level(world: RefCounted, point: Vector2) -> int:
	return world.map_data.get_elevation(TileGrid.world_to_cell(point)) if world.map_data != null else 0


static func solid(world: RefCounted, cell: Vector2i, at_level: int, observed_structure: String = "") -> bool:
	if world.map_data != null:
		if not world.map_data.in_bounds(cell) or world.map_data.get_elevation(cell) > at_level or world.map_data.get_terrain(cell) == WorldMapData.TERRAIN_ROCK:
			return true
	if world.construction != null and world.construction.blocked(cell) and (observed_structure.is_empty() or world.construction.project_at(cell, "ground") != observed_structure):
		return true
	if world.plants != null and world.plants.blocked(cell):
		return true
	for sim: VillageSimulation in world.regions.values():
		if SimWorkplaces.blocked(sim.places, cell):
			return true
	return false


static func clear_segment(world: RefCounted, from: Vector2, to: Vector2, at_level: int, observed_structure: String = "") -> bool:
	var steps: int = maxi(1, ceili(from.distance_to(to) / float(world.conflicts.rules.cover_sample_px)))
	for index: int in range(steps + 1):
		if solid(world, TileGrid.world_to_cell(from.lerp(to, float(index) / steps)), at_level, observed_structure):
			return false
	return true


static func can_step(world: RefCounted, from: Vector2i, to: Vector2i) -> bool:
	if world.map_data != null and not world.map_data.terrain_can_step(from, to - from):
		return false
	if solid(world, to, world.map_data.get_elevation(to) if world.map_data != null else 0):
		return false
	if world.large_bodies != null and world.large_bodies.blocked(to):
		return false
	var delta: Vector2i = to - from
	if delta.x != 0 and delta.y != 0:
		var side_a := Vector2i(to.x, from.y)
		var side_b := Vector2i(from.x, to.y)
		if _blocked_step_cell(world, side_a) and _blocked_step_cell(world, side_b):
			return false
	return true


static func _blocked_step_cell(world: RefCounted, cell: Vector2i) -> bool:
	return solid(world, cell, world.map_data.get_elevation(cell) if world.map_data != null else 0) or (world.large_bodies != null and world.large_bodies.blocked(cell))


static func walking_path(world: RefCounted, from: Vector2i, to: Vector2i, radius: int = 24, budget: int = 4096) -> Array[Vector2i]:
	return SimGridNavigation.find_path(from, to, _stand.bind(world), _step.bind(world), radius, budget)


static func _stand(cell: Vector2i, world: RefCounted) -> bool:
	return not _blocked_step_cell(world, cell) and (world.map_data == null or world.map_data.terrain_is_walkable(cell))


static func _step(from: Vector2i, direction: Vector2i, world: RefCounted) -> bool:
	return can_step(world, from, from + direction)


static func in_fan(origin: Vector2, target: Vector2, facing: Vector2, reach: float, half_angle: float) -> bool:
	var delta: Vector2 = target - origin
	return delta.length() <= reach and (delta.is_zero_approx() or facing.dot(delta.normalized()) >= cos(deg_to_rad(half_angle)))


static func segment_distance(from: Vector2, to: Vector2, point: Vector2) -> float:
	return Geometry2D.get_closest_point_to_segment(point, from, to).distance_to(point)
