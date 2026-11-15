extends "res://tests/abilities_smoke.gd"
const Reaction = preload("res://scripts/sim/definitions/actions/reaction_def.gd")
const Effect = preload("res://scripts/sim/definitions/actions/effect_def.gd")
func splitting() -> void:
	var w: RefCounted = fixture("stars")
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 270)
	check(w.pages[0].health[1] < 2000 and w.combat.bolts.size() >= 3, "Hit did not emit independent fragment payloads")
	var chain: int = w.combat.bolts.values()[0].lineage.chain
	for bolt: Dictionary in w.combat.bolts.values():
		check(bolt.lineage.chain == chain and bolt.payload == Defs.ACTIONS.star_fragment.payload and bolt.passed.has(2), "Sibling fragments lost budget/payload/exclusion")
	same_after_restore(w, 700, "split descendants")
	var timed: RefCounted = fixture("stars")
	for row: int in range(1, 4): timed.pages[0].positions[row] += Vector2(20, 0)
	timed.combat.request(timed, 1, "skill", Vector2.RIGHT)
	timed.step(500)
	check(timed.combat.bolts.size() == 5, "Timer split did not consume parent and emit five children")
	for bolt: Dictionary in timed.combat.bolts.values():
		check(bolt.born_ms == 340 and Vector2(bolt.position).distance_to(Vector2(123.14, 120.5)) <= 2.9, "Child projectile swept time before its birth")

func combinations() -> void:
	var blood: RefCounted = fixture("bloodblade")
	blood.Equipment.rebuild(blood, 1)
	blood.pages[0].health[0] = 1000
	blood.pages[0].positions[1] = Vector2(121.5, 120.5)
	blood.defense.shield(blood, 2, 2, 1000, 1000, 0)
	blood.combat.request(blood, 1, "primary", Vector2.RIGHT)
	advance(blood, 300)
	check(blood.pages[0].health[0] == 1000 and blood.pools.amount(1, "rage") == 0, "Shield contact fabricated leech or rage")
	blood.defense.shields.clear()
	blood.combat.request(blood, 1, "primary", Vector2.RIGHT)
	advance(blood, 600)
	check(blood.pages[0].health[0] > 1000 and blood.pools.amount(1, "rage") == 7, "Actual HP loss did not leech and restore rage")
	var plague: RefCounted = fixture("plague")
	plague.pages[0].positions[2] = Vector2(125.0, 120.5)
	plague.combat.request(plague, 1, "primary", Vector2.RIGHT)
	advance(plague, 300)
	check(not plague.effects.records.is_empty(), "Plague mark missing")
	plague.combat.launch(3, Vector2(124.0, 120.5), Vector2(123.0, 120.5), plague.elapsed_ms, 10000)
	advance(plague, 380)
	check(not plague.combat.alive(plague, 2) and plague.effects.records.values().any(func(entry: Dictionary): return entry.target == 3 and entry.status_id == "plague"), "Host death did not spread its creator's status")
	same_after_restore(plague, 1000, "propagation chain")

func bounded_and_script() -> void:
	var w: RefCounted = fixture()
	var rule := Reaction.new()
	rule.id = "finite_followup"
	rule.mode = "bundle"
	rule.recipient = "target"
	rule.chain_limit = 2
	var effect := Effect.new()
	effect.kind = "damage"
	effect.magnitude = 0.2
	rule.bundle.effects.append(effect)
	var lineage: Dictionary = w.reactions.root(1, 0)
	var local_rules: Array = [rule.values()]
	for index: int in 5: w.reactions.submit(w, {"event": "hit", "actor": 1, "target": 2, "at_ms": 0, "activation": 0, "damage": 10, "position": w.pages[0].positions[1], "direction": Vector2.RIGHT, "lineage": lineage}, local_rules)
	w.step(50)
	check(w.reactions.chains.get(lineage.chain, {}).get("remaining", 0) <= 62 and w.reactions.instances["1:finite_followup"].count == 5, "Sibling events did not share a finite rule budget")
	var script_state: Dictionary = w.reactions.Marks.initial_state()
	check(w.reactions.Marks.valid(script_state) and not w.reactions.Marks.valid({"version": 2}), "Trusted extension accepted undeclared state")

