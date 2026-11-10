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
var cultivation: Dictionary = {}
var active: Dictionary = {}
var zones: Dictionary = {}
var _pending: Array[String] = []
var _supports: Dictionary[Vector2i, String] = {}
var _bed_ids: Array[String] = []
var next_zone: int = 1
var next_project: int = 1
var next_job: int = 1
var next_check_ms: int = SimInventory.MAX_COUNT
var _changing: bool = false
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
	if not Shape.keys(data, ["version", "site", "check_ms", "minimum_fullness", "minimum_energy", "operate_ms", "pickup_ms", "roof_span", "types"]) or data.version != 2 or not Shape.count(data.roof_span, 1, 4) or not Shape.keys(data.site, ["region", "source", "builders", "workers", "width", "height", "source_cells", "notice_cells", "observe_cells"]):
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
	if not Shape.count(data.minimum_fullness, 1, 100) or not Shape.count(data.minimum_energy, 1, 100) or not data.types is Dictionary or data.types.is_empty() or data.types.size() > 256:
		return false
	for type: Variant in data.types:
		if not SimInventory._nonempty(type) or not SimConstructionGeometry.valid_type(data.types[type]):
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


func register_site(actor: String, origin: Vector2i, size: Vector2i = Vector2i.ZERO) -> Dictionary:
	if not authorized(actor) or sites.size() >= 16 or not _ready_actor(actor, false):
		return reply(false, "须由获准同门在库房附近划定工地；工地数量已达上限。")
	var sim: RefCounted = world.regions[definitions.site.region]
	var source: Vector2i = SimRouteTravel.cell(sim.places[definitions.site.source].cell)
	if source.distance_to(origin) > float(definitions.site.source_cells) or SimRouteTravel.point(sim.actors[actor]).distance_to(TileGrid.cell_to_world(origin)) > float(definitions.site.observe_cells) * TileGrid.TILE_SIZE:
		return reply(false, "这片地离库房或你太远，不能在这里登记宗门工地。")
	if size == Vector2i.ZERO:
		size = Vector2i(int(definitions.site.width), int(definitions.site.height))
	if size.x < 1 or size.y < 1 or size.x > 32 or size.y > 32:
		return reply(false, "工地边长须在1至32格内。")
	var bounds := Rect2i(origin, size)
	for site: String in sites:
		if bounds.intersects(site_bounds(site)):
			return reply(false, "工地不能重叠；请另选一片空地。")
	for cell: Vector2i in cells_in(bounds):
		if not terrain_open(cell) or protected_cell(cell):
			return reply(false, "工地需是一片连续草地，并避开已有生活设施。")
	var site_id: String = "sect_yard" if sites.is_empty() else "construction_site:%d" % (sites.size() + 1)
	sites[site_id] = {"size": [size.x, size.y],"region": str(definitions.site.region), "owner": str(sim.config.institution.id), "origin": [origin.x, origin.y], "created_by": actor, "created_ms": world.elapsed_ms}
	_reindex()
	return {"ok": true, "line": "已登记宗门工地：此处公料仅供获准工程使用。", "site": site_id}


func place(actor: String, type: String, cell: Vector2i, rotation: int = 0) -> Dictionary:
	if not _ready_actor(actor, false) or not definitions.types.has(type) or rotation < 0 or rotation > 3:
		return reply(false, "此定义或朝向不适用。")
	var site: String = site_at(cell)
	if site.is_empty():
		return reply(false, "请在已登记的工地内落蓝图。")
	var rule: Dictionary = definitions.types[type]
	var footprint: Array[Vector2i] = SimConstructionGeometry.cells({"cell": [cell.x, cell.y], "rotation": rotation}, rule)
	for covered: Vector2i in footprint:
		if site_at(covered) != site or not can_observe(actor, covered) or not terrain_open(covered) or protected_cell(covered) or not project_at(covered, str(rule.layer)).is_empty():
			return reply(false, "整个占地须位于同一工地的可见空地内。")
	var id: String = "construction:%d" % next_project
	var sim: RefCounted = world.regions[definitions.site.region]
	if not sim.inventory.create_container(id, {}):
		return reply(false, "无法登记这批材料的容器。")
	next_project += 1
	projects[id] = {"site": site, "type": type, "cell": [cell.x, cell.y], "rotation": rotation, "hp": 0, "state": "blueprint", "open": false, "created_by": actor, "created_ms": world.elapsed_ms, "completed_ms": 0, "removed_ms": 0, "work_ms": 0, "material_cell": [cell.x, cell.y], "carrier": "", "delivered": false, "line": "蓝图已画好，等待取料施工。"}
	_reindex()
	_schedule_check()
	space_changed.emit(footprint)
	return {"ok": true, "line": "蓝图不挡路；材料到场并完成施工后才成为实物。", "project": id}


