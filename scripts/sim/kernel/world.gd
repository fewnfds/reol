extends RefCounted
## The simulation thread owns this world. Lanes exclusively own unit pages
## during a step; only this owner resolves shared resources and commands.
## No Node, scene callback, global GameClock, or borrowed live-world UI access.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Fields = preload("res://scripts/sim/kernel/environment.gd")
const Batch = preload("res://scripts/sim/execution/batch_execution.gd")

class Lane extends RefCounted:
	var pages: Array[RefCounted] = []
	var graph: AStarGrid2D
	var paths: Dictionary = {}
	var work_usec: int = 0
	var thread_id: int
	var sampling: bool = false

	func run() -> void:
		var start: int = Time.get_ticks_usec()
		thread_id = OS.get_thread_caller_id()
		for page: RefCounted in pages:
			if sampling:
				page.sample_environment()
			else:
				page.advance(graph, paths)
		work_usec += Time.get_ticks_usec() - start

var terrain := Terrain.new()
var environment := Fields.new()
var pages: Array[RefCounted] = []
var lanes: Array[RefCounted] = []
var quantities := PackedInt32Array()
var reservations := PackedInt32Array()
var elapsed_ms: int = 0
var actor_count: int
var workers: int
var stored: int = 0
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


func initialize(count: int = 1000, requested_workers: int = 4) -> void:
	actor_count = count
	terrain.initialize()
	environment.initialize(terrain, count)
	terrain.source_cells = environment.source_cells.duplicate()
	terrain.source_channels = environment.source_channels.duplicate()
	quantities.resize(terrain.resources.size())
	quantities.fill(1000)
	reservations.resize(quantities.size())
	attack_due.resize(count)
	initial_material = quantities.size() * 1000
	for first: int in range(0, count, Units.PAGE_SIZE):
		var page := Units.new()
		page.initialize(first + 1, mini(Units.PAGE_SIZE, count - first), terrain)
		page.environment = environment
		pages.append(page)
	workers = Batch.resolve_workers(requested_workers, pages.size())
	for lane_id: int in maxi(1, workers):
		var lane := Lane.new()
		lane.graph = terrain.navigation()
		lanes.append(lane)
	for id: int in pages.size():
		lanes[id % lanes.size()].pages.append(pages[id])
	environment.update(0, pages)
	for page: RefCounted in pages:
		page.sample_environment(0.0)
	topology_revision = terrain.revision


func step() -> void:
	var start: int = Time.get_ticks_usec()
	var end: int = elapsed_ms + 50
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
	for page: RefCounted in pages:
		for row: int in page.failures:
			release(page.first_id + row)
			if page.modes[row] == Units.Mode.MANUAL:
				page.modes[row] = Units.Mode.IDLE
				outcomes.append({"kind": "path_failed", "actor": page.first_id + row, "at_ms": end})
			else:
				if page.cargo[row] > 0:
					page.depot_ids[row] = (page.depot_ids[row] + 1) % terrain.depots.size()
				page.modes[row] = Units.Mode.REST
				page.due_ms[row] = end + 1000
		for entry: int in range(0, page.ready.size(), 2):
			events.append(page.ready[entry + 1] * 65536 + page.first_id + page.ready[entry])
	events.sort() # Arrival/due time first; stable ID breaks simultaneous ties.
	for event: int in events:
		settle(int(event % 65536), int(event / 65536))
	effects_usec += Time.get_ticks_usec() - effect_start
	if end % 1000 == 0:
		# Periodic end-of-step effects cannot erase an earlier arrival/due effect.
		var env_start: int = Time.get_ticks_usec()
		environment.update(end, pages)
		for lane: RefCounted in lanes:
			lane.sampling = true
		var sampling := Batch.new()
		sampling.start(lanes, workers)
		sampling.finish(true)
		for lane: RefCounted in lanes:
			lane.sampling = false
		for page: RefCounted in pages:
			for row: int in page.environmental_deaths:
				kill(page.first_id + row, end)
		environment_usec += Time.get_ticks_usec() - env_start
	elapsed_ms = end
	steps += 1
	var cost: int = Time.get_ticks_usec() - start
	step_usec += cost
	maximum_step_usec = maxi(maximum_step_usec, cost)


