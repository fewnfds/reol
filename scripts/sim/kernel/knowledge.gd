extends RefCounted
## Personal evidence, never live entity state or another perception bitmap.
const MinTimeQueue = preload("res://scripts/sim/execution/min_time_queue.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const STATE_FIELDS: Array = ["records"]
const SUBJECT_LIMIT: int = 128
const EXPERIENCE_LIMIT: int = 24
const HOP_LIMIT: int = 2
const MOBILE_FRESH_MS: int = 60000
const OBSERVATION_MS: int = 5000
const CHANNEL_LIMIT: int = 8
var records: Dictionary = {}
var observations: int = 0
var observe_usec: int = 0
# Transient protection cache scoped to one observer's observation slice.
var _batch_actor: int = 0
var _protected: Dictionary = {}
var _protection_dirty: bool = true
# Transient index of living observers. An admitted scan is served by DeferredWork.
var _observer_keys: Dictionary[int, String] = {}
var _next_observation := MinTimeQueue.new()
var _scans: Dictionary = {} # Transient cursor; overdue persisted due_ms rebuilds it.
var _planning_views: Dictionary = {} # Immutable projections, rebuilt from records.
# Amortize queue service and eye/protection setup across nearby targets.
const SCAN_TARGETS: int = 16

func record(actor: int) -> Dictionary:
	if not records.has(actor): records[actor] = {"due_ms": 0, "subjects": {}, "experiences": [], "next_revision": 1, "channels": {}}
	return records[actor]

func _revision(actor: int) -> int:
	var entry: Dictionary = record(actor)
	var result: int = entry.next_revision
	entry.next_revision += 1
	return result

func view(actor: int, target: int, at: int) -> Dictionary:
	var entry: Dictionary = records.get(actor, {}).get("subjects", {}).get(target, {})
	return {} if entry.is_empty() else _project(entry, at)

func _project(entry: Dictionary, at: int) -> Dictionary:
	var result: Dictionary = State.copy(entry.view)
	if result.kind == "actor" and at - int(entry.seen_ms) > MOBILE_FRESH_MS: result.tile = -1
	if not entry.teachings.is_empty():
		result["teaches"] = {}
		for method: String in entry.teachings: result.teaches[method] = int(entry.teachings[method].seen_ms)
	return result

func known(actor: int, at: int, include_mobile: bool = true) -> Dictionary:
	var result: Dictionary = {}
	for target: int in records.get(actor, {}).get("subjects", {}):
		if not include_mobile and records[actor].subjects[target].view.kind == "actor": continue
		result[target] = view(actor, target, at)
	return result

# Planning jobs may outlive this view's validity. Publish replacements and
# leave every version already held by a job untouched.
func planning_clues(actor: int, at: int) -> Dictionary:
	var owner: Dictionary = records.get(actor, {})
	if owner.is_empty(): return {}
	var previous: Dictionary = _planning_views.get(actor, {})
	var revision: int = int(owner.next_revision)
	if previous.get("revision", -1) == revision and at >= int(previous.at) and at < int(previous.expires): return previous.clues
	var old_versions: Dictionary = previous.get("versions", {})
	var old_clues: Dictionary = previous.get("clues", {})
	var versions: Dictionary = {}
	var clues: Dictionary = {}
	var expires: int = 9223372036854775807
	for target: int in owner.subjects:
		var entry: Dictionary = owner.subjects[target]
		var expired: bool = false
		if entry.view.kind == "actor" and int(entry.view.tile) >= 0:
			var expiry: int = int(entry.seen_ms) + MOBILE_FRESH_MS + 1
			expired = at >= expiry
			if not expired: expires = mini(expires, expiry)
		var version: int = int(entry.revision) * 2 + int(expired)
		versions[target] = version
		clues[target] = old_clues[target] if old_versions.get(target, -1) == version else Operations.freeze(_project(entry, at))
	clues.make_read_only()
	_planning_views[actor] = {"revision": revision, "at": at, "expires": expires, "versions": versions, "clues": clues}
	return clues

func review_inputs(actor: int, at: int, duty_targets: Dictionary, include_clues: bool = true) -> Dictionary:
	var clues: Dictionary = {}
	var observations: Dictionary = {}
	var subjects: Dictionary = records.get(actor, {}).get("subjects", {})
	for target: int in subjects:
		var entry: Dictionary = subjects[target]
		var raw: Dictionary = entry.view
		if not duty_targets.has(target) and not raw.has("post_revision") and not raw.has("source_qi_band"): continue
		if include_clues: clues[target] = _project(entry, at)
		observations[target] = {"at_ms": entry.seen_ms, "direct": entry.origin != "heard"}
	return {"clues": clues, "observations": observations}

func evidence(actor: int, target: int) -> Dictionary:
	var entry: Dictionary = records.get(actor, {}).get("subjects", {}).get(target, {})
	return {} if entry.is_empty() else {"revision": int(entry.revision)}

func account_view(actor: int, target: int, at: int) -> Dictionary:
	# The presentation reads already acquired evidence. Inspecting a panel does
	# not observe the world, renew a location or create a new memory.
	var entry: Dictionary = records.get(actor, {}).get("subjects", {}).get(target, {})
	if entry.is_empty(): return {}
	var refused: Dictionary = {}
	for experience: Dictionary in records.get(actor, {}).get("experiences", []):
		if experience.target == target and not can_attempt(actor, experience.operation, target, at): refused[experience.operation] = experience.reason
	return {"view": view(actor, target, at), "seen_ms": int(entry.seen_ms), "origin": str(entry.origin), "teaching_refusals": refused}

func read_channel(world: RefCounted, actor: int, channel: int, board: Dictionary, at: int) -> void:
	var entry: Dictionary = record(actor)
	var posts: Dictionary = {}
	var open: bool = false
	var self_view: Dictionary = world.operation_actor(actor)
	for id: int in board.posts:
		var post: Dictionary = board.posts[id]
		posts[id] = world.institutions.Channels.post_view(post)
		open = open or preload("res://scripts/sim/kernel/agency_institutions.gd")._actionable(self_view, posts[id], at)
		for clue: Dictionary in post.clues:
			var previous: Dictionary = entry.subjects.get(int(clue.view.id), {})
			if not previous.is_empty() and (int(previous.seen_ms) >= int(clue.seen_ms) or (previous.origin != "heard" and int(previous.view.get("tile", -1)) >= 0)): continue
			if post.issuer == actor:
				_store(world, actor, clue.view, str(clue.origin), int(clue.observer), int(clue.source), int(clue.seen_ms), at, int(clue.hops), {}, true)
			elif int(clue.hops) < HOP_LIMIT and int(clue.observer) != actor:
				_store(world, actor, clue.view, "heard", int(clue.observer), int(post.issuer), int(clue.seen_ms), at, int(clue.hops) + 1, {}, true)
	var misses: int = 0 if open and int(board.revision) != int(entry.channels.get(channel, {}).get("revision", -1)) else mini(6, int(entry.channels.get(channel, {}).get("empty_reads", 0)) + 1)
	entry.channels[channel] = {"at_ms": at, "revision": int(board.revision), "empty_reads": misses, "posts": posts}
	if entry.channels.size() > CHANNEL_LIMIT:
		var victim: int = 0
		for id: int in entry.channels:
			if id != channel and (victim == 0 or entry.channels[id].at_ms < entry.channels[victim].at_ms): victim = id
		if victim > 0: entry.channels.erase(victim)

func _store(world: RefCounted, actor: int, value: Dictionary, origin: String, observer: int, source: int, seen: int, at: int, hops: int, teachings: Dictionary = {}, focus: bool = false) -> bool:
	var subjects: Dictionary = record(actor).subjects
	var target: int = value.id
	var old: Dictionary = subjects.get(target, {})
	if _batch_actor == actor and (world.institutions.Access.personal_place(world.institutions, actor, target) or value.has("occupant") or old.get("view", {}).has("occupant")): _protection_dirty = true
	if origin == "heard" and not old.is_empty():
		if (seen <= int(old.absent_ms) and (value.kind != "actor" or value.tile == old.absent_tile)) or seen < int(old.seen_ms): return _merge_teachings(actor, target, teachings)
		if seen == int(old.seen_ms) and hops >= int(old.hops): return _merge_teachings(actor, target, teachings)
	var changed: bool = old.is_empty() or old.view != value or (value.kind == "actor" and value.tile >= 0 and at - int(old.seen_ms) > MOBILE_FRESH_MS)
	if not changed and not old.is_empty():
		# Better provenance or a newer mobile sighting can refresh metadata without
		# inventing a changed observation (and clearing an unrelated retry delay).
		var improved: bool = origin == "heard" and (hops < int(old.hops) or (value.kind == "actor" and seen > int(old.seen_ms)))
		if origin != "heard" or improved:
			# Forward refreshes may keep the earlier expiry as a conservative
			# bound, unless a view was already sampled after that deadline.
			if value.kind == "actor" and value.tile >= 0 and seen != int(old.seen_ms):
				var cached: Dictionary = _planning_views.get(actor, {})
				if not cached.is_empty() and (seen < int(old.seen_ms) or int(cached.at) - int(old.seen_ms) > MOBILE_FRESH_MS):
					_planning_views.erase(actor)
			old.merge({"origin": origin, "observer": observer, "source": source, "seen_ms": seen, "received_ms": at, "hops": hops}, true)
		if origin != "heard": old.merge({"absent_ms": -1, "absent_tile": -1}, true)
		return _merge_teachings(actor, target, teachings) or improved
	# Admission precedes revision/copy: an immediately forgotten sighting is not
	# new usable evidence and must not repeatedly wake the planner.
	if old.is_empty() and subjects.size() >= SUBJECT_LIMIT:
		var incoming: Dictionary = {"view": value, "origin": origin, "seen_ms": seen, "absent_ms": -1, "teachings": teachings}
		var protected: Dictionary
		# Include this newly acquired clue while deriving protection, exactly as
		# the previous insert-then-prune path did, without growing the stored set.
		if _batch_actor != actor or _protection_dirty:
			var candidates: Dictionary = subjects.duplicate()
			candidates[target] = incoming
			protected = world.livelihood.protected_targets(world, actor, candidates)
			if _batch_actor == actor: _protected = protected; _protection_dirty = false
		else: protected = _protected
		var victim: int = 0
		var worst: Dictionary = incoming
		var rank: int = _rank(incoming, target, protected, at)
		var action_target: int = int(world.actions.get(actor, {}).get("target", 0))
		var task_target: int = int(world.decisions.records.get(actor, {}).get("task", {}).get("target", 0))
		var protect_incoming: bool = focus or target == action_target or target == task_target
		for id: int in subjects:
			if id == action_target or id == task_target: continue
			var candidate: Dictionary = subjects[id]
			var priority: int = _rank(candidate, id, protected, at)
			if (victim == 0 and protect_incoming) or priority < rank or (priority == rank and (int(candidate.seen_ms) < int(worst.seen_ms) or (candidate.seen_ms == worst.seen_ms and id < (target if victim == 0 else victim)))):
				victim = id; worst = candidate; rank = priority
		if victim == 0:
			# The provisional candidate never became knowledge. Its dependencies
			# must not remain protected during this observation batch.
			if _batch_actor == actor and (value.has("occupant") or world.institutions.Access.personal_place(world.institutions, actor, target)): _protection_dirty = true
			return false
		if _batch_actor == actor and (subjects[victim].view.has("occupant") or world.institutions.Access.personal_place(world.institutions, actor, victim)): _protection_dirty = true
		subjects.erase(victim)
	var revision: int = _revision(actor) if changed else int(old.revision)
	subjects[target] = {"view": State.copy(value), "origin": origin, "observer": observer, "source": source, "seen_ms": seen,
		"received_ms": at, "hops": hops, "revision": revision, "absent_ms": int(old.get("absent_ms", -1)) if origin == "heard" else -1,
		"absent_tile": int(old.get("absent_tile", -1)) if origin == "heard" else -1, "teachings": State.copy(old.get("teachings", {}))}
	changed = _merge_teachings(actor, target, teachings) or changed
	return changed and subjects.has(target)

static func _rank(clue: Dictionary, id: int, protected: Dictionary, at: int) -> int:
	if protected.has(id): return 8
	if not clue.teachings.is_empty(): return 6
	if clue.view.kind != "actor" and clue.absent_ms >= 0 and at - int(clue.absent_ms) <= 300000: return 5
	return 0 if clue.view.tile < 0 else (1 if clue.view.kind == "pile" else (2 if clue.view.kind == "actor" else (4 if clue.origin == "seed" else 3)))

func _teaching_evidence(actor: int, target: int, method: String, incoming: Dictionary) -> bool:
	# Watching someone's body does not reveal their methods. Successful teaching
	# accounts keep their own event times when the physical clue is refreshed.
	var entry: Dictionary = records.get(actor, {}).get("subjects", {}).get(target, {})
	if entry.is_empty(): return false
	var old: Dictionary = entry.teachings.get(method, {})
	if not old.is_empty() and (incoming.seen_ms < old.seen_ms or (incoming.seen_ms == old.seen_ms and incoming.hops >= old.hops)): return false
	var changed: bool = old.is_empty() or incoming.seen_ms != old.seen_ms or incoming.hops < old.hops
	entry.teachings[method] = State.copy(incoming)
	if changed: entry.revision = _revision(actor)
	return changed

func _merge_teachings(actor: int, target: int, incoming: Dictionary) -> bool:
	var changed: bool = false
	for method: String in incoming: changed = _teaching_evidence(actor, target, method, incoming[method]) or changed
	return changed

func seed(world: RefCounted, actor: int, value: Dictionary, at: int = -1) -> void:
	# Scenario knowledge is explicit author input, not a remote World query.
	if at < 0: at = world.operation_time()
	var known_value: Dictionary = _public_value(value)
	known_value.erase("teaches")
	var teachings: Dictionary = {}
	for method: String in value.get("teaches", {}):
		teachings[method] = {"origin": "seed", "observer": 0, "source": 0, "seen_ms": int(value.teaches[method]), "received_ms": at, "hops": 0}
	_store(world, actor, known_value, "seed", 0, 0, at, at, 0, teachings)

static func _public_value(supplied: Dictionary) -> Dictionary:
	if supplied.kind != "actor":
		var value: Dictionary = State.copy(supplied)
		value.erase("guest")
		return value
	var value: Dictionary = {}
	for field: String in ["id", "kind", "definition", "tile", "owner", "organization", "sapient", "name"]:
		if supplied.has(field): value[field] = supplied[field]
	value["sapient"] = supplied.get("sapient", false)
	value["hp"] = 1 if int(supplied.get("hp", 1)) > 0 else 0
	return value

func _snapshot(world: RefCounted, target: int) -> Dictionary:
	if world.actor_slots.has(target):
		var value: Dictionary = _public_value(world.objects.records[target])
		value.tile = Terrain.index(Vector2i(world.combat.position(world, target).floor()))
		value.hp = 1 if world.combat.alive(world, target) else 0
		return value
	var value: Dictionary = world.operation_target(target)
	value.erase("guest")
	return value

func refresh(world: RefCounted, actor: int, target: int, at: int, focus: bool = false) -> bool:
	world.sight.sync(world)
	var eye: int = Terrain.index(Vector2i(world.combat.position(world, actor).floor()))
	return _refresh_from(world, actor, target, at, eye, world.sight.range_for(world, actor), focus)

func _refresh_from(world: RefCounted, actor: int, target: int, at: int, eye: int, radius: float, focus: bool = false) -> bool:
	if world.sight.observable(world, eye, radius, target):
		_store(world, actor, _snapshot(world, target), "seen", actor, actor, at, at, 0, {}, focus)
		var guest: int = int(world.objects.records[target].get("guest", 0))
		if guest > 0 and world.sight.observable(world, eye, radius, guest):
			_store(world, actor, _snapshot(world, guest), "seen", actor, actor, at, at, 0, {}, focus)
		return true
	var entry: Dictionary = records.get(actor, {}).get("subjects", {}).get(target, {})
	if not entry.is_empty() and int(entry.view.tile) >= 0 and world.sight.sees_tile(eye, int(entry.view.tile), radius):
		if _batch_actor == actor: _protection_dirty = true
		entry.absent_tile = entry.view.tile
		entry.view.tile = -1
		entry.absent_ms = at
		entry.revision = _revision(actor)
	return false

func created(world: RefCounted, actor: int, target: int, at: int) -> void:
	# Creator knows their actual submitted site even when it is beyond sight.
	_store(world, actor, _snapshot(world, target), "receipt", actor, actor, at, at, 0, {}, true)

func contacted(world: RefCounted, actor: int, target: int, at: int) -> void:
	# Called only after Society has established actual contact. Contact itself
	# conveys identity/presence even without vision, never private abilities.
	if not world.actor_slots.has(actor) or refresh(world, actor, target, at, true): return
	var object: Dictionary = world.objects.records[target]
	var value: Dictionary = {"id": target, "kind": object.kind, "definition": object.definition, "tile": Terrain.index(Vector2i(world.combat.position(world, target).floor())),
		"owner": int(object.owner), "organization": int(object.organization), "sapient": object.get("sapient", false)}
	if object.has("name"): value["name"] = object.name
	if object.kind == "actor": value["hp"] = 1 if world.combat.alive(world, target) else 0
	_store(world, actor, value, "receipt", actor, actor, at, at, 0, {}, true)

func observe(world: RefCounted, actor: int, at: int) -> void:
	var started: int = Time.get_ticks_usec()
	var entry: Dictionary = record(actor)
	_batch_actor = actor
	_protected = {}
	_protection_dirty = true
	world.sight.sync(world)
	var previous_revision: int = entry.next_revision
	var position: Vector2 = world.combat.position(world, actor)
	var eye: int = Terrain.index(Vector2i(position.floor()))
	var radius: float = world.sight.range_for(world, actor)
	var checked: Dictionary = {}
	for target: int in world.objects.nearby(position, radius, false):
		if checked.has(target): continue
		var value: Dictionary = world.objects.records[target]
		if value.kind == "plant" and int(value.get("host", 0)) == 0 and world.objects.count_inventory(target) == 0 and not entry.subjects.has(target) and not value.get("sapient", false) and not preload("res://scripts/sim/kernel/nature_defs.gd").DEFINITIONS[value.definition].has("stored_qi"): continue
		_refresh_from(world, actor, target, at, eye, radius)
		checked[target] = true
	# Reuse the existing body index. Before the first simulation slice only,
	# initialization has no index yet and uses the actual initial body IDs.
	var nearby: Array = world.combat.scan.nearby(position - Vector2.ONE * radius, position + Vector2.ONE * radius, true) if not world.combat.scan.ids.is_empty() else world.actor_slots.keys()
	for target: int in nearby:
		if target != actor and not checked.has(target) and world.actor_slots.has(target):
			_refresh_from(world, actor, target, at, eye, radius)
			checked[target] = true
	for target: int in entry.subjects.keys():
		var tile: int = entry.subjects[target].view.tile
		if not checked.has(target) and tile >= 0 and world.sight.sees_tile(eye, tile, radius): _refresh_from(world, actor, target, at, eye, radius)
	set_observation_due(world, actor, at + OBSERVATION_MS)
	if entry.next_revision != previous_revision: world.decisions.knowledge_changed(world, actor, at, "knowledge_observed")
	_batch_actor = 0
	_protected = {}
	observations += 1
	observe_usec += Time.get_ticks_usec() - started

func rebuild_observation_schedule(world: RefCounted) -> void:
	_observer_keys.clear()
	_next_observation.clear()
	for actor: int in world.actor_slots:
		if world.combat.alive(world, actor): track_actor(world, actor)

func track_actor(world: RefCounted, actor: int) -> void:
	# The shared heap orders ties by string. Pad positive int64 IDs to retain
	# numeric admission order, including when 2 and 10 have the same deadline.
	_observer_keys[actor] = "%019d" % actor
	_index_observation(world, actor, int(records.get(actor, {}).get("due_ms", 0)))

func set_observation_due(world: RefCounted, actor: int, at: int) -> void:
	record(actor).due_ms = at
	_index_observation(world, actor, at)

func _index_observation(world: RefCounted, actor: int, at: int) -> void:
	var key: String = _observer_keys.get(actor, "")
	if not key.is_empty() and not world.deferred.ready.has(world.deferred.key("observe", actor)):
		_next_observation.set_time(key, at)

func admit(world: RefCounted, actor: int, at: int, priority: int) -> void:
	# Ordinary and exploration admission both transfer the request to DeferredWork.
	var key: String = _observer_keys.get(actor, "")
	if not key.is_empty(): _next_observation.erase(key)
	world.deferred.request("observe", actor, at, priority)

func pulse(world: RefCounted, at: int) -> void:
	var quota: int = maxi(2, ceili(float(_observer_keys.size()) * 50.0 / OBSERVATION_MS) + 1)
	for index: int in quota:
		var key: String = _next_observation.first_through(at)
		if key.is_empty(): break
		var actor: int = int(key)
		admit(world, actor, int(records.get(actor, {}).get("due_ms", 0)), 2)

func service(world: RefCounted, actor: int, at: int) -> bool:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor):
		_scans.erase(actor)
		return true
	var began: int = Time.get_ticks_usec()
	var entry: Dictionary = record(actor)
	if not _scans.has(actor):
		world.sight.sync(world)
		if int(entry.due_ms) > at:
			# A direct observation may have met this dependency while queued.
			# DeferredWork.take removed the item before calling this service.
			_index_observation(world, actor, int(entry.due_ms))
			_finish_wait(world, actor, at)
			return true
		var position: Vector2 = world.combat.position(world, actor)
		var eye: int = Terrain.index(Vector2i(position.floor()))
		var radius: float = world.sight.range_for(world, actor)
		var targets: Dictionary = {}
		for target: int in world.objects.nearby(position, radius, false): targets[target] = true
		var nearby: Array = world.combat.scan.nearby(position - Vector2.ONE * radius, position + Vector2.ONE * radius, true) if not world.combat.scan.ids.is_empty() else world.actor_slots.keys()
		for target: int in nearby:
			if target != actor: targets[target] = true
		# Missing remembered subjects need a real look at their old location.
		# Enumeration conveys no information; each refresh still checks visibility.
		for target: int in entry.subjects:
			var tile: int = entry.subjects[target].view.tile
			if not targets.has(target) and tile >= 0 and world.sight.sees_tile(eye, tile, radius): targets[target] = true
		_scans[actor] = {"targets": targets.keys(), "cursor": 0, "revision": int(entry.next_revision)}
		observe_usec += Time.get_ticks_usec() - began
		return false
	var scan: Dictionary = _scans[actor]
	var previous_revision: int = int(entry.next_revision)
	world.sight.sync(world)
	var eye: int = Terrain.index(Vector2i(world.combat.position(world, actor).floor()))
	var radius: float = world.sight.range_for(world, actor)
	_batch_actor = actor; _protected = {}; _protection_dirty = true
	for item: int in SCAN_TARGETS:
		if int(scan.cursor) >= scan.targets.size(): break
		var target: int = scan.targets[scan.cursor]
		scan.cursor += 1
		var value: Dictionary = world.objects.records.get(target, {})
		if value.get("kind") == "plant" and int(value.get("host", 0)) == 0 and world.objects.count_inventory(target) == 0 and not entry.subjects.has(target) and not value.get("sapient", false) and not preload("res://scripts/sim/kernel/nature_defs.gd").DEFINITIONS[value.definition].has("stored_qi"): continue
		_refresh_from(world, actor, target, at, eye, radius)
	_batch_actor = 0; _protected = {}
	# Each acquired piece carries its own durable wake. A save between pieces
	# must not turn already-learned information into a permanently missed event.
	if entry.next_revision != previous_revision: world.decisions.knowledge_changed(world, actor, at, "knowledge_observed")
	var done: bool = int(scan.cursor) >= scan.targets.size()
	if done:
		set_observation_due(world, actor, at + OBSERVATION_MS)
		_scans.erase(actor)
		observations += 1
		_finish_wait(world, actor, at)
	observe_usec += Time.get_ticks_usec() - began
	return done