func ordering_and_extension() -> void:
	var w: RefCounted = fixture("sequence")
	w.pages[0].positions[2] = Vector2(125.5, 120.5)
	w.pages[0].positions[3] = Vector2(130.5, 123.5)
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 260)
	check(w.effects.records.size() == 1, "First piercer contact did not retain its own mark")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "In-flight script activation failed to restore")
	advance(w, 400)
	if restored != null:
		advance(restored, 400)
		check(w.reactions.script_states == restored.reactions.script_states and w.pages[0].health == restored.pages[0].health, "Trusted script changed after restore")
	check(w.reactions.script_states.get("1:owned_mark_burst", {}).get("detonations", 0) == 1 and w.pages[0].health[1] < 1980 and w.pages[0].health[2] < 1980, "Piercer did not detonate two targets from its own activation")
	var frost: RefCounted = fixture("binder")
	for cast: int in 3:
		frost.combat.request(frost, 1, "primary", Vector2.RIGHT)
		advance(frost, (cast + 1) * 450)
	check(frost.effects.records.values().any(func(entry: Dictionary): return entry.target == 2 and entry.kind == "root"), "Cross-cast frost stacks did not trigger bounded root")
	var fifo: RefCounted = fixture()
	fifo.step(50)
	var chain: Dictionary = fifo.reactions.root(1, 0)
	var rule := Reaction.new()
	rule.id = "full_action"
	rule.mode = "request"
	rule.template = "fire_bolt"
	for at: int in [10, 35]:
		var event: Dictionary = {"event": "hit", "actor": 1, "target": 2, "at_ms": at, "activation": 0, "damage": 1, "position": fifo.pages[0].positions[1], "direction": Vector2.RIGHT, "lineage": chain}
		fifo.reactions.requests.append({"at_ms": 50, "key": "1:full_action", "event": event, "rule": rule.values()})
		rule.template = "frost_seeker"
	var root_counter: int = fifo.reactions.next_chain
	fifo.reactions.prepare(fifo, 50)
	check(fifo.combat.states.get(1, {}).get("kind") == "fire_bolt" and fifo.combat.intents.is_empty() and fifo.reactions.next_chain == root_counter, "Full-action admission overtook FIFO, buffered an unwanted skill or allocated a fresh root")
	var malformed: Dictionary = Persistence.capture(w)
	malformed.domains.reactions.pending = [{"actor": 1, "at_ms": w.elapsed_ms, "event": "hit", "lineage": "invalid", "rules": [], "position": Vector2.ZERO}]
	check(Persistence.candidate(malformed, 0) == null, "Corrupt reaction lineage was adopted")

func zero_direction_producer() -> void:
	var w: RefCounted = fixture()
	w.pages[0].positions[1] = w.pages[0].positions[0]
	var rule := Reaction.new()
	rule.id = "center_followup"
	rule.mode = "emit"
	rule.template = "fire_bolt"
	var result: Dictionary = w.combat.damage(w, 1, 2, 1, 0, Vector2.ZERO, 0, 0, 0.0, {"periodic": true, "group_ms": 0})
	w.reactions.damage_result(w, result, {"incoming": Vector2.ZERO, "rules": [rule.values()], "position": w.pages[0].positions[1]})
	w.step(1)
	check(not w.combat.bolts.is_empty() and w.combat.bolts.values()[0].velocity.length_squared() > 0, "Center contact consumed a producer rule but emitted no directional child")

func _run() -> void:
	splitting()
	combinations()
	bounded_and_script()
	ordering_and_extension()
	zero_direction_producer()
	print("ACTION_REACTIONS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