func settle(id: int, at: int) -> void:
	var page: RefCounted = pages[(id - 1) / Units.PAGE_SIZE]
	var row: int = (id - 1) % Units.PAGE_SIZE
	var mode: int = page.modes[row]
	var source: int = page.source_ids[row]
	if page.health[row] <= 0:
		kill(id, at)
	elif mode == Units.Mode.RESOURCE:
		if reservations[source] == 0 and quantities[source] > 0:
			reservations[source] = id
			page.modes[row] = Units.Mode.HARVEST
			page.due_ms[row] = at + 500
		else:
			page.modes[row] = Units.Mode.REST
			page.due_ms[row] = at + 250
	elif mode == Units.Mode.HARVEST:
		if reservations[source] == id and quantities[source] > 0:
			reservations[source] = 0
			quantities[source] -= 1
			page.cargo[row] += 1
			harvested += 1
			page.move_to(row, terrain.depots[page.depot_ids[row]], Units.Mode.DEPOT)
		else:
			failed_harvests += 1
			page.modes[row] = Units.Mode.REST
			page.due_ms[row] = at + 1000
	elif mode == Units.Mode.DEPOT:
		stored += page.cargo[row]
		page.cargo[row] = 0
		deliveries += 1
		page.energy[row] = mini(10000, page.energy[row] + 100)
		page.modes[row] = Units.Mode.REST
		page.due_ms[row] = at + 250
	elif mode == Units.Mode.REST:
		resume_work(id)
	elif mode == Units.Mode.MANUAL:
		page.modes[row] = Units.Mode.IDLE
		outcomes.append({"kind": "arrived", "actor": id, "at_ms": at})


func resume_work(id: int) -> void:
	var page: RefCounted = pages[(id - 1) / Units.PAGE_SIZE]
	var row: int = (id - 1) % Units.PAGE_SIZE
	if page.cargo[row] > 0:
		page.move_to(row, terrain.depots[page.depot_ids[row]], Units.Mode.DEPOT)
		return
	var source: int = page.source_ids[row]
	for attempt: int in quantities.size():
		source = (source + 37) % quantities.size()
		if quantities[source] > 0:
			page.source_ids[row] = source
			page.move_to(row, terrain.resources[source], Units.Mode.RESOURCE)
			return
	page.modes[row] = Units.Mode.IDLE


func release(id: int) -> void:
	var page: RefCounted = pages[(id - 1) / Units.PAGE_SIZE]
	var source: int = page.source_ids[(id - 1) % Units.PAGE_SIZE]
	if reservations[source] == id:
		reservations[source] = 0


func kill(id: int, at: int = -1) -> void:
	var page: RefCounted = pages[(id - 1) / Units.PAGE_SIZE]
	var row: int = (id - 1) % Units.PAGE_SIZE
	if page.modes[row] == Units.Mode.DEAD:
		return
	release(id)
	page.health[row] = 0
	page.modes[row] = Units.Mode.DEAD
	environment.remove_mobile(id)
	# A corpse retains its cargo. Death cannot erase or duplicate materials.
	deaths += 1
	outcomes.append({"kind": "death", "actor": id, "at_ms": at if at >= 0 else elapsed_ms})