func _finish_wait(world: RefCounted, actor: int, at: int) -> void:
	var timers: Dictionary = world.decisions.wakeups.get(actor, {})
	if not timers.has("exploration_observe"): return
	timers.erase("exploration_observe")
	world.decisions._sync_next(actor)
	world.livelihood.think(world, actor, at)

func request(world: RefCounted, actor: int, at: int) -> void:
	# Arrivals request ordinary coverage; direct target/contact receipts remain
	# immediate. No nested whole-radius observation during a work commit.
	set_observation_due(world, actor, mini(int(records.get(actor, {}).get("due_ms", 0)), at))
	_scans.erase(actor) # A new arrival must enumerate its new location.

func stop(actor: int) -> void:
	var key: String = _observer_keys.get(actor, "")
	if not key.is_empty(): _next_observation.erase(key)
	_observer_keys.erase(actor)
	_scans.erase(actor)
	_planning_views.erase(actor)

func forget_actor(actor: int) -> void:
	stop(actor)
	records.erase(actor)

func deliver(world: RefCounted, recipient: int, giver: int, target: int, at: int, focus: bool = false) -> bool:
	var incoming: Dictionary = records.get(giver, {}).get("subjects", {}).get(target, {})
	if incoming.is_empty() or giver == recipient or target == recipient: return false
	var value: Dictionary = view(giver, target, at)
	value.erase("teaches")
	var changed: bool = false
	var teachings: Dictionary = {}
	for method: String in incoming.teachings:
		var account: Dictionary = incoming.teachings[method]
		if account.source == recipient or account.observer == recipient or account.hops >= HOP_LIMIT: continue
		var forwarded: Dictionary = account.duplicate()
		forwarded.merge({"origin": "heard", "source": giver, "received_ms": at, "hops": int(account.hops) + 1}, true)
		teachings[method] = forwarded
	# A newer local observation wins; the message itself is never a remote query.
	world.sight.sync(world)
	if world.sight.observed_position(world, recipient, target) != null:
		refresh(world, recipient, target, at, focus or not teachings.is_empty())
		changed = _merge_teachings(recipient, target, teachings)
	elif value.tile >= 0 and incoming.source != recipient and incoming.observer != recipient and incoming.hops < HOP_LIMIT:
		changed = _store(world, recipient, value, "heard", incoming.observer, giver, incoming.seen_ms, at, incoming.hops + 1, teachings, focus)
	elif not teachings.is_empty():
		if records.get(recipient, {}).get("subjects", {}).has(target): changed = _merge_teachings(recipient, target, teachings)
		else:
			# Knowing a named teacher exists does not imply knowing a current body,
			# live status or position. Retain only identity from the teaching account.
			var identity: Dictionary = {"id": target, "kind": value.kind, "definition": value.definition, "tile": -1,
				"sapient": value.sapient, "owner": value.owner, "organization": value.organization}
			if value.has("name"): identity["name"] = value.name
			var account: Dictionary = teachings.values()[0]
			changed = _store(world, recipient, identity, "heard", account.observer, giver, account.seen_ms, at, account.hops, teachings, focus)
	if changed: world.decisions.knowledge_changed(world, recipient, at, "knowledge_delivered")
	return changed

