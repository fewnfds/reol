extends RefCounted
## The simulation thread owns this world. Lanes exclusively own unit pages
## during a step; only this owner resolves shared resources and commands.
## No Node, scene callback, global GameClock, or borrowed live-world UI access.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Navigation = preload("res://scripts/sim/kernel/navigation.gd")
const Fields = preload("res://scripts/sim/kernel/environment.gd")
const Batch = preload("res://scripts/sim/execution/batch_execution.gd")
const Objects = preload("res://scripts/sim/kernel/objects.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const Facilities = preload("res://scripts/sim/kernel/facilities.gd")
const Decisions = preload("res://scripts/sim/kernel/decisions.gd")
const Livelihood = preload("res://scripts/sim/kernel/livelihood.gd")
const Nature = preload("res://scripts/sim/kernel/nature.gd")
const DomainOps = preload("res://scripts/sim/kernel/domain_effects.gd")
const Effects = preload("res://scripts/sim/kernel/combat_effects.gd")
const Entities = preload("res://scripts/sim/kernel/combat_entities.gd")
const Reactions = preload("res://scripts/sim/kernel/combat_reactions.gd")
const Pools = preload("res://scripts/sim/kernel/resource_pools.gd")
const Defense = preload("res://scripts/sim/kernel/combat_defense.gd")
const Areas = preload("res://scripts/sim/kernel/combat_areas.gd")
const Implements = preload("res://scripts/sim/kernel/implements.gd")
const Motion = preload("res://scripts/sim/kernel/motion.gd")
const Gate = preload("res://scripts/sim/kernel/action_gate.gd")
const Combat = preload("res://scripts/sim/kernel/combat.gd")
const Society = preload("res://scripts/sim/kernel/society.gd")
const Perception = preload("res://scripts/sim/kernel/perception.gd")
const Sight = preload("res://scripts/sim/kernel/sight.gd")
const Regions = preload("res://scripts/sim/kernel/regions.gd")
const PersonEvents = preload("res://scripts/sim/kernel/person_events.gd")
const STATE_FIELDS: Array = ["elapsed_ms", "actor_count", "initial_material", "harvested", "deliveries", "failed_harvests", "steps", "deaths", "attacks", "heals", "topology_revision", "source_objects", "depot_objects", "reservations", "actions", "work_runs", "next_run", "next_process"]
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const OperationQuery = preload("res://scripts/sim/kernel/operation_query.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const ActivityResults = preload("res://scripts/sim/kernel/activity_results.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Institutions = preload("res://scripts/sim/kernel/institutions.gd")
const Production = preload("res://scripts/sim/kernel/production.gd")
const Knowledge = preload("res://scripts/sim/kernel/knowledge.gd")
const Equipment = preload("res://scripts/sim/kernel/equipment.gd")

class Lane extends RefCounted:
	var pages: Array[RefCounted] = []
	var navigation: RefCounted
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
				page.advance(navigation)
		work_usec += Time.get_ticks_usec() - start

var terrain := Terrain.new()
var environment := Fields.new()
var pages: Array[RefCounted] = []
var lanes: Array[RefCounted] = []
var objects := Objects.new()
var facilities := Facilities.new()
var livelihood := Livelihood.new()
var decisions := Decisions.new()
var nature := Nature.new()
var combat := Combat.new()
var effects := Effects.new()
var entities := Entities.new()
var reactions := Reactions.new()
var pools := Pools.new()
var defense := Defense.new()
var areas := Areas.new()
var implements := Implements.new()
var society := Society.new()
var institutions := Institutions.new()
var perception := Perception.new()
var sight := Sight.new() # Derived shared geometry; observation state is separate.
var regions := Regions.new()
var person_events := PersonEvents.new()
var activity_results := ActivityResults.new()
var actor_slots: Dictionary = {} # External identity -> stable internal body slot.
var source_objects := PackedInt64Array()
var depot_objects := PackedInt64Array()
var reservations: Dictionary = {} # Target identity -> actor identity, owner only.
var actions: Dictionary = {}
var work_runs: Dictionary = {} # Body-work host owns its persistent run identity.
var next_run: int = 1
var next_process: int = 1
var knowledge := Knowledge.new()
var gate := Gate.new()
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
var body_count: int:
	get: return (pages.size() - 1) * Units.PAGE_SIZE + pages.back().ids.size() if not pages.is_empty() else 0
var topology_revision: int = 0
var outcomes: Array[Dictionary] = []
var _topology_edits: Dictionary = {}
var _spatial_edits: Array[Dictionary] = []
var _finishing: Dictionary = {}
var _commit_ms: int = -1
var _motion_begin: int = 0
var _motion_end: int = 0
var topology_usec: int = 0
var preparation_usec: int = 0 # Outer preparation only; nested combat/index timers are separate.
var intervals: int = 0


func initialize(count: int = 1000, requested_workers: int = 4, stress_environment: bool = false) -> void:
	if not Beings.ERRORS.is_empty():
		push_error("Invalid being definitions: " + str(Beings.ERRORS))
		return
	if not Operations.ERRORS.is_empty():
		push_error("Invalid operation definitions: " + str(Operations.ERRORS))
		return
	if not Growth.Defs.ERRORS.is_empty():
		push_error("Invalid growth definitions: " + str(Growth.Defs.ERRORS))
		return
	if not livelihood.Defs.ERRORS.is_empty():
		push_error("Invalid agency definitions: " + str(livelihood.Defs.ERRORS))
		return
	if not institutions.Defs.ERRORS.is_empty():
		push_error("Invalid institution definitions: " + str(institutions.Defs.ERRORS))
		return
	actor_count = count
	terrain.initialize()
	environment.initialize(terrain, count, stress_environment)
	terrain.source_cells = environment.source_cells.duplicate()
	terrain.source_channels = environment.source_channels.duplicate()
	for slot: int in count:
		var id: int = objects.create("actor", "human")
		objects.add(id, "potion", 3)
		actor_slots[id] = slot
	for tile: int in terrain.resources:
		var id: int = objects.create("resource", "wood", tile)
		objects.add(id, "wood", 1000)
		source_objects.append(id)
	var initial_depots: PackedInt32Array = terrain.depots.duplicate()
	terrain.depots.clear()
	for tile: int in initial_depots:
		facilities.create_completed(self, "wood_chest", tile, 0, -1)
	for tile: int in terrain.structures:
		if terrain.enclosures[tile] != 0:
			facilities.create_completed(self, "wood_wall" if terrain.blocked[tile] != 0 else "wood_door", tile)
	for tile: int in terrain.flooring.size():
		if terrain.flooring[tile] != 0:
			facilities.create_completed(self, "wood_floor", tile)
	initial_material = objects.total("wood")
	var pile: int = objects.create("pile", "wood", Terrain.index(Vector2i(178, 186)))
	objects.transfer(source_objects[0], pile, "wood", 50)
	facilities.create_completed(self, "wood_chest", Terrain.index(Vector2i(176, 186)), 0, 100)
	for first: int in range(0, count, Units.PAGE_SIZE):
		var page := Units.new()
		page.initialize(first + 1, mini(Units.PAGE_SIZE, count - first), terrain)
		page.environment = environment
		page.potions.fill(3)
		pages.append(page)
	configure_lanes(requested_workers)
	for id: int in actor_slots: Equipment.rebuild(self, id, false)
	environment.update(0, pages, actor_slots)
	for page: RefCounted in pages:
		page.sample_environment(0.0)
	topology_revision = terrain.revision
	if count < 1000:
		pages[0].positions[0] = Terrain.center(Terrain.index(Vector2i(177, 188)))
	facilities.seed_fixture(self, "long_bed", Terrain.index(Vector2i(176, 182)))
	var stove: int = facilities.seed_fixture(self, "cook_stove", Terrain.index(Vector2i(174, 185)))
	facilities.seed_fixture(self, "water_well", Terrain.index(Vector2i(168, 176)))
	objects.add(stove, "meal", 30)
	var supplies: int = objects.by_tile[Terrain.index(Vector2i(176, 186))][0]
	objects.add(supplies, "grain", 30)
	objects.add(supplies, "water", 30)
	# Temporary playable equipment samples; ordinary NPCs need no gear scan.
	for item: String in ["iron_sword", "iron_sword@2", "short_bow", "willow_staff", "cloth_robe", "travel_boots", "jade_charm@3"]:
		objects.add(1, item, 1)
	objects.equip(1, "iron_sword")
	Equipment.rebuild(self, 1)
	objects.add(supplies, "cloth_robe@2", 1)
	objects.add(supplies, "travel_boots@2", 1)
	flush_topology()
	livelihood.initialize(self)
	nature.initialize(self)
	society.initialize(self)
	regions.initialize(self)
	flush_topology()
	if count >= 24:
		for actor: int in range(count - 3, count + 1):
			release(actor)
			var body_slot: int = actor_slots[actor]
			pages[body_slot / 256].modes[body_slot % 256] = Units.Mode.IDLE
			var slot: int = actor_slots[actor]
			var page: RefCounted = pages[slot / 256]
			page.positions[slot % 256] = Terrain.center(Terrain.index(Vector2i(177 + count - actor, 168)))
			objects.records[actor]["side"] = 1
			objects.records[actor].autonomous = false
			objects.records[actor]["combatant"] = true
			objects.records[actor]["combat_style"] = "trained"
			var weapon: String = "short_bow" if actor % 2 == 0 else "iron_sword"
			objects.add(actor, weapon, 1)
			objects.equip(actor, weapon)
			Equipment.rebuild(self, actor)
	perception.update(self, 0, true)
	knowledge.observe(self, 1, 0)


func state_owners() -> Dictionary:
	# The concrete composition root lists real domains; field selection belongs
	# to each owner. New domains do not require a new serializer implementation.
	return {"world": self, "terrain": terrain, "objects": objects, "environment": environment, "nature": nature, "combat": combat, "effects": effects, "areas": areas, "implements": implements, "perception": perception, "regions": regions, "person_events": person_events, "activity_results": activity_results, "society": society, "institutions": institutions, "knowledge": knowledge, "livelihood": livelihood, "pools": pools, "defense": defense, "reactions": reactions, "entities": entities, "decisions": decisions}

func emit(event: Dictionary) -> void:
	event = preload("res://scripts/sim/kernel/outcome.gd").envelope(event, operation_time())
	outcomes.append(event)
	person_events.accept(event, actor_slots)


func configure_lanes(requested_workers: int) -> void:
	self.requested_workers = requested_workers
	workers = Batch.resolve_workers(requested_workers, pages.size())
	lanes.clear()
	for lane_id: int in maxi(1, workers):
		var lane := Lane.new()
		lane.navigation = Navigation.new(terrain)
		lanes.append(lane)
	for index: int in pages.size():
		lanes[index % lanes.size()].pages.append(pages[index])


func step(milliseconds: int = 50) -> void:
	var start: int = Time.get_ticks_usec()
	var begin: int = elapsed_ms
	var end: int = begin + milliseconds
	combat.projectile_segments = []
	combat.action_segments = []
	combat.reaction_segments = []
	implements.segments = []
	var origins: Array[PackedVector2Array] = []
	var origin_ids: Array[PackedInt64Array] = []
	var traces: Array[Dictionary] = []
	for page: RefCounted in pages:
		origins.append(page.positions.duplicate())
		origin_ids.append(page.ids.duplicate())
		traces.append({})
	while elapsed_ms < end:
		var preparing: int = Time.get_ticks_usec()
		entities.prepare(self, elapsed_ms)
		reactions.prepare(self, elapsed_ms)
		pools.prepare(self, elapsed_ms)
		defense.prepare(self, elapsed_ms)
		effects.prepare(self, elapsed_ms)
		combat.prepare(self, elapsed_ms)
		implements.prepare(self, elapsed_ms)
		preparation_usec += Time.get_ticks_usec() - preparing
		var boundary: int = combat.next_boundary(self, elapsed_ms, mini(end, (elapsed_ms / 50 + 1) * 50))
		boundary = effects.next_boundary(elapsed_ms, boundary)
		boundary = defense.next_boundary(elapsed_ms, boundary)
		boundary = entities.next_boundary(elapsed_ms, boundary)
		boundary = areas.next_boundary(elapsed_ms, boundary)
		boundary = implements.next_boundary(elapsed_ms, boundary)
		boundary = work_boundary(elapsed_ms, boundary)
		boundary = decisions.next_boundary(elapsed_ms, boundary)
		var before: int = elapsed_ms
		_advance_interval(boundary)
		for index: int in pages.size():
			var page: RefCounted = pages[index]
			var positions: PackedVector2Array = page.positions
			var ids: PackedInt64Array = page.ids
			var motion: Dictionary = page.motion
			var trace: Dictionary = traces[index] if index < traces.size() else {}
			if index >= origins.size():
				origins.append(positions.duplicate())
				origin_ids.append(PackedInt64Array())
				traces.append(trace)
			var previous_ids: PackedInt64Array = origin_ids[index]
			var previous_origins: PackedVector2Array = origins[index]
			var count: int = previous_ids.size()
			previous_ids.resize(ids.size())
			previous_origins.resize(ids.size())
			for row: int in ids.size():
				if row >= count or previous_ids[row] != ids[row]:
					previous_ids[row] = ids[row]
					previous_origins[row] = combat.previous[index][row] if index < combat.previous.size() and row < combat.previous[index].size() else positions[row]
					trace.erase(row)
				if not trace.has(row) and positions[row].is_equal_approx(previous_origins[row]): continue
				if not trace.has(row): trace[row] = PackedVector3Array([Vector3(previous_origins[row].x, previous_origins[row].y, 0)])
				var knots: PackedVector3Array = trace[row]
				if motion.has(row):
					for point: Vector3 in motion[row]:
						if point.z <= 0: continue
						knots.append(Vector3(point.x, point.y, (before - begin + point.z * (boundary - before)) / milliseconds))
				else: knots.append(Vector3(positions[row].x, positions[row].y, float(boundary - begin) / milliseconds))
				trace[row] = knots
			origins[index] = previous_origins
			origin_ids[index] = previous_ids
	for index: int in pages.size():
		pages[index].motion = {}
		for row: int in traces[index]:
			if traces[index][row].size() > 2: pages[index].motion[row] = traces[index][row]
	steps += 1
	var cost: int = Time.get_ticks_usec() - start
	step_usec += cost
	maximum_step_usec = maxi(maximum_step_usec, cost)


func _advance_interval(end: int) -> void:
	intervals += 1
	var delta_ms: int = end - elapsed_ms
	for lane: RefCounted in lanes:
		lane.navigation.begin_step()
	combat.before_motion(self)
	for page: RefCounted in pages:
		page.end_ms = end
		page.delta_ms = delta_ms
	var unit_start: int = Time.get_ticks_usec()
	var batch := Batch.new()
	batch.start(lanes, workers)
	batch.finish(true)
	units_usec += Time.get_ticks_usec() - unit_start
	# Capture all owner identities before adopting any candidate. Combat and work
	# share chronological buckets; endpoint navigation failure cannot erase history.
	var effect_start: int = Time.get_ticks_usec()
	var events: Array[Dictionary] = []
	_motion_begin = elapsed_ms
	_motion_end = end
	for page: RefCounted in pages:
		for row: int in page.failures:
			var id: int = page.ids[row]
			ensure_work_binding(id)
			events.append({"event": "world_failure", "actor": id, "at_ms": end, "expected": gate.current(id), "mode": page.modes[row], "route_version": page.route_versions[row]})
		for entry: int in range(0, page.ready.size(), 2):
			var row: int = page.ready[entry]
			var id: int = page.ids[row]
			ensure_work_binding(id)
			events.append({"event": "world_ready", "actor": id, "at_ms": clampi(page.ready[entry + 1], elapsed_ms, end), "expected": gate.current(id), "mode": page.modes[row], "route_version": page.route_versions[row]})
	combat.step(self, elapsed_ms, end, events)
	_commit_ms = -1
	_commit_ms = end
	if end % 50 == 0: nature.pulse(self, end)
	flush_topology()
	effects_usec += Time.get_ticks_usec() - effect_start
	if end % 1000 == 0:
		facilities.Sources.pulse(self, end)
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
			for event: Dictionary in page.environmental_events:
				if event.kind == "needs_changed": decisions.wake(self, event.actor, end, "needs_changed")
				else:
					if event.kind == "thermal_hit" and int(event.damage) > 0 and combat.alive(self, event.actor):
						if Growth.apply_condition(objects.records[event.actor], "thermal_strain", event.cause, end):
							Equipment.rebuild(self, event.actor)
							if objects.records[event.actor].get("autonomous", false): decisions.wake(self, event.actor, end, "condition_changed")
					emit(event)
			for row: int in page.environmental_deaths:
				kill(page.ids[row], end, "cold" if page.body_heat[row] < 0.0 else "heat")
		environment_usec += Time.get_ticks_usec() - env_start
	_commit_ms = end
	pools.prepare(self, end)
	entities.expire(self, end)
	effects.expire(self, end)
	defense.prepare(self, end)
	_commit_ms = -1
	elapsed_ms = end
	perception.update(self, end)
	if end % 1000 == 0: knowledge.pulse(self, end)


func operation_time() -> int:
	return elapsed_ms if _commit_ms < 0 else _commit_ms

func position_at(id: int, at: int = -1) -> Vector2:
	var point: Vector2 = combat.position(self, id)
	var time: int = operation_time() if at < 0 else at
	if not actor_slots.has(id) or combat.previous.is_empty() or _motion_end <= _motion_begin or time < _motion_begin or time > _motion_end: return point
	var slot: int = actor_slots[id]
	if slot / 256 >= combat.previous.size() or slot % 256 >= combat.previous[slot / 256].size(): return point
	return Motion.at(combat.previous[slot / 256][slot % 256], point, pages[slot / 256].motion.get(slot % 256, PackedVector3Array()), float(time - _motion_begin) / (_motion_end - _motion_begin))

func work_boundary(now: int, end: int) -> int:
	for actor: int in actions:
		var slot: int = actor_slots[actor]
		var page: RefCounted = pages[slot / 256]
		if page.modes[slot % 256] == Units.Mode.ACTION and page.due_ms[slot % 256] > now: end = mini(end, page.due_ms[slot % 256])
	for actor: int in work_runs:
		var slot: int = actor_slots[actor]
		var page: RefCounted = pages[slot / 256]
		if page.modes[slot % 256] in [Units.Mode.HARVEST, Units.Mode.REST] and page.due_ms[slot % 256] > now: end = mini(end, page.due_ms[slot % 256])
	return end

func commit_work_event(event: Dictionary, end: int) -> Array[Dictionary]:
	var id: int = event.actor
	var at: int = event.at_ms
	if not actor_slots.has(id) or not gate.matches(id, event.expected) or not combat.alive(self, id): return []
	_commit_ms = at
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / 256]
	var row: int = slot % 256
	if page.modes[row] != event.mode or page.route_versions[row] != event.route_version:
		_commit_ms = -1
		return []
	if event.event == "world_failure":
		if page.modes[row] == Units.Mode.COMBAT_MOVE and combat.engagements.has(id): combat.blocked(self, id, at)
		else:
			var automatic: bool = objects.records[id].get("autonomous", false)
			end_run(id, at, "path_failed")
			clear_navigation(id)
			page.modes[row] = Units.Mode.IDLE
			if automatic: livelihood.after_action(self, id, at)
		emit({"kind": "path_failed", "actor": id, "at_ms": at})
	else: settle(id, at, event.expected)
	var next: Array[Dictionary] = []
	if page.modes[row] in [Units.Mode.ACTION, Units.Mode.HARVEST, Units.Mode.REST] and page.due_ms[row] <= end:
		# A newly created zero/short process must not wait for the next world step.
		next.append({"event": "world_ready", "actor": id, "at_ms": maxi(at, page.due_ms[row]), "expected": gate.current(id), "mode": page.modes[row], "route_version": page.route_versions[row]})
	_commit_ms = -1
	return next

func settle(id: int, at: int, expected: Variant = null) -> void:
	if expected != null and not gate.matches(id, expected): return
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
		var query: Dictionary = OperationQuery.evaluate(Operations.OPERATIONS.harvest, operation_actor(id), operation_target(target))
		if not query.ready:
			end_run(id, at, query.reason, ActivityResults.refused(query.reason))
			clear_navigation(id)
			livelihood.after_action(self, id, at, target)
		elif not facilities.in_range(self, target, position_at(id, at), page.radii[row], "harvest", page.flight[row] > 0):
			end_run(id, at, "out_of_reach")
			clear_navigation(id)
			livelihood.after_action(self, id, at, target)
		elif not reservations.has(target) and objects.amount(target, "wood") > 0:
			reservations[target] = id
			page.modes[row] = Units.Mode.HARVEST
			page.due_ms[row] = at + int(Operations.OPERATIONS.harvest.duration_ms)
		else:
			page.modes[row] = Units.Mode.REST
			page.due_ms[row] = at + 250
	elif mode == Units.Mode.HARVEST:
		var query: Dictionary = OperationQuery.evaluate(Operations.OPERATIONS.harvest, operation_actor(id), operation_target(target))
		var in_range: bool = facilities.in_range(self, target, position_at(id, at), page.radii[row], "harvest", page.flight[row] > 0)
		if query.ready and reservations.get(target, 0) == id and in_range and institutions.acquire_yield(self, id, target, "wood", 1, at) > 0:
			reservations.erase(target)
			_sync_inventory(id)
			harvested += 1
			reactions.submit(self, {"event": "gathered", "actor": id, "target": target, "at_ms": at, "amount": 1, "activation": 0, "position": position_at(id, at)})
			knowledge.refresh(self, id, target, at)
			end_run(id, at, "completed", ActivityResults.completed({"item": "wood", "amount": 1, "source": target, "destination": id}))
			livelihood.think(self, id, at)
		else:
			if reservations.get(target, 0) == id:
				reservations.erase(target)
			failed_harvests += 1
			var reason: String = query.reason if not query.ready else ("out_of_reach" if not in_range else "empty_or_full")
			end_run(id, at, reason, ActivityResults.interrupted(reason) if reason == "out_of_reach" else ActivityResults.refused(reason))
			livelihood.after_action(self, id, at, target)
	elif mode == Units.Mode.REST:
		end_run(id, at, "completed")
		resume_work(id, at)
	elif mode == Units.Mode.MANUAL:
		end_run(id, at, "completed")
		page.modes[row] = Units.Mode.IDLE
		emit({"kind": "arrived", "actor": id, "at_ms": at})
	elif mode == Units.Mode.APPROACH or mode == Units.Mode.ACTION:
		settle_action(id, at)
	elif mode == Units.Mode.EXPLORE:
		livelihood.arrived(self, id, at)
		end_run(id, at, "completed")
		knowledge.observe(self, id, at)
		livelihood.think(self, id, at)
	elif mode == Units.Mode.COMBAT_MOVE:
		page.modes[row] = Units.Mode.IDLE


func resume_work(id: int, at: int = -1) -> void:
	livelihood.think(self, id, at if at >= 0 else operation_time())


func end_run(id: int, at: int = -1, reason: String = "replaced", outcome: Dictionary = {}, resume: bool = true) -> Dictionary:
	ensure_work_binding(id)
	var binding: Dictionary = gate.current(id)
	if binding.is_empty(): return {}
	if not gate.unbind(id, binding.domain, binding.run_id): return {}
	var now: int = at if at >= 0 else operation_time()
	var resume_partner: bool = false
	var result: Dictionary = {}
	var interaction: Dictionary = {}
	match str(binding.domain):
		"combat":
			combat.states.erase(id)
			if reason != "completed": combat.chains.erase(id)
			combat._cut_action(id, now)
		"interaction":
			var action: Dictionary = actions[id]
			interaction = action
			actions.erase(id)
			if reservations.get(action.target, 0) == id: reservations.erase(action.target)
			var final: Dictionary = State.copy(outcome) if not outcome.is_empty() else ActivityResults.interrupted(reason)
			if final.status != "completed": final.facts.merge(facilities.interrupt(self, Operations.domain_action(action), now), true)
			knowledge.outcome(self, id, action.kind, action.target, final.status, final.reason, now, action.has("started_ms"))
			if int(action.get("worked_ms", 0)) > 0: final.facts["worked_ms"] = int(final.facts.get("worked_ms", 0)) + int(action.worked_ms)
			result = activity_results.record(binding.run_id, action.kind, id, action.target, action.get("participants", [id]), now, final)
		"partner":
			var wait: Dictionary = society.waits[id]
			resume_partner = actions.get(wait.actor, {}).get("partner_resume", false)
			society.waits.erase(id)
			if actions.get(wait.actor, {}).get("run_id") == wait.owner_run:
				end_run(wait.actor, now, "partner_left" if combat.alive(self, id) else "target_gone")
				clear_navigation(wait.actor)
		"work":
			work_runs.erase(id)
			if actor_slots.has(id):
				var slot: int = actor_slots[id]
				var target: int = source_objects[pages[slot / 256].source_ids[slot % 256]]
				if reservations.get(target, 0) == id: reservations.erase(target)
				if pages[slot / 256].modes[slot % 256] in [Units.Mode.RESOURCE, Units.Mode.HARVEST]:
					var final: Dictionary = outcome if not outcome.is_empty() else ActivityResults.interrupted(reason)
					knowledge.outcome(self, id, "harvest", target, final.status, final.reason, now, pages[slot / 256].modes[slot % 256] == Units.Mode.HARVEST)
					result = activity_results.record(binding.run_id, "harvest", id, target, [id], now, final)
	if actor_slots.has(id):
		var slot: int = actor_slots[id]
		pages[slot / 256].modes[slot % 256] = Units.Mode.IDLE
	# Evidence is committed before either participant is awakened. Partner waits
	# never publish a second result for the same shared activity.
	if not interaction.is_empty(): society.interrupt(self, interaction, now)
	livelihood.outcome(self, id, binding, result, now, reason)
	decisions.ended(self, id, binding, now, reason, result)
	if resume and resume_partner and objects.records[id].get("autonomous", false) and combat.alive(self, id) and not decisions.records.get(id, {}).get("manual", false) and not decisions.in_combat(id):
		livelihood.after_action(self, id, now)
	emit({"kind": "action_ended", "actor": id, "domain": binding.domain, "run_id": binding.run_id, "result_id": int(result.get("id", 0)), "reason": reason, "at_ms": now})
	return result

func clear_navigation(id: int) -> void:
	if not actor_slots.has(id): return
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / 256]
	page.routes[slot % 256] = PackedVector2Array()
	page.route_cursors[slot % 256] = 0
	page.route_versions[slot % 256] += 1
	page.targets[slot % 256] = page.positions[slot % 256]
	page.direct_velocities[slot % 256] = Vector2.ZERO

