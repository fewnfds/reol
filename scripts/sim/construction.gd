class_name SimConstruction
extends RefCounted
signal structures_changed(cells: Array[Vector2i])
signal space_changed(cells: Array[Vector2i])
## Persistent projects; quantities stay in the settlement's original ledger.
## A material container is either carried by a real worker or lies on the ground.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/construction_schema.gd")
const SIDES: Array[Vector2i] = [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]
var definitions: Dictionary = {}
var sites: Dictionary = {}
var projects: Dictionary = {}
var active: Dictionary = {}
var next_project: int = 1
var next_job: int = 1
var next_check_ms: int = SimInventory.MAX_COUNT
var _owner: WeakRef
var _terrain: Callable
var _elevation: Callable
var _incoming: Callable
var _cells: Dictionary = {}
var _roofs: Dictionary = {}
var _blocked: Dictionary = {}
var _spaces: Dictionary = {}
var _material_cells: Dictionary[Vector2i, int] = {}
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "site", "check_ms", "minimum_fullness", "minimum_energy", "operate_ms", "pickup_ms", "roof_span", "types"]) or data.version != 1 or not Shape.count(data.roof_span, 1, 4) or not Shape.keys(data.site, ["region", "source", "builders", "workers", "width", "height", "source_cells", "notice_cells", "observe_cells"]):
		return false
	if not SimInventory._nonempty(data.site.region) or not SimInventory._nonempty(data.site.source) or not SimEmbodiment._unique_texts(data.site.builders) or data.site.builders.is_empty() or not SimEmbodiment._unique_texts(data.site.workers):
		return false
	for worker: String in data.site.workers:
		if not data.site.builders.has(worker):
			return false
	for key: String in ["width", "height", "source_cells", "notice_cells", "observe_cells"]:
		if not Shape.count(data.site[key], 1, 32):
			return false
	for value: Variant in [data.check_ms, data.operate_ms, data.pickup_ms]:
		if not Shape.count(value, 1, 600000):
			return false
	if not Shape.count(data.minimum_fullness, 1, 100) or not Shape.count(data.minimum_energy, 1, 100) or not Shape.keys(data.types, ["wood_wall", "wood_door", "wood_bed", "wood_roof"]):
		return false
	for type: String in data.types:
		var row: Variant = data.types[type]
		if not Shape.keys(row, ["label", "kind", "item", "amount", "work_ms", "demolish_ms", "salvage", "door"]) or not SimInventory._nonempty(row.label) or row.kind != str(type).trim_prefix("wood_") or row.item != "wood" or not row.door is bool or row.door != (type == "wood_door") or not Shape.count(row.amount, 1, 20) or not Shape.count(row.salvage, 1, int(row.amount) - 1):
			return false
		if not Shape.count(row.work_ms, 1, 3600000) or not Shape.count(row.demolish_ms, 1, 3600000):
			return false
	return true


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(parent: RefCounted, rules: Dictionary) -> bool:
	if not valid_definitions(rules):
		return false
	_owner = weakref(parent)
	definitions = rules.duplicate(true)
	return true


func set_terrain(provider: Callable, elevation: Callable = Callable()) -> void:
	_terrain = provider
	_elevation = elevation
	_reindex()


func set_incoming_occupancy(provider: Callable) -> void:
	_incoming = provider


func authorized(actor: String) -> bool:
	var rule: Dictionary = definitions.site
	return rule.builders.has(actor) and world.regions.has(rule.region) and world.regions[rule.region].actors.has(actor)


func register_site(actor: String, origin: Vector2i) -> Dictionary:
	if not authorized(actor) or not sites.is_empty() or not _ready_actor(actor, false):
		return reply(false, "须由获准同门在库房附近划定工地；现有工地继续沿用。")
	var sim: RefCounted = world.regions[definitions.site.region]
	var source: Vector2i = SimRouteTravel.cell(sim.places[definitions.site.source].cell)
	if source.distance_to(origin) > float(definitions.site.source_cells) or SimRouteTravel.point(sim.actors[actor]).distance_to(TileGrid.cell_to_world(origin)) > float(definitions.site.observe_cells) * TileGrid.TILE_SIZE:
		return reply(false, "这片地离库房或你太远，不能在这里登记宗门工地。")
	var bounds := Rect2i(origin, Vector2i(int(definitions.site.width), int(definitions.site.height)))
	for cell: Vector2i in cells_in(bounds):
		if not terrain_open(cell) or protected_cell(cell):
			return reply(false, "工地需是一片连续草地，并避开已有生活设施。")
	sites["sect_yard"] = {"region": str(definitions.site.region), "owner": str(sim.config.institution.id), "origin": [origin.x, origin.y], "created_by": actor, "created_ms": world.elapsed_ms}
	_reindex()
	return reply(true, "已登记宗门工地：此处公料仅供获准工程使用。")


