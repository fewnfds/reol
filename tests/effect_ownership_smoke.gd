extends "res://tests/abilities_smoke.gd"
const Status = preload("res://scripts/sim/definitions/actions/status_def.gd")
const Reaction = preload("res://scripts/sim/definitions/actions/reaction_def.gd")
const Effect = preload("res://scripts/sim/definitions/actions/effect_def.gd")

func defensive_sources() -> void:
	var original: Dictionary = Defs.LOADOUTS
	for event: String in ["damaged", "blocked", "shield_broken"]:
		var profiles: Dictionary = original.duplicate(true)
		var mark := Status.new()
		mark.id = "plague"
		mark.kind = "dot"
		mark.period_ms = 500
		var effect := Effect.new()
		effect.kind = "status"
		effect.status = mark
		var rule := Reaction.new()
		rule.id = "defender_mark"
		rule.event = event
		rule.mode = "bundle"
		rule.recipient = "target"
		rule.bundle.effects.append(effect)
		profiles.sword.reactions = [rule.values()]
		Defs.LOADOUTS = profiles
		var w: RefCounted = fixture("plague")
		w.objects.records[2]["ability_loadout"] = "sword"
		w.combat.request(w, 1, "primary", Vector2.UP)
		var activation: int = w.combat.states[1].activation
		if event == "blocked": w.defense.guard(w, 2, 0.8, 1000, 0, Vector2.LEFT)
		if event == "shield_broken": w.defense.shield(w, 2, 2, 5, 1000, 0)
		var result: Dictionary = w.combat.damage(w, 1, 2, 20, 0, Vector2.LEFT, activation)
		w.reactions.damage_result(w, result, {"action": "plague_needle", "incoming": Vector2.LEFT, "rules": Defs.ACTIONS.plague_needle.reactions})
		var responses: Array = w.reactions.pending.filter(func(value: Dictionary): return value.event == event)
		check(responses.size() == 1, event + ": defense result was not generated")
		if responses.is_empty(): continue
		var response: Dictionary = responses[0]
		check(response.actor == 2 and response.action.is_empty() and response.activation == 0 and response.cause.action == "plague_needle" and response.cause.activation == activation, event + ": trigger identity became effect ownership")
		check(response.side == 1 and response.lineage == w.reactions.pending[0].lineage and w.reactions.valid_event(response, w), event + ": defender source/budget or cause contract changed")
		check(Persistence.candidate(Persistence.capture(w), 0) != null, event + ": pending cause could not restore")
		w.reactions.resolve(w, 0, 0)
		check(w.effects.records.size() == 1, event + ": defensive status missing")
		if w.effects.records.is_empty(): continue
		var status: Dictionary = w.effects.records.values()[0]
		check(status.source == 2 and status.target == 1 and status.ability.is_empty() and status.activation == 0 and status.rules.is_empty() and status.cause == response.cause, event + ": passive status inherited attack rules or lost cause")
		var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
		check(restored != null and restored.effects.records == w.effects.records, event + ": owned status changed after restore")
		var corrupted: Dictionary = Persistence.capture(w)
		corrupted.domains.effects.records.values()[0].cause["nested"] = response.cause
		check(Persistence.candidate(corrupted, 0) == null, event + ": nested cause history was accepted")
	Defs.LOADOUTS = original

func stun_spec(id: String, duration: int) -> Dictionary:
	var spec := Status.new()
	spec.id = id
	spec.kind = "stun"
	spec.duration_ms = duration
	return spec.values()