func clear_input(id: int) -> void:
	combat.controls.erase(id)
	combat.discard_intent(self, id, operation_time())

func release(id: int, at: int = -1, reason: String = "replaced") -> void:
	# Explicit full command/death reset; ordinary run completion uses end_run.
	end_run(id, at, reason, {}, false)
	combat.chains.erase(id)
	combat.engagements.erase(id)
	decisions.released(id)
	clear_navigation(id)
	clear_input(id)

func ensure_work_binding(id: int) -> void:
	# Bind current body work when an internal/fixture entry has set its mode directly.
	if gate.bindings.has(id) or not actor_slots.has(id): return
	var slot: int = actor_slots[id]
	if pages[slot / 256].modes[slot % 256] not in [Units.Mode.RESOURCE, Units.Mode.HARVEST, Units.Mode.REST, Units.Mode.MANUAL, Units.Mode.EXPLORE]: return
	work_runs[id] = next_run
	next_run += 1
	gate.bind(id, "work", work_runs[id])

func adopt_work(id: int, at: int) -> bool:
	if not Beings.has(objects.records.get(id, {}), "work"): return false
	return adopt_motion(id, at)

func adopt_motion(id: int, at: int) -> bool:
	# The legacy work host also owns walking; motion does not require labor.
	if not gate.check(self, id, at).is_empty(): return false
	end_run(id, at)
	work_runs[id] = next_run
	next_run += 1
	gate.bind(id, "work", work_runs[id])
	decisions.track_host(self, id)
	return true

