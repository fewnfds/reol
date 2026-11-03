extends RefCounted
## Natural substrate is stable across views/candidates and does not mint any
## withdrawable water, plants, creatures or spirit energy.

const Nature = preload("res://scripts/sim/natural_environment.gd")

class FlatMap extends RefCounted:
	var terrain: int = 1
	var elevation: int = 0
	var water: Dictionary = {}


	func in_bounds(cell: Vector2i) -> bool:
		return cell.x >= 0 and cell.y >= 0 and cell.x < 512 and cell.y < 512


	func get_terrain(cell: Vector2i) -> int:
		if not in_bounds(cell):
			return -1
		return 0 if water.has(cell) else terrain


	func get_elevation(_cell: Vector2i) -> int:
		return elevation


func run(runner: Object) -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Nature.DEFAULT_PATH))
	runner.assert_true(Nature.valid_definitions(rules), "finite natural-substrate definitions validate")
	_boundaries(runner)
	_correlated_substrate(runner, rules)
	_determinism_and_cache(runner, rules)
	_five_elements(runner, rules)
	_bad_definitions(runner, rules)
	print("SCENARIO natural substrate: stable surface/vegetation/habitat, bounded cache, actual map shoreline, finite soil suitability and five-phase affinities without generated resources")


func _boundaries(runner: Object) -> void:
	var map := WorldMapData.new()
	for cell: Vector2i in [Vector2i(-1, 0), Vector2i(0, -1), Vector2i(512, 0), Vector2i(0, 512)]:
		runner.assert_true(map.natural_cell(cell).is_empty(), "outside map has no invented natural cell: " + str(cell))
		runner.assert_eq(map.natural_surface(cell), "", "outside map has no painted ground: " + str(cell))
		runner.assert_eq(map.natural_affinity(cell, "wood"), 0, "outside map has no elemental substrate: " + str(cell))
		runner.assert_eq(map.natural_growth_factor(cell), 0, "outside map has no plant growing potential: " + str(cell))
	runner.assert_eq(map.natural_affinity(Vector2i(256, 256), "heaven"), 0, "unknown phase does not acquire a fallback supernatural bonus")
	var definitions: Dictionary = map.natural_surface_definitions()
	definitions.water.label = "changed caller copy"
	runner.assert_eq(map.natural_surface_definitions().water.label, "山泽水面", "surface definitions are returned as independent values")


func _correlated_substrate(runner: Object, rules: Dictionary) -> void:
	var cell := Vector2i(100, 100)
	var dry := FlatMap.new()
	var shore := FlatMap.new()
	shore.water[cell + Vector2i.RIGHT] = true
	var dry_cell: Dictionary = Nature.new(91, rules).cell_at(dry, cell)
	var wet_cell: Dictionary = Nature.new(91, rules).cell_at(shore, cell)
	runner.assert_eq(wet_cell.surface_id, "shore", "actual neighbouring map water creates riparian substrate")
	runner.assert_true(int(wet_cell.moisture_potential) >= int(dry_cell.moisture_potential), "nearby real water cannot reduce moisture potential at the same coordinate")
	runner.assert_true(int(wet_cell.elements.water) > int(dry_cell.elements.water), "water-adjacent substrate has a real difference in water affinity")
	var shared_rules := Nature.new(91, rules)
	shared_rules.cell_at(dry, cell)
	runner.assert_eq(shared_rules.cell_at(shore, cell), wet_cell, "different spatial authorities cannot share stale same-coordinate cache entries")
	runner.assert_eq(shared_rules.cell_at(dry, cell), dry_cell, "switching back recomputes the original substrate instead of retaining candidate data")
	var water := FlatMap.new()
	water.terrain = 0
	var water_cell: Dictionary = Nature.new(91, rules).cell_at(water, cell)
	runner.assert_eq(water_cell.surface_id, "water", "map water remains water instead of becoming walkable soil")
	runner.assert_eq(water_cell.moisture_potential, 100, "water surface has saturated substrate potential")
	runner.assert_eq(water_cell.growth_factor, 0, "terrestrial herb suitability does not turn water into free plant growth")
	runner.assert_eq(water_cell.dominant_element, "water", "water has water affinity without claiming an actual qi reserve")
	var rock := FlatMap.new()
	rock.terrain = 2
	var rock_cell: Dictionary = Nature.new(91, rules).cell_at(rock, cell)
	runner.assert_eq(rock_cell.fertility, 0, "bare rock is not ordinary fertile soil")
	runner.assert_eq(rock_cell.growth_factor, 0, "ordinary herbs cannot grow on bare rock through a generic multiplier")
	runner.assert_true(rock_cell.surface_id in ["stone", "ore_rock"], "rock substrate keeps its physical family")
	var mountain := FlatMap.new()
	mountain.elevation = 3
	var mountain_cell: Dictionary = Nature.new(91, rules).cell_at(mountain, cell)
	runner.assert_true(int(mountain_cell.exposure) >= int(dry_cell.exposure), "higher same-coordinate open ground is more exposed")
	runner.assert_true(int(mountain_cell.moisture_potential) <= int(dry_cell.moisture_potential), "higher substrate does not invent extra groundwater")


