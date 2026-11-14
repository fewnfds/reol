extends Node2D
## Data-driven combat geometry, sampled at the same display time as bodies.
const Art = preload("res://scripts/presentation/art.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Motion = preload("res://scripts/sim/kernel/motion.gd")
var frame: RefCounted
var pose: RefCounted
var now: int = 0
var fog: bool = true
var target_point := Vector2.ZERO
var show_target: bool = false

func advance(current: RefCounted, history: RefCounted, at: int, use_fog: bool, point: Vector2, aiming: bool) -> void:
	frame = current
	pose = history
	now = at
	fog = use_fog
	target_point = point
	show_target = aiming
	queue_redraw()

func visible_point(point: Vector2) -> bool:
	if point.x < 0 or point.y < 0 or point.x >= 512 or point.y >= 512: return false
	return not fog or frame.perception.tiles[int(point.y) * 512 + int(point.x)] != 0

func _draw() -> void:
	if frame == null: return
	if show_target and not frame.loadout.is_empty() and frame.actor_slots.has(1):
		var def: Dictionary = Defs.ACTIONS[frame.loadout.primary]
		if def.delivery.target == "point":
			var origin: Vector2 = frame.positions[frame.actor_slots[1]]
			var point: Vector2 = origin + (target_point - origin).limit_length(float(def.delivery.range))
			var color := Color(def.tint)
			if not visible_point(point): color = Color("b85c5c")
			draw_arc(Art.body_foot(point) * Art.TILE, float(def.delivery.radius) * Art.TILE, 0, TAU, 36, Color(color, 0.65), 1.2, true)
	for value: Dictionary in frame.areas.values():
		if now < int(value.born_ms) or not visible_point(value.position): continue
		var def: Dictionary = Defs.ACTIONS[value.ability]
		var center: Vector2 = Art.body_foot(value.position) * Art.TILE
		var radius: float = float(def.delivery.radius) * Art.TILE
		var color := Color(def.tint) if value.actor == 1 else Color("ff8c7c")
		if now < int(value.trigger_ms):
			var weight: float = clampf(float(now - int(value.born_ms)) / maxi(1, int(value.trigger_ms) - int(value.born_ms)), 0, 1)
			draw_circle(center, radius, Color(color, 0.06))
			draw_arc(center, radius, 0, TAU, 48, Color(color, 0.55), 1.2, true)
			draw_arc(center, radius, -PI * 0.5, -PI * 0.5 + TAU * weight, 48, color, 2.4, true)
			draw_line(center - Vector2(5, 0), center + Vector2(5, 0), Color(color, 0.65), 1.5)
		else:
			var duration: int = int(def.delivery.duration)
			var last: int = int(value.trigger_ms) + ((now - int(value.trigger_ms)) / int(def.delivery.period)) * int(def.delivery.period)
			var age: int = now - last
			if duration == 0: age = now - int(value.trigger_ms)
			if duration == 0 and age > 160: continue
			if duration > 0 and now >= int(value.expire_ms): continue
			draw_circle(center, radius, Color(color, 0.10 + maxf(0, 1.0 - age / 160.0) * 0.12))
			draw_arc(center, radius, 0, TAU, 48, Color(color, 0.7), 1.8, true)
			if age < 120:
				var fade: float = 1.0 - age / 120.0
				for index: int in 4:
					var offset: Vector2 = Vector2.RIGHT.rotated(index * TAU / 4) * radius * 0.45
					var bolt := PackedVector2Array([center + offset + Vector2(0, -radius - 28), center + offset + Vector2(-6, -18), center + offset + Vector2(4, -22), center + offset])
					draw_polyline(bolt, Color(color, fade), 2.2, true)
	if pose != null:
		for segment: Dictionary in pose.projectile_segments:
			if now < int(segment.start_ms) or now > int(segment.end_ms): continue
			var t: float = clampf(float(now - int(segment.start_ms)) / maxi(1, int(segment.end_ms) - int(segment.start_ms)), 0, 1)
			var position: Vector2 = Vector2(segment.from).lerp(segment.to, t)
			if not visible_point(position): continue
			var point: Vector2 = Art.body_foot(position) * Art.TILE
			var direction: Vector2 = Vector2(segment.from).direction_to(segment.to)
			var def: Dictionary = Defs.ACTIONS.get(segment.get("ability", ""), {})
			var color := Color(def.get("tint", "9fddd4")) if segment.actor == 1 else Color("ff9986")
			var radius: float = maxf(2.0, float(segment.radius) * Art.TILE)
			if segment.actor != 1: draw_circle(point, radius + 1.6, Color("38152b"))
			draw_line(point - direction * (radius + 8), point, Color(color, 0.45), radius, true)
			draw_circle(point, radius, color)
			draw_circle(point + direction * radius * 0.35, maxf(1, radius * 0.35), Color("eef5df"))
	for value: Dictionary in frame.implements.values():
		var position: Vector2 = value.position
		var deployed: bool = false
		if pose != null:
			for segment: Dictionary in pose.implement_segments:
				if segment.id == value.id and now >= int(segment.start_ms) and now <= int(segment.end_ms):
					if now < int(segment.active_until) and now <= int(value.get("stopped_ms", 9223372036854775807)):
						position = Motion.at(segment.from, segment.to, segment.knots, clampf(float(now - int(segment.start_ms)) / maxi(1, int(segment.end_ms) - int(segment.start_ms)), 0, 1))
						deployed = true
					break
		if not deployed and value.phase == "stowed": continue
		if not visible_point(position): continue
		var point: Vector2 = Art.body_foot(position) * Art.TILE
		var direction: Vector2 = value.direction
		var normal := Vector2(-direction.y, direction.x)
		var color := Color("a9e4d6") if value.phase not in ["broken", "dropped"] else Color("9b9b8a")
		draw_line(point - direction * 20, point - direction * 6, Color(color, 0.35), 5, true)
		draw_colored_polygon(PackedVector2Array([point + direction * 13, point + normal * 3, point - direction * 9, point - normal * 3]), color)
		draw_line(point - normal * 6 - direction * 6, point + normal * 6 - direction * 6, Color("d9ba7a"), 2, true)
		draw_arc(point, 15, -PI * 0.5, -PI * 0.5 + TAU * float(value.hp) / int(Defs.ACTIONS[value.ability].delivery.durability), 24, Color(color, 0.8), 1.4, true)
	for value: Dictionary in frame.effects.values():
		if now < int(value.born_ms) or now >= int(value.until_ms) or not frame.actor_slots.has(value.target): continue
		var point: Vector2 = frame.positions[frame.actor_slots[value.target]]
		if not visible_point(point): continue
		var color := Color("8edcec") if value.kind == "slow" else Color("e6a869")
		draw_arc(Art.body_foot(point) * Art.TILE, 11, 0.2, 2.9, 16, Color(color, 0.85), 2, true)
