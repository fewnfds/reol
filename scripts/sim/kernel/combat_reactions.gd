extends RefCounted
## Sparse result rules, shared causal budgets and bounded later waves.
## World.emit remains presentation output; callers submit actual typed results here.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Marks = preload("res://scripts/sim/kernel/reaction_scripts/owned_marks.gd")
const STATE_FIELDS: Array = ["chains", "next_chain", "instances", "script_states", "requests", "pending"]
const ROOT_BUDGET: int = 64
var chains: Dictionary = {}
var next_chain: int = 1
var instances: Dictionary = {}
var script_states: Dictionary = {}
var requests: Array[Dictionary] = []
var pending: Array[Dictionary] = []
var tracing: bool = false
var trace: Array[Dictionary] = [] # Optional bounded diagnostics, deliberately unsaved.

func root(actor: int, activation: int) -> Dictionary:
	var id: int = next_chain
	next_chain += 1
	chains[id] = {"remaining": ROOT_BUDGET, "counts": {}, "visited": {}, "source": actor, "activation": activation}
	return {"chain": id, "depth": 0}

func ensure(event: Dictionary) -> Dictionary:
	var lineage: Dictionary = event.get("lineage", {})
	if lineage.is_empty(): lineage = root(event.actor, int(event.get("activation", 0)))
	return lineage

func submit(world: RefCounted, event: Dictionary, local_rules: Array = []) -> void:
	event = event.duplicate(true)
	if not event.has("damage"): event.damage = 0
	if not event.has("target"): event.target = 0
	if not event.has("activation"): event.activation = 0
	if not event.has("side"): event["side"] = int(world.objects.records.get(event.actor, {}).get("side", 0))
	if not event.has("power"): event["power"] = world.combat.source_power(world, event.actor)
	var direction: Vector2 = event.get("direction", Vector2.ZERO)
	if direction.is_zero_approx() and world.objects.records.has(event.actor) and world.objects.records.has(event.target):
		direction = world.position_at(event.target, int(event.at_ms)) - world.position_at(event.actor, int(event.at_ms))
	event["direction"] = Vector2.RIGHT if direction.is_zero_approx() else direction.normalized()
	event.lineage = ensure(event)
	event["rules"] = local_rules.duplicate(true)
	if not event.has("dying_status") and world.actor_slots.has(event.actor): event.rules.append_array(world.combat.profile(world, event.actor).reactions)
	pending.append(event)

func damage_result(world: RefCounted, result: Dictionary, context: Dictionary) -> void:
	if not result.get("contact", false): return
	var event: Dictionary = context.duplicate(true)
	event.merge(result, true)
	event["position"] = context.get("delivery_position", context.get("position", world.position_at(result.target, result.at_ms)))
	event["direction"] = -Vector2(context.get("incoming", Vector2.LEFT))
	event["event"] = "hit"
	event.lineage = ensure(event)
	submit(world, event, context.get("rules", []))
	if int(result.damage) > 0:
		submit(world, _defender_event(event, "damaged"))
	if int(result.blocked) > 0:
		submit(world, _defender_event(event, "blocked"))
	for entry: Dictionary in result.broken:
		submit(world, _defender_event(event, "shield_broken"))
	if result.fatal:
		var killed: Dictionary = event.duplicate(true)
		killed.event = "killed"
		submit(world, killed, context.get("rules", []))
		for entry: Dictionary in world.effects.records.values():
			if entry.target != result.target: continue
			var death: Dictionary = killed.duplicate(true)
			death["cause"] = cause_of(killed)
			death.actor = entry.source
			death.activation = entry.activation
			death["action"] = entry.ability
			death.lineage = entry.lineage if not entry.lineage.is_empty() else event.lineage
			death["side"] = entry.side
			death["power"] = entry.power
			death["dying_status"] = entry.duplicate(true)
			submit(world, death, entry.get("rules", []))

func _defender_event(attack: Dictionary, kind: String) -> Dictionary:
	var response: Dictionary = attack.duplicate(true)
	# A triggering attack is evidence, not ownership of the defender's effect.
	# Keep only one flat cause; repeated reactions cannot grow a nested history.
	response["cause"] = cause_of(attack)
	response.event = kind
	response.actor = attack.target
	response.target = attack.actor
	response.direction = -Vector2(attack.direction)
	response["action"] = ""
	response.activation = 0 # A passive response has no body-action activation.
	response.erase("side"); response.erase("power")
	return response

