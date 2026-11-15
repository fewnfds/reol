extends RefCounted
## Authoritative status instances. Derived movement/attributes rebuild from source facts.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const StatusDef = preload("res://scripts/sim/definitions/actions/status_def.gd")
const STATE_FIELDS: Array = ["records", "next_id"]
var records: Dictionary = {}
var next_id: int = 1
var dirty: Dictionary = {}

func apply(world: RefCounted, target: int, source: int, activation: int, ability: String, now: int, amount: int) -> void:
	apply_bundle(world, target, source, activation, ability, Defs.ACTIONS[ability].payload, now, amount)

func apply_bundle(world: RefCounted, target: int, source: int, activation: int, ability: String, bundle: Array, now: int, damage: int, scope: String = "contact", lineage: Dictionary = {}, control_blocked: bool = false, source_context: Dictionary = {}) -> void:
	for spec: Dictionary in bundle:
		if spec.get("stage", "contact") != scope: continue
		if control_blocked and (spec.kind in ["slow", "control"] or (spec.kind == "status" and spec.status.kind in ["stun", "root", "slow"])): continue
		if spec.kind == "domain":
			world.DomainOps.commit(world, source, target, spec.operation, now)
			continue
		if not world.combat.alive(world, target): continue
		match str(spec.kind):
			"slow", "dot":
				var legacy: Dictionary = {"id": spec.id, "kind": spec.kind, "magnitude": spec.magnitude, "duration_ms": spec.duration_ms, "period_ms": spec.period_ms, "stacking": "refresh", "max_stacks": 1, "max_instances": 8, "attribute": "armor", "modifier": "add", "dispellable": true, "isolation": "source"}
				for rule: Dictionary in Defs.ACTIONS.get(ability, {}).get("reactions", []):
					if rule.mode == "spread" and rule.status_id == spec.id: legacy.isolation = "chain"
				add(world, target, source, activation, ability, legacy, now, damage, lineage, source_context)
			"status": add(world, target, source, activation, ability, spec.status, now, damage, lineage, source_context)
			"heal": world.combat.heal(world, source, target, int(spec.amount), now)
			"resource": world.pools.gain(world, target, spec.pool, int(spec.amount), now)
			"shield": world.defense.shield(world, source, target, int(spec.amount), now + int(spec.duration_ms), now)
			"guard":
				if world.actor_slots.has(target):
					var slot: int = world.actor_slots[target]
					world.defense.guard(world, target, float(spec.magnitude), int(spec.duration_ms), now, world.pages[slot / 256].aims[slot % 256])
			"dispel":
				for id: int in records.keys():
					if records[id].target == target and records[id].spec.dispellable: remove(world, id, "dispelled", now)