func set_aptitudes(id: int, values: Dictionary) -> bool:
	if not actor_slots.has(id) or not combat.alive(self, id): return false
	var candidate: Dictionary = objects.records[id].duplicate()
	candidate["aptitudes"] = values.duplicate()
	if not Growth.valid_record(candidate, objects.next_id, operation_time()): return false
	objects.records[id]["aptitudes"] = values.duplicate()
	Equipment.rebuild(self, id)
	if objects.records[id].get("autonomous", false): decisions.wake(self, id, operation_time(), "aptitudes_changed")
	return true

func set_capability_overrides(id: int, changes: Dictionary) -> bool:
	if not actor_slots.has(id) or not combat.alive(self, id): return false
	var candidate: Dictionary = objects.records[id].duplicate()
	if changes.is_empty(): candidate.erase("capability_overrides")
	else: candidate["capability_overrides"] = changes.duplicate()
	if not Beings.valid_record(candidate): return false
	if changes.is_empty(): objects.records[id].erase("capability_overrides")
	else: objects.records[id]["capability_overrides"] = changes.duplicate()
	Equipment.rebuild(self, id, false)
	ensure_work_binding(id)
	var binding: Dictionary = gate.current(id)
	var invalid: bool = false
	if binding.get("domain") == "interaction":
		var operation: String = actions[id].kind
		invalid = not Operations.capability_reason(candidate, operation).is_empty()
	elif binding.get("domain") == "partner": invalid = not Beings.has(candidate, "contact")
	elif binding.get("domain") == "work":
		var slot: int = actor_slots[id]
		invalid = pages[slot / 256].modes[slot % 256] in [Units.Mode.RESOURCE, Units.Mode.HARVEST] and not Beings.has(candidate, "work")
	if not Beings.has(candidate, "work") and objects.records[id].has("commitment"):
		objects.records[id].autonomous = objects.records[id].commitment.get("was_autonomous", false)
		objects.records[id].erase("commitment")
	if invalid:
		end_run(id, operation_time(), "capability_lost")
		clear_navigation(id)
	if objects.records[id].get("autonomous", false): decisions.wake(self, id, operation_time(), "capabilities_changed")
	return true


