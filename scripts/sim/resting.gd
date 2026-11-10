class_name SimResting
extends RefCounted
## Bed use and allocation only. Bodies, continuous needs and construction stay
## in their original domains; topology and eligibility are queried, not copied.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/resting_schema.gd")
var definitions: Dictionary = {}
var allocations: Dictionary = {}
var active: Dictionary = {}
var next_job: int = 1
var next_check_ms: int = SimInventory.MAX_COUNT
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	return Shape.keys(data, ["version", "region", "members", "notice_cells", "check_ms", "rest_ms", "energy_per_minute", "wake_energy"]) and data.version == 1 and SimInventory._nonempty(data.region) and SimEmbodiment._unique_texts(data.members) and not data.members.is_empty() and Shape.count(data.notice_cells, 1, 32) and Shape.count(data.check_ms, 1, 60000) and Shape.count(data.rest_ms, 60000, 86400000) and Shape.count(data.energy_per_minute, 1, 5) and Shape.count(data.wake_energy, 36, 100)


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(parent: RefCounted, rules: Dictionary) -> bool:
	if not valid_definitions(rules) or not parent.regions.has(rules.region) or rules.region != parent.construction.definitions.site.region:
		return false
	for actor: String in rules.members:
		if not parent.regions[rules.region].has_actor(actor):
			return false
	_owner = weakref(parent)
	definitions = rules.duplicate(true)
	return true


func member(actor: String) -> bool:
	return definitions.members.has(actor) and world.regions[definitions.region].has_actor(actor)


func can_observe(actor: String, bed: String) -> bool:
	if not member(actor) or not world.construction.is_bed(bed):
		return false
	return SimRouteTravel.point(_body(actor)).distance_to(TileGrid.cell_to_world(_cell(bed))) <= float(definitions.notice_cells) * TileGrid.TILE_SIZE


func allowed(actor: String, bed: String) -> bool:
	return member(actor) and world.construction.is_bed(bed) and str(allocations.get(bed, actor)) == actor


func assign(requester: String, bed: String, occupant: String = "") -> Dictionary:
	if world.elapsed_ms != world.target_ms or not world.construction.authorized(requester) or not world.actor_controls(requester, "communication") or not can_observe(requester, bed) or not occupant.is_empty() and not member(occupant):
		return SimConstruction.reply(false, "须由获准同门在床边安排本院同门的床位。")
	if bed_reserved(bed) or world.construction._project_busy(bed):
		return SimConstruction.reply(false, "床位正在使用、已被预约或正待拆改，先结束现有事务。")
	if occupant.is_empty():
		allocations.erase(bed)
	else:
		allocations[bed] = occupant
	return SimConstruction.reply(true, "床位已设为本院共用。" if occupant.is_empty() else "床位已安排；这只是使用安排，不改变宗门所有权。")


func begin(actor: String, bed: String) -> Dictionary:
	return _begin(actor, bed, false)