func independent_control() -> void:
	var w: RefCounted = fixture()
	var long_id: int = w.effects.add(w, 2, 1, 0, "", stun_spec("long_stun", 300), 0, 0)
	advance(w, 10)
	var short_id: int = w.effects.add(w, 2, 3, 0, "", stun_spec("short_stun", 50), 10, 0)
	check(w.effects.records[long_id].until_ms == 300 and w.effects.records[short_id].until_ms == 60 and w.combat.status[2].stun_until == 300, "Short control inherited the longer source deadline")
	advance(w, 20)
	w.effects.remove(w, long_id, "dispelled", 20)
	check(w.combat.status[2].stun_until == 60 and not w.combat.status[2].has("ready_ms"), "Removing long status kept unrelated control or implicit hit recovery")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.effects.records == w.effects.records and restored.combat.status == w.combat.status, "Independent control deadlines changed after restore")
	var corrupted: Dictionary = Persistence.capture(w)
	corrupted.domains.combat.status[2].stun_until = 300
	check(Persistence.candidate(corrupted, 0) == null, "Aggregate control deadline disagreed with its saved source facts")
	advance(w, 61)
	check(not w.effects.has_kind(2, "stun", 61) and w.combat.status[2].stun_until <= 61, "Natural expiry retained a control contribution")
	for reason: String in ["left_aura", "source_removed", "replaced"]:
		var removed: RefCounted = fixture()
		var id: int = removed.effects.add(removed, 2, 1, 0, "", stun_spec("removed_stun", 300), 0, 0)
		advance(removed, 20)
		var used: int = removed.combat.status[2].stun_used
		removed.effects.remove(removed, id, reason, 20)
		check(removed.combat.status[2].stun_until == 20 and removed.combat.status[2].stun_used == used, reason + ": early removal retained stun or refunded the control budget")
	var dead: RefCounted = fixture()
	dead.effects.add(dead, 2, 1, 0, "", stun_spec("dead_recipient_stun", 300), 0, 0)
	dead.kill(2, 0)
	check(Persistence.candidate(Persistence.capture(dead), 0) != null, "Removing a dead recipient left control aggregation inconsistent with its removed status sources")

func hit_control_and_recovery() -> void:
	var w: RefCounted = fixture()
	w.combat.damage(w, 2, 1, 1, 0, Vector2.LEFT, 0, 200, 0.4)
	var hit: Dictionary = w.combat.status[1].duplicate(true)
	advance(w, 10)
	var status: int = w.effects.add(w, 1, 3, 0, "", stun_spec("separate_status", 300), 10, 0)
	advance(w, 20)
	w.effects.remove(w, status, "source_removed", 20)
	check(w.combat.status[1].stun_until == 200 and w.combat.status[1].hit_stun_until == 200 and w.combat.status[1].ready_ms == hit.ready_ms, "Status removal discarded hit control or altered its recovery")
	check(w.combat.status[1].push_until == hit.push_until and w.combat.status[1].push == hit.push, "Status removal erased residual knockback")
	var reverse: RefCounted = fixture()
	var long_status: int = reverse.effects.add(reverse, 1, 3, 0, "", stun_spec("long_status", 300), 0, 0)
	advance(reverse, 10)
	reverse.combat.damage(reverse, 2, 1, 1, 10, Vector2.LEFT, 0, 50, 0.2)
	advance(reverse, 20)
	reverse.effects.remove(reverse, long_status, "dispelled", 20)
	check(reverse.combat.status[1].stun_until == 60 and reverse.combat.status[1].hit_stun_until == 60 and reverse.combat.status[1].ready_ms == 240, "A short hit inherited the longer status deadline or recovery")
	var budget: RefCounted = fixture()
	var id: int = budget.effects.add(budget, 2, 1, 0, "", stun_spec("budget_stun", 350), 0, 0)
	advance(budget, 10)
	budget.effects.remove(budget, id, "dispelled", 10)
	var limited: int = budget.effects.add(budget, 2, 3, 0, "", stun_spec("limited_stun", 300), 10, 0)
	check(limited > 0 and budget.effects.records[limited].until_ms == 60 and budget.combat.status[2].stun_used == Defs.CONTROL_BUDGET_MS, "Independent admission escaped the shared control budget")
	var protected: int = budget.effects.add(budget, 2, 4, 0, "", stun_spec("protected_stun", 100), 10, 0)
	check(protected == 0, "Exhausted control budget admitted another status")
	var heavy: RefCounted = fixture()
	heavy.objects.records[2]["ability_loadout"] = "heavy"
	heavy.combat.request(heavy, 2, "primary", Vector2.LEFT)
	var ready: int = heavy.combat.status[2].ready_ms
	advance(heavy, 651)
	var interrupted: int = heavy.effects.add(heavy, 2, 1, 0, "", stun_spec("post_stun", 90), 651, 0)
	check(interrupted > 0, "Recovery control fixture was armored outside its active commitment")
	heavy.effects.remove(heavy, interrupted, "dispelled", 651)
	check(heavy.combat.status[2].ready_ms == ready, "Removing control erased independent committed recovery")