func project_cells(id: String) -> Array[Vector2i]:
	return SimConstructionGeometry.cells(projects[id], definitions.types[projects[id].type]) if projects.has(id) else []


func fact(id: String, name: String) -> bool:
	return projects.has(id) and SimConstructionGeometry.fact(projects[id], definitions.types[projects[id].type], name)


func has_capability(id: String, capability: String) -> bool:
	return projects.has(id) and projects[id].state == "built" and definitions.types[projects[id].type].capabilities.has(capability)


func operation_slots(id: String, capability: String = "") -> Array[Dictionary]:
	return SimConstructionGeometry.slots(projects[id], definitions.types[projects[id].type], capability) if projects.has(id) else []


func _completion_clear(id: String, newly_solid: bool) -> bool:
	var roof: bool = definitions.types[projects[id].type].layer == "roof"
	for cell: Vector2i in project_cells(id):
		if not terrain_open(cell) or not roof and occupied(cell, newly_solid):
			return false
		if newly_solid and SimMotionClearance.fixed_road_reserves(world, cell):
			return false
	return true


func _facility_reserved(id: String) -> bool:
	return world.resting != null and world.resting.bed_reserved(id) or world.facility_use != null and world.facility_use.project_reserved(id)


func contents_valid(project: Dictionary, items: Dictionary) -> bool:
	var rule: Dictionary = definitions.types[project.type]
	if not rule.capabilities.has("storage"):
		return false
	var terms: Dictionary = rule.capabilities.storage
	var total: int = 0
	for item: Variant in items:
		if not SimInventory._nonempty(item) or not Shape.count(items[item], 0, int(terms.capacity)) or not terms.items.is_empty() and item not in terms.items:
			return false
		total += int(items[item])
		if total > int(terms.capacity):
			return false
	return true


func _contents_empty(id: String) -> bool:
	var inventory: SimInventory = world.regions[definitions.site.region].inventory
	return not inventory.containers.get(id + ":contents", {}).values().any(func(value: int) -> bool: return value > 0)


func damage(id: String, amount: int) -> Dictionary:
	# Authority effect: callers own attack legality, reach, accuracy and cost.
	# The building owner alone settles armor, durability and structural loss.
	if _changing or world.elapsed_ms != world.target_ms or world.environment_boundary_active() or not projects.has(id) or projects[id].state != "built" or amount < 1 or amount > 1000000:
		return reply(false, "当前对象不能结算结构伤害。")
	var project: Dictionary = projects[id]
	var rule: Dictionary = definitions.types[project.type]
	var dealt: int = mini(int(project.hp), maxi(0, amount - int(rule.armor)))
	if dealt < int(project.hp):
		project.hp = int(project.hp) - dealt
		structures_changed.emit(project_cells(id))
		return {"ok": true, "damage": dealt, "destroyed": false, "line": "结构承受了伤害。"}
	var removals: Array[String] = _removal_projects(id)
	var changed: Array[Vector2i] = []
	for removed: String in removals:
		for cell: Vector2i in project_cells(removed):
			if cell not in changed:
				changed.append(cell)
	if not _can_remove_all(removals, true) or not _before_thermal_change(str(project.type), changed):
		return reply(false, "结构事务尚未就绪，原耐久与内容物保留。")
	var drop: Array = _drop_cell(id, removals)
	if drop.is_empty():
		return reply(false, "现场没有安全的残料落点，原结构保留。")
	_changing = true
	for actor: String in SimAvianLife.sorted_keys(active):
		if active[actor].project in removals:
			_cancel(actor)
	if world.facility_use != null:
		world.facility_use.cancel_projects(removals)
	if world.resting != null:
		for actor: String in world.resting.active.keys():
			if world.resting.active[actor].bed in removals:
				world.resting.cancel(actor)
	_remove(id, drop)
	project.state = "ruined"
	project.line = "结构损毁，残骸与原内容物留在现场；清空后可清理。"
	_collapse_roofs(removals.slice(1))
	_reindex()
	_after_thermal_change(str(project.type))
	_changing = false
	structures_changed.emit(changed)
	space_changed.emit(changed)
	return {"ok": true, "damage": dealt, "destroyed": true, "line": str(project.line)}


