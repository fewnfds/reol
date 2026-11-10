class_name SettlementServices
extends RefCounted
## Cross-settlement services keep the visitor in their original identity ledger.

const Jobs = preload("res://scripts/sim/services/visitor_jobs.gd")
const Help = preload("res://scripts/sim/services/service_help.gd")
const Schema = preload("res://scripts/sim/services/service_schema.gd")
const Institutions = preload("res://scripts/sim/services/service_institutions.gd")
const Trade = preload("res://scripts/sim/services/local_trade.gd")
const Hauling = preload("res://scripts/sim/services/stock_hauling.gd")
const Inventory = preload("res://scripts/sim/inventory_ledger.gd")
const Social = preload("res://scripts/sim/social_memory.gd")
const Workplaces = preload("res://scripts/sim/workplaces.gd")

var definitions: Dictionary = {}
var jobs: Dictionary = {}
var active_jobs: Dictionary = {}
var receipts: Dictionary = {}
var authorizations: Dictionary = {}
var help_requests: Dictionary = {}
var operations: Dictionary = {}
var events: Array = []
var escrow: RefCounted = Inventory.new()
var social: RefCounted = Social.new()
var last_ms: int = 0
var last_time: int:
	get:
		return floori(float(last_ms) / 60000.0)
var next_id: int = 1
var _owner: WeakRef
var _navigation: Callable
var _can_step: Callable
var _jobs: RefCounted
var _help: RefCounted
var _institutions: RefCounted
var _trade: RefCounted
var _hauling: RefCounted
var _handling_stock: bool = false
var _rng := RandomNumberGenerator.new()
# Derived lookup only; rebuilding it on load keeps historical jobs out of the
# display hot path without adding another authoritative save field.
var _latest_jobs: Dictionary = {}

var world: RefCounted:
	get:
		return _owner.get_ref() if _owner != null else null


func initialize(simulation: RefCounted, settings: Dictionary) -> bool:
	if simulation == null or not Schema.valid_definitions(settings, simulation):
		return false
	_owner = weakref(simulation)
	definitions = settings.duplicate(true)
	last_ms = simulation.elapsed_ms
	_rng.seed = int(definitions.help.seed)
	_jobs = Jobs.new(self)
	_help = Help.new(self)
	_institutions = Institutions.new(self)
	_trade = Trade.new(self)
	_hauling = Hauling.new(self)
	social.configure({})
	for region: RefCounted in world.regions.values():
		for actor_id: String in region.synchronize_actors():
			social.register_actor(actor_id)
	for courier_id: String in world.couriers:
		social.register_actor(courier_id)
	return true


func bind_world(simulation: RefCounted) -> void:
	_owner = weakref(simulation)


func set_navigation(provider: Callable, step_validator: Callable = Callable()) -> void:
	_navigation = provider
	_can_step = step_validator


func begin(actor_id: String, region_id: String, action_id: String, options: Dictionary = {}) -> Dictionary:
	if world == null or not world.accepts_commands():
		return response(false, "pending_time", "先等当前世界结算完成。")
	return _jobs.begin(actor_id, region_id, action_id, options)


func begin_haul(actor: String, source: Dictionary, target: Dictionary, item: String, amount: int) -> Dictionary:
	return begin(actor, str(target.get("region", "")), "carry_stock", {"source": source, "target": target, "item": item, "amount": amount})


func cancel(actor_id: String, reason: String = "cancelled") -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	return _jobs.cancel(actor_id, reason)


func owns_actor(actor_id: String) -> bool:
	return active_jobs.has(actor_id)


func native_action_allowed(actor_id: String) -> bool:
	return world != null and world.actor_controls(actor_id, "action") and not owns_actor(actor_id)


