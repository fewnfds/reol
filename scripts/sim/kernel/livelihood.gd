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
				world.objects.records[id]["autonomous"] = true
				world.adopt_work(id, 0)
				page.modes[row] = Units.Mode.REST
				page.due_ms[row] = 50 + (id % 20) * 50
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
	world.sight.sync(world)
	var sight_range: float = world.sight.range_for(world, id)
	var nearby: Array[int] = world.objects.nearby(position, sight_range, false)
	var visible: Array[int] = []
	for target: int in nearby:
		if world.sight.sees_object(position, world.objects.records[target], sight_range):
			visible.append(target)
	for target: int in clues.keys():
		var tile: int = clues[target].tile
		if world.sight.sees(position, tile, sight_range) and not visible.has(target):
			clues.erase(target)
	for target: int in visible:
		var rec: Dictionary = world.objects.records[target]
		if rec.kind == "plant" and rec.inventory.is_empty() and not clues.has(target):
			continue # No actionable clue yet; the next observation can find fruit.
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
	clue["capacity"] = record.capacity
	clue["stage"] = int(record.get("stage", -1))
	clue["seen_ms"] = at
	person.known[target] = clue


func think(world: RefCounted, id: int, at: int) -> void:
	world.decisions.wake(world, id, at, "life_ready")


func choose(world: RefCounted, id: int, at: int) -> void:
	var started: int = Time.get_ticks_usec()
	_think(world, id, at)
	decision_usec += Time.get_ticks_usec() - started


func _think(world: RefCounted, id: int, at: int) -> void:
	if world.decisions.in_combat(id) or not world.gate.check(world, id, at).is_empty(): return
	decisions += 1
	var person: Dictionary = world.objects.records[id]
	var slot: int = world.actor_slots[id]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if person.get("observe_due", 0) <= at:
		observe(world, id, at)
	var commitment: Dictionary = person.get("commitment", {})
	if not commitment.is_empty():
		var target: int = int(commitment.target)
		if at >= int(commitment.expires_ms) or world.objects.records.get(target, {}).get("kind", "") != "blueprint":
			person.erase("commitment")
			person.autonomous = commitment.get("was_autonomous", true)
			if not person.autonomous:
				page.modes[row] = Units.Mode.IDLE
				return
		elif page.hunger[row] >= 2500 and page.energy[row] >= 2000:
			if world.begin_interaction(id, {"kind": "construct", "target": target, "autonomous": true}) == "accepted":
				return
			after_action(world, id, at, target)
			return
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
		elif page.cargo[row] == 0 and clue.definition == "cook_stove" and world.objects.amount(id, "grain") >= 2 and world.objects.amount(id, "water") >= 1:
			candidate = "cook"
			priority = -1500
		elif page.cargo[row] > 0 and clue.kind == "chest":
			var occupied: int = 0
			for count: int in clue.inventory.values(): occupied += count
			if int(clue.get("capacity", -1)) >= 0 and occupied >= int(clue.capacity): continue
			candidate = "put"
			priority = -1000
		elif clue.kind == "plant" and int(clue.get("stage", -1)) == world.nature.Stage.MATURE and not clue.inventory.is_empty():
			candidate = "gather"
			priority = -700
		elif page.cargo[row] == 0 and clue.kind == "resource" and int(clue.inventory.get("wood", 0)) > 0:
			candidate = "harvest"
		if candidate.is_empty():
			continue
		if person.has("commitment") and candidate not in ["eat", "rest"]: continue
		var score: float = page.positions[row].distance_squared_to(Terrain.center(clue.tile)) + priority
		if candidate not in ["put", "eat"] and world.sight.sees(page.positions[row], clue.tile, world.sight.range_for(world, id)) and world.reservations.has(target):
			continue
		if score < best:
			chosen = target
			best = score
			kind = candidate
	if chosen == 0:
		if person.has("commitment"):
			after_action(world, id, at)
			return
		# No known useful site: take a short walk and observe at the destination.
		var point: Vector2i = Vector2i(page.positions[row]) + Vector2i(8 if (id + at / 1000) % 2 == 0 else -8, 5)
		point = point.clamp(Vector2i(1, 1), Vector2i(510, 510))
		_walk_to_site(world, id, world.terrain.nearest_open(Terrain.index(point)), Units.Mode.EXPLORE, at)
		return
	if not world.sight.sees(page.positions[row], clues[chosen].tile, world.sight.range_for(world, id)):
		# Approach remembered evidence before consulting current facility state.
		_walk_to_site(world, id, world.terrain.nearest_open(clues[chosen].tile), Units.Mode.EXPLORE, at)
		return
	if not world.objects.records.has(chosen):
		_walk_to_site(world, id, world.terrain.nearest_open(clues[chosen].tile), Units.Mode.EXPLORE, at)
		return
	if kind == "harvest":
		var source: int = world.source_objects.find(chosen)
		if source >= 0:
			var point: Vector2 = world.facilities.interaction_point(world, chosen, page.positions[row], page.radii[row], page.flight[row] > 0, "harvest")
			if point.x < 0:
				after_action(world, id, at, chosen)
				return
			world.end_run(id, at)
			page.source_ids[row] = source
			if world.adopt_work(id, at): page.move_to(row, point, Units.Mode.RESOURCE)
			else: after_action(world, id, at, chosen)
			return
	var reason: String
	if kind == "put":
		reason = world.begin_transfer(id, {"kind": "put", "target": chosen, "item": "wood", "amount": page.cargo[row]})
	else:
		reason = world.begin_interaction(id, {"kind": kind, "target": chosen, "autonomous": true})
	if reason == "accepted":
		world.actions[id]["autonomous"] = true
	else:
		after_action(world, id, at, chosen)


func _walk_to_site(world: RefCounted, id: int, tile: int, mode: int, at: int) -> void:
	var slot: int = world.actor_slots[id]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	var point: Vector2 = world.terrain.project_point(Terrain.center(tile), page.radii[row], page.flight[row] > 0)
	if point.x < 0:
		after_action(world, id, at)
	else:
		if world.adopt_work(id, at): page.move_to(row, point, mode)
		else: after_action(world, id, at)


func after_action(world: RefCounted, id: int, at: int, target: int = 0) -> void:
	if not world.actor_slots.has(id) or not world.combat.alive(world, id): return
	if target > 0: remember(world, id, target, at)
	world.decisions.wake(world, id, at, "life_result", 500 + (id % 10) * 50)
