extends Node
## Bounded sound layers scheduled against displayed world time.
const Impact = preload("res://scripts/presentation/impact.gd")
const RATE: int = 22050
var volume: float = 0.7
var _voices: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _pending: Array[Dictionary] = []
var _epoch: int = -1
var _last: Dictionary = {}
var _accents: Dictionary = {}
var _seen: Dictionary = {}
var _variant: int = 0
var played: Dictionary = {}

func _priority(kind: String) -> int:
	return {"hurt": 8, "warning": 7, "break": 6, "death": 5, "heavy": 4, "armor": 3, "hit": 2}.get(kind, 1)

func _ready() -> void:
	for index: int in 8:
		var voice := AudioStreamPlayer.new()
		add_child(voice)
		_voices.append(voice)
	for row: Array in [["swish", 0.075, 520, 160, 0.35], ["swing_heavy", 0.11, 360, 95, 0.38], ["shot", 0.07, 750, 320, 0.12], ["hit", 0.075, 210, 68, 0.48], ["heavy", 0.12, 135, 38, 0.50], ["break", 0.14, 320, 42, 0.45], ["armor", 0.065, 970, 460, 0.14], ["hurt", 0.11, 160, 52, 0.58], ["death", 0.13, 130, 38, 0.3], ["step", 0.06, 310, 630, 0.20], ["evade", 0.055, 880, 1180, 0.08], ["warning", 0.09, 430, 550, 0.10]]:
		var variants: Array[AudioStreamWAV] = []
		for variant: int in 3: variants.append(_tone(row[1], row[2] * (0.96 + variant * 0.04), row[3], row[4]))
		_streams[row[0]] = variants

func _tone(seconds: float, from: float, to: float, noise: float) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	var count: int = int(seconds * RATE)
	bytes.resize(count * 2)
	for index: int in count:
		var time: float = float(index) / RATE
		var envelope: float = pow(1.0 - float(index) / count, 2.0) * minf(1.0, time * 700.0)
		var phase: float = TAU * (from * time + (to - from) * time * time / (2.0 * seconds))
		var sample: float = (sin(phase) * (1.0 - noise) + sin(index * 13.371 + sin(index * 0.713) * 83.0) * noise) * envelope
		bytes.encode_u16(index * 2, int(sample * 20000) & 65535)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = RATE
	stream.data = bytes
	return stream

func adopt(frame: RefCounted, outcomes: Array, fog: bool) -> void:
	if _epoch != frame.epoch:
		_epoch = frame.epoch
		_pending.clear()
		_last.clear()
		_accents.clear()
		_seen.clear()
		for voice: AudioStreamPlayer in _voices: voice.stop()
	for event: Dictionary in outcomes:
		if int(event.get("epoch", frame.epoch)) != frame.epoch or not Impact.visible(frame, event, fog): continue
		var kind: String = Impact.tone(event)
		var key: String = Impact.key(event)
		if kind.is_empty() or _seen.has(key): continue
		_seen[key] = event.at_ms
		if _pending.size() >= 64: _pending.pop_front()
		var layer: String = "contact" if event.kind == "hit" and kind != "hurt" else kind
		_pending.append({"kind": kind, "at_ms": event.at_ms, "group": "%s:%s:%s" % [event.actor, event.get("activation", 0), layer]})
	for key: String in _seen.keys():
		if frame.world_ms - int(_seen[key]) > 2000: _seen.erase(key)

func advance(now: int) -> void:
	var ready: Dictionary = {}
	for index: int in range(_pending.size() - 1, -1, -1):
		var event: Dictionary = _pending[index]
		if int(event.at_ms) > now: continue
		_pending.remove_at(index)
		if now - int(event.at_ms) > 180: continue
		# One contact accent per activation, even when targets react differently.
		if not ready.has(event.group) or _priority(event.kind) > _priority(ready[event.group].kind): ready[event.group] = event
	var ordered: Array = ready.values()
	ordered.sort_custom(func(a: Dictionary, b: Dictionary): return _priority(a.kind) > _priority(b.kind))
	for event: Dictionary in ordered:
		var kind: String = event.kind
		var previous: Dictionary = _accents.get(event.group, {})
		if not previous.is_empty() and now - int(previous.at) < 2000 and _priority(kind) <= int(previous.priority): continue
		if now - int(_last.get(kind, -10000)) < 35: continue
		var important: bool = kind in ["hurt", "break", "death", "warning"]
		var chosen: AudioStreamPlayer
		if not previous.is_empty() and previous.voice.playing and previous.voice.get_meta("accent_group", "") == event.group:
			chosen = previous.voice # Upgrade the existing accent rather than stacking it.
		elif kind in ["hurt", "warning"]:
			chosen = _voices[7 if kind == "hurt" else 6]
		else:
			for index: int in 6:
				if not _voices[index].playing: chosen = _voices[index]; break
			if chosen == null and important: chosen = _voices[5]
		if chosen == null: continue
		chosen.stop()
		chosen.set_meta("accent_group", event.group)
		_accents[event.group] = {"at": now, "priority": _priority(kind), "voice": chosen}
		_last[kind] = now
		chosen.stream = _streams[kind][_variant % 3]
		_variant += 1
		chosen.volume_db = linear_to_db(maxf(0.00001, volume)) - (14.0 if important else 19.0)
		chosen.play()
		played[kind] = int(played.get(kind, 0)) + 1
	for key: String in _last.keys():
		if now - int(_last[key]) > 2000: _last.erase(key)
	for key: String in _accents.keys():
		if now - int(_accents[key].at) > 2000: _accents.erase(key)
