extends RefCounted
## Flat worlds are a distinct generator, not a reinterpretation of old saves.

const Legacy = preload("res://tests/sim/helpers/legacy_world_map_oracle.gd")
const STEPS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


func run(runner: Object) -> void:
	_descriptors(runner)
	_reproducibility(runner)
	_old_world_and_flat_terrain(runner)
	_navigation(runner)
	_copy_and_nature(runner)
	print("SCENARIO flat map: independently versioned planar height, seeded terrain and nature, original map preserved")


func _descriptors(runner: Object) -> void:
	for seed: int in [1, 20261101, WorldMapData.FLAT_MAX_SEED]:
		var value: Dictionary = WorldMapData.flat_descriptor(seed)
		runner.assert_true(not value.is_empty() and WorldMapData.valid_descriptor(value), "supported flat seed has a valid exact descriptor: %d" % seed)
		var roundtrip: Variant = JSON.parse_string(JSON.stringify(value))
		runner.assert_true(WorldMapData.valid_descriptor(roundtrip), "flat descriptor survives JSON whole-number conversion: %d" % seed)
		var map: WorldMapData = WorldMapData.from_descriptor(roundtrip)
		runner.assert_true(map != null, "flat descriptor builds a map: %d" % seed)
		if map != null:
			runner.assert_eq(map.descriptor(), value, "map retains its exact accepted flat identity")
	for seed: int in [-1, 0, WorldMapData.FLAT_MAX_SEED + 1, 2147483647]:
		runner.assert_true(WorldMapData.flat_descriptor(seed).is_empty(), "flat helper refuses a seed outside supported noise bounds: %d" % seed)
	var bad: Dictionary = WorldMapData.flat_descriptor(1)
	bad.seed = WorldMapData.FLAT_MAX_SEED + 1
	_reject(runner, bad, "seed above signed-noise offset bound")
	bad = WorldMapData.flat_descriptor(1)
	bad.seed = 0
	_reject(runner, bad, "zero seed")
	bad = WorldMapData.flat_descriptor(1)
	bad.seed = 1.5
	_reject(runner, bad, "fractional seed")
	bad = WorldMapData.flat_descriptor(1)
	bad.seed = true
	_reject(runner, bad, "boolean seed")
	bad = WorldMapData.flat_descriptor(1)
	bad.generator_version = 2
	_reject(runner, bad, "unknown flat generator version")
	bad = WorldMapData.flat_descriptor(1)
	bad.size = 1024
	_reject(runner, bad, "unsupported flat map size")
	bad = WorldMapData.flat_descriptor(1)
	bad.generator = "reol_noise"
	_reject(runner, bad, "legacy generator paired with a non-legacy seed")
	bad = WorldMapData.flat_descriptor(1)
	bad.generator = "reol_unknown"
	_reject(runner, bad, "unknown generator")
	bad = WorldMapData.flat_descriptor(1)
	bad["other"] = 0
	_reject(runner, bad, "additional field")


func _reproducibility(runner: Object) -> void:
	var samples: Array[Vector2i] = []
	for y: int in range(0, 512, 31):
		for x: int in range(0, 512, 37):
			samples.append(Vector2i(x, y))
	for seed: int in [1, 42, 20261101, WorldMapData.FLAT_MAX_SEED]:
		var first: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(seed))
		var second: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(seed))
		if first == null or second == null:
			runner.assert_true(false, "supported seed constructs both independent maps: %d" % seed)
			continue
		var recorded: Dictionary = {}
		for cell: Vector2i in samples:
			recorded[cell] = [first.get_terrain(cell), first.get_elevation(cell), first.natural_cell(cell)]
		var different: int = 0
		# Reverse query order to exercise generation without relying on cache order.
		for index: int in range(samples.size() - 1, -1, -1):
			var cell: Vector2i = samples[index]
			var actual: Array = [second.get_terrain(cell), second.get_elevation(cell), second.natural_cell(cell)]
			if actual != recorded[cell]:
				different += 1
		runner.assert_eq(different, 0, "same seed reproduces terrain and natural cells independent of query order: %d" % seed)
	var one: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(1))
	var two: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(42))
	if one == null or two == null:
		runner.assert_true(false, "different-seed comparison maps exist")
		return
	var changed: int = 0
	for cell: Vector2i in samples:
		if one.get_terrain(cell) != two.get_terrain(cell):
			changed += 1
	runner.assert_true(changed > 0, "different seeds actually alter sampled terrain")