func _determinism_and_cache(runner: Object, rules: Dictionary) -> void:
	var map := WorldMapData.new()
	var candidate: WorldMapData = map.independent_copy()
	var surfaces: Dictionary = {}
	var flora: Dictionary = {}
	var mismatch: int = 0
	var invalid: int = 0
	var seen_habitats: Dictionary = {}
	for y: int in range(0, 512, 9):
		for x: int in range(0, 512, 11):
			var cell := Vector2i(x, y)
			var actual: Dictionary = map.natural_cell(cell)
			if actual != candidate.natural_cell(cell):
				mismatch += 1
			surfaces[actual.surface_id] = true
			for key: String in ["moisture_potential", "fertility", "mineralization", "exposure", "growth_factor"]:
				if int(actual[key]) < 0 or int(actual[key]) > 100:
					invalid += 1
			for element: String in Nature.ELEMENTS:
				if int(actual.elements[element]) < 0 or int(actual.elements[element]) > 100:
					invalid += 1
			if not actual.flora.is_empty():
				flora[actual.flora.id] = true
				if not rules.flora.has(actual.flora.id) or actual.flora.element not in Nature.ELEMENTS or not str(actual.flora.placement_id).begins_with("cover:"):
					invalid += 1
			for habitat: String in actual.habitat:
				seen_habitats[habitat] = true
				if not rules.fauna.has(habitat):
					invalid += 1
	runner.assert_eq(mismatch, 0, "same map and independent candidate derive identical nature at 2679 representative cells")
	runner.assert_eq(invalid, 0, "all sampled soil/affinity ranges and plant/animal references remain valid")
	runner.assert_true(surfaces.size() >= 7, "the finite world really contains diverse derived landforms instead of unused definitions: " + str(surfaces.keys()))
	runner.assert_true(flora.size() >= 10, "deterministic vegetation actually uses multiple species: " + str(flora.keys()))
	runner.assert_true(seen_habitats.has("fish") and seen_habitats.has("mountain_beast") and seen_habitats.has("sparrow"), "actual substrate supports water, mountain and small-animal habitat distinctions")
	var saved: Dictionary = map.natural_cell(Vector2i(256, 256))
	var altered: Dictionary = map.natural_cell(Vector2i(256, 256))
	altered.elements.wood = -100
	altered.habitat.clear()
	runner.assert_eq(map.natural_cell(Vector2i(256, 256)), saved, "callers cannot mutate authoritative derived substrate through returned nested values")
	var tiny: Dictionary = rules.duplicate(true)
	tiny.cache_cells = 8
	var nature := Nature.new(WorldMapData.WORLD_SEED, tiny)
	var before: Dictionary = nature.cell_at(map, Vector2i(32, 32))
	for x: int in range(100):
		nature.cell_at(map, Vector2i(x, 31))
	runner.assert_eq(nature.cache_size(), 8, "space-cache has a strict configured bound instead of growing with explored world")
	runner.assert_eq(nature.cell_at(map, Vector2i(32, 32)), before, "cache eviction and re-entry do not reroll vegetation or attributes")
	runner.assert_eq(map.natural_surface(Vector2i(32, 32)), before.surface_id, "cheap rendering surface query agrees with full substrate projection")
	runner.assert_eq(map.natural_growth_factor(Vector2i(32, 32)), before.growth_factor, "growth suitability API agrees with the same soil")
	for element: String in Nature.ELEMENTS:
		runner.assert_eq(map.natural_affinity(Vector2i(32, 32), element), before.elements[element], "five-phase API reads the same substrate: " + element)


