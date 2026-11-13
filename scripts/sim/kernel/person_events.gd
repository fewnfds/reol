extends RefCounted
## Committed personal facts, bounded independently of population and play time.
## The player keeps a reserved history; NPC entries share a fixed-size ring.
const State = preload("res://scripts/sim/kernel/state.gd")
const PLAYER_LIMIT: int = 256
const NPC_LIMIT: int = 64
const RECENT_LIMIT: int = 2048
const STATE_FIELDS: Array = ["player", "recent", "sequence", "cursor"]
var player: Array = []
var recent: Array = []
var sequence: int = 0
var cursor: int = 0
var _by_actor: Dictionary = {}
var _views: Dictionary = {}
var _versions: Dictionary = {}
var _revision: int = 0

func record(actor: int, event: Dictionary) -> void:
	var entries: Array = player if actor == 1 else _by_actor.get(actor, [])
	# Consecutive continuous damage is one range with summed, real consequences.
	if not entries.is_empty():
		var previous: Dictionary = entries.back()
		if event.kind == "thermal_hit" and previous.kind == event.kind and previous.get("cause") == event.get("cause") and int(event.at_ms) - int(previous.at_ms) <= 2000:
			previous.at_ms = event.at_ms
			previous.damage += event.damage
			previous.absorbed += event.absorbed
			previous.tolerance = event.tolerance
			previous.hp = event.hp
			previous.temperature = event.temperature
			previous.count += 1
			_changed(actor)
			return
	sequence += 1
	var entry: Dictionary = event.duplicate(true)
	entry["seq"] = sequence
	entry["actor"] = actor
	entry["first_ms"] = int(event.at_ms)
	entry["count"] = 1
	if actor == 1:
		player.append(entry)
		if player.size() > PLAYER_LIMIT: player.pop_front()
	else:
		if recent.size() < RECENT_LIMIT:
			recent.append(entry)
		else:
			var old: Dictionary = recent[cursor]
			var old_actor: int = old.actor
			if _by_actor.has(old_actor):
				_by_actor[old_actor].erase(old)
				if _by_actor[old_actor].is_empty():
					_by_actor.erase(old_actor)
				_changed(old_actor)
			recent[cursor] = entry
		cursor = (cursor + 1) % RECENT_LIMIT
		entries = _by_actor.get(actor, [])
		entries.append(entry)
		if entries.size() > NPC_LIMIT: entries.pop_front()
		_by_actor[actor] = entries
	_changed(actor)

func _changed(actor: int) -> void:
	_revision += 1
	_views.erase(actor)
	if actor != 1 and not _by_actor.has(actor): _versions.erase(actor)
	else: _versions[actor] = _revision

func view(actor: int) -> Array:
	if actor != 1 and not _by_actor.has(actor): return []
	if not _views.has(actor): _views[actor] = State.copy(player if actor == 1 else _by_actor.get(actor, []))
	return _views[actor] # Immutable until replaced; publication never borrows a log.

func version(actor: int) -> int:
	return int(_versions.get(actor, 0))

func accept(event: Dictionary, actors: Dictionary) -> void:
	var actor: int = int(event.get("actor", 0))
	if event.kind == "hit":
		var target: int = int(event.get("target", 0))
		if actors.has(target):
			# Taking a hit conveys damage, not the identity of a hidden attacker.
			record(target, {"kind": "hit", "damage": event.damage, "at_ms": event.at_ms})
		if actors.has(actor): record(actor, {"kind": "hit_dealt", "damage": event.damage, "at_ms": event.at_ms})
	elif actors.has(actor):
		record(actor, event)

func command(input: Dictionary, receipt: Dictionary) -> void:
	var actor: int = int(input.get("actor", 1))
	var action: String = str(input.get("kind", ""))
	if receipt.get("placed", false):
		record(actor, {"kind": "placed", "action": action, "target": receipt.target, "at_ms": receipt.at_ms})
	if not receipt.ok:
		record(actor, {"kind": "rejected", "action": action, "reason": receipt.reason, "at_ms": receipt.at_ms})
	elif action not in ["heal", "ability", "attack"]:
		record(actor, {"kind": "order", "action": action, "target": int(input.get("target", 0)), "at_ms": receipt.at_ms})

func rebuild(now: int) -> bool:
	if player.size() > PLAYER_LIMIT or recent.size() > RECENT_LIMIT or sequence < 0 or cursor < 0 or cursor >= RECENT_LIMIT or (recent.size() < RECENT_LIMIT and cursor != recent.size()): return false
	_by_actor.clear()
	_views.clear()
	_versions.clear()
	_revision = 0
	var seen: Dictionary = {}
	var ordered: Array = recent.slice(cursor) + recent.slice(0, cursor) if recent.size() == RECENT_LIMIT else recent
	for entry: Variant in player + ordered:
		if not entry is Dictionary or not entry.get("actor") is int or entry.actor <= 0 or not entry.get("seq") is int or entry.seq <= 0 or entry.seq > sequence or seen.has(entry.seq): return false
		if not entry.get("kind") is String or not entry.get("at_ms") is int or not entry.get("first_ms") is int or entry.first_ms < 0 or entry.at_ms < entry.first_ms or entry.at_ms > now or not entry.get("count") is int or entry.count < 1: return false
		for value: Variant in entry.values():
			if typeof(value) not in [TYPE_STRING, TYPE_INT, TYPE_FLOAT, TYPE_BOOL] or (value is float and not is_finite(value)): return false
		if not _payload_valid(entry): return false
		seen[entry.seq] = true
		if entry.actor != 1:
			var entries: Array = _by_actor.get(entry.actor, [])
			entries.append(entry)
			if entries.size() > NPC_LIMIT: entries.pop_front()
			_by_actor[entry.actor] = entries
	for entry: Dictionary in player:
		if entry.actor != 1: return false
	for entry: Dictionary in recent:
		if entry.actor == 1: return false
	return true

func _payload_valid(entry: Dictionary) -> bool:
	match str(entry.kind):
		"thermal_hit":
			for key: String in ["absorbed", "damage", "tolerance", "hp", "temperature"]:
				if not entry.get(key) is int and not entry.get(key) is float: return false
			return entry.get("cause") in ["cold", "heat"] and entry.damage >= 0 and entry.absorbed >= 0
		"hit", "hit_dealt": return entry.get("damage") is int and entry.damage >= 0
		"order", "rejected", "placed": return entry.get("action") is String and entry.get("target", 0) is int
		_: return true