func place(actor: String, type: String, cell: Vector2i) -> Dictionary:
	if not _ready_actor(actor, false) or not definitions.types.has(type) or not site_contains(cell) or not can_observe(actor, cell) or not terrain_open(cell) or protected_cell(cell) or not project_at(cell, "roof" if type == "wood_roof" else "ground").is_empty():
		return reply(false, "此处不能落蓝图：请当面选择获准工地中的空草地。")
	var id: String = "construction:%d" % next_project
	var sim: RefCounted = world.regions[definitions.site.region]
	if not sim.inventory.create_container(id, {}):
		return reply(false, "无法登记这批材料的容器。")
	next_project += 1
	projects[id] = {"site": "sect_yard", "type": type, "cell": [cell.x, cell.y], "state": "blueprint", "open": false, "created_by": actor, "created_ms": world.elapsed_ms, "completed_ms": 0, "removed_ms": 0, "work_ms": 0, "material_cell": [cell.x, cell.y], "carrier": "", "delivered": false, "line": "蓝图已画好，等待取料施工。"}
	_reindex()
	_schedule_check()
	space_changed.emit([cell])
	return {"ok": true, "line": "蓝图不挡路；材料到场并完成施工后才成为实物。", "project": id}


func cancel_project(actor: String, id: String) -> Dictionary:
	if not authorized(actor) or not projects.has(id) or projects[id].state != "blueprint" or not can_observe(actor, SimRouteTravel.cell(projects[id].cell)):
		return reply(false, "只能在场撤销本工地尚未建成的蓝图。")
	for worker: String in active.keys():
		if active[worker].project == id:
			cancel(worker)
	projects[id].state = "cancelled"
	projects[id].line = "蓝图撤下；在地材料仍须搬回。"
	_reindex()
	_schedule_check()
	space_changed.emit([SimRouteTravel.cell(projects[id].cell)])
	return reply(true, projects[id].line)


func begin(actor: String, id: String, kind: String = "build") -> Dictionary:
	return _begin(actor, id, kind, false)


