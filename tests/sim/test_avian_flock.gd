extends RefCounted

const Fixtures = preload("res://tests/sim/test_regional_simulation.gd")
const Placement = preload("res://scripts/sim/avian_habitat_placement.gd")


func run(runner: Object) -> void:
	_opening_and_food(runner)
	_understanding(runner)
	_resume_and_rejection(runner)
	_placement(runner)
	print("SCENARIO avian flock: ordinary birds share finite habitat food, reject incomprehensible errands and keep real bodies through sparse time and saves")


func _base() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/avian_life.json"))


func _patch() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/wildlife_flocks.json"))


func _merged() -> Dictionary:
	var scene: Dictionary = _base()
	var patch: Dictionary = _patch()
	for region: String in patch.regions:
		scene.regions[region].flock = patch.regions[region].flock.duplicate(true)
	return scene


func _world(runner: Object, flock: bool = true) -> RegionalSimulation:
	var world: RegionalSimulation = Fixtures.new()._make_world(runner)
	runner.assert_true(world.avian_life.spawn_opening(_merged() if flock else _base(), {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}), "opening stages old birds and optional flock atomically")
	return world


func _canonical(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _opening_and_food(runner: Object) -> void:
	var legacy: RegionalSimulation = _world(runner, false)
	runner.assert_eq(legacy.avian_life.birds.size(), 2, "original two-bird scenario does not silently spawn new wildlife")
	runner.assert_true(not legacy.avian_life.birds.moss_sparrow.has("understands_gestures"), "old bodies keep their original serialized shape")
	var world: RegionalSimulation = _world(runner)
	var domain: SimAvianLife = world.avian_life
	runner.assert_eq(domain.birds.size(), 4, "two ordinary birds join the two original spirit birds")
	for id: String in ["chestnut_sparrow", "bank_sparrow"]:
		runner.assert_true(not world.regions.home.actors.has(id) and not world.regions.river.actors.has(id), "ordinary bird is not duplicated as a human pawn")
		runner.assert_eq(world.embodiment.carrier_for_source("avian_body", id), SimAvianLife.carrier_id(id), "one registered body references each original bird")
		runner.assert_true(not bool(domain.birds[id].understands_gestures), "ordinary bird does not gain a spirit bird's understanding")
	var initial: int = 0
	for id: String in domain.sites:
		initial += domain.inventory.quantity(id, "seed")
	world.advance_to_ms(240000)
	var eaten: int = 0
	var new_birds_ate: Dictionary = {}
	for event: Dictionary in domain.events:
		if event.kind == "forage":
			eaten += 1
			new_birds_ate[event.bird] = true
	var remaining: int = 0
	for id: String in domain.sites:
		remaining += domain.inventory.quantity(id, "seed")
	runner.assert_true(new_birds_ate.has("chestnut_sparrow") and new_birds_ate.has("bank_sparrow"), "ordinary birds actually fly to and eat from finite food patches")
	runner.assert_eq(initial - remaining, eaten, "shared patches lose exactly the food eaten before the first growth boundary")
	runner.assert_eq(domain.inventory.quantity("bird:chestnut_sparrow", "seed"), 0, "no second virtual food bag is created during eating")


func _understanding(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var domain: SimAvianLife = world.avian_life
	var site: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(domain.sites["home:seeds"].cell))
	SimRouteTravel.put(world.regions.home.actors.player, site)
	domain.birds.chestnut_sparrow.position = [site.x, site.y]
	domain.birds.chestnut_sparrow.altitude = 0
	world.regions.home.inventory.containers["actor:player"].grain = 1
	runner.assert_true(str(domain.describe("player", "chestnut_sparrow").line).contains("普通山雀"), "observer sees ordinary bird description rather than a fabricated spirit identity")
	runner.assert_true(domain.offer_grain("player", "chestnut_sparrow").ok, "ordinary animal can receive physically scattered food without understanding a command")
	var before: String = _canonical(world)
	var reply: Dictionary = domain.ask_herb("player", "chestnut_sparrow")
	runner.assert_true(not bool(reply.ok) and reply.code == "uncomprehended", "feeding cannot teach an ordinary bird an abstract herb-fetching request")
	runner.assert_eq(_canonical(world), before, "incomprehensible request neither creates an errand nor consumes more food")
	domain.birds.chestnut_sparrow.autonomous = false
	runner.assert_true(domain.command_activity("chestnut_sparrow", "pickup").ok, "direct control of one's own beak does not require understanding another person's request")
	var resumed: RegionalSimulation = _world(runner, false)
	runner.assert_true(resumed.restore(JSON.parse_string(JSON.stringify(world.to_dict()))), "direct bodily action remains a valid saved process for an ordinary bird")


func _resume_and_rejection(runner: Object) -> void:
	var coarse: RegionalSimulation = _world(runner)
	var fine: RegionalSimulation = _world(runner)
	coarse.advance_to_ms(2447)
	for at: int in range(1, 2447, 73):
		fine.advance_to_ms(at)
	fine.advance_to_ms(2447)
	runner.assert_eq(_canonical(fine), _canonical(coarse), "ordinary flock shares deterministic fractional flight and common time")
	var resumed: RegionalSimulation = _world(runner, false)
	runner.assert_true(resumed.restore(JSON.parse_string(JSON.stringify(coarse.to_dict()))), "joint candidate restores new birds even when opening scenario contains only old birds")
	coarse.advance_to_ms(600123)
	resumed.advance_to_ms(600123)
	runner.assert_eq(_canonical(resumed), _canonical(coarse), "loaded flock continues to the same future without respawning or refilling food")
	var bad: Dictionary = JSON.parse_string(JSON.stringify(coarse.to_dict()))
	bad.avian_life.birds.chestnut_sparrow.understands_gestures = 0
	var before: String = _canonical(coarse)
	runner.assert_true(not coarse.restore(bad), "numeric false cannot masquerade as a saved understanding flag")
	runner.assert_eq(_canonical(coarse), before, "bad understanding flag cannot partly replace living flock")
	for kind: String in ["duplicate", "bad_flock", "bad_flag"]:
		var empty: RegionalSimulation = Fixtures.new()._make_world(runner)
		var opening: Dictionary = _merged()
		if kind == "duplicate":
			opening.regions.home.flock[0].id = "moss_sparrow"
		elif kind == "bad_flock":
			opening.regions.home.flock = {"invented": true}
		else:
			opening.regions.home.flock[0].understands_gestures = "false"
		var unchanged: String = _canonical(empty)
		runner.assert_true(not empty.avian_life.spawn_opening(opening, {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}), "malformed flock is rejected before its references are committed")
		runner.assert_eq(_canonical(empty), unchanged, "rejected opening does not create partial birds, subjects or food")


func _placement(runner: Object) -> void:
	var map_data := WorldMapData.new()
	var centers: Dictionary = {"home": Vector2i(256, 256), "river": Vector2i(280, 256)}
	var base: Dictionary = _base()
	var patch: Dictionary = _patch()
	var original: String = JSON.stringify(base, "", true, true)
	runner.assert_eq(Placement.assemble(base, centers, map_data), base, "empty wildlife patch preserves legacy opening exactly")
	var first: Dictionary = Placement.assemble(base, centers, map_data, patch)
	runner.assert_true(not first.is_empty(), "real terrain provides safe nearby food habitat")
	if first.is_empty():
		return
	runner.assert_eq(first, Placement.assemble(base, centers, map_data.independent_copy(), patch), "seed/roost habitat selection is independent of cache and read order")
	runner.assert_eq(JSON.stringify(base, "", true, true), original, "assembly does not mutate original historical scenario")
	for region: String in patch.regions:
		runner.assert_eq(first.regions[region].flock, patch.regions[region].flock, "only explicit new-world patch adds ordinary birds")
		var selected: Dictionary = {}
		for row: Dictionary in first.regions[region].sites.values():
			if row.type != "seeds":
				continue
			var cell: Vector2i = centers[region] + SimRouteTravel.cell(row.offset)
			runner.assert_true(map_data.terrain_is_walkable(cell), "each food patch has safe ground for physical landing")
			runner.assert_true(not selected.has(cell), "two food stocks do not occupy the same new habitat cell")
			selected[cell] = true
			var nature: Dictionary = map_data.natural_cell(cell)
			runner.assert_true(patch.placement.seed_surfaces.has(map_data.natural_surface(cell)) or patch.placement.seed_flora.has(nature.get("flora", {}).get("id", "")), "food site belongs to plausible grass or reed habitat")
			var nest: Vector2i = centers[region] + SimRouteTravel.cell(first.regions[region].sites.roost.offset)
			runner.assert_true(cell.distance_to(nest) <= float(patch.placement.near_roost_cells), "food stays within the new bird's initial observation range")
	var furniture_cell: Vector2i = centers.home + SimRouteTravel.cell(first.regions.home.sites.seeds.offset)
	var clear: Callable = func(cell: Vector2i) -> bool: return cell != furniture_cell
	var adjusted: Dictionary = Placement.assemble(base, centers, map_data, patch, clear)
	runner.assert_true(not adjusted.is_empty(), "nearby alternative habitat exists when a desk occupies the first candidate")
	if not adjusted.is_empty():
		for row: Dictionary in adjusted.regions.home.sites.values():
			if row.type == "seeds":
				runner.assert_true(centers.home + SimRouteTravel.cell(row.offset) != furniture_cell, "food habitat is never placed on furniture or a wall")
	runner.assert_true(Placement.assemble(base, centers, map_data, patch, func(_cell: Vector2i) -> bool: return false).is_empty(), "wholly blocked habitat fails rather than placing inaccessible food")
	patch.placement.search_radius = -1
	runner.assert_true(Placement.assemble(base, centers, map_data, patch).is_empty(), "malformed search budget returns explicit failed assembly")
