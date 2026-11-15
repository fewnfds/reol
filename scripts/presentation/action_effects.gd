extends Node2D
## Contact aftermath is presentation only. Bodies and danger regions never freeze.
const Art = preload("res://scripts/presentation/art.gd")
const Impact = preload("res://scripts/presentation/impact.gd")
const TILE: float = Art.TILE
const LIMIT: int = 96
var flash: float = 0.65
var shake: float = 0.65
var _effects: Array[Dictionary] = []
var _seen: Dictionary = {}
var _pulses: Dictionary = {}
var _frame: RefCounted
var _now: int = -1
var _epoch: int = -1

func adopt(frame: RefCounted, outcomes: Array, fog_enabled: bool) -> void:
	_frame = frame
	if _epoch != frame.epoch:
		_effects.clear()
		_seen.clear()
		_pulses.clear()
		_epoch = frame.epoch
		_now = -1
	for event: Dictionary in outcomes:
		if event.kind not in ["hit", "evaded", "death", "transferred", "ability_used", "healed"]: continue
		if int(event.get("epoch", frame.epoch)) != frame.epoch or not Impact.visible(frame, event, fog_enabled): continue
		var key: String = Impact.key(event)
		if _seen.has(key): continue
		_seen[key] = event.at_ms
		var id: int = Impact.subject(event)
		var slot: int = int(frame.actor_slots.get(id, -1))
		var point: Vector2 = event.get("position", frame.positions[slot])
		var tone: String = Impact.tone(event)
		if _effects.size() >= LIMIT: _effects.pop_front()
		_effects.append({"position": point, "target": id, "at": int(event.at_ms), "kind": event.kind, "tone": tone, "incoming": event.get("incoming", Vector2.LEFT), "tile": clampi(int(point.y) * 512 + int(point.x), 0, 512 * 512 - 1)})
		var pulse: String = "%s:%s" % [event.actor, event.get("activation", 0)]
		if tone in ["heavy", "break", "hurt"] and not _pulses.has(pulse): _pulses[pulse] = {"at": int(event.at_ms), "power": 2.5 if tone == "hurt" else 2.0}
		_now = -1
	for key: String in _seen.keys():
		if frame.world_ms - int(_seen[key]) > 2000: _seen.erase(key)

func advance(now: int, fog_enabled: bool) -> void:
	if now == _now: return
	_now = now
	for index: int in range(_effects.size() - 1, -1, -1):
		if now - int(_effects[index].at) > 450 or (fog_enabled and _frame.perception.tiles[_effects[index].tile] == 0): _effects.remove_at(index)
	for key: String in _pulses.keys():
		if now - int(_pulses[key].at) > 300: _pulses.erase(key)
	queue_redraw()

func camera_offset() -> Vector2:
	var power: float = 0.0
	for pulse: Dictionary in _pulses.values():
		var age: int = _now - int(pulse.at)
		if age >= 0 and age < 100: power = maxf(power, float(pulse.power) * pow(1.0 - age / 100.0, 2.0))
	return Vector2(sin(_now * 0.19), sin(_now * 0.23)) * minf(2.5, power) * shake

func tint(id: int, now: int) -> Color:
	for index: int in range(_effects.size() - 1, -1, -1):
		var effect: Dictionary = _effects[index]
		var age: int = now - int(effect.at)
		if effect.target != id or effect.kind != "hit" or age < 0 or age >= 65: continue
		var color := Color("f39d87") if id == 1 else (Color("eccb86") if effect.tone == "armor" else Color(1.8, 1.7, 1.5))
		return Color.WHITE.lerp(color, flash * (1.0 - age / 65.0))
	return Color.WHITE

func _draw() -> void:
	for effect: Dictionary in _effects:
		var age: int = _now - int(effect.at)
		if age < 0: continue
		var point: Vector2 = Art.body_foot(effect.position) * TILE
		var tone: String = effect.tone
		if effect.kind in ["hit", "evaded"]:
			var lifetime: float = 180.0 if tone in ["heavy", "break", "hurt"] else 120.0
			if age >= lifetime: continue
			var fade: float = 1.0 - age / lifetime
			var color := Color("b1e5e3") if tone == "evade" else (Color("d5ae68") if tone == "armor" else (Color("f38b70") if tone == "hurt" else Color("fff0c8")))
			color.a = fade * (0.40 + flash * 0.5)
			var count: int = 8 if tone in ["heavy", "break", "hurt"] else 4
			var incoming: Vector2 = effect.incoming
			for index: int in count:
				var direction: Vector2 = incoming.rotated((index - count * 0.5) * 0.6)
				var length: float = (13.0 if count == 8 else 7.0) * (0.4 + age / lifetime)
				draw_line(point + direction * 3.0, point + direction * length, color, 1.4, true)
			if tone in ["heavy", "break", "evade"]: draw_arc(point, 6 + age * 0.07, 0, TAU, 20, color, 1.2, true)
			if age < 45 and tone in ["heavy", "break"]: draw_line(point - incoming.rotated(0.6) * 11, point + incoming.rotated(0.6) * 11, color, 3.0, true)
		else:
			var appearance: String = "hit" if effect.kind == "death" else ("dust" if effect.kind == "transferred" else ("heal" if effect.kind == "healed" else "qi"))
			var index: int = clampi(age / 115, 0, 3)
			point += Vector2(0, -10 - age * 0.012)
			draw_texture_rect_region(Art.WORLD, Rect2(point - Vector2(24, 42), Vector2(48, 48)), Art.region("fx_%s_%d" % [appearance, index]))
