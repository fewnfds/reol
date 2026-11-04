extends RefCounted
## The descriptor factory accepts only the historical, independently verified map.

const Legacy = preload("res://tests/sim/helpers/legacy_world_map_oracle.gd")
const POINTS: Array[Vector2i] = [
	Vector2i(0, 0), Vector2i(1, 1), Vector2i(63, 63), Vector2i(64, 63),
	Vector2i(63, 64), Vector2i(64, 64), Vector2i(127, 127), Vector2i(128, 128),
	Vector2i(255, 255), Vector2i(256, 255), Vector2i(255, 256), Vector2i(256, 256),
	Vector2i(257, 256), Vector2i(256, 257), Vector2i(384, 384), Vector2i(447, 447),
	Vector2i(448, 448), Vector2i(511, 511), Vector2i(0, 511), Vector2i(511, 0),
]
const STEPS: Array[Vector2i] = [
	Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
	Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1),
]


func run(runner: Object) -> void:
	var original: Dictionary = WorldMapData.legacy_descriptor()
	runner.assert_eq(original, {"generator": "reol_noise", "generator_version": 1, "seed": 20261101, "size": 512}, "legacy descriptor is the explicitly frozen original tuple")
	runner.assert_eq(WorldMapData.generation_descriptor(), original, "current default still identifies the legacy map")
	var decoded: Variant = JSON.parse_string(JSON.stringify(original))
	runner.assert_true(WorldMapData.valid_descriptor(decoded), "whole JSON numbers in the original descriptor are accepted")
	var map: WorldMapData = WorldMapData.from_descriptor(decoded)
	runner.assert_true(map != null, "the historical descriptor constructs a map")
	if map == null:
		return
	var second: WorldMapData = WorldMapData.from_descriptor(original)
	runner.assert_true(second != null and second != map, "separate factory calls produce separate map owners")
	runner.assert_eq(map.descriptor(), original, "the instance records the accepted generator identity")
	var exported: Dictionary = map.descriptor()
	exported.seed = 7
	runner.assert_eq(map.descriptor(), original, "the exported descriptor cannot alter the accepted map")
	decoded.seed = 8
	runner.assert_eq(map.descriptor(), original, "modifying caller input cannot alter the accepted map")
	_bad_descriptors(runner, original)
	_compare_legacy_oracle(runner, map)
	_nature_copy(runner, map)
	print("SCENARIO map descriptor: exact v1 validation, independent legacy oracle, deep-copied nature and caches")


func _bad_descriptors(runner: Object, original: Dictionary) -> void:
	for value: Variant in [null, [], "reol_noise", 1, {}]:
		_reject(runner, value, "not a complete descriptor")
	var bad: Dictionary = original.duplicate(true)
	bad.erase("seed")
	_reject(runner, bad, "missing seed")
	bad = original.duplicate(true)
	bad["extra"] = 1
	_reject(runner, bad, "extra field")
	bad = original.duplicate(true)
	bad.erase("seed")
	bad[42] = 20261101
	_reject(runner, bad, "a non-string field key")
	bad = original.duplicate(true)
	bad.generator = "unknown"
	_reject(runner, bad, "unknown generator")
	bad = original.duplicate(true)
	bad.generator = StringName("reol_noise")
	_reject(runner, bad, "generator outside JSON string types")
	for field: String in ["generator_version", "seed", "size"]:
		for invalid: Variant in [null, true, "1", -1, 0.5, INF]:
			bad = original.duplicate(true)
			bad[field] = invalid
			_reject(runner, bad, "invalid integer for " + field + ": " + str(invalid))
	bad = original.duplicate(true)
	bad.generator_version = 2
	_reject(runner, bad, "unknown generator version")
	bad = original.duplicate(true)
	bad.seed = int(original.seed) + 1
	_reject(runner, bad, "a different seed")
	bad = original.duplicate(true)
	bad.size = 1024
	_reject(runner, bad, "a different extent")


func _compare_legacy_oracle(runner: Object, map: WorldMapData) -> void:
	# The pre-existing oracle preserves the original implementation; it is not
	# calculated from this factory. The separate exhaustive test checks every cell.
	var oracle: Legacy = Legacy.new()
	for cell: Vector2i in POINTS:
		runner.assert_eq(map.get_terrain(cell), oracle.get_terrain(cell), "legacy terrain at " + str(cell))
		runner.assert_eq(map.get_elevation(cell), oracle.get_elevation(cell), "legacy elevation at " + str(cell))
		runner.assert_eq(map.terrain_is_walkable(cell), oracle.terrain_is_walkable(cell), "legacy walkability at " + str(cell))
		for step: Vector2i in STEPS:
			runner.assert_eq(map.terrain_can_step(cell, step), oracle.terrain_can_step(cell, step), "legacy step at %s + %s" % [cell, step])


func _nature_copy(runner: Object, map: WorldMapData) -> void:
	var loaded: Variant = JSON.parse_string(FileAccess.get_file_as_string(NaturalEnvironment.DEFAULT_PATH))
	if not loaded is Dictionary or not map.configure_nature(loaded):
		runner.assert_true(false, "natural environment definitions are available")
		return
	var rules: Dictionary = loaded
	var original_label: String = str(rules.surfaces.grassland.label)
	var cell := Vector2i(256, 256)
	var nature: Dictionary = map.natural_cell(cell)
	runner.assert_true(not nature.is_empty() and int(map._nature.call("cache_size")) > 0, "the original populates its own natural cache")
	var copied: WorldMapData = map.independent_copy()
	runner.assert_true(copied != null and copied != map, "copy comes from a new independent map owner")
	if copied == null:
		return
	runner.assert_eq(copied.descriptor(), map.descriptor(), "copy retains the original map's generator identity")
	runner.assert_true(copied._nature != map._nature, "natural query providers do not alias")
	runner.assert_eq(int(copied._nature.call("cache_size")), 0, "copy does not inherit populated cache entries")
	runner.assert_eq(copied.natural_cell(cell), nature, "copy derives the same initial natural cell")
	rules.surfaces.grassland.label = original_label + " copied input"
	runner.assert_eq(str(map.natural_surface_definitions().grassland.label), original_label, "source retains a private definition copy")
	runner.assert_true(map.configure_nature(rules), "source can adopt another valid nature definition")
	runner.assert_eq(str(map.natural_surface_definitions().grassland.label), original_label + " copied input", "source uses its changed definition")
	runner.assert_eq(str(copied.natural_surface_definitions().grassland.label), original_label, "copy retains its own prior nature definitions")
	runner.assert_true(int(copied._nature.call("cache_size")) > 0, "reconfiguring source cannot clear the copy's cache")


func _reject(runner: Object, value: Variant, label: String) -> void:
	runner.assert_true(not WorldMapData.valid_descriptor(value), "descriptor rejects " + label)
	runner.assert_true(WorldMapData.from_descriptor(value) == null, "factory rejects " + label)
