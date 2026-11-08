extends RefCounted
## Strict construction references, original ledger receipts and body occupancy.
const Shape = preload("res://scripts/sim/avian_schema.gd")


static func inventory_scope(data: Variant, region: String, rules: Dictionary) -> Dictionary:
	var scope: Dictionary = {"containers": {}, "operations": {}, "reservations": {}}
	if region != rules.site.region or not data is Dictionary or not data.get("projects") is Dictionary or not data.get("active") is Dictionary:
		return scope
	for id: Variant in data.projects:
		if not id is String or not data.projects[id] is Dictionary:
			continue
		scope.containers[id] = true
		var type: Variant = data.projects[id].get("type")
		if type is String and rules.types.has(type) and rules.types[type].capabilities.has("storage") and data.projects[id].get("state") in ["built", "removed", "ruined"]:
			scope.containers[id + ":contents"] = true
		if data.projects[id].get("state") in ["removed", "ruined"]:
			scope.containers[id + ":salvage"] = true
		for suffix: String in [":supply", ":build", ":salvage", ":return"]:
			scope.operations[id + suffix] = true
	for job: Variant in data.active.values():
		if job is Dictionary and job.get("reserved") == true and job.get("id") is String:
			scope.reservations[job.id] = true
	return scope


static func valid(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "sites", "projects", "active", "zones", "next_zone", "next_project", "next_job", "next_check_ms"]) or data.version != 3 or not data.sites is Dictionary or not data.projects is Dictionary or not data.active is Dictionary or not data.zones is Dictionary or not Shape.count(data.next_zone, 1) or not Shape.count(data.next_project, 1) or not Shape.count(data.next_job, 1) or not Shape.count(data.next_check_ms, domain.world.elapsed_ms + 1):
		return false
	if data.projects.size() != int(data.next_project) - 1 or data.sites.size() > 16 or data.zones.size() > 64:
		return false
	var rules: Dictionary = domain.definitions
	for index: int in data.sites.size():
		if not data.sites.has("sect_yard" if index == 0 else "construction_site:%d" % (index + 1)):
			return false
	var bounds_list: Array[Rect2i] = []
	for site_id: Variant in data.sites:
		var site: Variant = data.sites[site_id]
		if not site_id is String or not SimInventory._nonempty(site_id) or not Shape.keys(site, ["region", "owner", "origin", "size", "created_by", "created_ms"]) or site.region != rules.site.region or not domain.world.regions.has(site.region) or not domain.authorized(str(site.created_by)) or not Shape.cell_valid(site.origin) or not SimConstructionGeometry._pair(site.size, 1, 32) or not Shape.count(site.created_ms, 0, domain.world.elapsed_ms) or site.owner != domain.world.regions[site.region].config.institution.id:
			return false
		var source: Vector2i = SimRouteTravel.cell(domain.world.regions[site.region].places[rules.site.source].cell)
		if source.distance_to(SimRouteTravel.cell(site.origin)) > float(rules.site.source_cells):
			return false
		var bounds := Rect2i(SimRouteTravel.cell(site.origin), SimRouteTravel.cell(site.size))
		for other: Rect2i in bounds_list:
			if bounds.intersects(other):
				return false
		bounds_list.append(bounds)
	if data.sites.is_empty() and not data.projects.is_empty():
		return false
	for zone_id: Variant in data.zones:
		var zone: Variant = data.zones[zone_id]
		if not zone_id is String or not SimInventory._nonempty(zone_id) or not Shape.keys(zone, ["site", "origin", "size", "purpose"]) or not zone.site is String or not data.sites.has(zone.site) or not Shape.cell_valid(zone.origin) or not SimConstructionGeometry._pair(zone.size, 1, 32) or not SimInventory._nonempty(zone.purpose) or str(zone.purpose).length() > 64:
			return false
		var raw_id: String = zone_id.trim_prefix("zone:")
		if not zone_id.begins_with("zone:") or not raw_id.is_valid_int() or str(int(raw_id)) != raw_id or not Shape.count(int(raw_id), 1, int(data.next_zone) - 1):
			return false
		var site: Dictionary = data.sites[zone.site]
		if not Rect2i(SimRouteTravel.cell(site.origin), SimRouteTravel.cell(site.size)).encloses(Rect2i(SimRouteTravel.cell(zone.origin), SimRouteTravel.cell(zone.size))):
			return false
	var used_cells: Dictionary = {}
	var pending: bool = false
	for index: int in range(1, int(data.next_project)):
		var id: String = "construction:%d" % index
		var project: Variant = data.projects.get(id)
		if not _project(project, id, data, domain):
			return false
		if project.state in ["blueprint", "built", "ruined"]:
			for cell: Vector2i in SimConstructionGeometry.cells(project, rules.types[project.type]):
				var key: String = str(cell) + ":" + str(rules.types[project.type].layer)
				if used_cells.has(key):
					return false
				used_cells[key] = true
		pending = pending or project.state == "blueprint"
	if (int(data.next_check_ms) == SimInventory.MAX_COUNT) == pending or pending and int(data.next_check_ms) > domain.world.elapsed_ms + int(rules.check_ms):
		return false
	var workers: Dictionary = {}
	var orders: Dictionary = {}
	for actor: Variant in data.active:
		var job: Variant = data.active[actor]
		if not actor is String or not _job(actor, job, data, domain) or workers.has(job.id) or orders.has(job.project):
			return false
		workers[job.id] = true
		orders[job.project] = true
	for id: String in data.projects:
		var project: Dictionary = data.projects[id]
		if not str(project.carrier).is_empty() and (not data.active.has(project.carrier) or data.active[project.carrier].project != id or not data.active[project.carrier].phase in ["to_site", "to_store"]):
			return false
	return true


