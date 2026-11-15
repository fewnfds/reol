extends "res://tests/abilities_smoke.gd"
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Status = preload("res://scripts/sim/definitions/actions/status_def.gd")
func resources() -> void:
	var w: RefCounted = fixture("guardian")
	w.Equipment.rebuild(w, 1)
	w.pages[0].health[0] = 40
	var costs: Array = [{"kind": "pool", "id": "mana", "amount": 10}, {"kind": "health", "id": "", "amount": 25}, {"kind": "pool", "id": "hp", "amount": 20}]
	check(not Costs.pay(w, 1, costs) and w.pools.amount(1, "mana") == 100 and w.pages[0].health[0] == 40, "Aliases bypassed atomic multi-cost admission")
	check(w.combat.request(w, 1, "skill", Vector2.RIGHT) == "started" and w.pools.amount(1, "mana") == 82, "Pool cost not paid exactly once at start")
	w.step(80)
	check(w.defense.total(1, 80) == 32 and w.defense.guards.has(1), "Shield/guard did not execute at active frame")
	var data: Dictionary = Persistence.capture(w)
	var restored: RefCounted = Persistence.candidate(data, 0)
	check(restored != null and restored.pools.records == w.pools.records and restored.defense.shields == w.defense.shields, "Pool/shield restore changed balances")
	if restored != null:
		advance(w, 500)
		advance(restored, 500)
		check(w.pools.records == restored.pools.records, "Restored regen cadence differs")

func defense() -> void:
	var w: RefCounted = fixture()
	w.defense.shield(w, 1, 1, 12, 1000, 0)
	w.defense.shield(w, 1, 1, 15, 1500, 0)
	var hit: Dictionary = w.combat.damage(w, 2, 1, 20, 0)
	check(hit.damage == 0 and hit.absorbed == 20 and hit.broken.size() == 1 and w.defense.total(1, 0) == 7, "Layered shields did not consume in stable order")
	hit = w.combat.damage(w, 2, 1, 20, 0)
	check(hit.damage == 13 and hit.absorbed == 7, "Shield overflow lost actual HP loss")
	w.defense.guard(w, 1, 1.0, 100, 0, Vector2.RIGHT)
	var front: Dictionary = w.combat.damage(w, 2, 1, 10, 0, Vector2.RIGHT)
	var rear: Dictionary = w.combat.damage(w, 2, 1, 10, 0, Vector2.LEFT)
	check(front.damage == 0 and front.blocked == 10 and rear.damage == 10, "Directional block ignored facing")
	w.defense.shield(w, 1, 1, 100, 100, 0)
	check(w.combat.damage(w, 2, 1, 10, 100).damage == 10, "Shield survived its half-open expiry")
	w.pages[0].health[0] = 5
	var empty: Array[Dictionary] = []
	w.combat._begin_wave(empty)
	w.combat.damage(w, 2, 1, 10, 101)
	check(w.combat.heal(w, 1, 1, 30, 101).amount == 0, "Result-driven healing resurrected a pending fatal target")
	w.combat._close_wave(w)
	check(w.pages[0].modes[0] == w.Units.Mode.DEAD, "Pending death did not close with bucket")

func statuses() -> void:
	var w: RefCounted = fixture()
	var definition := Status.new()
	definition.id = "chill_stack"
	definition.stacking = "stack"
	definition.max_stacks = 3
	definition.magnitude = 0.8
	for count: int in 5: w.effects.add(w, 1, 2, 0, "", definition.values(), 0, 0)
	w.effects.prepare(w, 0)
	check(w.effects.records.size() == 1 and w.effects.records.values()[0].stacks == 3 and is_equal_approx(w.pages[0].move_scales[0], 0.512), "Status layering did not obey cap")
	definition.id = "root"
	definition.kind = "root"
	w.effects.add(w, 1, 2, 0, "", definition.values(), 0, 0)
	check(w.combat.request(w, 1, "step", Vector2.RIGHT) == "rooted" and w.combat.request(w, 1, "primary", Vector2.RIGHT) == "started", "Root did not separate movement from stationary attacks")
	w.release(1)
	definition.id = "armor_food"
	definition.kind = "modifier"
	definition.attribute = "armor"
	definition.modifier = "add"
	definition.magnitude = 4.0
	var first: int = w.effects.add(w, 1, 1, 0, "", definition.values(), 0, 0)
	definition.id = "armor_scale"
	definition.modifier = "multiply"
	definition.magnitude = 1.5
	w.effects.add(w, 1, 1, 0, "", definition.values(), 0, 0)
	w.effects.prepare(w, 0)
	check(w.pages[0].armor[0] == 6, "Attribute additions and factors did not rebuild")
	w.effects.remove(w, first, "dispelled", 0)
	w.effects.prepare(w, 0)
	check(w.pages[0].armor[0] == 0, "Removing a source left an attribute contribution")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Stacked modifiers failed restoration")

func _run() -> void:
	resources()
	defense()
	statuses()
	print("ACTION_RESOURCES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
