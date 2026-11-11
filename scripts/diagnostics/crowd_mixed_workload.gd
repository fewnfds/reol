extends RefCounted
## Reproducible mixed pressure on the ordinary owners. Setup uses original
## commands and explicit clock advances; measurement runs at requested 1×.

const DOOR_WORKER: String = "shi_tou"
const COOK: String = "a_he"
const FIGHTERS: Array[String] = ["chen_shouzhuo", "river_chen_shouzhuo"]
const HAULERS_PER_REGION: int = 8
const VISITS: Array[String] = ["home:kitchen", "river:dorm", "river:store", "home:dorm"]

var _runtime: WorldContinuityRuntime
var _world: RegionalSimulation
var _clock: ReolGameClock
var _participants: Dictionary[String, bool] = {}
var _haulers: Array[Dictionary] = []
var _carry_ids: Dictionary[String, bool] = {}
var _cook_id: String = ""
var _door: String = ""
var _conflict: String = ""
var _start_ms: int = 0
var _next_haul_ms: int = 0
var _next_door_ms: int = 5000
var _visit: int = 0
var _moves: int = 0
var _elapsed_usec: int = 0
var _max_usec: int = 0
var _completed: Dictionary[String, int] = {}
var _rejected: Dictionary[String, int] = {}
var _last_cell: Vector2i


func prepare(runtime: WorldContinuityRuntime, clock: ReolGameClock) -> String:
	_runtime = runtime
	_world = runtime.world_sim
	_clock = clock
	var home: VillageSimulation = _world.regions.home
	var source: Dictionary = _world.artifacts.begin("player", "take", "amber_pearl")
	if not source.ok or not await _advance_to(int(_world.artifacts.active.get("player", {}).get("due_ms", _clock.elapsed_ms))):
		return "Taking the original light source: " + str(source.line)
	if _world.artifacts.objects.amber_pearl.container != "actor:player":
		return "The original light source did not transfer to the observer"
	var stock: Dictionary = _haul("player", "home", "store", "wood", 4)
	if not stock.ok or not await _advance_to(_clock.elapsed_ms + 15000):
		return "Supplying the kitchen: " + str(stock.line)
	if _world.services.owns_actor("player") or home.inventory.available("kitchen", "wood") < 1:
		return "Kitchen supplies did not arrive during setup"
	_world.interrupt_occupation(COOK, "mixed_setup")
	if not home.submit_action(COOK, "cook"):
		return "The original recipe did not reserve its inputs"
	_cook_id = str(home.actor_state(COOK).active.id)
	var yard: Vector2i = runtime.construction_adapter.find_yard_origin()
	var registered: Dictionary = _world.construction.register_site("player", yard)
	if not registered.ok:
		return "Registering a construction site: " + str(registered.line)
	# The first registered grid cell can belong to the fixed freight route or
	# already have a body on it. Pick a clear edge of the actual yard.
	var door_cell: Vector2i = Vector2i(-1, -1)
	var store: Vector2i = SimRouteTravel.cell(home.places.store.cell)
	var best: int = -1
	for cell: Vector2i in SimConstruction.cells_in(_world.construction.site_bounds(str(registered.site))):
		var distance: int = (cell - store).length_squared()
		if distance <= best or not _world.construction.can_observe("player", cell) or SimMotionClearance.fixed_road_reserves(_world, cell) or _world.construction.occupied(cell):
			continue
		best = distance
		door_cell = cell
	if best < 0:
		return "The yard has no clear cell outside the freight route"
	var blueprint: Dictionary = _world.construction.place("player", "wood_door", door_cell)
	if not blueprint.ok:
		return "Placing a door: " + str(blueprint.line)
	_door = str(blueprint.project)
	var build: Dictionary = _world.construction.begin("player", _door)
	if not build.ok or not await _advance_to(_clock.elapsed_ms + 270000):
		return "Building the door through the original action: " + str(build.line)
	if _world.construction.projects[_door].state != "built":
		return "Door was not built: " + str(_world.construction.projects[_door].line)
	var recipe: Dictionary = home.actor_state(COOK).active
	if recipe.get("id", "") != _cook_id or recipe.get("phase", "") != "work":
		return "Cook did not start the original recipe"
	# Leave the last 24 game seconds of the unchanged recipe inside the capture.
	if not await _advance_to(int(recipe.due_ms) - 24000) or home.actor_state(COOK).active.get("id", "") != _cook_id:
		return "Recipe setup did not reach its final work interval"
	_participants = {"player": true, COOK: true, DOOR_WORKER: true}
	var stand: Vector2i = SimRouteTravel.cell(home.actor_state("player").cell)
	var dorm: Vector2i = SimRouteTravel.cell(home.places.dorm.cell)
	# Only initial positions are staged. During the capture movement comes
	# exclusively from the real actions, combat and observer route.
	_stage_body(DOOR_WORKER, stand)
	_stage_body(FIGHTERS[0], dorm)
	var nearby: Array[Vector2i] = VillageRuntime.find_reachable_cells(runtime.home_runtime()._world, dorm, 3, 64)
	for cell: Vector2i in nearby:
		if cell != dorm and cell.distance_to(dorm) >= 2.0:
			_stage_body(FIGHTERS[1], cell)
			break
	if not _participants.has(FIGHTERS[1]):
		return "No nearby starting place for the second fighter"
	_stage_body("player", dorm)
	for region: String in _world.regions:
		var sim: VillageSimulation = _world.regions[region]
		var count: int = 0
		for actor: String in sim.actors:
			if not actor.begins_with("crowd_") and not actor.begins_with("river_crowd_"):
				continue
			_participants[actor] = true
			_haulers.append({"actor": actor, "region": region})
			count += 1
			if count == HAULERS_PER_REGION:
				break
	return ""