func cancel_project(actor: String, id: String) -> Dictionary:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return reply(false, "世界事务尚未结清，请稍后再撤销蓝图。")
	if _changing or not authorized(actor) or not projects.has(id) or projects[id].state != "blueprint" or not can_observe(actor, SimRouteTravel.cell(projects[id].cell)):
		return reply(false, "只能在场撤销本工地尚未建成的蓝图。")
	for worker: String in active.keys():
		if active[worker].project == id:
			cancel(worker)
	projects[id].state = "cancelled"
	projects[id].line = "蓝图撤下；在地材料仍须搬回。"
	_reindex()
	_schedule_check()
	space_changed.emit(project_cells(id))
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
	if kind == "build" and project.state != "blueprint" or kind == "demolish" and project.state not in ["built", "ruined"] or kind in ["open", "close"] and project.state != "built" or kind == "recover" and (not project.state in ["cancelled", "removed", "ruined"] or material == 0):
		return reply(false, "这项工程当前不适用此操作。")
	if kind in ["open", "close"] and (not rule.door or bool(project.open) == (kind == "open")):
		return reply(false, "此处没有需要这样操作的木门。")
	if kind == "demolish" and (_facility_reserved(id) or not _contents_empty(id)):
		return reply(false, "这张床已有人在用或正前来，先让对方结束休息。")
	var stand: Array = _work_cell(actor, id)
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
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	return false if _changing else _cancel(actor)


func _cancel(actor: String) -> bool:
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
		boundary = mini(boundary, SimRouteTravel.next_boundary(job, body, world.elapsed_ms, route_step) if str(job.phase).begins_with("to_") else int(job.due_ms))
	return boundary


func settle_at_ms(now: int) -> void:
	for actor: String in SimAvianLife.sorted_keys(active):
		var job: Dictionary = active[actor]
		world.synchronize_region(str(definitions.site.region))
		var sim: RefCounted = world.regions[definitions.site.region]
		var body: Dictionary = sim.actors[actor]
		if not _can_continue(job):
			cancel(actor)
			continue
		if str(job.phase).begins_with("to_"):
			if not SimRouteTravel.repair(sim, actor, job, now, job.destination, -1.0, route_step):
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
	for id: String in _pending:
		var project: Dictionary = projects[id]
		var rule: Dictionary = definitions.types[project.type]
		var stock: Dictionary = sim.stock_understanding(actor, str(definitions.site.source), str(rule.item))
		var near: bool = SimRouteTravel.point(body).distance_to(TileGrid.cell_to_world(SimRouteTravel.cell(project.cell))) <= float(definitions.site.notice_cells) * TileGrid.TILE_SIZE
		if project.state == "blueprint" and not _project_busy(id) and near and (sim.inventory.quantity(id, str(rule.item)) > 0 or bool(stock.known) and float(stock.amount) >= int(rule.amount)):
			var cell: Vector2i = SimRouteTravel.cell(project.cell)
			var newly_solid: bool = bool(rule.facts.movement_blocked)
			if int(project.work_ms) < int(rule.work_ms) or _completion_clear(id, newly_solid):
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
		_set_material_cell(str(job.project), job.stand)
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
	if job.kind == "build" and rule.layer == "roof":
		for covered: Vector2i in project_cells(str(job.project)):
			if not roof_supported(covered):
				_release(job, "屋面缺少近处支撑；工时与材料保留。")
				return
	var newly_solid: bool = job.kind == "close" or job.kind == "build" and bool(rule.facts.movement_blocked)
	if (job.kind == "build" or job.kind == "close") and not _completion_clear(str(job.project), newly_solid):
		_release(job, "占地有人、余料或通道尚未清空，工时与材料保留。")
		return
	# Preflight the whole transaction before spending completion materials,
	# issuing salvage, dirtying heat geometry or removing a supporting wall.
	var removals: Array[String] = []
	if job.kind == "demolish":
		removals = _removal_projects(str(job.project))
	var changed_cells: Array[Vector2i] = project_cells(str(job.project))
	for id: String in removals:
		for removed_cell: Vector2i in project_cells(id):
			if removed_cell not in changed_cells:
				changed_cells.append(removed_cell)
	if job.kind == "build" and not sim.inventory.can_consume(str(job.project) + ":build", job.project, str(rule.item), int(rule.amount)):
		_release(job, "到场工料不足，无法完成结构。")
		return
	if job.kind == "demolish" and not _can_remove_all(removals):
		_release(job, "拆除余料记录不一致；结构与材料保留。")
		return
	if not _before_thermal_change(str(project.type), changed_cells):
		_release(job, "环境尚未就绪；工时、材料与原结构保留，稍后再续。")
		return
	match str(job.kind):
		"build":
			if not sim.inventory.consume(str(job.project) + ":build", job.project, str(rule.item), int(rule.amount)):
				_after_thermal_change(str(project.type))
				_release(job, "到场工料不足，无法完成结构。")
				return
			project.state = "built"
			project.hp = int(rule.max_hp)
			if rule.capabilities.has("storage"):
				sim.inventory.create_container(str(job.project) + ":contents", {})
			if rule.capabilities.has("cultivation"):
				var terms: Dictionary = rule.capabilities.cultivation
				cultivation[job.project] = {"substrate": terms.substrate, "water": int(terms.initial_water), "plant": ""}
			project.completed_ms = world.elapsed_ms
		"demolish":
			if not _remove(str(job.project), job.stand):
				_after_thermal_change(str(project.type))
				_release(job, "拆除余料记录不一致。")
				return
		"open", "close":
			project.open = job.kind == "open"
	if job.kind == "demolish":
		_collapse_roofs(removals.slice(1))
	_reindex()
	_after_thermal_change(str(project.type))
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
		_set_material_cell(str(job.project), sim.actors[job.actor].cell)
		project.carrier = ""
		sim.actors[job.actor].goal = "在脚边留下木料"
	project.line = line
	sim.actors[job.actor].goal = line
	sim.actors[job.actor].retry_ms = world.elapsed_ms + int(definitions.check_ms)
	active.erase(job.actor)
	SimActionContract.release(world, str(definitions.site.region), job.actor, bool(job.previous_autonomous), job.id)
	_schedule_check()
	SimActionContract.publish_finished(world, SimActionContract.view(world, "construction", job.id, job.actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), status, job.project), line)