func share(world: RefCounted, giver: int, recipient: int, at: int) -> Dictionary:
	var candidates: Array = records.get(giver, {}).get("subjects", {}).keys()
	candidates.sort_custom(func(a: int, b: int):
		var left: Dictionary = records[giver].subjects[a]
		var right: Dictionary = records[giver].subjects[b]
		var left_time: int = _latest_account(left)
		var right_time: int = _latest_account(right)
		return left_time > right_time if left_time != right_time else a < b)
	for target: int in candidates:
		var before: Dictionary = State.copy(records.get(recipient, {}).get("subjects", {}).get(target, {}).get("teachings", {}))
		if deliver(world, recipient, giver, target, at):
			var entry: Dictionary = records[recipient].subjects[target]
			for method: String in entry.teachings:
				if before.get(method, {}) != entry.teachings[method]: return {"subject": target, "source": giver, "hops": int(entry.teachings[method].hops), "topic": "teaching", "method": method}
			return {"subject": target, "source": giver, "hops": entry.hops}
	return {}

static func _latest_account(entry: Dictionary) -> int:
	var result: int = entry.seen_ms
	for account: Dictionary in entry.teachings.values(): result = maxi(result, int(account.seen_ms))
	return result

func outcome(world: RefCounted, actor: int, operation: String, target: int, status: String, reason: String, at: int, experienced: bool = false) -> void:
	if not Operations.OPERATIONS.has(operation) or target <= 0 or not world.objects.records.has(actor): return
	var visible: bool = refresh(world, actor, target, at, experienced)
	if status == "interrupted": return # The original ActivityResult already records a technical interruption.
	if not visible:
		var response: bool = reason in ["teacher_does_not_know", "refused_need", "not_interested", "learner_already_understood"] and world.society.in_contact(world, actor, target, at)
		if (experienced or response) and Operations.OPERATIONS[operation].handler in ["learn", "teach"] and world.objects.records.has(target):
			# Actual face-to-face learning conveys only contact identity and the
			# specific teaching result, even when the participant has no vision.
			var object: Dictionary = world.objects.records[target]
			var contact: Dictionary = {"id": target, "kind": object.kind, "definition": object.definition, "tile": Terrain.index(Vector2i(world.combat.position(world, target).floor())),
				"owner": int(object.owner), "organization": int(object.organization), "sapient": object.get("sapient", false)}
			if object.has("name"): contact["name"] = object.name
			if object.kind == "actor": contact["hp"] = 1 if world.combat.alive(world, target) else 0
			_store(world, actor, contact, "receipt", actor, actor, at, at, 0, {}, true)
		elif not ((status == "completed" and experienced) or (reason == "target_gone" and records.get(actor, {}).get("subjects", {}).get(target, {}).get("absent_ms", -1) == at)): return
	var entry: Dictionary = record(actor)
	for index: int in range(entry.experiences.size() - 1, -1, -1):
		if entry.experiences[index].operation == operation and entry.experiences[index].target == target:
			if entry.experiences[index].reason == "teacher_does_not_know" and status != "completed" and reason != "teacher_does_not_know" and at < int(entry.experiences[index].at_ms) + 300000: return
			entry.experiences.remove_at(index)
	entry.experiences.append({"operation": operation, "target": target, "status": status, "reason": reason, "at_ms": at})
	if entry.experiences.size() > EXPERIENCE_LIMIT:
		# Routine receipts cannot erase a still-relevant specific refusal. The
		# detailed history remains bounded even when every entry is significant.
		var victim: int = 0
		for index: int in entry.experiences.size():
			var previous: Dictionary = entry.experiences[index]
			if previous.reason != "teacher_does_not_know" or at >= int(previous.at_ms) + 300000:
				victim = index; break
		entry.experiences.remove_at(victim)
	var definition: Dictionary = Operations.OPERATIONS[operation]
	if definition.handler == "learn" and (status == "completed" or reason == "teacher_does_not_know"):
		if status == "completed" and experienced:
			_teaching_evidence(actor, target, definition.learning_method, {"origin": "receipt", "observer": actor, "source": actor, "seen_ms": at, "received_ms": at, "hops": 0})