func _advance_to(target: int) -> bool:
	if target <= _clock.elapsed_ms:
		return target == _clock.elapsed_ms and _world.accepts_commands()
	var timeout: int = Time.get_ticks_msec() + 18000
	_clock.advance_msec(target - _clock.elapsed_ms)
	while _clock.elapsed_ms < target and Time.get_ticks_msec() < timeout:
		await _clock.get_tree().process_frame
	return _clock.elapsed_ms == target and _world.elapsed_ms == target and _world.accepts_commands()


func _stage_body(actor: String, cell: Vector2i) -> void:
	var home: String = _world.clothing.home(actor)
	_world.advance_region_to_world(home)
	_world.interrupt_occupation(actor, "mixed_setup")
	_world.regions[home].set_actor_cell(actor, cell)
	_world.invalidate_region(home, actor)
	_participants[actor] = true


func uses_actor(actor: String) -> bool:
	return _participants.has(actor)


func _haul(actor: String, region: String, source: String, item: String, amount: int) -> Dictionary:
	return _world.services.begin_haul(actor, {"region": region, "container": source}, {"region": region, "container": "kitchen"}, item, amount)


func start() -> void:
	_start_ms = _clock.elapsed_ms
	_last_cell = _runtime.home_runtime()._player.cell
	_world.action_finished.connect(_on_finished)


func sample() -> void:
	var began: int = Time.get_ticks_usec()
	var elapsed: int = _clock.elapsed_ms - _start_ms
	var home: VillageSimulation = _world.regions.home
	if not _haulers.is_empty() and elapsed >= _next_haul_ms:
		var entry: Dictionary = _haulers.pop_front()
		_world.advance_region_to_world(entry.region)
		_world.regions[entry.region].cancel_action(entry.actor, "mixed_haul_order")
		var hauling: Dictionary = _haul(entry.actor, entry.region, "well", "water", 2)
		if hauling.ok:
			_carry_ids[str(hauling.id)] = true
		else:
			_increment(_rejected, "haul:" + str(hauling.reason))
		_next_haul_ms += 450
	if elapsed >= _next_door_ms:
		var verb: String = "close" if _world.construction.projects[_door].open else "open"
		_world.advance_region_to_world("home")
		home.cancel_action(DOOR_WORKER, "mixed_door_order")
		if not _world.construction.begin(DOOR_WORKER, _door, verb).ok:
			_increment(_rejected, verb)
		_next_door_ms += 15000
	if elapsed >= 10000 and _conflict.is_empty():
		_world.advance_region_to_world("home")
		_world.advance_region_to_world("river")
		if _world.conflicts.begin(FIGHTERS[0], FIGHTERS[1]).ok:
			_conflict = _world.conflicts.conflict_for(FIGHTERS[0])
		else:
			_increment(_rejected, "conflict")
			_conflict = "not_started" # Only one initial encounter is requested.
	if _runtime.player_journey.is_empty():
		var stop: PackedStringArray = VISITS[_visit].split(":")
		var target: Vector2i = SimRouteTravel.cell(_world.regions[stop[0]].places[stop[1]].cell)
		if _runtime.home_runtime()._player.cell != target and not _runtime.travel_to(stop[0], target):
			_increment(_rejected, "observer_route")
		_visit = (_visit + 1) % VISITS.size()
	var current: Vector2i = _runtime.home_runtime()._player.cell
	if current != _last_cell:
		_moves += 1
		_last_cell = current
	var cost: int = Time.get_ticks_usec() - began
	_elapsed_usec += cost
	_max_usec = maxi(_max_usec, cost)


func _on_finished(outcome: Dictionary) -> void:
	var id: String = str(outcome.id)
	if _carry_ids.has(id):
		_increment(_completed, "haul:" + str(outcome.status))
	elif id == _cook_id and outcome.actor == COOK:
		_increment(_completed, "cook:" + str(outcome.status))
	elif outcome.domain == "construction" and outcome.target == _door:
		_increment(_completed, str(outcome.intent) + ":" + str(outcome.status))


func travelling() -> int:
	var count: int = int(not _runtime.player_journey.is_empty())
	for id: String in _carry_ids:
		var job: Dictionary = _world.services.jobs[id]
		if job.status == "active" and job.phase == "travel":
			count += 1
	return count


func evidence() -> Dictionary:
	_world.action_finished.disconnect(_on_finished)
	var effects: int = 0
	var projectiles: int = 0
	for action: Dictionary in _world.conflicts.actions.values():
		if action.conflict == _conflict and action.emitted:
			effects += 1
			if action.method == "qi_bolt":
				projectiles += 1
	return {"setup_world_ms": _start_ms, "haul_started": _carry_ids.size(), "completed": _completed,
		"rejected": _rejected, "observer_cell_changes": _moves, "source_carried": _world.artifacts.objects.amber_pearl.container == "actor:player",
		"combat_effects": effects, "projectiles_emitted": projectiles, "combat_hits": _world.conflicts.hits.size(), "driver_ms": _elapsed_usec / 1000.0,
		"max_driver_ms": _max_usec / 1000.0}


static func _increment(counts: Dictionary[String, int], key: String) -> void:
	counts[key] = counts.get(key, 0) + 1