func _begin(actor: String, bed: String, during_commit: bool) -> Dictionary:
	if not member(actor) or not during_commit and world.elapsed_ms != world.target_ms or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion"):
		return SimConstruction.reply(false, "眼下无法支配身体使用床铺。")
	world.synchronize_region(str(definitions.region))
	var body: Dictionary = _body(actor)
	if not body.active.is_empty() or world.local_action_owns(actor) or world.artifacts.owns_actor(actor) or world.services != null and world.services.owns_actor(actor):
		return SimConstruction.reply(false, "先停下手头的事情，再去床上休息。")
	if not allowed(actor, bed) or world.facility_use != null and world.facility_use.cell_reserved(_cell(bed), actor) or not can_observe(actor, bed) or bed_reserved(bed) or world.construction._project_busy(bed) or _occupied_by_other(actor, bed):
		return SimConstruction.reply(false, "床位不适用：可能已分配给他人、被占用、正在拆改或离得太远。")
	var path: Array = _route(actor, bed)
	if path.is_empty() and not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(_cell(bed))):
		return SimConstruction.reply(false, "走不到这张床；先检查门和道路。")
	var job: Dictionary = {"id": "bed_use:%d" % next_job, "actor": actor, "bed": bed, "phase": "travel", "path": path, "segment_from": body.position.duplicate(), "segment_started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + 1, "started_ms": world.elapsed_ms, "arrived_ms": 0, "previous_autonomous": bool(body.autonomous)}
	SimRouteTravel.begin_segment(job, body, world.elapsed_ms, _speed())
	next_job += 1
	active[actor] = job
	body.autonomous = false
	body.goal = "前往已预约的木床"
	_schedule_check()
	world.invalidate_region(str(definitions.region))
	return SimConstruction.reply(true, "床位已预约，走到床边后才开始休息。")


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func bed_reserved(bed: String) -> bool:
	for job: Dictionary in active.values():
		if job.bed == bed:
			return true
	return false


func cancel(actor: String) -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if not active.has(actor):
		return false
	_release(actor, "已结束床上休息；已恢复的精神保留，床位已释放。")
	return true


func recovery_for(actor: String) -> int:
	if not active.has(actor) or active[actor].phase != "sleep":
		return 0
	return int(world.weather.definitions.wet_recovery) if world.weather != null and world.weather.bed_is_wet(str(active[actor].bed)) else int(definitions.energy_per_minute)


func duty_for(actor: String) -> String:
	if not member(actor) or active.has(actor):
		return ""
	var body: Dictionary = _body(actor)
	var sim: RefCounted = world.regions[definitions.region]
	if not bool(body.autonomous) or not bool(body.alive) or not body.active.is_empty() or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or float(body.hunger) <= float(sim.config.needs.eat_below) or float(body.energy) > float(sim.config.needs.rest_below):
		return ""
	var best: String = ""
	var distance: int = SimInventory.MAX_COUNT
	for id: String in world.construction.bed_ids():
		if world.facility_use != null and world.facility_use.cell_reserved(_cell(id), actor) or not allowed(actor, id) or not can_observe(actor, id) or bed_reserved(id) or world.construction._project_busy(id) or _occupied_by_other(actor, id):
			continue
		var path: Array = _route(actor, id)
		var wet: int = 1 if world.weather != null and world.weather.bed_is_wet(id) else 0
		var best_wet: int = 1 if not best.is_empty() and world.weather != null and world.weather.bed_is_wet(best) else 0
		if (not path.is_empty() or SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(_cell(id)))) and (best.is_empty() or wet < best_wet or wet == best_wet and path.size() < distance):
			best = id
			distance = path.size()
	return best


func next_boundary_ms() -> int:
	var boundary: int = next_check_ms
	for actor: String in active:
		var job: Dictionary = active[actor]
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion"):
			return world.elapsed_ms + 1
		boundary = mini(boundary, SimRouteTravel.next_boundary(job, _body(actor), world.elapsed_ms, _route_step) if job.phase != "sleep" else int(job.due_ms))
	return boundary


func settle_at_ms(now: int) -> void:
	if now >= next_check_ms:
		world.synchronize_region(str(definitions.region))
	for actor: String in active.keys():
		world.synchronize_region(str(definitions.region))
		var job: Dictionary = active[actor]
		var body: Dictionary = _body(actor)
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not allowed(actor, str(job.bed)):
			_release(actor, "床铺或身体已不适用，休息中断。")
			continue
		if job.phase != "sleep":
			if not SimRouteTravel.repair(world.regions[definitions.region], actor, job, now, [], -1.0, _route_step):
				_release(actor, "通往床铺的道路被挡住，床位已释放。")
				continue
			world.regions[definitions.region].project_actor_route(actor, job, now)
			if now < int(job.due_ms):
				continue
			if not job.path.is_empty():
				world.regions[definitions.region].set_actor_position(actor, TileGrid.cell_to_world(SimRouteTravel.cell(job.path.pop_front())))
			if not job.path.is_empty():
				SimRouteTravel.begin_segment(job, body, now, _speed())
				continue
			if job.phase == "leave":
				_release(actor, str(body.goal), "completed")
				continue
			if _occupied_by_other(actor, str(job.bed)):
				_release(actor, "床边有人占着，暂不能躺下。")
				continue
			job.phase = "sleep"
			job.arrived_ms = now
			job.segment_started_ms = now
			job.segment_from = body.position.duplicate()
			job.due_ms = now + int(definitions.rest_ms)
			body.goal = "在木床上休息"
		elif now >= int(job.due_ms) or now >= next_check_ms and (float(body.energy) >= float(definitions.wake_energy) or float(body.hunger) <= float(world.regions[definitions.region].config.needs.eat_below)):
			_wake(actor, "休息后精神已足，起身让出床位。" if float(body.energy) >= float(definitions.wake_energy) else "肚饿，先起身找饭。" if float(body.hunger) <= float(world.regions[definitions.region].config.needs.eat_below) else "这一觉结束，起身活动。")
	if next_check_ms <= now:
		next_check_ms = SimInventory.MAX_COUNT
		for actor: String in definitions.members:
			var bed: String = duty_for(actor)
			if not bed.is_empty():
				_begin(actor, bed, true)
		_schedule_check()


