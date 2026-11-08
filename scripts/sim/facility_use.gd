class_name SimFacilityUse
extends RefCounted
## Real operation slots and bounded container use. Buildings, bodies and stock
## remain in their original owners; active jobs are the reservation authority.

const Shape = preload("res://scripts/sim/avian_schema.gd")
var active: Dictionary = {}
var transfers: Dictionary = {}
var next_job: int = 1
var _owner: WeakRef
var world: RegionalSimulation:
	get: return _owner.get_ref() as RegionalSimulation


func bind_world(authority: RegionalSimulation) -> void:
	_owner = weakref(authority)


func slot(project: String, name: String) -> Dictionary:
	for row: Dictionary in world.construction.operation_slots(project):
		if row.id == name:
			return row
	return {}


func slot_available(project: String, name: String, kind: String, actor: String = "") -> bool:
	var domain: SimConstruction = world.construction
	if not domain.projects.has(project) or domain._project_busy(project):
		return false
	var row: Dictionary = slot(project, name)
	var capability: String = "seat" if kind == "sit" else "storage" if kind in ["deposit", "withdraw"] else "workbench"
	if row.is_empty() or row.capability != capability or not domain.has_capability(project, capability) and not (kind == "withdraw" and domain.projects[project].state == "ruined" and domain.definitions.types[domain.projects[project].type].capabilities.has("storage")):
		return false
	if not domain.terrain_open(row.cell) or domain.blocked(row.cell):
		return false
	if not str(row.requires).is_empty():
		var support: String = domain.project_at(row.cell + row.facing)
		if not domain.has_capability(support, str(row.requires)) or domain._project_busy(support):
			return false
	return not cell_reserved(row.cell, actor)


func cell_reserved(cell: Vector2i, except_actor: String = "") -> bool:
	for actor: String in active:
		if actor != except_actor and SimRouteTravel.cell(active[actor].stand) == cell:
			return true
	if world.personal_production != null:
		for actor: String in world.personal_production.active:
			var job: Dictionary = world.personal_production.active[actor]
			var batch: Dictionary = world.personal_production.batches[job.batch]
			if actor != except_actor and not str(batch.facility).is_empty() and world.personal_production.work_cell(batch) == cell:
				return true
	for job: Dictionary in world.construction.active.values():
		if job.actor != except_actor and SimRouteTravel.cell(job.stand) == cell:
			return true
	if world.resting != null:
		for actor: String in world.resting.active:
			if actor != except_actor and SimRouteTravel.cell(world.construction.projects[world.resting.active[actor].bed].cell) == cell:
				return true
	return false


func project_reserved(project: String) -> bool:
	for job: Dictionary in active.values():
		if job.project == project or job.support == project:
			return true
	if world.personal_production != null:
		for job: Dictionary in world.personal_production.active.values():
			if world.personal_production.batches[job.batch].facility == project:
				return true
	return false


func begin(actor: String, project: String, name: String, kind: String = "sit", item: String = "", amount: int = 0, duration_ms: int = 60000) -> Dictionary:
	var domain: SimConstruction = world.construction
	var region: String = str(domain.definitions.site.region)
	if kind not in ["sit", "deposit", "withdraw"] or not domain._ready_actor(actor, true) or duration_ms < 1 or duration_ms > 86400000 or not slot_available(project, name, kind, actor):
		return SimConstruction.reply(false, "设施、操作位置或身体当前不可用。")
	var row: Dictionary = slot(project, name)
	if not domain.can_observe(actor, row.cell):
		return SimConstruction.reply(false, "先走近，查看设施的实际操作位置。")
	var sim: VillageSimulation = world.regions[region]
	var from: Vector2i = SimRouteTravel.cell(sim.actors[actor].cell)
	var path: Array[Vector2i] = sim.find_path(from, row.cell)
	if from != row.cell and path.is_empty():
		return SimConstruction.reply(false, "到不了设施的操作位置。")
	var id: String = "facility_use:%d" % next_job
	var job: Dictionary = {"id": id, "actor": actor, "project": project, "slot": name, "kind": kind, "item": item, "amount": amount, "duration_ms": duration_ms,
		"phase": "travel", "path": [], "stand": [row.cell.x, row.cell.y], "support": "", "segment_from": sim.actors[actor].position.duplicate(), "segment_started_ms": world.elapsed_ms,
		"due_ms": world.elapsed_ms + 1, "started_ms": world.elapsed_ms, "work_started_ms": world.elapsed_ms, "previous_autonomous": bool(sim.actors[actor].autonomous), "reserved": false}
	if kind == "sit":
		if not item.is_empty() or amount != 0:
			return SimConstruction.reply(false, "坐下不包含物资转移。")
	else:
		if not SimInventory._nonempty(item) or amount < 1 or amount > SimInventory.MAX_COUNT or not _storage_ready(job):
			return SimConstruction.reply(false, "物品、可用数量或容器容量不适用。")
		if not sim.inventory.reserve(id, _source(job), item, amount, actor):
			return SimConstruction.reply(false, "这批物品已不足或被预约。")
		job.reserved = true
	if row.requires != "":
		job.support = domain.project_at(row.cell + row.facing)
	for cell: Vector2i in path:
		job.path.append([cell.x, cell.y])
	if job.path.is_empty() and not SimRouteTravel.point(sim.actors[actor]).is_equal_approx(TileGrid.cell_to_world(row.cell)):
		job.path.append([row.cell.x, row.cell.y])
	SimRouteTravel.begin_segment(job, sim.actors[actor], world.elapsed_ms, float(sim.motion_rules.motion.speed))
	next_job += 1
	active[actor] = job
	SimActionContract.occupy(world, region, actor)
	sim.actors[actor].goal = "前往设施操作位置"
	world.invalidate_region(region)
	return SimConstruction.reply(true, "操作位已预约；实际到场后才开始使用。")


