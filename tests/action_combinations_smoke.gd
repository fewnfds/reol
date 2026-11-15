extends "res://tests/abilities_smoke.gd"
## Complete resource loops and simultaneous domain-owned lifetimes.
func melee_loop() -> void:
	var w: RefCounted = fixture("bloodblade")
	w.pages[0].positions[1] = Vector2(121.5, 120.5)
	w.pages[0].health[0] = 1000
	check(w.combat.request(w, 1, "skill2", Vector2.RIGHT) == "insufficient_resource" and not w.combat.cooldowns.has(1), "Empty rage spent cooldown")
	for cast: int in 3:
		check(w.combat.request(w, 1, "primary", Vector2.RIGHT) == "started", "Melee combo failed admission")
		advance(w, (cast + 1) * 450)
	check(w.pools.amount(1, "rage") >= 21 and w.pages[0].health[0] > 1000, "Three contacts did not fund burst and sustain")
	advance(w, 1450)
	var before: int = w.pools.amount(1, "rage")
	check(w.combat.request(w, 1, "skill2", Vector2.RIGHT) == "started" and w.pools.amount(1, "rage") == before - 21, "Rage finisher did not pay once")
	advance(w, 2000)
	check(w.combat.request(w, 1, "skill", Vector2.RIGHT) == "started", "Guard slot unavailable")
	advance(w, 2100)
	check(not w.defense.shields.is_empty() and w.defense.guards.has(1), "Guard slot lost its direct defense")
	same_after_restore(w, 2400, "bloodblade defense and resource loop")
	check(w.combat.request(w, 1, "skill3", Vector2.RIGHT) == "started", "Recovery slot unavailable")
	advance(w, 2700)

func ranged_loop_and_restore() -> void:
	var w: RefCounted = fixture("barrage")
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 350)
	check(w.combat.request(w, 1, "skill", Vector2.RIGHT) == "started", "Ember slot unavailable")
	advance(w, 850)
	check(w.combat.request(w, 1, "skill2", Vector2.RIGHT, Vector2.ZERO, -1, w.pages[0].positions[1]) == "started", "Control slot unavailable")
	advance(w, 1200)
	check(w.combat.request(w, 1, "skill3", Vector2.DOWN, Vector2.ZERO, -1, Vector2(120.5, 122.5)) == "started", "Point blink slot unavailable")
	advance(w, 1300)
	check(w.pools.amount(1, "mana") < 70 and w.pages[0].positions[0].distance_to(Vector2(120.5, 122.5)) < 0.01, "Ranged costs or blink did not commit")
	same_after_restore(w, 2200, "ranged fields, split lineage and pools")

func mixed_lifetimes() -> void:
	var w: RefCounted = fixture("companions")
	w.combat.request(w, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(121.5, 121.5))
	advance(w, 400)
	w.combat.request(w, 1, "skill2", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(120.5, 121.5))
	advance(w, 850)
	w.combat.request_template(w, 1, "sword_array", Vector2.RIGHT, w.elapsed_ms, w.pages[0].positions[1])
	advance(w, 1200)
	w.combat.request_template(w, 1, "guard_stance", Vector2.RIGHT, w.elapsed_ms, w.pages[0].positions[0])
	advance(w, 1500)
	w.defense.shield(w, 1, 1, 12, 2400, w.elapsed_ms)
	w.combat.spawn_template(w, 1, "plague_needle", w.pages[0].positions[0], Vector2.RIGHT, w.elapsed_ms, 1.0, w.reactions.root(1, 0))
	w.combat.request_template(w, 1, "star_timed", Vector2.RIGHT, w.elapsed_ms, w.pages[0].positions[1])
	advance(w, 1650)
	check(w.entities.records.size() == 2 and w.implements.records.size() == 2 and not w.combat.bolts.is_empty() and not w.defense.shields.is_empty(), "Mixed state fixture did not contain simultaneous processes")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Mixed lifetimes could not restore")
	if restored == null: return
	advance(w, 2500)
	advance(restored, 2500)
	for field: String in ["entities", "implements", "effects", "pools"]:
		check(w.get(field).records == restored.get(field).records, "Mixed restore changed " + field)
	check(w.reactions.chains == restored.reactions.chains and w.combat.bolts == restored.combat.bolts and w.pages[0].health == restored.pages[0].health, "Mixed restore changed causal future")

func accepted_cancel_owns_recovery() -> void:
	var original: Dictionary = Defs.ACTIONS
	var variants: Dictionary = original.duplicate(true)
	variants.enemy_heavy.step_miss = 900
	Defs.ACTIONS = variants
	var w: RefCounted = fixture("bloodblade")
	w.combat.request_template(w, 1, "enemy_heavy", Vector2.UP, 0, w.pages[0].positions[0])
	advance(w, 900)
	check(w.combat.request(w, 1, "step", Vector2.RIGHT) == "started", "Legal cancel did not replace committed recovery")
	advance(w, 1200)
	var result: Dictionary = w.combat.damage(w, 2, 1, 1, w.elapsed_ms, Vector2.LEFT, 0, 50, 0.0, {"heavy_hit": true, "punish_ms": 260, "group_ms": 0})
	check(not result.get("off_balance", false), "Finished replacement inherited the canceled action's punishable recovery")
	Defs.ACTIONS = original

func _run() -> void:
	melee_loop()
	ranged_loop_and_restore()
	mixed_lifetimes()
	accepted_cancel_owns_recovery()
	print("ACTION_COMBINATIONS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
