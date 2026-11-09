class_name SimSparring
extends RefCounted
## Voluntary, restrained combat over original actor bodies. No scene-owned rules.

const RULES_PATH: String = "res://data/definitions/sparring.json"
const NEVER: int = 0x3fffffffffffffff

var rules: Dictionary = {}
var bout: Dictionary = {}
var last_result: Dictionary = {}
var _next_id: int = 1
var _owner: WeakRef
var _contact_guard: Callable
var _step_guard: Callable
var world: RefCounted:
	get:
		return _owner.get_ref() if _owner != null else null


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted) -> bool:
	_owner = weakref(authority)
	var raw: Variant = authority._content.sparring
	if not valid_rules(raw):
		return false
	rules = raw
	return true


func set_geometry(contact_guard: Callable, step_guard: Callable) -> void:
	_contact_guard = contact_guard
	_step_guard = step_guard


func owns_actor(id: String) -> bool:
	return not bout.is_empty() and bout.people.has(id)


func action_blocks(id: String) -> bool:
	return owns_actor(id) and (not bout.people[id].action.is_empty() or int(bout.people[id].ready_ms) > world.elapsed_ms)


func body(id: String) -> Dictionary:
	for simulation: VillageSimulation in world.regions.values():
		if simulation.actors.has(id):
			return simulation.actors[id]
	return {}


func _home(id: String) -> String:
	for region: String in world.regions:
		if world.regions[region].actors.has(id):
			return region
	return ""


func invite(initiator: String, partner: String) -> Dictionary:
	if world.elapsed_ms > SimInventory.MAX_COUNT - int(rules.duration_ms):
		return _reply(false, "世界时刻已超出可记录的约练范围。")
	if not bout.is_empty() or initiator == partner or _home(initiator).is_empty() or _home(initiator) != _home(partner):
		return _reply(false, "眼下没有合适的同门可以约练。")
	var region: String = _home(initiator)
	world.synchronize_region(region)
	for id: String in [initiator, partner]:
		var person: Dictionary = body(id)
		if not world.actor_controls(id, "action") or not world.actor_controls(id, "motion") or not world.actor_controls(id, "communication"):
			return _reply(false, "眼下无法回应或支配身体，不能约练。")
		if world.local_action_owns(id) or world.artifacts.owns_actor(id) or (world.services != null and world.services.owns_actor(id)):
			return _reply(false, "对方或你正有别的事务，先把手头事情办完。")
		if float(person.energy) < float(rules.min_energy) or float(person.hunger) < float(rules.min_hunger) or int(person.stamina) <= int(rules.stop_stamina) + int(rules.strike.stamina):
			return _reply(false, "眼下太疲惫或腹中空空，改日再切磋。")
		if not person.active.is_empty() and world.regions[region].config.actions[person.active.action].kind != "visit":
			return _reply(false, "还有实在的活计没有办妥，暂不陪练。")
	if SimRouteTravel.point(body(initiator)).distance_to(SimRouteTravel.point(body(partner))) > float(rules.invite_radius):
		return _reply(false, "请先走近同门，再开口约练。")
	var people: Dictionary = {}
	for id: String in [initiator, partner]:
		people[id] = {"autonomous": bool(body(id).autonomous), "action": {}, "ready_ms": world.elapsed_ms, "hits": 0}
		world.regions[region].cancel_action(id, "agreed_practice")
		body(id).autonomous = false
		body(id).goal = "约练，点到为止"
	bout = {"id": _next_id, "region": region, "initiator": initiator, "partner": partner,
		"started_ms": world.elapsed_ms, "last_ms": world.elapsed_ms,
		"next_step_ms": world.elapsed_ms + int(rules.step_ms), "people": people}
	_next_id += 1
	world.invalidate_region(region)
	world.regions[region].observe("sparring_started", initiator, partner, {})
	return _reply(true, "对方答应点到为止。J 出掌，WASD 走位，Shift 闪身；可随时收手。")