func workplace_job_available(sim: RefCounted, actor_id: String, job_id: String) -> bool:
	# This is one original clerk's currently executing return registration,
	# never a general exemption from the body's other process owners.
	if world == null or world.services != self or active_jobs.get(actor_id, "") != job_id or not jobs.has(job_id):
		return false
	var job: Dictionary = jobs[job_id]
	if job.actor != actor_id or job.kind != "site_return" or job.status != "active" or job.phase != "work" or job.stage != "register" or not job.path.is_empty() or int(job.due_ms) > world.elapsed_ms:
		return false
	if not world.regions.has(job.home) or not world.regions.has(job.region) or world.regions[job.home] != sim or world.regions[job.region] != sim or not sim.has_actor(actor_id) or job.options.get("issuer") != actor_id:
		return false
	if world.get("site_affairs") == null or not Schema.same_value(job.spec, world.site_affairs.service_spec("site_return", str(job.region), job.options, "register")):
		return false
	var actor: Dictionary = sim.synchronize_actor(actor_id)
	if not actor.active.is_empty() or bool(actor.autonomous) or not world.actor_controls(actor_id, "communication") or not world.actor_controls(actor_id, "action") or not world.actor_controls(actor_id, "motion"):
		return false
	if world.body_action_owns(actor_id, &"services") or (world.construction != null and not world.construction.duty_for(actor_id).is_empty()) or (world.resting != null and not world.resting.duty_for(actor_id).is_empty()):
		return false
	return true


func status(actor_id: String) -> Dictionary:
	var id: String = str(active_jobs.get(actor_id, _latest_jobs.get(actor_id, "")))
	if id.is_empty() or not jobs.has(id):
		return {"busy": false, "line": "眼下没有正在办理的差事。"}
	var job: Dictionary = jobs[id]
	var busy: bool = owns_actor(actor_id)
	var outcome: String = str(job.outcome)
	return {"busy": busy, "id": job.id, "phase": job.phase, "stage": job.stage,
		"kind": job.kind, "status": job.status, "outcome": outcome,
		"line": outcome if not outcome.is_empty() else str(job.label),
		"remaining": maxi(0, ceili(float(int(job.due_ms) - world.elapsed_ms) / 60000.0)) if busy else 0}


func remember_job(job: Dictionary) -> void:
	var previous: String = str(_latest_jobs.get(job.actor, ""))
	if previous.is_empty() or int(str(job.id).get_slice(":", 2)) > int(previous.get_slice(":", 2)):
		_latest_jobs[job.actor] = job.id


func report_work(actor_id: String, region_id: String) -> Dictionary:
	return begin(actor_id, region_id, "report")


func redeem(actor_id: String, region_id: String, offer_id: String) -> Dictionary:
	return begin(actor_id, region_id, "redeem", {"offer": offer_id})


func request_access(actor_id: String, region_id: String, scope: String) -> Dictionary:
	return begin(actor_id, region_id, "access", {"scope": scope})


func has_access(actor_id: String, region_id: String, scope: String) -> bool:
	var key: String = region_id + ":" + actor_id + ":" + scope
	if not authorizations.has(key) or not world.regions.has(region_id):
		return false
	var permission: Dictionary = authorizations[key]
	var sim: RefCounted = world.regions[region_id]
	return sim.has_actor(permission.issuer) and bool(sim.synchronize_actor(permission.issuer).alive) and sim.institutions.has_permission(sim.config.institution.id, permission.issuer, "authorize")


func collection_allowed(job: Dictionary) -> bool:
	if job.options.has("admission"):
		return job.options.admission is String and world.admissions.valid_grant(job.options.admission, job.actor, job.region)
	return has_access(job.actor, job.region, job.spec.scope)


func ask_help(actor_id: String, courier_id: String, route_id: String, offer_coins: int = 0) -> Dictionary:
	return _help.ask(actor_id, courier_id, route_id, offer_coins)


func courier_claimed(courier_id: String) -> bool:
	for request: Dictionary in help_requests.values():
		if request.courier == courier_id and request.status == "accepted" and request.execution == "pending":
			return true
	return false


func expected_deliveries(region_id: String, container: String, item: String) -> int:
	var result: int = 0
	for actor_id: String in active_jobs:
		var job: Dictionary = jobs[active_jobs[actor_id]]
		if job.kind != "haul_grain":
			continue
		var route: Dictionary = world.settings.routes[job.route]
		if route.to == region_id and route.target == container and route.item == item:
			result += int(job.amount)
	return result


func next_boundary_ms() -> int:
	var boundary: int = 0x3fffffffffffffff
	for actor_id: String in active_jobs:
		var job: Dictionary = jobs[active_jobs[actor_id]]
		if not world.actor_controls(actor_id, "action") or not world.actor_controls(actor_id, "motion"):
			return world.elapsed_ms + 1
		boundary = mini(boundary, int(job.due_ms))
		boundary = mini(boundary, int(job.started_ms) + int(definitions.job_timeout) * 60000)
		if job.phase == "travel":
			boundary = mini(boundary, SimRouteTravel.next_boundary(job, world.regions[job.home].synchronize_actor(actor_id), world.elapsed_ms, route_step.bind(job.home))) if not bool(job.get("road_paused", false)) else boundary
	return maxi(world.elapsed_ms + 1, boundary)


