extends RefCounted
## The simulation thread owns this world. Lanes exclusively own unit pages
## during a step; only this owner resolves shared resources and commands.
## No Node, scene callback, global GameClock, or borrowed live-world UI access.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Fields = preload("res://scripts/sim/kernel/environment.gd")
const Batch = preload("res://scripts/sim/execution/batch_execution.gd")
const Objects = preload("res://scripts/sim/kernel/objects.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const Facilities = preload("res://scripts/sim/kernel/facilities.gd")
const Livelihood = preload("res://scripts/sim/kernel/livelihood.gd")
const Nature = preload("res://scripts/sim/kernel/nature.gd")
const Combat = preload("res://scripts/sim/kernel/combat.gd")
const Society = preload("res://scripts/sim/kernel/society.gd")
const Perception = preload("res://scripts/sim/kernel/perception.gd")
const Regions = preload("res://scripts/sim/kernel/regions.gd")
const STATE_FIELDS: Array = ["elapsed_ms", "actor_count", "initial_material", "harvested", "deliveries", "failed_harvests", "steps", "deaths", "attacks", "heals", "attack_due", "topology_revision", "source_objects", "depot_objects", "reservations", "actions"]

class Lane extends RefCounted:
	var pages: Array[RefCounted] = []
	var graph: AStarGrid2D
	var paths: Dictionary = {}
	var work_usec: int = 0
	var thread_id: int
	var sampling: bool = false
	var large_graph: AStarGrid2D

	func run() -> void:
		var start: int = Time.get_ticks_usec()
		thread_id = OS.get_thread_caller_id()
		for page: RefCounted in pages:
			if sampling:
				page.sample_environment()
			else:
				if large_graph == null and page.has_large:
					large_graph = page.terrain.navigation(1)
				page.advance(graph, paths, large_graph)
		work_usec += Time.get_ticks_usec() - start

var terrain := Terrain.new()
var environment := Fields.new()
var pages: Array[RefCounted] = []
var lanes: Array[RefCounted] = []
var objects := Objects.new()
var facilities := Facilities.new()
var livelihood := Livelihood.new()
var nature := Nature.new()
var combat := Combat.new()
var society := Society.new()
var perception := Perception.new()
var regions := Regions.new()
var actor_slots: Dictionary = {} # External identity -> stable internal body slot.
var source_objects := PackedInt64Array()
var depot_objects := PackedInt64Array()
var reservations: Dictionary = {} # Target identity -> actor identity, owner only.
var actions: Dictionary = {}
var free_slots := PackedInt32Array()
var elapsed_ms: int = 0
var actor_count: int
var workers: int
var requested_workers: int = -1
var stored: int:
	get:
		var count: int = 0
		for id: int in depot_objects:
			count += objects.amount(id, "wood")
		return count
var initial_material: int = 0
var harvested: int = 0
var deliveries: int = 0
var failed_harvests: int = 0
var steps: int = 0
var step_usec: int = 0
var maximum_step_usec: int = 0
var environment_usec: int = 0
var units_usec: int = 0
var effects_usec: int = 0
var deaths: int = 0
var attacks: int = 0
var heals: int = 0
var attack_due := PackedInt64Array()
var topology_revision: int = 0
var outcomes: Array[Dictionary] = []
var _topology_edits: Dictionary = {}
var topology_usec: int = 0


func initialize(count: int = 1000, requested_workers: int = 4) -> void:
	actor_count = count
	terrain.initialize()
	environment.initialize(terrain, count)
	terrain.source_cells = environment.source_cells.duplicate()
	terrain.source_channels = environment.source_channels.duplicate()
	attack_due.resize(count)
	for slot: int in count:
		var id: int = objects.create("actor", "human")
		objects.add(id, "potion", 3)
		actor_slots[id] = slot
	for tile: int in terrain.resources:
		var id: int = objects.create("resource", "wood", tile)
		objects.add(id, "wood", 1000)
		source_objects.append(id)
	for tile: int in terrain.depots:
		depot_objects.append(objects.create("chest", "wood_chest", tile))
	for tile: int in terrain.structures:
		if terrain.enclosures[tile] != 0:
			objects.create("wall" if terrain.blocked[tile] != 0 else "door", "wood_wall" if terrain.blocked[tile] != 0 else "wood_door", tile)
	initial_material = objects.total("wood")
	var pile: int = objects.create("pile", "wood", Terrain.index(Vector2i(178, 186)))
	objects.transfer(source_objects[0], pile, "wood", 50)
	objects.create("chest", "wood_chest", Terrain.index(Vector2i(176, 186)), 100)
	for first: int in range(0, count, Units.PAGE_SIZE):
		var page := Units.new()
		page.initialize(first + 1, mini(Units.PAGE_SIZE, count - first), terrain)
		page.environment = environment
		page.potions.fill(3)
		pages.append(page)
	configure_lanes(requested_workers)
	environment.update(0, pages, actor_slots)
	for page: RefCounted in pages:
		page.sample_environment(0.0)
	topology_revision = terrain.revision
	if count < 1000:
		pages[0].positions[0] = Terrain.center(Terrain.index(Vector2i(177, 188)))
	facilities.seed_fixture(self, "long_bed", Terrain.index(Vector2i(176, 182)))
	var stove: int = facilities.seed_fixture(self, "cook_stove", Terrain.index(Vector2i(174, 185)))
	objects.add(stove, "meal", 30)
	var supplies: int = objects.by_tile[Terrain.index(Vector2i(176, 186))][0]
	objects.add(supplies, "grain", 30)
	objects.add(supplies, "water", 30)
	flush_topology()
	livelihood.initialize(self)
	nature.initialize(self)
	society.initialize(self)
	regions.initialize(self)
	flush_topology()
	if count >= 24:
		for actor: int in range(count - 3, count + 1):
			var slot: int = actor_slots[actor]
			var page: RefCounted = pages[slot / 256]
			page.positions[slot % 256] = Terrain.center(Terrain.index(Vector2i(177 + count - actor, 168)))
			objects.records[actor]["side"] = 1
			objects.records[actor].autonomous = false
			combat.begin(self, actor, "hold", 0, -1, actor % 2 == 0)
	perception.update(self, 0, true)


func state_owners() -> Dictionary:
	# The concrete composition root lists real domains; field selection belongs
	# to each owner. New domains do not require a new serializer implementation.
	return {"world": self, "terrain": terrain, "objects": objects, "environment": environment, "nature": nature, "combat": combat, "perception": perception, "regions": regions}


func configure_lanes(requested_workers: int) -> void:
	self.requested_workers = requested_workers
	workers = Batch.resolve_workers(requested_workers, pages.size())
	lanes.clear()
	for lane_id: int in maxi(1, workers):
		var lane := Lane.new()
		lane.graph = terrain.navigation()
		lanes.append(lane)
	for index: int in pages.size():
		lanes[index % lanes.size()].pages.append(pages[index])


func step() -> void:
	var start: int = Time.get_ticks_usec()
	var end: int = elapsed_ms + 50
	combat.before_motion(self)
	for page: RefCounted in pages:
		page.end_ms = end
	var unit_start: int = Time.get_ticks_usec()
	var batch := Batch.new()
	batch.start(lanes, workers)
	batch.finish(true)
	units_usec += Time.get_ticks_usec() - unit_start
	# Only contenders reach this stage; ordinary in-transit rows are not scanned.
	var effect_start: int = Time.get_ticks_usec()
	var events := PackedInt64Array()
	var stride: int = attack_due.size() + 1
	for page: RefCounted in pages:
		for row: int in page.failures:
			var id: int = page.ids[row]
			if combat.orders.has(id):
				combat.finish(self, id, end)
				outcomes.append({"kind": "path_failed", "actor": id, "at_ms": end})
				continue
			release(id)
			if page.modes[row] == Units.Mode.MANUAL:
				page.modes[row] = Units.Mode.IDLE
				outcomes.append({"kind": "path_failed", "actor": id, "at_ms": end})
			elif page.modes[row] == Units.Mode.APPROACH:
				page.modes[row] = Units.Mode.IDLE
				if objects.records[id].get("autonomous", false):
					livelihood.after_action(self, id, end)
				outcomes.append({"kind": "path_failed", "actor": id, "at_ms": end})
			else:
				page.modes[row] = Units.Mode.REST
				page.due_ms[row] = end + 1000
		for entry: int in range(0, page.ready.size(), 2):
			var slot: int = actor_slots[page.ids[page.ready[entry]]]
			events.append(clampi(page.ready[entry + 1] - elapsed_ms, 0, 50) * stride + slot)
	events.sort() # Arrival/due time first; stable body slot breaks equal-time ties.
	for event: int in events:
		var slot: int = event % stride
		settle(pages[slot / Units.PAGE_SIZE].ids[slot % Units.PAGE_SIZE], elapsed_ms + int(event / stride))
	combat.step(self, end)
	nature.pulse(self, end)
	flush_topology()
	effects_usec += Time.get_ticks_usec() - effect_start
	if end % 1000 == 0:
		# Periodic end-of-step effects cannot erase an earlier arrival/due effect.
		var env_start: int = Time.get_ticks_usec()
		environment.update(end, pages, actor_slots)
		for lane: RefCounted in lanes:
			lane.sampling = true
		var sampling := Batch.new()
		sampling.start(lanes, workers)
		sampling.finish(true)
		for lane: RefCounted in lanes:
			lane.sampling = false
		for page: RefCounted in pages:
			for row: int in page.environmental_deaths:
				kill(page.ids[row], end)
		environment_usec += Time.get_ticks_usec() - env_start
	elapsed_ms = end
	perception.update(self, end)
	steps += 1
	var cost: int = Time.get_ticks_usec() - start
	step_usec += cost
	maximum_step_usec = maxi(maximum_step_usec, cost)


func settle(id: int, at: int) -> void:
	if not actor_slots.has(id):
		return
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	var mode: int = page.modes[row]
	var source: int = page.source_ids[row]
	var target: int = source_objects[source]
	if page.health[row] <= 0:
		kill(id, at)
	elif mode == Units.Mode.RESOURCE:
		if not reservations.has(target) and objects.amount(target, "wood") > 0:
			reservations[target] = id
			page.modes[row] = Units.Mode.HARVEST
			page.due_ms[row] = at + 500
		else:
			page.modes[row] = Units.Mode.REST
			page.due_ms[row] = at + 250
	elif mode == Units.Mode.HARVEST:
		if reservations.get(target, 0) == id and objects.transfer(target, id, "wood", 1) > 0:
			reservations.erase(target)
			_sync_inventory(id)
			harvested += 1
			livelihood.remember(self, id, target, at)
			livelihood.think(self, id, at)
		else:
			if reservations.get(target, 0) == id:
				reservations.erase(target)
			failed_harvests += 1
			page.modes[row] = Units.Mode.REST
			page.due_ms[row] = at + 1000
	elif mode == Units.Mode.REST:
		resume_work(id, at)
	elif mode == Units.Mode.MANUAL:
		page.modes[row] = Units.Mode.IDLE
		outcomes.append({"kind": "arrived", "actor": id, "at_ms": at})
	elif mode == Units.Mode.APPROACH or mode == Units.Mode.ACTION:
		settle_action(id, at)
	elif mode == Units.Mode.EXPLORE:
		livelihood.observe(self, id, at)
		livelihood.think(self, id, at)
	elif mode == Units.Mode.COMBAT_MOVE:
		page.modes[row] = Units.Mode.IDLE


func resume_work(id: int, at: int = -1) -> void:
	livelihood.think(self, id, at if at >= 0 else elapsed_ms)


func release(id: int, at: int = -1) -> void:
	if not actor_slots.has(id):
		return
	combat.orders.erase(id)
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var target: int = source_objects[page.source_ids[slot % Units.PAGE_SIZE]]
	if reservations.get(target, 0) == id:
		reservations.erase(target)
	if actions.has(id):
		var action: Dictionary = actions[id]
		actions.erase(id)
		target = action.target
		if reservations.get(target, 0) == id:
			reservations.erase(target)
		facilities.interrupt(self, action, at if at >= 0 else elapsed_ms)
		society.interrupt(self, action, at if at >= 0 else elapsed_ms)


func kill(id: int, at: int = -1) -> void:
	if not actor_slots.has(id):
		return
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	if page.modes[row] == Units.Mode.DEAD:
		return
	release(id, at)
	forget_target(id)
	objects.records[id].erase("commitment")
	page.health[row] = 0
	page.modes[row] = Units.Mode.DEAD
	environment.remove_mobile(id)
	# A corpse retains its cargo. Death cannot erase or duplicate materials.
	deaths += 1
	outcomes.append({"kind": "death", "actor": id, "at_ms": at if at >= 0 else elapsed_ms})


func forget_target(target: int) -> void:
	# Rare structural deletion cleans cold dependents immediately, including
	# save-between-removal-and-arrival. No per-step scan for missing objects.
	for actor: int in actions.keys():
		if actions[actor].target == target:
			var automatic: bool = actions[actor].get("autonomous", false)
			release(actor)
			var slot: int = actor_slots[actor]
			pages[slot / Units.PAGE_SIZE].modes[slot % Units.PAGE_SIZE] = Units.Mode.IDLE
			if automatic:
				livelihood.after_action(self, actor, elapsed_ms)
	reservations.erase(target)


func command(input: Dictionary) -> Dictionary:
	var receipt: Dictionary = {"seq": input.get("seq", 0), "kind": input.get("kind", ""), "at_ms": elapsed_ms, "ok": false, "reason": "invalid"}
	var id: int = int(input.get("actor", 1))
	if not actor_slots.has(id):
		return receipt
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	if page.health[row] <= 0:
		receipt.reason = "dead"
		return receipt
	match str(input.get("kind", "")):
		"journey":
			if not input.get("region") is int:
				return receipt
			var tile: int = regions.destination(int(input.get("region", 0)))
			if tile < 0:
				return receipt
			tile = terrain.nearest_open(tile, int(page.radii[row] > 0.5 and page.flight[row] == 0))
			if tile < 0:
				receipt.reason = "destination_blocked"
				return receipt
			release(id)
			objects.records[id].autonomous = false
			page.move_to(row, tile, Units.Mode.MANUAL)
		"ability":
			var reason: String = society.use_ability(self, id)
			receipt.ok = reason == "ability_used"
			receipt.reason = reason
			return receipt
		"pursue", "attack_move", "hold":
			var destination: int = int(input.get("tile", -1))
			if input.kind == "attack_move" and (destination < 0 or destination >= terrain.blocked.size() or terrain.blocked[destination] != 0):
				receipt.reason = "blocked"
				return receipt
			var reason: String = combat.begin(self, id, input.kind, int(input.get("target", 0)), destination, input.get("ranged", false))
			if reason != "accepted":
				receipt.reason = reason
				return receipt
		"body":
			var clearance: int = 1 if input.get("large", false) else 0
			var flight: int = clampi(int(input.get("flight", 0)), 0, 1)
			if flight == 0 and not terrain.fits(Vector2i(page.positions[row]), clearance):
				receipt.reason = "body_does_not_fit_here"
				return receipt
			release(id)
			page.flight[row] = flight
			page.radii[row] = 0.9 if input.get("large", false) else 0.35
			page.has_large = page.has_large or clearance > 0
			page.modes[row] = Units.Mode.IDLE
		"move":
			var tile: int = int(input.get("tile", -1))
			if tile < 0 or tile >= terrain.blocked.size() or (terrain.blocked[tile] != 0 and page.flight[row] == 0):
				receipt.reason = "blocked"
				return receipt
			release(id)
			objects.records[id].autonomous = false
			page.move_to(row, tile, Units.Mode.MANUAL)
		"stop":
			release(id)
			page.modes[row] = Units.Mode.IDLE
			objects.records[id].autonomous = false
		"work":
			release(id)
			objects.records[id].autonomous = true
			livelihood.observe(self, id, elapsed_ms)
			livelihood.think(self, id, elapsed_ms)
		"heal":
			if objects.amount(id, "potion") <= 0 or page.health[row] >= 100:
				receipt.reason = "no_potion_or_full"
				return receipt
			objects.add(id, "potion", -1)
			_sync_inventory(id)
			page.health[row] = mini(100, page.health[row] + 40)
			heals += 1
		"attack":
			var target: int = int(input.get("target", 0))
			if not actor_slots.has(target) or target == id:
				return receipt
			var other_slot: int = actor_slots[target]
			var victim: RefCounted = pages[other_slot / Units.PAGE_SIZE]
			var other: int = other_slot % Units.PAGE_SIZE
			if victim.health[other] <= 0 or page.positions[row].distance_to(victim.positions[other]) > 2.0 or attack_due[slot] > elapsed_ms:
				receipt.reason = "out_of_reach_or_cooldown"
				return receipt
			release(id)
			page.modes[row] = Units.Mode.IDLE
			attack_due[slot] = elapsed_ms + 600
			combat.damage(self, id, target, 25, elapsed_ms)
			if objects.records[id].get("autonomous", false):
				livelihood.after_action(self, id, elapsed_ms)
		"source":
			var source: int = int(input.get("target", -1))
			if input.has("tile"):
				# Render marker order is not a source identity: plants can add,
				# release and reuse slots before a region adds its own emitters.
				source = -1
				for index: int in environment.source_cells.size():
					if environment.source_cells[index] == int(input.tile) and not environment.free_sources.has(index):
						source = index
						break
			if source < 0 or source >= environment.enabled.size() or environment.free_sources.has(source):
				return receipt
			environment.enabled[source] = 1 - environment.enabled[source]
			environment.rebuild_static()
		"take", "put":
			var reason: String = begin_transfer(id, input)
			if reason != "accepted":
				receipt.reason = reason
				return receipt
		"construct":
			var result: Dictionary = facilities.blueprint(self, id, str(input.get("definition", "wood_wall")), int(input.get("tile", -1)))
			if result.reason != "accepted":
				receipt.reason = result.reason
				return receipt
			var reason: String = begin_interaction(id, {"kind": "construct", "target": result.target})
			if reason != "accepted":
				receipt.reason = reason
				return receipt
		"plant":
			var result: Dictionary = nature.plant_site(self, id, str(input.get("definition", "perennial_herb")), int(input.get("tile", -1)))
			if result.reason != "accepted":
				receipt.reason = result.reason
				return receipt
			var reason: String = begin_interaction(id, {"kind": "sow", "target": result.target})
			if reason != "accepted":
				receipt.reason = reason
				return receipt
		"weather":
			environment.weather_override = clampi(int(input.get("weather", -1)), -1, 3)
		"talk", "trade", "request_help", "learn", "study", "practice", "sow", "tend", "gather", "cut", "uproot", "rest", "eat", "cook", "continue_build", "demolish":
			var action: Dictionary = input.duplicate()
			if action.kind == "continue_build":
				action.kind = "construct"
			var reason: String = begin_interaction(id, action)
			if reason != "accepted":
				receipt.reason = reason
				return receipt
		"drop":
			var item: String = str(input.get("item", "wood"))
			var count: int = mini(int(input.get("amount", 10)), objects.amount(id, item))
			if count <= 0:
				receipt.reason = "empty"
				return receipt
			release(id)
			page.modes[row] = Units.Mode.IDLE
			var pile: int = objects.create("pile", item, Terrain.index(Vector2i(page.positions[row])))
			objects.transfer(id, pile, item, count)
			_sync_inventory(id)
		"build":
			var tile: int = int(input.get("tile", -1))
			var kind: int = int(input.get("structure", 1))
			if tile < 0 or tile >= terrain.blocked.size() or kind < 0 or kind > 2:
				return receipt
			for object: int in objects.by_tile.get(tile, []):
				if objects.records[object].kind not in ["wall", "door", "pile"]:
					receipt.reason = "occupied"
					return receipt
			if kind == 1:
				if terrain.resources.has(tile) or terrain.depots.has(tile):
					receipt.reason = "reserved_ground"
					return receipt
				for body: RefCounted in pages:
					for local: int in body.ids.size():
						if body.ids[local] > 0 and Terrain.index(Vector2i(body.positions[local])) == tile:
							receipt.reason = "occupied"
							return receipt
			for object: int in objects.by_tile.get(tile, []).duplicate():
				if objects.records[object].kind in ["wall", "door"]:
					facilities.demolish(self, object)
			if kind > 0:
				objects.create("wall" if kind == 1 else "door", "wood_wall" if kind == 1 else "wood_door", tile)
			queue_structure(tile, kind == 1, kind > 0, kind == 0)
		_:
			return receipt
	receipt.ok = true
	receipt.reason = "accepted"
	return receipt


func counters() -> Dictionary:
	var material: int = objects.total("wood")
	var cargo_total: int = 0
	var distance: float = 0.0
	var paths: int = 0
	var failed_paths: int = 0
	var alive: int = 0
	for page: RefCounted in pages:
		distance += page.moved_distance
		paths += page.path_requests
		failed_paths += page.path_failures
		for amount: int in page.cargo:
			cargo_total += amount
		for hp: int in page.health:
			alive += int(hp > 0)
	return {"world_ms": elapsed_ms, "actors": actor_count, "alive": alive, "workers": workers,
		"steps": steps, "step_usec": step_usec, "maximum_step_usec": maximum_step_usec,
		"moved_cells": distance, "path_requests": paths, "path_failures": failed_paths,
		"harvested": harvested, "deliveries": deliveries, "stored": stored, "cargo": cargo_total,
		"material": material, "initial_material": initial_material,
		"failed_harvests": failed_harvests, "deaths": deaths, "attacks": attacks, "heals": heals,
		"environment_usec": environment_usec, "units_usec": units_usec, "effects_usec": effects_usec,
		"environment_updates": environment.updates, "rooms": terrain.room_cells.size(),
		"structures": terrain.structures.size(), "static_sources": environment.source_cells.size(),
		"mobile_sources": environment.mobile_units.size(), "objects": objects.records.size(), "transfers": objects.transfers,
		"decisions": livelihood.decisions, "observations": livelihood.observations, "decision_usec": livelihood.decision_usec, "observe_usec": livelihood.observe_usec, "topology_usec": topology_usec,
		"facility_completions": facilities.completed.duplicate(), "plants": nature.ids.size(), "plant_evaluations": nature.evaluations, "plant_transitions": nature.transitions, "plant_collections": nature.collections, "nature_usec": nature.work_usec, "calendar": environment.calendar(), "combatants": combat.orders.size(), "projectiles": combat.bolts.size(), "shots": combat.shots, "hits": combat.hits, "combat_usec": combat.work_usec, "combat_repaths": combat.repaths, "combat_resumed": combat.resumed}


func _sync_inventory(id: int) -> void:
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	page.cargo[row] = objects.amount(id, "wood") # Display summaries, not inventory authority.
	page.potions[row] = objects.amount(id, "potion")


func begin_transfer(id: int, input: Dictionary) -> String:
	var target: int = int(input.get("target", 0))
	if not objects.records.has(target) or objects.records[target].kind not in ["chest", "pile", "resource"]:
		return "invalid_target"
	var kind: String = input.kind
	var item: String = str(input.get("item", "wood"))
	var count: int = int(input.get("amount", 10))
	var source: int = target if kind == "take" else id
	if count <= 0 or (kind == "put" and objects.amount(source, item) <= 0):
		return "empty"
	return begin_interaction(id, {"kind": kind, "target": target, "item": item, "amount": count})


func begin_interaction(id: int, input: Dictionary) -> String:
	var target: int = int(input.get("target", 0))
	if not objects.records.has(target) or (actor_slots.has(target) and not combat.alive(self, target)):
		return "invalid_target"
	if input.kind not in ["take", "put", "demolish"] and input.kind not in Nature.ACTIONS and input.kind not in Society.ACTIONS and not facilities.available(self, input):
		return "unavailable"
	if input.kind in Society.ACTIONS and not society.available(self, id, input):
		return "not_available_for_contact"
	if objects.records[target].tile < 0 and input.kind not in Society.ACTIONS:
		return "invalid_target"
	if input.kind in Nature.ACTIONS and objects.records[target].kind != "plant":
		return "not_a_plant"
	var exclusive: bool = input.kind not in ["take", "put", "eat"]
	if exclusive and reservations.has(target) and reservations[target] != id and input.get("autonomous", false):
		return "target_busy"
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	var tile: int = facilities.interaction_tile(self, target, page.positions[row])
	if tile < 0:
		return "no_operation_place"
	release(id)
	actions[id] = input.duplicate(true)
	if exclusive and not reservations.has(target):
		reservations[target] = id
	if input.kind in Society.ACTIONS and reservations.get(target, 0) == id:
		society.invite(self, id, actions[id])
	page.move_to(row, tile, Units.Mode.APPROACH)
	return "accepted"


func settle_action(id: int, at: int) -> void:
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	if not actions.has(id):
		page.modes[row] = Units.Mode.IDLE
		return
	var action: Dictionary = actions[id]
	var target: int = action.target
	if not objects.records.has(target) or (actor_slots.has(target) and not combat.alive(self, target)):
		var autonomous: bool = action.get("autonomous", false)
		release(id, at)
		page.modes[row] = Units.Mode.IDLE
		outcomes.append({"kind": "target_gone", "actor": id, "at_ms": at})
		if autonomous:
			livelihood.after_action(self, id, at, target)
		return
	var in_range: bool = false
	var target_cells: PackedInt32Array = objects.records[target].get("cells", PackedInt32Array([objects.records[target].tile]))
	if actor_slots.has(target):
		target_cells = PackedInt32Array([Terrain.index(Vector2i(combat.position(self, target)))])
	for tile: int in target_cells:
		if page.positions[row].distance_to(Terrain.center(tile)) <= 1.5:
			in_range = true
	if not in_range:
		var autonomous: bool = action.get("autonomous", false)
		release(id, at)
		page.modes[row] = Units.Mode.IDLE
		outcomes.append({"kind": "out_of_reach", "actor": id, "at_ms": at})
		if autonomous:
			livelihood.after_action(self, id, at, target)
		return
	if page.modes[row] == Units.Mode.APPROACH:
		var exclusive: bool = action.kind not in ["take", "put", "eat"]
		if exclusive and reservations.has(target) and reservations[target] != id:
			if action.get("autonomous", false):
				release(id)
				livelihood.after_action(self, id, at, target)
				return
			page.modes[row] = Units.Mode.ACTION
			page.due_ms[row] = at + 250
			action["waiting"] = true
			return
		if exclusive:
			reservations[target] = id
		if action.kind in Society.ACTIONS and not action.get("partner_waiting", false):
			society.invite(self, id, action)
		page.modes[row] = Units.Mode.ACTION
		action["started_ms"] = at
		var duration: int = facilities.duration(self, action)
		if action.kind in Nature.ACTIONS:
			duration = int(objects.records[target].remaining_ms) if action.kind == "sow" else 1500
		elif action.kind in Society.ACTIONS:
			duration = 3000 if action.kind == "practice" else 1000
		page.due_ms[row] = at + duration
		return
	if action.get("waiting", false):
		action.erase("waiting")
		page.modes[row] = Units.Mode.APPROACH
		settle_action(id, at)
		return
	if action.kind not in ["take", "put"]:
		var reason: String
		if action.kind == "demolish":
			reason = "completed" if facilities.demolish(self, target) else "failed"
		elif action.kind in Nature.ACTIONS:
			reason = nature.finish(self, id, action, at)
		elif action.kind in Society.ACTIONS:
			reason = society.finish(self, id, action, at)
		else:
			reason = facilities.finish(self, id, action, at)
		if reason == "occupied" and action.kind == "construct":
			objects.records[target].remaining_ms = 1
			action.started_ms = at
			page.due_ms[row] = at + 250
			return
		if objects.records.has(target) and action.kind == "construct":
			action.erase("started_ms") # Completion/cannot-build is not an extra work interval.
		var autonomous: bool = action.get("autonomous", false)
		release(id)
		page.modes[row] = Units.Mode.IDLE
		outcomes.append({"kind": reason, "actor": id, "at_ms": at})
		if autonomous:
			livelihood.after_action(self, id, at, target)
		return
	var source: int = target if action.kind == "take" else id
	var destination: int = id if action.kind == "take" else target
	var amount: int = objects.transfer(source, destination, action.item, action.amount)
	if objects.records.get(source, {}).get("kind", "") == "pile":
		objects.remove_empty(source)
	var autonomous: bool = action.get("autonomous", false)
	_sync_inventory(id)
	release(id)
	page.modes[row] = Units.Mode.IDLE
	outcomes.append({"kind": "transferred" if amount > 0 else "empty_or_full", "actor": id, "at_ms": at, "amount": amount})
	if autonomous:
		if action.kind == "put" and amount > 0:
			deliveries += 1
		livelihood.after_action(self, id, at, target)


func describe(id: int) -> Dictionary:
	if not objects.records.has(id):
		return {}
	var result: Dictionary = State.copy(objects.records[id])
	if actor_slots.has(id):
		var slot: int = actor_slots[id]
		var page: RefCounted = pages[slot / Units.PAGE_SIZE]
		var row: int = slot % Units.PAGE_SIZE
		result.merge({"hp": page.health[row], "energy": page.energy[row], "hunger": page.hunger[row],
			"temperature": page.body_heat[row], "elements": page.elements.slice(row * 5, row * 5 + 5),
			"cargo": page.cargo[row], "potions": page.potions[row], "mode": page.modes[row], "position": page.positions[row]}, true)
		result["action"] = State.copy(actions.get(id, combat.orders.get(id, {})))
		result["flight"] = page.flight[row]
		result["radius"] = page.radii[row]
	return result


func queue_structure(tile: int, solid: bool, enclosed: bool, removing: bool = false) -> void:
	if not _topology_edits.has(tile):
		_topology_edits[tile] = {"solid": terrain.blocked[tile] != 0, "enclosed": terrain.enclosures[tile] != 0}
	terrain.blocked[tile] = int(solid)
	terrain.enclosures[tile] = int(enclosed)
	if removing:
		terrain.structures.erase(tile)
	elif not terrain.structures.has(tile):
		terrain.structures.append(tile)


func flush_topology() -> void:
	if _topology_edits.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	var room_dirty: bool = false
	var field_dirty: bool = false
	var blockers: Dictionary = {}
	for tile: int in _topology_edits:
		room_dirty = room_dirty or _topology_edits[tile].enclosed != (terrain.enclosures[tile] != 0)
		if _topology_edits[tile].solid != (terrain.blocked[tile] != 0):
			for lane: RefCounted in lanes:
				lane.graph.set_point_solid(Terrain.cell(tile), terrain.blocked[tile] != 0)
				lane.paths.clear()
				lane.large_graph = null
			if terrain.blocked[tile] != 0:
				blockers[tile] = true
			for source: int in environment.source_cells:
				if (Terrain.cell(source) - Terrain.cell(tile)).length_squared() < environment.RADIUS * environment.RADIUS:
					field_dirty = true
	if not blockers.is_empty():
		for page: RefCounted in pages:
			for row: int in page.routes.size():
				for cursor: int in range(page.route_cursors[row], page.routes[row].size()):
					if blockers.has(page.routes[row][cursor]):
						page.routes[row] = PackedInt32Array()
						page.route_cursors[row] = 0
						break
	if room_dirty:
		var previous_rooms: PackedInt32Array = terrain.rooms.duplicate()
		var previous_heat: PackedFloat32Array = environment.room_temperature
		terrain.rebuild_rooms()
		var heat := PackedFloat32Array()
		for room: PackedInt32Array in terrain.room_cells:
			var sum: float = 0
			for tile: int in room:
				var before: int = previous_rooms[tile]
				sum += previous_heat[before] if before >= 0 else 22.0
			heat.append(sum / room.size())
		environment.room_temperature = heat
	if field_dirty:
		environment.rebuild_static()
	terrain.revision += 1
	topology_revision = terrain.revision
	_topology_edits.clear()
	topology_usec += Time.get_ticks_usec() - started


func spawn_actor(tile: int) -> int:
	if tile < 0 or tile >= terrain.blocked.size() or terrain.blocked[tile] != 0:
		return 0
	var id: int = objects.create("actor", "human")
	var slot: int
	var page: RefCounted
	var row: int
	if not free_slots.is_empty():
		slot = free_slots[-1]
		free_slots.resize(free_slots.size() - 1)
		page = pages[slot / Units.PAGE_SIZE]
		row = slot % Units.PAGE_SIZE
		page.ids[row] = id
		page.positions[row] = Terrain.center(tile)
		page.health[row] = 100
		page.energy[row] = 10000
		page.hunger[row] = 10000
		page.body_heat[row] = 22.0
		page.flight[row] = 0
		page.radii[row] = 0.35
		page.cargo[row] = 0
		page.potions[row] = 0
		page.routes[row] = PackedInt32Array()
		page.route_cursors[row] = 0
		page.due_ms[row] = 0
		attack_due[slot] = 0
	else:
		slot = attack_due.size()
		if pages.is_empty() or pages.back().ids.size() == Units.PAGE_SIZE:
			page = Units.new()
			page.terrain = terrain
			page.environment = environment
			pages.append(page)
			configure_lanes(requested_workers)
		else:
			page = pages.back()
		row = page.add_row(id, tile)
		attack_due.append(0)
	page.modes[row] = Units.Mode.IDLE
	actor_slots[id] = slot
	actor_count += 1
	return id


func remove_actor(id: int) -> bool:
	if id == 1 or not actor_slots.has(id):
		return false
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	release(id)
	forget_target(id)
	environment.remove_mobile(id)
	if objects.count_inventory(id) > 0:
		var pile: int = objects.create("pile", "remains", Terrain.index(Vector2i(page.positions[row])))
		for item: String in objects.records[id].inventory.keys():
			objects.transfer(id, pile, item, objects.amount(id, item))
	objects.remove_empty(id)
	actor_slots.erase(id)
	page.ids[row] = 0
	page.health[row] = 0
	page.cargo[row] = 0
	page.potions[row] = 0
	page.modes[row] = Units.Mode.FREE
	free_slots.append(slot)
	actor_count -= 1
	return true
