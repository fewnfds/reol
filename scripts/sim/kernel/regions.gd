extends RefCounted
## Bounded connected places in the same world. Travel changes the destination,
## never creates another world, actor, inventory or clock.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const STATE_FIELDS: Array = ["landmarks"]
const DESTINATIONS: Array[Vector2i] = [Vector2i(177, 190), Vector2i(309, 194), Vector2i(309, 306)]
const LABELS: Array[String] = ["居住谷地", "寒林", "旱砂地"]
var landmarks := PackedInt64Array()


func initialize(world: RefCounted) -> void:
	for region: int in 3:
		var tile: int = Terrain.index(DESTINATIONS[region])
		var id: int = world.objects.create("landmark", LABELS[region], tile)
		landmarks.append(id)
		if region == 0:
			continue
		var chest: int = world.objects.create("chest", "wood_chest", tile + 2)
		world.depot_objects.append(chest)
		world.terrain.depots.append(tile + 2)
		world.objects.add(chest, "meal", 20)
		for local: int in 6:
			var site: int = Terrain.index(DESTINATIONS[region] + Vector2i(4 + local * 2, 3 + local % 3))
			var resource: int = world.objects.create("resource", "wood", site)
			world.objects.transfer(world.source_objects[local], resource, "wood", 100)
			world.source_objects.append(resource)
			world.terrain.resources.append(site)
			var plant_tile: int = Terrain.index(DESTINATIONS[region] + Vector2i(4 + local * 2, -3))
			world.nature.create(world, "perennial_herb" if region == 1 else "desert_thorn", plant_tile)
		var source: int = world.environment.add_source(tile + 5, 1 if region == 1 else 0, 12)
		world.terrain.source_cells.append(world.environment.source_cells[source])
		world.terrain.source_channels.append(world.environment.source_channels[source])
	if world.actor_count >= 24:
		for offset: int in 4:
			var actor: int = world.actor_count - 4 - offset
			var slot: int = world.actor_slots[actor]
			var page: RefCounted = world.pages[slot / 256]
			world.release(actor)
			page.positions[slot % 256] = Vector2(312.5 + offset, 192.5)
			page.modes[slot % 256] = Units.Mode.REST
			page.due_ms[slot % 256] = 50 + offset * 50
			world.objects.records[actor].known = {}


func destination(region: int) -> int:
	return Terrain.index(DESTINATIONS[region]) if region >= 0 and region < DESTINATIONS.size() else -1


func valid(world: RefCounted) -> bool:
	if landmarks.size() != DESTINATIONS.size():
		return false
	for id: int in landmarks:
		if world.objects.records.get(id, {}).get("kind", "") != "landmark":
			return false
	return true