func settle_at_ms(at_ms: int) -> void:
	var elapsed: int = at_ms - last_ms
	var ids: Array = active_jobs.keys()
	ids.sort()
	for actor_id: String in ids:
		if not active_jobs.has(actor_id):
			continue
		var job: Dictionary = jobs[active_jobs[actor_id]]
		world.synchronize_region(job.home)
		var sim: RefCounted = world.regions[job.home]
		var actor: Dictionary = sim.synchronize_actor(actor_id)
		sim._decay_need(actor, "energy", roundi(float(definitions.work_energy_per_minute) * 1000000.0), elapsed)
		if not world.actor_controls(actor_id, "action") or not world.actor_controls(actor_id, "motion") or at_ms >= int(job.started_ms) + int(definitions.job_timeout) * 60000:
			_jobs.finish(job, false, "差事中止，已取出的物资仍随身保存。")
		else:
			if job.kind == "carry_stock":
				_hauling.settle(job, at_ms)
				continue
			if job.phase == "travel":
				if job.kind == "haul_grain" and job.stage == "delivery" and bool(world.routes[job.route].blocked):
					job["road_paused"] = true
					job.segment_started_ms = at_ms
					job.segment_from = actor.position.duplicate()
					job.due_ms = at_ms + int(definitions.move_minutes_per_cell) * 60000
					job.outcome = "山路受阻，带着货物等候通行。"
					continue
				if bool(job.get("road_paused", false)):
					job.road_paused = false
					job.outcome = ""
					SimRouteTravel.begin_segment(job, actor, at_ms, float(sim.motion_rules.motion.speed))
				else:
					if not SimRouteTravel.repair(sim, actor_id, job, at_ms, [], -1.0, route_step.bind(job.home)):
						_jobs.finish(job, false, "道路受阻，已停在原处；随身物资没有消失。")
						continue
					sim.project_actor_route(actor_id, job, at_ms)
			if int(job.due_ms) <= at_ms:
				_jobs.settle(job)
	_help.settle()
	last_ms = at_ms


func route_step(from: Vector2i, direction: Vector2i, home: String) -> bool:
	var sim: VillageSimulation = world.regions[home]
	return (not _can_step.is_valid() or bool(_can_step.call(from, direction))) and (not sim._step_validator.is_valid() or bool(sim._step_validator.call(from, direction)))


func actor_home(actor_id: String) -> String:
	for region_id: String in world.regions:
		if world.regions[region_id].has_actor(actor_id):
			return region_id
	return ""


func path_between(home: String, from_cell: Array, to_cell: Array) -> Array:
	var origin := Vector2i(int(from_cell[0]), int(from_cell[1]))
	var target := Vector2i(int(to_cell[0]), int(to_cell[1]))
	if origin == target:
		return []
	var raw: Array = _navigation.call(origin, target) if _navigation.is_valid() else world.regions[home].find_path(origin, target)
	var path: Array = []
	var previous: Vector2i = origin
	for value: Variant in raw:
		if not value is Vector2i:
			return []
		var point: Vector2i = value
		if point == origin and path.is_empty():
			continue
		var delta: Vector2i = point - previous
		if absi(delta.x) > 1 or absi(delta.y) > 1 or delta == Vector2i.ZERO:
			return []
		path.append([point.x, point.y])
		previous = point
	return path if previous == target else []