func kill(id: int, at: int = -1, cause: String = "") -> void:
	if not actor_slots.has(id):
		return
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	if page.modes[row] == Units.Mode.DEAD:
		return
	page.health[row] = 0 # Mark unavailable before participant/target callbacks.
	implements.drop_owner(self, id, at if at >= 0 else operation_time())
	entities.forget_member(self, id, at if at >= 0 else operation_time())
	entities.drop_owner(self, id, at if at >= 0 else operation_time())
	effects.remove_target(self, id, at if at >= 0 else operation_time())
	defense.remove_target(id)
	release(id, at, "actor_dead")
	forget_target(id, at)
	objects.records[id].erase("commitment")
	page.health[row] = 0
	page.tolerance[row] = 0.0
	page.thermal_carry[row] = 0.0
	page.modes[row] = Units.Mode.DEAD
	environment.remove_mobile(id)
	# A corpse retains its cargo. Death cannot erase or duplicate materials.
	decisions.forget(id)
	livelihood.forget(id)
	deaths += 1
	emit({"kind": "death", "actor": id, "at_ms": at if at >= 0 else operation_time(), "cause": cause})


func forget_target(target: int, at: int = -1) -> void:
	var now: int = at if at >= 0 else operation_time()
	effects.remove_source(self, target, now)
	# Rare structural deletion cleans cold dependents immediately, including
	# save-between-removal-and-arrival. No per-step scan for missing objects.
	for actor: int in actions.keys():
		if not actions.has(actor) or _finishing.get(actor) == actions[actor].run_id: continue
		if actions[actor].target == target:
			var automatic: bool = objects.records[actor].get("autonomous", false) and not decisions.records.get(actor, {}).get("manual", false)
			end_run(actor, now, "target_gone")
			clear_navigation(actor)
			var slot: int = actor_slots[actor]
			pages[slot / Units.PAGE_SIZE].modes[slot % Units.PAGE_SIZE] = Units.Mode.IDLE
			if automatic:
				livelihood.after_action(self, actor, now)
	institutions.Access.forget_target(institutions, self, target)
	reservations.erase(target)


func register_depot(id: int) -> void:
	if depot_objects.has(id): return
	depot_objects.append(id)
	terrain.depots.append(int(objects.records[id].tile))


func remove_static(id: int, at: int = -1) -> bool:
	# Cross-domain removal is explicit; Objects only erases identity and indexes.
	var record: Dictionary = objects.records.get(id, {})
	if record.is_empty() or int(record.tile) < 0 or record.kind in ["actor", "plant", "resource"] or not objects.can_remove(id): return false
	forget_target(id, at)
	facilities.uninstall(self, record)
	var depot: int = depot_objects.find(id)
	if depot >= 0:
		depot_objects.remove_at(depot)
		terrain.depots.remove_at(depot)
	regions.forget(id)
	return objects.remove_empty(id)


func command(input: Dictionary) -> Dictionary:
	var receipt: Dictionary = _command(input)
	if actor_slots.has(int(input.get("actor", 1))): person_events.command(input, receipt)
	return receipt

