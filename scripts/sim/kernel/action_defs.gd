extends RefCounted
## Shared player/NPC action contracts. Times are world milliseconds.
const BUFFER_MS: int = 120
const ACTIONS: Dictionary = {
	"slash_1": {"windup": 70, "active": 60, "recovery": 150, "reach": 1.55, "angle": 1.0, "damage": 1.0, "move": 0.28, "stun": 80, "push": 2.0},
	"slash_2": {"windup": 80, "active": 70, "recovery": 170, "reach": 1.65, "angle": 1.1, "damage": 1.05, "move": 0.24, "stun": 95, "push": 2.5},
	"slash_3": {"windup": 140, "active": 90, "recovery": 230, "reach": 1.9, "angle": 1.2, "damage": 1.5, "move": 0.18, "stun": 140, "push": 4.5},
	"shot": {"windup": 160, "active": 1, "recovery": 220, "damage": 1.0, "move": 0.8, "stun": 0, "push": 0.0},
	"cleave": {"windup": 180, "active": 100, "recovery": 240, "reach": 2.6, "angle": 1.15, "damage": 1.8, "move": 0.1, "stun": 160, "push": 5.0, "cooldown": 1800},
	"fan": {"windup": 180, "active": 1, "recovery": 240, "damage": 0.8, "move": 0.6, "stun": 0, "push": 0.0, "cooldown": 1800},
	"step": {"windup": 0, "active": 160, "recovery": 60, "damage": 0.0, "move": 0.0, "speed": 13.0, "cooldown": 700}
}

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
