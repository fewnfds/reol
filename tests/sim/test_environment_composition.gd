extends RefCounted
## Primary owner: composed environment. Protects single room temperature,
## geometry, original custody/motion and restore; no separate room heat store.
const Fields = preload("res://tests/sim/test_world_environment_fields.gd")
const Buildings = preload("res://tests/sim/test_building_framework.gd")
const Rooms = preload("res://tests/sim/test_rooms_and_rest.gd")
var fields := Fields.new()
var buildings := Buildings.new()
var rooms := Rooms.new()


func run(runner: Object) -> void:
	_room_and_restore(runner)
	_custody_and_motion(runner)
	_light_and_receptors(runner)
	print("SCENARIO environment composition: shared rooms, apertures, custody, exact motion crossings, artificial light and same restored future")


func _world(runner: Object, bright: bool = false) -> RegionalSimulation:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json"))
	for row: Dictionary in rules.types.values():
		row.work_ms = 1
		row.demolish_ms = 1
	rules.operate_ms = 1
	var sources: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/environment_sources.json"))
	sources.profiles["test_heat"] = sources.profiles.intrinsic_hot.duplicate(true)
	sources.profiles.test_heat.thermal_grade = 1000
	sources.bindings.artifacts.plain_slate = "test_heat"
	sources.bindings.materials.herb = "test_heat"
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	for item: Dictionary in opening.objects:
		if item.id == "glow_shard":
			item.region = "home"
			item.container = "actor:player"
	var overrides: Dictionary = {"res://data/definitions/construction.json": rules,
		"res://data/definitions/environment_sources.json": sources, "res://data/scenarios/artifacts.json": opening}
	if bright:
		var artifacts: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/artifacts.json"))
		artifacts.types.glow_shard.lighting.peak_relative = 10000
		overrides["res://data/definitions/artifacts.json"] = artifacts
		for index: int in 4:
			opening.objects.append({"id": "lamp:" + str(index), "definition": "glow_shard", "region": "home", "container": "actor:player"})
	var world: RegionalSimulation = fields._world(runner, overrides)
	if world == null:
		return null
	world.regions.home.set_actor_cell("player", Vector2i(108, 104))
	world.regions.home.set_actor_cell("shi_tou", Vector2i(107, 104))
	rooms._bind_navigation(world)
	buildings.fixture._site(runner, world)
	world.invalidate_region("home")
	return world


