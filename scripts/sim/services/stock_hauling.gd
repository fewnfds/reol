extends RefCounted
## Geometry and stock-handling phases for SettlementServices' original jobs.
## Quantities/custody stay in original inventories; no new task or save owner.
const Shape = preload("res://scripts/sim/avian_schema.gd")
var _owner: WeakRef
var service: RefCounted:
	get: return _owner.get_ref()
var world: RegionalSimulation:
	get: return service.world


func _init(owner: RefCounted) -> void:
	_owner = weakref(owner)


func begin(actor: String, options: Dictionary) -> Dictionary:
	if world.elapsed_ms != world.target_ms:
		return _reply(false, "pending_time", "先等世界推进到当前时刻。")
	if not Shape.keys(options, ["source", "target", "item", "amount"]) or not SimInventory._nonempty(options.item) or not Shape.count(options.amount, 1, int(world._content.local_actions.hauling.max_units)):
		return _reply(false, "invalid_load", "请选择可搬运的物品及单次数量。")
	var home: String = service.actor_home(actor)
	if not _reference(options.source) or not _reference(options.target) or Shape.same_record(options.source, options.target):
		return _reply(false, "invalid_endpoint", "起点和终点必须是两个实际容器。")
	if not world.advance_region_to_world(options.source.region) or not world.advance_region_to_world(options.target.region):
		return _reply(false, "unavailable", "搬运地点尚未准备好。")
	if not _allowed(actor, options.source, true, options.item) or not _allowed(actor, options.target, false, options.item):
		return _reply(false, "permission", "这些物资或容器不在本人可办理的范围。")
	if not _observed(actor, options.source) or not _observed(actor, options.target):
		return _reply(false, "unobserved", "先查看容器，或使用本人已知的聚落地点。")
	var carried: String = _held(actor, options)
	var public_source: bool = world.regions[options.source.region].places.has(options.source.container)
	if public_source and not _public_target(actor, home, options.target):
		return _reply(false, "public_destination", "公物只能交到已登记的聚落地点，或留在本人行囊继续保管；普通箱体尚不承接公物责任。")
	if carried.is_empty() and public_source and options.source.region != home and world.regions[options.source.region].inventory.available(options.source.container, options.item) - int(options.amount) < int(service.definitions.hauling.source_floor):
		return _reply(false, "source_floor", "供货地点必须保留基本存量。")
	var id: String = service.allocate("job")
	var job: Dictionary = {"id": id, "actor": actor, "home": home, "region": home, "kind": "carry_stock", "label": "搬运物资",
		"status": "active", "phase": "travel", "stage": "delivery" if not carried.is_empty() else "pickup", "carrying": not carried.is_empty(),
		"path": [], "started_ms": world.elapsed_ms, "started": world.current_time, "segment_started_ms": world.elapsed_ms,
		"segment_from": world.regions[home].synchronize_actor(actor).position.duplicate(), "due_ms": world.elapsed_ms + 1,
		"options": options.duplicate(true), "spec": {"label": "搬运物资"}, "stand": [], "anchor": [],
		"reservation": "", "previous_autonomous": bool(world.regions[home].synchronize_actor(actor).autonomous), "outcome": ""}
	job.options["custody"] = carried
	if not _route(job):
		return _reply(false, "unreachable", "目前无法接近搬运地点。")
	if carried.is_empty():
		var source: SimInventory = world.regions[options.source.region].inventory
		if not _room_for(job, options.target) or not source.reserve(id + ":stock", options.source.container, options.item, int(options.amount), actor):
			return _reply(false, "stock_or_capacity", "可处分的数量或目的容器容量不足。")
		job.reservation = id + ":stock"
	service.jobs[id] = job
	service.active_jobs[actor] = id
	service.remember_job(job)
	SimActionContract.occupy(world, home, actor)
	world.regions[home].synchronize_actor(actor).goal = "前往取货" if carried.is_empty() else "继续交付随身受托物资"
	service.record("service_started", actor, {"job": id, "kind": "carry_stock", "region": job.region})
	return _reply(true, "started", "已预约物资；到场取货后实际携带，交付前会再核对容器。", id)


static func _reference(value: Variant) -> bool:
	return Shape.keys(value, ["region", "container"]) and SimInventory._nonempty(value.region) and SimInventory._nonempty(value.container)


func _public_target(actor: String, home: String, endpoint: Dictionary) -> bool:
	return endpoint == {"region": home, "container": "actor:" + actor} or world.regions[endpoint.region].places.has(endpoint.container)