func transfer(operation_id: String, from_region: String, from_container: String, to_region: String, to_container: String, item: String, amount: int, custody_id: String = "", reservation_id: String = "") -> bool:
	if operation_id.is_empty() or item.is_empty() or amount <= 0 or amount > Inventory.MAX_COUNT:
		return false
	if (from_region != "escrow" and not world.regions.has(from_region)) or (to_region != "escrow" and not world.regions.has(to_region)):
		return false
	var signature: Dictionary = {"from": from_region, "source": from_container, "to": to_region, "target": to_container, "item": item, "amount": amount}
	if operations.has(operation_id):
		return Schema.same_value(operations[operation_id], signature)
	# Ground piles are managed through the object lifecycle, which keeps their
	# placement and environmental invalidation together. Existing historical
	# receipts still replay above without another write.
	if from_container.begins_with("ground:") or to_container.begins_with("ground:"):
		return false
	var source: RefCounted = escrow if from_region == "escrow" else world.regions[from_region].inventory
	var target: RefCounted = escrow if to_region == "escrow" else world.regions[to_region].inventory
	if not source.containers.has(from_container) or not target.containers.has(to_container) or amount <= 0:
		return false
	if source == target and from_container == to_container:
		return false
	if amount > Inventory.MAX_COUNT - target.quantity(to_container, item):
		return false
	if reservation_id.is_empty():
		if not source.can_use(from_container, item, amount, custody_id):
			return false
	elif not custody_id.is_empty() or not source.reservations.has(reservation_id) or source.reservations[reservation_id].container != from_container or source.reservations[reservation_id].item != item or int(source.reservations[reservation_id].amount) != amount or source.quantity(from_container, item) < amount:
		return false
	source.containers[from_container][item] = source.quantity(from_container, item) - amount
	target.containers[to_container][item] = target.quantity(to_container, item) + amount
	operations[operation_id] = signature
	if not reservation_id.is_empty():
		source.release(reservation_id)
	if not custody_id.is_empty():
		source.settle_custody(custody_id, "service", operation_id)
	source.contents_changed.emit(from_container)
	target.contents_changed.emit(to_container)
	if from_region != "escrow":
		world.invalidate_region(from_region)
	if to_region != "escrow":
		world.invalidate_region(to_region)
	return true


func issuer(region_id: String, actor_id: String, permission: String) -> String:
	var home: String = actor_home(actor_id)
	if home.is_empty() or permission.is_empty() or not world.synchronize_region(region_id):
		return ""
	var sim: RefCounted = world.regions[region_id]
	var visitor: Dictionary = world.regions[home].synchronize_actor(actor_id)
	if not visitor.alive:
		return ""
	var visitor_cell := Vector2(float(visitor.cell[0]), float(visitor.cell[1]))
	for id: String in sim._actor_ids():
		var person: Dictionary = sim.synchronize_actor(id)
		if person.alive and sim.institutions.has_permission(sim.config.institution.id, id, permission):
			if visitor_cell.distance_to(Vector2(float(person.cell[0]), float(person.cell[1]))) <= float(sim.config.talk_radius) and bool(Workplaces.assessment(sim, id, permission).ok):
				return id
	return ""


func record(kind: String, actor_id: String, details: Dictionary) -> String:
	var id: String = allocate("event")
	events.append({"id": id, "kind": kind, "actor": actor_id, "at": world.current_time, "details": details.duplicate(true)})
	return id


func allocate(prefix: String) -> String:
	var id: String = "service:%s:%d" % [prefix, next_id]
	next_id += 1
	return id


func response(ok: bool, reason: String, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "reason": reason, "line": line, "id": id}


func to_dict() -> Dictionary:
	return world._json_keys({
		"version": 5, "definitions": definitions.duplicate(true), "jobs": jobs.duplicate(true),
		"active_jobs": active_jobs.duplicate(true), "receipts": receipts.duplicate(true),
		"authorizations": authorizations.duplicate(true), "help_requests": help_requests.duplicate(true),
		"operations": operations.duplicate(true), "events": events.duplicate(true),
		"escrow": escrow.to_dict(), "social": social.to_dict(), "rng_state": str(_rng.state),
		"last_time": last_time, "last_ms": last_ms, "next_id": next_id,
	})


func restore(data: Dictionary) -> bool:
	if not Schema.validate_snapshot(data, self):
		return false
	var next_escrow := Inventory.new()
	var next_social := Social.new()
	if not next_escrow.restore(data.escrow) or not next_social.restore(data.social):
		return false
	for field: String in ["jobs", "active_jobs", "receipts", "authorizations", "help_requests", "operations"]:
		set(field, data[field].duplicate(true))
	_latest_jobs.clear()
	for job: Dictionary in jobs.values():
		remember_job(job)
	events = data.events.duplicate(true)
	escrow = next_escrow
	social = next_social
	last_ms = int(data.last_ms)
	next_id = int(data.next_id)
	_rng.state = int(data.rng_state)
	return true
