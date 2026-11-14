extends Node
## Small synthesized placeholders. Only adopted, visible committed events make sound.
const RATE: int = 22050
var _voices: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _pending: Array[Dictionary] = []
var _epoch: int = -1
var _last: Dictionary = {}

func _ready() -> void:
	for index: int in 6:
		var voice := AudioStreamPlayer.new()
		voice.volume_db = -19.0
		add_child(voice)
		_voices.append(voice)
	_streams.swish = _tone(0.075, 520, 160, 0.35)
	_streams.shot = _tone(0.085, 750, 320, 0.12)
	_streams.hit = _tone(0.065, 180, 60, 0.55)
	_streams.death = _tone(0.13, 130, 38, 0.3)

func _tone(seconds: float, from: float, to: float, noise: float) -> AudioStreamWAV:
	var bytes := PackedByteArray()
	var count: int = int(seconds * RATE)
	bytes.resize(count * 2)
	for index: int in count:
		var time: float = float(index) / RATE
		var envelope: float = pow(1.0 - float(index) / count, 2.0) * minf(1.0, time * 1000.0)
		var phase: float = TAU * (from * time + (to - from) * time * time / (2.0 * seconds))
		var sample: float = (sin(phase) * (1.0 - noise) + sin(index * 13.371 + sin(index * 0.713) * 83.0) * noise) * envelope
		bytes.encode_u16(index * 2, int(sample * 26000) & 65535)
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
		for voice: AudioStreamPlayer in _voices: voice.stop()
	for event: Dictionary in outcomes:
		if int(event.get("epoch", frame.epoch)) != frame.epoch: continue
		if event.kind not in ["action_active", "hit", "death"]: continue
		var actor: int = int(event.get("target", event.actor)) if event.kind == "hit" else int(event.actor)
		var slot: int = int(frame.actor_slots.get(actor, -1))
		if slot < 0 or (fog and frame.visible[slot] == 0): continue
		if frame.positions[slot].distance_to(frame.positions[frame.actor_slots[1]]) > 22.0: continue
		var kind: String = event.kind
		if kind == "action_active": kind = "shot" if event.get("action") in ["shot", "fan"] else "swish"
		if _pending.size() >= 64: _pending.pop_front()
		_pending.append({"kind": kind, "at_ms": event.at_ms})

func advance(now: int) -> void:
	for index: int in range(_pending.size() - 1, -1, -1):
		var event: Dictionary = _pending[index]
		if event.at_ms > now: continue
		_pending.remove_at(index)
		if now - int(event.at_ms) > 180 or now - int(_last.get(event.kind, -1000)) < 45: continue
		_last[event.kind] = now
		for voice: AudioStreamPlayer in _voices:
			if voice.playing: continue
			voice.stream = _streams[event.kind]
			voice.play()
			break
