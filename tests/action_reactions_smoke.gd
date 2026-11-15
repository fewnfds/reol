extends "res://tests/abilities_smoke.gd"
const Reaction = preload("res://scripts/sim/definitions/actions/reaction_def.gd")
const Status = preload("res://scripts/sim/definitions/actions/status_def.gd")
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

func source_snapshots() -> void:
	# A body can be removed and its slot reused while its committed attack lives.
	var timed: RefCounted = fixture("stars")
	timed.objects.records[2]["ability_loadout"] = "stars"
	timed.pages[0].positions[1] = Vector2(120.5, 120.5)
	for row: int in [0, 2, 3]: timed.pages[0].positions[row] = Vector2(140.5, 120.5 + row * 3)
	timed.combat.request(timed, 2, "skill", Vector2.RIGHT)
	advance(timed, 100)
	timed.objects.records[2].base_stats["ranged"] = 80.0
	timed.Equipment.rebuild(timed, 2)
	advance(timed, 200)
	check(timed.combat.bolts.size() == 1 and timed.combat.bolts.values()[0].damage == 56, "Attack did not sample source power at actual delivery")
	timed.remove_actor(2)
	var replacement: int = timed.spawn_actor(125 * 512 + 120)
	timed.objects.records[replacement]["side"] = 0
	timed.objects.records[replacement]["base_stats"] = {"ranged": 5.0}
	timed.Equipment.rebuild(timed, replacement)
	timed.objects.records[replacement].autonomous = false
	check(timed.actor_slots[replacement] == 1, "Fixture did not reuse the removed source slot")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(timed), 0)
	check(restored != null, "In-flight removed-source snapshot was rejected")
	advance(timed, 360)
	check(timed.combat.bolts.size() == 5, "Removed producer cancelled committed timer split")
	for bolt: Dictionary in timed.combat.bolts.values():
		check(bolt.actor == 2 and bolt.side == 1 and bolt.damage == 28 and bolt.power == Vector2i(25, 80), "Split sampled removed/reused source or default power")
	if restored != null:
		advance(restored, 360)
		check(timed.combat.bolts == restored.combat.bolts, "Source snapshot changed after restore")
	var corrupt: Dictionary = Persistence.capture(timed)
	corrupt.domains.combat.bolts.values()[0].power = Vector2(-1, 80)
	check(Persistence.candidate(corrupt, 0) == null, "Invalid source-power snapshot was adopted")
	var counter: RefCounted = fixture()
	var hit: Dictionary = counter.combat.damage(counter, 1, 2, 1, 0)
	counter.reactions.damage_result(counter, hit, {"side": 0, "power": Vector2i(25, 80)})
	check(counter.reactions.pending.any(func(event: Dictionary): return event.event == "damaged" and event.side == 1 and event.power == Vector2i(25, 20)), "Defender reaction inherited the attacker's source snapshot")
	for remove_at: int in [110, 300]:
		var plague: RefCounted = fixture("plague")
		plague.objects.records[2]["ability_loadout"] = "plague"
		plague.objects.records[3]["side"] = 0
		plague.pages[0].positions[0] = Vector2(123.5, 120.5)
		plague.pages[0].positions[1] = Vector2(120.5, 120.5)
		plague.pages[0].positions[2] = Vector2(125.5, 120.5)
		plague.pages[0].positions[3] = Vector2(127.0, 120.5)
		plague.combat.request(plague, 2, "primary", Vector2.RIGHT)
		advance(plague, remove_at)
		plague.remove_actor(2)
		advance(plague, 300)
		check(plague.effects.records.values().any(func(entry: Dictionary): return entry.target == 1 and entry.side == 1), "Impact after source removal lost status faction")
		plague.combat.launch(4, Vector2(124.3, 120.5), Vector2(123.5, 120.5), 300, 10000)
		advance(plague, 400)
		check(plague.effects.records.values().any(func(entry: Dictionary): return entry.target == 3 and entry.side == 1), "Spread lost original source faction")
		var saved: RefCounted = Persistence.candidate(Persistence.capture(plague), 0)
		check(saved != null, "Removed-source propagation failed to restore")
		plague.combat.launch(1, Vector2(124.5, 120.5), Vector2(125.5, 120.5), 400, 10000)
		advance(plague, 500)
		check(not plague.combat.alive(plague, 3) and not plague.effects.records.values().any(func(entry: Dictionary): return entry.target == 4), "Second spread infected the removed source's ally")
		if saved != null:
			saved.combat.launch(1, Vector2(124.5, 120.5), Vector2(125.5, 120.5), 400, 10000)
			advance(saved, 500)
			check(plague.effects.records == saved.effects.records and plague.pages[0].health == saved.pages[0].health, "Propagation faction changed after restore")

