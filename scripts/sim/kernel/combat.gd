extends RefCounted
## One action executor for direct control and AI. World alone commits effects.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const Scan = preload("res://scripts/sim/kernel/combat_scan.gd")
const Motion = preload("res://scripts/sim/kernel/motion.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const CONTACT_MEMORY_MS: int = 5000
const STATE_FIELDS: Array = ["engagements", "states", "cooldowns", "chains", "status", "bolts", "next_bolt", "next_activation", "shots", "hits", "resumed", "unreachable"]
var engagements: Dictionary = {} # AI contacts, never player attack-move orders.
var states: Dictionary = {}
var cooldowns: Dictionary = {}
var chains: Dictionary = {}
var status: Dictionary = {}
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

func ranged(world: RefCounted, actor: int) -> bool:
	var key: String = str(world.objects.records[actor].get("equipment", {}).get("weapon", ""))
	return not key.is_empty() and Items.definition(key) == "short_bow"

func set_control(world: RefCounted, input: Dictionary) -> void:
	var actor: int = 1
	if not alive(world, actor): controls.erase(actor); return
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if not input.get("enabled", false):
		controls.erase(actor)
		if states.has(actor): states[actor].buffer = {}
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
	if not movement.is_zero_approx() and not controls.has(actor) and not states.has(actor):
		world.release(actor)
	controls[actor] = {"move": movement, "primary": bool(input.get("primary", false))}
	if not movement.is_zero_approx():
		world.objects.records[actor].autonomous = false
		page.routes[row] = PackedVector2Array()
		page.modes[row] = Units.Mode.DIRECT

func request(world: RefCounted, actor: int, button: String, aim: Vector2, movement: Vector2 = Vector2.ZERO, at: int = -1) -> String:
	var now: int = world.elapsed_ms if at < 0 else at
	if not alive(world, actor) or not aim.is_finite() or not movement.is_finite(): return "invalid_action"
	var slot: int = world.actor_slots[actor]
	var page: RefCounted = world.pages[slot / 256]
	var row: int = slot % 256
	if aim.length_squared() < 0.000001: aim = page.aims[row]
	aim = aim.normalized()
	if now < int(status.get(actor, {}).get("stun_until", 0)): return "stunned"
	if button not in ["primary", "skill", "step"]: return "invalid_action"
	if states.has(actor):
		var current: Dictionary = states[actor]
		var cancel_at: int = Defs.recovery_ms(current)
		var confirmed_step: bool = button == "step" and bool(current.confirmed) and str(current.kind).begins_with("slash")
		if now < cancel_at and not confirmed_step:
			if button == "primary" and not ranged(world, actor) and str(current.kind).begins_with("slash") and cancel_at - now <= Defs.BUFFER_MS:
				current.buffer = {"aim": aim, "until": now + Defs.BUFFER_MS}
				return "buffered"
			return "action_committed"
	var kind: String
	if button == "step": kind = "step"
	elif button == "skill": kind = "fan" if ranged(world, actor) else "cleave"
	elif ranged(world, actor): kind = "shot"
	else:
		var chain: Dictionary = chains.get(actor, {})
		var index: int = int(chain.get("next", 1)) if now <= int(chain.get("until", -1)) else 1
		kind = "slash_%d" % index
	var due: Dictionary = cooldowns.get(actor, {})
	if button != "primary" and now < int(due.get(button, 0)): return "cooldown"
	var def: Dictionary = Defs.ACTIONS[kind]
	if world.actions.has(actor) or page.modes[row] in [Units.Mode.RESOURCE, Units.Mode.HARVEST, Units.Mode.REST, Units.Mode.MANUAL, Units.Mode.APPROACH, Units.Mode.ACTION, Units.Mode.EXPLORE]: world.release(actor, now)
	if actor == 1: world.objects.records[actor].autonomous = false
	page.routes[row] = PackedVector2Array()
	page.route_cursors[row] = 0
	page.targets[row] = page.positions[row]
	page.modes[row] = Units.Mode.DIRECT
	page.aims[row] = aim
	var direction: Vector2 = movement.normalized() if kind == "step" and not movement.is_zero_approx() else (-aim if kind == "step" else aim)
	states[actor] = {"kind": kind, "started_ms": now, "direction": direction, "aim": aim,
		"activation": next_activation, "hit": {}, "fired": false, "confirmed": false, "buffer": {},
		"damage": roundi((page.ranged_damage[row] if kind in ["shot", "fan"] else page.melee_damage[row]) * float(def.damage))}
	next_activation += 1
	if str(kind).begins_with("slash"):
		var index: int = int(kind.right(1))
		chains[actor] = {"next": index % 3 + 1, "until": Defs.end_ms(states[actor]) + 350}
	elif kind != "step": chains.erase(actor)
	if button != "primary":
		due[button] = now + int(def.cooldown)
		cooldowns[actor] = due
	world.emit({"kind": "action_started", "actor": actor, "action": kind, "activation": states[actor].activation, "at_ms": now})
	return "started"

func next_boundary(now: int, end: int) -> int:
	var result: int = end
	for state: Dictionary in states.values():
		for boundary: int in [Defs.active_ms(state), Defs.recovery_ms(state), Defs.end_ms(state)]:
			if boundary > now: result = mini(result, boundary)
	for value: Dictionary in status.values():
		var boundary: int = int(value.get("stun_until", 0))
		if boundary > now: result = mini(result, boundary)
	for bolt: Dictionary in bolts.values():
		if int(bolt.expire_ms) > now: result = mini(result, int(bolt.expire_ms))
	return result

func prepare(world: RefCounted, now: int) -> void:
	var started: int = Time.get_ticks_usec()
	for actor: int in states.keys():
		var state: Dictionary = states[actor]
		var buffer: Dictionary = state.buffer
		if not buffer.is_empty() and now >= Defs.recovery_ms(state) and now <= int(buffer.until):
			state.buffer = {}
			request(world, actor, "primary", buffer.aim, Vector2.ZERO, now)
			state = states[actor]
		if now >= Defs.end_ms(state):
			states.erase(actor)
			var slot: int = world.actor_slots[actor]
			world.pages[slot / 256].modes[slot % 256] = Units.Mode.IDLE
			continue
		if not state.fired and now >= Defs.active_ms(state):
			state.fired = true
			if state.kind in ["shot", "fan"]:
				var count: int = 5 if state.kind == "fan" else 1
				for index: int in count:
					var direction: Vector2 = state.direction.rotated((index - (count - 1) * 0.5) * 0.16)
					launch(actor, position(world, actor), position(world, actor) + direction, now, state.damage, state.activation)
			world.emit({"kind": "action_active", "actor": actor, "action": state.kind, "at_ms": now})
	if _brain_bucket != now / 50:
		_brain_bucket = now / 50
		_think(world, now)
	for actor: int in controls:
		if bool(controls[actor].primary) and ranged(world, actor) and not states.has(actor):
			request(world, actor, "primary", world.pages[world.actor_slots[actor] / 256].aims[world.actor_slots[actor] % 256], Vector2.ZERO, now)
	var bodies: Dictionary = {}
	for actor: int in states: bodies[actor] = true
	for actor: int in controls: bodies[actor] = true
	for actor: int in status: bodies[actor] = true
	for actor: int in bodies:
		if not alive(world, actor): continue
		var slot: int = world.actor_slots[actor]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		var state: Dictionary = states.get(actor, {})
		var value: Dictionary = status.get(actor, {})
		var movement: Vector2 = controls.get(actor, {}).get("move", Vector2.ZERO)
		var velocity: Vector2 = movement * page.move_speed[row]
		if not state.is_empty():
			var def: Dictionary = Defs.ACTIONS[state.kind]
			velocity *= float(def.move)
			if state.kind == "step" and now < Defs.recovery_ms(state): velocity = state.direction * float(def.speed)
		if now < int(value.get("stun_until", 0)):
			velocity = value.get("push", Vector2.ZERO)
		elif value.has("stun_until") and state.is_empty() and not controls.has(actor):
			if page.modes[row] == Units.Mode.DIRECT: page.modes[row] = Units.Mode.IDLE
		if not state.is_empty() or controls.has(actor) or now < int(value.get("stun_until", 0)):
			page.modes[row] = Units.Mode.DIRECT
			page.direct_velocities[row] = velocity
	var cost: int = Time.get_ticks_usec() - started
	prepare_usec += cost
	work_usec += cost

func before_motion(world: RefCounted) -> void:
	previous.clear()
	if bolts.is_empty() and states.is_empty(): return
	for page: RefCounted in world.pages: previous.append(page.positions.duplicate())

func step(world: RefCounted, start: int, now: int) -> void:
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
	if bolts.is_empty() and melee.is_empty(): return
	scan.index(world)
	var impacts: Array[Dictionary] = []
	for id: int in bolts.keys():
		var bolt: Dictionary = bolts[id]
		var from: Vector2 = bolt.position
		var until: int = mini(now, int(bolt.expire_ms))
		var to: Vector2 = from + Vector2(bolt.velocity) * maxf(0, until - start) / 1000.0
		var wall: Dictionary = Motion.wall_hit(world.terrain, from, to, bolt.radius)
		var first: float = wall.fraction
		var hit: int = 0
		for target: int in scan.nearby(from.min(to) - Vector2.ONE * (1.0 + scan.sweep_padding), from.max(to) + Vector2.ONE * (1.0 + scan.sweep_padding)):
			if target == bolt.actor: continue
			var slot: int = world.actor_slots[target]
			var page: RefCounted = world.pages[slot / 256]
			var row: int = slot % 256
			var before: Vector2 = previous[slot / 256][row] if not previous.is_empty() else page.positions[row]
			var fraction: float = Motion.hit_fraction(from, to, before, page.positions[row], page.radii[row] + float(bolt.radius), page.motion.get(row, PackedVector3Array()))
			if fraction >= 0 and (first < 0 or fraction < first): first = fraction; hit = target
		if first >= 0 and hit == 0 and wall.tile >= 0:
			for object: int in world.objects.by_tile.get(wall.tile, []):
				if world.objects.records[object].kind in ["wall", "door"]: hit = object; break
		var at: int = start + roundi((until - start) * (first if first >= 0 else 1.0))
		var endpoint: Vector2 = from.lerp(to, first) if first >= 0 else to
		projectile_segments.append({"id": id, "actor": bolt.actor, "from": from, "to": endpoint, "start_ms": start, "end_ms": at, "radius": bolt.radius})
		if hit > 0: impacts.append({"actor": bolt.actor, "target": hit, "damage": bolt.damage, "activation": bolt.activation, "at_ms": at, "incoming": -Vector2(bolt.velocity).normalized(), "stun": 0, "push": 0.0})
		if first >= 0 or now >= int(bolt.expire_ms): bolts.erase(id)
		else: bolt.position = to
	for actor: int in melee:
		var state: Dictionary = states[actor]
		var def: Dictionary = Defs.ACTIONS[state.kind]
		var origin: Vector2 = position(world, actor)
		var own_slot: int = world.actor_slots[actor]
		var before_origin: Vector2 = previous[own_slot / 256][own_slot % 256]
		var own_knots: PackedVector3Array = world.pages[own_slot / 256].motion.get(own_slot % 256, PackedVector3Array())
		var polygon: PackedVector2Array = Defs.sector(def, state.direction)
		var reach: float = float(def.reach) + 1.0 + scan.sweep_padding
		for target: int in scan.nearby(origin - Vector2.ONE * reach, origin + Vector2.ONE * reach):
			if target == actor or state.hit.has(target): continue
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
			state.hit[target] = true
			state.confirmed = true
			impacts.append({"actor": actor, "target": target, "damage": state.damage, "activation": state.activation,
				"at_ms": start + roundi((now - start) * fraction), "incoming": (source - contact).normalized(), "stun": def.stun, "push": def.push, "melee": true})
	impacts.sort_custom(func(a: Dictionary, b: Dictionary): return a.at_ms < b.at_ms if a.at_ms != b.at_ms else a.actor < b.actor)
	var collected: int = Time.get_ticks_usec()
	collect_usec += collected - started
	var index: int = 0
	while index < impacts.size():
		var end: int = index + 1
		while end < impacts.size() and impacts[end].at_ms == impacts[index].at_ms: end += 1
		var accepted: Array[Dictionary] = []
		for entry: int in range(index, end):
			var impact: Dictionary = impacts[entry]
			if not impact.get("melee", false) or (alive(world, impact.actor) and states.get(impact.actor, {}).get("activation") == impact.activation): accepted.append(impact)
		# Equal-time contacts trade; an earlier death/stagger cancels later melee.
		for impact: Dictionary in accepted:
			damage(world, impact.actor, impact.target, impact.damage, impact.at_ms, impact.incoming, impact.activation, impact.stun, impact.push)
		index = end
	damage_usec += Time.get_ticks_usec() - collected
	var cost: int = Time.get_ticks_usec() - started
	resolve_usec += cost
	work_usec += cost

func launch(actor: int, origin: Vector2, destination: Vector2, now: int, amount: int = 20, activation: int = 0) -> void:
	if origin.is_equal_approx(destination): return
	bolts[next_bolt] = {"actor": actor, "position": origin, "velocity": origin.direction_to(destination) * 22.0,
		"damage": amount, "radius": 0.10, "born_ms": now, "expire_ms": now + 2000, "activation": activation if activation > 0 else -next_bolt}
	next_bolt += 1
	shots += 1

func damage(world: RefCounted, actor: int, target: int, amount: int, now: int, incoming: Vector2 = Vector2.ZERO, activation: int = 0, stun_ms: int = 0, push: float = 0.0) -> void:
	if not alive(world, target): return
	var applied: int
	var rec: Dictionary = world.objects.records[target]
	if world.actor_slots.has(target):
		var value: Dictionary = status.get(target, {"groups": {}, "stun_window": 0, "stun_used": 0})
		var group: String = "%d:%d" % [actor, activation]
		if activation != 0 and now < int(value.groups.get(group, 0)): return
		for key: String in value.groups.keys():
			if now >= int(value.groups[key]): value.groups.erase(key)
		if activation != 0: value.groups[group] = now + 280
		value.last_damage_ms = now
		var slot: int = world.actor_slots[target]
		var page: RefCounted = world.pages[slot / 256]
		var row: int = slot % 256
		applied = mini(page.health[row], maxi(1, amount - page.armor[row]))
		page.health[row] -= applied
		if world.actions.has(target) or page.modes[row] in [Units.Mode.RESOURCE, Units.Mode.HARVEST, Units.Mode.REST, Units.Mode.MANUAL, Units.Mode.APPROACH, Units.Mode.ACTION, Units.Mode.EXPLORE]:
			world.release(target, now)
			page.modes[row] = Units.Mode.IDLE
		if now >= int(value.stun_window) + 800: value.stun_window = now; value.stun_used = 0
		var duration: int = mini(stun_ms, maxi(0, 220 - int(value.stun_used)))
		if duration > 0:
			value.stun_used += duration
			value.stun_until = now + duration
			value.push = -incoming * push
			states.erase(target)
			page.routes[row] = PackedVector2Array()
			page.modes[row] = Units.Mode.DIRECT
		status[target] = value
		world.attacks += 1
		world.emit({"kind": "hit", "actor": actor, "target": target, "damage": applied, "at_ms": now, "position": page.positions[row], "activation": activation})
		if page.health[row] <= 0: world.kill(target, now, "combat")
		elif target != 1 and not engagements.has(target):
			world.sight.sync(world)
			if alive(world, actor) and world.sight.observed_position(world, target, actor) != null: engage(world, target, actor, Vector2(-1, -1), ranged(world, target), now)
			elif not incoming.is_zero_approx():
				var goal: Vector2 = world.terrain.project_point(position(world, target) + incoming * 6.0, page.radii[row], page.flight[row] > 0)
				if goal.x >= 0: engage(world, target, 0, goal, ranged(world, target), now)
	else:
		applied = mini(int(rec.hp), maxi(1, amount - int(world.facilities.definitions.get(rec.definition, {}).get("armor", 0))))
		rec.hp -= applied
		world.emit({"kind": "hit", "actor": actor, "target": target, "damage": applied, "at_ms": now})
		if rec.hp <= 0: world.facilities.demolish(world, target, now)
	hits += 1

func engage(world: RefCounted, actor: int, target: int = 0, destination: Vector2 = Vector2(-1, -1), use_bow: bool = false, at: int = -1) -> String:
	if not alive(world, actor) or (target > 0 and (target == actor or not alive(world, target))): return "invalid_target"
	world.sight.sync(world)
	var observed: Variant = world.sight.observed_position(world, actor, target) if target > 0 else null
	if target > 0 and observed == null: return "target_not_visible"
	var now: int = world.elapsed_ms if at < 0 else at
	var automatic: bool = world.objects.records[actor].get("autonomous", false)
	# Engagement changes preserve an already committed action and hit reaction.
	var state: Dictionary = states.get(actor, {})
	world.release(actor, now)
	if not state.is_empty(): states[actor] = state
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
		if states.has(actor) or now < int(status.get(actor, {}).get("stun_until", 0)): continue
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
		var range_cells: float = 8.0 if ranged(world, actor) else 1.5
		if observed != null and origin.distance_to(goal) <= range_cells and Terrain.blocking_fraction(world.terrain.blocked, origin, goal) < 0:
			page.routes[row] = PackedVector2Array()
			page.modes[row] = Units.Mode.IDLE
			if now >= int(order.react_ms):
				var button: String = "skill" if world.objects.records[actor].get("heavy", false) and now >= int(cooldowns.get(actor, {}).get("skill", 0)) else "primary"
				request(world, actor, button, origin.direction_to(goal), Vector2.ZERO, now)
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
		result[actor] = {"kind": state.kind, "started_ms": state.started_ms, "direction": state.direction,
			"active_ms": Defs.active_ms(state), "recovery_ms": Defs.recovery_ms(state), "end_ms": Defs.end_ms(state), "confirmed": state.confirmed}
	return result

func valid(world: RefCounted) -> bool:
	if next_activation < 1 or next_bolt < 1 or shots < 0 or hits < 0 or resumed < 0: return false
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
		if not state.get("hit") is Dictionary or not state.get("buffer") is Dictionary or not state.get("damage") is int or not state.get("fired") is bool or not state.get("confirmed") is bool: return false
		if state.damage < 0 or Defs.end_ms(state) < world.elapsed_ms: return false
		for target: Variant in state.hit:
			if not target is int or target <= 0 or target >= world.objects.next_id or state.hit[target] != true: return false
		if not state.buffer.is_empty() and (not _direction_valid(state.buffer.get("aim")) or not state.buffer.get("until") is int or state.buffer.until < state.started_ms or state.buffer.until > world.elapsed_ms + Defs.BUFFER_MS): return false
	for actor: Variant in cooldowns:
		if not actor is int or not world.actor_slots.has(actor) or not cooldowns[actor] is Dictionary: return false
		for key: Variant in cooldowns[actor]:
			if key not in ["skill", "step"] or not cooldowns[actor][key] is int or cooldowns[actor][key] < 0: return false
	for actor: Variant in chains:
		if not actor is int or not world.actor_slots.has(actor) or not chains[actor] is Dictionary or not chains[actor].get("next") is int or chains[actor].next < 1 or chains[actor].next > 3 or not chains[actor].get("until") is int or chains[actor].until < 0: return false
	for actor: Variant in status:
		var value: Variant = status[actor]
		if not actor is int or not world.actor_slots.has(actor) or not value is Dictionary or not value.get("groups") is Dictionary or not value.get("stun_window") is int or not value.get("stun_used") is int: return false
		if value.stun_window < 0 or value.stun_window > world.elapsed_ms or value.stun_used < 0 or value.stun_used > 220: return false
		if value.has("stun_until") and (not value.stun_until is int or value.stun_until < 0 or value.stun_until > world.elapsed_ms + 220 or not value.get("push") is Vector2 or not value.push.is_finite() or value.push.length() > 100): return false
		if value.has("last_damage_ms") and (not value.last_damage_ms is int or value.last_damage_ms < 0 or value.last_damage_ms > world.elapsed_ms): return false
		for key: Variant in value.groups:
			if not key is String or key.length() > 80 or not value.groups[key] is int or value.groups[key] < 0 or value.groups[key] > world.elapsed_ms + 280: return false
	for id: Variant in bolts:
		var bolt: Variant = bolts[id]
		if not id is int or id <= 0 or id >= next_bolt or not bolt is Dictionary: return false
		if not bolt.get("position") is Vector2 or not bolt.position.is_finite() or not bolt.get("velocity") is Vector2 or not bolt.velocity.is_finite(): return false
		for field: String in ["actor", "damage", "born_ms", "expire_ms", "activation"]:
			if not bolt.get(field) is int: return false
		if bolt.actor <= 0 or bolt.actor >= world.objects.next_id or bolt.damage < 0 or bolt.born_ms < 0 or bolt.born_ms > world.elapsed_ms or bolt.expire_ms <= world.elapsed_ms or bolt.expire_ms < bolt.born_ms or bolt.activation == 0 or bolt.activation >= next_activation: return false
		if not bolt.get("radius") is float or not is_finite(bolt.radius) or bolt.radius <= 0 or bolt.radius > 2: return false
	return true

func _point_valid(value: Variant) -> bool:
	return value is Vector2 and value.is_finite() and (value == Vector2(-1, -1) or (value.x >= 0 and value.y >= 0 and value.x < Terrain.SIZE and value.y < Terrain.SIZE))

func _direction_valid(value: Variant) -> bool:
	return value is Vector2 and value.is_finite() and absf(value.length() - 1.0) < 0.01