func _room_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var door: String = ""
	var wall: String = ""
	for y: int in range(107, 110):
		for x: int in range(109, 114):
			if x in [110, 111, 112] and y == 108:
				continue
			var at := Vector2i(x, y)
			if at == Vector2i(109, 108):
				continue
			var id: String = buildings._build(runner, world, "wood_wall", at)
			if at == Vector2i(110, 107):
				wall = id
	door = buildings._build(runner, world, "wood_door", Vector2i(109, 108))
	if door.is_empty() or wall.is_empty():
		return
	runner.assert_true(world.construction.begin("player", door, "open").ok, "original door opens to admit the roof worker")
	buildings.fixture._finish(runner, world)
	for cell: Vector2i in [Vector2i(110, 108), Vector2i(111, 108), Vector2i(112, 108)]:
		buildings._build(runner, world, "wood_roof", cell)
	var domain: SimWorldEnvironmentFields = world.environment_fields
	runner.assert_eq(domain._layout.rooms.size(), 1, "a physically enclosed roofed pair becomes one thermal compartment")
	if domain._layout.rooms.is_empty():
		return
	var anchor: Vector2i = domain._layout.room_of[Vector2i(110, 108)]
	var open_tau: int = int(domain._layout.rooms[anchor].tau_ms)
	runner.assert_true(world.construction.begin("player", door, "close").ok, "the same original door closes")
	buildings.fixture._finish(runner, world)
	runner.assert_true(int(domain._layout.rooms[anchor].tau_ms) > open_tau, "an open aperture exchanges temperature faster than its closed wall")
	var source := Vector2i(110, 108)
	var created: Dictionary = world.object_lifecycle.execute(fields._lifecycle._spawn("room_heat", "room_heat", "plain_slate", [source.x, source.y]))
	runner.assert_true(bool(created.get("ok", false)), "one original hot item is put inside the compartment")
	if not bool(created.get("ok", false)):
		return
	fields._advance(runner, world, world.elapsed_ms + 30000, "room responds to its actual source")
	fields._near(runner, float(domain.actual_at(source, world.elapsed_ms).value_c), float(domain.actual_at(Vector2i(111, 108), world.elapsed_ms).value_c), "every cell reads the same single mixed room temperature")
	var hot := Vector2i(110, 106)
	var inside := Vector2i(110, 108)
	var thermal: int = domain._layout.transmission(hot, inside, 5)
	var elemental: int = domain._layout.transmission(hot, inside, 0)
	var blocked_grade: int = int(domain._field.read_base(hot).channels[5])
	runner.assert_true(thermal > 0 and thermal < elemental and elemental < 10000, "thermal and elemental channels obey separate material permeability")
	var saved: Dictionary = JSON.parse_string(buildings.fixture._canonical(world))
	var restored: RegionalSimulation = _world(runner)
	var accepted: bool = restored.restore(saved)
	runner.assert_true(accepted, "the original response codec restores mixed room anchors with the archived content")
	if not accepted:
		return
	var target: int = world.elapsed_ms + 17000
	fields._advance(runner, world, target, "whole room future")
	fields._advance(runner, restored, target - 7000, "first restored slice")
	fields._advance(runner, restored, target, "second restored slice")
	runner.assert_eq(buildings.fixture._canonical(restored), buildings.fixture._canonical(world), "room and all original domains have the identical restored future")
	var before: String = buildings.fixture._canonical(world)
	var bad: Dictionary = JSON.parse_string(before)
	for row: Dictionary in bad.local_heat.temperature.cells:
		if SimRouteTravel.cell(row.cell) == Vector2i(110, 108):
			row.response.initial_value += 1.0
			break
	runner.assert_true(not world.restore(bad) and buildings.fixture._canonical(world) == before, "a divergent per-cell room candidate cannot partly replace the live world")
	runner.assert_true(world.construction.begin("player", door, "open").ok, "the worker opens a real route back to the partition material")
	buildings.fixture._finish(runner, world)
	var partition: String = buildings._build(runner, world, "wood_wall", Vector2i(111, 108))
	runner.assert_eq(domain._layout.rooms.size(), 2, "an actual partition splits the existing room into independent thermal compartments")
	fields._advance(runner, world, world.elapsed_ms + 30000, "split rooms respond independently")
	var sum: float = 0.0
	for point: Vector2i in [Vector2i(110, 108), Vector2i(111, 108), Vector2i(112, 108)]:
		sum += float(domain.actual_at(point, world.elapsed_ms).value_c)
	runner.assert_true(world.construction.damage(partition, 1000000).destroyed, "the original partition is removed by structure damage")
	runner.assert_eq(domain._layout.rooms.size(), 1, "removing the partition merges the actual compartments")
	fields._near(runner, sum / 3.0, float(domain.actual_at(inside, world.elapsed_ms).value_c), "the merged room mixes the prior actual temperatures by cell area")
	var old: float = float(domain.actual_at(inside, world.elapsed_ms).value_c)
	runner.assert_true(world.construction.damage(wall, 1000000).destroyed, "original structure damage opens the compartment")
	runner.assert_true(domain._layout.rooms.is_empty(), "a breached wall no longer claims an indoor compartment: " + str(domain._layout.rooms))
	fields._near(runner, old, float(domain.actual_at(inside, world.elapsed_ms).value_c), "opening a room preserves its actual heat instead of resetting it to climate")
	fields._near(runner, 10000.0, float(domain._layout.transmission(hot, inside, 5)), "removing the real wall restores transmission")
	runner.assert_true(int(domain._field.read_base(hot).channels[5]) > blocked_grade, "topology invalidation rebuilds the actual cached field behind the removed wall")