func _command(input: Dictionary) -> Dictionary:
	var receipt: Dictionary = {"seq": input.get("seq", 0), "kind": input.get("kind", ""), "at_ms": elapsed_ms, "ok": false, "reason": "invalid"}
	if input.get("kind") == "action_trace":
		reactions.tracing = not reactions.tracing
		if not reactions.tracing: reactions.trace.clear()
		receipt.ok = true
		receipt.reason = "trace_enabled" if reactions.tracing else "trace_disabled"
		return receipt
	var id: int = int(input.get("actor", 1))
	if not actor_slots.has(id):
		return receipt
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	if page.health[row] <= 0:
		receipt.reason = "dead"
		return receipt
	if elapsed_ms < int(combat.status.get(id, {}).get("stun_until", 0)) and input.get("kind", "") not in ["action", "heal", "save", "load"]:
		receipt.reason = "stunned"
		return receipt
	if combat.states.has(id) and elapsed_ms < combat.Defs.end_ms(combat.states[id]) and input.get("kind", "") not in ["action", "heal", "save", "load"]:
		receipt.reason = "action_committed"
		return receipt
	var operation_id: String = str(input.get("kind", ""))
	if operation_id == "continue_build": operation_id = "construct"
	if Operations.OPERATIONS.has(operation_id) and input.get("kind") not in ["construct", "take", "put"]:
		var request: Dictionary = input.duplicate()
		request.kind = operation_id
		var reason: String = execute_operation(id, request)
		receipt.ok = reason in ["accepted", "completed"]
		receipt.reason = reason
		return receipt
	match str(input.get("kind", "")):
		"journey":
			if not input.get("region") is int:
				return receipt
			var tile: int = regions.destination(int(input.get("region", 0)))
			if tile < 0:
				return receipt
			var point: Vector2 = terrain.project_point(Terrain.center(tile), page.radii[row], page.flight[row] > 0)
			if point.x < 0:
				receipt.reason = "destination_blocked"
				return receipt
			release(id)
			objects.records[id].autonomous = false
			decisions.suspend(self, id)
			adopt_motion(id, elapsed_ms)
			page.move_to(row, point, Units.Mode.MANUAL)
		"ability":
			var reason: String = execute_operation(id, {"kind": "wood_mend", "target": id})
			receipt.ok = reason == "completed"
			receipt.reason = "ability_used" if receipt.ok else reason
			if receipt.ok:
				emit({"kind": "ability_used", "actor": id, "at_ms": elapsed_ms})
			return receipt
		"action":
			var reason: String = combat.request(self, id, str(input.get("button", "primary")), input.get("aim", page.aims[row]), input.get("move", Vector2.ZERO), -1, input.get("point", Vector2(-1, -1)), int(input.get("target", 0)))
			if reason in ["started", "buffered"]: decisions.suspend(self, id)
			receipt.ok = reason in ["started", "buffered"]
			receipt.reason = reason
			return receipt
		"body":
			var radius: float = 0.9 if input.get("large", false) else 0.35
			var flight: int = clampi(int(input.get("flight", 0)), 0, 1)
			if not terrain.can_stand(page.positions[row], radius, flight > 0):
				receipt.reason = "body_does_not_fit_here"
				return receipt
			release(id)
			page.flight[row] = flight
			page.radii[row] = radius
			page.modes[row] = Units.Mode.IDLE
			if objects.records[id].get("autonomous", false): livelihood.after_action(self, id, elapsed_ms)
		"move":
			var point: Vector2 = _command_point(input, page, row)
			if point.x < 0:
				receipt.reason = "blocked"
				return receipt
			release(id)
			objects.records[id].autonomous = false
			decisions.suspend(self, id)
			adopt_motion(id, elapsed_ms)
			page.move_to(row, point, Units.Mode.MANUAL)
			receipt["position"] = point
		"interrupt":
			release(id)
			page.modes[row] = Units.Mode.IDLE
			objects.records[id].autonomous = false
			decisions.suspend(self, id)
		"work":
			if not Beings.has(objects.records[id], "work"):
				receipt.ok = false
				receipt.reason = "body_cannot_work"
				return receipt
			release(id)
			objects.records[id].erase("commitment")
			objects.records[id].autonomous = true
			decisions.resume(self, id, elapsed_ms)
			knowledge.observe(self, id, elapsed_ms)
			livelihood.think(self, id, elapsed_ms)
			decisions.prepare(self, elapsed_ms)
		"heal":
			if objects.amount(id, "potion", objects.Stock.right(id)) <= 0 or page.health[row] >= page.max_health[row]:
				receipt.reason = "no_potion_or_full"
				return receipt
			objects.consume(id, {"potion": 1}, objects.Stock.right(id))
			_sync_inventory(id)
			combat.heal(self, id, id, 40, elapsed_ms)
			heals += 1
			emit({"kind": "healed", "actor": id, "at_ms": elapsed_ms})
		"equip", "unequip":
			if (combat.states.has(id) and elapsed_ms < combat.Defs.end_ms(combat.states[id])) or elapsed_ms < int(combat.status.get(id, {}).get("last_damage_ms", -2000)) + 1500:
				receipt.reason = "in_combat"
				return receipt
			var item: String = str(input.get("item", ""))
			var gear_slot: String = str(input.get("slot", ""))
			var right: Dictionary = institutions.equipment_right(self, id, item) if input.kind == "equip" else {}
			var reason: String = (objects.equip(id, item, right) if not right.is_empty() else "no_authorized_equipment") if input.kind == "equip" else objects.unequip(id, gear_slot)
			receipt.ok = reason in ["equipped", "unequipped"]
			receipt.reason = reason
			if receipt.ok:
				Equipment.rebuild(self, id)
				combat.chains.erase(id)
				combat.discard_intent(self, id, elapsed_ms)
				emit({"kind": reason, "actor": id, "item": item, "slot": gear_slot, "at_ms": elapsed_ms})
			return receipt
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
			var actor_reason: String = OperationQuery.readiness(Operations.OPERATIONS.construct, operation_actor(id))
			if not actor_reason.is_empty():
				receipt.reason = actor_reason
				return receipt
			var result: Dictionary = facilities.blueprint(self, id, str(input.get("definition", "wood_wall")), int(input.get("tile", -1)), int(input.get("facing", 0)), int(input.get("organization", 0)))
			if result.reason != "accepted":
				receipt.reason = result.reason
				return receipt
			receipt["target"] = result.target
			receipt["placed"] = true
			var reason: String = begin_interaction(id, {"kind": "construct", "target": result.target})
			if reason != "accepted":
				receipt.ok = true # Placement committed; dispatch is a separate outcome.
				receipt.reason = "placed_waiting"
				receipt["dispatch_reason"] = reason
				return receipt
		"plant":
			var actor_reason: String = OperationQuery.readiness(Operations.OPERATIONS.sow, operation_actor(id))
			if not actor_reason.is_empty():
				receipt.reason = actor_reason
				return receipt
			var result: Dictionary = nature.plant_site(self, id, str(input.get("definition", "perennial_herb")), int(input.get("tile", -1)), int(input.get("organization", 0)))
			if result.reason != "accepted":
				receipt.reason = result.reason
				return receipt
			receipt["target"] = result.target
			receipt["placed"] = true
			var reason: String = begin_interaction(id, {"kind": "sow", "target": result.target})
			if reason != "accepted":
				receipt.ok = true
				receipt.reason = "placed_waiting"
				receipt["dispatch_reason"] = reason
				return receipt
		"weather":
			environment.weather_override = clampi(int(input.get("weather", -1)), -1, 3)
		"drop":
			var item: String = str(input.get("item", "wood"))
			var count: int = mini(int(input.get("amount", 10)), objects.amount(id, item))
			if count <= 0:
				receipt.reason = "empty"
				return receipt
			release(id)
			page.modes[row] = Units.Mode.IDLE
			var pile: int = objects.create("pile", item, Terrain.index(Vector2i(page.positions[row])))
			var personal: int = objects.transfer(id, pile, item, count, objects.Stock.right(id))
			if personal < count: objects.transfer(id, pile, item, count - personal)
			_sync_inventory(id)
			if objects.records[id].get("autonomous", false): livelihood.after_action(self, id, elapsed_ms)
		"build":
			var tile: int = int(input.get("tile", -1))
			var kind: int = int(input.get("structure", 1))
			if tile < 0 or tile >= terrain.blocked.size() or kind < 0 or kind > 2:
				return receipt
			for object: int in objects.by_tile.get(tile, []):
				if objects.records[object].kind not in ["wall", "door", "pile", "floor", "roof"]:
					receipt.reason = "occupied"
					return receipt
			if kind == 1:
				if terrain.resources.has(tile) or terrain.depots.has(tile):
					receipt.reason = "reserved_ground"
					return receipt
				for body: RefCounted in pages:
					for local: int in body.ids.size():
						if body.ids[local] > 0 and body.flight[local] == 0 and _body_overlaps_tile(body.positions[local], body.radii[local], tile):
							receipt.reason = "occupied"
							return receipt
			for object: int in objects.by_tile.get(tile, []).duplicate():
				if objects.records[object].kind in ["wall", "door"]:
					facilities.demolish(self, object)
			if kind > 0:
				facilities.create_completed(self, "wood_wall" if kind == 1 else "wood_door", tile)
			queue_structure(tile, kind == 1, kind > 0, kind == 0)
		_:
			return receipt
	receipt.ok = true
	receipt.reason = "accepted"
	return receipt


func _command_point(input: Dictionary, page: RefCounted, row: int) -> Vector2:
	var point := Vector2(-1, -1)
	if input.has("position"):
		if not input.position is Vector2: return point
		point = input.position
	else:
		var tile: int = int(input.get("tile", -1))
		if tile >= 0 and tile < terrain.blocked.size(): point = Terrain.center(tile)
	if not point.is_finite() or point.x < 0 or point.y < 0 or point.x >= Terrain.SIZE or point.y >= Terrain.SIZE:
		return Vector2(-1, -1)
	return terrain.project_point(point, page.radii[row], page.flight[row] > 0)


static func _body_overlaps_tile(point: Vector2, radius: float, tile: int) -> bool:
	var low := Vector2(Terrain.cell(tile))
	# The same conservative square footprint as motion clearance.
	return point.x + radius > low.x and point.x - radius < low.x + 1 and point.y + radius > low.y and point.y - radius < low.y + 1


func counters() -> Dictionary:
	var material: int = objects.total("wood")
	var cargo_total: int = 0
	var distance: float = 0.0
	var paths: int = 0
	var failed_paths: int = 0
	var alive: int = 0
	var modes := PackedInt32Array()
	modes.resize(Units.Mode.size())
	var stationary_combatants: int = 0
	for actor: int in combat.engagements:
		var slot: int = actor_slots[actor]
		stationary_combatants += int(pages[slot / 256].modes[slot % 256] == Units.Mode.IDLE)
	var navigation_geometry: int = 0
	var navigation_search: int = 0
	var navigation_direct: int = 0
	var navigation_cached: int = 0
	var navigation_waits: int = 0
	for lane: RefCounted in lanes:
		navigation_geometry += lane.navigation.geometry_usec
		navigation_search += lane.navigation.search_usec
		navigation_direct += lane.navigation.direct
		navigation_cached += lane.navigation.cache_hits
		navigation_waits += lane.navigation.waits
		paths += lane.navigation.searches
	for page: RefCounted in pages:
		distance += page.moved_distance
		failed_paths += page.path_failures
		for amount: int in page.cargo:
			cargo_total += amount
		for row: int in page.health.size():
			alive += int(page.ids[row] > 0 and page.health[row] > 0 and Beings.population_member(objects.records[page.ids[row]]))
		for mode: int in page.modes: modes[mode] += 1
	return {"world_ms": elapsed_ms, "actors": actor_count, "alive": alive, "workers": workers, "mode_counts": modes, "stationary_combatants": stationary_combatants,
		"steps": steps, "step_usec": step_usec, "maximum_step_usec": maximum_step_usec,
		"moved_cells": distance, "path_requests": paths, "path_failures": failed_paths,
		"navigation_geometry_usec": navigation_geometry, "navigation_search_usec": navigation_search,
		"navigation_direct": navigation_direct, "navigation_cached": navigation_cached,
		"navigation_waits": navigation_waits,
		"harvested": harvested, "deliveries": deliveries, "stored": stored, "cargo": cargo_total,
		"material": material, "initial_material": initial_material,
		"failed_harvests": failed_harvests, "deaths": deaths, "attacks": attacks, "heals": heals,
		"environment_usec": environment_usec, "units_usec": units_usec, "effects_usec": effects_usec,
		"environment_updates": environment.updates, "rooms": terrain.room_cells.size(),
		"structures": terrain.structures.size(), "static_sources": environment.source_cells.size(),
		"mobile_sources": environment.mobile_units.size(), "objects": objects.records.size(), "transfers": objects.transfers,
		"decisions": livelihood.decisions, "observations": knowledge.observations, "decision_usec": livelihood.decision_usec, "observe_usec": knowledge.observe_usec, "topology_usec": topology_usec,
		"facility_completions": facilities.completed.duplicate(), "plants": nature.ids.size(), "plant_evaluations": nature.evaluations, "plant_transitions": nature.transitions, "plant_collections": nature.collections, "nature_usec": nature.work_usec, "calendar": environment.calendar(), "unit_decisions": decisions.evaluations, "unit_decision_usec": decisions.work_usec, "combatants": combat.engagements.size(), "projectiles": combat.bolts.size(), "shots": combat.shots, "hits": combat.hits, "combat_usec": combat.work_usec, "combat_prepare_usec": combat.prepare_usec, "combat_resolve_usec": combat.resolve_usec, "combat_collect_usec": combat.collect_usec, "combat_damage_usec": combat.damage_usec, "combat_slices": combat.slices, "melee_candidates": combat.melee_candidates, "melee_tests": combat.melee_tests, "combat_repaths": combat.repaths, "combat_resumed": combat.resumed,
		"perception_usec": perception.work_usec, "sight_observers": combat.scan.observer_count,
		"sight_candidates": combat.scan.candidates, "sight_queries": combat.scan.queries,
		"sight_index_usec": combat.scan.index_usec, "sight_batch_usec": combat.scan.batch_usec,
		"sight_sync_usec": sight.sync_usec, "sight_rebuilds": sight.rebuilds,
		"sight_parallel_batches": combat.scan.parallel_batches, "sight_thread_ids": combat.scan.thread_ids.keys()}