func add(world: RefCounted, target: int, source: int, activation: int, ability: String, spec: Dictionary, now: int, amount: int, lineage: Dictionary = {}, source_context: Dictionary = {}) -> int:
	if not world.actor_slots.has(target) or not world.combat.alive(world, target): return 0
	if not Defs.ACTIONS.has(ability): ability = ""
	activation = maxi(0, activation)
	var found: int = 0
	var independent_count: int = 0
	for id: int in records:
		var old: Dictionary = records[id]
		if old.target == target and old.source == source and old.status_id == spec.id and now < int(old.until_ms): independent_count += 1
		if now < int(old.until_ms) and old.target == target and old.source == source and old.status_id == spec.id and (spec.isolation == "source" or (spec.isolation == "chain" and old.get("lineage", {}).get("chain", 0) == lineage.get("chain", 0)) or (spec.isolation == "activation" and old.activation == activation)) and spec.stacking != "independent": found = id; break
	if spec.stacking == "independent" and independent_count >= int(spec.max_stacks): return 0
	if found == 0 and independent_count >= int(spec.max_instances): return 0
	if found > 0 and spec.stacking == "replace" and spec.kind != "stun": remove(world, found, "replaced", now); found = 0
	if found > 0 and spec.kind != "stun":
		var old: Dictionary = records[found]
		old.until_ms = maxi(int(old.until_ms), now + int(spec.duration_ms))
		old.magnitude = minf(float(old.magnitude), float(spec.magnitude)) if spec.kind == "slow" else maxf(float(old.magnitude), float(spec.magnitude))
		old.spec.magnitude = old.magnitude
		if spec.stacking == "stack":
			var previous: int = old.stacks
			old.stacks = mini(int(spec.max_stacks), int(old.stacks) + 1)
			if previous < int(spec.max_stacks) and old.stacks == int(spec.max_stacks):
				world.reactions.submit(world, {"event": "stack_max", "actor": source, "target": target, "at_ms": now, "activation": activation, "action": ability, "damage": amount, "position": world.position_at(target, now), "lineage": lineage, "side": old.side, "power": old.power}, old.get("rules", []))
		old.damage = maxi(int(old.damage), maxi(0, roundi(amount * float(spec.magnitude))))
		dirty[target] = true
		if spec.kind == "modifier": flush_dirty(world)
		return found # Renewal preserves cadence and causality.
	var until: int = now + int(spec.duration_ms)
	if spec.kind == "stun":
		var result: Dictionary = world.combat.damage(world, source, target, 0, now, Vector2.ZERO, 0, int(spec.duration_ms), 0.0, {"periodic": true, "group_ms": 0, "status_control": true})
		until = now + int(result.get("stun_ms", 0))
		if until <= now: return found
		if found > 0: remove(world, found, "replaced", now)
	var id: int = next_id
	next_id += 1
	records[id] = {"source": source, "target": target, "activation": activation, "ability": ability, "kind": spec.kind, "status_id": spec.id,
		"side": int(source_context.side) if source_context.has("side") else int(world.objects.records.get(source, {}).get("side", 0)), "power": source_context.power if source_context.has("power") else world.combat.source_power(world, source),
		"born_ms": now, "until_ms": until, "next_ms": now + int(spec.period_ms), "period_ms": int(spec.period_ms), "magnitude": float(spec.magnitude),
		"rules": Defs.ACTIONS.get(ability, {}).get("reactions", []), "damage": maxi(0, roundi(amount * float(spec.magnitude))), "stacks": 1, "spec": spec.duplicate(true), "lineage": lineage.duplicate(true)}
	dirty[target] = true
	if spec.kind == "modifier": flush_dirty(world)
	world.emit({"kind": "status_added", "actor": source, "target": target, "status": spec.id, "at_ms": now})
	return id

func has_kind(target: int, kind: String, now: int) -> bool:
	for entry: Dictionary in records.values():
		if entry.target == target and entry.kind == kind and now >= int(entry.born_ms) and now < int(entry.until_ms): return true
	return false

func remove(world: RefCounted, id: int, reason: String, now: int) -> void:
	if not records.has(id): return
	var entry: Dictionary = records[id]
	records.erase(id)
	world.entities.forget_status(id)
	dirty[entry.target] = true
	if entry.kind == "stun" and reason == "dispelled":
		var until: int = maxi(now, int(world.combat.status.get(entry.target, {}).get("hit_stun_until", 0)))
		for other: Dictionary in records.values():
			if other.target == entry.target and other.kind == "stun": until = maxi(until, int(other.until_ms))
		if world.combat.status.has(entry.target): world.combat.status[entry.target].stun_until = until
	if entry.kind == "modifier": flush_dirty(world)
	world.emit({"kind": "status_removed", "actor": entry.source, "target": entry.target, "status": entry.status_id, "reason": reason, "at_ms": now})

func modify(base: Dictionary, target: int, at: int) -> Dictionary:
	var additions: Dictionary = {}
	var factors: Dictionary = {}
	var ids: Array = records.keys()
	ids.sort()
	for id: int in ids:
		var entry: Dictionary = records[id]
		if entry.target != target or entry.kind != "modifier" or at < int(entry.born_ms) or at >= int(entry.until_ms): continue
		var key: String = entry.spec.attribute
		if entry.spec.modifier == "add": additions[key] = float(additions.get(key, 0)) + float(entry.magnitude) * int(entry.stacks)
		else: factors[key] = float(factors.get(key, 1)) * pow(float(entry.magnitude), int(entry.stacks))
	for key: String in base:
		base[key] = clampf((float(base[key]) + float(additions.get(key, 0))) * float(factors.get(key, 1)), 0.1 if key == "speed" else 1 if key == "max_hp" else 0, 50 if key == "speed" else 1000000)
		if key != "speed": base[key] = roundi(base[key])
	return base

func next_boundary(now: int, end: int) -> int:
	for entry: Dictionary in records.values():
		for at: int in [int(entry.until_ms), int(entry.next_ms) if entry.kind == "dot" else 0]:
			if at > now: end = mini(end, at)
	return end

func flush_dirty(world: RefCounted) -> void:
	var actors: Array = dirty.keys()
	dirty.clear()
	for actor: int in actors:
		if world.actor_slots.has(actor): world.Equipment.rebuild(world, actor)