func _custody_and_motion(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if not fields._ready(runner, world):
		return
	var start := Vector2i(120, 120)
	world.regions.home.set_actor_cell("player", start)
	var created: Dictionary = world.object_lifecycle.execute({"command": "held_heat", "op": "spawn", "id": "held_heat", "definition": "plain_slate", "to": {"region": "home", "container": "actor:player"}})
	runner.assert_true(bool(created.get("ok", false)), "a carried original artifact emits without a duplicate ground object")
	if not bool(created.get("ok", false)):
		return
	var saved: Dictionary = JSON.parse_string(buildings.fixture._canonical(world))
	var sliced: RegionalSimulation = _world(runner)
	runner.assert_true(sliced.restore(saved), "carried source state restores independently")
	for current: RegionalSimulation in [world, sliced]:
		var motion := SimLocalMotion.new(current._content.local_actions)
		var sim: VillageSimulation = current.regions.home
		motion.bind_body(sim.actors.player, sim.notify_body_space_changed.bind("player"), sim.notify_body_cell_crossed.bind("player"))
		current.set_manual_motion_executor(func(from: int, to: int) -> void:
			motion.advance(from, to, Vector2.RIGHT, func(_cell: Vector2i, _direction: Vector2i) -> bool: return true))
	fields._advance(runner, world, 2000, "whole manual movement interval")
	for now: int in [123, 537, 1103, 2000]:
		fields._advance(runner, sliced, now, "arbitrary movement slice")
	for at: Vector2i in [start, start + Vector2i.RIGHT, start + Vector2i.RIGHT * 4]:
		fields._near(runner, float(world.environment_fields.actual_at(at, 2000).value_c), float(sliced.environment_fields.actual_at(at, 2000).value_c), "integer crossing notices preserve identical moving-source heat")
	runner.assert_eq(buildings.fixture._canonical(world), buildings.fixture._canonical(sliced), "motion source anchors and the entire world are independent of host slicing")
	var source: Dictionary = world.environment_fields._sources.get_source("artifact:held_heat")
	runner.assert_true(source.cell == SimRouteTravel.cell(world.regions.home.actors.player.cell) and source.cell != start, "the source uses the same original carrier's final cell")


func _light_and_receptors(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, true)
	if not fields._ready(runner, world):
		return
	var box: String = buildings._build(runner, world, "wood_chest", Vector2i(110, 107))
	if box.is_empty():
		return
	var cell := Vector2i(110, 107)
	var sim: VillageSimulation = world.regions.home
	runner.assert_true(sim.inventory.transfer("pick_test_herb", "garden", "actor:player", "herb", 1), "the fixture picks an actual original stock item")
	var slot: Dictionary = world.construction.operation_slots(box, "storage")[0]
	sim.set_actor_cell("player", slot.cell)
	var created: Dictionary = world.facility_use.begin("player", box, slot.id, "deposit", "herb", 1)
	runner.assert_true(bool(created.get("ok", false)), "one original hot material enters real furniture through its storage action: " + str(created))
	if not bool(created.get("ok", false)):
		return
	buildings._finish_use(runner, world)
	var key: String = SimWorldEnvironmentSourceParticipant.stock_key("home", box + ":contents", "herb")
	var source: Dictionary = world.environment_fields._sources.get_source(key)
	runner.assert_eq(source.channels[5], 250, "closed furniture attenuates its contents' heat without consuming or cloning them")
	world.construction.damage(box, 1000000)
	source = world.environment_fields._sources.get_source(key)
	runner.assert_eq(source.channels[5], 1000, "breaking a container exposes the same original contents")
	runner.assert_true(world.artifacts.objects.glow_shard.container == "actor:player", "an original intrinsic lamp supplies local artificial illumination")
	var near: Vector2i = SimRouteTravel.cell(world.regions.home.actors.player.cell)
	world.target_ms += 1000
	var ui: Dictionary = SimLocalLight.at_cell(world, near)
	var light: Dictionary = SimLocalLight.at_simulation_cell(world, near)
	var habitat: Dictionary = world.plants.habitat(near)
	runner.assert_true(not bool(ui.supported) and bool(light.supported) and int(light.artificial_relative) > 0, "simulation sampling reads its committed instant while UI still refuses future debt")
	runner.assert_true(not habitat.is_empty() and int(habitat.light) == int(light.total_relative), "plant growth conditions include exactly the original natural and artificial light")
	runner.assert_eq(int(habitat.temperature), roundi(float(world.environment_fields.actual_at(near, world.elapsed_ms).value_c) * 10), "plants read the same actual temperature as bodily receptors")
	world.target_ms = world.elapsed_ms
	runner.assert_true(int(light.total_relative) > 40000, "natural and saturated artificial light are a supported combined input")
	runner.assert_true(world.plants.spawn("lit_plant", "annual_grass", "home", near), "a real plant records that combined light without dropping it")
	var restored: RegionalSimulation = _world(runner, true)
	runner.assert_true(restored.restore(JSON.parse_string(buildings.fixture._canonical(world))), "combined-light plant conditions survive the ordinary owner codec")
