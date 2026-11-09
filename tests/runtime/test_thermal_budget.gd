extends RefCounted
## A real source, saved climate and weather reach the declared v2 bath limit.
## Neither regional time nor runtime travel may price the rejected interval.

const RuntimeFixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const HEAT_PATH: String = "res://data/definitions/local_heat.json"
const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const WEATHER_PATH: String = "res://data/definitions/weather.json"
const STONE: String = "hearth_stone"
const CHANGE_MS: int = 420000
const BATH_BUDGET: int = 9980000000
var _fixtures := RuntimeFixtures.new()


func run(runner: Object) -> void:
	_regional_preflight(runner)
	_runtime_preflight_and_frame_debt(runner)
	print("SCENARIO thermal budget: real finite source and rain-to-clear warming exhaust exterior input, shared clocks and travel stop before the rejected interval, pending time and frame debt remain")


func _budget_bundle(runner: Object) -> Dictionary:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "thermal budget fixture loads ordinary v2 definitions")
		return {}
	var documents: Dictionary = content.content_bundle().documents
	var heat: Dictionary = documents[HEAT_PATH]
	heat.source_radius = 0
	heat.pulse_energy = 1
	heat.max_exchange_energy = BATH_BUDGET
	# Both climate regions remain constant in time apart from an actual saved
	# rain-to-clear weather phase. The one-cell rainy baseline exactly fills
	# the valid exchange budget; the tiny real pulse creates no initial flow.
	for region: Dictionary in documents[CLIMATE_PATH].regions.values():
		region.base_tenths = 0
		for point: Array in region.seasonal_curve:
			point[1] = 0
		for point: Array in region.daily_curve:
			point[1] = 0
		region.weather_offsets.rain = -20
	var weather: Dictionary = documents[WEATHER_PATH]
	weather.phases = [{"kind": "rain", "duration_ms": CHANGE_MS}, {"kind": "clear", "duration_ms": 600000}]
	weather.regions.home.offset_ms = 0
	weather.regions.river.offset_ms = 0
	var bundle: Dictionary = ReolContentBundle.from_documents(documents)
	var check := ReolContentDB.new()
	runner.assert_true(check.load_bundle(bundle), "bounded weather and heat are valid session-bound v2 content")
	return bundle if check.errors.is_empty() else {}


func _prepare(runner: Object) -> Dictionary:
	var bundle: Dictionary = _budget_bundle(runner)
	if bundle.is_empty():
		return {}
	var fixture: Dictionary = _fixtures._fixture(runner, bundle)
	if fixture.is_empty():
		return {}
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	# This scenario needs no unrelated NPC intentions while the real held stone
	# is studied and used. All original actors and resources remain present.
	for sim: VillageSimulation in world.regions.values():
		for actor: Dictionary in sim.actors.values():
			actor.autonomous = false
	for id: String in world.regions:
		world.invalidate_region(id)
	var player: PlayerCharacter = fixture.player
	player.spawn_at(world.artifacts.object_cell(STONE))
	fixture.home._sync_player_cell()
	var initial_charge: int = int(world.artifacts.objects[STONE].charge)
	if not _perform(runner, world, "study") or not _perform(runner, world, "take") or not _perform(runner, world, "warm"):
		_fixtures._dispose(fixture)
		return {}
	var event: Dictionary = world.artifacts.events.back()
	var activated: bool = event.get("kind") == "warmed" and event.get("heat_amount") == 1 and world.environment_fields.receipts.size() == 1 and world.environment_fields.cells.size() == 1
	runner.assert_true(activated, "one ordinary completed warm action creates a real one-unit thermal receipt and cell")
	runner.assert_eq(int(world.artifacts.objects[STONE].charge), initial_charge - 1, "the real successful source consumes exactly its own stone charge")
	runner.assert_eq(int(world.environment_fields.ambient_in), BATH_BUDGET, "the actual rainy cell allocation fills the declared exterior input budget")
	if not activated or int(world.environment_fields.ambient_in) != BATH_BUDGET:
		_fixtures._dispose(fixture)
		return {}
	runner.assert_true(GameClock.elapsed_ms < CHANGE_MS, "the original source finishes before the declared weather transition")
	if GameClock.elapsed_ms >= CHANGE_MS:
		_fixtures._dispose(fixture)
		return {}
	GameClock.advance_msec(CHANGE_MS - GameClock.elapsed_ms)
	var on_boundary: bool = world.elapsed_ms == CHANGE_MS and world.target_ms == CHANGE_MS and GameClock.elapsed_ms == CHANGE_MS
	runner.assert_true(on_boundary, "real shared time reaches the rain-to-clear boundary before any new exchange")
	if not on_boundary:
		_fixtures._dispose(fixture)
		return {}
	var incoming: bool = false
	for flow: Dictionary in world.environment_fields.flows:
		incoming = incoming or str(flow.from).is_empty() and int(flow.rate) > 0
	runner.assert_true(incoming, "the actual warmer clear-weather boundary produces a positive inward frozen transfer")
	var frozen: bool = not world.environment_fields._geometry_dirty
	runner.assert_true(frozen, "the weather boundary has already frozen its real transfer before the snapshot")
	runner.assert_true(not world.environment_fields.can_settle_at_ms(CHANGE_MS + 1), "the exhausted saved budget refuses even one millisecond of that real transfer")
	if not incoming or not frozen:
		_fixtures._dispose(fixture)
		return {}
	var validation := SimLocalHeat.new()
	var valid: bool = validation.initialize(world, world.environment_fields.definitions)
	if valid:
		validation.set_geometry(world.construction.thermal_roofed, world.construction.thermal_barrier)
		valid = validation.restore(world.environment_fields.to_dict())
	runner.assert_true(valid, "the exhausted state is a fully valid v2 heat candidate with real source and ledger evidence")
	if not valid:
		_fixtures._dispose(fixture)
		return {}
	return fixture