func _old_world_and_flat_terrain(runner: Object) -> void:
	var old: WorldMapData = WorldMapData.from_descriptor(WorldMapData.legacy_descriptor())
	var flat: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(20261101))
	if old == null or flat == null:
		runner.assert_true(false, "legacy and flat generators both construct")
		return
	var oracle: Legacy = Legacy.new()
	var old_mismatch: int = 0
	var terrain_mismatch: int = 0
	var flat_height_mismatch: int = 0
	var elevated: int = 0
	for y: int in range(0, 512, 13):
		for x: int in range(0, 512, 17):
			var cell := Vector2i(x, y)
			if old.get_terrain(cell) != oracle.get_terrain(cell) or old.get_elevation(cell) != oracle.get_elevation(cell):
				old_mismatch += 1
			if flat.get_terrain(cell) != oracle.get_terrain(cell):
				terrain_mismatch += 1
			if flat.get_elevation(cell) != 0:
				flat_height_mismatch += 1
			if oracle.get_elevation(cell) > 0:
				elevated += 1
	runner.assert_eq(old_mismatch, 0, "the old generator still matches the independent historical oracle")
	runner.assert_eq(terrain_mismatch, 0, "flat generation retains the old terrain noise at the same seed")
	runner.assert_eq(flat_height_mismatch, 0, "all sampled in-bounds flat cells have zero elevation")
	runner.assert_true(elevated > 0, "the historical generator still retains its nonzero heights")
	for cell: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(512, 0), Vector2i(0, 512), Vector2i(512, 512)]:
		runner.assert_eq(flat.get_terrain(cell), -1, "outside flat map has no terrain")
		runner.assert_eq(flat.get_elevation(cell), -1, "outside flat map has no elevation")


func _navigation(runner: Object) -> void:
	var map: WorldMapData = WorldMapData.from_descriptor(WorldMapData.flat_descriptor(20261101))
	if map == null:
		runner.assert_true(false, "flat map exists for navigation checks")
		return
	for y: int in [0, 127, 256, 511]:
		runner.assert_true(not map.terrain_can_step(Vector2i(0, y), Vector2i.LEFT), "steps cannot leave the western boundary")
		runner.assert_true(not map.terrain_can_step(Vector2i(511, y), Vector2i.RIGHT), "steps cannot leave the eastern boundary")
	for x: int in [0, 127, 256, 511]:
		runner.assert_true(not map.terrain_can_step(Vector2i(x, 0), Vector2i.UP), "steps cannot leave the northern boundary")
		runner.assert_true(not map.terrain_can_step(Vector2i(x, 511), Vector2i.DOWN), "steps cannot leave the southern boundary")
	var water_cases: int = 0
	var invalid_steps: int = 0
	for y: int in range(1, 511, 5):
		for x: int in range(1, 511, 5):
			var cell := Vector2i(x, y)
			for step: Vector2i in STEPS:
				var destination: Vector2i = cell + step
				var terrain: int = map.get_terrain(destination)
				if terrain == WorldMapData.TERRAIN_WATER:
					water_cases += 1
				if map.terrain_can_step(cell, step) and (not map.in_bounds(destination) or terrain != WorldMapData.TERRAIN_GRASS):
					invalid_steps += 1
	runner.assert_true(water_cases > 0, "navigation sample actually encounters water")
	runner.assert_eq(invalid_steps, 0, "no allowed sampled step lands outside the map, in water, or on rock")


func _copy_and_nature(runner: Object) -> void:
	var input: Dictionary = WorldMapData.flat_descriptor(42)
	var map: WorldMapData = WorldMapData.from_descriptor(input)
	if map == null:
		runner.assert_true(false, "flat map exists for identity and nature copy")
		return
	input.seed = 1
	runner.assert_eq(int(map.descriptor().seed), 42, "caller cannot change a map by mutating its input")
	var exported: Dictionary = map.descriptor()
	exported.seed = 3
	runner.assert_eq(int(map.descriptor().seed), 42, "caller cannot change a map by mutating its exported descriptor")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(NaturalEnvironment.DEFAULT_PATH))
	if not raw is Dictionary or not map.configure_nature(raw):
		runner.assert_true(false, "flat map accepts natural definitions")
		return
	var rules: Dictionary = raw
	var original_label: String = str(rules.surfaces.grassland.label)
	var cell := Vector2i(256, 256)
	var original_cell: Dictionary = map.natural_cell(cell)
	var copy: WorldMapData = map.independent_copy()
	runner.assert_true(copy != null and copy != map, "flat copy is a separate map")
	if copy == null:
		return
	runner.assert_eq(copy.descriptor(), map.descriptor(), "flat copy retains its generator and seed")
	runner.assert_true(copy._nature != map._nature, "flat copy has a separate natural query provider")
	runner.assert_eq(int(copy._nature.call("cache_size")), 0, "flat copy starts with an empty natural cache")
	runner.assert_eq(copy.natural_cell(cell), original_cell, "flat copy derives the same natural cell")
	rules.surfaces.grassland.label = original_label + " edited"
	runner.assert_true(map.configure_nature(rules), "original flat map can install another valid definition")
	runner.assert_eq(str(copy.natural_surface_definitions().grassland.label), original_label, "flat copy keeps its own original nature definitions")
	runner.assert_true(int(copy._nature.call("cache_size")) > 0, "changing original does not clear the copy's natural cache")


func _reject(runner: Object, value: Variant, reason: String) -> void:
	runner.assert_true(not WorldMapData.valid_descriptor(value), "flat descriptor rejects " + reason)
	runner.assert_true(WorldMapData.from_descriptor(value) == null, "flat factory rejects " + reason)
