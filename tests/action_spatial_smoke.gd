extends "res://tests/abilities_smoke.gd"
func companions() -> void:
	var w: RefCounted = fixture("companions")
	var population: int = w.actor_count
	w.combat.request(w, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(121.5, 121.5))
	advance(w, 220)
	check(w.entities.records.size() == 1 and w.actor_count == population and w.actor_slots.size() == population + 1, "Temporary body polluted population or failed to spawn")
	if w.entities.records.is_empty(): return
	var id: int = w.entities.records.keys()[0]
	var slot: int = w.actor_slots[id]
	check(w.pages[slot / 256].needs_enabled[slot % 256] == 0 and not w.objects.records[id].autonomous and not w.work_runs.has(id), "Companion entered villager lifecycle")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Companion body failed restoration")
	advance(w, 800, false)
	check(w.combat.engagements.has(id) or w.combat.states.has(id), "Companion did not independently acquire an enemy")
	w.entities.remove(w, id, w.elapsed_ms)
	check(w.actor_count == population and not w.actor_slots.has(id), "Companion cleanup changed population")

func auras_and_receiver() -> void:
	var w: RefCounted = fixture("totems")
	w.combat.request(w, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(121.5, 121.5))
	advance(w, 750)
	check(w.entities.records.size() == 1 and w.pages[0].armor[0] == 3, "Totem did not grant its own modifier contribution")
	if w.entities.records.is_empty(): return
	var id: int = w.entities.records.keys()[0]
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Aura membership failed restoration")
	w.pages[0].positions[0] += Vector2(8, 0)
	advance(w, 1250)
	check(w.pages[0].armor[0] == 0, "Leaving aura retained source contribution")
	var point: Vector2 = w.combat.position(w, id)
	w.combat.launch(2, point + Vector2(1.2, 0), point, w.elapsed_ms, 1000)
	advance(w, 1400)
	check(not w.entities.records.has(id) and not w.objects.records.has(id), "Projectile could not destroy a static receiver")

func blink_and_implements() -> void:
	var w: RefCounted = fixture("companions")
	var origin: Vector2 = w.pages[0].positions[0]
	check(w.combat.request(w, 1, "step", Vector2.RIGHT, Vector2.ZERO, -1, origin + Vector2(4, 0)) == "started", "Blink not admitted")
	advance(w, 100)
	check(w.pages[0].positions[0].distance_to(origin + Vector2(4, 0)) < 0.01 and not w.combat.Defs.evading(w.combat.states.get(1, {}), w.elapsed_ms), "Blink position failed or granted hidden evade")
	var swords: RefCounted = fixture("sword_array")
	swords.combat.request(swords, 1, "primary", Vector2.RIGHT)
	advance(swords, 1000)
	check(swords.implements.records.size() == 2 and swords.combat.shots > 0 and swords.implements.records.values().all(func(entry: Dictionary): return entry.phase == "orbiting"), "Independent orbiting producers failed")
	check(Persistence.candidate(Persistence.capture(swords), 0) != null, "Orbiting implements failed restoration")
	swords.implements.records.values()[0].hp -= 5
	var hp: int = swords.implements.records.values()[0].hp
	swords.implements.recall(swords, 1)
	advance(swords, 1600)
	check(swords.implements.records.size() == 2 and swords.implements.records.values()[0].hp == hp and swords.implements.records.values().all(func(entry: Dictionary): return entry.phase == "stowed"), "Recall duplicated or repaired implements")

