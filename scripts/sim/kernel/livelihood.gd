extends RefCounted
## Sparse owner-side choices, awakened by the existing body due/arrival queue.
## Personal clues are observations, not an alias of current global inventories.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
var decisions: int = 0
var decision_usec: int = 0


func initialize(world: RefCounted) -> void:
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			var id: int = page.ids[row]
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
	if world.knowledge.record(id).due_ms <= at:
		world.knowledge.observe(world, id, at)
	var commitment: Dictionary = person.get("commitment", {})
	var labor: bool = Beings.has(person, "work")
	var metabolism: bool = Beings.has(person, "metabolism")
	if not commitment.is_empty():
		var target: int = int(commitment.target)
		var clue: Dictionary = world.knowledge.view(id, target, at)
		if not clue.is_empty() and clue.tile >= 0 and world.sight.sees(page.positions[row], clue.tile, world.sight.range_for(world, id)):
			world.knowledge.refresh(world, id, target, at)
			clue = world.knowledge.view(id, target, at)
		if not labor or at >= int(commitment.expires_ms) or clue.is_empty() or clue.tile < 0 or clue.kind != "blueprint":
			person.erase("commitment")
			person.autonomous = commitment.get("was_autonomous", true)
			if not person.autonomous:
				page.modes[row] = Units.Mode.IDLE
				return
		elif not metabolism or (page.hunger[row] >= 2500 and page.energy[row] >= 2000):
			if not world.decisions.retry_allowed(world, id, "construct", target, at):
				after_action(world, id, at)
				return
			if not world.sight.sees(page.positions[row], clue.tile, world.sight.range_for(world, id)):
				_walk_to_site(world, id, world.terrain.nearest_open(clue.tile), Units.Mode.EXPLORE, at, "construct", target)
				return
			var reason: String = world.begin_interaction(id, {"kind": "construct", "target": target, "autonomous": true})
			if reason == "accepted":
				return
			_rejected(world, id, "construct", target, reason, at)
			return
	var clues: Dictionary = world.knowledge.known(id, at, false)
	var chosen: int = 0
	var kind: String = ""
	var best: float = INF
	var actor_view: Dictionary = world.operation_actor(id)
	for target: int in clues.keys():
		var clue: Dictionary = clues[target]
		if clue.kind == "actor" or int(clue.get("tile", -1)) < 0: continue # Contacts are not static work sites.
		# Absence at a presently observed location disproves this actor's clue.
		# Unseen locations retain their evidence until the actor actually checks.
		if world.sight.sees(page.positions[row], clue.tile, world.sight.range_for(world, id)):
			world.knowledge.refresh(world, id, target, at)
			clue = world.knowledge.view(id, target, at)
			if clue.tile < 0: continue
		var candidate: String = ""
		var priority: float = 0
		var available: Dictionary = {}
		for option: String in Query.options(clue):
			var handler: String = Operations.OPERATIONS[option].handler
			if handler not in ["eat", "rest", "construct", "craft", "put", "gather", "harvest"] or available.has(handler): continue
			if not world.decisions.retry_allowed(world, id, option, target, at): continue
			if Query.evaluate(Operations.OPERATIONS[option], actor_view, clue).ready: available[handler] = option
		if page.hunger[row] < 4000 and available.has("eat"):
			candidate = available.eat
			priority = -10000
		elif (page.energy[row] < 4000 or (Growth.needs_rest(person) and page.body_heat[row] >= 5.0 and page.body_heat[row] <= 40.0)) and available.has("rest"):
			candidate = available.rest
			priority = -9000
		elif available.has("construct"):
			candidate = available.construct
			priority = -2000
		elif page.cargo[row] == 0 and available.has("craft"):
			candidate = available.craft
			priority = -1500
		elif page.cargo[row] > 0 and clue.kind == "chest" and available.has("put"):
			candidate = available.put
			priority = -1000
		elif available.has("gather"):
			candidate = available.gather
			priority = -700
		elif page.cargo[row] == 0 and available.has("harvest"):
			candidate = available.harvest
		if candidate.is_empty():
			continue
		if not world.decisions.retry_allowed(world, id, candidate, target, at): continue
		if person.has("commitment") and Operations.OPERATIONS[candidate].handler not in ["eat", "rest"]: continue
		var score: float = page.positions[row].distance_squared_to(Terrain.center(clue.tile)) + priority
		if Operations.OPERATIONS[candidate].exclusive and world.sight.sees(page.positions[row], clue.tile, world.sight.range_for(world, id)) and world.reservations.has(target):
			continue
		if score < best:
			chosen = target
			best = score
			kind = candidate
	if chosen == 0:
		if not labor and not metabolism:
			page.modes[row] = Units.Mode.IDLE
			return # No current livelihood motive; do not schedule aimless searches.
		# No known useful site: take a short walk and observe at the destination.
		var point: Vector2i = Vector2i(page.positions[row]) + Vector2i(8 if (id + at / 1000) % 2 == 0 else -8, 5)
		point = point.clamp(Vector2i(1, 1), Vector2i(510, 510))
		_walk_to_site(world, id, world.terrain.nearest_open(Terrain.index(point)), Units.Mode.EXPLORE, at)
		return
	if not world.sight.sees(page.positions[row], clues[chosen].tile, world.sight.range_for(world, id)):
		# Approach remembered evidence before consulting current facility state.
		_walk_to_site(world, id, world.terrain.nearest_open(clues[chosen].tile), Units.Mode.EXPLORE, at, kind, chosen)
		return
	if not world.objects.records.has(chosen):
		_rejected(world, id, kind, chosen, "target_gone", at)
		return
	if Operations.OPERATIONS[kind].executor == "work_source":
		var source: int = world.source_objects.find(chosen)
		if source >= 0:
			var point: Vector2 = world.facilities.interaction_point(world, chosen, page.positions[row], page.radii[row], page.flight[row] > 0, "harvest")
			if point.x < 0:
				_rejected(world, id, kind, chosen, "no_operation_place", at)
				return
			world.end_run(id, at)
			page.source_ids[row] = source
			if world.adopt_work(id, at):
				page.move_to(row, point, Units.Mode.RESOURCE)
				world.decisions.track_host(world, id, kind, chosen)
			else: after_action(world, id, at, chosen)
			return
	var reason: String
	if Operations.OPERATIONS[kind].handler == "put":
		reason = world.begin_transfer(id, {"kind": kind, "target": chosen, "item": "wood", "amount": page.cargo[row]})
	else:
		reason = world.begin_interaction(id, {"kind": kind, "target": chosen, "autonomous": true})
	if reason == "accepted":
		world.actions[id]["autonomous"] = true
	else:
		_rejected(world, id, kind, chosen, reason, at)


func _walk_to_site(world: RefCounted, id: int, tile: int, mode: int, at: int, operation: String = "", target: int = 0) -> void:
	var slot: int = world.actor_slots[id]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	var point: Vector2 = world.terrain.project_point(Terrain.center(tile), page.radii[row], page.flight[row] > 0)
	if point.x < 0:
		_rejected(world, id, operation, target, "no_operation_place", at)
	else:
		if world.adopt_motion(id, at):
			page.move_to(row, point, mode)
			world.decisions.track_host(world, id, operation, target, true)
		else: after_action(world, id, at)


func _rejected(world: RefCounted, id: int, operation: String, target: int, reason: String, at: int) -> void:
	if target > 0: world.knowledge.outcome(world, id, operation, target, "refused", reason, at)
	world.decisions.result(world, id, operation, target, reason, at)
	after_action(world, id, at)


func after_action(world: RefCounted, id: int, at: int, target: int = 0) -> void:
	if not world.actor_slots.has(id) or not world.combat.alive(world, id): return
	if target > 0: world.knowledge.refresh(world, id, target, at)
	world.decisions.wake(world, id, at, "life_result", 500 + (id % 10) * 50)
