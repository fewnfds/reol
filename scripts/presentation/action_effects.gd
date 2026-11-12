extends Node2D
## Bounded visual aftermath of committed outcomes. No damage or targeting rules.
const Art = preload("res://scripts/presentation/art.gd")
const TILE: float = 32.0
const LIMIT: int = 96
var _effects: Array[Dictionary] = []
var _frame: RefCounted
var _now: int = -1
var _epoch: int = -1


func adopt(frame: RefCounted, outcomes: Array, fog_enabled: bool) -> void:
	_frame = frame
	if _epoch != frame.epoch:
		_effects.clear()
		_epoch = frame.epoch
		_now = -1
	for outcome: Dictionary in outcomes:
		if int(outcome.get("epoch", frame.epoch)) != frame.epoch:
			continue
		var kind: String = str(outcome.kind)
		if kind not in ["hit", "death", "transferred", "ability_used", "healed"]:
			continue
		var id: int = int(outcome.get("target", outcome.get("actor", 0))) if kind == "hit" else int(outcome.get("actor", 0))
		var slot: int = int(frame.actor_slots.get(id, -1))
		if slot < 0 or (fog_enabled and (slot >= frame.visible.size() or frame.visible[slot] == 0)):
			continue
		if _effects.size() >= LIMIT:
			_effects.pop_front()
		var appearance: String = "hit" if kind in ["hit", "death"] else ("dust" if kind == "transferred" else ("heal" if kind == "healed" else "qi"))
		_effects.append({"position": frame.positions[slot], "at": int(outcome.at_ms), "kind": appearance, "tile": int(frame.positions[slot].y) * 512 + int(frame.positions[slot].x)})
		_now = -1 # New outcomes must redraw even at the same paused world time.


func advance(now: int, fog_enabled: bool) -> void:
	if now == _now:
		return
	_now = now
	for index: int in range(_effects.size() - 1, -1, -1):
		if now - int(_effects[index].at) > 450 or (fog_enabled and _frame.perception.tiles[_effects[index].tile] == 0):
			_effects.remove_at(index)
	queue_redraw()


func _draw() -> void:
	for effect: Dictionary in _effects:
		var age: int = _now - int(effect.at)
		if age < 0:
			continue
		var frame: int = clampi(age / 115, 0, 3)
		var point: Vector2 = effect.position * TILE + Vector2(0, -10 - age * 0.012)
		draw_texture_rect_region(Art.WORLD, Rect2(point - Vector2(24, 42), Vector2(48, 48)), Art.region("fx_%s_%d" % [effect.kind, frame]))
