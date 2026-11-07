extends RefCounted
## Allocation uses the original logical cell union, even when Q is compressed.
## The authored geographic content and finite artifact owners remain real.

const Compressed = preload("res://tests/sim/test_thermal_compressed_field.gd")
const HEAT_PATH: String = "res://data/definitions/local_heat.json"
const STONE: String = "hearth_stone"
const FIRE: String = "fire_stone"
const CENTER: Vector2i = Vector2i(116, 116)

## Retain the original navigation and artifact fixture owners for all worlds.
var _fixture := Compressed.new()


func run(runner: Object) -> void:
	_logical_union_and_refusals(runner)
	_refinement_and_weather(runner)
	_custom_capacity_and_restore(runner)
	print("SCENARIO thermal allocation: logical union, bounded real pulse/device actions, unique-Q refinement, geographic weather and independent JSON continuation")


func _world(runner: Object, max_cells: int, reference: bool = false) -> RegionalSimulation:
	# Set the limit in the complete immutable content bundle before creating
	# any original body or domain. This keeps the world and restored candidate
	# bound to the same actual rules and digest rather than a modified live rule.
	var disk := ReolContentDB.new()
	if not disk.load_all():
		runner.assert_true(false, "thermal allocation fixture loads the original complete bundle")
		return null
	var documents: Dictionary = disk.content_bundle().documents
	documents[HEAT_PATH].max_cells = max_cells
	var profile: Variant = JSON.parse_string(FileAccess.get_file_as_string(Compressed.GEOGRAPHY))
	var content: ReolContentDB = ReolGeographicContent.build(ReolContentBundle.from_documents(documents), profile)
	if content == null:
		runner.assert_true(false, "the original geographic profile accepts the explicit bounded content bundle")
		return null
	var instances: Dictionary = {}
	for id: String in ["home", "river"]:
		var village: VillageSimulation = _fixture._regional._make_village(content, id, false)
		if village == null:
			runner.assert_true(false, "bounded fixture constructs original village bodies: " + id)
			return null
		instances[id] = village
	var world := RegionalSimulation.new()
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Compressed.CONTINUITY))
	if not world.initialize(settings, instances, content):
		runner.assert_true(false, "bounded original regional world initializes")
		return null
	if reference:
		# Replace the empty heat authority before any source exists or time runs.
		var heat: SimLocalHeat = Compressed.ReferenceHeat.new()
		if world.elapsed_ms != 0 or not heat.initialize(world, content.local_heat):
			runner.assert_true(false, "fine reference binds the same opening heat rules")
			return null
		heat.set_geometry(world.construction.thermal_roofed, world.construction.thermal_barrier, true)
		world.environment_fields = heat
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(Compressed.ARTIFACTS))
	if not world.configure_services(content.settlement_services) or not world.set_active_region("") or not world.clothing.spawn_opening() or not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "bounded world issues the original services, garments and finite objects")
		return null
	world.services.set_navigation(Callable(_fixture._regional, "_path"))
	world.regions.home.set_actor_cell("player", world.artifacts.object_cell(STONE))
	world.invalidate_region("home")
	return world


func _logical_union_and_refusals(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, 30)
	if world == null or not _fixture._environment._prepare(runner, world):
		return
	_capacity(runner, world, 30, 0, 0, "empty")
	_place_holder(world, CENTER)
	if not _warm(runner, world):
		return
	_capacity(runner, world, 30, 25, 6, "one isolated original pulse")
	var charge: int = int(world.artifacts.objects[STONE].charge)
	var before: String = _state(world)
	var distant := Vector2i(124, 116)
	var amount: int = int(world.environment_fields.definitions.pulse_energy)
	runner.assert_true(not world.environment_fields.can_deposit(distant, amount), "a second isolated 25-cell patch is refused despite only six Q slots being occupied")
	runner.assert_true(world.environment_fields.can_deposit(CENTER + Vector2i.RIGHT, amount), "an overlapping patch fits by counting only its five new logical coordinates")
	runner.assert_eq(_state(world), before, "pure allocation checks do not change time, Q, costs or the world")
	_place_holder(world, distant)
	if not _failed_action(runner, world, "warm", STONE):
		return
	runner.assert_eq(int(world.artifacts.objects[STONE].charge), charge, "a capacity-refused real warm action spends no original charge")
	_capacity(runner, world, 30, 25, 6, "rejected isolated pulse")
	_place_holder(world, CENTER + Vector2i.RIGHT)
	if not _warm(runner, world):
		return
	runner.assert_eq(int(world.artifacts.objects[STONE].charge), charge - 1, "the successful overlapping action spends exactly one original charge")
	_capacity(runner, world, 30, 30, 30, "overlap reaches the exact logical maximum")
	var before_device: String = _state(world)
	runner.assert_true(not world.environment_fields.can_switch_device(FIRE, true), "a distant device patch is refused when the real logical union is full")
	runner.assert_eq(_state(world), before_device, "refused device preflight is a pure query")
	_place_holder(world, world.artifacts.object_cell(FIRE))
	if not _fixture._environment._do_actor(runner, world, "player", "study", FIRE):
		return
	var fire_q: int = int(world.artifacts.objects[FIRE].stored_q)
	if not _failed_action(runner, world, "enable", FIRE):
		return
	runner.assert_true(not bool(world.artifacts.objects[FIRE].enabled), "the rejected original device remains disabled")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), fire_q, "a rejected device does not debit its original reservoir")
	_capacity(runner, world, 30, 30, 30, "rejected device at the exact maximum")