func aura_contributions() -> void:
	var original: Dictionary = Defs.ACTIONS
	var variants: Dictionary = original.duplicate(true)
	var second: Dictionary = variants.radiant_totem.entity.aura[0].duplicate(true)
	# Equal status IDs still represent two independently owned definition slots.
	second.status.magnitude = 5.0
	variants.radiant_totem.entity.aura.append(second)
	Defs.ACTIONS = variants
	var w: RefCounted = fixture("totems")
	w.combat.request(w, 1, "skill", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(121.5, 121.5))
	advance(w, 750)
	check(w.entities.records.size() == 1 and w.effects.records.size() == 2 and w.pages[0].armor[0] == 8, "Equal status IDs merged independent aura contributions")
	if w.entities.records.is_empty() or w.effects.records.size() != 2: Defs.ACTIONS = original; return
	var entity: int = w.entities.records.keys()[0]
	var slots: Array = w.entities.records[entity].members[1]
	var survivor: Dictionary = w.effects.records[slots[1]].duplicate(true)
	w.effects.apply_bundle(w, 1, 2, 0, "", [{"kind": "dispel"}], 750, 0)
	check(w.pages[0].armor[0] == 8 and w.effects.records.size() == 2, "Ordinary cleanse removed externally maintained aura contributions")
	w.effects.remove(w, slots[0], "contribution_removed", 750)
	check(slots[0] == 0 and slots[1] > 0 and w.pages[0].armor[0] == 5, "Removing one contribution lost its stable slot")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Missing aura slot could not restore before the next pulse")
	advance(w, 1199)
	check(w.pages[0].armor[0] == 5, "Aura contribution returned before the scheduled pulse")
	advance(w, 1201)
	check(w.pages[0].armor[0] == 8 and w.effects.records.size() == 2 and w.effects.records[slots[1]] == survivor, "Aura repair reset or duplicated the surviving contribution")
	if restored != null:
		advance(restored, 1201)
		check(restored.effects.records == w.effects.records and restored.entities.records == w.entities.records, "Aura repair changed after restoring a missing slot")
	var suppression: int = w.effects.add(w, 1, 3, 0, "", suppression_spec("aura_suppression", ["beneficial"], 1000), w.elapsed_ms, 0)
	advance(w, 1801)
	check(w.pages[0].armor[0] == 0 and w.effects.records[slots[1]] == survivor and w.effects.records.size() == 3, "Suppression removed or reset maintained aura identity")
	w.effects.remove(w, suppression, "dispelled", w.elapsed_ms)
	check(w.pages[0].armor[0] == 8 and w.effects.records[slots[1]] == survivor, "Ending suppression failed to restore the original aura contribution")
	for status: int in slots.duplicate(): w.effects.remove(w, status, "contribution_removed", w.elapsed_ms)
	check(w.pages[0].armor[0] == 0 and slots == [0, 0], "Source-maintenance removal did not clear both contribution slots")
	advance(w, 2201)
	check(w.pages[0].armor[0] == 8 and w.effects.records.size() == 2, "Repeated pulses stacked or failed to restore aura contributions")
	var corrupted: Dictionary = Persistence.capture(w)
	corrupted.domains.entities.records[entity].members[1].reverse()
	check(Persistence.candidate(corrupted, 0) == null, "Swapped contribution slots were accepted")
	w.entities.remove(w, entity, w.elapsed_ms)
	advance(w, 2701)
	check(w.effects.records.is_empty() and w.pages[0].armor[0] == 0, "Removed aura producer recreated its contributions")
	Defs.ACTIONS = original

func suppression_spec(id: String, tags: Array, duration: int) -> Dictionary:
	var spec := Status.new()
	spec.id = id
	spec.kind = "suppression"
	spec.duration_ms = duration
	spec.suppressed_tags = PackedStringArray(tags)
	return spec.values()