func command(input: Dictionary) -> Dictionary:
	var receipt: Dictionary = {"seq": input.get("seq", 0), "kind": input.get("kind", ""), "at_ms": elapsed_ms, "ok": false, "reason": "invalid"}
	var id: int = int(input.get("actor", 1))
	if id < 1 or id > actor_count:
		return receipt
	var page: RefCounted = pages[(id - 1) / Units.PAGE_SIZE]
	var row: int = (id - 1) % Units.PAGE_SIZE
	if page.health[row] <= 0:
		receipt.reason = "dead"
		return receipt
	match str(input.get("kind", "")):
		"move":
			var tile: int = int(input.get("tile", -1))
			if tile < 0 or tile >= terrain.blocked.size() or terrain.blocked[tile] != 0:
				receipt.reason = "blocked"
				return receipt
			release(id)
			page.move_to(row, tile, Units.Mode.MANUAL)
		"stop":
			release(id)
			page.modes[row] = Units.Mode.IDLE
		"work":
			release(id)
			resume_work(id)
		"heal":
			if page.potions[row] <= 0 or page.health[row] >= 100:
				receipt.reason = "no_potion_or_full"
				return receipt
			page.potions[row] -= 1
			page.health[row] = mini(100, page.health[row] + 40)
			heals += 1
		"attack":
			var target: int = int(input.get("target", 0))
			if target < 1 or target > actor_count or target == id:
				return receipt
			var victim: RefCounted = pages[(target - 1) / Units.PAGE_SIZE]
			var other: int = (target - 1) % Units.PAGE_SIZE
			if victim.health[other] <= 0 or page.positions[row].distance_to(victim.positions[other]) > 2.0 or attack_due[id - 1] > elapsed_ms:
				receipt.reason = "out_of_reach_or_cooldown"
				return receipt
			attack_due[id - 1] = elapsed_ms + 500
			victim.health[other] = maxi(0, victim.health[other] - 25)
			attacks += 1
			if victim.health[other] == 0:
				kill(target)
		"source":
			var source: int = int(input.get("target", -1))
			if source < 0 or source >= environment.enabled.size():
				return receipt
			environment.enabled[source] = 1 - environment.enabled[source]
			environment.rebuild_static()
		"build":
			var tile: int = int(input.get("tile", -1))
			var kind: int = int(input.get("structure", 1))
			if tile < 0 or tile >= terrain.blocked.size() or kind < 0 or kind > 2:
				return receipt
			if kind == 1:
				if terrain.resources.has(tile) or terrain.depots.has(tile):
					receipt.reason = "reserved_ground"
					return receipt
				for body: RefCounted in pages:
					for position: Vector2 in body.positions:
						if Terrain.index(Vector2i(position)) == tile:
							receipt.reason = "occupied"
							return receipt
			var was_blocked: bool = terrain.blocked[tile] != 0
			var old_rooms: PackedInt32Array = terrain.rooms.duplicate()
			var old_heat: PackedFloat32Array = environment.room_temperature
			terrain.change_structure(tile, kind)
			for lane: RefCounted in lanes:
				lane.graph.set_point_solid(Terrain.cell(tile), kind == 1)
				lane.paths.clear()
			if kind == 1 and not was_blocked:
				for body: RefCounted in pages:
					for local: int in body.routes.size():
						var route: PackedInt32Array = body.routes[local]
						for cursor: int in range(body.route_cursors[local], route.size()):
							if route[cursor] == tile:
								body.routes[local] = PackedInt32Array()
								body.route_cursors[local] = 0
								break
			var next_heat := PackedFloat32Array()
			for room: PackedInt32Array in terrain.room_cells:
				var total: float = 0.0
				for member: int in room:
					var before: int = old_rooms[member]
					total += old_heat[before] if before >= 0 else 22.0
				next_heat.append(total / room.size())
			environment.room_temperature = next_heat
			if was_blocked != (kind == 1):
				environment.rebuild_static()
			topology_revision = terrain.revision
		_:
			return receipt
	receipt.ok = true
	receipt.reason = "accepted"
	return receipt


func counters() -> Dictionary:
	var material: int = stored
	var cargo_total: int = 0
	var distance: float = 0.0
	var paths: int = 0
	var failed_paths: int = 0
	for amount: int in quantities:
		material += amount
	for page: RefCounted in pages:
		distance += page.moved_distance
		paths += page.path_requests
		failed_paths += page.path_failures
		for amount: int in page.cargo:
			cargo_total += amount
	material += cargo_total
	return {"world_ms": elapsed_ms, "actors": actor_count, "alive": actor_count - deaths, "workers": workers,
		"steps": steps, "step_usec": step_usec, "maximum_step_usec": maximum_step_usec,
		"moved_cells": distance, "path_requests": paths, "path_failures": failed_paths,
		"harvested": harvested, "deliveries": deliveries, "stored": stored, "cargo": cargo_total,
		"material": material, "initial_material": initial_material,
		"failed_harvests": failed_harvests, "deaths": deaths, "attacks": attacks, "heals": heals,
		"environment_usec": environment_usec, "units_usec": units_usec, "effects_usec": effects_usec,
		"environment_updates": environment.updates, "rooms": terrain.room_cells.size(),
		"structures": terrain.structures.size(), "static_sources": environment.source_cells.size(),
		"mobile_sources": environment.mobile_units.size()}