func _begin(actor: String, id: String, kind: String, during_commit: bool) -> Dictionary:
	if not _ready_actor(actor, true, during_commit) or not projects.has(id) or not kind in ["build", "demolish", "recover", "open", "close"]:
		return reply(false, "先停下手头的事；只有获准且能行动的同门可施工。")
	var project: Dictionary = projects[id]
	var rule: Dictionary = definitions.types[project.type]
	var sim: RefCounted = world.regions[definitions.site.region]
	if not can_observe(actor, SimRouteTravel.cell(project.cell)) or _project_busy(id):
		return reply(false, "先走到工地附近；同一处工程只由一人接手。")
	var material: int = sim.inventory.quantity(id, str(rule.item))
	if kind == "build" and project.state != "blueprint" or kind in ["demolish", "open", "close"] and project.state != "built" or kind == "recover" and (not project.state in ["cancelled", "removed"] or material == 0):
		return reply(false, "这项工程当前不适用此操作。")
	if kind in ["open", "close"] and (not rule.door or bool(project.open) == (kind == "open")):
		return reply(false, "此处没有需要这样操作的木门。")
	if kind == "demolish" and world.resting != null and world.resting.bed_reserved(id):
		return reply(false, "这张床已有人在用或正前来，先让对方结束休息。")
	var stand: Array = _work_cell(actor, SimRouteTravel.cell(project.cell))
	if stand.is_empty():
		return reply(false, "工地旁没有可达的站脚处。")
	var job: Dictionary = {"id": "construction_job:%d" % next_job, "actor": actor, "project": id, "kind": kind, "phase": "", "path": [], "segment_from": sim.actors[actor].position.duplicate(), "segment_started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + 1, "destination": [], "stand": stand, "started_ms": world.elapsed_ms, "work_started_ms": world.elapsed_ms, "previous_autonomous": bool(sim.actors[actor].autonomous), "reserved": false}
	var destination: Array = stand
	var phase: String = "to_site"
	if kind == "build" and not bool(project.delivered) or kind == "recover":
		phase = "to_supply"
		destination = project.material_cell if material > 0 else sim.places[definitions.site.source].cell
		if material == 0:
			if not sim.inventory.reserve(str(job.id), str(definitions.site.source), str(rule.item), int(rule.amount), actor):
				return reply(false, "库房可用木料不足；未搬出的材料仍在原库中。")
			job.reserved = true
	if not _route(job, destination, phase):
		sim.inventory.release(str(job.id))
		return reply(false, "眼下走不到材料或工地。")
	next_job += 1
	active[actor] = job
	SimActionContract.occupy(world, str(definitions.site.region), actor)
	sim.actors[actor].goal = "处理工地：" + str(rule.label)
	project.line = "有人接手，正在实际搬料或动工。"
	world.invalidate_region(str(definitions.site.region))
	return reply(true, "已接手工程；移动、搬料、动工均会经过世界时间。")


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func cancel(actor: String) -> bool:
	if not active.has(actor):
		return false
	var job: Dictionary = active[actor]
	var project: Dictionary = projects[job.project]
	if job.kind == "build" and job.phase == "work":
		project.work_ms = mini(int(definitions.types[project.type].work_ms), int(project.work_ms) + maxi(0, world.elapsed_ms - int(job.work_started_ms)))
	_release(job, "施工中断；已做工时和已取出的材料留在世界中。", "cancelled")
	return true


func next_boundary_ms() -> int:
	var boundary: int = next_check_ms
	for job: Dictionary in active.values():
		if not _can_continue(job):
			return world.elapsed_ms + 1
		var body: Dictionary = world.regions[definitions.site.region].actors[job.actor]
		boundary = mini(boundary, SimRouteTravel.crossing_ms(job, body, world.elapsed_ms) if str(job.phase).begins_with("to_") else int(job.due_ms))
	return boundary


func settle_at_ms(now: int) -> void:
	for actor: String in active.keys():
		var job: Dictionary = active[actor]
		world.synchronize_region(str(definitions.site.region))
		var sim: RefCounted = world.regions[definitions.site.region]
		var body: Dictionary = sim.actors[actor]
		if not _can_continue(job):
			cancel(actor)
			continue
		if str(job.phase).begins_with("to_"):
			if not job.path.is_empty() and not _step_open(sim, SimRouteTravel.cell(body.cell), SimRouteTravel.cell(job.path[0])):
				cancel(actor)
				continue
			sim.project_actor_route(actor, job, now)
		if now < int(job.due_ms):
			continue
		if str(job.phase).begins_with("to_"):
			if not job.path.is_empty():
				sim.set_actor_position(actor, TileGrid.cell_to_world(SimRouteTravel.cell(job.path.pop_front())))
			if not job.path.is_empty():
				SimRouteTravel.begin_segment(job, body, now, _speed())
				continue
			_arrived(job)
		elif job.phase == "pickup":
			_pickup(job)
		elif job.phase == "work":
			_complete(job)
	if next_check_ms <= now:
		next_check_ms = SimInventory.MAX_COUNT
		for actor: String in definitions.site.workers:
			var id: String = duty_for(actor)
			if not id.is_empty():
				_begin(actor, id, "build", true)
		_schedule_check()


func _can_continue(job: Dictionary) -> bool:
	var expected: Array = []
	if not str(job.phase).begins_with("to_"):
		var point: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(job.destination))
		expected = [point.x, point.y]
	return SimActionContract.can_continue(world, str(definitions.site.region), job.actor, &"construction", expected)


func duty_for(actor: String) -> String:
	if not definitions.site.workers.has(actor) or not authorized(actor) or owns_actor(actor):
		return ""
	var sim: RefCounted = world.regions[definitions.site.region]
	var body: Dictionary = sim.actors[actor]
	if not bool(body.autonomous) or not body.active.is_empty() or not world.actor_controls(actor, "action") or float(body.hunger) <= maxf(float(definitions.minimum_fullness), float(sim.config.needs.eat_below)) or float(body.energy) <= maxf(float(definitions.minimum_energy), float(sim.config.needs.rest_below)):
		return ""
	for id: String in projects:
		var project: Dictionary = projects[id]
		var rule: Dictionary = definitions.types[project.type]
		var stock: Dictionary = sim.stock_understanding(actor, str(definitions.site.source), str(rule.item))
		var near: bool = SimRouteTravel.point(body).distance_to(TileGrid.cell_to_world(SimRouteTravel.cell(project.cell))) <= float(definitions.site.notice_cells) * TileGrid.TILE_SIZE
		if project.state == "blueprint" and not _project_busy(id) and near and (sim.inventory.quantity(id, str(rule.item)) > 0 or bool(stock.known) and float(stock.amount) >= int(rule.amount)):
			var cell: Vector2i = SimRouteTravel.cell(project.cell)
			var newly_solid: bool = rule.kind in ["wall", "door"]
			if int(project.work_ms) < int(rule.work_ms) or not occupied(cell, newly_solid) and (not newly_solid or not SimMotionClearance.fixed_road_reserves(world, cell)):
				return id
	return ""


