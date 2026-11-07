extends RefCounted

const Devices = preload("res://tests/sim/test_thermal_devices.gd")
const FlatMap = preload("res://tests/sim/test_structure_query.gd").FlatMap
var _devices := Devices.new()


func run(runner: Object) -> void:
	_lifecycle(runner)
	_tail(runner)
	_multiple_and_legacy(runner)
	_structures(runner)
	_definition_contract(runner)
	_restore_and_failures(runner)
	print("SCENARIO local light: actual finite output, original costs/custody, current/far sources, additive saturation, absent legacy capability, in-flight restore, retained backlog and read-only bounded queries")


func _world(runner: Object, capacity: int = 180000000, lighting: bool = true, count: int = 1, kitchen: Vector2i = Vector2i(-1, -1)) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "light fixture loads definitions")
		return null
	# Explicit fixture law before creating owners or issuing any real object.
	content.artifacts.types.fire_stone.thermal.capacity_q = capacity
	content.artifacts.types.fire_stone.thermal.opening_q = capacity
	if not lighting:
		content.artifacts.types.fire_stone.erase("lighting")
	if count > 1:
		content.artifacts.types.fire_stone.lighting.peak_relative = 10000
	var instances: Dictionary = {}
	for region: String in ["home", "river"]:
		instances[region] = _devices._artifacts._fixtures._make_village(content, region, false)
	if kitchen.x >= 0:
		instances.home.places.kitchen.cell = [kitchen.x, kitchen.y]
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	var world := RegionalSimulation.new()
	if not world.initialize(settings, instances, content):
		runner.assert_true(false, "light fixture assembles original regional owners")
		return null
	world.bind_map_data(FlatMap.new())
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	# Isolate finite heat-driven light; intrinsic sources have separate scenarios.
	opening.objects = opening.objects.filter(func(row: Dictionary) -> bool: return not content.artifacts.types[row.definition].get("capabilities", []).has("intrinsic_light"))
	for index: int in range(1, count):
		opening.objects.append({"id": "extra_fire_%d" % index, "definition": "fire_stone", "region": "home", "container": "kitchen"})
	if not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "light fixture issues declared original artifacts once")
		return null
	world.set_active_region("")
	world.regions.home.set_actor_cell("player", world.artifacts.object_cell("fire_stone"))
	world.invalidate_region("home")
	return world


func _light(world: RegionalSimulation, cell: Vector2i) -> int:
	var result: Dictionary = SimLocalLight.local_patch(world, [cell])
	return int(result.values[cell]) if bool(result.supported) else -1