static func _project(project: Variant, id: String, data: Dictionary, domain: RefCounted) -> bool:
	if not Shape.keys(project, ["site", "type", "cell", "rotation", "hp", "state", "open", "created_by", "created_ms", "completed_ms", "removed_ms", "work_ms", "material_cell", "carrier", "delivered", "line"]) or not project.site is String or not data.sites.has(project.site) or not domain.definitions.types.has(project.type) or not project.state in ["blueprint", "built", "removed", "cancelled", "ruined"] or not project.open is bool or not project.delivered is bool or not project.carrier is String or not project.line is String or not domain.authorized(str(project.created_by)) or not Shape.cell_valid(project.cell) or not Shape.cell_valid(project.material_cell):
		return false
	var rule: Dictionary = domain.definitions.types[project.type]
	for value: Variant in [project.created_ms, project.completed_ms, project.removed_ms]:
		if not Shape.count(value, 0, domain.world.elapsed_ms):
			return false
	var site: Dictionary = data.sites[project.site]
	if project.created_ms < site.created_ms or not Shape.count(project.work_ms, 0, int(rule.work_ms)) or not Shape.count(project.rotation, 0, 3) or not Shape.count(project.hp, 1 if project.state == "built" else 0, int(rule.max_hp) if project.state == "built" else 0):
		return false
	var bounds := Rect2i(SimRouteTravel.cell(site.origin), SimRouteTravel.cell(site.size))
	for cell: Vector2i in SimConstructionGeometry.cells(project, rule):
		if not bounds.has_point(cell) or domain.protected_cell(cell):
			return false
	if project.open and (not rule.door or project.state != "built"):
		return false
	var inventory: SimInventory = domain.world.regions[domain.definitions.site.region].inventory
	if not inventory.containers.has(id) or not _only_item(inventory.containers[id], str(rule.item)):
		return false
	var supplied: bool = inventory.operations.has(id + ":supply")
	var returned: bool = inventory.operations.has(id + ":return")
	var amount: int = int(rule.amount) if supplied and project.state in ["blueprint", "cancelled"] else int(rule.salvage) if project.state in ["removed", "ruined"] else 0
	if returned:
		if not project.state in ["cancelled", "removed", "ruined"] or amount == 0 or not _transfer(inventory.operations[id + ":return"], id, str(domain.definitions.site.source), str(rule.item), amount, ""):
			return false
		amount = 0
	if inventory.quantity(id, str(rule.item)) != amount or not supplied and (project.delivered or not project.carrier.is_empty() or project.work_ms != 0):
		return false
	if supplied:
		var receipt: Variant = inventory.operations[id + ":supply"]
		if not receipt is Dictionary or not receipt.get("reservation_id") is String or not _job_id(str(receipt.reservation_id), int(data.next_job)) or not _transfer(receipt, str(domain.definitions.site.source), id, str(rule.item), int(rule.amount), str(receipt.reservation_id)):
			return false
	var built: bool = project.state in ["built", "removed", "ruined"]
	if inventory.operations.has(id + ":build") != built:
		return false
	if built:
		if not supplied or project.work_ms != rule.work_ms or project.completed_ms < project.created_ms or not Shape.same_record(inventory.operations[id + ":build"], {"kind": "consume", "container": id, "item": str(rule.item), "amount": int(rule.amount)}):
			return false
	elif project.completed_ms != 0:
		return false
	if inventory.operations.has(id + ":salvage") != (project.state in ["removed", "ruined"]):
		return false
	if project.state in ["removed", "ruined"]:
		if project.removed_ms < project.completed_ms or not inventory.containers.has(id + ":salvage") or inventory.quantity(id + ":salvage", str(rule.item)) != 0 or not _only_item(inventory.containers[id + ":salvage"], str(rule.item)) or not _transfer(inventory.operations[id + ":salvage"], id + ":salvage", id, str(rule.item), int(rule.salvage), ""):
			return false
	elif project.removed_ms != 0:
		return false
	if amount == 0 and not project.carrier.is_empty():
		return false
	var contents: String = id + ":contents"
	if rule.capabilities.has("storage") and built:
		if not inventory.containers.has(contents) or not domain.contents_valid(project, inventory.containers[contents]):
			return false
		if project.state == "removed" and inventory.containers[contents].values().any(func(value: int) -> bool: return value > 0):
			return false
	elif inventory.containers.has(contents):
		return false
	return true