func restored_rule_contract() -> void:
	var w: RefCounted = fixture()
	var rule := Reaction.new()
	rule.id = "restored_emission"
	rule.mode = "emit"
	rule.template = "fire_bolt"
	w.reactions.submit(w, {"event": "hit", "actor": 1, "target": 2, "at_ms": 0, "damage": 1, "position": w.pages[0].positions[1]}, [rule.values()])
	var original: Dictionary = Persistence.capture(w)
	check(Persistence.candidate(original, 0) != null, "Legal pending emission failed to restore")
	for mode: String in ["template", "scope"]:
		var data: Dictionary = original.duplicate(true)
		var restored_rule: Dictionary = data.domains.reactions.pending[0].rules[0]
		if mode == "template": restored_rule.template = "blink"
		else:
			var effect := Effect.new()
			effect.kind = "heal"
			effect.stage = "activation"
			restored_rule.mode = "bundle"
			restored_rule.bundle = [effect.values()]
		check(Persistence.candidate(data, 0) == null, "Unsupported restored reaction was adopted: " + mode)
	check(Persistence.capture(w) == original, "Rejected reaction changed the live world")
	var activation_counter: int = w.combat.next_activation
	check(w.combat.spawn_template(w, 1, "blink", w.pages[0].positions[0], Vector2.RIGHT, 0, 1.0, {}).is_empty() and w.combat.next_activation == activation_counter, "Emission bypassed full-action admission")
	var unsupported := Effect.new()
	unsupported.kind = "heal"
	unsupported.stage = "activation"
	rule.bundle.effects.append(unsupported)
	check(not rule.errors().is_empty(), "Reaction authoring accepted an unreachable activation effect")

func nested_and_projectile_edges() -> void:
	var original: Dictionary = Defs.ACTIONS
	var profiles: Dictionary = Defs.LOADOUTS
	var variants: Dictionary = original.duplicate(true)
	var mark := Status.new()
	mark.id = "nested_stack_mark"
	mark.kind = "modifier"
	mark.attribute = "armor"
	mark.magnitude = 1.0
	mark.stacking = "stack"
	mark.max_stacks = 2
	var effect := Effect.new()
	effect.kind = "status"
	effect.status = mark
	var on_hit := Reaction.new()
	on_hit.id = "nested_add_mark"
	on_hit.mode = "bundle"
	on_hit.recipient = "target"
	on_hit.bundle.effects.append(effect)
	var on_max := Reaction.new()
	on_max.id = "nested_shield"
	on_max.event = "stack_max"
	on_max.mode = "bundle"
	on_max.recipient = "target"
	var shield := Effect.new()
	shield.kind = "shield"
	shield.amount = 7
	shield.duration_ms = 500
	on_max.bundle.effects.append(shield)
	variants.fire_bolt.reactions = [on_hit.values(), on_max.values()]
	Defs.ACTIONS = variants
	var w: RefCounted = fixture()
	w.effects.add(w, 2, 1, 0, "fire_bolt", mark.values(), 0, 20, w.reactions.root(1, 0))
	w.reactions.submit(w, {"event": "hit", "actor": 1, "target": 2, "at_ms": 0, "position": w.pages[0].positions[1], "action": "fire_bolt", "damage": 1}, [on_hit.values()])
	w.reactions.resolve(w, 0, 0)
	check(w.reactions.pending.is_empty() and w.defense.total(2, 0) == 7, "Nested stack_max reaction escaped its chronological wave")
	Defs.ACTIONS = original
	var counter := Reaction.new()
	counter.id = "counter_projectile"
	counter.event = "damaged"
	counter.mode = "emit"
	counter.template = "fire_bolt"
	var loadouts: Dictionary = profiles.duplicate(true)
	loadouts.sword.reactions = [counter.values()]
	Defs.LOADOUTS = loadouts
	var c: RefCounted = fixture("sword")
	c.pages[0].positions[1] = Vector2(123.5, 120.5)
	var context: Dictionary = {"action": "fire_bolt", "incoming": Vector2.RIGHT, "position": c.pages[0].positions[0]}
	var damage: Dictionary = c.combat.damage(c, 2, 1, 20, 0, Vector2.RIGHT, 0, 0, 0.0, context)
	c.reactions.damage_result(c, damage, context)
	c.reactions.resolve(c, 0, 0)
	check(not c.combat.bolts.is_empty(), "Counterattack failed to emit")
	if not c.combat.bolts.is_empty():
		check(not c.combat.bolts.values()[0].passed.has(2), "Counterattack excluded the attacker from collision")
	advance(c, 220)
	check(c.pages[0].health[1] < 2000, "Counterattack projectile could not damage its attacker")
	Defs.LOADOUTS = profiles
	var h: RefCounted = fixture("frost")
	h.combat.scan.index(h)
	h.combat.spawn_template(h, 1, "frost_seeker", h.pages[0].positions[0], Vector2.RIGHT, 0, 1.0, h.reactions.root(1, 0), 2)
	var homing: Dictionary = h.combat.bolts.values()[0]
	h.combat.Projectiles.steer(h.combat, h, 50)
	check(homing.target != 2, "Homing child locked onto a recipient it cannot hit")
	var zero: Dictionary = original.duplicate(true)
	zero.guard_stance.windup = 0
	Defs.ACTIONS = zero
	var g: RefCounted = fixture("guardian")
	g.combat.request(g, 1, "skill", Vector2.RIGHT)
	g.combat.prepare(g, 0)
	check(not g.combat.states[1].fired and g.defense.total(1, 0) == 0, "Zero-windup direct effect bypassed contact-wave settlement")
	advance(g, 16)
	check(g.combat.states[1].fired and g.defense.total(1, 16) == 32, "Zero-windup direct effect failed to settle once in its contact wave")
	advance(g, 32)
	check(g.defense.total(1, 32) == 32, "Direct effect was delivered twice")
	Defs.ACTIONS = original

func _run() -> void:
	nested_and_projectile_edges()
	splitting()
	combinations()
	bounded_and_script()
	ordering_and_extension()
	zero_direction_producer()
	source_snapshots()
	restored_rule_contract()
	print("ACTION_REACTIONS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