func _allowed(actor: String, endpoint: Dictionary, taking: bool, item: String) -> bool:
	if not world.regions.has(endpoint.region):
		return false
	var sim: VillageSimulation = world.regions[endpoint.region]
	var home: String = service.actor_home(actor)
	if endpoint.container == "actor:" + actor:
		return endpoint.region == home
	if str(endpoint.container).ends_with(":contents"):
		var id: String = str(endpoint.container).trim_suffix(":contents")
		return endpoint.region == world.construction.definitions.site.region and world.construction.authorized(actor) and world.construction.has_capability(id, "storage")
	if not sim.places.has(endpoint.container):
		return false # Private pockets, production batches and raw resources have their own protocols.
	if not taking:
		return true # Depositing conveys no right to withdraw from a foreign institution.
	if endpoint.region == home:
		for action: Dictionary in sim.config.actions.values():
			if action.get("source") == endpoint.container and action.get("item") == item:
				return true
		return false
	# The existing public freight policy is the only foreign withdrawal grant.
	var route: Dictionary = world.settings.routes[service.definitions.hauling.route]
	return endpoint.region == route.from and endpoint.container == route.source and item == route.item


func _observed(actor: String, endpoint: Dictionary) -> bool:
	if endpoint.container == "actor:" + actor:
		return true
	var sim: VillageSimulation = world.regions[endpoint.region]
	if sim.places.has(endpoint.container):
		# Registered destinations already belong to the current limited public map.
		return true
	var anchor: Dictionary = SimStorageQuery.locate(world, {"domain": "village", "region": endpoint.region, "container": endpoint.container})
	if not bool(anchor.ok):
		return false
	var person: Dictionary = world.regions[service.actor_home(actor)].synchronize_actor(actor)
	var from: Vector2 = SimRouteTravel.point(person)
	if from.distance_to(anchor.position) > float(world.regions[service.actor_home(actor)].config.observation_radius) * TileGrid.TILE_SIZE:
		return false
	# A solid chest is the object being seen. Only that original structure is
	# excluded from this sight ray; terrain, walls and other objects still occlude.
	var id: String = str(endpoint.container).trim_suffix(":contents")
	return SimConflictSpace.level(world, anchor.position) == SimConflictSpace.level(world, from) and SimConflictSpace.clear_segment(world, from, anchor.position, SimConflictSpace.level(world, from), id)


func _held(actor: String, options: Dictionary) -> String:
	var inventory: SimInventory = world.regions[service.actor_home(actor)].inventory
	for id: String in SimAvianLife.sorted_keys(inventory.custody):
		var note: Dictionary = inventory.custody[id]
		if note.container != "actor:" + actor or not note.settled_by.is_empty() or note.item != options.item or int(note.amount) != int(options.amount) or note.basis.domain != "service" or note.basis.purpose != "carry_stock":
			continue
		var origin: Dictionary = service.jobs[note.basis.origin]
		if Shape.same_record(origin.options.source, options.source) and Shape.same_record(origin.options.target, options.target):
			return id
	return ""


func _endpoint(job: Dictionary) -> Dictionary:
	return job.options.source if job.stage == "pickup" else job.options.target


func _stands(job: Dictionary) -> Array[Vector2i]:
	var endpoint: Dictionary = _endpoint(job)
	var result: Array[Vector2i] = []
	if endpoint.container == "actor:" + str(job.actor):
		result.append(SimRouteTravel.cell(world.regions[job.home].synchronize_actor(job.actor).cell))
	elif str(endpoint.container).ends_with(":contents"):
		var id: String = str(endpoint.container).trim_suffix(":contents")
		for slot: Dictionary in world.construction.operation_slots(id, "storage"):
			if not world.facility_use.cell_reserved(slot.cell, str(job.actor)):
				result.append(slot.cell)
	elif world.regions[endpoint.region].places.has(endpoint.container):
		result.append(SimRouteTravel.cell(world.regions[endpoint.region].places[endpoint.container].cell))
	return result


func _route(job: Dictionary) -> bool:
	var endpoint: Dictionary = _endpoint(job)
	var sim: VillageSimulation = world.regions[job.home]
	var from: Vector2i = SimRouteTravel.cell(sim.synchronize_actor(job.actor).cell)
	var best: Array = []
	var stand: Array = []
	var length: int = SimInventory.MAX_COUNT
	for point: Vector2i in _stands(job):
		var path: Array = service.path_between(job.home, [from.x, from.y], [point.x, point.y])
		if path.is_empty() and from != point:
			continue
		if path.size() < length:
			length = path.size()
			best = path
			stand = [point.x, point.y]
	if stand.is_empty():
		return false
	job.stand = stand
	job.anchor = _anchor(endpoint)
	job.path = best
	job.phase = "travel"
	job.region = endpoint.region
	if not SimRouteTravel.point(sim.synchronize_actor(job.actor)).is_equal_approx(TileGrid.cell_to_world(from)):
		job.path.push_front([from.x, from.y])
	SimRouteTravel.begin_segment(job, sim.synchronize_actor(job.actor), world.elapsed_ms, float(sim.motion_rules.motion.speed))
	return true