func cause_of(event: Dictionary) -> Dictionary:
	return {"event": event.event, "actor": event.actor, "target": event.target,
		"action": str(event.get("action", "")), "activation": int(event.get("activation", 0)), "at_ms": event.at_ms}

func resolve(world: RefCounted, interval_start: int, interval_end: int) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	var spawned: Array = []
	# Status-only results can submit another bounded rule (for example stack_max).
	# Drain it before advancing the chronological wave; budget/depth stay shared.
	while not pending.is_empty():
		var events: Array[Dictionary] = pending
		pending = []
		_resolve_events(world, events, spawned, impacts)
	if not spawned.is_empty(): impacts.append_array(world.combat.Projectiles.collect(world.combat, world, interval_start, interval_end, spawned))
	impacts.append_array(world.areas.collect(world, interval_end))
	return impacts

func _resolve_events(world: RefCounted, events: Array[Dictionary], spawned: Array, impacts: Array[Dictionary]) -> void:
	for event: Dictionary in events:
		var lineage: Dictionary = event.lineage
		if not valid_lineage(lineage) or not chains.has(lineage.chain): continue
		for index: int in event.rules.size():
			var rule: Dictionary = event.rules[index]
			if rule.event != event.event or int(lineage.depth) >= int(rule.max_depth): continue
			if rule.mode == "spread" and (not event.has("dying_status") or event.dying_status.status_id != rule.status_id): continue
			if event.has("dying_status") and rule.mode != "spread": continue
			if rule.mode == "script" and Marks.candidates(world, event).size() < 2: continue
			if rule.event == "hit" and rule.health_leech > 0 and int(event.get("damage", 0)) <= 0: continue
			var chain: Dictionary = chains[lineage.chain]
			var key: String = "%d:%s" % [event.actor, rule.id]
			var instance: Dictionary = instances.get(key, {"count": 0, "until_ms": 0})
			instance.count += 1
			instances[key] = instance
			if instance.count % int(rule.every) != 0 or event.at_ms < int(instance.until_ms) or int(chain.remaining) <= 0 or int(chain.counts.get(key, 0)) >= int(rule.chain_limit): continue
			if rule.mode == "request" and requests.any(func(request: Dictionary): return request.key == key): continue
			if rule.chance < 1.0 and world.environment.rng.randf() >= float(rule.chance): continue
			# A rule evaluation and each child consume work. Do not admit a
			# producer when the budget cannot pay for even its first child.
			if rule.mode in ["emit", "spread", "script"] and int(chain.remaining) < 2: continue
			if rule.mode == "request":
				if not world.actor_slots.has(event.actor) or not world.combat.alive(world, event.actor): continue
				requests.append({"at_ms": (int(event.at_ms) / 50 + 1) * 50, "event": event.duplicate(true), "rule": rule.duplicate(true), "key": key})
				continue # No CD/budget/payment before joint admission at the spatial grid.
			instance.until_ms = event.at_ms + int(rule.interval_ms)
			chain.remaining -= 1
			chain.counts[key] = int(chain.counts.get(key, 0)) + 1
			if tracing:
				if trace.size() >= 64: trace.pop_front()
				trace.append({"at_ms": event.at_ms, "actor": event.actor, "target": event.get("target", 0), "event": event.event, "rule": rule.id, "mode": rule.mode, "chain": lineage.chain, "depth": lineage.depth, "budget_after_admission": chain.remaining})
			if rule.consume_delivery and world.combat.bolts.has(event.get("bolt_id", 0)):
				world.combat.Projectiles.truncate(world.combat, event.bolt_id, event.at_ms)
				world.combat.bolts.erase(event.bolt_id)
			var child: Dictionary = {"chain": lineage.chain, "depth": int(lineage.depth) + 1}
			match str(rule.mode):
				"bundle":
					var recipient: int = event.actor if rule.recipient == "source" else int(event.get("target", 0))
					if rule.health_leech > 0: world.combat.heal(world, event.actor, recipient, floori(int(event.get("damage", 0)) * float(rule.health_leech)), event.at_ms)
					impacts.append_array(_bundle(world, event, recipient, rule.bundle, child))
				"emit":
					var activation: int = world.combat.next_activation
					world.combat.next_activation += 1
					var excluded: int = 0 if event.event in ["damaged", "blocked", "shield_broken"] else int(event.get("target", 0))
					for number: int in int(rule.count):
						if int(chain.remaining) <= 0: break
						chain.remaining -= 1
						var direction: Vector2 = Vector2(event.get("direction", Vector2.RIGHT)).rotated((number - (int(rule.count) - 1) * 0.5) * float(rule.spread))
						spawned.append_array(world.combat.spawn_template(world, event.actor, rule.template, event.position, direction, event.at_ms, float(rule.scale), child, excluded, activation, event))
				"spread": _spread(world, event, rule, child)
				"script":
					if not script_states.has(key): script_states[key] = Marks.initial_state()
					for target: int in Marks.targets(world, event, script_states[key]):
						if int(chain.remaining) <= 0: break
						chain.remaining -= 1
						impacts.append_array(_bundle(world, event, target, rule.bundle, child))
