extends RefCounted
## Sparse owner-side choices, awakened by the existing body due/arrival queue.
## Personal clues are observations, not an alias of current global inventories.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
var decisions: int = 0
var observations: int = 0
var decision_usec: int = 0
var observe_usec: int = 0


func initialize(world: RefCounted) -> void:
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			var id: int = page.ids[row]
			world.objects.records[id]["known"] = {}
			if id != 1:
				page.modes[row] = Units.Mode.REST
				page.due_ms[row] = 50 + (id % 20) * 50
				world.objects.records[id]["autonomous"] = true
				if id % 20 == 2:
					world.objects.add(id, "grain", 4)
					world.objects.add(id, "water", 2)
					page.hunger[row] = 2800
				if id % 20 == 3:
					page.energy[row] = 2800


func observe(world: RefCounted, id: int, at: int) -> void:
	var started: int = Time.get_ticks_usec()
	var slot: int = world.actor_slots[id]
	var position: Vector2 = world.pages[slot / 256].positions[slot % 256]
	var person: Dictionary = world.objects.records[id]
	if not person.has("known"):
		person["known"] = {}
	var clues: Dictionary = person.known
	var nearby: Array[int] = world.objects.nearby(position, 24.0, false)
	for target: int in clues.keys():
		var tile: int = clues[target].tile
		if Terrain.center(tile).distance_squared_to(position) <= 24.0 * 24.0 and not nearby.has(target):
			clues.erase(target)
	for target: int in nearby:
		remember(world, id, target, at)
	person["observe_due"] = at + 5000
	observations += 1
	observe_usec += Time.get_ticks_usec() - started


func remember(world: RefCounted, id: int, target: int, at: int) -> void:
	var person: Dictionary = world.objects.records[id]
	if not person.has("known"):
		person["known"] = {}
	if not world.objects.records.has(target):
		person.known.erase(target)
		return
	var record: Dictionary = world.objects.records[target]
	var clue: Dictionary = person.known.get(target, {})
	var version: int = int(record.get("inventory_revision", 0))
	if clue.get("inventory_revision", -1) != version:
		clue["inventory"] = record.inventory.duplicate()
		clue["inventory_revision"] = version
	clue["kind"] = record.kind
	clue["definition"] = record.definition
	clue["tile"] = record.tile
	clue["seen_ms"] = at
	person.known[target] = clue


func think(world: RefCounted, id: int, at: int) -> void:
	var started: int = Time.get_ticks_usec()
	_think(world, id, at)
	decision_usec += Time.get_ticks_usec() - started


func _think(world: RefCounted, id: int, at: int) -> void:
	decisions += 1
	var person: Dictionary = world.objects.records[id]
	var slot: int = world.actor_slots[id]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if person.get("observe_due", 0) <= at:
		observe(world, id, at)
	var clues: Dictionary = person.known
	var chosen: int = 0
	var kind: String = ""
	var best: float = INF
	for target: int in clues:
		var clue: Dictionary = clues[target]
		var candidate: String = ""
		var priority: float = 0
		if page.hunger[row] < 4000 and int(clue.inventory.get("meal", 0)) > 0:
			candidate = "eat"
			priority = -10000
		elif page.energy[row] < 4000 and clue.definition in ["wood_bed", "long_bed"] and clue.kind != "blueprint":
			candidate = "rest"
			priority = -9000
		elif clue.kind == "blueprint":
			candidate = "construct"
			priority = -2000
		elif clue.definition == "cook_stove" and world.objects.amount(id, "grain") >= 2 and world.objects.amount(id, "water") >= 1:
			candidate = "cook"
			priority = -1500
		elif page.cargo[row] > 0 and clue.kind == "chest":
			candidate = "put"
			priority = -1000
		elif page.cargo[row] == 0 and clue.kind == "resource" and int(clue.inventory.get("wood", 0)) > 0:
			candidate = "harvest"
		if candidate.is_empty():
			continue
		var score: float = page.positions[row].distance_squared_to(Terrain.center(clue.tile)) + priority
		if candidate not in ["put", "eat"] and world.reservations.has(target) and page.positions[row].distance_squared_to(Terrain.center(clue.tile)) <= 24.0 * 24.0:
			continue
		if score < best:
			chosen = target
			best = score
			kind = candidate
	if chosen == 0:
		# No known useful site: take a short walk and observe at the destination.
		var point: Vector2i = Vector2i(page.positions[row]) + Vector2i(8 if (id + at / 1000) % 2 == 0 else -8, 5)
		point = point.clamp(Vector2i(1, 1), Vector2i(510, 510))
		page.move_to(row, world.terrain.nearest_open(Terrain.index(point)), Units.Mode.EXPLORE)
		return
	if not world.objects.records.has(chosen):
		page.move_to(row, world.terrain.nearest_open(clues[chosen].tile), Units.Mode.EXPLORE)
		return
	if kind == "harvest":
		var source: int = world.source_objects.find(chosen)
		if source >= 0:
			page.source_ids[row] = source
			page.move_to(row, clues[chosen].tile, Units.Mode.RESOURCE)
			return
	var reason: String
	if kind == "put":
		reason = world.begin_transfer(id, {"kind": "put", "target": chosen, "item": "wood", "amount": page.cargo[row]})
	else:
		reason = world.begin_interaction(id, {"kind": kind, "target": chosen})
	if reason == "accepted":
		world.actions[id]["autonomous"] = true
	else:
		after_action(world, id, at)


func after_action(world: RefCounted, id: int, at: int, target: int = 0) -> void:
	var slot: int = world.actor_slots[id]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if target > 0:
		remember(world, id, target, at)
	if world.objects.records[id].get("observe_due", 0) <= at:
		observe(world, id, at)
	page.modes[row] = Units.Mode.REST
	page.due_ms[row] = at + 500 + (id % 10) * 50