func _refinement_and_weather(runner: Object) -> void:
	var compact: RegionalSimulation = _world(runner, 50)
	var fine: RegionalSimulation = _world(runner, 50, true)
	if compact == null or fine == null:
		return
	for world: RegionalSimulation in [compact, fine]:
		if not _fixture._environment._prepare(runner, world):
			return
		_place_holder(world, CENTER)
		if not _warm(runner, world):
			return
	_capacity(runner, compact, 50, 25, 6, "compressed field before restart")
	_capacity(runner, fine, 50, 25, 25, "independent fine reference")
	if not _same(runner, compact, fine, "compressed and fine worlds match after the original pulse"):
		return
	var resumed: RegionalSimulation = _clone(runner, compact, 50)
	if resumed == null:
		return
	runner.assert_true(resumed.environment_fields != compact.environment_fields and resumed.artifacts != compact.artifacts, "JSON continuation has independent thermal and artifact owners")
	_capacity(runner, resumed, 50, 25, 6, "independent restored compressed field")
	if not _same(runner, resumed, compact, "v3 JSON continuation preserves all world facts"):
		return
	var at: int = int(compact.elapsed_ms)
	var boundary: int = SimWeather.next_phase_boundary_ms(compact.weather.definitions, "home", compact.weather.epoch_ms, at)
	if boundary <= at + 1 or boundary >= SimInventory.MAX_COUNT - 1737:
		runner.assert_true(false, "the original geographic climate supplies an upcoming weather boundary")
		return
	runner.assert_true(SimWeather.kind_at(compact.weather.definitions, "home", compact.weather.epoch_ms, boundary - 1) != SimWeather.kind_at(compact.weather.definitions, "home", compact.weather.epoch_ms, boundary), "the tested boundary actually changes the authored weather")
	var target: int = boundary + 1737
	if not _advance(runner, compact, target) or not _advance(runner, fine, at + 137) or not _advance(runner, fine, target):
		return
	for instant: int in [at + 1, boundary - 1, boundary, target]:
		if not _advance(runner, resumed, instant):
			return
	if not _same(runner, compact, fine, "whole and sliced fine worlds match through the real weather boundary") or not _same(runner, compact, resumed, "the independently restored sliced world matches through weather"):
		return
	_capacity(runner, compact, 50, 25, 6, "weather retains the exact isolated patch")
	for world: RegionalSimulation in [compact, fine, resumed]:
		_place_holder(world, world.artifacts.object_cell(FIRE))
		if not _fixture._environment._do_actor(runner, world, "player", "study", FIRE) or not _fixture._environment._do_actor(runner, world, "player", "enable", FIRE):
			return
		runner.assert_true(bool(world.artifacts.objects[FIRE].enabled), "the learned original stationary device really enables")
		_capacity(runner, world, 50, 50, 50, "device safely refines the earlier compressed block")
	if not _same(runner, compact, fine, "enabled device and fully fine Q match the original reference") or not _same(runner, compact, resumed, "enabled device and fully fine Q match the independent resumed world"):
		return
	var stored: int = int(compact.artifacts.objects[FIRE].stored_q)
	var future: int = int(compact.elapsed_ms) + 1737
	for world: RegionalSimulation in [compact, fine, resumed]:
		if not _advance(runner, world, future):
			return
	runner.assert_true(int(compact.artifacts.objects[FIRE].stored_q) < stored and int(compact.environment_fields.continuous_input) > 0, "the enabled source pays from its one finite original stock")
	_same(runner, compact, fine, "fully refined and fine worlds retain the same physical future")
	_same(runner, compact, resumed, "fully refined and restarted worlds retain the same physical future")


func _custom_capacity_and_restore(runner: Object) -> void:
	# Existing content may declare more than the default 512; this verifies its
	# opening and persistence, not a claim that 600 live cells have been tested.
	var world: RegionalSimulation = _world(runner, 600)
	if world == null:
		return
	runner.assert_eq(int(world._content.content_bundle().documents[HEAT_PATH].max_cells), 600, "the larger supported logical bound is actually bound into the content bundle")
	_capacity(runner, world, 600, 0, 0, "larger valid authored bound")
	var resumed: RegionalSimulation = _clone(runner, world, 600)
	if resumed != null:
		_capacity(runner, resumed, 600, 0, 0, "larger bound after independent JSON restoration")
		_same(runner, resumed, world, "custom content opening and independent JSON state match")