func _arrived(job: Dictionary) -> void:
	if job.phase == "to_supply":
		_work(job, "pickup", int(definitions.pickup_ms))
	elif job.phase == "to_store":
		var project: Dictionary = projects[job.project]
		var rule: Dictionary = definitions.types[project.type]
		var inventory: SimInventory = world.regions[definitions.site.region].inventory
		var count: int = inventory.quantity(job.project, str(rule.item))
		if not inventory.transfer(str(job.project) + ":return", job.project, str(definitions.site.source), str(rule.item), count):
			_release(job, "库房无法接收余料，材料留在脚边。")
			return
		project.delivered = false
		_release(job, "余料已实际搬回宗门库房。", "completed")
	else:
		var project: Dictionary = projects[job.project]
		project.carrier = ""
		_set_material_cell(project, job.stand)
		if job.kind == "build":
			project.delivered = true
		var rule: Dictionary = definitions.types[project.type]
		var duration: int = maxi(1, int(rule.work_ms) - int(project.work_ms)) if job.kind == "build" else int(rule.demolish_ms) if job.kind == "demolish" else int(definitions.operate_ms)
		_work(job, "work", duration)


func _pickup(job: Dictionary) -> void:
	var project: Dictionary = projects[job.project]
	var rule: Dictionary = definitions.types[project.type]
	var sim: RefCounted = world.regions[definitions.site.region]
	if bool(job.reserved):
		if not sim.inventory.transfer(str(job.project) + ":supply", str(definitions.site.source), job.project, str(rule.item), int(rule.amount), str(job.id)):
			_release(job, "预约材料无法取出，工程暂停。")
			return
		job.reserved = false
	project.carrier = str(job.actor)
	project.delivered = false
	var destination: Array = sim.places[definitions.site.source].cell if job.kind == "recover" else job.stand
	if not _route(job, destination, "to_store" if job.kind == "recover" else "to_site"):
		_release(job, "取料后道路不通，材料留在脚边。")


func _complete(job: Dictionary) -> void:
	var project: Dictionary = projects[job.project]
	var rule: Dictionary = definitions.types[project.type]
	var sim: RefCounted = world.regions[definitions.site.region]
	var cell: Vector2i = SimRouteTravel.cell(project.cell)
	if job.kind == "build":
		project.work_ms = int(rule.work_ms)
	if job.kind == "build" and rule.kind == "roof" and not roof_supported(cell):
		_release(job, "屋面缺少同高度近处墙柱支撑；工时与材料保留，补好支撑再续。")
		return
	var newly_solid: bool = job.kind == "close" or job.kind == "build" and rule.kind in ["wall", "door"]
	if not terrain_open(cell) or (rule.kind != "roof" and (job.kind == "build" or job.kind == "close") and occupied(cell, newly_solid)):
		_release(job, "占地尚有人、余料或地面不适用，清场后再续。")
		return
	if newly_solid and SimMotionClearance.fixed_road_reserves(world, cell):
		# Fixed couriers do not yet replan against structures, so keep their road
		# clear until that consumer is integrated. Work/materials stay in place.
		_release(job, "此处属运粮通道；工时与材料保留，调整通道后再续。")
		return
	# Preflight the whole transaction before spending completion materials,
	# issuing salvage, dirtying heat geometry or removing a supporting wall.
	var removals: Array[String] = []
	if job.kind == "demolish":
		removals = _removal_projects(str(job.project))
	var changed_cells: Array[Vector2i] = [cell]
	for id: String in removals:
		var removed_cell: Vector2i = SimRouteTravel.cell(projects[id].cell)
		if removed_cell not in changed_cells:
			changed_cells.append(removed_cell)
	if job.kind == "build" and not sim.inventory.can_consume(str(job.project) + ":build", job.project, str(rule.item), int(rule.amount)):
		_release(job, "到场工料不足，无法完成结构。")
		return
	if job.kind == "demolish" and not _can_remove_all(removals):
		_release(job, "拆除余料记录不一致；结构与材料保留。")
		return
	if not _before_thermal_change(str(rule.kind), changed_cells):
		_release(job, "环境尚未就绪；工时、材料与原结构保留，稍后再续。")
		return
	match str(job.kind):
		"build":
			if not sim.inventory.consume(str(job.project) + ":build", job.project, str(rule.item), int(rule.amount)):
				_after_thermal_change(str(rule.kind))
				_release(job, "到场工料不足，无法完成结构。")
				return
			project.state = "built"
			project.completed_ms = world.elapsed_ms
		"demolish":
			if not _remove(str(job.project), job.stand):
				_after_thermal_change(str(rule.kind))
				_release(job, "拆除余料记录不一致。")
				return
		"open", "close":
			project.open = job.kind == "open"
	if job.kind == "demolish":
		_collapse_roofs(removals.slice(1))
	_reindex()
	_after_thermal_change(str(rule.kind))
	_release(job, "结构已完工。" if job.kind == "build" else "拆除完成，余料还在工地。" if job.kind == "demolish" else "木门已打开。" if job.kind == "open" else "木门已关上。", "completed")
	# Observers only see the completed transaction, including collateral roofs,
	# derived rooms/heat geometry and released worker/material reservations.
	structures_changed.emit(changed_cells)
	space_changed.emit(changed_cells)


