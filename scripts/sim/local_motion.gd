class_name SimLocalMotion
extends RefCounted
## Continuous body position is owned here. Scene nodes are projections.
## No inventory, stamina copy, wall-clock timer or invulnerability lives here.

const RULES_PATH: String = "res://data/definitions/local_actions.json"
const MAX_TIME: int = 9007199254740991
const INTEGRATION_STEP_MS: int = 1

var _position: Vector2 = Vector2.ZERO
var _facing: Vector2 = Vector2.DOWN
var _body: Dictionary = {}
var _space_changed: Callable
var position: Vector2:
	get:
		return SimRouteTravel.point(_body) if not _body.is_empty() else _position
	set(value):
		if _body.is_empty():
			_position = value
		else:
			var before: Vector2i = SimRouteTravel.cell(_body.cell)
			SimRouteTravel.put(_body, value)
			if before != SimRouteTravel.cell(_body.cell) and _space_changed.is_valid():
				_space_changed.call()
var velocity: Vector2 = Vector2.ZERO
var facing: Vector2:
	get:
		return SimRouteTravel.facing(_body) if not _body.is_empty() else _facing
	set(value):
		if _body.is_empty():
			_facing = value
		else:
			_body.facing = [value.x, value.y]
var blocked: bool = false
var action: Dictionary = {}
var last_outcome: String = ""
var rules: Dictionary


func _init(definitions: Dictionary = {}) -> void:
	rules = definitions