static func _job(actor: String, job: Variant, data: Dictionary, domain: RefCounted) -> bool:
	if not Shape.keys(job, ["id", "actor", "project", "kind", "phase", "path", "segment_from", "segment_started_ms", "due_ms", "destination", "stand", "started_ms", "work_started_ms", "previous_autonomous", "reserved"]) or job.actor != actor or not domain.authorized(actor) or not job.id is String or not _job_id(str(job.id), int(data.next_job)) or not data.projects.has(job.project) or not job.kind in ["build", "demolish", "recover", "open", "close"] or not job.phase in ["to_supply", "pickup", "to_site", "to_store", "work"] or not job.previous_autonomous is bool or not job.reserved is bool or not job.path is Array or not Shape.cell_valid(job.destination) or not Shape.cell_valid(job.stand):
		return false
	var world: RefCounted = domain.world
	var sim: RefCounted = world.regions[domain.definitions.site.region]
	var body: Dictionary = sim.actors[actor]
	if bool(body.autonomous) or not body.active.is_empty() or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or world.artifacts.owns_actor(actor) or world.admissions.owns_actor(actor) or world.soul_vessels.owns_actor(actor) or world.sparring.owns_actor(actor) or world.services != null and world.services.owns_actor(actor):
		return false
	var project: Dictionary = data.projects[job.project]
	var rule: Dictionary = domain.definitions.types[project.type]
	if job.kind == "build" and project.state != "blueprint" or job.kind == "recover" and not project.state in ["cancelled", "removed", "ruined"] or job.kind == "demolish" and project.state not in ["built", "ruined"] or job.kind in ["open", "close"] and project.state != "built":
		return false
	if job.kind == "demolish" and not domain._contents_empty(str(job.project)):
		return false
	if job.kind in ["open", "close"] and (not rule.door or project.open == (job.kind == "open")):
		return false
	var footprint: Array[Vector2i] = SimConstructionGeometry.cells(project, rule)
	var stand: Vector2i = SimRouteTravel.cell(job.stand)
	if stand in footprint or not footprint.any(func(cell: Vector2i) -> bool: return absi(cell.x - stand.x) + absi(cell.y - stand.y) == 1):
		return false
	for value: Variant in [job.started_ms, job.work_started_ms, job.segment_started_ms]:
		if not Shape.count(value, int(project.created_ms), world.elapsed_ms):
			return false
	if not Shape.count(job.due_ms, world.elapsed_ms + 1):
		return false
	if bool(job.reserved):
		if job.kind != "build" or not job.phase in ["to_supply", "pickup"] or sim.inventory.operations.has(str(job.project) + ":supply") or not sim.inventory.reservations.has(job.id) or not Shape.same_record(sim.inventory.reservations[job.id], {"container": str(domain.definitions.site.source), "item": str(rule.item), "amount": int(rule.amount), "owner_id": actor}):
			return false
	elif sim.inventory.reservations.has(job.id):
		return false
	var target: Array = sim.places[domain.definitions.site.source].cell if job.phase == "to_store" else job.stand if job.phase in ["to_site", "work"] else sim.places[domain.definitions.site.source].cell if job.reserved else project.material_cell
	if job.destination != target:
		return false
	if str(job.phase).begins_with("to_"):
		var current: Vector2i = SimRouteTravel.cell(body.cell)
		for raw: Variant in job.path:
			if not Shape.cell_valid(raw):
				return false
			var next: Vector2i = SimRouteTravel.cell(raw)
			if absi(next.x - current.x) > 1 or absi(next.y - current.y) > 1:
				return false
			current = next
		if current != SimRouteTravel.cell(target) or not SimRouteTravel.valid_segment(job, body, world.elapsed_ms, domain._speed()):
			return false
	else:
		var duration: int = int(domain.definitions.pickup_ms) if job.phase == "pickup" else maxi(1, int(rule.work_ms) - int(project.work_ms)) if job.kind == "build" else int(rule.demolish_ms) if job.kind == "demolish" else int(domain.definitions.operate_ms)
		if not job.path.is_empty() or body.cell != target or int(job.due_ms) != int(job.work_started_ms) + duration:
			return false
	if job.phase == "work" and job.kind == "build" and (not project.delivered or not project.carrier.is_empty() or project.material_cell != job.stand):
		return false
	var amount: int = sim.inventory.quantity(job.project, str(rule.item))
	if job.phase in ["to_supply", "pickup"] and not job.reserved and (amount == 0 or project.delivered or not project.carrier.is_empty()):
		return false
	if job.phase == "to_site" and job.kind == "build" and (amount != int(rule.amount) or not project.delivered and project.carrier != actor or project.delivered and not project.carrier.is_empty()):
		return false
	if job.phase == "to_store" and (job.kind != "recover" or project.carrier != actor or amount == 0):
		return false
	return true


static func _job_id(id: String, limit: int) -> bool:
	var raw: String = id.trim_prefix("construction_job:")
	return id.begins_with("construction_job:") and raw.is_valid_int() and str(int(raw)) == raw and int(raw) >= 1 and int(raw) < limit


static func _only_item(items: Dictionary, item: String) -> bool:
	for key: String in items:
		if key != item:
			return false
	return true


static func _transfer(record: Variant, source: String, target: String, item: String, amount: int, reservation: String) -> bool:
	return Shape.same_record(record, {"kind": "transfer", "source": source, "target": target, "item": item, "amount": amount, "reservation_id": reservation})