func _source(job: Dictionary) -> String:
	return "actor:" + str(job.actor) if job.kind == "deposit" else str(job.project) + ":contents"


func _target(job: Dictionary) -> String:
	return str(job.project) + ":contents" if job.kind == "deposit" else "actor:" + str(job.actor)


func _storage_ready(job: Dictionary) -> bool:
	var inventory: SimInventory = world.regions[world.construction.definitions.site.region].inventory
	var contents: String = str(job.project) + ":contents"
	if not inventory.containers.has(contents) or not inventory.containers.has("actor:" + str(job.actor)):
		return false
	if job.kind == "withdraw":
		return inventory.quantity(contents, str(job.item)) >= int(job.amount) and inventory.quantity(_target(job), str(job.item)) <= SimInventory.MAX_COUNT - int(job.amount)
	var items: Dictionary = inventory.containers[contents].duplicate()
	items[job.item] = int(items.get(job.item, 0)) + int(job.amount)
	for other: Dictionary in active.values():
		if other.id != job.id and other.project == job.project and other.kind == "deposit":
			items[other.item] = int(items.get(other.item, 0)) + int(other.amount)
	return world.construction.contents_valid(world.construction.projects[job.project], items)


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func cancel(actor: String) -> bool:
	if not active.has(actor):
		return false
	_release(active[actor], "cancelled", "使用已中断，操作位与未用物资已释放。")
	return true


func cancel_projects(ids: Array[String]) -> void:
	for actor: String in SimAvianLife.sorted_keys(active):
		if active[actor].project in ids or active[actor].support in ids:
			cancel(actor)
	if world.personal_production != null:
		for actor: String in world.personal_production.active.keys():
			if world.personal_production.batches[world.personal_production.active[actor].batch].facility in ids:
				world.personal_production.cancel(actor)


func _can_continue(job: Dictionary) -> bool:
	var region: String = str(world.construction.definitions.site.region)
	var position: Array = [] if job.phase == "travel" else [TileGrid.cell_to_world(SimRouteTravel.cell(job.stand)).x, TileGrid.cell_to_world(SimRouteTravel.cell(job.stand)).y]
	if not SimActionContract.can_continue(world, region, job.actor, &"facility_use", position) or not slot_available(job.project, job.slot, job.kind, job.actor):
		return false
	var row: Dictionary = slot(job.project, job.slot)
	return row.requires == "" and job.support == "" or world.construction.project_at(row.cell + row.facing) == job.support


func next_boundary_ms() -> int:
	var boundary: int = SimInventory.MAX_COUNT
	for job: Dictionary in active.values():
		if not _can_continue(job):
			return world.elapsed_ms + 1
		var body: Dictionary = world.regions[world.construction.definitions.site.region].actors[job.actor]
		boundary = mini(boundary, SimRouteTravel.crossing_ms(job, body, world.elapsed_ms) if job.phase == "travel" else int(job.due_ms))
	return boundary