func lifecycle_and_cleanse() -> void:
	var w: RefCounted = fixture()
	var buff := Status.new()
	buff.id = "timed_armor"
	buff.kind = "modifier"
	buff.magnitude = 2.0
	w.effects.add(w, 1, 2, 0, "", buff.values(), 0, 0)
	buff.id = "self_field"
	buff.magnitude = 3.0
	var maintained: int = w.effects.add(w, 1, 1, 0, "", buff.values(), 0, 0, {}, {"lifetime": "source", "contribution": "self_field"})
	w.effects.apply_bundle(w, 1, 2, 0, "", [{"kind": "dispel"}], 0, 0)
	check(w.effects.records.size() == 1 and w.effects.records.has(maintained) and w.pages[0].armor[0] == 3, "Cleanse inferred lifecycle from source distance or source/recipient equality")
	w.effects.remove(w, maintained, "source_removed", 0)
	check(w.pages[0].armor[0] == 0, "Source removal failed to revoke its maintained contribution")
	for operation: String in ["kill", "forget"]:
		var removed: RefCounted = fixture()
		buff.id = "kept_after_source"
		buff.magnitude = 2.0
		var timed: int = removed.effects.add(removed, 1, 2, 0, "", buff.values(), 0, 0)
		buff.id = "bound_to_source"
		buff.magnitude = 3.0
		removed.effects.add(removed, 1, 2, 0, "", buff.values(), 0, 0, {}, {"lifetime": "source", "contribution": "source_field"})
		if operation == "kill": removed.kill(2, 0)
		else: removed.forget_target(2, 0)
		check(removed.effects.records.size() == 1 and removed.effects.records.has(timed) and removed.pages[0].armor[0] == 2, operation + ": source cleanup removed a recipient-owned buff or kept a maintained contribution")

func suppression_projections() -> void:
	var w: RefCounted = fixture()
	var buff := Status.new()
	buff.id = "tagged_armor"
	buff.kind = "modifier"
	buff.duration_ms = 800
	buff.magnitude = 4.0
	buff.tags = PackedStringArray(["beneficial"])
	var buff_id: int = w.effects.add(w, 1, 2, 0, "", buff.values(), 0, 0)
	var movement := Status.new()
	movement.id = "tagged_slow"
	movement.kind = "slow"
	movement.magnitude = 0.5
	movement.duration_ms = 800
	movement.tags = PackedStringArray(["frost"])
	w.effects.add(w, 1, 2, 0, "", movement.values(), 0, 0)
	movement.id = "tagged_root"
	movement.kind = "root"
	movement.duration_ms = 300
	w.effects.add(w, 1, 2, 0, "", movement.values(), 0, 0)
	var filter: Dictionary = suppression_spec("first_suppression", ["beneficial", "frost"], 100)
	filter.tags = PackedStringArray(["beneficial"])
	w.effects.add(w, 1, 3, 0, "", filter, 0, 0)
	w.effects.add(w, 1, 4, 0, "", suppression_spec("second_suppression", ["beneficial"], 200), 0, 0)
	w.effects.prepare(w, 0)
	check(w.pages[0].armor[0] == 0 and w.pages[0].move_scales[0] == 1.0 and not w.effects.has_kind(1, "root", 0) and w.effects.has_kind(1, "suppression", 0), "Tagged suppression disagreed across projections or recursively disabled itself")
	advance(w, 101)
	check(w.pages[0].armor[0] == 0 and w.effects.has_kind(1, "root", 101) and w.pages[0].move_scales[0] == 0.0, "Overlapping suppression tags ended together or failed to restore movement control")
	advance(w, 201)
	check(w.pages[0].armor[0] == 4 and w.effects.records[buff_id].until_ms == 800, "Suppression expiry restarted a recipient-owned buff or failed to restore it")
	advance(w, 301)
	check(w.pages[0].move_scales[0] == 0.5, "Unsuppressed movement failed to rebuild after root expiry")
	var malformed := Status.new()
	malformed.id = "invalid_suppression"
	malformed.kind = "suppression"
	check(not malformed.errors().is_empty(), "Suppression accepted an empty tag selector")
	malformed.suppressed_tags = PackedStringArray(["bad tag"])
	check(not malformed.errors().is_empty(), "Suppression accepted a non-identifier tag")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null and restored.effects.records == w.effects.records, "Tagged state projection failed restoration")
	var corrupted: Dictionary = Persistence.capture(w)
	corrupted.domains.effects.records[buff_id].spec.tags = ["beneficial"]
	check(Persistence.candidate(corrupted, 0) == null, "Malformed tag payload reached a derived state query")
	corrupted = Persistence.capture(w)
	corrupted.domains.combat.status[1] = {"stun_until": "invalid"}
	check(Persistence.candidate(corrupted, 0) == null, "Malformed aggregate control reached early effects validation")