func _work_cell(actor: String, id: String) -> Array:
	var sim: RefCounted = world.regions[definitions.site.region]
	var from: Vector2i = SimRouteTravel.cell(sim.actors[actor].cell)
	var result: Array = []
	var best: int = SimInventory.MAX_COUNT
	var footprint: Array[Vector2i] = project_cells(id)
	var candidates: Dictionary = {}
	for target: Vector2i in footprint:
		for direction: Vector2i in SIDES:
			var cell: Vector2i = target + direction
			if cell in footprint or candidates.has(cell) or not terrain_open(cell) or blocked(cell) or world.facility_use != null and world.facility_use.cell_reserved(cell, actor):
				continue
			candidates[cell] = true
			var path: Array[Vector2i] = sim.find_path(from, cell)
			if from != cell and path.is_empty():
				continue
			if path.size() < best:
				best = path.size()
				result = [cell.x, cell.y]
	return result


func _ready_actor(actor: String, require_idle: bool, during_commit: bool = false) -> bool:
	if _changing or not authorized(actor) or not during_commit and world.elapsed_ms != world.target_ms or not SimActionContract.can_act(world, str(definitions.site.region), actor):
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
	if world.plants != null and world.plants.blocked(cell):
		return true
	if world.large_bodies != null and world.large_bodies.blocked(cell):
		return true
	if include_motion and _incoming.is_valid() and bool(_incoming.call(cell)):
		return true
	for id: String in _project_ids():
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


func route_step(from: Vector2i, step: Vector2i) -> bool:
	return _step_open(world.regions[definitions.site.region], from, from + step)


func _speed() -> float:
	return float(world.regions[definitions.site.region].motion_rules.motion.speed)


func _schedule_check() -> void:
	next_check_ms = mini(next_check_ms, world.elapsed_ms + int(definitions.check_ms)) if not _pending.is_empty() else SimInventory.MAX_COUNT


func project_at(cell: Vector2i, layer: String = "ground") -> String:
	return str((_roofs if layer == "roof" else _cells).get(cell, ""))


