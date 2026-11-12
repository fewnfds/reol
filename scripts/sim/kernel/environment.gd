extends RefCounted
## Static influence is baked once. Moving sources are queried only by receivers.
## Empty ground has no thermal history; units and rooms carry their own inertia.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const CHANNELS: int = 7 # heat, cold, metal, wood, water, fire, earth
const RADIUS: int = 8
const BUCKET: int = 16
const BUCKETS: int = Terrain.SIZE / BUCKET
const STATE_FIELDS: Array = ["source_cells", "source_channels", "source_strengths", "enabled", "mobile_units", "room_temperature", "tides", "revision", "updates", "free_sources", "clock_ms", "weather", "weather_override", "ambient_temperature", "light", "rng_seed", "rng_state"]
const DAY_MS: int = 1200000
const SEASONS: Array[String] = ["春", "夏", "秋", "冬"]
const WEATHER: Array[String] = ["晴", "雨", "寒风", "热浪"]
var terrain: RefCounted
var field := PackedInt32Array()
var source_cells := PackedInt32Array()
var source_channels := PackedInt32Array()
var source_strengths := PackedInt32Array()
var enabled := PackedByteArray()
var mobile_cells := PackedInt32Array()
var mobile_units := PackedInt64Array()
var heads := PackedInt32Array()
var links := PackedInt32Array()
var room_temperature := PackedFloat32Array()
var tides := PackedInt32Array([100, 100, 100, 100, 100])
var rng := RandomNumberGenerator.new()
var revision: int = 0
var updates: int = 0
var samples: int = 0
var free_sources := PackedInt32Array()
var clock_ms: int = 0
var weather: int = 0
var weather_override: int = -1
var ambient_temperature: float = 22.0
var light: int = 1000
var rng_seed: int:
	get: return rng.seed
	set(value): rng.seed = value
var rng_state: int:
	get: return rng.state
	set(value): rng.state = value


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


func update(now: int, pages: Array[RefCounted], actor_slots: Dictionary = {}) -> void:
	clock_ms = now
	if now > 0 and now % 300000 == 0 and weather_override < 0:
		weather = rng.randi_range(0, 3)
	if weather_override >= 0:
		weather = weather_override
	var season: int = (now / DAY_MS / 4) % 4
	var phase: float = fposmod(float(now) / DAY_MS + 0.5, 1.0)
	light = roundi(maxf(0, sin((phase - 0.25) * TAU)) * (650 if weather == 1 else 1000))
	ambient_temperature = 18.0 + [0.0, 9.0, -2.0, -15.0][season] + light * 0.004 + [0.0, -3.0, -10.0, 12.0][weather]
	index_mobile(pages, actor_slots)
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
			target += ambient_at(tile) + probe[0] - probe[1]
		target /= maxi(1, terrain.room_cells[room].size())
		if now > 0:
			room_temperature[room] = lerpf(room_temperature[room], target, 1.0 - exp(-1.0 / 30.0))
	updates += 1


func index_mobile(pages: Array[RefCounted], actor_slots: Dictionary) -> void:
	heads.fill(-1)
	for source: int in mobile_units.size():
		var id: int = int(actor_slots.get(mobile_units[source], mobile_units[source] - 1))
		if id < 0 or id / 256 >= pages.size():
			mobile_cells[source] = -1
			links[source] = -1
			continue
		var page: RefCounted = pages[id / 256]
		var row: int = id % 256
		if row >= page.ids.size() or page.ids[row] != mobile_units[source] or page.health[row] <= 0:
			mobile_cells[source] = -1
			links[source] = -1
			continue
		var point := Vector2i(page.positions[row])
		mobile_cells[source] = Terrain.index(point)
		var bucket: int = (point.y / BUCKET) * BUCKETS + point.x / BUCKET
		links[source] = heads[bucket]
		heads[bucket] = source


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
	return room_temperature[room] if room >= 0 else ambient_at(tile) + values[offset] - values[offset + 1]


func ambient_at(tile: int) -> float:
	return ambient_temperature + [0.0, -19.0, 14.0][Terrain.region(tile)]


func calendar() -> Dictionary:
	return {"day": clock_ms / DAY_MS + 1, "season": SEASONS[(clock_ms / DAY_MS / 4) % 4],
		"day_phase": fposmod(float(clock_ms) / DAY_MS + 0.5, 1.0), "light": light,
		"weather": WEATHER[weather], "ambient": ambient_temperature}


func add_source(tile: int, channel: int, strength: int) -> int:
	var source: int
	if free_sources.is_empty():
		source = source_cells.size()
		source_cells.append(tile)
		source_channels.append(channel)
		source_strengths.append(0)
		enabled.append(0)
	else:
		source = free_sources[-1]
		free_sources.resize(free_sources.size() - 1)
		source_cells[source] = tile
		source_channels[source] = channel
	set_source(source, strength)
	return source


func set_source(source: int, strength: int) -> void:
	if source_strengths[source] == strength and enabled[source] == int(strength > 0):
		return
	source_strengths[source] = strength
	enabled[source] = int(strength > 0)
	refresh_region(Terrain.cell(source_cells[source]), source_channels[source])


func release_source(source: int) -> void:
	set_source(source, 0)
	if not free_sources.has(source):
		free_sources.append(source)


func refresh_region(origin: Vector2i, only_channel: int = -1) -> void:
	# max-fields cannot subtract a removed source. Recompose the affected
	# footprint including every surviving overlapping source, not the whole map.
	var low: Vector2i = (origin - Vector2i.ONE * RADIUS).max(Vector2i.ZERO)
	var high: Vector2i = (origin + Vector2i.ONE * RADIUS).min(Vector2i.ONE * (Terrain.SIZE - 1))
	for y: int in range(low.y, high.y + 1):
		for x: int in range(low.x, high.x + 1):
			for channel: int in range(0 if only_channel < 0 else only_channel, CHANNELS if only_channel < 0 else only_channel + 1):
				field[(y * Terrain.SIZE + x) * CHANNELS + channel] = 0
	for source: int in source_cells.size():
		if enabled[source] == 0 or (only_channel >= 0 and source_channels[source] != only_channel):
			continue
		var center: Vector2i = Terrain.cell(source_cells[source])
		if absi(center.x - origin.x) > RADIUS * 2 or absi(center.y - origin.y) > RADIUS * 2:
			continue
		for y: int in range(maxi(low.y, center.y - RADIUS), mini(high.y, center.y + RADIUS) + 1):
			for x: int in range(maxi(low.x, center.x - RADIUS), mini(high.x, center.x + RADIUS) + 1):
				var address: int = (y * Terrain.SIZE + x) * CHANNELS + source_channels[source]
				field[address] = maxi(field[address], contribution(center, Vector2i(x, y), source_strengths[source]))
	revision += 1


func element(tile: int, values: PackedInt32Array, offset: int, channel: int) -> int:
	var base: int = 80 + posmod(tile * (channel * 2 + 3), 41)
	return roundi(float(base + values[offset + channel + 2]) * tides[channel] / 100.0)