func strike(id: String, direction: Vector2) -> bool:
	if not owns_actor(id) or action_blocks(id) or not direction.is_finite() or direction.is_zero_approx() or not world.actor_controls(id, "action"):
		return false
	if world._local_action_owner.is_valid() and bool(world._local_action_owner.call(id)):
		return false
	var person: Dictionary = body(id)
	var spec: Dictionary = rules.strike
	if int(person.stamina) < int(spec.stamina) or world.elapsed_ms > SimInventory.MAX_COUNT - _duration() - int(world.regions[_home(id)].motion_rules.recovery.delay_ms):
		return false
	person.stamina = int(person.stamina) - int(spec.stamina)
	person.exertion_until_ms = world.elapsed_ms + _duration() + int(world.regions[_home(id)].motion_rules.recovery.delay_ms)
	person.stamina_carry = 0
	var facing: Vector2 = direction.normalized()
	bout.people[id].action = {"started_ms": world.elapsed_ms, "direction": [facing.x, facing.y], "hit": false}
	return true


func phase(id: String, at_ms: int) -> String:
	if not owns_actor(id) or bout.people[id].action.is_empty():
		return ""
	var elapsed: int = at_ms - int(bout.people[id].action.started_ms)
	if elapsed < int(rules.strike.prepare_ms):
		return "prepare"
	if elapsed < int(rules.strike.prepare_ms) + int(rules.strike.contact_ms):
		return "contact"
	return "recover" if elapsed < _duration() else ""


func next_boundary_ms() -> int:
	if bout.is_empty():
		return NEVER
	var boundary: int = mini(int(bout.next_step_ms), int(bout.started_ms) + int(rules.duration_ms))
	for person: Dictionary in bout.people.values():
		if not person.action.is_empty():
			var start: int = int(person.action.started_ms)
			for offset: int in [int(rules.strike.prepare_ms), int(rules.strike.prepare_ms) + int(rules.strike.contact_ms), _duration()]:
				if start + offset > world.elapsed_ms:
					boundary = mini(boundary, start + offset)
	return boundary


func settle_at_ms(now: int) -> void:
	if bout.is_empty():
		return
	# RegionalSimulation already selected a boundary using the pre-commit clock.
	# A partial target before every pending phase must leave the state untouched.
	var due: bool = now >= int(bout.next_step_ms) or now >= int(bout.started_ms) + int(rules.duration_ms)
	for person: Dictionary in bout.people.values():
		if not person.action.is_empty():
			var age: int = now - int(person.action.started_ms)
			due = due or age == int(rules.strike.prepare_ms) or age == int(rules.strike.prepare_ms) + int(rules.strike.contact_ms) or age == _duration()
	if not due:
		return
	world.synchronize_region(str(bout.region))
	var ids: Array = bout.people.keys()
	ids.sort()
	for id: String in ids:
		if not world.actor_controls(id, "action") or not world.actor_controls(id, "motion"):
			stop("control_lost")
			return
	if now >= int(bout.started_ms) + int(rules.duration_ms) or SimRouteTravel.point(body(str(ids[0]))).distance_to(SimRouteTravel.point(body(str(ids[1])))) > float(rules.leash_radius):
		stop("finished")
		return
	# AI motion is committed before contact collection. Both effects read the
	# same resulting geometry, so dictionary order cannot cancel a mutual hit.
	_ai_motion(str(bout.partner), now - int(bout.last_ms))
	var contacts: Array[String] = []
	for id: String in ids:
		var action: Dictionary = bout.people[id].action
		if not action.is_empty() and not bool(action.hit) and phase(id, now) == "contact" and _covers(id, opponent(id)):
			contacts.append(id)
	for id: String in contacts:
		bout.people[id].action.hit = true
		bout.people[id].hits = int(bout.people[id].hits) + 1
	for id: String in contacts:
		var target: String = opponent(id)
		var person: Dictionary = body(target)
		person.stamina = maxi(0, int(person.stamina) - int(rules.strike.pressure))
		person.stamina_carry = 0
		person.exertion_until_ms = maxi(int(person.exertion_until_ms), now + int(world.regions[_home(target)].motion_rules.recovery.delay_ms))
		bout.people[target].action = {}
		bout.people[target].ready_ms = maxi(int(bout.people[target].ready_ms), now + int(rules.stagger_ms))
		world.regions[bout.region].observe("practice_hit", id, target, {})
	for id: String in ids:
		if int(body(id).stamina) <= int(rules.stop_stamina):
			stop("tired")
			return
		if not bout.people[id].action.is_empty() and now >= int(bout.people[id].action.started_ms) + _duration():
			bout.people[id].action = {}
			bout.people[id].ready_ms = now + (int(rules.ai_pause_ms) if id == bout.partner else 0)
	bout.last_ms = now
	bout.next_step_ms = now + int(rules.step_ms)
	var partner: String = bout.partner
	if not action_blocks(partner) and SimRouteTravel.point(body(partner)).distance_to(SimRouteTravel.point(body(str(bout.initiator)))) <= float(rules.strike.reach) and _contact_possible(partner, str(bout.initiator)):
		strike(partner, SimRouteTravel.point(body(str(bout.initiator))) - SimRouteTravel.point(body(partner)))
	world.invalidate_region(str(bout.region))