func roof_supported(cell: Vector2i, except_project: String = "") -> bool:
	var level: int = int(_elevation.call(cell)) if _elevation.is_valid() else 0
	var span: int = int(definitions.roof_span)
	for y: int in range(-span, span + 1):
		for x: int in range(-span, span + 1):
			if absi(x) + absi(y) > span:
				continue
			var other: Vector2i = cell + Vector2i(x, y)
			var id: String = str(_supports.get(other, ""))
			if not id.is_empty() and id != except_project and projects[id].state == "built" and (not _elevation.is_valid() or int(_elevation.call(other)) == level):
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
	return _physical_fact(cell, "thermal_barrier")


func blocks_sight(cell: Vector2i) -> bool:
	# Current built types are opaque wood. Keep sight separate from furniture
	# collision and from heat coefficients so later materials can differ.
	return _physical_fact(cell, "sight_blocked")


func _physical_fact(cell: Vector2i, name: String) -> bool:
	var id: String = project_at(cell)
	if not id.is_empty() and fact(id, name):
		return true
	for sim: RefCounted in world.regions.values():
		if SimWorkplaces.wall_at(sim.places, cell):
			return true
	return false


func thermal_roofed(cell: Vector2i) -> bool:
	return roofed(cell)


func _changes_thermal(type: String) -> bool:
	var rule: Dictionary = definitions.types[type]
	return rule.layer == "roof" or bool(rule.facts.thermal_barrier) or bool(rule.facts.enclosure_boundary) or bool(rule.facts.roof_support)


func _before_thermal_change(type: String, changed_cells: Array[Vector2i]) -> bool:
	if world.environment_fields is SimWorldEnvironmentFields:
		return world.environment_fields.before_topology_change(world.elapsed_ms, changed_cells)
	if _changes_thermal(type) and world.environment_fields != null:
		if not world.environment_fields.can_change_topology(world.elapsed_ms, changed_cells):
			return false
		return world.environment_fields.before_topology_change(world.elapsed_ms)
	return true


func _after_thermal_change(type: String) -> void:
	if world.environment_fields is SimWorldEnvironmentFields:
		var updated: bool = world.environment_fields.after_topology_change(world.elapsed_ms)
		assert(updated, "preflighted construction environment publication failed")
		return
	if _changes_thermal(type) and world.environment_fields != null:
		# Called only after a successful operation and all resulting collapses
		# have been reindexed. Generic reindex/restore never advances heat.
		world.environment_fields.after_topology_change(world.elapsed_ms)


func _remove(id: String, material_cell: Array) -> bool:
	var project: Dictionary = projects[id]
	var rule: Dictionary = definitions.types[project.type]
	var inventory: SimInventory = world.regions[definitions.site.region].inventory
	var salvage: String = id + ":salvage"
	if project.state != "ruined":
		if not inventory.create_container(salvage, {str(rule.item): int(rule.salvage)}) or not inventory.transfer(salvage, salvage, id, str(rule.item), int(rule.salvage)):
			return false
	project.state = "removed"
	project.hp = 0
	project.removed_ms = world.elapsed_ms
	project.open = false
	project.carrier = ""
	_set_material_cell(id, material_cell)
	return true


func material_cell_referenced(cell: Vector2i) -> bool:
	# The current save contract validates retained project material coordinates,
	# including zero-stock terminal projects. Do not scan that history per brush.
	return _material_cells.has(cell)


func _set_material_cell(id: String, raw: Array) -> void:
	var project: Dictionary = projects[id]
	var previous: Vector2i = SimRouteTravel.cell(project.material_cell)
	var remaining: int = int(_material_cells.get(previous, 0)) - 1
	if remaining <= 0:
		_material_cells.erase(previous)
	else:
		_material_cells[previous] = remaining
	project.material_cell = raw.duplicate()
	var cell: Vector2i = SimRouteTravel.cell(raw)
	_material_cells[cell] = int(_material_cells.get(cell, 0)) + 1
	world.regions[definitions.site.region].inventory.contents_changed.emit(id)


func _removal_projects(id: String) -> Array[String]:
	var result: Array[String] = [id]
	if not bool(definitions.types[projects[id].type].facts.roof_support):
		return result
	var candidates: Dictionary = {}
	var span: int = int(definitions.roof_span)
	for support: Vector2i in project_cells(id):
		for y: int in range(-span, span + 1):
			for x: int in range(-span, span + 1):
				if absi(x) + absi(y) <= span:
					var roof: String = project_at(support + Vector2i(x, y), "roof")
					if not roof.is_empty(): candidates[roof] = true
	for other: String in SimAvianLife.sorted_keys(candidates):
		if projects[other].state == "built" and project_cells(other).any(func(cell: Vector2i) -> bool: return not roof_supported(cell, id)):
			result.append(other)
	return result

