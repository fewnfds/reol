extends RefCounted
## Optional developer load assembled through the same real objects and actions.
## No alternative simulation path and no repeated command injector.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")


static func mixed(world: RefCounted) -> void:
	if world.actor_count < 150:
		return
	for actor: int in range(1, 101):
		world.release(actor)
		var slot: int = world.actor_slots[actor]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		var team: int = int(actor > 50)
		var index: int = (actor - 1) % 50
		page.positions[row] = Vector2(265.5 + index % 10, 182.5 + index / 10 + team * 8)
		page.health[row] = 10000 # Explicit stress fixture, not normal HP balance.
		world.objects.records[actor]["base_stats"] = {"max_hp": 10000.0}
		world.Equipment.rebuild(world, actor)
		world.objects.records[actor].autonomous = false
		world.objects.records[actor]["side"] = team
		world.combat.begin(world, actor, "pursue", actor + 50 if actor <= 50 else actor - 50, Vector2(-1, -1), actor % 3 != 0)
	for index: int in 20:
		var actor: int = index + 101
		var slot: int = world.actor_slots[actor]
		world.release(actor)
		world.pages[slot / 256].positions[slot % 256] = Vector2(151.5 + index % 5 * 2, 190.5 + index / 5 * 3)
		world.objects.transfer(world.source_objects[0], actor, "wood", 10)
		world._sync_inventory(actor)
		var tile: int = Terrain.index(Vector2i(153 + index % 5 * 2, 190 + index / 5 * 3))
		var receipt: Dictionary = world.command({"kind": "construct", "actor": actor, "definition": "wood_wall", "tile": tile})
		if receipt.ok:
			world.objects.records[world.actions[actor].target].remaining_ms = 60000
			world.actions[actor]["autonomous"] = true
	for index: int in 4:
		var actor: int = 121 + index * 2
		var target: int = actor + 1
		for id: int in [actor, target]:
			world.release(id)
			var slot: int = world.actor_slots[id]
			world.pages[slot / 256].positions[slot % 256] = Vector2(155.5 + index * 2, 180.5 + int(id == target))
			world.pages[slot / 256].modes[slot % 256] = 4
			world.objects.records[id].autonomous = false
		world.objects.add(target, "breath_manual", 1)
		world.command({"kind": "trade", "actor": actor, "target": target})
	world.perception.update(world, world.elapsed_ms, true)


static func capacity(world: RefCounted) -> void:
	# capacity-v1: same mixed world and algorithms, explicitly durable starting
	# actors/supplies so the measured work cannot disappear through death/famine.
	mixed(world)
	for actor: int in world.actor_slots:
		var slot: int = world.actor_slots[actor]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		world.objects.records[actor]["base_stats"] = {"max_hp": 1000000.0}
		world.Equipment.rebuild(world, actor)
		page.health[row] = page.max_health[row]
		page.energy[row] = 1000000
		page.hunger[row] = 1000000
		if actor % 10 == 0:
			world.objects.add(actor, "iron_sword@2", 1)
			world.command({"kind": "equip", "actor": actor, "item": "iron_sword@2"})
		if actor % 10 == 1:
			world.objects.add(actor, "travel_boots", 1)
			world.command({"kind": "equip", "actor": actor, "item": "travel_boots"})
	var supply: int = maxi(1000, ceili(float(world.actor_count) * 2000 / world.source_objects.size()))
	for source: int in world.source_objects:
		world.objects.add(source, "wood", supply - world.objects.amount(source, "wood"))
	world.initial_material = world.objects.total("wood")
	for record: Dictionary in world.objects.records.values():
		if record.kind == "blueprint": record.remaining_ms = 1000000