func learned(world: RefCounted, learner: int, teacher: int, method: String, at: int) -> void:
	# Both entry directions yield the learner's same first-hand teacher evidence.
	contacted(world, learner, teacher, at)
	_teaching_evidence(learner, teacher, method, {"origin": "receipt", "observer": learner, "source": learner, "seen_ms": at, "received_ms": at, "hops": 0})

func can_attempt(actor: int, operation: String, target: int, at: int) -> bool:
	var definition: Dictionary = Operations.OPERATIONS.get(operation, {})
	if definition.is_empty(): return true # P5 may retain feedback for trusted non-operation tasks.
	for experience: Dictionary in records.get(actor, {}).get("experiences", []):
		if experience.target != target or experience.operation != operation or experience.reason != "teacher_does_not_know" or at >= int(experience.at_ms) + 300000: continue
		return int(view(actor, target, at).get("teaches", {}).get(definition.learning_method, -1)) > int(experience.at_ms)
	return true

func valid(world: RefCounted) -> bool:
	for actor: Variant in records:
		if not actor is int or not world.objects.records.has(actor): return false
		var entry: Variant = records[actor]
		if not entry is Dictionary or entry.size() != 5 or not entry.get("due_ms") is int or entry.due_ms < 0 or entry.due_ms > world.elapsed_ms + OBSERVATION_MS: return false
		if not entry.get("channels") is Dictionary or entry.channels.size() > CHANNEL_LIMIT: return false
		for channel: Variant in entry.channels:
			var account: Variant = entry.channels[channel]
			if not channel is int or channel < 1 or channel >= world.objects.next_id or not account is Dictionary or account.size() != 4: return false
			if not account.get("at_ms") is int or account.at_ms < 0 or account.at_ms > world.elapsed_ms or not account.get("revision") is int or account.revision < 0 or account.revision > 999999999999 or not account.get("empty_reads") is int or account.empty_reads < 0 or account.empty_reads > 6 or not account.get("posts") is Dictionary or account.posts.size() > world.institutions.Channels.POST_LIMIT: return false
			for matter: Variant in account.posts:
				if not matter is int or not world.institutions.Channels.public_valid(world.institutions, world, account.posts[matter]) or account.posts[matter].matter != matter: return false
		if not entry.get("next_revision") is int or entry.next_revision < 1 or entry.next_revision > 999999999999: return false
		if not entry.get("subjects") is Dictionary or entry.subjects.size() > SUBJECT_LIMIT: return false
		for target: Variant in entry.subjects:
			var clue: Variant = entry.subjects[target]
			if not target is int or target <= 0 or target >= world.objects.next_id or not clue is Dictionary or clue.size() != 11: return false
			if clue.get("origin") not in ["seed", "seen", "receipt", "heard"] or not clue.get("view") is Dictionary: return false
			for field: String in ["observer", "source"]:
				if not clue.get(field) is int or clue[field] < 0 or clue[field] >= world.objects.next_id: return false
			if not clue.get("seen_ms") is int or not clue.get("received_ms") is int or clue.seen_ms < 0 or clue.received_ms < clue.seen_ms or clue.received_ms > world.elapsed_ms: return false
			if not clue.get("hops") is int or clue.hops < 0 or clue.hops > HOP_LIMIT or (clue.origin == "heard") != (clue.hops > 0): return false
			if clue.origin == "seed":
				if clue.source != 0 or clue.observer != 0: return false
			elif clue.origin in ["seen", "receipt"]:
				if clue.source != actor or clue.observer != actor: return false
			elif clue.source <= 0 or clue.source == actor or clue.observer == actor: return false
			if not clue.get("revision") is int or clue.revision < 1 or clue.revision >= entry.next_revision or not clue.get("absent_ms") is int or clue.absent_ms < -1 or clue.absent_ms > world.elapsed_ms: return false
			if not clue.get("absent_tile") is int or clue.absent_tile < -1 or clue.absent_tile >= Terrain.SIZE * Terrain.SIZE or (clue.absent_tile == -1) != (clue.absent_ms == -1): return false
			if not _valid_view(clue.view, target, world.objects.next_id, world.elapsed_ms): return false
			if not clue.get("teachings") is Dictionary or clue.teachings.size() > Growth.Defs.METHODS.size(): return false
			for method: Variant in clue.teachings:
				if not method is String or not Growth.Defs.METHODS.has(method) or not _valid_teaching(clue.teachings[method], actor, world.objects.next_id, world.elapsed_ms): return false
		if not entry.get("experiences") is Array or entry.experiences.size() > EXPERIENCE_LIMIT: return false
		var seen: Dictionary = {}
		for experience: Variant in entry.experiences:
			if not experience is Dictionary or experience.size() != 5 or not experience.get("operation") is String or not Operations.OPERATIONS.has(experience.operation): return false
			if not experience.get("target") is int or experience.target <= 0 or experience.target >= world.objects.next_id or experience.get("status") not in ["completed", "refused", "failed", "interrupted"]: return false
			if not experience.get("reason") is String or not experience.reason.is_valid_identifier() or experience.reason.length() > 80 or not experience.get("at_ms") is int or experience.at_ms < 0 or experience.at_ms > world.elapsed_ms: return false
			var key: String = "%s:%d" % [experience.operation, experience.target]
			if seen.has(key): return false
			seen[key] = true
	return true

