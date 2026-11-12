extends RefCounted
## Static influence is baked once. Moving sources are queried only by receivers.
## Empty ground has no thermal history; units and rooms carry their own inertia.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const CHANNELS: int = 7 # heat, cold, metal, wood, water, fire, earth
const RADIUS: int = 8
const BUCKET: int = 16
const BUCKETS: int = Terrain.SIZE / BUCKET
var terrain: RefCounted
var field := PackedInt32Array()
var source_cells := PackedInt32Array()
var source_channels := PackedInt32Array()
var source_strengths := PackedInt32Array()
var enabled := PackedByteArray()
var mobile_cells := PackedInt32Array()
var mobile_units := PackedInt32Array()
var heads := PackedInt32Array()
var links := PackedInt32Array()
var room_temperature := PackedFloat32Array()
var tides := PackedInt32Array([100, 100, 100, 100, 100])
var rng := RandomNumberGenerator.new()
var revision: int = 0
var updates: int = 0
var samples: int = 0


func initialize(ground: RefCounted, actor_count: int) -> void:
	terrain = ground
	rng.seed = 730177
	field.resize(Terrain.SIZE * Terrain.SIZE * CHANNELS)
	var used: Dictionary = {}
	while source_cells.size() < 96:
		var tile: int = terrain.nearest_open(Terrain.index(Vector2i(rng.randi_range(174, 262), rng.randi_range(174, 262))))
		if used.has(tile):
			continue
		used[tile] = true
		var id: int = source_cells.size()
		source_cells.append(tile)
		source_channels.append(id % CHANNELS)
		source_strengths.append(50 + posmod(id * 13, 120))
		enabled.append(1)
	for id: int in mini(32, maxi(0, actor_count - 1)):
		mobile_units.append(id + 2)
		mobile_cells.append(0)
		links.append(-1)
	heads.resize(BUCKETS * BUCKETS)
	heads.fill(-1)
	room_temperature.resize(terrain.room_cells.size())
	room_temperature.fill(22.0)
	rebuild_static()


func rebuild_static() -> void:
	field.fill(0)
	for source: int in source_cells.size():
		if enabled[source] == 0:
			continue
		var origin: Vector2i = Terrain.cell(source_cells[source])
		for y: int in range(maxi(0, origin.y - RADIUS), mini(Terrain.SIZE, origin.y + RADIUS + 1)):
			for x: int in range(maxi(0, origin.x - RADIUS), mini(Terrain.SIZE, origin.x + RADIUS + 1)):
				var tile: int = y * Terrain.SIZE + x
				var value: int = contribution(origin, Vector2i(x, y), source_strengths[source])
				var address: int = tile * CHANNELS + source_channels[source]
				field[address] = maxi(field[address], value)
	revision += 1


func contribution(origin: Vector2i, receiver: Vector2i, strength: int) -> int:
	var squared: int = (origin - receiver).length_squared()
	if squared >= RADIUS * RADIUS:
		return 0
	var value: float = strength * (1.0 - float(squared) / float(RADIUS * RADIUS))
	# Exact tile traversal only for nearby, actually sampled source/receiver pairs.
	# Walls attenuate rather than hide perception; this coefficient is thermal.
	var delta: Vector2 = Vector2(receiver - origin)
	var length: int = maxi(absi(receiver.x - origin.x), absi(receiver.y - origin.y))
	var previous: int = -1
	for step: int in range(1, length):
		var point: Vector2i = Vector2i((Vector2(origin) + delta * float(step) / float(length)).round())
		var tile: int = Terrain.index(point)
		if tile != previous and terrain.blocked[tile] != 0:
			value *= 0.25
		previous = tile
	return roundi(value)


func update(now: int, pages: Array[RefCounted]) -> void:
	heads.fill(-1)
	for source: int in mobile_units.size():
		var id: int = mobile_units[source] - 1
		var page: RefCounted = pages[id / 256]
		var row: int = id % 256
		if page.health[row] <= 0:
			mobile_cells[source] = -1
			links[source] = -1
			continue
		var point := Vector2i(page.positions[row])
		mobile_cells[source] = Terrain.index(point)
		var bucket: int = (point.y / BUCKET) * BUCKETS + point.x / BUCKET
		links[source] = heads[bucket]
		heads[bucket] = source
	if now > 0 and now % 60000 == 0:
		for channel: int in 5:
			tides[channel] = rng.randi_range(95, 105)
	# A room is one receiver, not hundreds of duplicated cell response curves.
	var probe := PackedInt32Array()
	probe.resize(CHANNELS)
	for room: int in terrain.room_cells.size():
		var target: float = 0.0
		for tile: int in terrain.room_cells[room]:
			sample_raw(tile, probe, 0)
			target += 22.0 + probe[0] - probe[1]
		target /= maxi(1, terrain.room_cells[room].size())
		if now > 0:
			room_temperature[room] = lerpf(room_temperature[room], target, 1.0 - exp(-1.0 / 30.0))
	updates += 1


func remove_mobile(unit: int) -> void:
	var source: int = mobile_units.find(unit)
	if source < 0:
		return
	mobile_cells[source] = -1
	heads.fill(-1)
	for slot: int in mobile_cells.size():
		if mobile_cells[slot] < 0:
			links[slot] = -1
			continue
		var point: Vector2i = Terrain.cell(mobile_cells[slot])
		var bucket: int = (point.y / BUCKET) * BUCKETS + point.x / BUCKET
		links[slot] = heads[bucket]
		heads[bucket] = slot


func sample_raw(tile: int, output: PackedInt32Array, offset: int) -> void:
	for channel: int in CHANNELS:
		output[offset + channel] = field[tile * CHANNELS + channel]
	var receiver: Vector2i = Terrain.cell(tile)
	var bx: int = receiver.x / BUCKET
	var by: int = receiver.y / BUCKET
	for y: int in range(maxi(0, by - 1), mini(BUCKETS, by + 2)):
		for x: int in range(maxi(0, bx - 1), mini(BUCKETS, bx + 2)):
			var source: int = heads[y * BUCKETS + x]
			while source >= 0:
				var channel: int = source % CHANNELS
				var value: int = contribution(Terrain.cell(mobile_cells[source]), receiver, 90)
				output[offset + channel] = maxi(output[offset + channel], value)
				source = links[source]


func temperature_at(tile: int, values: PackedInt32Array, offset: int) -> float:
	var room: int = terrain.rooms[tile]
	return room_temperature[room] if room >= 0 else 22.0 + values[offset] - values[offset + 1]


func element(tile: int, values: PackedInt32Array, offset: int, channel: int) -> int:
	var base: int = 80 + posmod(tile * (channel * 2 + 3), 41)
	return roundi(float(base + values[offset + channel + 2]) * tides[channel] / 100.0)