func _anchor(endpoint: Dictionary) -> Array:
	var located: Dictionary = SimStorageQuery.locate(world, {"domain": "village", "region": endpoint.region, "container": endpoint.container})
	return [located.cell.x, located.cell.y] if bool(located.ok) else []


func _stand_matches_endpoint(job: Dictionary) -> bool:
	var endpoint: Dictionary = _endpoint(job)
	if not _allowed(job.actor, endpoint, job.stage == "pickup", job.options.item):
		return false
	var expected: Array = _anchor(endpoint)
	if expected.is_empty(): return false
	if endpoint.container == "actor:" + str(job.actor):
		return SimRouteTravel.cell(job.stand) == SimRouteTravel.cell(expected)
	if SimRouteTravel.cell(job.anchor) != SimRouteTravel.cell(expected): return false
	if str(endpoint.container).ends_with(":contents"):
		var id: String = str(endpoint.container).trim_suffix(":contents")
		for slot: Dictionary in world.construction.operation_slots(id, "storage"):
			if slot.cell == SimRouteTravel.cell(job.stand): return true
		return false
	return SimRouteTravel.cell(job.stand) == SimRouteTravel.cell(expected)


func _room_for(job: Dictionary, endpoint: Dictionary) -> bool:
	var inventory: SimInventory = world.regions[endpoint.region].inventory
	if not inventory.containers.has(endpoint.container) or inventory.quantity(endpoint.container, job.options.item) > SimInventory.MAX_COUNT - int(job.options.amount):
		return false
	if not str(endpoint.container).ends_with(":contents"):
		return true
	var id: String = str(endpoint.container).trim_suffix(":contents")
	var items: Dictionary = inventory.containers[endpoint.container].duplicate()
	items[job.options.item] = int(items.get(job.options.item, 0)) + int(job.options.amount)
	for active_id: String in service.active_jobs.values():
		var other: Dictionary = service.jobs[active_id]
		if other.kind == "carry_stock" and other.id != job.id and Shape.same_record(other.options.target, endpoint):
			items[other.options.item] = int(items.get(other.options.item, 0)) + int(other.options.amount)
	for other: Dictionary in world.facility_use.active.values():
		if other.project == id and other.kind == "deposit":
			items[other.item] = int(items.get(other.item, 0)) + int(other.amount)
	return world.construction.projects.has(id) and world.construction.contents_valid(world.construction.projects[id], items)


func settle(job: Dictionary, now: int) -> void:
	if job.status != "active":
		return
	var endpoint: Dictionary = _endpoint(job)
	world.advance_region_to_world(endpoint.region)
	var sim: VillageSimulation = world.regions[job.home]
	var body: Dictionary = sim.synchronize_actor(job.actor)
	if not _allowed(job.actor, endpoint, job.stage == "pickup", job.options.item) or endpoint.container != "actor:" + str(job.actor) and RegionalSimulation._normalized(job.anchor) != RegionalSimulation._normalized(_anchor(endpoint)):
		service._jobs.finish(job, false, "目标或使用权已改变，物资保留在原容器或行囊中。")
		return
	if job.phase == "travel":
		if not SimRouteTravel.repair(sim, job.actor, job, now, job.stand, -1.0, service.route_step.bind(job.home)):
			service._jobs.finish(job, false, "道路不通；已取物资和保管责任仍随身。")
			return
		sim.project_actor_route(job.actor, job, now)
		if now < int(job.due_ms):
			return
		if not job.path.is_empty():
			sim.set_actor_cell(job.actor, SimRouteTravel.cell(job.path.pop_front()))
		if not job.path.is_empty():
			SimRouteTravel.begin_segment(job, body, now, float(sim.motion_rules.motion.speed))
			return
		job.phase = "work"
		job.segment_from = body.position.duplicate()
		job.segment_started_ms = now
		job.due_ms = now + int(world._content.local_actions.hauling.handling_ms)
		return
	if now < int(job.due_ms):
		return
	if not _stand_matches_endpoint(job) or SimRouteTravel.cell(body.cell) != SimRouteTravel.cell(job.stand) or not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(SimRouteTravel.cell(job.stand))):
		service._jobs.finish(job, false, "离开了操作位置，本次搬运中断。")
		return
	service._handling_stock = true
	_handle(job)
	service._handling_stock = false