func _sync_inventory(id: int) -> void:
	if not actor_slots.has(id): return
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	page.cargo[row] = objects.amount(id, "wood") # Display summaries, not inventory authority.
	page.potions[row] = objects.amount(id, "potion")


func begin_transfer(id: int, input: Dictionary) -> String:
	if not actor_slots.has(id): return "unsupported_carrier"
	var operation: Dictionary = Operations.OPERATIONS.get(input.get("kind", ""), {})
	if operation.is_empty(): return "unknown_operation"
	if operation.executor != "transfer": return "invalid_transfer"
	if not institutions.transfer_context_valid(input): return "invalid_transfer_context"
	var admission: String = gate.check(self, id, operation_time())
	if not admission.is_empty(): return admission
	var target: int = int(input.get("target", 0))
	var context: Dictionary = input.duplicate()
	context["item"] = input.get("item", "wood")
	var query: Dictionary = OperationQuery.evaluate(operation, operation_actor(id), operation_target(target), context)
	if not query.ready: return query.reason
	var kind: String = operation.handler
	var item: String = str(input.get("item", "wood"))
	var count: int = int(input.get("amount", 10))
	var source: int = target if kind == "take" else id
	if count <= 0 or objects.goods_amount(source, item, {}, kind == "take" and actor_slots.has(source) and not combat.alive(self, source)) <= 0:
		return "empty"
	var destination: int = id if kind == "take" else target
	if objects.records[destination].capacity >= 0 and objects.count_inventory(destination) >= objects.records[destination].capacity:
		return "full"
	var request: Dictionary = input.duplicate()
	request["item"] = item
	request["amount"] = count
	return begin_interaction(id, request)

func operation_actor(id: int) -> Dictionary:
	if not actor_slots.has(id): return {}
	var access: Dictionary = institutions.access_view(self, id)
	var available: Array = institutions.bundles(self, id, access)
	var record: Dictionary = objects.records[id]
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / 256]
	var result: Dictionary = {"id": id, "hp": page.health[slot % 256], "max_hp": page.max_health[slot % 256], "energy": page.energy[slot % 256],
		"at_ms": operation_time(),
		"qi": int(record.get("qi", 0)), "inventory": objects.usable_summary(id), "methods": State.copy(record.get("methods", {})),
		"carried": objects.inventory_summary(id), "readable": institutions.readable(self, id, available), "bundles": available, "returns": institutions.returns(self, id),
		"task_access": {int(record.commitment.target): ["construct"]} if record.get("commitment", {}).get("kind") == "construct" else {},
		"abilities": Growth.abilities(record), "body_capabilities": Beings.capabilities(record), "pools": State.copy(pools.records.get(id, {})), "admission_reason": gate.check(self, id, operation_time())}
	result.merge(access, true)
	return result

func operation_target(id: int) -> Dictionary:
	if not objects.records.has(id): return {}
	var record: Dictionary = objects.records[id]
	var result: Dictionary = {"id": id, "kind": record.kind, "definition": record.definition, "tile": record.tile,
		"inventory": objects.goods_summary(id, actor_slots.has(id) and not combat.alive(self, id)), "owner": int(record.owner), "organization": int(record.organization), "capacity": record.capacity, "sapient": record.get("sapient", false), "guest": int(record.get("guest", 0))}
	result["access_dependencies"] = facilities.access_dependencies(self, id)
	result["process"] = Production.view(record)
	if record.kind != "actor": result["services"] = institutions.Access.service_flags(institutions, id)
	if record.kind != "actor": result["contents"] = objects.public_contents(id)
	if record.has("stage"): result["stage"] = record.stage
	if actor_slots.has(id):
		var slot: int = actor_slots[id]
		result["hp"] = pages[slot / 256].health[slot % 256]
	return result

func execute_operation(id: int, input: Dictionary) -> String:
	var operation: Dictionary = Operations.OPERATIONS.get(input.get("kind", ""), {})
	if operation.is_empty(): return "unknown_operation"
	if operation.executor == "transfer": return begin_transfer(id, input)
	if operation.executor == "work_source": return "unsupported_host"
	if operation.executor != "instant": return begin_interaction(id, input)
	var admission: String = gate.check(self, id, operation_time())
	if not admission.is_empty(): return admission
	if not input.get("target", id) is int or int(input.get("target", id)) != id: return "invalid_target"
	var query: Dictionary = OperationQuery.evaluate(operation, operation_actor(id), operation_target(id))
	if not query.ready: return query.reason
	if not Costs.pay(self, id, operation.costs): return "insufficient_resource"
	var activation: int = combat.next_activation
	combat.next_activation += 1
	effects.apply_bundle(self, id, id, activation, "", operation.effects, operation_time(), 0, "activation")
	var run_id: int = next_run
	next_run += 1
	activity_results.record(run_id, operation.id, id, id, [id], operation_time(), ActivityResults.completed({"activation": activation, "paid": Costs.normalized(operation.costs)}))
	emit({"kind": "operation_completed", "actor": id, "target": id, "operation": operation.id, "activation": activation, "at_ms": operation_time()})
	return "completed"


func begin_interaction(id: int, input: Dictionary) -> String:
	if not actor_slots.has(id): return "unsupported_carrier"
	var operation: Dictionary = Operations.OPERATIONS.get(input.get("kind", ""), {})
	if operation.is_empty(): return "unknown_operation"
	if operation.executor in ["instant", "work_source"]: return "unsupported_host"
	if operation.handler in ["gather", "collect_source"] and input.has("amount") and (not input.amount is int or input.amount <= 0 or input.amount > 10000): return "invalid_amount"
	var capability_reason: String = Operations.capability_reason(objects.records.get(id, {}), str(input.kind))
	if not capability_reason.is_empty(): return capability_reason
	var admission: String = gate.check(self, id, operation_time())
	if not admission.is_empty(): return admission
	var target: int = int(input.get("target", 0))
	if not objects.records.has(target):
		return "invalid_target"
	var context: Dictionary = input.duplicate()
	context["help_target"] = int(input.get("task_target", 0))
	var query: Dictionary = OperationQuery.evaluate(operation, operation_actor(id), operation_target(target), context, facilities.definitions)
	if not query.ready: return query.reason
	if operation.executor == "transfer" and (not input.get("item") is String or not preload("res://scripts/sim/kernel/items.gd").valid(input.item) or not input.get("amount") is int or input.amount <= 0): return "invalid_transfer"
	if operation.executor == "transfer" and not institutions.transfer_context_valid(input): return "invalid_transfer_context"
	if operation.executor == "society" and not society.contact_reason(self, Operations.domain_action(input)).is_empty():
		return "not_available_for_contact"
	if objects.records[target].tile < 0 and not actor_slots.has(target):
		return "invalid_target"
	if operation.handler == "tend":
		var reason: String = DomainOps.check(self, id, target, "tend")
		if not reason.is_empty(): return reason
	var exclusive: bool = operation.exclusive
	if exclusive and reservations.has(target) and reservations[target] != id and input.get("autonomous", false):
		return "target_busy"
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	var point: Vector2 = facilities.interaction_point(self, target, page.positions[row], page.radii[row], page.flight[row] > 0, operation.handler)
	if point.x < 0:
		return "no_operation_place"
	release(id)
	actions[id] = input.duplicate(true)
	if not operation.recipe.is_empty():
		actions[id]["expected_process"] = int(objects.records[target].get("process", {}).get("id", 0))
		actions[id]["expected_run"] = int(actions.get(reservations.get(target, 0), {}).get("run_id", 0)) if actions[id].expected_process == 0 else 0
	actions[id]["run_id"] = next_run
	actions[id]["participants"] = [id]
	next_run += 1
	gate.bind(id, "interaction", actions[id].run_id)
	if exclusive and not reservations.has(target):
		reservations[target] = id
	if operation.executor == "society" and reservations.get(target, 0) == id:
		society.invite(self, id, actions[id])
	page.move_to(row, point, Units.Mode.APPROACH)
	decisions.track_host(self, id)
	return "accepted"