func _bundle(world: RefCounted, event: Dictionary, target: int, bundle: Array, lineage: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var summary: Dictionary = world.combat.Payload.summary(bundle)
	if float(summary.damage) > 0:
		var amount: int = event.power.y
		result.append({"actor": event.actor, "target": target, "at_ms": event.at_ms, "activation": int(event.get("activation", 0)), "damage": roundi(amount * float(summary.damage)),
			"stun": summary.stun, "push": summary.push, "incoming": -Vector2(event.get("direction", Vector2.RIGHT)), "group_ms": 0, "lineage": lineage, "rules": [], "payload": bundle, "action": event.get("action", ""), "cause": event.get("cause", {}).duplicate(true), "position": world.position_at(target, event.at_ms), "side": event.side, "power": event.power})
	else: world.effects.apply_bundle(world, target, event.actor, int(event.get("activation", 0)), event.get("action", ""), bundle, event.at_ms, int(event.get("damage", 0)), "contact", lineage, false, event)
	return result

func _spread(world: RefCounted, event: Dictionary, rule: Dictionary, lineage: Dictionary) -> void:
	var entry: Dictionary = event.get("dying_status", {})
	if entry.is_empty() or entry.status_id != rule.status_id: return
	var chain: Dictionary = chains[lineage.chain]
	var visited: Dictionary = chain.visited.get(rule.id, {})
	visited[entry.target] = true
	chain.visited[rule.id] = visited
	var count: int = 0
	for target: int in world.combat.scan.nearby(event.position - Vector2.ONE * (float(rule.radius) + world.combat.scan.sweep_padding), event.position + Vector2.ONE * (float(rule.radius) + world.combat.scan.sweep_padding)):
		if visited.has(target) or not world.combat.eligible(world, event.actor, target, "hostile", int(entry.side)): continue
		if world.position_at(target, event.at_ms).distance_to(event.position) > float(rule.radius): continue
		if int(chain.remaining) <= 0 or count >= int(rule.count): break
		var spec: Dictionary = entry.spec.duplicate(true)
		spec.duration_ms = mini(int(spec.duration_ms), maxi(0, int(entry.until_ms) - int(event.at_ms)))
		if spec.duration_ms < maxi(1, int(spec.period_ms)): continue
		visited[target] = true
		chain.remaining -= 1
		count += 1
		world.effects.add(world, target, entry.source, entry.activation, entry.ability, spec, event.at_ms, roundi(float(entry.damage) / maxf(0.001, float(entry.magnitude))), lineage, entry)

func prepare(world: RefCounted, now: int) -> void:
	var due: Array[Dictionary] = requests
	requests = []
	for request: Dictionary in due:
		if request.at_ms > now: requests.append(request); continue
		var event: Dictionary = request.event
		var rule: Dictionary = request.rule
		if not valid_lineage(event.lineage) or not world.combat.alive(world, event.actor): continue
		var chain: Dictionary = chains[event.lineage.chain]
		var instance: Dictionary = instances.get(request.key, {"count": 0, "until_ms": 0})
		if chain.remaining <= 0 or int(chain.counts.get(request.key, 0)) >= int(rule.chain_limit) or now < int(instance.until_ms): continue
		var child: Dictionary = {"chain": event.lineage.chain, "depth": int(event.lineage.depth) + 1}
		var accepted: String = world.combat.request_template(world, event.actor, rule.template, event.get("direction", Vector2.RIGHT), now, event.position, int(event.get("target", 0)), child)
		if accepted != "started": continue
		instance.until_ms = now + int(rule.interval_ms)
		instances[request.key] = instance
		chain.remaining -= 1
		chain.counts[request.key] = int(chain.counts.get(request.key, 0)) + 1
	# Reachability, not a wall-clock expiry: delayed descendants keep their budget.
	var live: Dictionary = {}
	for host: Dictionary in [world.combat.states, world.combat.bolts, world.areas.records, world.effects.records, world.implements.records, world.entities.records]:
		for entry: Dictionary in host.values():
			var lineage: Dictionary = entry.get("lineage", {})
			if not lineage.is_empty(): live[lineage.chain] = true
	for request: Dictionary in requests:
		live[request.event.lineage.chain] = true
	for event: Dictionary in pending:
		if not event.get("lineage", {}).is_empty(): live[event.lineage.chain] = true
	for id: int in chains.keys():
		if not live.has(id): chains.erase(id)
	for host: Dictionary in [instances, script_states]:
		for key: String in host.keys():
			if not world.actor_slots.has(int(key.get_slice(":", 0))): host.erase(key)

func valid_lineage(lineage: Variant) -> bool:
	return lineage is Dictionary and lineage.get("chain") is int and chains.has(lineage.chain) and lineage.get("depth") is int and lineage.depth >= 0 and lineage.depth <= 6

func forget_actor(actor: int) -> void:
	# Committed deliveries survive a source; unstarted body actions cannot.
	requests = requests.filter(func(request: Dictionary): return request.event.actor != actor)

static func valid_rule(rule: Variant) -> bool:
	if not rule is Dictionary: return false
	var definition := preload("res://scripts/sim/definitions/actions/reaction_def.gd").new()
	for field: String in ["id", "event", "mode", "recipient", "template", "script_id", "chance", "every", "interval_ms", "delay_ms", "count", "spread", "radius", "scale", "health_leech", "chain_limit", "max_depth", "status_id", "consume_delivery"]:
		if not rule.has(field) or typeof(rule[field]) != typeof(definition.get(field)): return false
		definition.set(field, rule[field])
	return definition.errors().is_empty() and preload("res://scripts/sim/kernel/effect_payload.gd").valid(rule.get("bundle"), "contact") and definition.template_error(rule, Defs.ACTIONS).is_empty()

func valid(world: RefCounted) -> bool:
	if next_chain < 1: return false
	for id: Variant in chains:
		var chain: Variant = chains[id]
		if not id is int or id < 1 or id >= next_chain or not chain is Dictionary or not chain.get("remaining") is int or chain.remaining < 0 or chain.remaining > ROOT_BUDGET or not chain.get("counts") is Dictionary or not chain.get("visited") is Dictionary or not chain.get("source") is int or not chain.get("activation") is int: return false
		for key: Variant in chain.counts:
			if not key is String or not chain.counts[key] is int or chain.counts[key] < 0 or chain.counts[key] > 32: return false
		for key: Variant in chain.visited:
			if not key is String or not chain.visited[key] is Dictionary: return false
			for target: Variant in chain.visited[key]:
				if not target is int or target <= 0 or target >= world.objects.next_id or chain.visited[key][target] != true: return false
	for key: Variant in instances:
		var entry: Variant = instances[key]
		if not key is String or not entry is Dictionary or not entry.get("count") is int or entry.count < 0 or not entry.get("until_ms") is int or entry.until_ms < 0 or entry.until_ms > world.elapsed_ms + 60000: return false
	for key: Variant in script_states:
		if not key is String or not script_states[key] is Dictionary or not Marks.valid(script_states[key]): return false
	for request: Variant in requests:
		if not request is Dictionary or not request.get("key") is String or not request.get("event") is Dictionary or not request.event.get("actor") is int or not world.actor_slots.has(request.event.actor) or not request.event.get("position") is Vector2 or not request.event.position.is_finite(): return false
		if not request is Dictionary or not request.get("at_ms") is int or request.at_ms < world.elapsed_ms or request.at_ms > world.elapsed_ms + 50 or request.at_ms % 50 != 0 or not valid_rule(request.get("rule")) or not request.get("event") is Dictionary or not valid_lineage(request.event.get("lineage", {})): return false
		if request.rule.mode != "request" or not valid_event(request.event, world) or request.key != "%d:%s" % [request.event.actor, request.rule.id]: return false
	for event: Variant in pending:
		if not event is Dictionary or not event.get("actor") is int or not event.get("at_ms") is int or event.at_ms < 0 or event.at_ms > world.elapsed_ms or not valid_lineage(event.get("lineage", {})) or not event.get("rules") is Array or event.actor < 1 or event.actor >= world.objects.next_id or not event.get("event") is String or not event.get("position") is Vector2 or not event.position.is_finite(): return false
		for rule: Variant in event.rules:
			if not valid_rule(rule): return false
		if event.rules.size() > 16 or not valid_event(event, world): return false
	for host: Dictionary in [{"records": world.combat.states, "snapshot": false}, {"records": world.combat.bolts, "snapshot": true}, {"records": world.areas.records, "snapshot": true}, {"records": world.effects.records, "snapshot": true}, {"records": world.implements.records, "snapshot": false}, {"records": world.entities.records, "snapshot": false}]:
		for entry: Variant in host.records.values():
			if not entry is Dictionary: return false
			if host.snapshot and not entry.has("rules"): return false
			if not entry.get("rules", []) is Array or entry.get("rules", []).size() > 8: return false
			for rule: Variant in entry.get("rules", []):
				if not valid_rule(rule): return false
			var lineage: Variant = entry.get("lineage", {})
			if not lineage is Dictionary or (not lineage.is_empty() and not valid_lineage(lineage)): return false
			var ability: String = str(entry.get("ability", ""))
			# Implements/entities read their immutable definition instead of saving
			# a second rules snapshot. Payload hosts must retain the exact snapshot.
			if entry.has("rules") and not ability.is_empty() and entry.rules != Defs.ACTIONS.get(ability, {}).get("reactions", []): return false
	return true

func valid_event(event: Dictionary, world: RefCounted) -> bool:
	if not world.combat.valid_source(event): return false
	if not valid_cause(event.get("cause", {}), world): return false
	if event.get("event") not in ["hit", "damaged", "killed", "blocked", "shield_broken", "gathered", "timer", "expired", "stack_max"]: return false
	for key: String in ["actor", "target", "activation", "at_ms", "damage"]:
		if not event.get(key) is int: return false
	if event.target < 0 or event.target >= world.objects.next_id or event.activation < -world.combat.next_bolt or event.activation >= world.combat.next_activation or event.damage < 0: return false
	if not event.get("position") is Vector2 or not event.position.is_finite(): return false
	if event.has("direction") and (not event.direction is Vector2 or not event.direction.is_finite() or (not event.direction.is_zero_approx() and not is_equal_approx(event.direction.length_squared(), 1.0))): return false
	if event.has("dying_status"):
		var entry: Variant = event.dying_status
		if not entry is Dictionary or not entry.get("spec") is Dictionary or not world.effects.valid_spec(entry.spec): return false
		if not world.combat.valid_source(entry): return false
		for key: String in ["source", "target", "activation", "side", "until_ms", "damage"]:
			if not entry.get(key) is int: return false
		if not entry.get("magnitude") is float or entry.magnitude <= 0 or entry.get("status_id") != entry.spec.id: return false
	return true

func valid_cause(cause: Variant, world: RefCounted) -> bool:
	if not cause is Dictionary: return false
	if cause.is_empty(): return true
	if cause.size() != 6 or cause.get("event") not in ["hit", "damaged", "killed", "blocked", "shield_broken", "gathered", "timer", "expired", "stack_max"]: return false
	for key: String in ["actor", "target", "activation", "at_ms"]:
		if not cause.get(key) is int: return false
	if cause.actor < 1 or cause.actor >= world.objects.next_id or cause.target < 0 or cause.target >= world.objects.next_id or cause.at_ms < 0 or cause.at_ms > world.elapsed_ms: return false
	if cause.activation < -world.combat.next_bolt or cause.activation >= world.combat.next_activation: return false
	return cause.get("action") is String and (cause.action.is_empty() or Defs.ACTIONS.has(cause.action))
