extends RefCounted
## Shared player/NPC action contracts. Times are world milliseconds.
const BUFFER_MS: int = 120
const STEP_BUFFER_MS: int = 80
const EVADE_MS: int = 90
const CONTROL_WINDOW_MS: int = 1200
const CONTROL_BUDGET_MS: int = 400
const ACTIONS: Dictionary = {
	"slash_1": {"windup": 70, "active": 60, "recovery": 150, "reach": 1.55, "angle": 1.0, "damage": 1.0, "move": 0.40, "free_at": 190, "free_move": 0.80, "stun": 90, "push": 0.12, "lunge": 0.10, "lunge_from": 40, "lunge_to": 100, "next_hit": 190, "next_miss": 240, "step_hit": 0, "step_miss": 160, "skill_hit": 160, "skill_miss": 210},
	"slash_2": {"windup": 80, "active": 70, "recovery": 170, "reach": 1.65, "angle": 1.1, "damage": 1.1, "move": 0.30, "free_at": 220, "free_move": 0.75, "stun": 110, "push": 0.16, "lunge": 0.18, "lunge_from": 50, "lunge_to": 120, "next_hit": 220, "next_miss": 280, "step_hit": 0, "step_miss": 190, "skill_hit": 190, "skill_miss": 240},
	"slash_3": {"windup": 140, "active": 90, "recovery": 230, "reach": 1.9, "angle": 0.75, "damage": 1.6, "move": 0.18, "free_at": 360, "free_move": 0.75, "stun": 200, "push": 0.35, "heavy_hit": true, "lunge": 0.24, "lunge_from": 80, "lunge_to": 170, "step_hit": 300, "step_miss": 360},
	"shot": {"windup": 160, "active": 1, "recovery": 220, "damage": 1.0, "move": 0.8, "stun": 0, "push": 0.0},
	"cleave": {"windup": 180, "active": 100, "recovery": 240, "reach": 2.4, "angle": 1.15, "damage": 2.0, "move": 0.1, "free_at": 420, "free_move": 0.65, "stun": 240, "push": 0.45, "heavy_hit": true, "lunge": 0.22, "lunge_from": 100, "lunge_to": 200, "step_hit": 340, "step_miss": 420, "cooldown": 3200},
	"fan": {"windup": 180, "active": 1, "recovery": 240, "damage": 0.8, "move": 0.6, "stun": 0, "push": 0.0, "cooldown": 1800},
	"step": {"windup": 0, "active": 160, "recovery": 60, "damage": 0.0, "move": 0.0, "speed": 13.0, "cooldown": 700},
	"enemy_light": {"windup": 400, "lock": 100, "active": 70, "recovery": 420, "reach": 1.55, "angle": 0.87, "damage": 0.35, "move": 0.0, "stun": 90, "push": 0.16, "post": 200},
	"enemy_heavy": {"windup": 550, "lock": 200, "active": 100, "recovery": 800, "reach": 2.3, "angle": 1.05, "damage": 0.70, "move": 0.0, "stun": 200, "push": 0.50, "heavy_hit": true, "steady": true, "post": 250},
	"enemy_shot": {"windup": 480, "lock": 240, "active": 1, "recovery": 450, "damage": 0.4, "move": 0.0, "stun": 0, "push": 0.0, "bolt_speed": 14.0, "post": 950}
}

static func is_shot(kind: String) -> bool:
	return kind in ["shot", "fan", "enemy_shot"]

static func cancel_ms(state: Dictionary, button: String) -> int:
	var def: Dictionary = ACTIONS[state.kind]
	var prefix: String = "next" if button == "primary" else button
	var key: String = prefix + ("_hit" if state.confirmed else "_miss")
	return int(state.started_ms) + int(def.get(key, end_ms(state) - int(state.started_ms)))

static func evading(state: Dictionary, at: int) -> bool:
	return state.get("kind") == "step" and at >= int(state.started_ms) and at < int(state.started_ms) + EVADE_MS

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
