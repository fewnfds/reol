extends "res://tests/abilities_smoke.gd"
## Counterexamples for cached movement and publication cadence, not capacity gates.
const Runner = preload("res://scripts/sim/kernel/runner.gd")
const Status = preload("res://scripts/sim/definitions/actions/status_def.gd")

func movement_lifetimes() -> void:
	var w: RefCounted = fixture()
	var spec := Status.new()
	spec.id = "brief_slow"
	spec.magnitude = 0.6
	spec.duration_ms = 137
	w.effects.add(w, 1, 2, 0, "", spec.values(), 0, 0)
	spec.id = "brief_root"
	spec.kind = "root"
	spec.duration_ms = 53
	w.effects.add(w, 1, 2, 0, "", spec.values(), 0, 0)
	w.effects.prepare(w, 0)
	check(w.pages[0].move_scales[0] == 0, "Root missing from derived movement")
	w.Equipment.rebuild(w, 1) # Equipment changes must invalidate the same row.
	w.step(16)
	check(w.pages[0].move_scales[0] == 0, "Equipment rebuild erased an existing root")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.pages[0].move_scales == w.pages[0].move_scales, "Restored movement cache differs")
	w.step(37)
	w.effects.prepare(w, 53)
	check(is_equal_approx(w.pages[0].move_scales[0], 0.6), "Root expiry erased the surviving slow")
	w.step(84)
	w.effects.prepare(w, 137)
	check(w.pages[0].move_scales[0] == 1.0, "Exact expiry left a movement contribution")
	spec.duration_ms = 500
	w.effects.add(w, 4, 1, 0, "", spec.values(), w.elapsed_ms, 0)
	w.effects.prepare(w, w.elapsed_ms)
	var slot: int = w.actor_slots[4]
	check(w.pages[0].move_scales[slot] == 0, "Reuse fixture has no root")
	w.remove_actor(4)
	check(w.pages[0].move_scales[slot] == 1.0, "Free slot retained a movement contribution")
	var id: int = w.spawn_actor(w.Terrain.index(Vector2i(130, 120)))
	check(id > 4 and w.actor_slots[id] == slot and w.pages[0].move_scales[slot] == 1.0, "New body inherited the previous occupant's root")
	w.effects.prepare(w, w.elapsed_ms)
	check(w.pages[0].move_scales[slot] == 1.0, "Stale movement invalidation changed a reused slot")
	# Several dirty targets share one status pass; changing one cannot reset another.
	spec.id = "group_slow"
	spec.kind = "slow"
	spec.magnitude = 0.7
	var status: int = 0
	for actor: int in [1, 2, 3]:
		var added: int = w.effects.add(w, actor, 1, 0, "", spec.values(), w.elapsed_ms, 0)
		if actor == 2: status = added
	w.effects.prepare(w, w.elapsed_ms)
	check(is_equal_approx(w.pages[0].move_scales[0], 0.7) and is_equal_approx(w.pages[0].move_scales[1], 0.7) and is_equal_approx(w.pages[0].move_scales[2], 0.7), "Grouped movement rebuild skipped a dirty target")
	w.effects.remove(w, status, "dispelled", w.elapsed_ms)
	w.effects.prepare(w, w.elapsed_ms)
	check(w.pages[0].move_scales[1] == 1.0 and is_equal_approx(w.pages[0].move_scales[0], 0.7), "One target's dispel reset another contribution")

func current_spatial_facts() -> void:
	var w: RefCounted = fixture()
	var scan: RefCounted = w.combat.scan
	scan.index(w)
	var old: Vector2 = w.pages[0].positions[3]
	w.pages[0].positions[3] = Vector2(160.5, 160.5)
	w.objects.records[4].side = 7
	w.pages[0].health[2] = 0
	w.pages[0].delta_ms = 15
	w.pages[0].direct_velocities[1] = Vector2(40, 0)
	scan.index(w)
	check(not scan.nearby(old - Vector2.ONE, old + Vector2.ONE).has(4), "Old bucket retained a teleported body")
	check(scan.nearby(Vector2(160, 160), Vector2(161, 161)).has(4) and scan.sides[3] == 7 and scan.ids[2] == 0, "Spatial rebuild missed current position/side/death")
	check(is_equal_approx(scan.sweep_padding, 0.6), "Sweep envelope retained the previous interval")
	check(scan.bucket(Vector2(-0.1, -0.1)) == Vector2i(-1, -1), "Negative query bounds changed rounding")

func publication() -> void:
	var w: RefCounted = fixture()
	var runner := Runner.new()
	runner._world = w
	runner._terrain_view = w.terrain.detached()
	runner._publish(false, 1.0, 1, -1)
	var old: RefCounted = runner.poll().frame
	var hp: int = old.player.hp
	w.step(17)
	w.combat.damage(w, 2, 1, 10, 17)
	runner._publish(false, 1.0, 1, -1)
	var packet: Dictionary = runner.poll()
	check(runner._slow_frame == old and packet.frame.player.hp == hp - 10, "Notification forced slow statistics or delayed player details")
	check(old.player.hp == hp and not packet.outcomes.is_empty() and runner.poll().outcomes.is_empty(), "Old frame changed or reliable outcomes duplicated")
	w.combat.launch(1, w.pages[0].positions[0], w.pages[0].positions[1], w.elapsed_ms)
	runner._publish(false, 1.0, 1, -1)
	check(runner.poll().frame.projectiles.size() == 1, "Non-full publication lost projectile diagnostics")
	var id: int = w.spawn_actor(w.Terrain.index(Vector2i(130, 120)))
	runner._publish(false, 1.0, 1, -1)
	var fresh: RefCounted = runner.poll().frame
	check(fresh.actor_slots.has(id) and fresh.sides.size() == fresh.ids.size() and not old.actor_slots.has(id), "Layout changed without matching detached columns")
	check(fresh.loadout.is_read_only() and fresh.loadout == Defs.LOADOUTS.fire, "Published loadout is not the immutable definition")
	# Paused time cannot eventually reach the ordinary 100ms refresh deadline.
	var before: RefCounted = fresh
	var source: int = w.environment.source_cells[0]
	var result: Dictionary = w.command({"kind": "source", "tile": source})
	result.seq = 1
	runner._ready_receipts.append(result)
	runner._pending = 1
	runner._publish(true, 1.0, 1, -1)
	var paused: Dictionary = runner.poll()
	check(result.ok and paused.frame.source_enabled[0] == 0 and before.source_enabled[0] == 1 and paused.receipts.size() == 1, "Paused management receipt retained a stale environment view")
	w.command({"kind": "source", "tile": source})
	runner._publish(true, 1.0, 1, -1)
	check(runner.poll().frame.source_enabled[0] == 1, "Paused explicit publication retained stale fields")

func _run() -> void:
	movement_lifetimes()
	current_spatial_facts()
	publication()
	print("FRAMEWORK_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
