extends RefCounted
## Bounded connected places in the same world. Travel changes the destination,
## never creates another world, actor, inventory or clock.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const STATE_FIELDS: Array = ["landmarks"]
const DESTINATIONS: Array[Vector2i] = [Vector2i(177, 190), Vector2i(309, 194), Vector2i(309, 306)]
const LABELS: Array[String] = ["居住谷地", "寒林", "旱砂地"]
var landmarks := PackedInt64Array()


func seed_examples(world: RefCounted) -> void:
	for region: int in 3:
		var tile: int = Terrain.index(DESTINATIONS[region])
		create_landmark(world, LABELS[region], tile)
		if region == 0:
			continue
		var chest: int = world.facilities.create_completed(world, "wood_chest", tile + 2, 0, -1)
		world.objects.add(chest, "meal", 20)
		for local: int in 6:
			var site: int = Terrain.index(DESTINATIONS[region] + Vector2i(4 + local * 2, 3 + local % 3))
			var resource: int = world.objects.create("resource", "wood", site)
			# Dry-region supply is already-cut timber, not a tree on sand.
			world.objects.records[resource]["vegetation_level"] = 0 if region == 2 else 3
			world.objects.transfer(world.source_objects[local], resource, "wood", 100)
			world.source_objects.append(resource)
			world.terrain.resources.append(site)
			var plant_tile: int = Terrain.index(DESTINATIONS[region] + Vector2i(4 + local * 2, -3))
			world.nature.create(world, "perennial_herb" if region == 1 else "desert_thorn", plant_tile, false, true)
		# Regional climate already comes from ambient_at(); no invisible test emitter.
	if world.actor_count >= 24:
		for offset: int in 4:
			var actor: int = world.actor_count - 4 - offset
			var slot: int = world.actor_slots[actor]
			var page: RefCounted = world.pages[slot / 256]
			world.release(actor)
			page.positions[slot % 256] = Vector2(312.5 + offset, 192.5)
			page.modes[slot % 256] = Units.Mode.REST
			page.due_ms[slot % 256] = 50 + offset * 50
			world.ensure_work_binding(actor)
			world.knowledge.forget_actor(actor)


func destination(region: int) -> int:
	return Terrain.index(DESTINATIONS[region]) if region >= 0 and region < DESTINATIONS.size() else -1


func create_landmark(world: RefCounted, definition: String, tile: int) -> int:
	var id: int = world.objects.create("landmark", definition, tile)
	landmarks.append(id)
	return id


func forget(id: int) -> void:
	var index: int = landmarks.find(id)
	if index >= 0: landmarks.remove_at(index)


func valid(world: RefCounted) -> bool:
	var seen: Dictionary = {}
	for id: int in landmarks:
		if seen.has(id) or world.objects.records.get(id, {}).get("kind", "") != "landmark" or int(world.objects.records[id].tile) < 0:
			return false
		seen[id] = true
	for id: int in world.objects.records:
		if world.objects.records[id].kind == "landmark" and not seen.has(id): return false
	return true
