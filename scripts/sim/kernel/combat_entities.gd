extends RefCounted
## Temporary bodies and destructible static producers. No villager work or population.
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const STATE_FIELDS: Array = ["records"]
var records: Dictionary = {}

func root_owner(owner: int) -> int:
	return int(records.get(owner, {}).get("root_owner", owner))

func readiness(owner: int, ability: String) -> String:
	var spec: Dictionary = Defs.ACTIONS[ability].entity
	var count: int = 0
	for entry: Dictionary in records.values():
		if entry.root_owner == root_owner(owner) and Defs.ACTIONS[entry.ability].entity.group == spec.group: count += 1
	return "summon_limit" if count >= int(spec.limit) else ""

func create(world: RefCounted, owner: int, state: Dictionary, at: int) -> int:
	if not world.combat.alive(world, owner) or not readiness(owner, state.kind).is_empty(): return 0
	var spec: Dictionary = Defs.ACTIONS[state.kind].entity
	var point: Vector2 = world.terrain.project_point(state.point, 0.35, false)
	if point.x < 0: return 0
	var id: int
	if spec.body == "companion":
		id = world.spawn_actor(Terrain.index(Vector2i(point)), "companion", "summoned")
		if id == 0: return 0
		var rec: Dictionary = world.objects.records[id]
		rec["ability_loadout"] = spec.loadout
		rec["base_stats"] = {"max_hp": float(spec.max_hp), "melee": float(spec.damage), "ranged": float(spec.damage), "speed": float(spec.speed)}
		rec["combatant"] = true
		rec["alert_range"] = 7.0
		rec["name"] = Defs.ACTIONS[state.kind].title
		world.Equipment.rebuild(world, id)
		var slot: int = world.actor_slots[id]
		world.pages[slot / 256].health[slot % 256] = int(spec.max_hp)
	else:
		id = world.objects.create("combat_object", state.kind, Terrain.index(Vector2i(point)))
		world.objects.records[id]["hp"] = int(spec.max_hp)
		world.objects.records[id]["combat_receiver"] = true
	world.objects.records[id]["side"] = int(world.objects.records[owner].get("side", 0))
	world.objects.records[id]["autonomous"] = false
	records[id] = {"id": id, "owner": owner, "root_owner": root_owner(owner), "ability": state.kind, "anchor": world.combat.position(world, id), "born_ms": at, "until_ms": at + int(spec.life),
		"next_ms": at + int(spec.period), "activation": state.activation, "lineage": state.get("lineage", {}), "members": {}}
	var target: int = int(state.get("target_id", 0))
	if spec.body == "companion" and target > 0 and world.combat.eligible(world, owner, target, "hostile", int(world.objects.records[owner].get("side", 0))):
		# The owner's selected identity is only an initial command. The companion
		# must independently see it and thereafter uses its own contact memory.
		world.combat.engage(world, id, target, Vector2(-1, -1), world.combat.ranged(world, id), at)
	world.emit({"kind": "entity_created", "actor": owner, "target": id, "at_ms": at, "position": point})
	return id

func forget_member(world: RefCounted, actor: int, at: int) -> void:
	for entry: Dictionary in records.values():
		if not entry.members.has(actor): continue
		for status: int in entry.members[actor].duplicate(): world.effects.remove(world, status, "target_removed", at)
		entry.members.erase(actor)

func drop_owner(world: RefCounted, owner: int, at: int) -> void:
	for id: int in records.keys():
		if records.has(id) and records[id].owner == owner: remove(world, id, at)

func next_boundary(now: int, end: int) -> int:
	for entry: Dictionary in records.values():
		for at: int in [int(entry.until_ms), int(entry.next_ms)]:
			if at > now: end = mini(end, at)
	return end

func remove(world: RefCounted, id: int, at: int) -> void:
	if not records.has(id): return
	var entry: Dictionary = records[id]
	records.erase(id)
	for ids: Array in entry.members.values():
		for status: int in ids: world.effects.remove(world, status, "source_removed", at)
	if world.actor_slots.has(id): world.remove_actor(id, at)
	else:
		world.forget_target(id, at)
		world.objects.remove_empty(id)
	world.emit({"kind": "entity_removed", "actor": entry.owner, "target": id, "at_ms": at})

func expire(world: RefCounted, now: int) -> void:
	for id: int in records.keys():
		if not records.has(id): continue
		var entry: Dictionary = records[id]
		if now >= int(entry.until_ms) or not world.combat.alive(world, entry.owner) or not world.combat.alive(world, id): remove(world, id, now)

func forget_status(id: int) -> void:
	for entry: Dictionary in records.values():
		for ids: Array in entry.members.values():
			for slot: int in ids.size():
				if ids[slot] == id: ids[slot] = 0