static func valid_rules(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") != 1:
		return false
	for section: String in ["clock", "motion", "sidestep", "recovery"]:
		if not value.get(section) is Dictionary:
			return false
	for field: String in ["fixed_step_ms", "steps_per_frame", "wait_minutes", "view_transition_ms"]:
		if not SimInventory._valid_count(value.clock.get(field), false):
			return false
	for field: String in ["speed", "acceleration", "friction", "sweep_px"]:
		var number: Variant = value.motion.get(field)
		if not (number is int or number is float) or not is_finite(float(number)) or float(number) <= 0.0:
			return false
	for field: String in ["prepare_ms", "travel_ms", "recover_ms", "speed", "stamina"]:
		if not SimInventory._valid_count(value.sidestep.get(field), false):
			return false
	return SimInventory._valid_count(value.recovery.get("delay_ms")) and SimInventory._valid_count(value.recovery.get("stamina_per_second"))


func bind_body(body: Dictionary, space_changed: Callable = Callable()) -> void:
	# Facing, like position, is a projection of the one original body. Preserve
	# its last heading across route/manual control changes and view recreation.
	_body = body
	_space_changed = space_changed


func cell() -> Vector2i:
	return TileGrid.world_to_cell(position)


func relocate(point: Vector2) -> void:
	position = point
	velocity = Vector2.ZERO
	blocked = false
	cancel("relocated")


func begin_sidestep(now: int, direction: Vector2, actor: Dictionary) -> bool:
	var definition: Dictionary = rules.sidestep
	var duration: int = int(definition.prepare_ms) + int(definition.travel_ms) + int(definition.recover_ms)
	if not action.is_empty() or now < 0 or now > MAX_TIME - duration or not actor.get("alive", false) or not actor.get("active", {}).is_empty():
		return false
	if int(actor.get("stamina", 0)) < int(definition.stamina) or not direction.is_finite():
		return false
	if direction.is_zero_approx():
		direction = facing
	actor.stamina = int(actor.stamina) - int(definition.stamina)
	actor["exertion_until_ms"] = now + duration + int(rules.recovery.delay_ms)
	actor["stamina_carry"] = 0
	facing = direction.normalized()
	action = {"kind": "sidestep", "started_ms": now, "advanced_ms": now,
		"direction": [facing.x, facing.y], "blocked": false, "stamina_spent": int(definition.stamina)}
	velocity = Vector2.ZERO
	last_outcome = ""
	return true


func cancel(reason: String) -> void:
	if not action.is_empty():
		last_outcome = reason
		action = {}
	velocity = Vector2.ZERO


func limit_walking_speed(speed_fraction: float = 1.0) -> void:
	# Restrict existing momentum as well as the next desired velocity. Starting
	# a slow cast must not carry a prior full-speed run into its preparation.
	var fraction: float = clampf(speed_fraction, 0.0, 1.0) if is_finite(speed_fraction) else 0.0
	velocity = velocity.limit_length(float(rules.motion.speed) * fraction)


func advance(from_ms: int, to_ms: int, intent: Vector2, can_step: Callable, controlled: bool = true, speed_fraction: float = 1.0) -> void:
	if to_ms <= from_ms:
		return
	if not controlled:
		cancel("control_lost")
		return
	if not action.is_empty():
		var end: int = int(action.started_ms) + int(rules.sidestep.prepare_ms) + int(rules.sidestep.travel_ms) + int(rules.sidestep.recover_ms)
		_advance_sidestep(from_ms, to_ms, can_step)
		if action.is_empty() and to_ms > end:
			advance(maxi(from_ms, end), to_ms, intent, can_step, controlled, speed_fraction)
		return
	limit_walking_speed(speed_fraction)
	if not intent.is_finite():
		intent = Vector2.ZERO
	if not intent.is_zero_approx():
		facing = intent.normalized()
	# The timeline's integer millisecond is the local integration quantum. A
	# caller cutting at an arbitrary effect/hit boundary must consume exactly
	# the same body substeps as one sparse call, including float coordinates and
	# collision sweeps. This does not wake any other world domain per millisecond.
	var cursor: int = from_ms
	var speed: float = velocity_limit(speed_fraction)
	while cursor < to_ms:
		if intent.is_zero_approx() and velocity.is_zero_approx():
			break
		var end: int = mini(to_ms, cursor + INTEGRATION_STEP_MS)
		var dt: float = float(end - cursor) / 1000.0
		var target: Vector2 = intent.limit_length() * speed
		var rate: float = float(rules.motion.acceleration if not intent.is_zero_approx() else rules.motion.friction)
		velocity = velocity.move_toward(target, rate * dt)
		if velocity.length_squared() < 1.0:
			velocity = Vector2.ZERO
		_move(velocity * dt, can_step)
		cursor = end
		if intent.is_zero_approx() and velocity.is_zero_approx():
			break


func velocity_limit(speed_fraction: float = 1.0) -> float:
	return float(rules.motion.speed) * (clampf(speed_fraction, 0.0, 1.0) if is_finite(speed_fraction) else 0.0)


func _advance_sidestep(from_ms: int, to_ms: int, can_step: Callable) -> void:
	var definition: Dictionary = rules.sidestep
	var start: int = int(action.started_ms)
	var effect: int = start + int(definition.prepare_ms)
	var recovery: int = effect + int(definition.travel_ms)
	var end: int = recovery + int(definition.recover_ms)
	var cursor: int = maxi(maxi(from_ms, int(action.advanced_ms)), effect)
	var travel_end: int = mini(to_ms, recovery)
	if travel_end > cursor and not bool(action.blocked):
		var direction := Vector2(float(action.direction[0]), float(action.direction[1]))
		while cursor < travel_end:
			var next: int = mini(travel_end, cursor + INTEGRATION_STEP_MS)
			_move(direction * float(definition.speed) * float(next - cursor) / 1000.0, can_step, false)
			cursor = next
			if blocked:
				action.blocked = true
				break
	action.advanced_ms = mini(to_ms, end)
	if to_ms >= end:
		last_outcome = "blocked" if bool(action.blocked) else "finished"
		action = {}
		velocity = Vector2.ZERO


func phase(now: int) -> String:
	if action.is_empty():
		return ""
	var elapsed: int = now - int(action.started_ms)
	if elapsed < int(rules.sidestep.prepare_ms):
		return "起势"
	if elapsed < int(rules.sidestep.prepare_ms) + int(rules.sidestep.travel_ms):
		return "闪身"
	return "收势"


func _move(motion: Vector2, can_step: Callable, slide: bool = true) -> void:
	blocked = false
	var count: int = maxi(1, ceili(motion.length() / float(rules.motion.sweep_px)))
	for _index in count:
		var part: Vector2 = motion / float(count)
		if _try_to(position + part, can_step):
			continue
		blocked = true
		if not slide:
			velocity = Vector2.ZERO
			break
		if not is_zero_approx(part.x) and not _try_to(position + Vector2(part.x, 0), can_step):
			velocity.x = 0.0
		if not is_zero_approx(part.y) and not _try_to(position + Vector2(0, part.y), can_step):
			velocity.y = 0.0


func _try_to(point: Vector2, can_step: Callable) -> bool:
	var next: Vector2i = TileGrid.world_to_cell(point)
	var current: Vector2i = cell()
	if next != current and (not can_step.is_valid() or not bool(can_step.call(current, next - current))):
		return false
	position = point
	return true


func to_dict() -> Dictionary:
	return {"velocity": [velocity.x, velocity.y], "facing": [facing.x, facing.y],
		"action": action.duplicate(true), "last_outcome": last_outcome, "blocked": blocked}


static func legacy_state() -> Dictionary:
	return {"velocity": [0.0, 0.0], "facing": [0.0, 1.0], "action": {}, "last_outcome": "", "blocked": false}


func valid_state(data: Variant, now: int) -> bool:
	if not data is Dictionary or data.size() != 5 or not _vector(data.get("velocity")) or not _vector(data.get("facing")) or not data.get("action") is Dictionary or not data.get("last_outcome") is String or not data.get("blocked") is bool:
		return false
	var saved_velocity := Vector2(float(data.velocity[0]), float(data.velocity[1]))
	var saved_facing := Vector2(float(data.facing[0]), float(data.facing[1]))
	if saved_velocity.length() > float(rules.motion.speed) + 0.001 or absf(saved_facing.length() - 1.0) > 0.001:
		return false
	var value: Dictionary = data.action
	if value.is_empty():
		return true
	if value.size() != 6 or value.get("kind") != "sidestep" or not _vector(value.get("direction")) or not value.get("blocked") is bool or value.get("stamina_spent") != rules.sidestep.stamina:
		return false
	for field: String in ["started_ms", "advanced_ms"]:
		if not ReolGameClock._integer(value.get(field)):
			return false
	var end: int = int(value.started_ms) + int(rules.sidestep.prepare_ms) + int(rules.sidestep.travel_ms) + int(rules.sidestep.recover_ms)
	var direction := Vector2(float(value.direction[0]), float(value.direction[1]))
	return saved_velocity.is_zero_approx() and int(value.started_ms) <= now and int(value.advanced_ms) == now and now < end and absf(direction.length() - 1.0) < 0.001 and direction.is_equal_approx(saved_facing)


func restore(data: Dictionary, point: Vector2, now: int) -> bool:
	if not point.is_finite() or not valid_state(data, now):
		return false
	position = point
	velocity = Vector2(float(data.velocity[0]), float(data.velocity[1]))
	facing = Vector2(float(data.facing[0]), float(data.facing[1]))
	action = data.action.duplicate(true)
	last_outcome = str(data.last_outcome)
	blocked = bool(data.blocked)
	return true


static func _vector(value: Variant) -> bool:
	return value is Array and value.size() == 2 and (value[0] is int or value[0] is float) and (value[1] is int or value[1] is float) and is_finite(float(value[0])) and is_finite(float(value[1]))
