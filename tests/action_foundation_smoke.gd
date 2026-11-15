extends "res://tests/abilities_smoke.gd"
## Cross-host admission, termination identity and detached payload regression cases.
func admission() -> void:
	var w: RefCounted = fixture("bow")
	var source: int = w.source_objects[0]
	w.pages[0].positions[0] = w.Terrain.center(w.objects.records[source].tile)
	check(w.begin_interaction(1, {"kind": "take", "target": source, "item": "wood", "amount": 1}) == "accepted", "Real work not admitted")
	var before: Dictionary = w.gate.current(1)
	w.combat.cooldowns[1] = {"shot": 1000}
	check(w.combat.request(w, 1, "primary", Vector2.RIGHT) == "cooldown" and w.gate.current(1) == before and w.actions.has(1), "Failed initial precheck destroyed work")
	w.combat.cooldowns[1].clear()
	check(w.combat.request(w, 1, "primary", Vector2.RIGHT) == "started" and not w.actions.has(1) and w.gate.current(1).domain == "combat", "Combat did not take over work")
	var activation: int = w.combat.states[1].activation
	w.settle(1, 0, before)
	check(w.combat.states[1].activation == activation, "Stale work candidate replaced a combat run")
	check(w.begin_interaction(1, {"kind": "take", "target": source, "item": "wood", "amount": 1}) == "action_committed", "Internal interaction bypassed action commitment")
	w.livelihood.after_action(w, 1, 0)
	check(w.gate.current(1).domain == "combat", "Livelihood bypassed shared gate")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.gate.current(1) == w.gate.current(1), "Bindings not rebuilt from domain hosts")
	w.end_run(1, 0)
	var count: int = w.outcomes.size()
	w.end_run(1, 0)
	check(count == w.outcomes.size(), "Run termination repeated")

func payload_and_chain() -> void:
	var w: RefCounted = fixture("sword")
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 310)
	check(not w.combat.states.has(1) and w.combat.chains.has(1), "Natural recovery erased combo continuation")
	check(w.combat.request(w, 1, "primary", Vector2.RIGHT) == "started" and w.combat.states[1].kind == "slash_2", "Post-recovery input did not continue combo")
	var shot: RefCounted = fixture()
	shot.combat.launch(1, Vector2(120.5, 120.5), Vector2(130, 120.5), 0)
	var saved: Dictionary = Persistence.capture(shot)
	saved.domains.combat.bolts[1].payload = [{"kind": "bogus"}]
	check(Persistence.candidate(saved, 0) == null, "Malformed independent payload was restored")
	var ghost: Dictionary = Persistence.capture(shot)
	ghost.domains.world.reservations[shot.source_objects[0]] = 1
	check(Persistence.candidate(ghost, 0) == null, "Reservation without owning action was restored")

func _run() -> void:
	admission()
	payload_and_chain()
	print("ACTION_FOUNDATION_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