func opponent(id: String) -> String:
	return str(bout.partner) if id == bout.initiator else str(bout.initiator)


func _covers(id: String, target: String) -> bool:
	var origin: Vector2 = SimRouteTravel.point(body(id))
	var delta: Vector2 = SimRouteTravel.point(body(target)) - origin
	if delta.length() > float(rules.strike.reach):
		return false
	var raw: Array = bout.people[id].action.direction
	var facing := Vector2(float(raw[0]), float(raw[1]))
	if not delta.is_zero_approx() and facing.dot(delta.normalized()) < cos(deg_to_rad(float(rules.strike.half_angle_degrees))):
		return false
	return _contact_possible(id, target)


func _contact_possible(id: String, target: String) -> bool:
	return not _contact_guard.is_valid() or bool(_contact_guard.call(SimRouteTravel.point(body(id)), SimRouteTravel.point(body(target))))


func _ai_motion(id: String, duration_ms: int) -> void:
	if action_blocks(id):
		return
	var person: Dictionary = body(id)
	var point: Vector2 = SimRouteTravel.point(person)
	var delta: Vector2 = SimRouteTravel.point(body(opponent(id))) - point
	var spacing: float = float(rules.strike.reach) * float(rules.ai_spacing_fraction) if _contact_possible(id, opponent(id)) else float(rules.ai_close_distance)
	var distance: float = maxf(0.0, delta.length() - spacing)
	var travel: float = minf(distance, float(world.regions[_home(id)].motion_rules.motion.speed) * float(rules.ai_speed_fraction) * duration_ms / 1000.0)
	var sweep: float = float(world.regions[_home(id)].motion_rules.motion.sweep_px)
	while travel > 0.0:
		var step: float = minf(sweep, travel)
		var next: Vector2 = point + delta.normalized() * step
		var from: Vector2i = TileGrid.world_to_cell(point)
		var to: Vector2i = TileGrid.world_to_cell(next)
		if _step_guard.is_valid() and from != to and not bool(_step_guard.call(from, to - from)):
			break
		point = next
		travel -= step
	world.regions[_home(id)].set_actor_position(id, point)


func stop(reason: String = "yielded") -> void:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return
	if bout.is_empty():
		return
	last_result = {"reason": reason, "at_ms": world.elapsed_ms, "initiator": bout.initiator, "partner": bout.partner}
	for id: String in bout.people:
		body(id).autonomous = bool(bout.people[id].autonomous)
		body(id).goal = "切磋收手，稍作调息"
		body(id).retry_ms = world.elapsed_ms + int(world.regions[bout.region].config.decision_interval) * 60000
	world.regions[bout.region].observe("sparring_ended", str(bout.initiator), str(bout.partner), {"reason": reason})
	world.invalidate_region(str(bout.region))
	var finished: Dictionary = bout
	bout = {}
	for actor: String in finished.people:
		SimActionContract.job_finished(world, "sparring", finished, actor, "completed" if reason == "finished" else "cancelled", reason)


func _duration() -> int:
	return int(rules.strike.prepare_ms) + int(rules.strike.contact_ms) + int(rules.strike.recover_ms)


static func empty_state() -> Dictionary:
	return {"version": 1, "next_id": 1, "bout": {}, "last_result": {}}


func to_dict() -> Dictionary:
	return {"version": 1, "next_id": _next_id, "bout": bout.duplicate(true), "last_result": last_result.duplicate(true)}


func restore(data: Variant) -> bool:
	if not _valid_state(data):
		return false
	_next_id = int(data.next_id)
	bout = data.bout.duplicate(true)
	last_result = data.last_result.duplicate(true)
	return true


