extends RefCounted
## A small integrated fixture; capacity measurement belongs to release captures.

const World = preload("res://scripts/sim/kernel/world.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")


static func run(check: Callable) -> void:
	var w := World.new()
	w.initialize(6, 0)
	var page: RefCounted = w.pages[0]
	for row: int in 6:
		w.release(row + 1)
		w.objects.records[row + 1].autonomous = false
		page.modes[row] = 4
		page.positions[row] = Vector2(145.5, 145.5 + row)
	var wall: int = Terrain.index(Vector2i(158, 150))
	var wall_id: int = w.objects.create("wall", "wood_wall", wall)
	w.queue_structure(wall, true, true)
	w.flush_topology()
	page.positions[2] = Vector2(154.5, 150.5)
	page.positions[3] = Vector2(162.5, 150.5)
	w.combat.launch(3, page.positions[2], page.positions[3], w.elapsed_ms)
	w.kill(3)
	for step: int in 12:
		w.step()
	check.call(page.health[3] == 100 and w.combat.bolts.is_empty() and w.objects.records[wall_id].hp < 100, "Arrow ignored wall or stopped existing after shooter death")
	w.facilities.demolish(w, wall_id)
	w.flush_topology()
	page.positions[1] = Vector2(154.5, 150.5)
	w.combat.launch(2, page.positions[1], page.positions[3], w.elapsed_ms)
	w.kill(2)
	for step: int in 12:
		w.step()
	check.call(page.health[3] == 80, "Launched projectile vanished with its dead shooter")
	page.positions[0] = Vector2(151.5, 150.5)
	page.positions[3] = Vector2(152.5, 150.5)
	page.health[0] = 25
	page.health[3] = 25
	w.combat.begin(w, 1, "pursue", 4)
	w.combat.begin(w, 4, "pursue", 1)
	w.step()
	check.call(page.health[0] == 0 and page.health[3] == 0, "Same-boundary committed strikes did not allow mutual death")
	# Restore the tiny fixture's participants for independent social scenarios.
	for row: int in [0, 1, 3]:
		page.health[row] = 100
		page.modes[row] = 4
	w.combat.orders.clear()
	# A stop issued after agreeing to wait must survive the inviter's cancel.
	w.objects.records[2].autonomous = true
	page.positions[0] = Vector2(176.5, 187.5)
	page.positions[1] = Vector2(177.5, 187.5)
	w.command({"kind": "talk", "target": 2})
	w.command({"kind": "stop", "actor": 2})
	w.command({"kind": "stop", "actor": 1})
	check.call(page.modes[1] == 4 and not w.objects.records[2].autonomous, "Canceling invitation overwrote a newer stop")
	page.positions[0] = Vector2(176.5, 187.5)
	page.positions[1] = Vector2(177.5, 187.5)
	check.call(not w.command({"kind": "ability"}).ok, "Unknown method granted a usable ability")
	check.call(w.command({"kind": "learn", "target": 2}).ok, "Teacher contact rejected")
	for step: int in 30:
		w.step()
	check.call(w.objects.records[1].get("methods", {}).has("wood_breath") and not w.command({"kind": "ability"}).ok, "Learning was conflated with mastered ability")
	w.command({"kind": "trade", "target": 2})
	for step: int in 30:
		w.step()
	check.call(w.objects.amount(1, "breath_manual") == 1 and w.objects.amount(2, "breath_manual") == 0, "Real exchange did not commit both inventories")
	var a: int = w.objects.create("chest", "wood_chest", -1, 5)
	var b: int = w.objects.create("chest", "wood_chest", -1, 5)
	w.objects.add(a, "wood", 5)
	w.objects.add(b, "stone", 5)
	check.call(w.objects.exchange(a, b, "wood", 5, "stone", 5) and w.objects.amount(a, "stone") == 5 and w.objects.amount(b, "wood") == 5, "Two full containers could not atomically exchange")
	var tree: int = 0
	for id: int in w.nature.ids:
		if w.objects.records[id].definition == "old_tree":
			tree = id
	page.positions[0] = Vector2(174.5, 180.5)
	for attempt: int in 3:
		w.command({"kind": "practice", "target": tree})
		for step: int in 70:
			w.step()
	page.health[0] = 50
	check.call(w.command({"kind": "ability"}).ok and page.health[0] == 75 and w.objects.records[tree].qi < 1000, "Practice did not use stored qi and unlock a real ability")
	var practice_before: int = w.objects.records[1].practice
	w.command({"kind": "practice", "target": tree})
	w.step()
	w.objects.records[tree].hp = 0
	w.nature.evaluate(w, tree, w.elapsed_ms)
	var remaining_qi: int = w.objects.records[tree].qi
	for step: int in 70:
		w.step()
	check.call(w.objects.records[1].practice == practice_before and w.objects.records[tree].qi == remaining_qi, "A withered tree still granted an in-flight practice reward")
	var site: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", Terrain.index(Vector2i(160, 173)))
	if site.get("target", 0) == 0:
		w.objects.transfer(w.source_objects[0], 1, "wood", 10)
		site = w.facilities.blueprint(w, 1, "wood_wall", Terrain.index(Vector2i(160, 173)))
	var task: int = int(site.get("target", 0))
	check.call(task > 0, "Could not create a physical cooperation task")
	if task > 0:
		w.objects.records[task].remaining_ms = 1000
		var action: Dictionary = {"kind": "request_help", "target": 5, "task_target": task}
		check.call(w.society.finish(w, 1, action, w.elapsed_ms) == "completed" and w.objects.records[task].kind == "blueprint" and not w.reservations.has(task), "Accepted promise fabricated completed construction")
		w.livelihood.think(w, 5, w.elapsed_ms)
	var saved: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check.call(saved != null and saved.objects.records[1].get("abilities", {}).has("wood_mend"), "Integrated domains could not resume from a candidate")
	var memory_tile: int = Terrain.index(Vector2i(175, 179))
	var object: int = w.objects.create("chest", "wood_chest", memory_tile)
	w.perception.update(w, w.elapsed_ms, true)
	check.call(w.perception.memories.has(object), "Visible static object was not remembered")
	w.terrain.set_floor(memory_tile, true)
	w.terrain.revision += 1
	w.perception.update(w, w.elapsed_ms + 200)
	check.call((w.perception.ground[memory_tile] & 8) != 0, "Observed ground was not cached")
	for tile: int in w.perception.seen_tiles:
		check.call(w.perception.explored[tile] != 0 and w.perception.ground[tile] != 0, "Visible tile left a hole in exploration or remembered terrain")
	var previous_tree_stage: int = w.perception.memories[tree].stage
	var original_position: Vector2 = page.positions[0]
	page.positions[5] = Terrain.center(memory_tile)
	page.positions[0] = Vector2(310.5, 195.5)
	w.objects.remove_empty(object)
	w.terrain.set_floor(memory_tile, false)
	w.terrain.revision += 1
	w.objects.records[tree].stage = 3
	w.objects.layout_revision += 1
	w.perception.update(w, w.elapsed_ms, true)
	check.call(w.perception.explored[memory_tile] != 0 and w.perception.tiles[memory_tile] == 0 and w.perception.visible[5] == 0, "Explored fog revealed a live unit or remained currently visible")
	check.call((w.perception.ground[memory_tile] & 8) != 0 and w.perception.memories[tree].stage == previous_tree_stage, "Offscreen terrain or plant changes leaked into memory")
	saved = Persistence.candidate(Persistence.capture(w), 0)
	check.call(saved != null and saved.perception.memories.has(object) and (saved.perception.ground[memory_tile] & 8) != 0 and saved.perception.memories[tree].stage == previous_tree_stage, "Loading or unseen removal refreshed frozen terrain/object memory")
	page.positions[0] = original_position
	w.perception.update(w, w.elapsed_ms, true)
	check.call(not w.perception.memories.has(object), "Returning to an empty observed place retained a ghost object")
	check.call((w.perception.ground[memory_tile] & 8) == 0 and w.perception.memories[tree].stage == 3 and w.perception.visible[5] != 0, "Reobservation did not refresh terrain, plant and unit visibility together")
	var carried: int = w.objects.amount(1, "breath_manual")
	var before: int = w.nature.evaluations
	w.command({"kind": "journey", "region": 1})
	for step: int in 760:
		w.step()
	check.call(page.positions[0].distance_to(Vector2(309.5, 194.5)) < 0.1 and w.nature.evaluations > before and w.objects.amount(1, "breath_manual") == carried, "Travel froze world processes or recreated carried objects")
	if task > 0:
		check.call(w.objects.records[task].kind == "wall", "Old-region promised work froze while player traveled")
	check.call(w.environment.ambient_at(Terrain.index(Vector2i(310, 195))) < w.environment.ambient_at(Terrain.index(Vector2i(175, 185))) and w.objects.audit_total("wood") == w.objects.total("wood"), "Regions had no actual environment difference or broke material accounting")
	var regional_source: int = w.environment.source_cells.find(Terrain.index(Vector2i(314, 194)))
	var source_enabled: int = w.environment.enabled[regional_source]
	check.call(w.command({"kind": "source", "tile": Terrain.index(Vector2i(314, 194))}).ok and w.environment.enabled[regional_source] != source_enabled, "Source control confused render marker order with source identity")
	# Switching attack commands must not grant a second, separate cooldown.
	w.release(1)
	w.release(4)
	page.positions[0] = Vector2(155.5, 151.5)
	page.positions[3] = Vector2(156.5, 151.5)
	page.health[0] = 100
	page.health[3] = 100
	page.modes[0] = 4
	page.modes[3] = 4
	check.call(w.command({"kind": "attack", "target": 4}).ok, "Immediate melee command failed")
	w.combat.begin(w, 1, "pursue", 4)
	w.step()
	check.call(page.health[3] == 75, "Switching to pursuit bypassed the shared attack cooldown")
	preload("res://tests/tile_smoke.gd").run(w, check)