func _failed_action(runner: Object, world: RegionalSimulation, verb: String, object_id: String) -> bool:
	var began: Dictionary = world.artifacts.begin("player", verb, object_id)
	runner.assert_true(bool(began.get("ok", false)), "the original capacity-test action starts: " + verb)
	if not bool(began.get("ok", false)):
		return false
	var due: int = int(world.artifacts.active.player.due_ms)
	var charge: int = int(world.artifacts.objects[STONE].charge)
	var fire_q: int = int(world.artifacts.objects[FIRE].stored_q)
	# A same-time cancelled control lets both worlds settle the real old heat
	# interval; it does not assert that elapsed time should be rolled back.
	var control: RegionalSimulation = _clone(runner, world, int(world.environment_fields.definitions.max_cells))
	if control == null:
		return false
	if not control.artifacts.cancel("player"):
		runner.assert_true(false, "independent control cancels the genuine in-flight action")
		return false
	if not _advance(runner, control, due) or not _advance(runner, world, due):
		return false
	var event: Dictionary = world.artifacts.events.back()
	runner.assert_eq(str(event.kind), "failed", "over-capacity " + verb + " completes with a real failed event")
	runner.assert_true(not event.has("heat_amount"), "the failed action claims no emitted thermal amount")
	runner.assert_eq(int(world.artifacts.objects[STONE].charge), charge, "capacity refusal leaves the original warm-stone charge")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), fire_q, "capacity refusal leaves the original device reservoir")
	runner.assert_eq(_json(world.environment_fields.to_dict()), _json(control.environment_fields.to_dict()), "refusal preserves the old Q, complete ledger, receipts and frozen segment after the legitimately elapsed interval")
	return str(event.kind) == "failed"


func _capacity(runner: Object, world: RegionalSimulation, maximum: int, logical: int, slots: int, label: String) -> void:
	var heat: SimLocalHeat = world.environment_fields
	var before: String = _state(world)
	var row: Dictionary = heat.allocation_capacity()
	runner.assert_eq(int(row.get("max_logical_cells", -1)), maximum, label + ": bound is the bound content's logical limit")
	runner.assert_eq(int(row.get("logical_cells", -1)), logical, label + ": logical coordinates count once")
	runner.assert_eq(int(row.get("q_slots", -1)), slots, label + ": unique running Q slots are reported separately")
	runner.assert_eq(int(row.get("refinement_reserve_q_slots", -1)), logical - slots, label + ": reserve is the additional final Q slots for full refinement")
	runner.assert_eq(int(row.get("fully_fine_q_slots", -1)), logical, label + ": a fully refined field owns one Q per logical cell")
	runner.assert_eq(int(row.get("flow_record_limit", -1)), 6 * maximum + 2, label + ": flow record bound includes the two original thermal device objects")
	row["logical_cells"] = -123
	runner.assert_eq(int(heat.allocation_capacity().get("logical_cells", -1)), logical, label + ": changing the returned capacity report cannot change the owner")
	runner.assert_eq(_state(world), before, label + ": capacity reports are read-only and do not advance time")


func _warm(runner: Object, world: RegionalSimulation) -> bool:
	if not _fixture._environment._do(runner, world, "warm"):
		return false
	var success: bool = not world.artifacts.events.is_empty() and world.artifacts.events.back().kind == "warmed"
	runner.assert_true(success, "the original warm action really produces its paid physical pulse")
	return success


func _place_holder(world: RegionalSimulation, cell: Vector2i) -> void:
	# Fixture placement moves the original body and its carried stone together.
	world.regions.home.set_actor_cell("player", cell)
	world.invalidate_region("home")


func _clone(runner: Object, world: RegionalSimulation, maximum: int) -> RegionalSimulation:
	var saved: Variant = JSON.parse_string(_state(world))
	if not saved is Dictionary:
		runner.assert_true(false, "a complete current regional snapshot survives JSON decoding")
		return null
	var candidate: RegionalSimulation = _world(runner, maximum)
	if candidate == null:
		return null
	runner.assert_eq(str(candidate._content.content_bundle().digest), str(world._content.content_bundle().digest), "independent candidate retains the exact same bound content digest")
	var ok: bool = candidate.restore(saved)
	runner.assert_true(ok, "an independent bounded regional world validates the original JSON state")
	return candidate if ok else null


func _advance(runner: Object, world: RegionalSimulation, target: int) -> bool:
	var ok: bool = world.advance_to_ms(target)
	runner.assert_true(ok, "the original shared clock reaches %dms" % target)
	return ok


func _same(runner: Object, left: RegionalSimulation, right: RegionalSimulation, label: String) -> bool:
	var same: bool = _state(left) == _state(right)
	runner.assert_true(same, label)
	return same


func _state(world: RegionalSimulation) -> String:
	return _json(world.to_dict())


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