func _handle(job: Dictionary) -> void:
	var endpoint: Dictionary = _endpoint(job)
	var sim: VillageSimulation = world.regions[job.home]
	var bag: String = "actor:" + str(job.actor)
	if job.stage == "pickup":
		if endpoint.container != bag or endpoint.region != job.home:
			if world.regions[endpoint.region].places.has(endpoint.container) and endpoint.region != job.home and world.regions[endpoint.region].inventory.quantity(endpoint.container, job.options.item) - int(job.options.amount) < int(service.definitions.hauling.source_floor):
				service._jobs.finish(job, false, "供货地点已到基本存量，本次未取货。")
				return
			if not service.transfer(job.id + ":pickup", endpoint.region, endpoint.container, job.home, bag, job.options.item, int(job.options.amount), "", job.reservation):
				service._jobs.finish(job, false, "取货复核未通过，原物资没有移动。")
				return
			job.reservation = ""
			if world.regions[endpoint.region].places.has(endpoint.container):
				job.options.custody = job.id + ":pickup"
				var entrusted: bool = sim.inventory.entrust(job.options.custody, bag, job.options.item, int(job.options.amount), SimEntrustedGoods.service_basis(world, job))
				assert(entrusted, "preflighted public cargo must retain custody")
			else:
				job.reservation = job.id + ":stock"
				var reserved: bool = sim.inventory.reserve(job.reservation, bag, job.options.item, int(job.options.amount), job.actor)
				assert(reserved, "preflighted private cargo must remain available")
		job.carrying = true
		job.stage = "delivery"
		if not _route(job):
			service._jobs.finish(job, false, "回程不通；实际货物与保管责任仍在行囊。")
		return
	if not _room_for(job, endpoint):
		service._jobs.finish(job, false, "目的容器已满，货物仍在行囊。")
		return
	if endpoint.container != bag or endpoint.region != job.home:
		if not service.transfer(job.id + ":delivery", job.home, bag, endpoint.region, endpoint.container, job.options.item, int(job.options.amount), job.options.custody, job.reservation):
			service._jobs.finish(job, false, "交付复核未通过，货物仍在行囊。")
			return
		job.reservation = ""
	service._jobs.finish(job, true, "物资已取入行囊，保管责任仍在。" if endpoint.container == bag and not job.options.custody.is_empty() else "物资已实际交付；原数量与保管责任已结清。")


func release(job: Dictionary) -> void:
	if not str(job.reservation).is_empty():
		var endpoint: Dictionary = job.options.source if job.stage == "pickup" else {"region": job.home, "container": "actor:" + str(job.actor)}
		world.regions[endpoint.region].inventory.release(job.reservation)
		job.reservation = ""


func cell_reserved(cell: Vector2i, except_actor: String = "") -> bool:
	for id: String in service.active_jobs.values():
		var job: Dictionary = service.jobs[id]
		if job.kind == "carry_stock" and job.actor != except_actor and str(_endpoint(job).container).ends_with(":contents") and SimRouteTravel.cell(job.stand) == cell:
			return true
	return false