func _five_elements(runner: Object, rules: Dictionary) -> void:
	var nature := Nature.new(4, rules)
	for element: String in Nature.ELEMENTS:
		runner.assert_eq(nature.relation(element, element), "same", "same-phase relation: " + element)
		runner.assert_eq(nature.relation(element, rules.elements.engenders[element]), "engenders", "five-phase production direction: " + element)
		runner.assert_eq(nature.relation(element, rules.elements.controls[element]), "controls", "five-phase restraint direction: " + element)
		runner.assert_eq(nature.relation(rules.elements.engenders[element], element), "engendered_by", "production has a directional reverse: " + element)
		runner.assert_eq(nature.relation(rules.elements.controls[element], element), "controlled_by", "restraint has a directional reverse: " + element)
	runner.assert_eq(nature.relation("heaven", "wood"), "unknown", "unsupported metaphysics does not silently map to a phase")
	runner.assert_eq(nature.relation("wood", "heaven"), "unknown", "unsupported target has no invented elemental relationship")


func _bad_definitions(runner: Object, rules: Dictionary) -> void:
	var bad: Dictionary = rules.duplicate(true)
	bad.version = true
	runner.assert_true(not Nature.valid_definitions(bad), "boolean cannot masquerade as a natural-substrate schema")
	bad = rules.duplicate(true)
	bad.cache_cells = 0
	runner.assert_true(not Nature.valid_definitions(bad), "zero-size cache cannot enter a modulo-zero eviction path")
	bad = rules.duplicate(true)
	bad.noise.moisture.frequency = INF
	runner.assert_true(not Nature.valid_definitions(bad), "non-finite field frequency is rejected")
	bad = rules.duplicate(true)
	bad.surfaces.meadow.flora.missing_species = 1
	runner.assert_true(not Nature.valid_definitions(bad), "vegetation distribution must refer to an actual species")
	bad = rules.duplicate(true)
	bad.surfaces.shore.habitat.append("dragon")
	runner.assert_true(not Nature.valid_definitions(bad), "undefined fauna is not advertised as a habitat species")
	bad = rules.duplicate(true)
	bad.surfaces.grassland.density = 101
	runner.assert_true(not Nature.valid_definitions(bad), "cover density is a bounded percentage")
	bad = rules.duplicate(true)
	bad.elements.controls.wood = "wood"
	runner.assert_true(not Nature.valid_definitions(bad), "an element cannot control itself in the configured cycle")
	bad = rules.duplicate(true)
	bad.elements.engenders.water = "fire"
	runner.assert_true(not Nature.valid_definitions(bad), "production relations must form one five-phase cycle rather than a disconnected loop")
	bad = rules.duplicate(true)
	bad.land.growth_moisture_optimal = 0
	runner.assert_true(not Nature.valid_definitions(bad), "soil suitability cannot divide by zero")
	bad = rules.duplicate(true)
	bad.land.water_probe_distances = [3, 1]
	runner.assert_true(not Nature.valid_definitions(bad), "ordered water probes cannot silently prefer a distant shore")
	var invalid := Nature.new(8, bad)
	runner.assert_true(not invalid.is_valid(), "bad custom rules do not replace themselves with apparently valid defaults")
	runner.assert_true(invalid.cell_at(WorldMapData.new(), Vector2i(256, 256)).is_empty(), "invalid nature has no invented output")