func _can_remove_all(ids: Array[String], preserve_contents: bool = false) -> bool:
	var inventory: SimInventory = world.regions[definitions.site.region].inventory
	for id: String in ids:
		if not preserve_contents and not _contents_empty(id):
			return false
		var rule: Dictionary = definitions.types[projects[id].type]
		var salvage: String = id + ":salvage"
		if _drop_cell(id, ids).is_empty():
			return false
		# _remove performs no external calls between creating this source and
		# transferring into the original project container. Check the entire set
		# now, so a dependent roof cannot fail after its support was removed.
		if projects[id].state == "ruined":
			if not _contents_empty(id):
				return false
			continue
		if projects[id].state != "built" or not inventory.containers.has(id) or inventory.containers.has(salvage) or inventory.operations.has(salvage) or inventory.quantity(id, str(rule.item)) > SimInventory.MAX_COUNT - int(rule.salvage):
			return false
	return true


func _collapse_roofs(ids: Array[String]) -> void:
	for id: String in ids:
		var project: Dictionary = projects[id]
		for actor: String in SimAvianLife.sorted_keys(active):
			if active[actor].project == id:
				_cancel(actor)
		var drop: Array = _drop_cell(id, ids)
		if drop.is_empty():
			drop = project.cell.duplicate()
		if _remove(id, drop):
			project.line = "支撑失去，木屋面塌回有限余料；下方床铺仍在。"


func blocked(cell: Vector2i) -> bool:
	if _blocked.has(cell):
		return true
	for sim: RefCounted in world.regions.values():
		if sim.workplace_blocked(cell):
			return true
	return false


func is_bed(id: String) -> bool:
	return has_capability(id, "rest")


func space_at(cell: Vector2i) -> Dictionary:
	var space: Dictionary = _spaces.get(cell, {}).duplicate(true)
	if not space.is_empty():
		space.roofed = roofed(cell)
	return space


func site_contains(cell: Vector2i) -> bool:
	return not site_at(cell).is_empty()


func site_at(cell: Vector2i) -> String:
	for id: String in sites:
		if site_bounds(id).has_point(cell):
			return id
	return ""


func site_bounds(id: String = "sect_yard") -> Rect2i:
	return Rect2i(SimRouteTravel.cell(sites[id].origin), SimRouteTravel.cell(sites[id].size)) if sites.has(id) else Rect2i()


func designate(actor: String, bounds: Rect2i, purpose: String) -> Dictionary:
	if not _ready_actor(actor, false) or purpose.is_empty() or purpose.length() > 64 or bounds.size.x < 1 or bounds.size.y < 1 or bounds.get_area() > 1024:
		return reply(false, "此用途区域不适用。")
	var site: String = site_at(bounds.position)
	for cell: Vector2i in cells_in(bounds):
		if site.is_empty() or site_at(cell) != site or not can_observe(actor, cell):
			return reply(false, "用途区域须在同一可见工地内。")
	for existing: String in zones:
		if zones[existing].origin == [bounds.position.x, bounds.position.y] and zones[existing].size == [bounds.size.x, bounds.size.y]:
			zones[existing].purpose = purpose
			return {"ok": true, "line": "已更新这片区域的用途。", "zone": existing}
	if zones.size() >= 64 or next_zone >= SimInventory.MAX_COUNT:
		return reply(false, "用途区域数量已达上限。")
	var id: String = "zone:%d" % next_zone
	next_zone += 1
	zones[id] = {"site": site, "origin": [bounds.position.x, bounds.position.y], "size": [bounds.size.x, bounds.size.y], "purpose": purpose}
	return {"ok": true, "line": "已指定用途；区域不会自动变成设施或产生物品。", "zone": id}