func settle_action(id: int, at: int) -> void:
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	if not actions.has(id):
		page.modes[row] = Units.Mode.IDLE
		return
	var action: Dictionary = actions[id]
	var operation: Dictionary = Operations.OPERATIONS[action.kind]
	var handler: String = operation.handler
	var target: int = action.target
	var stale_construction: bool = handler == "construct" and objects.records.get(target, {}).get("kind", "") != "blueprint"
	if not objects.records.has(target) or (handler != "take" and actor_slots.has(target) and not combat.alive(self, target)) or stale_construction:
		var autonomous: bool = action.get("autonomous", false)
		end_run(id, at, "unavailable" if stale_construction else "target_gone")
		clear_navigation(id)
		page.modes[row] = Units.Mode.IDLE
		emit({"kind": "unavailable" if stale_construction else "target_gone", "actor": id, "target": target, "action": action.kind, "at_ms": at})
		if autonomous:
			livelihood.after_action(self, id, at, target)
		return
	var context: Dictionary = action.duplicate()
	context["help_target"] = int(action.get("task_target", 0))
	var query: Dictionary = OperationQuery.evaluate(operation, operation_actor(id), operation_target(target), context, facilities.definitions)
	if query.ready and operation.executor == "society":
		query.reason = society.contact_reason(self, Operations.domain_action(action))
		query.ready = query.reason.is_empty()
	if not query.ready:
		var autonomous: bool = action.get("autonomous", false)
		end_run(id, at, query.reason, ActivityResults.refused(query.reason))
		clear_navigation(id)
		if autonomous: livelihood.after_action(self, id, at, target)
		return
	if not facilities.in_range(self, target, position_at(id, at), page.radii[row], handler, page.flight[row] > 0):
		var autonomous: bool = action.get("autonomous", false)
		end_run(id, at, "out_of_reach")
		clear_navigation(id)
		page.modes[row] = Units.Mode.IDLE
		emit({"kind": "out_of_reach", "actor": id, "target": target, "action": action.kind, "at_ms": at})
		if autonomous:
			livelihood.after_action(self, id, at, target)
		return
	if page.modes[row] == Units.Mode.APPROACH:
		var exclusive: bool = operation.exclusive
		if exclusive and reservations.has(target) and reservations[target] != id:
			if action.get("autonomous", false):
				end_run(id, at, "target_busy", ActivityResults.refused("target_busy"))
				clear_navigation(id)
				livelihood.after_action(self, id, at, target)
				return
			page.modes[row] = Units.Mode.ACTION
			page.due_ms[row] = at + 250
			action["waiting"] = true
			return
		if exclusive:
			reservations[target] = id
		if not operation.recipe.is_empty():
			var production_reason: String = Production.start(self, id, action, at)
			if production_reason != "started":
				var autonomous: bool = action.get("autonomous", false)
				end_run(id, at, production_reason, ActivityResults.refused(production_reason))
				clear_navigation(id)
				if autonomous: livelihood.after_action(self, id, at, target)
				return
		if handler == "construct":
			# Navigation for this slice has already run. Acquire the footprint at
			# its endpoint so no precomputed later movement can enter a new solid.
			if at < _motion_end:
				page.modes[row] = Units.Mode.ACTION
				page.due_ms[row] = _motion_end
				action["waiting"] = true
				return
			if facilities.start_construction(self, target, at) != "started":
				page.modes[row] = Units.Mode.ACTION
				page.due_ms[row] = at + 250
				action["waiting"] = true
				return
		if operation.executor == "society" and not action.get("partner_waiting", false):
			society.invite(self, id, action)
		if operation.executor == "society":
			var participation: String = society.participation_reason(self, id, action, at)
			if not participation.is_empty():
				var autonomous: bool = action.get("autonomous", false)
				end_run(id, at, participation, ActivityResults.refused(participation))
				clear_navigation(id)
				if autonomous: livelihood.after_action(self, id, at, target)
				return
			action["participants"] = society.participants(id, action)
		page.modes[row] = Units.Mode.ACTION
		action["started_ms"] = at
		var facing: Vector2 = position_at(id, at).direction_to(combat.position(self, target))
		if not facing.is_zero_approx(): page.aims[row] = facing
		var duration: int = operation.duration_ms if operation.duration_ms >= 0 else maxi(1, int(objects.records[target].get("remaining_ms", 1)))
		if not operation.recipe.is_empty(): duration = int(objects.records[target].process.remaining_ms)
		action["base_work_ms"] = duration
		action["scheduled_ms"] = Growth.duration_ms(objects.records[id], operation, duration)
		page.due_ms[row] = at + int(action.scheduled_ms)
		return
	if action.get("waiting", false):
		action.erase("waiting")
		page.modes[row] = Units.Mode.APPROACH
		settle_action(id, at)
		return
	if operation.executor != "transfer":
		var outcome: Dictionary
		if operation.executor == "society":
			var participation: String = society.participation_reason(self, id, action, at)
			if not participation.is_empty():
				var autonomous: bool = action.get("autonomous", false)
				end_run(id, at, participation, ActivityResults.refused(participation))
				clear_navigation(id)
				if autonomous: livelihood.after_action(self, id, at, target)
				return
		_finishing[id] = action.run_id
		if handler == "demolish":
			outcome = facilities.demolish_result(self, target, at, id)
		elif operation.executor == "nature":
			outcome = nature.commit(self, id, Operations.domain_action(action), at)
		elif operation.executor == "society":
			outcome = society.commit(self, id, action, at)
		else:
			outcome = facilities.commit(self, id, Operations.domain_action(action), at)
		_finishing.erase(id)
		if not gate.matches(id, {"domain": "interaction", "run_id": action.run_id}): return
		if outcome.reason == "occupied" and handler == "construct":
			var progress: Dictionary = facilities.interrupt(self, Operations.domain_action(action), at)
			action["worked_ms"] = int(action.get("worked_ms", 0)) + int(progress.get("worked_ms", 0))
			action.erase("started_ms")
			action["waiting"] = true
			page.due_ms[row] = at + 250
			return
		var reason: String = outcome.reason
		var autonomous: bool = action.get("autonomous", false)
		end_run(id, at, reason, outcome)
		clear_navigation(id)
		page.modes[row] = Units.Mode.IDLE
		emit({"kind": reason, "actor": id, "target": target, "action": action.kind, "at_ms": at})
		if autonomous:
			livelihood.after_action(self, id, at, target)
		return
	var source: int = target if handler == "take" else id
	var destination: int = id if handler == "take" else target
	var transferred: Dictionary = institutions.move_goods(self, id, target, action.item, action.amount, handler, action, at)
	if actor_slots.has(source) and source != id: _sync_inventory(source)
	var amount: int = int(transferred.facts.get("amount", 0))
	if objects.records.get(source, {}).get("kind", "") == "pile":
		_finishing[id] = action.run_id
		remove_static(source, at)
		_finishing.erase(id)
	var autonomous: bool = action.get("autonomous", false)
	_sync_inventory(id)
	end_run(id, at, transferred.reason, transferred)
	clear_navigation(id)
	page.modes[row] = Units.Mode.IDLE
	emit({"kind": "transferred" if amount > 0 else "empty_or_full", "actor": id, "target": target, "action": action.kind, "item": action.item, "at_ms": at, "amount": amount})
	if autonomous:
		if handler == "put" and amount > 0:
			deliveries += 1
		livelihood.after_action(self, id, at, target)


func describe(id: int) -> Dictionary:
	if not objects.records.has(id):
		return {}
	var result: Dictionary = State.copy(objects.records[id])
	result.erase("stock")
	result.erase("materials")
	result.erase("work_stock")
	result["process"] = Production.view(objects.records[id], actions.get(reservations.get(id, 0), {}), elapsed_ms)
	if objects.records[id].has("work_stock"): result["work_inventory"] = objects.Stock.summary(objects.records[id].work_stock)
	if not objects.records[id].get("work_stock", {}).is_empty():
		var right: Dictionary = objects.Stock.attribution(objects.records[id].work_stock.values()[0][0])
		result["work_attribution"] = {"owner": right.owner, "organization": right.organization, "organization_name": str(institutions.organizations.get(int(right.organization), {}).get("name", ""))}
	result["at_ms"] = elapsed_ms
	result["inventory"] = objects.inventory_summary(id)
	result["access_dependencies"] = facilities.access_dependencies(self, id)
	if result.kind != "actor": result["services"] = institutions.Access.service_flags(institutions, id)
	if actor_slots.has(id) and not combat.alive(self, id): result.inventory = objects.goods_summary(id, true)
	result["stock_organizations"] = []
	for right: Dictionary in objects.groups(id, actor_slots.has(id) and not combat.alive(self, id)):
		if right.organization > 0 and not result.stock_organizations.has(right.organization): result.stock_organizations.append(right.organization)
	if result.kind == "actor": result["equipment"] = objects.equipment_summary(id)
	if result.organization > 0: result["organization_name"] = str(institutions.organizations.get(int(result.organization), {}).get("name", ""))
	if result.tile >= 0:
		var spec: Dictionary = facilities.definitions.get(result.definition, {})
		result["work_cells"] = {}
		for operation: String in spec.get("work_positions", {}):
			result.work_cells[operation] = facilities.Positions.cells(self, id, operation)
	if actor_slots.has(id):
		var slot: int = actor_slots[id]
		var page: RefCounted = pages[slot / Units.PAGE_SIZE]
		var row: int = slot % Units.PAGE_SIZE
		result.merge({"hp": page.health[row], "energy": page.energy[row], "hunger": page.hunger[row],
			"tolerance": page.tolerance[row], "max_tolerance": Units.MAX_TOLERANCE,
			"temperature": page.body_heat[row], "elements": page.elements.slice(row * 5, row * 5 + 5),
			"cargo": page.cargo[row], "potions": page.potions[row], "mode": page.modes[row], "position": page.positions[row]}, true)
		result["action"] = State.copy(actions.get(id, combat.states.get(id, {})))
		result["due_ms"] = page.due_ms[row]
		result["events"] = person_events.view(id)
		result["events_version"] = person_events.version(id)
		result["decision"] = decisions.describe(id)
		result["agency"] = livelihood.describe(id)
		result["flight"] = page.flight[row]
		result["radius"] = page.radii[row]
		result["destination"] = page.targets[row]
		result["route_preview"] = page.routes[row].slice(page.route_cursors[row], mini(page.routes[row].size(), page.route_cursors[row] + 64)) if page.modes[row] in [Units.Mode.RESOURCE, Units.Mode.MANUAL, Units.Mode.APPROACH, Units.Mode.EXPLORE, Units.Mode.COMBAT_MOVE] else PackedVector2Array()
		result["sight_range"] = sight.range_for(self, id)
		result["stats"] = Equipment.view(page, row)
		result["body_capabilities"] = Beings.capabilities(objects.records[id])
		result["admission_reason"] = gate.check(self, id, operation_time())
		result["activity"] = activity_view(id)
		result["activity_results"] = activity_results.view(id)
		result["abilities"] = Growth.abilities(objects.records[id])
		result["aptitudes"] = {"physique": Growth.aptitude(objects.records[id], "physique"), "comprehension": Growth.aptitude(objects.records[id], "comprehension")}
		result["pools"] = State.copy(pools.records.get(id, {}))
		result["shield"] = defense.total(id, elapsed_ms)
		result["usable_inventory"] = objects.usable_summary(id)
		result["carried"] = objects.inventory_summary(id)
		var access: Dictionary = institutions.access_view(self, id)
		var available: Array = institutions.bundles(self, id, access)
		result["readable"] = institutions.readable(self, id, available)
		result.merge(access, true)
		result["returns"] = institutions.returns(self, id)
		result["task_access"] = {int(result.commitment.target): ["construct"]} if result.get("commitment", {}).get("kind") == "construct" else {}
		result["bundles"] = available
		result["equippable"] = []
		for bundle: Dictionary in result.bundles:
			if bundle.owner == id or bundle.purpose == "equip":
				for item: String in bundle.items:
					if not result.equippable.has(item): result.equippable.append(item)
		if id == 1: result["stock_rights"] = State.copy(objects.records[id].stock)
	return result