func _route(job: Dictionary, raw: Array, phase: String) -> bool:
	var sim: RefCounted = world.regions[definitions.site.region]
	var body: Dictionary = sim.actors[job.actor]
	var target: Vector2i = SimRouteTravel.cell(raw)
	var from: Vector2i = SimRouteTravel.cell(body.cell)
	var path: Array[Vector2i] = sim.find_path(from, target)
	if from != target and path.is_empty():
		return false
	job.path = []
	for cell: Vector2i in path:
		job.path.append([cell.x, cell.y])
	if job.path.is_empty() and not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(target)):
		job.path.append([target.x, target.y])
	job.destination = raw.duplicate()
	job.phase = phase
	SimRouteTravel.begin_segment(job, body, world.elapsed_ms, _speed())
	return true


func _work(job: Dictionary, phase: String, duration: int) -> void:
	job.phase = phase
	job.path = []
	job.work_started_ms = world.elapsed_ms
	job.due_ms = world.elapsed_ms + duration


func _release(job: Dictionary, line: String, status: String = "failed") -> void:
	var sim: RefCounted = world.regions[definitions.site.region]
	var project: Dictionary = projects[job.project]
	if project.carrier == job.actor:
		_set_material_cell(project, sim.actors[job.actor].cell)
		project.carrier = ""
		sim.actors[job.actor].goal = "在脚边留下木料"
	project.line = line
	sim.actors[job.actor].goal = line
	sim.actors[job.actor].retry_ms = world.elapsed_ms + int(definitions.check_ms)
	active.erase(job.actor)
	SimActionContract.release(world, str(definitions.site.region), job.actor, bool(job.previous_autonomous), job.id)
	_schedule_check()
	SimActionContract.publish_finished(world, SimActionContract.view(world, "construction", job.id, job.actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), status, job.project), line)


func _work_cell(actor: String, target: Vector2i) -> Array:
	var sim: RefCounted = world.regions[definitions.site.region]
	var from: Vector2i = SimRouteTravel.cell(sim.actors[actor].cell)
	var result: Array = []
	var best: int = SimInventory.MAX_COUNT
	for direction: Vector2i in SIDES:
		var cell: Vector2i = target + direction
		if not terrain_open(cell) or blocked(cell):
			continue
		var path: Array[Vector2i] = sim.find_path(from, cell)
		if from != cell and path.is_empty():
			continue
		if path.size() < best:
			best = path.size()
			result = [cell.x, cell.y]
	return result


func _ready_actor(actor: String, require_idle: bool, during_commit: bool = false) -> bool:
	if not authorized(actor) or not during_commit and world.elapsed_ms != world.target_ms or not SimActionContract.can_act(world, str(definitions.site.region), actor):
		return false
	world.synchronize_region(str(definitions.site.region))
	return not require_idle or SimActionContract.can_begin(world, str(definitions.site.region), actor)


