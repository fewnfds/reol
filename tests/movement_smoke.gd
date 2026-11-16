extends "res://tests/melee_smoke.gd"
## Contact endpoints, escape and top-down ground footprints, independent of sprite height.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")

func contact_endpoints() -> void:
	var ground := Terrain.new()
	ground.initialize(0, 1)
	ground.blocked.fill(0)
	for y: int in range(20, 40): ground.blocked[Terrain.index(Vector2i(120, y))] = 1
	var body := Units.new()
	body.initialize(1, 1, ground)
	var random := RandomNumberGenerator.new()
	random.seed = 917
	for sample: int in 128:
		body.positions[0] = Vector2(119.5, random.randf_range(22.0, 37.0))
		body.delta_ms = random.randi_range(1, 33)
		body.direct_velocities[0] = Vector2(1, random.randf_range(-0.8, 0.8)) * random.randf_range(0.1, 13.0)
		for tick: int in 15:
			var before: Vector2 = body.positions[0]
			body.advance_direct(0)
			check(ground.can_stand(body.positions[0], body.radii[0]), "A diagonal contact committed an overlapping endpoint")
			for knot: Vector3 in body.motion.get(0, PackedVector3Array()):
				check(ground.segment_clear(before, Vector2(knot.x, knot.y), body.radii[0]), "A slide's published trajectory crossed a wall")
				before = Vector2(knot.x, knot.y)
		var contact: Vector2 = body.positions[0]
		body.direct_velocities[0] = Vector2.LEFT * 5
		body.delta_ms = 17
		body.advance_direct(0)
		check(body.positions[0].x < contact.x - 0.07, "A touching body could not move away immediately")
	# Existing saves may contain a subpixel overlap left by the former integrator.
	body.positions[0] = Vector2(119.65004, 30.5)
	body.advance_direct(0)
	check(ground.can_stand(body.positions[0], body.radii[0]) and body.positions[0].x < 119.6, "An old contact overlap could not escape")
	body.positions[0] = Vector2(120.5, 30.5)
	body.advance_direct(0)
	check(body.positions[0] == Vector2(120.5, 30.5), "Contact recovery teleported through a solid tile")
	ground.blocked.fill(0)
	for radius: float in [0.35, 0.9]:
		body.radii[0] = radius
		for direction: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN, Vector2(1, 1).normalized()]:
			body.positions[0] = Vector2(0.95 if direction.x < 0 else 511.05, 0.95 if direction.y < 0 else 511.05)
			body.direct_velocities[0] = direction * 13
			body.delta_ms = 160
			body.advance_direct(0)
			check(ground.can_stand(body.positions[0], body.radii[0]), "A map-edge sweep left the map or read row/column 512")
			body.direct_velocities[0] = -direction * 5
			body.advance_direct(0)
			check(ground.can_stand(body.positions[0], body.radii[0]), "A body could not reverse away from the map edge")
	check(ground.project_point(Vector2(600, 600), 0.35, false, 0.004).x < 0, "Bounded contact recovery snapped a distant invalid point into the map")

func melee_and_passages() -> void:
	for direction: Vector2 in [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN, Vector2(1, -0.4).normalized()]:
		var w: RefCounted = fixture()
		var body: RefCounted = w.pages[0]
		w.objects.records[1]["ability_loadout"] = "sword"
		w.facilities.create_completed(w, "wood_chest", Terrain.index(Vector2i(120, 120)))
		w.flush_topology()
		body.positions[0] = Vector2(120.5, 120.5) - direction * (0.54 / maxf(absf(direction.x), absf(direction.y)) + 0.35)
		check(w.combat.request(w, 1, "primary", direction) == "started", "Wall-facing melee did not start")
		advance(w, 330)
		check(w.terrain.can_stand(body.positions[0], body.radii[0]), "Melee lunge entered furniture")
		var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
		check(restored != null, "Touching furniture could not restore")
		var contact: Vector2 = body.positions[0]
		w.combat.set_control(w, {"enabled": true, "move": -direction, "aim": direction, "primary": false})
		advance(w, 530)
		check(body.positions[0].distance_to(contact) > 0.7 and w.terrain.can_stand(body.positions[0], body.radii[0]), "Melee contact prevented walking away")
		if restored != null:
			restored.combat.set_control(restored, {"enabled": true, "move": -direction, "aim": direction, "primary": false})
			advance(restored, 530)
			check(restored.pages[0].positions[0] == body.positions[0], "Restoring a wall contact changed subsequent movement")
	var w: RefCounted = fixture()
	var body: RefCounted = w.pages[0]
	for x: int in range(118, 126):
		w.facilities.create_completed(w, "wood_chest", Terrain.index(Vector2i(x, 120)))
		w.facilities.create_completed(w, "wood_wall", Terrain.index(Vector2i(x, 122)))
	w.flush_topology()
	body.positions[0] = Vector2(118.5, 121.5)
	w.combat.set_control(w, {"enabled": true, "move": Vector2.RIGHT, "aim": Vector2.UP, "primary": false})
	advance(w, 1000)
	check(body.positions[0].x > 122.5 and w.terrain.can_stand(body.positions[0], body.radii[0]), "A one-cell passage south of furniture treated the character's height as occupied ground")

func _run() -> void:
	contact_endpoints()
	melee_and_passages()
	print("MOVEMENT_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