func activity_view(id: int) -> Dictionary:
	var binding: Dictionary = gate.current(id)
	if binding.is_empty() or not actor_slots.has(id): return {}
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / 256]
	var row: int = slot % 256
	var result: Dictionary = binding.duplicate()
	result["due_ms"] = page.due_ms[row]
	result["phase"] = "working"
	if binding.domain == "interaction":
		var action: Dictionary = actions[id]
		result["operation"] = action.kind
		result["target"] = action.target
		result.phase = "approaching" if page.modes[row] == Units.Mode.APPROACH else ("waiting" if action.get("waiting", false) else "acting")
	elif binding.domain == "partner": result.phase = "partner_waiting"
	elif binding.domain == "combat": result.phase = "combat"
	elif binding.domain == "work":
		match page.modes[row]:
			Units.Mode.REST: result.phase = "waiting"
			Units.Mode.MANUAL: result.phase = "traveling"
			Units.Mode.EXPLORE: result.phase = "exploring"
			Units.Mode.RESOURCE, Units.Mode.HARVEST:
				result.phase = "approaching" if page.modes[row] == Units.Mode.RESOURCE else "acting"
				result["operation"] = "harvest"
				result["target"] = source_objects[page.source_ids[row]]
	return result


func queue_structure(tile: int, solid: bool, enclosed: bool, removing: bool = false) -> void:
	if _commit_ms >= 0 and _commit_ms <= _motion_end:
		_spatial_edits.append({"tile": tile, "solid": solid, "enclosed": enclosed, "removing": removing})
		return
	if not _topology_edits.has(tile):
		_topology_edits[tile] = {"solid": terrain.blocked[tile] != 0, "enclosed": terrain.enclosures[tile] != 0}
	terrain.blocked[tile] = int(solid)
	terrain.enclosures[tile] = int(enclosed)
	if removing:
		terrain.structures.erase(tile)
	elif not terrain.structures.has(tile):
		terrain.structures.append(tile)


func flush_topology() -> void:
	var pending: Array[Dictionary] = _spatial_edits
	_spatial_edits = []
	var commit: int = _commit_ms
	_commit_ms = -1
	for edit: Dictionary in pending: queue_structure(edit.tile, edit.solid, edit.enclosed, edit.removing)
	_commit_ms = commit
	if _topology_edits.is_empty():
		return
	var started: int = Time.get_ticks_usec()
	var room_dirty: bool = false
	var field_dirty: bool = false
	var blockers: Dictionary = {}
	var changed := PackedInt32Array()
	for tile: int in _topology_edits:
		room_dirty = room_dirty or _topology_edits[tile].enclosed != (terrain.enclosures[tile] != 0)
		if _topology_edits[tile].solid != (terrain.blocked[tile] != 0):
			changed.append(tile)
			if terrain.blocked[tile] != 0:
				blockers[tile] = true
			for source: int in environment.source_cells:
				if (Terrain.cell(source) - Terrain.cell(tile)).length_squared() < environment.RADIUS * environment.RADIUS:
					field_dirty = true
	if not changed.is_empty():
		for lane: RefCounted in lanes:
			lane.navigation.changed(changed)
	if not blockers.is_empty():
		var dirty := Rect2(Vector2(Terrain.cell(blockers.keys()[0])), Vector2.ONE)
		for tile: int in blockers:
			dirty = dirty.merge(Rect2(Vector2(Terrain.cell(tile)), Vector2.ONE))
		for page: RefCounted in pages:
			for row: int in page.routes.size():
				if page.flight[row] > 0: continue
				var from: Vector2 = page.positions[row]
				var radius: float = page.radii[row]
				for cursor: int in range(page.route_cursors[row], page.routes[row].size()):
					var to: Vector2 = page.routes[row][cursor]
					var affected: bool = false
					if Terrain.segment_hits_box(from, to, dirty.position - Vector2.ONE * radius, dirty.end + Vector2.ONE * radius):
						for tile: int in blockers:
							var low := Vector2(Terrain.cell(tile)) - Vector2.ONE * radius
							if Terrain.segment_hits_box(from, to, low, low + Vector2.ONE * (1.0 + radius * 2)):
								affected = true
								break
					if affected:
						page.routes[row] = PackedVector2Array()
						page.route_cursors[row] = 0
						break
					from = to
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


func spawn_actor(tile: int, body_profile: String = "human", origin: String = "independent") -> int:
	if not Beings.ERRORS.is_empty() or not Beings.FORMS.has(body_profile) or origin not in ["independent", "summoned"]: return 0
	if tile < 0 or tile >= terrain.blocked.size() or terrain.blocked[tile] != 0:
		return 0
	var id: int = objects.create("actor", body_profile)
	objects.records[id]["body_profile"] = body_profile
	objects.records[id]["body_origin"] = origin
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
		page.tolerance[row] = Units.MAX_TOLERANCE
		page.thermal_carry[row] = 0.0
		page.energy[row] = 10000
		page.hunger[row] = 10000
		page.body_heat[row] = 22.0
		page.flight[row] = 0
		page.radii[row] = 0.35
		page.aims[row] = Vector2.RIGHT
		page.direct_velocities[row] = Vector2.ZERO
		page.cargo[row] = 0
		page.potions[row] = 0
		page.targets[row] = page.positions[row]
		page.routes[row] = PackedVector2Array()
		page.route_cursors[row] = 0
		page.due_ms[row] = 0
		page.source_ids[row] = 0
		page.motion.erase(row)
		for index: int in 5: page.elements[row * 5 + index] = 0
		for index: int in 7: page.exposure[row * 7 + index] = 0
	else:
		slot = body_count
		if pages.is_empty() or pages.back().ids.size() == Units.PAGE_SIZE:
			page = Units.new()
			page.terrain = terrain
			page.environment = environment
			pages.append(page)
			configure_lanes(requested_workers)
		else:
			page = pages.back()
		row = page.add_row(id, tile)
	page.modes[row] = Units.Mode.IDLE
	actor_slots[id] = slot
	Equipment.rebuild(self, id)
	if Beings.population_member(objects.records[id]): actor_count += 1
	return id


func remove_actor(id: int, at: int = -1) -> bool:
	if at < 0: at = operation_time()
	var population: bool = Beings.population_member(objects.records.get(id, {}))
	if id == 1 or not actor_slots.has(id):
		return false
	var slot: int = actor_slots[id]
	var page: RefCounted = pages[slot / Units.PAGE_SIZE]
	var row: int = slot % Units.PAGE_SIZE
	page.health[row] = 0 # Removal callbacks must not read a live participant.
	reactions.forget_actor(id)
	implements.drop_owner(self, id, at)
	entities.forget_member(self, id, at)
	entities.drop_owner(self, id, at)
	effects.remove_target(self, id, at)
	defense.remove_target(id)
	release(id, at, "actor_removed")
	forget_target(id, at)
	environment.remove_mobile(id)
	if objects.count_inventory(id) > 0 or not objects.records[id].equipment.is_empty():
		var pile: int = objects.create("pile", "remains", Terrain.index(Vector2i(page.positions[row])))
		for gear_slot: String in objects.records[id].equipment.keys(): objects.unequip(id, gear_slot, pile)
		for item: String in objects.inventory_summary(id):
			objects.transfer(id, pile, item, objects.amount(id, item))
	objects.remove_empty(id)
	knowledge.records.erase(id)
	decisions.forget(id)
	livelihood.forget(id)
	actor_slots.erase(id)
	pools.records.erase(id)
	defense.guards.erase(id)
	combat.unreachable.erase(id)
	combat.cooldowns.erase(id)
	combat.chains.erase(id)
	combat.status.erase(id)
	page.ids[row] = 0
	page.health[row] = 0
	page.needs_enabled[row] = 0
	page.environment_enabled[row] = 0
	page.move_scales[row] = 1.0
	page.cargo[row] = 0
	page.potions[row] = 0
	page.modes[row] = Units.Mode.FREE
	free_slots.append(slot)
	if population: actor_count -= 1
	return true
