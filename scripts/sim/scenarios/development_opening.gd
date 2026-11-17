extends RefCounted
## Explicit developer fixtures for the original kernel, combat and capacity
## consumers. The normal settlement never runs this content assembler.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")

static func before_bodies(world: RefCounted) -> void:
	for id: int in world.actor_slots: world.objects.add(id, "potion", 3)
	for tile: int in world.terrain.resources:
		var id: int = world.objects.create("resource", "wood", tile)
		world.objects.add(id, "wood", 1000)
		world.source_objects.append(id)
	var initial_depots: PackedInt32Array = world.terrain.depots.duplicate()
	world.terrain.depots.clear()
	for tile: int in initial_depots:
		world.facilities.create_completed(world, "wood_chest", tile, 0, -1)
	for tile: int in world.terrain.structures:
		if world.terrain.enclosures[tile] != 0:
			world.facilities.create_completed(world, "wood_wall" if world.terrain.blocked[tile] != 0 else "wood_door", tile)
	for tile: int in world.terrain.flooring.size():
		if world.terrain.flooring[tile] != 0:
			world.facilities.create_completed(world, "wood_floor", tile)
	world.initial_material = world.objects.total("wood")
	var pile: int = world.objects.create("pile", "wood", Terrain.index(Vector2i(178, 186)))
	world.objects.transfer(world.source_objects[0], pile, "wood", 50)
	world.facilities.create_completed(world, "wood_chest", Terrain.index(Vector2i(176, 186)), 0, 100)

static func after_bodies(world: RefCounted) -> void:
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			var source: int = posmod(page.ids[row] * 37, world.terrain.resources.size())
			page.source_ids[row] = source
			if page.ids[row] == 1: continue
			page.targets[row] = Terrain.center(world.terrain.resources[source])
			page.modes[row] = Units.Mode.RESOURCE
	if world.actor_count < 1000:
		world.pages[0].positions[0] = Terrain.center(Terrain.index(Vector2i(177, 188)))
	world.facilities.seed_fixture(world, "long_bed", Terrain.index(Vector2i(176, 182)))
	var stove: int = world.facilities.seed_fixture(world, "cook_stove", Terrain.index(Vector2i(174, 185)))
	world.facilities.seed_fixture(world, "water_well", Terrain.index(Vector2i(168, 176)))
	world.objects.add(stove, "meal", 30)
	var supplies: int = world.objects.by_tile[Terrain.index(Vector2i(176, 186))][0]
	world.objects.add(supplies, "grain", 30)
	world.objects.add(supplies, "water", 30)
	# Temporary playable equipment samples; ordinary NPCs need no gear scan.
	for item: String in ["iron_sword", "iron_sword@2", "short_bow", "willow_staff", "cloth_robe", "travel_boots", "jade_charm@3"]:
		world.objects.add(1, item, 1)
	world.objects.equip(1, "iron_sword")
	world.Equipment.rebuild(world, 1)
	world.objects.add(supplies, "cloth_robe@2", 1)
	world.objects.add(supplies, "travel_boots@2", 1)
	world.flush_topology()
	for page: RefCounted in world.pages: page.potions.fill(3)
	world.livelihood.seed_examples(world)
	world.nature.seed_examples(world)
	world.society.seed_examples(world)
	world.regions.seed_examples(world)
	world.flush_topology()
	if world.actor_count >= 24:
		for actor: int in range(world.actor_count - 3, world.actor_count + 1):
			world.release(actor)
			var body_slot: int = world.actor_slots[actor]
			world.pages[body_slot / 256].modes[body_slot % 256] = Units.Mode.IDLE
			var slot: int = world.actor_slots[actor]
			var page: RefCounted = world.pages[slot / 256]
			page.positions[slot % 256] = Terrain.center(Terrain.index(Vector2i(177 + world.actor_count - actor, 168)))
			world.objects.records[actor]["side"] = 1
			world.objects.records[actor].autonomous = false
			world.objects.records[actor]["combatant"] = true
			world.objects.records[actor]["combat_style"] = "trained"
			var weapon: String = "short_bow" if actor % 2 == 0 else "iron_sword"
			world.objects.add(actor, weapon, 1)
			world.objects.equip(actor, weapon)
			world.Equipment.rebuild(world, actor)