func _lifecycle(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var at: Vector2i = world.artifacts.object_cell("fire_stone")
	runner.assert_eq(_light(world, at), 0, "a declared disabled fire stone emits no free light")
	if not _devices._action(runner, world, "player", "study", "fire_stone") or not _devices._start(runner, world, "player", "enable", "fire_stone"):
		return
	var due: int = int(world.artifacts.active.player.due_ms)
	world.advance_to_ms(due - 1)
	runner.assert_eq(_light(world, at), 0, "an unfinished paid activation gives no early light")
	world.advance_to_ms(due)
	runner.assert_eq(_light(world, at), 4000, "successful activation exposes the real original output slope")
	runner.assert_eq(int(world.artifacts.objects.fire_stone.stored_q), 180000000, "reading light does not prepay heat or a second light balance")
	var before: String = _devices._json(world.to_dict())
	for _read: int in 10:
		SimLocalLight.at_cell(world, at)
	runner.assert_eq(_devices._json(world.to_dict()), before, "light queries mutate no clock, stock, observations, receipts or world facts")
	runner.assert_eq(_light(world, at + Vector2i.RIGHT * 2), 3000, "actual source uses the common integer spatial falloff")
	runner.assert_true(bool(SimLocalLight.at_cell(world, at).supported), "local and original natural light share the accepted clock")
	var before_disable: int = int(world.artifacts.objects.fire_stone.stored_q)
	var started: int = world.elapsed_ms
	if not _devices._action(runner, world, "player", "disable", "fire_stone"):
		return
	runner.assert_eq(_light(world, at), 0, "the real switch removes light immediately")
	runner.assert_true(world.environment_fields.current_tenths(at) > 0, "closing light does not delete stored heat from the original field")
	var rate: int = int(world.artifacts.definitions.types.fire_stone.thermal.rate_q_per_ms)
	runner.assert_eq(int(world.artifacts.objects.fire_stone.stored_q), before_disable - rate * (world.elapsed_ms - started), "the original reservoir alone pays for elapsed output while disabling")


func _tail(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 1001)
	if world == null or not _devices._action(runner, world, "player", "study", "fire_stone") or not _devices._action(runner, world, "player", "enable", "fire_stone"):
		return
	var at: Vector2i = world.artifacts.object_cell("fire_stone")
	var start: int = world.elapsed_ms
	runner.assert_eq(_light(world, at), 4000, "the first millisecond has nominal flux")
	world.advance_to_ms(start + 1)
	runner.assert_eq(int(world.artifacts.objects.fire_stone.stored_q), 1, "the original source has exactly one Q left")
	runner.assert_eq(_light(world, at), 4, "the sub-rate last millisecond has only its proportional light")
	world.advance_to_ms(start + 2)
	runner.assert_eq(_light(world, at), 0, "an enabled but exhausted stone is dark")
	runner.assert_eq(int(world.artifacts.objects.fire_stone.stored_q), 0, "the original reservoir spends its final unit exactly once")
	var exhausted: String = _devices._json(world.to_dict())
	_light(world, at)
	runner.assert_eq(_devices._json(world.to_dict()), exhausted, "reading exhausted light does not create or spend another balance")


func _multiple_and_legacy(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 900000000, true, 5)
	if world == null:
		return
	var at: Vector2i = world.artifacts.object_cell("fire_stone")
	for index: int in 5:
		var id: String = "fire_stone" if index == 0 else "extra_fire_%d" % index
		if not _devices._action(runner, world, "player", "study", id) or not _devices._action(runner, world, "player", "enable", id):
			return
		runner.assert_eq(_light(world, at), mini(40000, (index + 1) * 10000), "real separately issued sources add, with a declared finite light cap")
	var old: RegionalSimulation = _world(runner, 180000000, false)
	if old == null or not _devices._action(runner, old, "player", "study", "fire_stone") or not _devices._action(runner, old, "player", "enable", "fire_stone"):
		return
	runner.assert_eq(_light(old, at), 0, "a bound old definition without lighting does not inherit today's disk capability")
	var stock: int = int(old.artifacts.objects.fire_stone.stored_q)
	var early: Dictionary = old.environment_fields.actual_at(at, old.elapsed_ms)
	old.advance_to_ms(old.elapsed_ms + 173)
	var later: Dictionary = old.environment_fields.actual_at(at, old.elapsed_ms)
	runner.assert_true(bool(early.get("ok", false)) and bool(later.get("ok", false)), "the no-light definition has queryable actual temperatures")
	if bool(early.get("ok", false)) and bool(later.get("ok", false)):
		runner.assert_true(float(later.value_c) > float(early.value_c), "absence of light does not disable the real gradually building heat")
	var rate: int = int(old.artifacts.definitions.types.fire_stone.thermal.rate_q_per_ms)
	runner.assert_eq(int(old.artifacts.objects.fire_stone.stored_q), stock - 173 * rate, "a no-light source still pays its original thermal stock")


func _restore_and_failures(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _devices._action(runner, world, "player", "study", "fire_stone") or not _devices._action(runner, world, "player", "enable", "fire_stone"):
		return
	world.advance_to_ms(world.elapsed_ms + 173)
	var saved: Dictionary = JSON.parse_string(_devices._json(world.to_dict()))
	var restored: RegionalSimulation = _world(runner)
	if not _restore(runner, restored, saved):
		return
	var at: Vector2i = world.artifacts.object_cell("fire_stone")
	runner.assert_eq(_light(restored, at), _light(world, at), "restored original devices rebuild the derived outgoing light index")
	var future: int = world.elapsed_ms + 12347
	world.advance_to_ms(future)
	restored.advance_to_ms(future - 1199)
	restored.advance_to_ms(future)
	runner.assert_eq(_devices._json(restored.to_dict()), _devices._json(world.to_dict()), "light leaves complete split and unsplit futures identical")
	var before_stock: int = int(world.artifacts.objects.fire_stone.stored_q)
	world.target_ms += 1
	var unknown: Dictionary = SimLocalLight.at_cell(world, at)
	runner.assert_true(not unknown.supported and unknown.reason == "pending_time" and not unknown.has("total_relative"), "owed time is explicit unknown, not a fake dark result")
	runner.assert_eq(int(world.artifacts.objects.fire_stone.stored_q), before_stock, "an unsupported query does not settle the pending millisecond")
	world.target_ms -= 1
	runner.assert_eq(_light(world, at), 4000, "clearing the artificial backlog restores a supported current light")
	runner.assert_true(world.environment_fields.device_emission_rates(world.elapsed_ms).rates.is_read_only(), "the public outgoing-flow index cannot be mutated by a light observer")
	var original_heat: RefCounted = world.environment_fields
	var other: RegionalSimulation = _world(runner)
	world.environment_fields = other.environment_fields
	runner.assert_true(not SimLocalLight.at_cell(world, at).supported, "a foreign thermal owner cannot silently supply this world's illumination")
	world.environment_fields = original_heat
	runner.assert_true(not SimLocalLight.at_cell(world, Vector2i(-1, 0)).supported, "outside-map query fails explicitly")
	var too_many: Array[Vector2i] = []
	too_many.resize(SimLocalLight.MAX_CELLS + 1)
	runner.assert_true(not SimLocalLight.local_patch(world, too_many).supported, "a batch beyond the declared spatial budget is rejected")


func _restore(runner: Object, world: RegionalSimulation, data: Dictionary) -> bool:
	var restored: bool = world != null and world.restore(data)
	runner.assert_true(restored, "independent JSON restores the complete current world")
	return restored


func _definition_contract(runner: Object) -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/artifacts.json"))
	runner.assert_true(SimArtifacts.valid_definitions(rules), "the current explicit luminous thermal definition is valid")
	var legacy: Dictionary = rules.duplicate(true)
	legacy.types.fire_stone.erase("lighting")
	runner.assert_true(SimArtifacts.valid_definitions(legacy), "old no-light definitions remain valid without changing their fields")
	var sink: Dictionary = rules.duplicate(true)
	sink.types.cold_stone.lighting = rules.types.fire_stone.lighting.duplicate(true)
	runner.assert_true(not SimArtifacts.valid_definitions(sink), "an absorber cannot declare the source-only heat-light effect")
	var unknown: Dictionary = rules.duplicate(true)
	unknown.types.fire_stone.lighting.light_balance = 42
	runner.assert_true(not SimArtifacts.valid_definitions(unknown), "unknown light state is rejected instead of creating a hidden second balance")


func _structures(runner: Object) -> void:
	var rooms: RefCounted = load("res://tests/sim/test_rooms_and_rest.gd").new()
	# An authored initial fixed kitchen borders the existing construction-test
	# yard. It is placed before the regional world and its thermal ports exist.
	var world: RegionalSimulation = _world(runner, 180000000, true, 1, Vector2i(107, 108))
	if world == null:
		return
	rooms._bind_navigation(world)
	var at: Vector2i = world.artifacts.object_cell("fire_stone")
	var registration: Dictionary = world.construction.register_site("player", Vector2i(108, 106))
	runner.assert_true(registration.ok, "a real permitted yard borders the source without covering its protected place: " + str(registration))
	if not registration.ok:
		return
	var wall: Vector2i = at + Vector2i.RIGHT
	var target: Vector2i = at + Vector2i.RIGHT * 2
	var planned: Dictionary = world.construction.place("player", "wood_door", wall)
	runner.assert_true(planned.ok, "a free neighboring cell accepts an actual door blueprint")
	if not planned.ok:
		return
	var door: String = str(planned.project)
	var built: Dictionary = world.construction.begin("player", door)
	runner.assert_true(built.ok, "the source's neighboring door is built with original stock/work")
	if not built.ok:
		return
	rooms._fixtures._finish(runner, world)
	world.regions.home.set_actor_cell("player", at)
	world.invalidate_region("home")
	if not _devices._action(runner, world, "player", "study", "fire_stone") or not _devices._action(runner, world, "player", "enable", "fire_stone"):
		return
	runner.assert_true(world.construction.blocks_sight(wall), "the completed closed door is a physical opaque fact")
	runner.assert_true(_light(world, wall) > 0, "the facing surface of a real closed door receives light")
	runner.assert_eq(_light(world, target), 0, "the same closed door blocks its actual rear cell")
	for verb: String in ["open", "close", "demolish"]:
		var response: Dictionary = world.construction.begin("player", door, verb)
		runner.assert_true(response.ok, "real timed door operation starts: " + verb)
		if not response.ok:
			return
		rooms._fixtures._finish(runner, world)
		runner.assert_eq(_light(world, target) > 0, verb != "close", "the committed door/structure operation updates the same local light: " + verb)