func _perform(runner: Object, world: RegionalSimulation, verb: String) -> bool:
	var response: Dictionary = world.artifacts.begin("player", verb, STONE)
	runner.assert_true(bool(response.get("ok", false)), "real artifact action starts before the weather boundary: " + verb)
	if not bool(response.get("ok", false)):
		return false
	var due: int = int(world.artifacts.active.player.due_ms)
	GameClock.advance_msec(due - GameClock.elapsed_ms)
	var finished: bool = world.elapsed_ms == due and not world.artifacts.active.has("player")
	runner.assert_true(finished, "the actual common clock finishes the original action: " + verb)
	return finished


func _regional_preflight(runner: Object) -> void:
	var fixture: Dictionary = _prepare(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var travelling: bool = runtime.travel_to("river")
	runner.assert_true(travelling and not runtime.player_journey.is_empty(), "a real player journey exists before regional preflight")
	if not travelling:
		_fixtures._dispose(fixture)
		return
	var before: Dictionary = _physical_state(runtime)
	var before_calls: int = int(world.simulation_work.boundaries)
	var advanced: bool = world.advance_to_ms(CHANGE_MS + 50)
	runner.assert_true(not advanced, "the regional executor rejects the numerically unfunded interval")
	runner.assert_eq(int(world.elapsed_ms), CHANGE_MS, "the accepted regional clock does not advance on failed preflight")
	runner.assert_eq(int(world.environment_fields.last_ms), CHANGE_MS, "the physical heat clock remains at the accepted boundary")
	runner.assert_eq(int(world.target_ms), CHANGE_MS + 50, "the requested regional target remains as explicit owed work")
	runner.assert_eq(int(world.simulation_work.boundaries), before_calls, "the failed interval does not consume a regional simulation boundary")
	runner.assert_true(not world.errors.is_empty() and str(world.errors.back()).contains("numerical budget"), "the real numerical-budget failure is reported")
	runner.assert_eq(_physical_state(runtime), before, "both villages, physical heat, source, inventory and the actual journey remain unchanged")
	_fixtures._dispose(fixture)


func _runtime_preflight_and_frame_debt(runner: Object) -> void:
	var fixture: Dictionary = _prepare(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var travelling: bool = runtime.travel_to("river")
	runner.assert_true(travelling and not runtime.player_journey.is_empty(), "runtime starts the real journey before the rejected frame")
	if not travelling:
		_fixtures._dispose(fixture)
		return
	var path: String = "user://tests/thermal_budget_save.json"
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	runner.assert_eq(runtime.save_game(path), OK, "the accepted pre-budget boundary writes a real ordinary primary")
	runner.assert_eq(runtime.save_game(path), OK, "a second valid save establishes the original backup")
	var primary: String = FileAccess.get_file_as_string(path)
	var backup: String = FileAccess.get_file_as_string(path + ".bak")
	var before: Dictionary = _physical_state(runtime)
	var old_clock: int = int(GameClock.elapsed_ms)
	var old_charge: int = int(world.artifacts.objects[STONE].charge)
	runner.assert_true(not GameClock.paused and is_zero_approx(GameClock._accumulator), "the frame begins without prior pause or frame debt")
	# 200ms owes four fixed steps. The first is rejected before displacement
	# and before publication, so the whole original frame remains debt.
	GameClock.advance_frame(0.2)
	runner.assert_true(GameClock.paused, "runtime pauses when the actual thermal preflight rejects the next interval")
	runner.assert_eq(int(world.elapsed_ms), CHANGE_MS, "runtime leaves the last simulated time at the accepted boundary")
	runner.assert_eq(int(world.target_ms), CHANGE_MS + 50, "the first requested fixed step remains owed to the world")
	runner.assert_eq(int(GameClock.elapsed_ms), old_clock, "the clock never publishes the rejected interval ahead of the actual world")
	runner.assert_true(GameClock.has_pending_advance(), "the failed interval remains an explicit pending clock request")
	runner.assert_true(is_equal_approx(GameClock._accumulator, 200.0), "all four uncommitted fixed steps remain as frame debt")
	runner.assert_eq(int(GameClock.elapsed_ms) + int(GameClock._accumulator), CHANGE_MS + 200, "committed time plus debt preserves the whole frame without double-counting the pending target")
	runner.assert_eq(int(world.artifacts.objects[STONE].charge), old_charge, "the rejected interval spends no additional original stone charge")
	runner.assert_eq(_physical_state(runtime), before, "runtime preflight leaves both bodies, inventories, source, field and travelling segment unchanged")
	GameClock.advance_frame(1.0)
	runner.assert_eq(int(world.elapsed_ms), CHANGE_MS, "paused time does not silently process the pending thermal interval")
	runner.assert_true(is_equal_approx(GameClock._accumulator, 200.0), "paused wall time leaves the original frame debt intact")
	runner.assert_eq(runtime.save_game(path), ERR_BUSY, "pending desired time is explicitly refused instead of writing an unloadable save")
	runner.assert_eq(FileAccess.get_file_as_string(path), primary, "failed pending-time save preserves the complete valid primary bytes")
	runner.assert_eq(FileAccess.get_file_as_string(path + ".bak"), backup, "failed pending-time save preserves the complete valid backup bytes")
	runner.assert_true(not FileAccess.file_exists(path + ".tmp") and not FileAccess.file_exists(path + ".bak.tmp"), "pending-time rejection happens before creating file intermediates")
	runner.assert_eq(_physical_state(runtime), before, "rejected save does not change any physical state or journey")
	runner.assert_eq(int(GameClock.elapsed_ms) + int(GameClock._accumulator), CHANGE_MS + 200, "rejected save preserves the full pending frame debt without duplicating the target")
	runner.assert_eq(runtime.load_game(path), OK, "the original ordinary primary loads immediately after rejected save")
	runner.assert_eq(_physical_state(runtime), before, "ordinary recovery restores the last valid complete physical boundary")
	runner.assert_eq(int(GameClock.elapsed_ms), CHANGE_MS, "ordinary load restores the accepted clock rather than inventing the unfunded interval")
	for suffix: String in ["", ".bak"]:
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	_fixtures._dispose(fixture)


func _physical_state(runtime: WorldContinuityRuntime) -> Dictionary:
	var world: RegionalSimulation = runtime.world_sim
	return {
		"home": _canonical(world.regions.home.to_dict()),
		"river": _canonical(world.regions.river.to_dict()),
		"transit_inventory": _canonical(world.in_transit.to_dict()),
		"shipments": _canonical(world.shipments),
		"couriers": _canonical(world.couriers),
		"routes": _canonical(world.routes),
		"operations": _canonical(world.operations),
		"large_bodies": _canonical(world.large_bodies.to_dict()),
		"avian_life": _canonical(world.avian_life.to_dict()),
		"heat": _canonical(world.environment_fields.to_dict()),
		"artifacts": _canonical(world.artifacts.to_dict()),
		"weather": _canonical(world.weather.to_dict()),
		"environment": _canonical(world.environment.to_dict()),
		"health": _canonical(world.health.to_dict()),
		"clothing": _canonical(world.clothing.to_dict()),
		"spirit_sources": _canonical(world.spirit_sources.to_dict()),
		"construction": _canonical(world.construction.to_dict()),
		"journey": _canonical(runtime.player_journey),
		"player_cell": [runtime._home._player.cell.x, runtime._home._player.cell.y],
		"player_position": [runtime._home._player.global_position.x, runtime._home._player.global_position.y],
	}


func _canonical(value: Dictionary) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
