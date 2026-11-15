extends RefCounted
## One action executor for direct control and AI. World alone commits effects.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Scan = preload("res://scripts/sim/kernel/combat_scan.gd")
const Motion = preload("res://scripts/sim/kernel/motion.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Projectiles = preload("res://scripts/sim/kernel/combat_projectiles.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Payload = preload("res://scripts/sim/kernel/effect_payload.gd")
const CONTACT_MEMORY_MS: int = 5000
const STATE_FIELDS: Array = ["engagements", "states", "cooldowns", "chains", "status", "intents", "bolts", "next_bolt", "next_activation", "shots", "hits", "resumed", "unreachable", "_brain_bucket", "catalog_signature"]
var catalog_signature: String = Defs.SIGNATURE
var engagements: Dictionary = {} # AI contacts, never player attack-move orders.
var states: Dictionary = {}
var cooldowns: Dictionary = {}
var chains: Dictionary = {}
var status: Dictionary = {}
var intents: Dictionary = {} # One mutually exclusive, short-lived next action per actor.
var controls: Dictionary = {} # Latest local held state, deliberately not saved.
var unreachable: Dictionary = {}
var bolts: Dictionary = {}
var next_bolt: int = 1
var next_activation: int = 1
var shots: int = 0
var hits: int = 0
var resumed: int = 0
var repaths: int = 0
var work_usec: int = 0
var prepare_usec: int = 0
var resolve_usec: int = 0
var collect_usec: int = 0
var damage_usec: int = 0
var slices: int = 0
var melee_candidates: int = 0
var melee_tests: int = 0
var scan := Scan.new()
var previous: Array[PackedVector2Array] = []
var projectile_segments: Array[Dictionary] = []
var action_segments: Array[Dictionary] = []
var reaction_segments: Array[Dictionary] = []
var _settling: bool = false
var _frozen_states: Dictionary = {}
var _interruptions: Dictionary = {}
var _brain_bucket: int = -1

func position(world: RefCounted, id: int) -> Vector2:
	if world.actor_slots.has(id):
		var slot: int = world.actor_slots[id]
		return world.pages[slot / 256].positions[slot % 256]
	return Terrain.center(int(world.objects.records.get(id, {}).get("tile", -1)))

func alive(world: RefCounted, id: int) -> bool:
	if not world.objects.records.has(id): return false
	if world.actor_slots.has(id):
		var slot: int = world.actor_slots[id]
		return world.pages[slot / 256].health[slot % 256] > 0
	return int(world.objects.records[id].get("hp", 0)) > 0

func profile(world: RefCounted, actor: int) -> Dictionary:
	var record: Dictionary = world.objects.records[actor]
	var key: String = str(record.get("equipment", {}).get("weapon", ""))
	var item: Dictionary = Items.spec(key) if not key.is_empty() else {}
	var id: String = str(record.get("ability_loadout", ""))
	if id.is_empty(): id = str(item.get("ai_loadout" if record.get("combat_style", "") == "trained" else "combat_loadout", "light" if record.get("combat_style", "") == "trained" else "sword"))
	return Defs.LOADOUTS[id]

func ability(world: RefCounted, actor: int, button: String, now: int) -> String:
	var base: String = profile(world, actor)[button]
	var chain: Dictionary = chains.get(actor, {})
	return str(chain.next) if button == "primary" and chain.get("root") == base and now <= int(chain.get("until", -1)) else base

func ranged(world: RefCounted, actor: int) -> bool:
	return Defs.ACTIONS[profile(world, actor).primary].stat == "ranged"

func eligible(world: RefCounted, source: int, target: int, policy: String, source_side: int) -> bool:
	if not alive(world, target): return false
	if policy == "self": return source == target
	if target == source: return false
	return policy == "physical" or int(world.objects.records[target].get("side", 0)) != source_side

func receivers(world: RefCounted, low: Vector2, high: Vector2, actor: int, policy: String, side: int) -> Array[int]:
	var found: Array[int] = []
	for target: int in world.objects.nearby((low + high) * 0.5, low.distance_to(high) * 0.5 + 1.0):
		var rec: Dictionary = world.objects.records[target]
		if not rec.get("combat_receiver", false) or world.actor_slots.has(target) or not eligible(world, actor, target, policy, side): continue
		var point: Vector2 = position(world, target)
		if point.x >= low.x and point.x <= high.x and point.y >= low.y and point.y <= high.y: found.append(target)
	return found

func set_control(world: RefCounted, input: Dictionary) -> void:
	var actor: int = 1
	if not alive(world, actor): controls.erase(actor); return
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if not input.get("enabled", false):
		controls.erase(actor)
		intents.erase(actor)
		if page.modes[row] == Units.Mode.DIRECT and not states.has(actor): page.modes[row] = Units.Mode.IDLE
		page.direct_velocities[row] = Vector2.ZERO
		return
	var movement: Vector2 = input.get("move", Vector2.ZERO)
	var aim: Vector2 = input.get("aim", page.aims[row])
	if not movement.is_finite() or not aim.is_finite(): return
	movement = movement.limit_length(1.0)
	if aim.length_squared() > 0.000001: page.aims[row] = aim.normalized()
	if movement.is_zero_approx() and not bool(input.get("primary", false)):
		controls.erase(actor)
		if page.modes[row] == Units.Mode.DIRECT and not states.has(actor): page.modes[row] = Units.Mode.IDLE
		page.direct_velocities[row] = Vector2.ZERO
		return
	if not movement.is_zero_approx() and not states.has(actor) and world.gate.check(world, actor, world.elapsed_ms).is_empty() and (world.gate.bindings.has(actor) or not controls.has(actor)):
		world.release(actor)
	controls[actor] = {"move": movement, "primary": bool(input.get("primary", false)), "point": input.get("point", Vector2(-1, -1))}
	if movement.is_zero_approx() and not states.has(actor) and page.modes[row] == Units.Mode.DIRECT:
		page.direct_velocities[row] = Vector2.ZERO
		page.modes[row] = Units.Mode.IDLE
	if not movement.is_zero_approx() and (states.has(actor) or world.gate.check(world, actor, world.elapsed_ms).is_empty()):
		world.objects.records[actor].autonomous = false
		page.routes[row] = PackedVector2Array()
		page.modes[row] = Units.Mode.DIRECT

func _priority(button: String) -> int:
	return {"primary": 1, "skill": 2, "skill2": 2, "skill3": 2, "step": 3}.get(button, 0)

func _buffer(actor: int, button: String, aim: Vector2, movement: Vector2, now: int, boundary: int, cooldown_boundary: int = -1, cd_key: String = "", point: Vector2 = Vector2(-1, -1), target_id: int = 0) -> String:
	var span: int = Defs.STEP_BUFFER_MS if button == "step" else Defs.BUFFER_MS
	if boundary - now > span: return "action_committed"
	if int(cooldowns.get(actor, {}).get(cd_key, 0)) > (boundary if cooldown_boundary < 0 else cooldown_boundary): return "cooldown"
	var old: Dictionary = intents.get(actor, {})
	if old.is_empty() or now > int(old.until) or _priority(button) >= _priority(old.button):
		intents[actor] = {"button": button, "aim": aim, "move": movement, "at": now, "until": now + span, "point": point, "target_id": target_id}
	return "buffered"

func request(world: RefCounted, actor: int, button: String, aim: Vector2, movement: Vector2 = Vector2.ZERO, at: int = -1, point: Vector2 = Vector2(-1, -1), target_id: int = 0, template: String = "", lineage: Dictionary = {}) -> String:
	var now: int = world.elapsed_ms if at < 0 else at
	if not world.actor_slots.has(actor) or not alive(world, actor) or not aim.is_finite() or not movement.is_finite(): return "invalid_action"
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if aim.length_squared() < 0.000001: aim = page.aims[row]
	aim = aim.normalized()
	movement = movement.limit_length(1.0)
	if button not in ["primary", "skill", "skill2", "skill3", "step"]: return "invalid_action"
	if button == "step" and world.effects.has_kind(actor, "root", now): return "rooted"
	var kind: String = ability(world, actor, button, now) if template.is_empty() else template
	if not Defs.ACTIONS.has(kind): return "invalid_action"
	var def: Dictionary = Defs.ACTIONS[kind]
	var cd_key: String = def.cd_group
	var stun_end: int = int(status.get(actor, {}).get("stun_until", 0))
	if now < stun_end:
		return _buffer(actor, button, aim, movement, now, stun_end, -1, cd_key, point, target_id) if button == "step" and stun_end - now <= Defs.STEP_BUFFER_MS else "stunned"
	var pending: Dictionary = intents.get(actor, {})
	if not pending.is_empty() and now <= int(pending.until) and _priority(button) < _priority(pending.button): return "buffered"
	if states.has(actor):
		var current: Dictionary = states[actor]
		var cancel_at: int = Defs.cancel_ms(current, button)
		if now < cancel_at:
			# A real contact may open an earlier cancel before this intent expires.
			var earliest: int = cancel_at
			if not current.confirmed and now < Defs.recovery_ms(current):
				var confirmed: Dictionary = current.merged({"confirmed": true}, true)
				earliest = maxi(now, maxi(Defs.active_ms(current), Defs.cancel_ms(confirmed, button)))
			var span: int = Defs.STEP_BUFFER_MS if button == "step" else Defs.BUFFER_MS
			return _buffer(actor, button, aim, movement, now, earliest, maxi(earliest, mini(cancel_at, now + span)), cd_key, point, target_id)
	var due: Dictionary = cooldowns.get(actor, {})
	if now < int(due.get(cd_key, 0)): return "cooldown"
	var delivery: Dictionary = def.delivery
	if delivery.kind in ["evade", "blink"] and world.effects.has_kind(actor, "root", now): return "rooted"
	if delivery.kind == "entity":
		var reason: String = world.entities.readiness(actor, kind)
		if not reason.is_empty(): return reason
	var origin: Vector2 = position(world, actor)
	if delivery.target == "object":
		var reason: String = direct_check(world, actor, target_id, def, now)
		if not reason.is_empty(): return reason
		point = position(world, target_id)
	elif delivery.target == "self": point = origin; target_id = actor
	elif delivery.target == "point":
		if not _point_valid(point) or point.x < 0: return "invalid_target"
		point = origin + (point - origin).limit_length(float(delivery.range))
		var tile: int = Terrain.index(Vector2i(point)) if _point_valid(point) else -1
		if tile < 0 or world.terrain.blocked[tile] != 0 or (delivery.walls and Terrain.blocking_fraction(world.terrain.blocked, origin, point) >= 0): return "target_blocked"
		world.sight.sync(world)
		if not world.sight.sees(origin, tile, world.sight.range_for(world, actor)): return "target_not_visible"
	else: point = origin + aim * float(delivery.range)
	if delivery.kind == "blink" and not world.terrain.can_stand(point, page.radii[row], page.flight[row] > 0): return "target_blocked"
	if delivery.kind == "entity" and not world.terrain.can_stand(point, 0.35, false): return "target_blocked"
	if delivery.kind == "area" and (not _point_valid(point) or point.x < 0 or world.terrain.blocked[Terrain.index(Vector2i(point))] != 0): return "target_blocked"
	if delivery.kind == "implement":
		var reason: String = world.implements.readiness(actor, kind)
		if not reason.is_empty(): return reason
	var costs: Array = Costs.from_action(def)
	var cost_reason: String = Costs.check(world, actor, costs)
	if not cost_reason.is_empty(): return cost_reason
	var admission: String = world.gate.check(world, actor, now, button)
	if not admission.is_empty(): return admission
	world.end_run(actor, now)
	world.clear_navigation(actor)
	if not world.gate.check(world, actor, now, button).is_empty(): return "action_committed"
	if not Costs.pay(world, actor, costs): return "insufficient_resource"
	if actor == 1: world.objects.records[actor].autonomous = false
	page.routes[row] = PackedVector2Array()
	page.route_cursors[row] = 0
	page.targets[row] = page.positions[row]
	page.modes[row] = Units.Mode.DIRECT
	page.aims[row] = aim
	var direction: Vector2 = movement.normalized() if Defs.is_evade(kind) and not movement.is_zero_approx() else (-aim if Defs.is_evade(kind) else aim)
	states[actor] = {"kind": kind, "started_ms": now, "direction": direction, "aim": aim,
		"point": point, "target_id": target_id, "activation": next_activation, "hit": {}, "fired": false, "confirmed": false,
		"step_speed": float(delivery.speed if not movement.is_zero_approx() else delivery.backward_speed),
		"damage": roundi((page.ranged_damage[row] if def.stat == "ranged" else page.melee_damage[row]) * float(Payload.summary(def.payload).damage))}
	states[actor]["lineage"] = world.reactions.root(actor, states[actor].activation) if lineage.is_empty() else lineage.duplicate(true)
	world.gate.bind(actor, "combat", states[actor].activation)
	intents.erase(actor)
	if status.has(actor): status[actor]["push_until"] = now # A legal new action owns its displacement.
	next_activation += 1
	if not str(def.next).is_empty():
		chains[actor] = {"next": def.next, "root": profile(world, actor).primary, "until": Defs.end_ms(states[actor]) + int(def.chain_ms)}
	else: chains.erase(actor)
	if int(def.post) > 0:
		var value: Dictionary = _status(actor)
		value.ready_ms = Defs.end_ms(states[actor]) + int(def.post)
		value.recovery_from = Defs.recovery_ms(states[actor])
		value.recovery_until = Defs.end_ms(states[actor])
		value.punishable = def.punishable
		value.punished = false
		status[actor] = value
	elif status.has(actor):
		# A legally accepted replacement owns its recovery, including zero post.
		status[actor].merge({"ready_ms": mini(int(status[actor].get("ready_ms", 0)), now), "recovery_from": 0, "recovery_until": 0, "punishable": false, "punished": false}, true)
	if int(def.cooldown) > 0:
		due[cd_key] = now + int(def.cooldown)
		cooldowns[actor] = due
	world.emit({"kind": "action_started", "actor": actor, "action": kind, "activation": states[actor].activation, "at_ms": now, "position": position(world, actor)})
	return "started"

func next_boundary(now: int, end: int) -> int:
	var result: int = end
	for state: Dictionary in states.values():
		var def: Dictionary = Defs.ACTIONS[state.kind]
		var offsets: Array = [def.get("lock", 0), def.get("lunge_from", 0), def.get("lunge_to", 0), def.get("free_at", 0), def.evade_ms]
		for button: String in ["primary", "skill", "step"]: offsets.append(Defs.cancel_ms(state, button) - int(state.started_ms))
		for offset: int in offsets:
			var boundary: int = int(state.started_ms) + offset
			if boundary > now: result = mini(result, boundary)
		for boundary: int in [Defs.active_ms(state), Defs.recovery_ms(state), Defs.end_ms(state)]:
			if boundary > now: result = mini(result, boundary)
	for value: Dictionary in status.values():
		for key: String in ["stun_until", "push_until", "ready_ms"]:
			var boundary: int = int(value.get(key, 0))
			if boundary > now: result = mini(result, boundary)
	for intent: Dictionary in intents.values():
		for boundary: int in [int(intent.until), int(intent.until) + 1]:
			if boundary > now: result = mini(result, boundary)
	for bolt: Dictionary in bolts.values():
		if int(bolt.expire_ms) > now: result = mini(result, int(bolt.expire_ms))
		for rule: Dictionary in bolt.rules:
			var at: int = int(bolt.born_ms) + int(rule.delay_ms)
			if rule.event == "timer" and not bolt.timers.has(rule.id) and at > now: result = mini(result, at)
		if float(bolt.get("turn", 0)) > 0 and int(bolt.next_steer) > now: result = mini(result, int(bolt.next_steer))
	return result

func prepare(world: RefCounted, now: int) -> void:
	var started: int = Time.get_ticks_usec()
	Projectiles.steer(self, world, now)
	for actor: int in states.keys():
		var state: Dictionary = states[actor]
		if now >= Defs.end_ms(state):
			world.end_run(actor, now, "completed")
			var slot: int = world.actor_slots[actor]
			world.pages[slot / 256].modes[slot % 256] = Units.Mode.IDLE
			continue
		if not state.fired and now >= Defs.active_ms(state):
			state.fired = true
			_deliver(world, actor, state, now)
			world.emit({"kind": "action_active", "actor": actor, "action": state.kind, "activation": state.activation, "at_ms": now, "position": position(world, actor)})
	for actor: int in intents.keys():
		var intent: Dictionary = intents[actor]
		if now > int(intent.until) or not alive(world, actor): intents.erase(actor); continue
		if now < int(status.get(actor, {}).get("stun_until", 0)): continue
		if states.has(actor) and now < Defs.cancel_ms(states[actor], intent.button): continue
		intents.erase(actor)
		request(world, actor, intent.button, intent.aim, intent.move, now, intent.get("point", Vector2(-1, -1)), int(intent.get("target_id", 0)))
	if _brain_bucket != now / 50:
		_brain_bucket = now / 50
		_think(world, now)
	for actor: int in controls:
		if bool(controls[actor].primary) and bool(Defs.ACTIONS[profile(world, actor).primary].repeat) and not states.has(actor):
			request(world, actor, "primary", world.pages[world.actor_slots[actor] / 256].aims[world.actor_slots[actor] % 256], Vector2.ZERO, now, controls[actor].point)
	var bodies: Dictionary = {}
	for actor: int in states: bodies[actor] = true
	for actor: int in controls:
		if not Vector2(controls[actor].move).is_zero_approx(): bodies[actor] = true
	for actor: int in status: bodies[actor] = true
	for actor: int in bodies:
		if not alive(world, actor): continue
		var slot: int = world.actor_slots[actor]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		var state: Dictionary = states.get(actor, {})
		var value: Dictionary = status.get(actor, {})
		var movement: Vector2 = controls.get(actor, {}).get("move", Vector2.ZERO)
		var velocity: Vector2 = movement * page.move_speed[row] * page.move_scales[row]
		if not state.is_empty():
			var def: Dictionary = Defs.ACTIONS[state.kind]
			var age: int = now - int(state.started_ms)
			velocity *= float(def.get("free_move", def.move)) if age >= int(def.get("free_at", 100000)) else float(def.move)
			if def.has("lunge") and age >= int(def.lunge_from) and age < int(def.lunge_to):
				velocity += _lunge(world, actor, state, float(def.lunge) * 1000.0 / (int(def.lunge_to) - int(def.lunge_from)))
			if Defs.is_evade(state.kind) and now < Defs.recovery_ms(state): velocity = state.direction * float(state.step_speed)
		if now < int(value.get("stun_until", 0)) or world.effects.has_kind(actor, "root", now):
			velocity = Vector2.ZERO
		if now < int(value.get("push_until", 0)): velocity += Vector2(value.get("push", Vector2.ZERO))
		elif value.has("stun_until") and state.is_empty() and movement.is_zero_approx():
			if page.modes[row] == Units.Mode.DIRECT: page.modes[row] = Units.Mode.IDLE
		if not state.is_empty() or (controls.has(actor) and not movement.is_zero_approx()) or now < int(value.get("stun_until", 0)) or now < int(value.get("push_until", 0)):
			page.modes[row] = Units.Mode.DIRECT
			page.direct_velocities[row] = velocity
	var cost: int = Time.get_ticks_usec() - started
	prepare_usec += cost
	work_usec += cost

func _status(actor: int) -> Dictionary:
	return status.get(actor, {"groups": {}, "stun_window": 0, "stun_used": 0})

func _cooldown_group(key: String) -> bool:
	for def: Dictionary in Defs.ACTIONS.values():
		if def.cd_group == key: return true
	return false

func _deliver(world: RefCounted, actor: int, state: Dictionary, now: int) -> void:
	var def: Dictionary = Defs.ACTIONS[state.kind]
	var delivery: Dictionary = def.delivery
	var origin: Vector2 = state.get("origin", position(world, actor))
	var side: int = int(world.objects.records.get(actor, {}).get("side", 0))
	match delivery.kind:
		"projectile":
			if Vector2(state.direction).is_zero_approx(): return
			for index: int in int(delivery.count):
				var direction: Vector2 = state.direction.rotated((index - (int(delivery.count) - 1) * 0.5) * float(delivery.spread))
				launch(actor, origin, origin + direction, now, state.damage, state.activation, float(delivery.speed))
				var bolt: Dictionary = bolts[next_bolt - 1]
				bolt.merge({"lineage": state.get("lineage", {}), "rules": def.reactions, "timers": {}, "ability": state.kind, "payload": def.payload, "group_ms": int(def.group_ms), "radius": float(delivery.radius), "expire_ms": now + int(delivery.life), "side": side,
					"filter": delivery.filter, "turn": float(delivery.turn), "target": 0, "pierce": int(delivery.pierce), "walls": delivery.walls, "steered_ms": now, "next_steer": now + 50}, true)
				# A mid-segment child cannot use the already integrated endpoint
				# as its birth-time knowledge. Its first future steer can acquire.
				if float(delivery.turn) > 0 and now >= world._motion_end: Projectiles.acquire(self, world, bolt)
		"blink":
			var slot: int = world.actor_slots[actor]
			var page: RefCounted = world.pages[slot / 256]
			world.sight.sync(world)
			var tile: int = Terrain.index(Vector2i(state.point))
			if not world.effects.has_kind(actor, "root", now) and origin.distance_to(state.point) <= float(delivery.range) + 0.001 and (not delivery.walls or Terrain.blocking_fraction(world.terrain.blocked, origin, state.point) < 0) and world.sight.sees(origin, tile, world.sight.range_for(world, actor)) and world.terrain.can_stand(state.point, page.radii[slot % 256], page.flight[slot % 256] > 0):
				page.positions[slot % 256] = state.point
				world.emit({"kind": "blink", "actor": actor, "from": origin, "position": state.point, "at_ms": now})
				world.effects.apply_bundle(world, actor, actor, state.activation, state.kind, def.payload, now, 0, "activation", state.get("lineage", {}))
		"entity": world.entities.create(world, actor, state, now)
		"direct":
			if direct_check(world, actor, int(state.target_id), def, now).is_empty(): world.effects.apply_bundle(world, state.target_id, actor, state.activation, state.kind, def.payload, now, state.damage, "activation", state.get("lineage", {}))
		"area": world.areas.create(actor, state, now, side)
		"implement": world.implements.dispatch(world, actor, state, now)
		"recall": world.implements.recall(world, actor)

func direct_check(world: RefCounted, actor: int, target: int, definition: Dictionary, _now: int) -> String:
	if not world.objects.records.has(target) or not alive(world, target): return "invalid_target"
	var has_domain: bool = definition.payload.any(func(effect: Dictionary): return effect.kind == "domain")
	if definition.delivery.target == "object" and not has_domain and not eligible(world, actor, target, definition.delivery.filter, int(world.objects.records[actor].get("side", 0))): return "invalid_target"
	var origin: Vector2 = world.position_at(actor)
	var point: Vector2 = world.position_at(target)
	if origin.distance_to(point) > float(definition.delivery.range): return "out_of_reach"
	world.sight.sync(world)
	if target != actor and not world.sight.sees_object(origin, world.objects.records[target], world.sight.range_for(world, actor)): return "target_not_visible"
	if definition.delivery.walls and Terrain.blocking_fraction(world.terrain.blocked, origin, point) >= 0: return "target_blocked"
	for effect: Dictionary in definition.payload:
		if effect.kind != "domain": continue
		var reason: String = world.DomainOps.check(world, actor, target, effect.operation)
		if not reason.is_empty(): return reason
	return ""

func request_template(world: RefCounted, actor: int, template: String, direction: Vector2, at: int, point: Vector2, target: int = 0, lineage: Dictionary = {}) -> String:
	var reason: String = world.gate.check(world, actor, at, "skill")
	if not reason.is_empty(): return reason
	if intents.has(actor): return "intent_pending"
	return request(world, actor, "skill", direction, Vector2.ZERO, at, point, target, template, lineage)

func spawn_template(world: RefCounted, actor: int, template: String, origin: Vector2, direction: Vector2, at: int, scale: float, lineage: Dictionary, exclude: int = 0, activation: int = 0) -> Array:
	if not Defs.ACTIONS.has(template) or not direction.is_finite() or direction.is_zero_approx(): return []
	direction = direction.normalized()
	var definition: Dictionary = Defs.ACTIONS[template]
	var amount: int = 20
	if world.actor_slots.has(actor):
		var slot: int = world.actor_slots[actor]
		amount = world.pages[slot / 256].ranged_damage[slot % 256] if definition.stat == "ranged" else world.pages[slot / 256].melee_damage[slot % 256]
	var first: int = next_bolt
	if activation == 0:
		activation = next_activation
		next_activation += 1
	var state: Dictionary = {"kind": template, "origin": origin, "point": origin, "target_id": exclude, "direction": direction, "aim": direction, "activation": activation, "damage": roundi(amount * float(Payload.summary(definition.payload).damage) * scale), "lineage": lineage}
	_deliver(world, actor, state, at)
	var ids: Array = []
	for id: int in range(first, next_bolt):
		ids.append(id)
		if exclude > 0: bolts[id].passed[exclude] = true
	return ids

func _lunge(world: RefCounted, actor: int, state: Dictionary, speed: float) -> Vector2:
	var origin: Vector2 = position(world, actor)
	var slot: int = world.actor_slots[actor]
	var radius: float = world.pages[slot / 256].radii[slot % 256]
	# Only stop the automatic addition at nearby bodies; never steer toward one.
	for target: int in scan.nearby(origin - Vector2.ONE * 2.0, origin + Vector2.ONE * 2.0):
		if target == actor or not alive(world, target): continue
		var other: int = world.actor_slots[target]
		var delta: Vector2 = position(world, target) - origin
		var clearance: float = radius + world.pages[other / 256].radii[other % 256] + 0.12
		if delta.dot(state.direction) > 0 and delta.length() < clearance: return Vector2.ZERO
	return state.direction * speed

func before_motion(world: RefCounted) -> void:
	previous.clear()
	if bolts.is_empty() and states.is_empty() and world.implements.records.is_empty() and world.actions.is_empty() and world.work_runs.is_empty() and world.areas.records.is_empty() and world.effects.records.is_empty() and world.reactions.pending.is_empty(): return
	for page: RefCounted in world.pages: previous.append(page.positions.duplicate())

func step(world: RefCounted, start: int, now: int, world_events: Array[Dictionary] = []) -> void:
	var started: int = Time.get_ticks_usec()
	slices += 1
	var actions: Dictionary = view()
	for actor: int in actions:
		var segment: Dictionary = actions[actor]
		segment.merge({"actor": actor, "from_ms": start, "until_ms": now})
		action_segments.append(segment)
	var melee: Array[int] = []
	for actor: int in states:
		var state: Dictionary = states[actor]
		if start >= Defs.active_ms(state) and start < Defs.recovery_ms(state) and Defs.ACTIONS[state.kind].has("reach"): melee.append(actor)
	var direct_activations: Array[Dictionary] = []
	for actor: int in states:
		var state: Dictionary = states[actor]
		if not state.fired and Defs.ACTIONS[state.kind].delivery.kind == "direct" and Defs.active_ms(state) >= start and Defs.active_ms(state) <= now:
			direct_activations.append({"event": "direct_activation", "actor": actor, "activation": state.activation, "at_ms": Defs.active_ms(state)})
	if world.reactions.pending.is_empty() and direct_activations.is_empty() and world_events.is_empty() and bolts.is_empty() and melee.is_empty() and world.areas.records.is_empty() and world.effects.records.is_empty() and world.implements.records.is_empty():
		_record_reactions(start, now)
		return
	scan.index(world)
	var impacts: Array[Dictionary] = world_events.duplicate()
	world.areas.queued.clear()
	impacts.append_array(direct_activations)
	if not world.reactions.pending.is_empty(): impacts.append({"event": "reaction_flush", "actor": 0, "at_ms": maxi(start, int(world.reactions.pending[0].at_ms))})
	impacts.append_array(world.areas.collect(world, now))
	impacts.append_array(world.implements.collect(world, start, now, melee))
	impacts.append_array(Projectiles.collect(self, world, start, now))
	for actor: int in melee:
		var state: Dictionary = states[actor]
		var def: Dictionary = Defs.ACTIONS[state.kind].merged(Payload.summary(Defs.ACTIONS[state.kind].payload), true)
		var origin: Vector2 = position(world, actor)
		var own_slot: int = world.actor_slots[actor]
		var before_origin: Vector2 = previous[own_slot / 256][own_slot % 256]
		var own_knots: PackedVector3Array = world.pages[own_slot / 256].motion.get(own_slot % 256, PackedVector3Array())
		var polygon: PackedVector2Array = Defs.sector(def, state.direction)
		var reach: float = float(def.reach) + 1.0 + scan.sweep_padding
		for target: int in scan.nearby(origin - Vector2.ONE * reach, origin + Vector2.ONE * reach):
			if not eligible(world, actor, target, def.delivery.filter, int(world.objects.records[actor].get("side", 0))) or state.hit.has(target): continue
			melee_candidates += 1
			var slot: int = world.actor_slots[target]
			var page: RefCounted = world.pages[slot / 256]
			var row: int = slot % 256
			# Bucket cells are coarser than a sword arc. Reject far bodies before
			# constructing relative paths, retaining both bodies' swept distance.
			var limit: float = float(def.reach) + page.radii[row] + scan.sweep_padding * 2.0
			if origin.distance_squared_to(page.positions[row]) > limit * limit: continue
			melee_tests += 1
			var before: Vector2 = previous[slot / 256][row]
			var knots: PackedVector3Array = page.motion.get(row, PackedVector3Array())
			var fraction: float = Motion.shape_hit(before_origin, origin, own_knots, before, page.positions[row], knots, polygon, page.radii[row])
			if fraction < 0: continue
			var contact: Vector2 = Motion.at(before, page.positions[row], knots, fraction)
			var source: Vector2 = Motion.at(before_origin, origin, own_knots, fraction)
			if Terrain.blocking_fraction(world.terrain.blocked, source, contact) >= 0: continue
			impacts.append({"actor": actor, "target": target, "damage": state.damage, "activation": state.activation,
				"at_ms": start + roundi((now - start) * fraction), "incoming": (source - contact).normalized(), "stun": def.stun, "push": def.push, "melee": true,
				"action": state.kind, "position": contact, "heavy_hit": def.heavy_hit, "punish_ms": def.punish_ms, "rules": def.reactions, "lineage": state.get("lineage", {}), "payload": def.payload, "evadable": true, "group_ms": def.group_ms})
	for actor: int in melee:
		var state: Dictionary = states[actor]
		var definition: Dictionary = Defs.ACTIONS[state.kind]
		var source: Vector2 = position(world, actor)
		var radius: float = float(definition.reach) + 0.5
		var slot: int = world.actor_slots[actor]
		for target: int in receivers(world, source - Vector2.ONE * radius, source + Vector2.ONE * radius, actor, definition.delivery.filter, int(world.objects.records[actor].get("side", 0))):
			if state.hit.has(target): continue
			var point: Vector2 = position(world, target)
			var fraction: float = Motion.shape_hit(previous[slot / 256][slot % 256], source, world.pages[slot / 256].motion.get(slot % 256, PackedVector3Array()), point, point, PackedVector3Array(), Defs.sector(definition, state.direction), 0.4)
			if fraction < 0 or Terrain.blocking_fraction(world.terrain.blocked, source, point) >= 0: continue
			var summary: Dictionary = Payload.summary(definition.payload)
			impacts.append({"actor": actor, "target": target, "damage": state.damage, "activation": state.activation, "at_ms": start + roundi((now - start) * fraction), "incoming": (source - point).normalized(),
				"stun": summary.stun, "push": summary.push, "melee": true, "action": state.kind, "position": point, "payload": definition.payload, "rules": definition.reactions, "lineage": state.lineage, "group_ms": definition.group_ms})
	impacts.sort_custom(_impact_before)
	var collected: int = Time.get_ticks_usec()
	collect_usec += collected - started
	var index: int = 0
	var periodic_collected: bool = false
	while index < impacts.size() or not periodic_collected:
		# A contact before this endpoint can renew an effect whose last tick was
		# formerly excluded. Collect endpoint ticks after those earlier contacts,
		# then let them trade with the other equal-time impacts.
		if not periodic_collected and (index >= impacts.size() or int(impacts[index].at_ms) >= now):
			var endpoint: Array[Dictionary] = impacts.slice(index)
			endpoint.append_array(world.effects.collect(world, now))
			endpoint.sort_custom(_impact_before)
			impacts.resize(index)
			impacts.append_array(endpoint)
			periodic_collected = true
			if index >= impacts.size(): break
		var end: int = index + 1
		while end < impacts.size() and impacts[end].at_ms == impacts[index].at_ms: end += 1
		var accepted: Array[Dictionary] = []
		var work: Array[Dictionary] = []
		var directs: Array[Dictionary] = []
		var deliveries: Array[Dictionary] = []
		for entry: int in range(index, end):
			var impact: Dictionary = impacts[entry]
			if impact.get("event") == "reaction_flush": continue
			if impact.get("event") == "projectile_reaction": deliveries.append(impact); continue
			if impact.get("event") == "direct_activation": directs.append(impact); continue
			if impact.get("event") == "area_pulse":
				accepted.append_array(world.areas.pulse(world, impact.area_id, impact.at_ms))
				continue
			if impact.has("event"): work.append(impact); continue
			if not impact.get("melee", false) or (alive(world, impact.actor) and states.get(impact.actor, {}).get("activation") == impact.activation): accepted.append(impact)
		world._commit_ms = int(impacts[index].at_ms)
		world.effects.expire(world, int(impacts[index].at_ms))
		var snapshot: Array[Dictionary] = accepted.duplicate()
		for event: Dictionary in directs:
			snapshot.append({"actor": event.actor, "target": states.get(event.actor, {}).get("target_id", event.actor)})
		_begin_wave(snapshot)
		# Equal-time contacts trade; an earlier death/stagger cancels later melee.
		world._commit_ms = int(impacts[index].at_ms)
		for event: Dictionary in directs:
			var state: Dictionary = states.get(event.actor, {})
			if state.get("activation") != event.activation or not alive(world, event.actor): continue
			state.fired = true
			_deliver(world, event.actor, state, event.at_ms)
			world.emit({"kind": "action_active", "actor": event.actor, "action": state.kind, "activation": state.activation, "at_ms": event.at_ms, "position": world.position_at(event.actor)})
		for impact: Dictionary in accepted:
			if impact.get("bolt_id", 0) > 0 and not Projectiles.accept(self, world, impact): continue
			if impact.get("bolt_wall", false) and impact.target == 0: continue
			if impact.get("source_implement", 0) > 0:
				var implement: Dictionary = world.implements.records[impact.source_implement]
				if impact.at_ms > int(implement.get("stopped_ms", 9223372036854775807)): continue
			if impact.get("implement_target", 0) > 0:
				if not world.implements.active_at(impact.implement_target, impact.at_ms): continue
				world.implements.hit(world, impact.implement_target, impact.damage, impact.at_ms)
				if impact.get("melee", false) and states.get(impact.actor, {}).get("activation") == impact.activation:
					states[impact.actor].hit["implement:%d" % impact.implement_target] = true
					states[impact.actor].confirmed = true
				continue
			var result: Dictionary = damage(world, impact.actor, impact.target, impact.damage, impact.at_ms, impact.incoming, impact.activation, impact.stun, impact.push, impact)
			if result.get("contact", false) and not impact.get("payload", []).is_empty():
				world.effects.apply_bundle(world, impact.target, impact.actor, impact.activation, impact.get("action", ""), impact.payload, impact.at_ms, impact.damage, "contact", impact.get("lineage", {}), bool(result.get("guarded", false)))
			world.reactions.damage_result(world, result, impact)
			if impact.get("melee", false) and states.get(impact.actor, {}).get("activation") == impact.activation:
				states[impact.actor].hit[impact.target] = true
				if result.get("damage", 0) > 0: states[impact.actor].confirmed = true
		_close_wave(world)
		for event: Dictionary in deliveries:
			if not bolts.has(event.bolt_id): continue
			var bolt: Dictionary = bolts[event.bolt_id]
			if bolt.timers.has(event.rule.id): continue
			bolt.timers[event.rule.id] = true
			event.event = event.rule.event
			var one_rule: Array = [event.rule]
			world.reactions.submit(world, event, one_rule)
		var appended: bool = false
		for event: Dictionary in work:
			var successors: Array[Dictionary] = world.commit_work_event(event, now)
			if not successors.is_empty(): impacts.append_array(successors); appended = true
		world._commit_ms = int(impacts[index].at_ms)
		var derived: Array[Dictionary] = world.reactions.resolve(world, start, now)
		world._commit_ms = -1
		if not derived.is_empty(): impacts.append_array(derived); appended = true
		if appended:
			var tail: Array[Dictionary] = impacts.slice(end)
			tail.sort_custom(_impact_before)
			impacts.resize(end)
			impacts.append_array(tail)
		index = end
	Projectiles.finish(self, now)
	_record_reactions(start, now)
	damage_usec += Time.get_ticks_usec() - collected
	var cost: int = Time.get_ticks_usec() - started
	resolve_usec += cost
	work_usec += cost

func _impact_before(a: Dictionary, b: Dictionary) -> bool:
	for key: String in ["at_ms", "actor", "bolt_id", "contact_order", "implement_target", "target"]:
		if int(a.get(key, 0)) != int(b.get(key, 0)): return int(a.get(key, 0)) < int(b.get(key, 0))
	return false

func _record_reactions(start: int, now: int) -> void:
	for actor: int in status:
		var value: Dictionary = status[actor]
		if int(value.get("stun_until", 0)) > start:
			reaction_segments.append({"actor": actor, "from_ms": start, "until_ms": now, "stun_from": value.get("stun_from", 0), "stun_until": value.stun_until})

func _cut_action(actor: int, at: int) -> void:
	for segment: Dictionary in action_segments:
		if segment.actor == actor and int(segment.until_ms) > at: segment.until_ms = maxi(int(segment.from_ms), at)

func launch(actor: int, origin: Vector2, destination: Vector2, now: int, amount: int = 20, activation: int = 0, speed: float = 22.0) -> void:
	if origin.is_equal_approx(destination): return
	bolts[next_bolt] = {"actor": actor, "position": origin, "velocity": origin.direction_to(destination) * speed,
		"lineage": {}, "rules": [], "timers": {}, "ability": "", "payload": [], "group_ms": 280, "side": -1, "filter": "physical", "turn": 0.0, "target": 0, "pierce": 0, "walls": true, "steered_ms": now, "next_steer": now + 50, "damage": amount, "radius": 0.10, "born_ms": now, "expire_ms": now + 2000, "activation": activation if activation > 0 else -next_bolt, "passed": {}}
	next_bolt += 1
	shots += 1

func damage(world: RefCounted, actor: int, target: int, amount: int, now: int, incoming: Vector2 = Vector2.ZERO, activation: int = 0, stun_ms: int = 0, push: float = 0.0, context: Dictionary = {}) -> Dictionary:
	if not alive(world, target): return {}
	if context.get("evadable", false) and Defs.evading(action_snapshot(target), now):
		world.emit({"kind": "evaded", "actor": actor, "target": target, "activation": activation, "at_ms": now, "position": context.get("position", position(world, target))})
		return {"evaded": true}
	var applied: int
	var duration: int = 0
	var armored: bool = false
	var off_balance: bool = false
	var rec: Dictionary = world.objects.records[target]
	if world.actor_slots.has(target):
		world.ensure_work_binding(target)
		var value: Dictionary = _status(target)
		var group: String = "%d:%d" % [actor, activation]
		var group_ms: int = int(context.get("group_ms", 280))
		if activation != 0 and group_ms > 0 and now < int(value.groups.get(group, 0)): return {}
		for key: String in value.groups.keys():
			if now >= int(value.groups[key]): value.groups.erase(key)
		if activation != 0 and group_ms > 0: value.groups[group] = now + group_ms
		if not context.get("status_control", false): value.last_damage_ms = now
		var slot: int = world.actor_slots[target]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		var defense: Dictionary = world.defense.absorb(world, target, maxi(1, amount - page.armor[row]) if amount > 0 else 0, incoming, now)
		context["blocked"] = defense.blocked
		context["absorbed"] = defense.absorbed
		context["broken"] = defense.broken
		context["guarded"] = defense.guarded
		if defense.guarded: stun_ms = 0; push = 0.0
		applied = mini(page.health[row], int(defense.remaining))
		page.health[row] -= applied
		var work_interrupted: bool = not context.get("periodic", false) and (world.actions.has(target) or world.work_runs.has(target) or world.society.waits.has(target))
		var target_state: Dictionary = action_snapshot(target)
		var steady: bool = not target_state.is_empty() and bool(Defs.ACTIONS[target_state.kind].get("steady", false)) and now < Defs.recovery_ms(target_state)
		if now >= int(value.stun_window) + Defs.CONTROL_WINDOW_MS or int(value.stun_used) == 0:
			value.stun_window = now
			value.stun_used = 0
		var remaining: int = Defs.CONTROL_BUDGET_MS - int(value.stun_used)
		armored = stun_ms > 0 and (steady or remaining < 40)
		if not armored and stun_ms > 0:
			var desired: int = stun_ms
			if value.get("punishable", false) and context.get("heavy_hit", false) and now >= int(value.get("recovery_from", 0)) and now < int(value.get("recovery_until", 0)) and not value.get("punished", false):
				desired = int(context.get("punish_ms", 260))
				value.punished = true
				off_balance = true
			var previous_end: int = maxi(now, int(value.get("stun_until", 0)))
			var addition: int = mini(maxi(0, now + desired - previous_end), remaining)
			value.stun_used += addition
			if remaining >= 40 and Defs.CONTROL_BUDGET_MS - int(value.stun_used) < 40: value.guard_from = now
			duration = maxi(0, previous_end + addition - now)
		if duration > 0:
			value.stun_from = now
			value.stun_until = now + duration
			if not context.get("status_control", false): value.hit_stun_until = maxi(int(value.get("hit_stun_until", 0)), now + duration)
			if push > 0 and not incoming.is_zero_approx():
				value.push_until = now + 120
				value.push = -incoming * minf(push, 1.0) / 0.120
			value.ready_ms = maxi(int(value.get("ready_ms", 0)), now + duration + 180)
		if not context.get("periodic", false) or duration > 0 or page.health[row] <= 0:
			var previous_request: Dictionary = _interruptions.get(target, {})
			_interruptions[target] = {"at_ms": now, "actor": actor, "incoming": incoming, "duration": maxi(duration, int(previous_request.get("duration", 0))), "work": work_interrupted or previous_request.get("work", false)}
		status[target] = value
		if not context.get("status_control", false):
			world.attacks += 1
			world.emit({"kind": "hit", "actor": actor, "target": target, "damage": applied, "at_ms": now, "position": context.get("position", page.positions[row]), "activation": activation,
				"blocked": context.get("blocked", 0), "absorbed": context.get("absorbed", 0), "action": context.get("action", ""), "incoming": incoming, "stun_ms": duration, "armored": armored, "off_balance": off_balance, "heavy_hit": context.get("heavy_hit", false)})
		if not _settling: _close_wave(world)

	else:
		applied = mini(int(rec.hp), maxi(1, amount - int(world.facilities.definitions.get(rec.definition, {}).get("armor", 0)))) if amount > 0 else 0
		rec.hp -= applied
		world.emit({"kind": "hit", "actor": actor, "target": target, "damage": applied, "at_ms": now})
		if rec.hp <= 0:
			if world.entities.records.has(target): world.entities.remove(world, target, now)
			else: world.facilities.demolish(world, target, now)
	if not context.get("status_control", false): hits += 1
	return {"kind": "damage", "contact": true, "actor": actor, "target": target, "at_ms": now, "activation": activation, "damage": applied, "guarded": context.get("guarded", false), "blocked": context.get("blocked", 0), "absorbed": context.get("absorbed", 0), "broken": context.get("broken", []), "fatal": not alive(world, target), "stun_ms": duration, "armored": armored, "off_balance": off_balance}

func action_snapshot(actor: int) -> Dictionary:
	return _frozen_states.get(actor, {}) if _settling else states.get(actor, {})

func _begin_wave(impacts: Array[Dictionary]) -> void:
	_settling = true
	_frozen_states.clear()
	for impact: Dictionary in impacts:
		for actor: int in [int(impact.get("actor", 0)), int(impact.get("target", 0))]:
			if not _frozen_states.has(actor): _frozen_states[actor] = states.get(actor, {}).duplicate(true)

func _close_wave(world: RefCounted) -> void:
	var pending: Dictionary = _interruptions
	_interruptions = {}
	for target: int in pending:
		if not world.actor_slots.has(target): continue
		var slot: int = world.actor_slots[target]
		var page: RefCounted = world.pages[slot / 256]
		var entry: Dictionary = pending[target]
		if page.health[slot % 256] <= 0:
			_cut_action(target, entry.at_ms)
			world.kill(target, entry.at_ms, "combat")
	for target: int in pending:
		if not alive(world, target): continue
		var slot: int = world.actor_slots[target]
		var page: RefCounted = world.pages[slot / 256]
		var entry: Dictionary = pending[target]
		if entry.work or entry.duration > 0:
			world.end_run(target, entry.at_ms, "interrupted")
			world.clear_navigation(target)
			intents.erase(target)
			chains.erase(target)
			page.modes[slot % 256] = Units.Mode.DIRECT if entry.duration > 0 else Units.Mode.IDLE
		if target != 1 and not engagements.has(target):
			world.sight.sync(world)
			if alive(world, entry.actor) and world.sight.observed_position(world, target, entry.actor) != null: engage(world, target, entry.actor, Vector2(-1, -1), ranged(world, target), entry.at_ms)
			elif not Vector2(entry.incoming).is_zero_approx():
				var goal: Vector2 = world.terrain.project_point(position(world, target) + Vector2(entry.incoming) * 6.0, page.radii[slot % 256], page.flight[slot % 256] > 0)
				if goal.x >= 0: engage(world, target, 0, goal, ranged(world, target), entry.at_ms)
	_settling = false
	_frozen_states.clear()

func heal(world: RefCounted, actor: int, target: int, amount: int, at: int) -> Dictionary:
	var actual: int = 0
	if alive(world, target) and world.actor_slots.has(target):
		var slot: int = world.actor_slots[target]
		var page: RefCounted = world.pages[slot / 256]
		actual = mini(maxi(0, amount), int(page.max_health[slot % 256]) - int(page.health[slot % 256]))
		page.health[slot % 256] += actual
	if actual > 0: world.emit({"kind": "healed", "actor": actor, "target": target, "amount": actual, "at_ms": at})
	return {"kind": "heal", "actor": actor, "target": target, "amount": actual, "at_ms": at}

func engage(world: RefCounted, actor: int, target: int = 0, destination: Vector2 = Vector2(-1, -1), use_bow: bool = false, at: int = -1) -> String:
	if not alive(world, actor) or (target > 0 and (target == actor or not alive(world, target))): return "invalid_target"
	world.sight.sync(world)
	var observed: Variant = world.sight.observed_position(world, actor, target) if target > 0 else null
	if target > 0 and observed == null: return "target_not_visible"
	var now: int = world.elapsed_ms if at < 0 else at
	var automatic: bool = world.objects.records[actor].get("autonomous", false)
	# Engagement changes preserve an already committed action and hit reaction.
	var state: Dictionary = states.get(actor, {})
	if state.is_empty(): world.end_run(actor, now)
	world.clear_navigation(actor)
	engagements[actor] = {"target": target, "destination": destination, "ranged": use_bow,
		"scan_ms": now + (actor % Scan.DISCOVERY_STEPS) * 50, "repath_ms": 0, "react_ms": now + 220,
		"resume": automatic, "last_goal": Vector2(-1, -1), "last_seen_pos": observed if observed != null else Vector2(-1, -1),
		"last_seen_ms": now if observed != null else -1, "search_tile": -1}
	var slot: int = world.actor_slots[actor]
	if state.is_empty(): world.pages[slot / 256].modes[slot % 256] = Units.Mode.IDLE
	return "accepted"

func finish(world: RefCounted, actor: int, now: int) -> void:
	var resume: bool = engagements.get(actor, {}).get("resume", false)
	engagements.erase(actor)
	if not world.actor_slots.has(actor): return
	var slot: int = world.actor_slots[actor]
	if not states.has(actor): world.pages[slot / 256].modes[slot % 256] = Units.Mode.IDLE
	if resume and alive(world, actor): resumed += 1; world.livelihood.after_action(world, actor, now)

func _think(world: RefCounted, now: int) -> void:
	world.sight.sync(world)
	scan.index(world)
	scan.observe(world, engagements, now, unreachable)
	for actor: int in scan.contacts:
		if actor != 1 and not engagements.has(actor) and alive(world, actor):
			engage(world, actor, scan.ids[scan.contacts[actor]], Vector2(-1, -1), ranged(world, actor), now)
	for actor: int in engagements.keys():
		if not alive(world, actor): engagements.erase(actor); continue
		var order: Dictionary = engagements[actor]
		var slot: int = world.actor_slots[actor]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		if states.has(actor):
			var state: Dictionary = states[actor]
			var lock_at: int = int(state.started_ms) + int(Defs.ACTIONS[state.kind].get("lock", 0))
			if now < lock_at:
				var seen: Variant = world.sight.observed_position(world, actor, order.target) if order.target > 0 else null
				if seen != null:
					var desired: Vector2 = position(world, actor).direction_to(seen)
					if not desired.is_zero_approx(): state.direction = Vector2(state.direction).rotated(clampf(Vector2(state.direction).angle_to(desired), -0.20, 0.20))
		if states.has(actor) or now < int(status.get(actor, {}).get("stun_until", 0)) or now < int(status.get(actor, {}).get("ready_ms", 0)): continue
		var origin: Vector2 = position(world, actor)
		if order.target == 0 and scan.contacts.has(actor):
			order.target = scan.ids[scan.contacts[actor]]
			order.react_ms = now + 220
		var observed: Variant = world.sight.observed_position(world, actor, order.target) if order.target > 0 else null
		if observed != null:
			if not alive(world, order.target): finish(world, actor, now); continue
			order.last_seen_pos = observed
			order.last_seen_ms = now
		elif order.last_seen_ms >= 0 and (now - int(order.last_seen_ms) >= CONTACT_MEMORY_MS or origin.distance_to(order.last_seen_pos) < 0.5 or (order.search_tile >= 0 and origin.distance_to(Terrain.center(order.search_tile)) < 0.4)):
			finish(world, actor, now); continue
		var goal: Vector2 = order.last_seen_pos if order.target > 0 else order.destination
		if goal.x < 0: continue
		var range_cells: float = float(profile(world, actor).range)
		if observed != null and origin.distance_to(goal) <= range_cells and Terrain.blocking_fraction(world.terrain.blocked, origin, goal) < 0:
			page.routes[row] = PackedVector2Array()
			page.modes[row] = Units.Mode.IDLE
			if now >= int(order.react_ms):
				var result: String = request(world, actor, "primary", origin.direction_to(goal), Vector2.ZERO, now, goal)
				if result not in ["started", "buffered"]: order.react_ms = now + 300
		elif now >= int(order.repath_ms):
			var projected: Vector2 = world.terrain.project_point(goal, page.radii[row], page.flight[row] > 0)
			if observed == null: order.search_tile = Terrain.index(Vector2i(projected)) if projected.x >= 0 else -1
			if projected.x < 0: blocked(world, actor, now); continue
			if origin.distance_to(projected) < 0.1: finish(world, actor, now); continue
			if projected.distance_squared_to(order.last_goal) >= 0.0625 or page.modes[row] != Units.Mode.COMBAT_MOVE:
				page.move_to(row, projected, Units.Mode.COMBAT_MOVE)
				order.last_goal = projected
				repaths += 1
			order.repath_ms = now + 300

func blocked(world: RefCounted, actor: int, now: int) -> void:
	var order: Dictionary = engagements[actor]
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var memory: Dictionary = {"topology": world.terrain.revision, "flight": page.flight[slot % 256], "large": page.radii[slot % 256] > 0.5, "targets": {}}
	if order.target > 0 and order.last_seen_ms >= 0: memory.targets[order.target] = Terrain.index(Vector2i(order.last_seen_pos))
	unreachable[actor] = memory
	world.objects.records[actor]["threat_scan_after"] = now + 2000
	finish(world, actor, now)

func view() -> Dictionary:
	var result: Dictionary = {}
	for actor: int in states:
		var state: Dictionary = states[actor]
		result[actor] = {"kind": state.kind, "started_ms": state.started_ms, "direction": state.direction, "activation": state.activation,
			"active_ms": Defs.active_ms(state), "recovery_ms": Defs.recovery_ms(state), "end_ms": Defs.end_ms(state), "confirmed": state.confirmed, "point": state.point, "visual": "evade" if Defs.is_evade(state.kind) else "shoot" if Defs.ACTIONS[state.kind].stat == "ranged" else "melee"}
	return result

func valid(world: RefCounted) -> bool:
	if catalog_signature != Defs.SIGNATURE or not Defs.ERRORS.is_empty(): return false
	if next_activation < 1 or next_bolt < 1 or shots < 0 or hits < 0 or resumed < 0: return false
	if _brain_bucket < -1 or _brain_bucket > world.elapsed_ms / 50: return false
	for actor: Variant in engagements:
		var order: Variant = engagements[actor]
		if not actor is int or not world.actor_slots.has(actor) or not order is Dictionary: return false
		for field: String in ["target", "scan_ms", "repath_ms", "react_ms", "last_seen_ms", "search_tile"]:
			if not order.get(field) is int: return false
		for field: String in ["destination", "last_goal", "last_seen_pos"]:
			if not _point_valid(order.get(field)): return false
		if not order.get("resume") is bool or not order.get("ranged") is bool: return false
		if order.target < 0 or order.target >= world.objects.next_id or order.target == actor or order.last_seen_ms < -1 or order.last_seen_ms > world.elapsed_ms or order.scan_ms < 0 or order.repath_ms < 0 or order.react_ms < 0 or order.search_tile < -1 or order.search_tile >= Terrain.SIZE * Terrain.SIZE: return false
	for actor: Variant in unreachable:
		var memory: Variant = unreachable[actor]
		if not actor is int or not world.actor_slots.has(actor) or not memory is Dictionary: return false
		if not memory.get("targets") is Dictionary or not memory.get("topology") is int or memory.topology < 0 or not memory.get("flight") is int or memory.flight not in [0, 1] or not memory.get("large") is bool: return false
		for target: Variant in memory.targets:
			if not target is int or target <= 0 or target >= world.objects.next_id or not memory.targets[target] is int or memory.targets[target] < 0 or memory.targets[target] >= Terrain.SIZE * Terrain.SIZE: return false
	for actor: Variant in states:
		var state: Variant = states[actor]
		if not actor is int or not world.actor_slots.has(actor) or not alive(world, actor) or world.actions.has(actor) or not state is Dictionary or not Defs.ACTIONS.has(state.get("kind")): return false
		if not _direction_valid(state.get("direction")) or not _direction_valid(state.get("aim")): return false
		if not state.get("started_ms") is int or state.started_ms < 0 or state.started_ms > world.elapsed_ms or not state.get("activation") is int or state.activation <= 0 or state.activation >= next_activation: return false
		if not state.get("target_id") is int or state.target_id < 0 or state.target_id >= world.objects.next_id: return false
		if not state.get("point") is Vector2 or not state.point.is_finite(): return false
		if Defs.ACTIONS[state.kind].delivery.target != "direction" and (not _point_valid(state.point) or state.point.x < 0): return false
		if not state.get("hit") is Dictionary or not state.get("damage") is int or not state.get("fired") is bool or not state.get("confirmed") is bool: return false
		if not state.get("step_speed") is float or state.step_speed not in [float(Defs.ACTIONS[state.kind].delivery.speed), float(Defs.ACTIONS[state.kind].delivery.backward_speed)]: return false
		if state.damage < 0 or Defs.end_ms(state) < world.elapsed_ms: return false
		for target: Variant in state.hit:
			if state.hit[target] != true: return false
			if target is String:
				if not target.begins_with("implement:") or not target.trim_prefix("implement:").is_valid_int(): return false
			elif not target is int or target <= 0 or target >= world.objects.next_id: return false
	for actor: Variant in intents:
		var intent: Variant = intents[actor]
		if not actor is int or not world.actor_slots.has(actor) or not alive(world, actor) or not intent is Dictionary: return false
		if intent.get("button") not in ["primary", "skill", "skill2", "skill3", "step"] or not _direction_valid(intent.get("aim")) or not intent.get("move") is Vector2 or not intent.move.is_finite() or intent.move.length() > 1.415: return false
		if not intent.get("target_id", 0) is int or int(intent.get("target_id", 0)) < 0 or int(intent.get("target_id", 0)) >= world.objects.next_id: return false
		if not intent.get("point") is Vector2 or not intent.point.is_finite(): return false
		var span: int = Defs.STEP_BUFFER_MS if intent.button == "step" else Defs.BUFFER_MS
		if not intent.get("at") is int or not intent.get("until") is int or intent.at < 0 or intent.at > world.elapsed_ms or intent.until < intent.at or intent.until > intent.at + span: return false
	for actor: Variant in cooldowns:
		if not actor is int or not world.actor_slots.has(actor) or not cooldowns[actor] is Dictionary: return false
		for key: Variant in cooldowns[actor]:
			if not key is String or not _cooldown_group(key) or not cooldowns[actor][key] is int or cooldowns[actor][key] < 0: return false
	for actor: Variant in chains:
		if not actor is int or not world.actor_slots.has(actor) or not chains[actor] is Dictionary or not Defs.ACTIONS.has(chains[actor].get("next")) or not Defs.ACTIONS.has(chains[actor].get("root")) or not chains[actor].get("until") is int or chains[actor].until < 0: return false
	for actor: Variant in status:
		var value: Variant = status[actor]
		if not actor is int or not world.actor_slots.has(actor) or not value is Dictionary or not value.get("groups") is Dictionary or not value.get("stun_window") is int or not value.get("stun_used") is int: return false
		if value.stun_window < 0 or value.stun_window > world.elapsed_ms or value.stun_used < 0 or value.stun_used > Defs.CONTROL_BUDGET_MS: return false
		for key: String in ["stun_from", "stun_until", "hit_stun_until", "push_until", "ready_ms", "recovery_from", "recovery_until", "guard_from"]:
			if value.has(key) and (not value[key] is int or value[key] < 0 or value[key] > world.elapsed_ms + Defs.MAX_STATUS_AHEAD_MS): return false
		if value.has("push") and (not value.push is Vector2 or not value.push.is_finite() or value.push.length() > 20): return false
		if value.has("punished") and not value.punished is bool: return false
		if value.has("punishable") and not value.punishable is bool: return false
		if value.has("last_damage_ms") and (not value.last_damage_ms is int or value.last_damage_ms < 0 or value.last_damage_ms > world.elapsed_ms): return false
		for key: Variant in value.groups:
			if not key is String or key.length() > 80 or not value.groups[key] is int or value.groups[key] < 0 or value.groups[key] > world.elapsed_ms + Defs.MAX_HIT_GROUP_MS: return false
	for id: Variant in bolts:
		var bolt: Variant = bolts[id]
		if not id is int or id <= 0 or id >= next_bolt or not bolt is Dictionary: return false
		if not bolt.get("timers") is Dictionary: return false
		for key: Variant in bolt.timers:
			if not key is String or bolt.timers[key] != true: return false
		if not Payload.valid(bolt.get("payload")) or not bolt.get("group_ms") is int or bolt.group_ms < 0 or bolt.group_ms > 5000: return false
		if not bolt.get("position") is Vector2 or not bolt.position.is_finite() or not bolt.get("velocity") is Vector2 or not bolt.velocity.is_finite(): return false
		for field: String in ["actor", "damage", "born_ms", "expire_ms", "activation"]:
			if not bolt.get(field) is int: return false
		if bolt.actor <= 0 or bolt.actor >= world.objects.next_id or bolt.damage < 0 or bolt.born_ms < 0 or bolt.born_ms > world.elapsed_ms or bolt.expire_ms <= world.elapsed_ms or bolt.expire_ms < bolt.born_ms or bolt.activation == 0 or bolt.activation >= next_activation: return false
		if not bolt.get("radius") is float or not is_finite(bolt.radius) or bolt.radius <= 0 or bolt.radius > 5: return false
		if not bolt.get("passed") is Dictionary: return false
		if not bolt.get("ability") is String or (not bolt.ability.is_empty() and (not Defs.ACTIONS.has(bolt.ability) or not Defs.is_shot(bolt.ability))): return false
		for field: String in ["side", "target", "pierce", "steered_ms", "next_steer"]:
			if not bolt.get(field) is int: return false
		if bolt.target < 0 or bolt.target >= world.objects.next_id or bolt.pierce < 0 or bolt.pierce > 8 or bolt.get("filter") not in ["physical", "hostile"] or not bolt.get("walls") is bool: return false
		if not bolt.get("turn") is float or not is_finite(bolt.turn) or bolt.turn < 0 or bolt.turn > 12 or bolt.velocity.length() <= 0 or bolt.velocity.length() > 60.01: return false
		if bolt.steered_ms < bolt.born_ms or bolt.steered_ms > world.elapsed_ms or bolt.next_steer != bolt.steered_ms + 50 or (bolt.turn > 0 and bolt.next_steer < world.elapsed_ms): return false
		for target: Variant in bolt.passed:
			if bolt.passed[target] != true: return false
			if target is String:
				if not target.begins_with("implement:") or not target.trim_prefix("implement:").is_valid_int(): return false
			elif not target is int or target <= 0 or target >= world.objects.next_id: return false
	return true

func _point_valid(value: Variant) -> bool:
	return value is Vector2 and value.is_finite() and (value == Vector2(-1, -1) or (value.x >= 0 and value.y >= 0 and value.x < Terrain.SIZE and value.y < Terrain.SIZE))

func _direction_valid(value: Variant) -> bool:
	return value is Vector2 and value.is_finite() and absf(value.length() - 1.0) < 0.01