func expire(world: RefCounted, now: int) -> void:
	for id: int in records.keys():
		var entry: Dictionary = records[id]
		if now >= int(entry.until_ms) or not world.combat.alive(world, entry.target): remove(world, id, "expired" if now >= int(entry.until_ms) else "death", now)
	flush_dirty(world)

func prepare(world: RefCounted, now: int) -> void:
	expire(world, now)
	for page: RefCounted in world.pages: page.move_scales.fill(1.0)
	for entry: Dictionary in records.values():
		var slot: int = world.actor_slots[entry.target]
		var page: RefCounted = world.pages[slot / 256]
		if entry.kind in ["slow", "haste"]: page.move_scales[slot % 256] *= pow(float(entry.magnitude), int(entry.stacks))
		elif entry.kind == "root": page.move_scales[slot % 256] = 0.0
	for page: RefCounted in world.pages:
		for row: int in page.move_scales.size(): page.move_scales[row] = clampf(page.move_scales[row], 0.0, 3.0)

func collect(world: RefCounted, now: int) -> Array[Dictionary]:
	var impacts: Array[Dictionary] = []
	for entry: Dictionary in records.values():
		if entry.kind != "dot": continue
		while int(entry.next_ms) <= now and int(entry.next_ms) < int(entry.until_ms):
			impacts.append({"actor": entry.source, "target": entry.target, "activation": entry.activation, "at_ms": entry.next_ms,
				"damage": int(entry.damage) * int(entry.stacks), "incoming": Vector2.ZERO, "stun": 0, "push": 0.0, "group_ms": 0, "periodic": true,
				"position": world.position_at(entry.target, entry.next_ms), "action": entry.ability, "lineage": entry.lineage, "rules": entry.rules, "side": entry.side, "power": entry.power})
			entry.next_ms += int(entry.period_ms)
	return impacts

func remove_target(actor: int) -> void:
	for id: int in records.keys():
		if records[id].target == actor: records.erase(id)
	dirty.erase(actor)

func valid(world: RefCounted) -> bool:
	if next_id < 1: return false
	var groups: Dictionary = {}
	var unique: Dictionary = {}
	for id: Variant in records:
		var entry: Variant = records[id]
		if not id is int or id < 1 or id >= next_id or not entry is Dictionary: return false
		if not world.combat.valid_source(entry): return false
		for key: String in ["source", "target", "activation", "side", "born_ms", "until_ms", "next_ms", "period_ms", "damage", "stacks"]:
			if not entry.get(key) is int: return false
		if not world.actor_slots.has(entry.target) or entry.source < 1 or entry.source >= world.objects.next_id or not entry.get("ability") is String or (not entry.ability.is_empty() and not Defs.ACTIONS.has(entry.ability)): return false
		if not entry.get("spec") is Dictionary or not entry.get("lineage") is Dictionary or not valid_spec(entry.spec): return false
		if entry.get("kind") != entry.spec.kind or entry.get("status_id") != entry.spec.id or entry.get("magnitude") != entry.spec.magnitude: return false
		if entry.born_ms < 0 or entry.born_ms > world.elapsed_ms or entry.until_ms <= entry.born_ms or entry.until_ms > world.elapsed_ms + 60000 or entry.activation < 0 or entry.activation >= world.combat.next_activation or entry.damage < 0 or entry.damage > 10000000 or entry.stacks < 1 or entry.stacks > entry.spec.max_stacks: return false
		if entry.kind == "dot" and (entry.period_ms != entry.spec.period_ms or entry.next_ms < entry.born_ms + entry.period_ms or (entry.next_ms <= world.elapsed_ms and entry.next_ms < entry.until_ms) or entry.next_ms > world.elapsed_ms + entry.period_ms): return false
		var key: String = "%d:%d:%s" % [entry.source, entry.target, entry.status_id]
		groups[key] = int(groups.get(key, 0)) + 1
		if groups[key] > int(entry.spec.max_instances): return false
		if entry.spec.stacking != "independent":
			if entry.spec.isolation == "chain": key += ":c%d" % int(entry.lineage.get("chain", 0))
			elif entry.spec.isolation == "activation": key += ":a%d" % entry.activation
			if unique.has(key): return false
			unique[key] = true
	return true

static func valid_spec(spec: Dictionary) -> bool:
	var definition := StatusDef.new()
	for field: String in ["id", "kind", "duration_ms", "period_ms", "magnitude", "stacking", "max_stacks", "max_instances", "attribute", "modifier", "dispellable", "isolation"]:
		if not spec.has(field) or typeof(spec[field]) != typeof(definition.get(field)): return false
		definition.set(field, spec[field])
	return definition.errors().is_empty()