func can_observe(actor: String, cell: Vector2i) -> bool:
	if not authorized(actor):
		return false
	var body: Dictionary = world.regions[definitions.site.region].actors[actor]
	return SimRouteTravel.point(body).distance_to(TileGrid.cell_to_world(cell)) <= float(definitions.site.observe_cells) * TileGrid.TILE_SIZE


func terrain_open(cell: Vector2i) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < ReolWorld.WORLD_SIZE and cell.y < ReolWorld.WORLD_SIZE and (not _terrain.is_valid() or bool(_terrain.call(cell)))


func protected_cell(cell: Vector2i) -> bool:
	for sim: RefCounted in world.regions.values():
		if SimWorkplaces.roofed(sim.places, cell):
			return true
		for place: Dictionary in sim.places.values():
			if SimRouteTravel.cell(place.cell) == cell:
				return true
	return false


func occupied(cell: Vector2i, include_motion: bool = true) -> bool:
	var lifecycle: Variant = world.get("object_lifecycle")
	if lifecycle != null:
		var placed: Dictionary = lifecycle.ground.query(Rect2i(cell, Vector2i.ONE), 512)
		if not bool(placed.ok) or not placed.ids.is_empty():
			return true
	if world.large_bodies != null and world.large_bodies.blocked(cell):
		return true
	if include_motion and _incoming.is_valid() and bool(_incoming.call(cell)):
		return true
	for id: String in projects:
		var project: Dictionary = projects[id]
		if str(project.carrier).is_empty() and SimRouteTravel.cell(project.material_cell) == cell and world.regions[definitions.site.region].inventory.quantity(id, str(definitions.types[project.type].item)) > 0:
			return true
	for sim: RefCounted in world.regions.values():
		for body: Dictionary in sim.actors.values():
			if bool(body.alive) and SimRouteTravel.cell(body.cell) == cell:
				return true
	if world.avian_life != null:
		for id: String in world.avian_life.birds:
			if int(world.avian_life.birds[id].altitude) == 0 and world.avian_life.body_cell(id) == cell:
				return true
	# Every original owner must finish projecting the old interval before a
	# new wall can take its current leg, including either diagonal side.
	if include_motion and SimMotionClearance.active_segment_reserves(world, cell):
		return true
	return false


func _project_busy(id: String) -> bool:
	for job: Dictionary in active.values():
		if job.project == id:
			return true
	return false


func _step_open(sim: RefCounted, from: Vector2i, to: Vector2i) -> bool:
	return not blocked(to) and (not sim._step_validator.is_valid() or bool(sim._step_validator.call(from, to - from)))


func _speed() -> float:
	return float(world.regions[definitions.site.region].motion_rules.motion.speed)


func _schedule_check() -> void:
	for project: Dictionary in projects.values():
		if project.state == "blueprint":
			next_check_ms = mini(next_check_ms, world.elapsed_ms + int(definitions.check_ms))
			return
	next_check_ms = SimInventory.MAX_COUNT


func project_at(cell: Vector2i, layer: String = "ground") -> String:
	return str((_roofs if layer == "roof" else _cells).get(cell, ""))


func roof_supported(cell: Vector2i, except_project: String = "") -> bool:
	var level: int = int(_elevation.call(cell)) if _elevation.is_valid() else 0
	for id: String in projects:
		if id == except_project:
			continue
		var project: Dictionary = projects[id]
		if project.state != "built" or definitions.types[project.type].kind not in ["wall", "door"]:
			continue
		var other: Vector2i = SimRouteTravel.cell(project.cell)
		if absi(other.x - cell.x) + absi(other.y - cell.y) <= int(definitions.roof_span) and (not _elevation.is_valid() or int(_elevation.call(other)) == level):
			return true
	return false


func roofed(cell: Vector2i) -> bool:
	for sim: RefCounted in world.regions.values():
		if SimWorkplaces.roofed(sim.places, cell):
			return true
	var id: String = project_at(cell, "roof")
	return not id.is_empty() and projects[id].state == "built" and roof_supported(cell)


func thermal_barrier(cell: Vector2i) -> bool:
	# Facts only: an open door conducts as an opening, while a blueprint is
	# still paper. The heat domain owns conductance and fixed-space storage.
	return _closed_wall_at(cell)


func blocks_sight(cell: Vector2i) -> bool:
	# Current built types are opaque wood. Keep sight separate from furniture
	# collision and from heat coefficients so later materials can differ.
	return _closed_wall_at(cell)