func zones_at(cell: Vector2i) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in SimAvianLife.sorted_keys(zones):
		var zone: Dictionary = zones[id]
		if Rect2i(SimRouteTravel.cell(zone.origin), SimRouteTravel.cell(zone.size)).has_point(cell):
			result.append(zone.duplicate(true))
	return result

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
	_pending.clear()
	_supports.clear()
	_bed_ids.clear()
	for id: String in _project_ids():
		var project: Dictionary = projects[id]
		var material: Vector2i = SimRouteTravel.cell(project.material_cell)
		_material_cells[material] = int(_material_cells.get(material, 0)) + 1
		if project.state == "blueprint":
			_pending.append(id)
		if has_capability(id, "rest"):
			_bed_ids.append(id)
		if project.state in ["blueprint", "built", "ruined"]:
			for cell: Vector2i in project_cells(id):
				(_roofs if definitions.types[project.type].layer == "roof" else _cells)[cell] = id
				if fact(id, "movement_blocked"):
					_blocked[cell] = true
				if fact(id, "roof_support"):
					_supports[cell] = id
	var topology_bounds := Rect2i()
	for id: String in sites:
		topology_bounds = site_bounds(id) if topology_bounds.size == Vector2i.ZERO else topology_bounds.merge(site_bounds(id))
	_spaces = SimEnclosedSpace.detect(topology_bounds, projects, definitions.types, _elevation)
	if world.resting != null:
		world.resting.structures_changed()
	if world.weather != null:
		world.weather.structures_changed()

static func empty_state() -> Dictionary:
	return {"version": 4, "cultivation": {}, "sites": {}, "projects": {}, "active": {}, "zones": {}, "next_zone": 1, "next_project": 1, "next_job": 1, "next_check_ms": SimInventory.MAX_COUNT}


func to_dict() -> Dictionary:
	return {"version": 4, "cultivation": cultivation.duplicate(true), "sites": sites.duplicate(true), "projects": projects.duplicate(true), "active": active.duplicate(true), "zones": zones.duplicate(true), "next_zone": next_zone, "next_project": next_project, "next_job": next_job, "next_check_ms": next_check_ms}


func restore(data: Dictionary) -> bool:
	if not Schema.valid(data, self):
		return false
	cultivation = SnapshotValues.normalized(data.cultivation)
	next_zone = int(data.next_zone)
	zones = data.zones.duplicate(true)
	sites = data.sites.duplicate(true)
	projects = data.projects.duplicate(true)
	active = data.active.duplicate(true)
	next_project = int(data.next_project)
	next_job = int(data.next_job)
	next_check_ms = int(data.next_check_ms)
	_reindex()
	return true


func space_valid() -> bool:
	for id: String in sites:
		for cell: Vector2i in cells_in(site_bounds(id)):
			if not terrain_open(cell) or protected_cell(cell):
				return false
	for project: Dictionary in projects.values():
		if not terrain_open(SimRouteTravel.cell(project.material_cell)):
			return false
		for cell: Vector2i in SimConstructionGeometry.cells(project, definitions.types[project.type]):
			if not terrain_open(cell) or project.state == "built" and definitions.types[project.type].layer == "roof" and not roof_supported(cell):
				return false
	for id: String in _project_ids():
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


func _project_ids() -> Array:
	var ids: Array = projects.keys()
	ids.sort_custom(func(a: String, b: String) -> bool: return int(a.trim_prefix("construction:")) < int(b.trim_prefix("construction:")))
	return ids


func bed_ids() -> Array[String]:
	return _bed_ids.duplicate()


func _drop_cell(id: String, removals: Array[String]) -> Array:
	var footprint: Array[Vector2i] = project_cells(id)
	var candidates: Array[Vector2i] = footprint.duplicate()
	for cell: Vector2i in footprint:
		for direction: Vector2i in SIDES:
			if cell + direction not in candidates: candidates.append(cell + direction)
	for cell: Vector2i in candidates:
		var ground: String = project_at(cell)
		if terrain_open(cell) and not SimWorkplaces.blocked(world.regions[definitions.site.region].places, cell) and (ground.is_empty() or ground in removals or not fact(ground, "movement_blocked")):
			return [cell.x, cell.y]
	return []


func clear_zone(actor: String, id: String) -> Dictionary:
	if not _ready_actor(actor, false) or not zones.has(id):
		return reply(false, "当前不能取消这片用途区域。")
	var zone: Dictionary = zones[id]
	for cell: Vector2i in cells_in(Rect2i(SimRouteTravel.cell(zone.origin), SimRouteTravel.cell(zone.size))):
		if not can_observe(actor, cell): return reply(false, "先到场查看这片用途区域。")
	zones.erase(id)
	return reply(true, "用途指定已取消，原地实物保持原状。")
