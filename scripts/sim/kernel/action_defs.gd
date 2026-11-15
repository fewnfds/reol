extends RefCounted
## Validated immutable values. Resources are authoring inputs, never cast state.
const LIBRARY = preload("res://data/definitions/combat/library.tres")
const BUFFER_MS: int = 120
const STEP_BUFFER_MS: int = 80
const EVADE_MS: int = 90
const CONTROL_WINDOW_MS: int = 1200
const CONTROL_BUDGET_MS: int = 400
const MAX_HIT_GROUP_MS: int = 5000
const MAX_STATUS_AHEAD_MS: int = 20000 # Three <=5s phases plus <=5s post commitment.
static var _compiled: Dictionary = LIBRARY.compile()
static var ERRORS: PackedStringArray = _compiled.errors
static var ACTIONS: Dictionary = _freeze(_compiled.actions)
static var LOADOUTS: Dictionary = _freeze(_compiled.loadouts)
static var SIGNATURE: String = _signature()

static func _freeze(value: Variant) -> Variant:
	if value is Dictionary:
		for child: Variant in value.values(): _freeze(child)
		value.make_read_only()
	elif value is Array:
		for child: Variant in value: _freeze(child)
		value.make_read_only()
	return value

static func _signature() -> String:
	var logic: Dictionary = ACTIONS.duplicate(true)
	for def: Dictionary in logic.values():
		for key: String in ["title", "description", "tint"]: def.erase(key)
	var profiles: Dictionary = LOADOUTS.duplicate(true)
	for profile: Dictionary in profiles.values():
		for key: String in ["title", "description"]: profile.erase(key)
	return JSON.stringify({"abilities": logic, "loadouts": profiles, "scripts": preload("res://scripts/sim/kernel/reaction_scripts/owned_marks.gd").LOGIC_VERSION, "meal": preload("res://data/definitions/actions/meal_effect.tres").values()}, "", true).sha256_text()

static func is_shot(kind: String) -> bool:
	return ACTIONS[kind].delivery.kind == "projectile"

static func is_evade(kind: String) -> bool:
	return ACTIONS.get(kind, {}).get("delivery", {}).get("kind") == "evade"

static func cancel_ms(state: Dictionary, button: String) -> int:
	var def: Dictionary = ACTIONS[state.kind]
	var prefix: String = "next" if button == "primary" else "skill" if button in ["skill2", "skill3"] else button
	return int(state.started_ms) + int(def[prefix + ("_hit" if state.confirmed else "_miss")])

static func evading(state: Dictionary, at: int) -> bool:
	return not state.is_empty() and at >= int(state.started_ms) and at < int(state.started_ms) + int(ACTIONS[state.kind].evade_ms)

static func end_ms(state: Dictionary) -> int:
	var def: Dictionary = ACTIONS[state.kind]
	return int(state.started_ms) + int(def.windup) + int(def.active) + int(def.recovery)

static func active_ms(state: Dictionary) -> int:
	return int(state.started_ms) + int(ACTIONS[state.kind].windup)

static func recovery_ms(state: Dictionary) -> int:
	return active_ms(state) + int(ACTIONS[state.kind].active)

static func sector(def: Dictionary, direction: Vector2) -> PackedVector2Array:
	var polygon := PackedVector2Array([Vector2.ZERO])
	for index: int in 9:
		polygon.append(direction.rotated(lerpf(-float(def.angle), float(def.angle), index / 8.0)) * float(def.reach))
	return polygon