func _valid_state(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not SimSnapshotSchema._count(data.get("next_id"), 1) or not data.get("bout") is Dictionary or not data.get("last_result") is Dictionary:
		return false
	var saved: Dictionary = data.bout
	if not data.last_result.is_empty():
		if not _valid_result(data.last_result):
			return false
	if saved.is_empty():
		return true
	if not SimSnapshotSchema._count(saved.get("id"), 1) or int(saved.id) >= int(data.next_id) or not saved.get("region") is String or not world.regions.has(saved.region) or not saved.get("people") is Dictionary or saved.people.size() != 2:
		return false
	if not saved.get("initiator") is String or not saved.get("partner") is String or saved.initiator == saved.partner or not saved.people.has(saved.initiator) or not saved.people.has(saved.partner):
		return false
	for field: String in ["started_ms", "last_ms", "next_step_ms"]:
		if not SimSnapshotSchema._count(saved.get(field)):
			return false
	if int(saved.started_ms) > int(saved.last_ms) or int(saved.last_ms) > world.elapsed_ms or int(saved.next_step_ms) != int(saved.last_ms) + int(rules.step_ms) or int(saved.next_step_ms) <= world.elapsed_ms or int(saved.started_ms) + int(rules.duration_ms) <= int(saved.last_ms):
		return false
	for id: String in saved.people:
		if not world.regions[saved.region].actors.has(id) or not world.actor_controls(id, "action") or not world.actor_controls(id, "motion") or not body(id).active.is_empty() or bool(body(id).autonomous) or world.artifacts.owns_actor(id) or (world.soul_vessels != null and world.soul_vessels.owns_actor(id)) or (world.services != null and world.services.owns_actor(id)):
			return false
		var person: Variant = saved.people[id]
		if not person is Dictionary or not person.get("autonomous") is bool or not person.get("action") is Dictionary or not SimSnapshotSchema._count(person.get("ready_ms")) or not SimSnapshotSchema._count(person.get("hits")):
			return false
		var action: Dictionary = person.action
		if not action.is_empty():
			if not SimSnapshotSchema._count(action.get("started_ms")) or int(action.started_ms) < int(saved.started_ms) or int(action.started_ms) > world.elapsed_ms or int(action.started_ms) + _duration() <= int(saved.last_ms) or not action.get("hit") is bool or not SimLocalMotion._vector(action.get("direction")):
				return false
			if not is_equal_approx(Vector2(float(action.direction[0]), float(action.direction[1])).length(), 1.0) or (bool(action.hit) and world.elapsed_ms < int(action.started_ms) + int(rules.strike.prepare_ms)):
				return false
	return true


func _valid_result(result: Dictionary) -> bool:
	return result.get("reason") in ["yielded", "control_lost", "finished", "tired"] and SimSnapshotSchema._count(result.get("at_ms")) and int(result.at_ms) <= world.elapsed_ms and result.get("initiator") is String and result.get("partner") is String and not body(result.initiator).is_empty() and not body(result.partner).is_empty() and result.initiator != result.partner


static func valid_rules(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1 or not value.get("strike") is Dictionary:
		return false
	for field: String in ["step_ms", "duration_ms", "stop_stamina", "ai_pause_ms", "stagger_ms"]:
		if not SimSnapshotSchema._count(value.get(field), 1):
			return false
	for field: String in ["invite_radius", "leash_radius", "min_energy", "min_hunger", "ai_speed_fraction", "ai_spacing_fraction", "ai_close_distance"]:
		if not SimSnapshotSchema._number(value.get(field)) or float(value[field]) <= 0.0:
			return false
	for field: String in ["prepare_ms", "contact_ms", "recover_ms", "stamina", "pressure"]:
		if not SimSnapshotSchema._count(value.strike.get(field), 1):
			return false
	return value.strike.get("label") is String and SimSnapshotSchema._number(value.strike.get("reach")) and float(value.strike.reach) > 0 and SimSnapshotSchema._range(value.strike.get("half_angle_degrees"), 1, 180) and int(value.step_ms) <= int(value.strike.contact_ms) and float(value.ai_speed_fraction) <= 1.0 and float(value.ai_spacing_fraction) <= 1.0 and float(value.ai_close_distance) < float(value.strike.reach)


static func _reply(ok: bool, line: String) -> Dictionary:
	return {"ok": ok, "line": line}