func lifecycle_edges() -> void:
	var w: RefCounted = fixture("totems")
	w.combat.request(w, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(121.5, 121.5))
	advance(w, 750)
	if w.entities.records.is_empty(): check(false, "Lifecycle totem missing"); return
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Aura candidate missing")
	if restored != null:
		advance(restored, 1250)
		check(restored.pages[0].armor[0] == 3, "Restoration lost first aura pulse")
	var id: int = w.entities.records.keys()[0]
	var until: int = w.entities.records[id].until_ms
	w.step(until - w.elapsed_ms)
	check(w.entities.records.is_empty() and w.pages[0].armor[0] == 0 and Persistence.candidate(Persistence.capture(w), 0) != null, "Exact entity expiry left orphaned contributions")
	var owned: RefCounted = fixture("totems")
	owned.combat.request(owned, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(121.5, 121.5))
	advance(owned, 750)
	owned.kill(1)
	check(owned.entities.records.is_empty() and Persistence.candidate(Persistence.capture(owned), 0) != null, "Owner death left aura members or producers")
	var swords: RefCounted = fixture("sword_array")
	swords.pages[0].positions[0] = Vector2(0.5, 120.5)
	swords.combat.request(swords, 1, "primary", Vector2.LEFT)
	advance(swords, 300)
	check(Persistence.candidate(Persistence.capture(swords), 0) != null, "Edge deployment created out-of-map hover state")
	var broken: Dictionary = swords.implements.records.values()[0]
	swords.implements.hit(swords, broken.id, 10000, swords.elapsed_ms)
	check(swords.implements.readiness(1, "sword_array").is_empty() and not swords.implements.active_at(broken.id, swords.elapsed_ms), "One broken slot disabled its sibling or swallowed same-time attacks")
	var pages: RefCounted = fixture("companions")
	for index: int in 252:
		var actor: int = pages.spawn_actor(pages.terrain.nearest_open(pages.Terrain.index(Vector2i(200 + index % 16, 200 + index / 16))))
		pages.objects.records[actor].autonomous = false
	check(pages.body_count == 256, "Expansion fixture failed")
	pages.combat.request(pages, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(121.5, 121.5))
	pages.step(220)
	check(pages.pages.size() == 2 and pages.actor_count == 256 and Persistence.candidate(Persistence.capture(pages), 0) != null, "Companion birth across a body page lost identity or population")

func controlled_and_defined_reactions() -> void:
	# Definition variants exercise hosts that read rules from the catalog rather
	# than duplicating them in each persistent entity/implement record.
	var original: Dictionary = Defs.ACTIONS
	var variants: Dictionary = original.duplicate(true)
	variants.wolf_call.reactions = variants.star_arrow.reactions.duplicate(true)
	variants.sword_array.reactions = variants.star_arrow.reactions.duplicate(true)
	Defs.ACTIONS = variants
	var wolf: RefCounted = fixture("companions")
	wolf.combat.request(wolf, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(121.5, 121.5))
	advance(wolf, 220)
	if not wolf.entities.records.is_empty():
		var id: int = wolf.entities.records.keys()[0]
		var root: Resource = load("res://data/definitions/actions/frost_bind.tres").duplicate(true)
		root.duration_ms = 1800
		wolf.effects.add(wolf, id, 1, 0, "", root.values(), wolf.elapsed_ms, 0)
		advance(wolf, 1500)
		check(wolf.effects.has_kind(id, "root", wolf.elapsed_ms) and Persistence.candidate(Persistence.capture(wolf), 0) != null, "Controlled companion stalled its cadence or rejected definition-owned rules")
		var rule: Resource = preload("res://scripts/sim/definitions/actions/reaction_def.gd").new()
		rule.id = "pending_companion_action"
		rule.mode = "request"
		rule.template = "fire_bolt"
		wolf.reactions.submit(wolf, {"event": "hit", "actor": id, "target": 2, "at_ms": wolf.elapsed_ms, "position": wolf.combat.position(wolf, id)}, [rule.values()])
		wolf.reactions.resolve(wolf, wolf.elapsed_ms, wolf.elapsed_ms)
		check(not wolf.reactions.requests.is_empty(), "Companion did not queue its full action")
		wolf.entities.remove(wolf, id, wolf.elapsed_ms)
		check(wolf.reactions.requests.is_empty() and Persistence.candidate(Persistence.capture(wolf), 0) != null, "Removed companion retained an unstarted body action")
		wolf.reactions.submit(wolf, {"event": "hit", "actor": id, "target": 2, "at_ms": wolf.elapsed_ms, "position": Vector2(121.5, 121.5)}, [rule.values()])
		wolf.reactions.resolve(wolf, wolf.elapsed_ms, wolf.elapsed_ms)
		check(wolf.reactions.requests.is_empty(), "Posthumous result queued a new full body action")
	var swords: RefCounted = fixture("sword_array")
	swords.combat.request(swords, 1, "primary", Vector2.RIGHT)
	advance(swords, 300)
	check(not swords.implements.records.is_empty() and Persistence.candidate(Persistence.capture(swords), 0) != null, "Implement with definition-owned reactions could not restore")
	var corrupt: Dictionary = Persistence.capture(swords)
	corrupt.domains.implements.records.values()[0].owner = swords.source_objects[0]
	check(Persistence.candidate(corrupt, 0) == null, "Deployed implement accepted a non-body owner")
	Defs.ACTIONS = original

func _run() -> void:
	companions()
	auras_and_receiver()
	blink_and_implements()
	lifecycle_edges()
	controlled_and_defined_reactions()
	print("ACTION_SPATIAL_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