func suppressed_periods_and_control() -> void:
	var w: RefCounted = fixture()
	var dot := Status.new()
	dot.id = "tagged_dot"
	dot.kind = "dot"
	dot.duration_ms = 550
	dot.period_ms = 100
	dot.magnitude = 1.0
	dot.tags = PackedStringArray(["poison"])
	w.effects.add(w, 2, 1, 0, "", dot.values(), 0, 10)
	advance(w, 50)
	w.effects.add(w, 2, 3, 0, "", suppression_spec("poison_suppression", ["poison"], 250), 50, 0)
	advance(w, 250)
	check(w.pages[0].health[1] == 2000, "Suppressed periodic damage still committed")
	advance(w, 301)
	check(w.pages[0].health[1] == 1990, "Suppression expiry replayed skipped ticks or delayed the original next tick")
	advance(w, 551)
	check(w.pages[0].health[1] == 1970, "Suppression changed the periodic status's original lifetime")
	var controlled: RefCounted = fixture()
	controlled.effects.add(controlled, 1, 3, 0, "", suppression_spec("control_suppression", ["control"], 100), 0, 0)
	controlled.combat.request(controlled, 1, "primary", Vector2.UP)
	var stun: Dictionary = stun_spec("disabled_stun", 300)
	stun.tags = PackedStringArray(["control"])
	var id: int = controlled.effects.add(controlled, 1, 2, 0, "", stun, 0, 0)
	check(id > 0 and controlled.combat.states.has(1) and not controlled.effects.has_kind(1, "stun", 0), "A suppressed control interrupted an active action during admission")
	var used: int = controlled.combat.status[1].stun_used
	advance(controlled, 101)
	check(not controlled.combat.states.has(1) and controlled.effects.has_kind(1, "stun", 101) and controlled.combat.status[1].stun_until == 300 and controlled.combat.status[1].stun_used == used, "Restoring a control failed to interrupt at the original remaining deadline or consumed its budget twice")
	var active: RefCounted = fixture()
	active.effects.add(active, 1, 2, 0, "", stun, 0, 0)
	advance(active, 10)
	active.effects.add(active, 1, 3, 0, "", suppression_spec("live_control_suppression", ["control"], 100), 10, 0)
	check(active.combat.request(active, 1, "primary", Vector2.UP) == "started", "Suppressing live control retained its action gate")
	advance(active, 111)
	check(not active.combat.states.has(1) and active.combat.status[1].stun_until == 300, "Ending suppression did not reapply the remaining live control")

func same_time_periodic_admission() -> void:
	var original: Dictionary = Defs.ACTIONS
	var variants: Dictionary = original.duplicate(true)
	variants.guard_stance.windup = 100
	variants.guard_stance.active = 1
	variants.guard_stance.recovery = 0
	variants.guard_stance.costs = []
	Defs.ACTIONS = variants
	for suppress: bool in [true, false]:
		var effect := Effect.new()
		effect.stage = "activation"
		if suppress:
			var filter := Status.new()
			filter.id = "direct_suppression"
			filter.kind = "suppression"
			filter.suppressed_tags = PackedStringArray(["poison"])
			filter.duration_ms = 250
			effect.kind = "status"
			effect.status = filter
		else: effect.kind = "dispel"
		variants.guard_stance.payload = [effect.values()]
		var w: RefCounted = fixture()
		var dot := Status.new()
		dot.id = "same_time_dot"
		dot.kind = "dot"
		dot.duration_ms = 500
		dot.period_ms = 100
		dot.magnitude = 1.0
		dot.dispellable = false
		dot.tags = PackedStringArray(["poison"])
		w.effects.add(w, 1, 2, 0, "", dot.values(), 0, 10)
		if not suppress: w.effects.add(w, 1, 3, 0, "", suppression_spec("cleansed_suppression", ["poison"], 250), 0, 0)
		check(w.combat.request_template(w, 1, "guard_stance", Vector2.RIGHT, 0, w.pages[0].positions[0]) == "started", "Same-time direct fixture failed admission")
		advance(w, 101)
		check(w.pages[0].health[0] == (2000 if suppress else 1990), "Same-time suppression/cleanse was not reflected in periodic admission")
	Defs.ACTIONS = original

func _run() -> void:
	defensive_sources()
	independent_control()
	hit_control_and_recovery()
	lifecycle_and_cleanse()
	suppression_projections()
	suppressed_periods_and_control()
	same_time_periodic_admission()
	aura_contributions()
	print("EFFECT_OWNERSHIP_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
