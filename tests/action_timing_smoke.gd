extends "res://tests/abilities_smoke.gd"

func buffered_gates() -> void:
	var w: RefCounted = fixture("sword")
	w.pages[0].positions[1] = w.pages[0].positions[0] + Vector2.RIGHT
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	w.combat.cooldowns[1] = {Defs.ACTIONS.cleave.cd_group: 180}
	advance(w, 60)
	check(w.combat.request(w, 1, "skill", Vector2.RIGHT) == "buffered", "Valid multi-gate intent was not accepted")
	advance(w, 170)
	check(w.combat.intents.has(1) and w.combat.states[1].confirmed, "Hit-confirm consumed a buffer before cooldown readiness")
	check(w.combat.next_boundary(w, 170, 200) == 180, "Buffered cooldown was absent from the chronological boundary")
	var original_until: int = w.combat.intents[1].until
	advance(w, 181)
	check(w.combat.states[1].kind == "cleave" and w.combat.states[1].started_ms == 180, "Buffered action missed exact inclusive deadline/readiness")
	check(not w.combat.intents.has(1) and original_until == 180, "Consuming a buffer renewed its expiry")
	var missing: RefCounted = fixture("sword")
	missing.combat.request(missing, 1, "primary", Vector2.RIGHT)
	advance(missing, 80)
	missing.combat.request(missing, 1, "primary", Vector2.RIGHT)
	advance(missing, 202)
	check(missing.combat.states[1].kind == "slash_1" and not missing.combat.intents.has(1), "Unconfirmed window extended the original intent lifetime")
	var npc: RefCounted = fixture("sword")
	npc.objects.records[2]["ability_loadout"] = "sword"
	npc.pages[0].positions[0] = npc.pages[0].positions[1] + Vector2.RIGHT
	npc.combat.request(npc, 2, "primary", Vector2.RIGHT)
	npc.combat.cooldowns[2] = {Defs.ACTIONS.cleave.cd_group: 180}
	advance(npc, 60)
	npc.combat.request(npc, 2, "skill", Vector2.RIGHT)
	advance(npc, 170)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(npc), 0)
	check(restored != null, "NPC buffered gates could not restore")
	if restored != null:
		advance(npc, 181)
		advance(restored, 181)
		check(npc.combat.states[2].kind == "cleave" and restored.combat.states[2].started_ms == 180, "NPC restore changed buffer readiness")

func implement_fixture() -> RefCounted:
	var w: RefCounted = fixture("flying_sword")
	w.pages[0].positions[0] = Vector2(124.5, 120.5)
	w.pages[0].positions[1] = Vector2(120.85, 120.5)
	w.combat.previous.clear()
	w.combat.previous.append(w.pages[0].positions.duplicate())
	w.terrain.blocked[w.Terrain.index(Vector2i(121, 120))] = 1
	w.combat.next_activation = 2
	w.implements.dispatch(w, 1, {"kind": "sword_dispatch", "direction": Vector2.RIGHT, "activation": 1, "damage": 20, "side": 0, "power": Vector2i(25, 20), "lineage": {}}, 0)
	var value: Dictionary = w.implements.records.values()[0]
	value.phase = "returning"
	value.position = Vector2(120, 120.5)
	w.combat.scan.index(w)
	return w

func implement_candidates() -> void:
	var w: RefCounted = implement_fixture()
	var value: Dictionary = w.implements.records.values()[0]
	var melee: Array[int] = []
	var impacts: Array[Dictionary] = w.implements.collect(w, 0, 100, melee)
	check(value.phase == "returning" and value.position == Vector2(120, 120.5) and value.touch.is_empty(), "Candidate collection committed phase/position/contact cooldown early")
	check(impacts.any(func(hit: Dictionary): return hit.get("source_implement", 0) == value.id), "Returning wall fixture had no later contact")
	w.implements.drop_owner(w, 1, 5)
	var stopped: Vector2 = value.position
	for event: Dictionary in impacts:
		if event.has("event"): w.implements.commit(event)
	check(value.phase == "dropped" and value.stopped_ms == 5 and value.position == stopped, "Late candidate overwrote an earlier owner stop")
	check(not w.implements.active_at(value.id, 20) and not w.implements.accept_contact(value.id, 2, 23), "Earlier death did not invalidate later contacts")
	check(value.touch.is_empty(), "Rejected contact consumed its cooldown")
	for death_first: bool in [true, false]:
		var boundary: RefCounted = implement_fixture()
		var tool: Dictionary = boundary.implements.records.values()[0]
		var events: Array[Dictionary] = boundary.implements.collect(boundary, 0, 100, melee)
		var wall: Dictionary = events.filter(func(event: Dictionary): return event.get("phase") == "dropped")[0]
		if death_first: boundary.implements.drop_owner(boundary, 1, wall.at_ms)
		for event: Dictionary in events:
			if event.has("event"): boundary.implements.commit(event)
		if not death_first: boundary.implements.drop_owner(boundary, 1, wall.at_ms + 1)
		var expected_x: float = minf(wall.position.x, 120.0 + float(Defs.ACTIONS.sword_dispatch.delivery.speed) * wall.at_ms / 1000.0)
		check(Vector2(tool.position).is_equal_approx(Vector2(expected_x, 120.5)) and tool.stopped_ms == wall.at_ms, "Owner death at/after the wall boundary changed the committed drop position/time")
	var caught: RefCounted = implement_fixture()
	caught.terrain.blocked[caught.Terrain.index(Vector2i(121, 120))] = 0
	caught.pages[0].positions[0] = Vector2(120.6, 120.5)
	caught.combat.previous[0][0] = caught.pages[0].positions[0]
	var carried: Dictionary = caught.implements.records.values()[0]
	var events: Array[Dictionary] = caught.implements.collect(caught, 0, 100, melee)
	var catch_event: Dictionary = events.filter(func(event: Dictionary): return event.get("phase") == "stowed")[0]
	caught.implements.commit(catch_event)
	caught.pages[0].positions[0] = Vector2(120.7, 120.5)
	caught.implements.drop_owner(caught, 1, catch_event.at_ms + 1)
	check(carried.phase == "dropped" and carried.position == caught.pages[0].positions[0], "Death after recovery dropped the implement at an obsolete flight position")

func _run() -> void:
	buffered_gates()
	implement_candidates()
	print("ACTION_TIMING_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
