extends RefCounted
## Sparse mutual acquaintance facts. Sentiment and professional trust are personal.
const LIMIT: int = 64
const GLOBAL_LIMIT: int = 4096
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")

static func key(a: int, b: int) -> String:
	return "%d:%d" % [mini(a, b), maxi(a, b)]

static func known(owner: RefCounted, a: int, b: int) -> bool:
	return owner.contacts.has(key(a, b))

static func _erase(owner: RefCounted, id: String) -> void:
	var contact: Dictionary = owner.contacts[id]
	for actor: int in [contact.a, contact.b]:
		owner._contacts_by_actor.get(actor, []).erase(id)
		if owner._contacts_by_actor.get(actor, []).is_empty(): owner._contacts_by_actor.erase(actor)
	owner.contacts.erase(id)

static func _victim(owner: RefCounted, ids: Array, now: int) -> String:
	var victim: String = ""
	for id: String in ids:
		var entry: Dictionary = owner.contacts[id]
		if owner.Requests.protects(owner, int(entry.a), int(entry.b), now): continue
		if victim.is_empty() or entry.last_ms < owner.contacts[victim].last_ms or (entry.last_ms == owner.contacts[victim].last_ms and id < victim): victim = id
	return victim

static func acknowledge(owner: RefCounted, world: RefCounted, a: int, b: int, now: int, seeded: bool = false) -> bool:
	if a == b or not world.objects.records.has(a) or not world.objects.records.has(b) or now < 0 or now > world.operation_time(): return false
	for actor: int in [a, b]:
		if not Beings.has(world.objects.records[actor], "contact"): return false
	if not seeded and not owner.in_contact(world, a, b, now): return false
	var id: String = key(a, b)
	if owner.contacts.has(id):
		owner.contacts[id].last_ms = maxi(int(owner.contacts[id].last_ms), now)
		return true
	# Choose every victim before changing either side of the shared fact.
	var victims: Array = []
	for actor: int in [a, b]:
		if owner._contacts_by_actor.get(actor, []).size() < LIMIT: continue
		var victim: String = _victim(owner, owner._contacts_by_actor[actor], now)
		if victim.is_empty(): return false
		if victim not in victims: victims.append(victim)
	if victims.is_empty() and owner.contacts.size() >= GLOBAL_LIMIT:
		var victim: String = _victim(owner, owner.contacts.keys(), now)
		if victim.is_empty(): return false
		victims.append(victim)
	for victim: String in victims: _erase(owner, victim)
	var entry: Dictionary = {"a": mini(a, b), "b": maxi(a, b), "since_ms": now, "last_ms": now, "basis": "seed" if seeded else "encounter"}
	owner.contacts[id] = entry
	_index(owner, id, entry)
	return true

static func _index(owner: RefCounted, id: String, entry: Dictionary) -> void:
	for actor: int in [entry.a, entry.b]:
		if not owner._contacts_by_actor.has(actor): owner._contacts_by_actor[actor] = []
		owner._contacts_by_actor[actor].append(id)

static func views(owner: RefCounted, actor: int) -> Dictionary:
	var result: Dictionary = {}
	for id: String in owner._contacts_by_actor.get(actor, []):
		var entry: Dictionary = owner.contacts[id]
		result[int(entry.b) if entry.a == actor else int(entry.a)] = {"since_ms": int(entry.since_ms), "last_ms": int(entry.last_ms), "basis": str(entry.basis)}
	return result

static func valid(owner: RefCounted, world: RefCounted) -> bool:
	if owner.contacts.size() > GLOBAL_LIMIT: return false
	owner._contacts_by_actor.clear()
	for id: Variant in owner.contacts:
		var entry: Variant = owner.contacts[id]
		if not id is String or not entry is Dictionary or entry.size() != 5: return false
		for field: String in ["a", "b", "since_ms", "last_ms"]:
			if not entry.get(field) is int: return false
		if entry.a < 1 or entry.a >= entry.b or entry.b >= world.objects.next_id or id != key(entry.a, entry.b) or entry.get("basis") not in ["encounter", "seed"]: return false
		if entry.since_ms < 0 or entry.last_ms < entry.since_ms or entry.last_ms > world.operation_time(): return false
		# Allocated identities may be gone. Encounters do not broadcast death.
		_index(owner, id, entry)
	for ids: Array in owner._contacts_by_actor.values():
		if ids.size() > LIMIT: return false
	return true