func _closed_wall_at(cell: Vector2i) -> bool:
	if _blocked.has(cell):
		return true
	for sim: RefCounted in world.regions.values():
		if SimWorkplaces.wall_at(sim.places, cell):
			return true
	return false


func thermal_roofed(cell: Vector2i) -> bool:
	return roofed(cell)


func _before_thermal_change(kind: String, changed_cells: Array[Vector2i]) -> bool:
	if kind in ["wall", "door", "roof"] and world.environment_fields != null:
		if world.environment_fields is SimWorldEnvironmentFields:
			# The outdoor field has no wall, door or roof insulation model. Its
			# existing state must already be settled at the shared event time.
			return world.environment_fields.last_ms == world.elapsed_ms and world.environment_fields.can_settle_at_ms(world.elapsed_ms)
		if not world.environment_fields.can_change_topology(world.elapsed_ms, changed_cells):
			return false
		return world.environment_fields.before_topology_change(world.elapsed_ms)
	return true


func _after_thermal_change(kind: String) -> void:
	if kind in ["wall", "door", "roof"] and world.environment_fields != null:
		if world.environment_fields is SimWorldEnvironmentFields:
			return
		# Called only after a successful operation and all resulting collapses
		# have been reindexed. Generic reindex/restore never advances heat.
		world.environment_fields.after_topology_change(world.elapsed_ms)


func _remove(id: String, material_cell: Array) -> bool:
	var project: Dictionary = projects[id]
	var rule: Dictionary = definitions.types[project.type]
	var inventory: SimInventory = world.regions[definitions.site.region].inventory
	var salvage: String = id + ":salvage"
	if not inventory.create_container(salvage, {str(rule.item): int(rule.salvage)}) or not inventory.transfer(salvage, salvage, id, str(rule.item), int(rule.salvage)):
		return false
	project.state = "removed"
	project.removed_ms = world.elapsed_ms
	project.open = false
	project.carrier = ""
	_set_material_cell(project, material_cell)
	return true


func material_cell_referenced(cell: Vector2i) -> bool:
	# The current save contract validates retained project material coordinates,
	# including zero-stock terminal projects. Do not scan that history per brush.
	return _material_cells.has(cell)


func _set_material_cell(project: Dictionary, raw: Array) -> void:
	var previous: Vector2i = SimRouteTravel.cell(project.material_cell)
	var remaining: int = int(_material_cells.get(previous, 0)) - 1
	if remaining <= 0:
		_material_cells.erase(previous)
	else:
		_material_cells[previous] = remaining
	project.material_cell = raw.duplicate()
	var cell: Vector2i = SimRouteTravel.cell(raw)
	_material_cells[cell] = int(_material_cells.get(cell, 0)) + 1


func _removal_projects(id: String) -> Array[String]:
	var result: Array[String] = [id]
	if definitions.types[projects[id].type].kind not in ["wall", "door"]:
		return result
	for other: String in projects:
		var project: Dictionary = projects[other]
		if project.state == "built" and definitions.types[project.type].kind == "roof" and not roof_supported(SimRouteTravel.cell(project.cell), id):
			result.append(other)
	return result


func _can_remove_all(ids: Array[String]) -> bool:
	var inventory: SimInventory = world.regions[definitions.site.region].inventory
	for id: String in ids:
		var rule: Dictionary = definitions.types[projects[id].type]
		var salvage: String = id + ":salvage"
		# _remove performs no external calls between creating this source and
		# transferring into the original project container. Check the entire set
		# now, so a dependent roof cannot fail after its support was removed.
		if projects[id].state != "built" or not inventory.containers.has(id) or inventory.containers.has(salvage) or inventory.operations.has(salvage) or inventory.quantity(id, str(rule.item)) > SimInventory.MAX_COUNT - int(rule.salvage):
			return false
	return true


func _collapse_roofs(ids: Array[String]) -> void:
	for id: String in ids:
		var project: Dictionary = projects[id]
		for actor: String in active.keys():
			if active[actor].project == id:
				cancel(actor)
		var cell: Vector2i = SimRouteTravel.cell(project.cell)
		var drop: Array = project.cell.duplicate()
		var below: String = project_at(cell)
		if not below.is_empty() and projects[below].state == "built" and definitions.types[projects[below].type].kind in ["wall", "door"]:
			for side: Vector2i in SIDES:
				if terrain_open(cell + side) and not blocked(cell + side):
					drop = [cell.x + side.x, cell.y + side.y]
					break
		if _remove(id, drop):
			project.line = "支撑失去，木屋面塌回有限余料；下方床铺仍在。"