func valid_job(job: Dictionary, data: Dictionary) -> bool:
	if job.spec != {"label": "搬运物资"} or job.get("label") != "搬运物资" or job.path.size() > 1024:
		return false
	if not _reference(job.options.get("source")) or not _reference(job.options.get("target")) or not Shape.keys(job.options, ["source", "target", "item", "amount", "custody"]) or not job.options.custody is String or not SimInventory._nonempty(job.options.item) or not Shape.count(job.options.amount, 1, int(world._content.local_actions.hauling.max_units)) or job.get("stage") not in ["pickup", "delivery"] or not job.get("reservation") is String or not Shape.cell_valid(job.get("stand")) or not Shape.cell_valid(job.get("anchor")):
		return false
	if not world.regions.has(job.options.source.region) or not world.regions.has(job.options.target.region) or Shape.same_record(job.options.source, job.options.target) or job.status == "active" and job.region != _endpoint(job).region or job.carrying != (job.stage == "delivery"):
		return false
	if world.regions[job.options.source.region].places.has(job.options.source.container) and not _public_target(job.actor, job.home, job.options.target):
		return false
	if not Shape.count(job.get("started_ms"), 0, world.elapsed_ms) or job.started != floori(float(job.started_ms) / 60000.0):
		return false
	if not job.options.custody.is_empty():
		var note: Dictionary = world.regions[job.home].inventory.custody.get(job.options.custody, {})
		if note.is_empty() or note.container != "actor:" + str(job.actor) or note.item != job.options.item or note.amount != job.options.amount or note.basis.purpose != "carry_stock" or job.stage != "delivery":
			return false
		if note.basis.domain != "service" or note.basis.source_region != job.options.source.region or note.basis.source != job.options.source.container or note.basis.target_region != job.options.target.region or note.basis.target != job.options.target.container:
			return false
	elif job.stage == "delivery" and job.options.source != {"region": job.home, "container": "actor:" + str(job.actor)} and not str(job.options.source.container).ends_with(":contents"):
		return false
	if data.operations.has(job.id + ":delivery") != (job.status == "completed" and job.stage == "delivery" and job.options.target != {"region": job.home, "container": "actor:" + str(job.actor)}):
		return false
	if job.options.source != {"region": job.home, "container": "actor:" + str(job.actor)} and job.carrying and not data.operations.has(job.id + ":pickup") and (job.options.custody.is_empty() or world.regions[job.home].inventory.custody[job.options.custody].basis.origin == job.id):
		return false
	if data.operations.has(job.id + ":pickup") and (not job.carrying or job.options.source == {"region": job.home, "container": "actor:" + str(job.actor)}):
		return false
	if job.status != "active":
		return job.reservation.is_empty() and Shape.count(job.get("finished_at"), int(job.started), world.current_time)
	var sim: VillageSimulation = world.regions[job.home]
	var body: Dictionary = sim.synchronize_actor(job.actor)
	if body.autonomous or not body.active.is_empty() or not Shape.count(job.get("due_ms"), world.elapsed_ms + 1) or not Shape.count(job.get("segment_started_ms"), int(job.started_ms), world.elapsed_ms) or not SimLocalMotion._vector(job.get("segment_from")) or not _stand_matches_endpoint(job):
		return false
	if not job.options.custody.is_empty():
		if not sim.inventory.can_use("actor:" + str(job.actor), job.options.item, int(job.options.amount), job.options.custody) or not job.reservation.is_empty():
			return false
	else:
		var endpoint: Dictionary = job.options.source if job.stage == "pickup" else {"region": job.home, "container": "actor:" + str(job.actor)}
		if job.reservation != job.id + ":stock" or not Shape.same_record(world.regions[endpoint.region].inventory.reservations.get(job.reservation), {"container": endpoint.container, "item": job.options.item, "amount": job.options.amount, "owner_id": job.actor}):
			return false
	var previous: Vector2i = SimRouteTravel.cell(body.cell)
	for point: Variant in job.path:
		if not Shape.cell_valid(point) or maxi(absi(int(point[0]) - previous.x), absi(int(point[1]) - previous.y)) > 1:
			return false
		previous = SimRouteTravel.cell(point)
	if previous != SimRouteTravel.cell(job.stand) or job.phase == "work" and (not job.path.is_empty() or not SimRouteTravel.point(body).is_equal_approx(TileGrid.cell_to_world(previous))):
		return false
	if job.phase == "work" and (int(job.due_ms) != int(job.segment_started_ms) + int(world._content.local_actions.hauling.handling_ms) or job.segment_from != body.position):
		return false
	return job.phase != "travel" or SimRouteTravel.valid_segment(job, body, world.elapsed_ms, float(sim.motion_rules.motion.speed))


static func inventory_scope(data: Variant, region: String, _content: RefCounted) -> Dictionary:
	var result: Dictionary = {"reservations": {}, "external_reservation_owners": {}}
	if not data is Dictionary or not data.get("jobs") is Dictionary:
		return result
	for job: Variant in data.jobs.values():
		if not job is Dictionary or job.get("kind") != "carry_stock" or job.get("status") != "active" or not SimInventory._nonempty(job.get("reservation")) or not job.get("options") is Dictionary:
			continue
		var endpoint: Variant = job.options.get("source") if job.get("stage") == "pickup" else {"region": job.get("home"), "container": "actor:" + str(job.get("actor"))}
		if endpoint is Dictionary and endpoint.get("region") == region:
			result.reservations[job.reservation] = true
			result.external_reservation_owners[job.reservation] = job.get("actor")
	return result


func _reply(ok: bool, reason: String, line: String, id: String = "") -> Dictionary:
	return service.response(ok, reason, line, id)