func settle_at_ms(now: int) -> void:
	var region: String = str(world.construction.definitions.site.region)
	for actor: String in SimAvianLife.sorted_keys(active):
		world.synchronize_region(region)
		var job: Dictionary = active[actor]
		var sim: VillageSimulation = world.regions[region]
		var body: Dictionary = sim.actors[actor]
		if not _can_continue(job):
			cancel(actor)
			continue
		if job.phase == "travel":
			if not job.path.is_empty() and not world.construction._step_open(sim, SimRouteTravel.cell(body.cell), SimRouteTravel.cell(job.path[0])):
				cancel(actor)
				continue
			sim.project_actor_route(actor, job, now)
		if now < int(job.due_ms):
			continue
		if job.phase == "travel":
			if not job.path.is_empty():
				sim.set_actor_position(actor, TileGrid.cell_to_world(SimRouteTravel.cell(job.path.pop_front())))
			if not job.path.is_empty():
				SimRouteTravel.begin_segment(job, body, now, float(sim.motion_rules.motion.speed))
				continue
			if not position_clear(actor, SimRouteTravel.cell(job.stand)):
				cancel(actor)
				continue
			job.phase = "use"
			job.work_started_ms = now
			job.due_ms = now + (int(job.duration_ms) if job.kind == "sit" else int(world.construction.definitions.operate_ms))
			var row: Dictionary = slot(job.project, job.slot)
			body.facing = [row.facing.x, row.facing.y]
			body.goal = "坐在座位上" if job.kind == "sit" else "正在取放容器中的物品"
		else:
			if not position_clear(actor, SimRouteTravel.cell(job.stand)):
				cancel(actor)
				continue
			if job.kind != "sit":
				if not _storage_ready(job) or not sim.inventory.transfer(str(job.id) + ":transfer", _source(job), _target(job), str(job.item), int(job.amount), str(job.id)):
					cancel(actor)
					continue
				transfers[job.id] = {"actor": actor, "project": str(job.project), "kind": str(job.kind), "item": str(job.item), "amount": int(job.amount), "at_ms": now}
				job.reserved = false
			_release(job, "completed", "使用完成，操作位已释放。")


func _release(job: Dictionary, status: String, line: String) -> void:
	var region: String = str(world.construction.definitions.site.region)
	active.erase(job.actor)
	SimActionContract.release(world, region, job.actor, bool(job.previous_autonomous), job.id)
	world.regions[region].actors[job.actor].goal = line
	SimActionContract.publish_finished(world, SimActionContract.view(world, "facility_use", job.id, job.actor, job.kind, job.phase, int(job.started_ms), int(job.due_ms), status, job.project), line)


static func inventory_scope(data: Variant, region: String, rules: Dictionary) -> Dictionary:
	var scope: Dictionary = {"containers": {}, "operations": {}, "reservations": {}}
	if region != rules.site.region or not data is Dictionary or not data.get("active") is Dictionary or not data.get("transfers") is Dictionary:
		return scope
	for job: Variant in data.active.values():
		if job is Dictionary and job.get("reserved") == true and job.get("id") is String:
			scope.reservations[job.id] = true
	for id: Variant in data.transfers:
		if id is String:
			scope.operations[id + ":transfer"] = true
	return scope


static func empty_state() -> Dictionary:
	return {"version": 1, "active": {}, "transfers": {}, "next_job": 1}


func to_dict() -> Dictionary:
	return {"version": 1, "active": active.duplicate(true), "transfers": transfers.duplicate(true), "next_job": next_job}


func restore(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "active", "transfers", "next_job"]) or data.version != 1 or not data.active is Dictionary or not data.transfers is Dictionary or not Shape.count(data.next_job, 1):
		return false
	# Candidate instance only; regional restore publishes after cross validation.
	active = data.active.duplicate(true)
	transfers = data.transfers.duplicate(true)
	next_job = int(data.next_job)
	return preload("res://scripts/sim/facility_use_schema.gd").valid(self)


func position_clear(actor: String, cell: Vector2i) -> bool:
	for sim: VillageSimulation in world.regions.values():
		for other: String in sim.actors:
			if other != actor and bool(sim.actors[other].alive) and SimRouteTravel.cell(sim.actors[other].cell) == cell:
				return false
	if world.large_bodies != null and world.large_bodies.blocked(cell): return false
	if world.avian_life != null:
		for id: String in world.avian_life.birds:
			if int(world.avian_life.birds[id].altitude) == 0 and world.avian_life.body_cell(id) == cell: return false
	var ground: Dictionary = world.object_lifecycle.ground.query(Rect2i(cell, Vector2i.ONE), 512)
	return ground.ok and ground.ids.is_empty()