func prepare(world: RefCounted, now: int) -> void:
	expire(world, now)
	if not records.is_empty(): world.combat.scan.index(world)
	for id: int in records.keys():
		if not records.has(id): continue
		var entry: Dictionary = records[id]
		if now >= int(entry.until_ms) or not world.combat.alive(world, entry.owner) or not world.combat.alive(world, id): remove(world, id, now); continue
		var spec: Dictionary = Defs.ACTIONS[entry.ability].entity
		if world.actor_slots.has(id):
			var home: Vector2 = world.combat.position(world, entry.owner) if spec.stance == "follow" else Vector2(entry.anchor)
			world.decisions.follow(world, id, home, now)
		if now < int(entry.next_ms): continue
		entry.next_ms += int(spec.period)
		if float(spec.radius) <= 0: continue
		var origin: Vector2 = world.combat.position(world, id)
		var inside: Dictionary = {}
		for actor: int in world.combat.scan.nearby(origin - Vector2.ONE * float(spec.radius), origin + Vector2.ONE * float(spec.radius)):
			if not world.combat.alive(world, actor) or int(world.objects.records[actor].get("side", 0)) != int(world.objects.records[id].side): continue
			if world.combat.position(world, actor).distance_to(origin) > float(spec.radius) or Terrain.blocking_fraction(world.terrain.blocked, origin, world.combat.position(world, actor)) >= 0: continue
			inside[actor] = true
			if not entry.members.has(actor):
				var slots: Array = []
				slots.resize(spec.aura.size())
				slots.fill(0)
				entry.members[actor] = slots
			var contributions: Array = entry.members[actor]
			for slot: int in spec.aura.size():
				if int(contributions[slot]) > 0: continue
				var effect: Dictionary = spec.aura[slot]
				var status: Dictionary = effect.status.duplicate(true)
				status.duration_ms = maxi(1, int(entry.until_ms) - now)
				contributions[slot] = world.effects.add(world, actor, id, entry.activation, entry.ability, status, now, 0, entry.lineage, {"contribution": "aura_%d" % slot, "lifetime": "source"})
			world.effects.apply_bundle(world, actor, id, entry.activation, entry.ability, spec.pulse, now, 0, "contact", entry.lineage)
		for actor: int in entry.members.keys():
			if inside.has(actor): continue
			# Removing a contribution clears its slot through forget_status().
			for status: int in entry.members[actor].duplicate(): world.effects.remove(world, status, "left_aura", now)
			entry.members.erase(actor)

func valid(world: RefCounted) -> bool:
	var groups: Dictionary = {}
	for id: Variant in records:
		var entry: Variant = records[id]
		if not id is int or not entry is Dictionary or entry.get("id") != id or not world.objects.records.has(id) or not Defs.ACTIONS.has(entry.get("ability")) or Defs.ACTIONS[entry.ability].get("entity", {}).is_empty(): return false
		for key: String in ["owner", "root_owner", "born_ms", "until_ms", "next_ms", "activation"]:
			if not entry.get(key) is int: return false
		if entry.owner <= 0 or entry.owner >= world.objects.next_id or entry.root_owner <= 0 or entry.root_owner >= world.objects.next_id or entry.born_ms < 0 or entry.born_ms > world.elapsed_ms or entry.until_ms <= entry.born_ms or entry.until_ms > world.elapsed_ms + 60000 or entry.next_ms < entry.born_ms or entry.activation < 1 or entry.activation >= world.combat.next_activation or not entry.get("members") is Dictionary: return false
		if Defs.ACTIONS[entry.ability].entity.body == "companion" and (not world.actor_slots.has(id) or world.objects.records[id].get("body_origin") != "summoned"): return false
		var spec: Dictionary = Defs.ACTIONS[entry.ability].entity
		if not world.combat._point_valid(entry.get("anchor")) or entry.anchor.x < 0: return false
		var rec: Dictionary = world.objects.records[id]
		if not world.actor_slots.has(entry.owner) or not world.actor_slots.has(entry.root_owner) or id == entry.owner or id == entry.root_owner or root_owner(entry.owner) != entry.root_owner or records.has(entry.root_owner): return false
		if entry.until_ms != entry.born_ms + int(spec.life) or entry.until_ms <= world.elapsed_ms or entry.next_ms <= world.elapsed_ms - int(spec.period) or entry.next_ms > world.elapsed_ms + int(spec.period) or (entry.next_ms - entry.born_ms) % int(spec.period) != 0: return false
		if rec.get("side") != world.objects.records[entry.owner].get("side", 0) or rec.get("autonomous") != false: return false
		if spec.body == "static" and (world.actor_slots.has(id) or rec.kind != "combat_object" or rec.get("combat_receiver") != true or not rec.get("hp") is int or rec.hp < 1 or rec.hp > spec.max_hp): return false
		var key: String = "%d:%s" % [entry.root_owner, spec.group]
		groups[key] = int(groups.get(key, 0)) + 1
		if groups[key] > int(spec.limit): return false
		for actor: Variant in entry.members:
			if not actor is int or not world.actor_slots.has(actor) or not entry.members[actor] is Array or entry.members[actor].size() != spec.aura.size(): return false
			for slot: int in spec.aura.size():
				var status: Variant = entry.members[actor][slot]
				if not status is int or status < 0: return false
				if status == 0: continue # An absent contribution is repaired at the next pulse.
				if not world.effects.records.has(status): return false
				var effect: Dictionary = world.effects.records[status]
				if effect.target != actor or effect.source != id or effect.ability != entry.ability or effect.activation != entry.activation or effect.lifetime != "source" or effect.contribution != "aura_%d" % slot or effect.status_id != spec.aura[slot].status.id: return false
	for actor: int in world.actor_slots:
		if world.objects.records[actor].get("body_origin") == "summoned" and not records.has(actor): return false
	for status: int in world.effects.records:
		var effect: Dictionary = world.effects.records[status]
		if not records.has(effect.source) or not effect.contribution.begins_with("aura_"): continue
		var slots: Array = records[effect.source].members.get(effect.target, [])
		var slot_text: String = effect.contribution.trim_prefix("aura_")
		if not slot_text.is_valid_int(): return false
		var slot: int = int(slot_text)
		if slot < 0 or slot >= slots.size() or slots[slot] != status: return false
	return true