func blocked(cell: Vector2i) -> bool:
	if _blocked.has(cell):
		return true
	for sim: RefCounted in world.regions.values():
		if SimWorkplaces.blocked(sim.places, cell):
			return true
	return false


func is_bed(id: String) -> bool:
	return projects.has(id) and projects[id].state == "built" and definitions.types[projects[id].type].kind == "bed"


func space_at(cell: Vector2i) -> Dictionary:
	var space: Dictionary = _spaces.get(cell, {}).duplicate(true)
	if not space.is_empty():
		space.roofed = roofed(cell)
	return space


func site_contains(cell: Vector2i) -> bool:
	return sites.has("sect_yard") and site_bounds().has_point(cell)


func site_bounds() -> Rect2i:
	return Rect2i(SimRouteTravel.cell(sites.sect_yard.origin), Vector2i(int(definitions.site.width), int(definitions.site.height))) if sites.has("sect_yard") else Rect2i()


static func cells_in(bounds: Rect2i) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for y: int in range(bounds.position.y, bounds.end.y):
		for x: int in range(bounds.position.x, bounds.end.x):
			result.append(Vector2i(x, y))
	return result


func _reindex() -> void:
	_cells.clear()
	_roofs.clear()
	_blocked.clear()
	_material_cells.clear()
	for id: String in projects:
		var project: Dictionary = projects[id]
		var material: Vector2i = SimRouteTravel.cell(project.material_cell)
		_material_cells[material] = int(_material_cells.get(material, 0)) + 1
		var cell: Vector2i = SimRouteTravel.cell(project.cell)
		if project.state in ["blueprint", "built"]:
			if definitions.types[project.type].kind == "roof":
				_roofs[cell] = id
			else:
				_cells[cell] = id
		if project.state == "built" and definitions.types[project.type].kind in ["wall", "door"] and not bool(project.open):
			_blocked[cell] = true
	_spaces = SimEnclosedSpace.detect(site_bounds(), projects, definitions.types, _elevation)
	if world.resting != null:
		world.resting.structures_changed()
	if world.weather != null:
		world.weather.structures_changed()


static func empty_state() -> Dictionary:
	return {"version": 2, "sites": {}, "projects": {}, "active": {}, "next_project": 1, "next_job": 1, "next_check_ms": SimInventory.MAX_COUNT}


func to_dict() -> Dictionary:
	return {"version": 2, "sites": sites.duplicate(true), "projects": projects.duplicate(true), "active": active.duplicate(true), "next_project": next_project, "next_job": next_job, "next_check_ms": next_check_ms}


func restore(data: Dictionary) -> bool:
	if not Schema.valid(data, self):
		return false
	sites = data.sites.duplicate(true)
	projects = data.projects.duplicate(true)
	active = data.active.duplicate(true)
	next_project = int(data.next_project)
	next_job = int(data.next_job)
	next_check_ms = int(data.next_check_ms)
	_reindex()
	return true


func space_valid() -> bool:
	if not sites.is_empty():
		for cell: Vector2i in cells_in(site_bounds()):
			if not terrain_open(cell) or protected_cell(cell):
				return false
	for project: Dictionary in projects.values():
		if not terrain_open(SimRouteTravel.cell(project.cell)) or not terrain_open(SimRouteTravel.cell(project.material_cell)):
			return false
		if project.state == "built" and definitions.types[project.type].kind == "roof" and not roof_supported(SimRouteTravel.cell(project.cell)):
			return false
	for id: String in projects:
		var project: Dictionary = projects[id]
		if str(project.carrier).is_empty() and blocked(SimRouteTravel.cell(project.material_cell)) and world.regions[definitions.site.region].inventory.quantity(id, str(definitions.types[project.type].item)) > 0:
			return false
	for sim: RefCounted in world.regions.values():
		for body: Dictionary in sim.actors.values():
			if blocked(SimRouteTravel.cell(body.cell)):
				return false
	for id: String in world.avian_life.birds:
		if int(world.avian_life.birds[id].altitude) == 0 and blocked(world.avian_life.body_cell(id)):
			return false
	for job: Dictionary in active.values():
		for raw: Array in job.path:
			if not terrain_open(SimRouteTravel.cell(raw)):
				return false
	return true


static func reply(ok: bool, line: String) -> Dictionary:
	return {"ok": ok, "line": line}