static func _valid_teaching(account: Variant, actor: int, next_id: int, now: int) -> bool:
	if not account is Dictionary or account.size() != 6 or account.get("origin") not in ["seed", "receipt", "heard"]: return false
	for field: String in ["observer", "source"]:
		if not account.get(field) is int or account[field] < 0 or account[field] >= next_id: return false
	if not account.get("seen_ms") is int or not account.get("received_ms") is int or account.seen_ms < 0 or account.received_ms < account.seen_ms or account.received_ms > now: return false
	if not account.get("hops") is int or account.hops < 0 or account.hops > HOP_LIMIT or (account.origin == "heard") != (account.hops > 0): return false
	if account.origin == "seed": return account.observer == 0 and account.source == 0
	if account.origin == "receipt": return account.observer == actor and account.source == actor
	return account.source > 0 and account.source != actor and account.observer != actor

static func _valid_view(value: Dictionary, target: int, next_id: int, now: int) -> bool:
	for field: Variant in value:
		if field not in ["id", "kind", "definition", "name", "tile", "capacity", "reserved_capacity", "owner", "organization", "sapient", "hp", "inventory", "stage", "process", "access_dependencies", "contents", "services", "post_revision", "host", "occupant", "injured", "water_band", "source_qi_band", "work_department", "storage_policy", "eaves"]: return false
	if value.has("work_department") and (not value.work_department is int or value.work_department < 0 or value.work_department > 1000000000): return false
	if value.has("storage_policy") and not Stock.valid_storage_policy(value.storage_policy, next_id): return false
	if value.has("name") and (not value.name is String or value.name.length() > 256): return false
	if value.has("source_qi_band") and (value.get("kind") != "plant" or not value.source_qi_band is int or (value.source_qi_band not in [-1, 0] and value.source_qi_band not in Growth.SOURCE_QI_STEPS)): return false
	for reference: String in ["host", "occupant"]:
		if value.has(reference) and (not value[reference] is int or value[reference] < 0 or value[reference] >= next_id): return false
	if value.has("host") or value.has("injured") or value.has("water_band"):
		if value.get("kind") != "plant" or not value.get("injured") is bool or not value.get("water_band") is int or value.water_band < -1 or value.water_band > 4 or not value.has("host"): return false
	if value.has("eaves") and (value.get("kind") != "wall" or not value.eaves is bool): return false
	if value.has("occupant") and (value.get("kind") in ["actor", "plant", "blueprint"] or not preload("res://scripts/sim/kernel/operation_query.gd").BUILDINGS.get(value.get("definition", ""), {}).get("capabilities", {}).has("cultivation")): return false
	if value.has("post_revision"):
		if not value.post_revision is int or value.post_revision < 0 or value.post_revision > 999999999999: return false
		if not preload("res://scripts/sim/kernel/operation_query.gd").BUILDINGS.get(value.get("definition", ""), {}).get("capabilities", {}).has("records") or value.get("kind") in ["actor", "blueprint"]: return false
	if not value.get("id") is int or value.id != target or not value.get("kind") is String or value.kind.is_empty() or value.kind.length() > 64 or not value.get("definition") is String or value.definition.is_empty() or value.definition.length() > 128: return false
	if not value.get("tile") is int or value.tile < -1 or value.tile >= Terrain.SIZE * Terrain.SIZE or not value.get("sapient") is bool: return false
	if not value.get("owner") is int or value.owner < 0 or value.owner >= next_id or not value.get("organization") is int or value.organization < 0 or (value.owner > 0 and value.organization > 0): return false
	if value.kind == "actor":
		if value.has("hp") and (not value.hp is int or value.hp not in [0, 1]): return false
		for private_field: String in ["inventory", "capacity", "process", "access_dependencies", "contents", "services"]:
			if value.has(private_field): return false
	else:
		if value.has("services"):
			if not value.services is Dictionary or value.services.size() > 2: return false
			for service: Variant in value.services:
				if service not in ["rest", "eat"] or not value.services[service] is bool or not value.services[service]: return false
		if value.has("capacity") and (not value.capacity is int or value.capacity < -1 or value.capacity > 1000000000): return false
		if value.has("reserved_capacity") and (not value.reserved_capacity is int or value.reserved_capacity < 0 or value.reserved_capacity > 1000000000): return false
		if value.has("inventory"):
			if not value.inventory is Dictionary or value.inventory.size() > 256: return false
			for item: Variant in value.inventory:
				if not item is String or not Items.valid(item) or not value.inventory[item] is int or value.inventory[item] <= 0 or value.inventory[item] > 1000000000: return false
		if value.has("contents"):
			if not value.contents is Dictionary or value.contents.size() > 256 or not value.has("inventory") or value.contents.keys().size() != value.inventory.keys().size(): return false
			for item: Variant in value.contents:
				if not item is String or not value.inventory.has(item) or not value.contents[item] is Array or value.contents[item].is_empty() or value.contents[item].size() > 256: return false
				var total: int = 0
				var seen: Dictionary = {}
				for group: Variant in value.contents[item]:
					if not group is Dictionary or group.size() != 5 or not group.get("owner") is int or group.owner < 0 or group.owner >= next_id or not group.get("organization") is int or group.organization < 0 or (group.owner > 0 and group.organization > 0) or not group.get("entrusted") is bool or not group.get("count") is int or group.count <= 0 or group.count > 1000000000: return false
					if not group.get("available") is int or group.available < 0 or group.available > group.count: return false
					var key: String = "%d:%d:%s" % [group.owner, group.organization, str(group.entrusted)]
					if seen.has(key): return false
					seen[key] = true; total += int(group.count)
				if total != value.inventory[item]: return false
	if value.has("stage") and (not value.stage is int or value.stage < 0 or value.stage > 100): return false
	if value.has("process"):
		if not value.process is Dictionary: return false
		var process: Dictionary = value.process
		if not process.is_empty():
			if process.size() != 9 or not process.get("id") is int or process.id <= 0 or not process.get("operation") is String or Operations.OPERATIONS.get(process.operation, {}).get("recipe", {}).is_empty(): return false
			if not process.get("paused") is bool or not process.get("passive_remaining_ms") is int or process.passive_remaining_ms < 0 or process.passive_remaining_ms > 300000: return false
			if not process.get("output_owner") is int or process.output_owner < 0 or process.output_owner >= next_id or not process.get("output_organization") is int or process.output_organization < 0 or (process.output_owner > 0 and process.output_organization > 0): return false
			if process.get("stage") not in ["work", "passive", "finish"] or not process.get("remaining_ms") is int or process.remaining_ms < 0 or process.remaining_ms > 300000 or not process.get("ready_ms") is int or process.ready_ms < 0 or process.ready_ms > now + 86400000: return false
	if value.has("access_dependencies"):
		if not value.access_dependencies is Dictionary or value.access_dependencies.size() > 2: return false
		for operation: Variant in value.access_dependencies:
			if operation not in ["construct", "demolish"] or not value.access_dependencies[operation] is Array or value.access_dependencies[operation].size() > 64: return false
			for dependency: Variant in value.access_dependencies[operation]:
				if not dependency is Dictionary or dependency.size() != 4 or not dependency.get("id") is int or dependency.id <= 0 or dependency.id >= next_id or dependency.get("operation") not in ["uproot", "demolish"]: return false
				if not dependency.get("owner") is int or dependency.owner < 0 or dependency.owner >= next_id or not dependency.get("organization") is int or dependency.organization < 0 or (dependency.owner > 0 and dependency.organization > 0): return false
	return true