func structures_changed() -> void:
	for bed: String in allocations.keys():
		if not world.construction.is_bed(bed):
			allocations.erase(bed)
	_schedule_check()


func _schedule_check() -> void:
	for bed: String in world.construction.bed_ids():
		if world.construction.is_bed(bed):
			next_check_ms = mini(next_check_ms, world.elapsed_ms + int(definitions.check_ms))
			return
	next_check_ms = SimInventory.MAX_COUNT


func _release(actor: String, line: String, status: String = "cancelled") -> void:
	var job: Dictionary = active[actor]
	var body: Dictionary = _body(actor)
	body.autonomous = bool(active[actor].previous_autonomous)
	body.retry_ms = world.elapsed_ms + int(definitions.check_ms)
	body.goal = line
	active.erase(actor)
	world.invalidate_region(str(definitions.region))
	_schedule_check()
	SimActionContract.job_finished(world, "resting", job, actor, status, line)


func _wake(actor: String, line: String) -> void:
	var job: Dictionary = active[actor]
	var body: Dictionary = _body(actor)
	var from: Vector2i = _cell(str(job.bed))
	for side: Vector2i in SimConstruction.SIDES:
		var to: Vector2i = from + side
		if world.construction.terrain_open(to) and _step_open(from, to) and not _cell_occupied(actor, to):
			job.phase = "leave"
			job.path = [[to.x, to.y]]
			body.goal = line
			SimRouteTravel.begin_segment(job, body, world.elapsed_ms, _speed())
			return
	_release(actor, line + "床边拥堵，暂时站在原处。", "completed")


func _route(actor: String, bed: String) -> Array:
	var sim: RefCounted = world.regions[definitions.region]
	var body: Dictionary = _body(actor)
	var start: Vector2i = SimRouteTravel.cell(body.cell)
	var target: Vector2i = _cell(bed)
	var path: Array[Vector2i] = sim.find_path(start, target)
	if start != target and path.is_empty():
		return []
	var result: Array = []
	for cell: Vector2i in path:
		if cell != start:
			result.append([cell.x, cell.y])
	if not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(start)):
		result.push_front([start.x, start.y])
	return result


func _occupied_by_other(actor: String, bed: String) -> bool:
	return _cell_occupied(actor, _cell(bed))


func _cell_occupied(actor: String, cell: Vector2i) -> bool:
	for sim: RefCounted in world.regions.values():
		for other: String in sim.actors:
			if other != actor and bool(sim.actor_state(other).alive) and SimRouteTravel.cell(sim.actor_state(other).cell) == cell:
				return true
	for id: String in world.avian_life.birds:
		if int(world.avian_life.birds[id].altitude) == 0 and world.avian_life.body_cell(id) == cell:
			return true
	return false


func _step_open(from: Vector2i, to: Vector2i) -> bool:
	var sim: RefCounted = world.regions[definitions.region]
	return not world.construction.blocked(to) and (not sim._step_validator.is_valid() or bool(sim._step_validator.call(from, to - from)))


func _route_step(from: Vector2i, step: Vector2i) -> bool:
	return _step_open(from, from + step)


func _body(actor: String) -> Dictionary:
	return world.regions[definitions.region].actor_state(actor)


func _cell(bed: String) -> Vector2i:
	return SimRouteTravel.cell(world.construction.projects[bed].cell)


func _speed() -> float:
	return float(world.regions[definitions.region].motion_rules.motion.speed)


static func empty_state() -> Dictionary:
	return {"version": 1, "allocations": {}, "active": {}, "next_job": 1, "next_check_ms": SimInventory.MAX_COUNT}


func to_dict() -> Dictionary:
	return {"version": 1, "allocations": allocations.duplicate(true), "active": active.duplicate(true), "next_job": next_job, "next_check_ms": next_check_ms}


func restore(data: Dictionary) -> bool:
	if not Schema.valid(data, self):
		return false
	allocations = data.allocations.duplicate(true)
	active = data.active.duplicate(true)
	next_job = int(data.next_job)
	next_check_ms = int(data.next_check_ms)
	return true
