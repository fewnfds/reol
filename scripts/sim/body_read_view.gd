class_name SimBodyReadView
extends RefCounted
## A bounded calculation input, not another body owner. No live dictionaries,
## callbacks or world reference survive capture. Index order is the original
## region/actor contact tie order, independent of worker completion order.

var world_id: int
var at_ms: int
var ids := PackedStringArray()
var points := PackedVector2Array()
var levels := PackedInt32Array()


static func capture(world: RegionalSimulation) -> SimBodyReadView:
	var result := SimBodyReadView.new()
	result.world_id = world.get_instance_id()
	result.at_ms = world.elapsed_ms
	for region: String in world.regions:
		world.advance_region_to_world(region)
		var sim: VillageSimulation = world.regions[region]
		for id: String in sim.actor_ids():
			if not sim.actor_is_alive(id):
				continue
			var point: Vector2 = sim.rule_actor_position(id)
			result.ids.append(id)
			result.points.append(point)
			result.levels.append(world.map_data.get_elevation(TileGrid.world_to_cell(point)) if world.map_data != null else 0)
	return result
