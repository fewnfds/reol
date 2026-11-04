extends RefCounted
## Exercise the real receivers against a controlled read-only thermal source.
## Fixed-Q integration and persistence require separate authority tests.

const HeatFixture = preload("res://tests/sim/test_local_heat_environment.gd")
const Ecology = preload("res://scripts/sim/herb_ecology_rules.gd")


class ThermalView extends RefCounted:
	var activation_ms: int = 0
	var last_sample_ms: int = 0
	var current_offset: int = 0
	var sampled_offset: int = 0
	var future_offset: int = 0
	var supported: bool = false

	func current_tenths(_cell: Vector2i) -> int:
		return current_offset

	func sample_tenths(_cell: Vector2i, at_ms: int) -> int:
		return sampled_offset if at_ms == last_sample_ms else 0

	func project_tenths(_cell: Vector2i, _at_ms: int) -> Dictionary:
		return {"supported": true, "value": future_offset} if supported else {"supported": false, "reason": "future_unavailable"}

	func minimum_offset_tenths() -> int:
		return -400

	func maximum_offset_tenths() -> int:
		return 400

	func has_visible_offsets(historical: bool) -> bool:
		return (sampled_offset if historical else current_offset) != 0


class ReceiverWorld extends RefCounted:
	var elapsed_ms: int = 0
	var clothing: SimClothing
	var weather: SimWeather
	var local_heat: RefCounted
	var regions: Dictionary = {}

	func _sorted_keys(value: Dictionary) -> Array:
		var keys: Array = value.keys()
		keys.sort()
		return keys


func run(runner: Object) -> void:
	_receivers(runner)
	_ecology(runner)
	print("SCENARIO signed environment: unknown thermal ranges, actual body and clothing rechecks, historical cold samples and ecological growth")


func _receivers(runner: Object) -> void:
	var fixture := HeatFixture.new()
	var world: RegionalSimulation = fixture._world(runner, 220)
	if world == null or not fixture._prepare(runner, world):
		return
	var wear: Dictionary = world.clothing.begin("lao_zhou", "wear", "clothing:spare:2")
	runner.assert_true(wear.ok, "the hot/cold decision uses an original owned outer garment")
	if not wear.ok:
		return
	var worn: bool = world.advance_to_ms(world.clothing.next_boundary_ms())
	runner.assert_true(worn, "the original outer garment finishes its real use")
	if not worn:
		return

	var heat := ThermalView.new()
	heat.last_sample_ms = world.elapsed_ms
	var view := ReceiverWorld.new()
	view.elapsed_ms = world.elapsed_ms
	view.clothing = world.clothing
	view.weather = world.weather
	view.regions = world.regions
	view.local_heat = heat
	var environment := SimEnvironment.new()
	var initialized: bool = environment.initialize(view, world.environment.definitions)
	runner.assert_true(initialized, "actual environmental rules bind to the controlled source")
	if not initialized:
		return
	world.environment = environment
	var future: int = view.elapsed_ms + 86400000
	var unknown: Dictionary = environment.local_conditions("player", future)
	runner.assert_eq(unknown.get("heat_supported"), false, "an unsupported projection states its uncertainty")
	runner.assert_eq(unknown.get("temperature_min_tenths"), -180, "unknown future includes a colder-than-background offset")
	runner.assert_eq(unknown.get("temperature_max_tenths"), 620, "unknown future includes a warmer-than-background offset")
	runner.assert_true(not unknown.has("temperature_tenths") and not unknown.has("heat_tenths") and not unknown.has("burden_rate"), "unknown future publishes neither a fabricated temperature nor a fabricated burden")
	var player_warmth: int = environment.insulation_for("player")
	var cape: int = SimClimateRules.insulation_at(environment.definitions, "reed_cape", 0)
	runner.assert_eq(SimClimateRules.burden(environment.definitions, -180, player_warmth).energy_rate,
		SimClimateRules.burden(environment.definitions, -180, player_warmth + cape).energy_rate,
		"the cold endpoint saturates, even though a middle temperature can benefit from clothing")
	var other_warmth: int = environment.insulation_for("lao_zhou")
	runner.assert_eq(SimClimateRules.burden(environment.definitions, 620, other_warmth).energy_rate,
		SimClimateRules.burden(environment.definitions, 620, other_warmth - cape).energy_rate,
		"the hot endpoint saturates, even though a middle temperature can benefit from removal")
	runner.assert_true(not environment.warmer_outer("player", "reed_cape", 0, view.elapsed_ms), "a comfortable current body does not dress for an imagined cold")
	runner.assert_true(environment.warmer_outer("player", "reed_cape", 0, future), "a possible cold future retains a clothing decision for recheck")
	runner.assert_true(not environment.cooler_without_outer("lao_zhou", "reed_cape", 0, view.elapsed_ms), "a comfortable current body does not remove its real outer garment")
	runner.assert_true(environment.cooler_without_outer("lao_zhou", "reed_cape", 0, future), "a possible hot future retains a removal decision for recheck")
	runner.assert_eq(world.artifacts._warming_choice("player", view.elapsed_ms), "", "a comfortable current holder does not use the stone")
	runner.assert_eq(world.artifacts._warming_choice("player", future), "hearth_stone", "possible cold beyond the outdoor background retains the stone decision for recheck")

	heat.supported = true
	heat.future_offset = -120
	var predicted: Dictionary = environment.local_conditions("player", future)
	runner.assert_eq(predicted.get("temperature_tenths"), 100, "a supported negative forecast uses the actual signed offset")
	runner.assert_eq(predicted.get("temperature_min_tenths"), 100, "a supported forecast has an exact lower endpoint")
	runner.assert_eq(predicted.get("temperature_max_tenths"), 100, "a supported forecast has an exact upper endpoint")
	heat.current_offset = -120
	heat.sampled_offset = -120
	var current: Dictionary = environment.local_conditions("player")
	runner.assert_true(str(current.feeling).contains("近旁留有寒意"), "the current negative offset has a qualitative cold explanation")
	runner.assert_true(environment.warmer_outer("player", "reed_cape", 0, view.elapsed_ms), "real cold can justify the actual insulated garment")
	runner.assert_eq(world.artifacts._warming_choice("player", view.elapsed_ms), "hearth_stone", "real cold justifies reconsidering the owned charged stone")
	var sample: Dictionary = environment.sample_for("player", view.elapsed_ms)
	runner.assert_true(not sample.cell.is_empty(), "a visible cold field keeps the real historical sample location")
	runner.assert_eq(sample.heat_tenths, -120, "the historical exposure preserves its negative offset")
	runner.assert_eq(sample.temperature_tenths, 100, "the historical exposure uses the background and signed offset")
	heat.current_offset = 200
	runner.assert_true(environment._valid_sample("player", sample, view.elapsed_ms), "later live warmth cannot replace the saved negative exposure")
	heat.last_sample_ms -= 1
	runner.assert_true(not environment._valid_sample("player", sample, view.elapsed_ms), "a different sample timestamp cannot validate the historical exposure")
	heat.last_sample_ms += 1
	runner.assert_true(environment.cooler_without_outer("lao_zhou", "reed_cape", 0, view.elapsed_ms), "actual heat can justify removing the real outer garment")


func _ecology(runner: Object) -> void:
	var definitions: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/land_resources.json"))
	var rules: Dictionary = definitions.types.wild_herbs.ecology
	var cold: Dictionary = Ecology.empty_state(rules, 0, 0, {"temperature_tenths": 0, "heat_tenths": -220})
	var warm: Dictionary = Ecology.empty_state(rules, 0, 0, {"temperature_tenths": 220, "heat_tenths": 0})
	runner.assert_eq(cold.version, 2, "signed ecology has its own new state version")
	runner.assert_eq(cold.rules_version, 1, "the ecology definition version stays unchanged")
	runner.assert_true(Ecology.valid_state(cold, rules, 0, 0), "a signed sample with a valid outdoor background passes state validation")
	var old_format: Dictionary = cold.duplicate(true)
	old_format.version = 1
	runner.assert_true(not Ecology.valid_state(old_format, rules, 0, 0), "old ecology state must enter through explicit migration")
	var colder: Dictionary = Ecology.advance(cold, rules, 60000, 0, 8)
	var warmer: Dictionary = Ecology.advance(warm, rules, 60000, 0, 8)
	runner.assert_eq(colder.state.absorbed, 0, "a real below-window temperature prevents future herb growth")
	runner.assert_true(int(warmer.state.absorbed) > 0, "the same watered source grows under the warm background")
	runner.assert_true(Ecology.temperature_valid(-1000120, -1000000), "large negative heat remains valid when its background is in range")
	runner.assert_true(not Ecology.temperature_valid(-1000120, 0), "a huge temperature cannot masquerade as an outdoor background")
	runner.assert_true(Ecology.temperature_valid(-SimInventory.MAX_COUNT, -SimInventory.MAX_COUNT), "the exact negative JSON integer boundary remains valid")
	runner.assert_true(Ecology.temperature_valid(SimInventory.MAX_COUNT, SimInventory.MAX_COUNT), "the exact positive JSON integer boundary remains valid")
	runner.assert_true(not Ecology.temperature_valid(-SimInventory.MAX_COUNT, SimInventory.MAX_COUNT), "opposite extreme signed values do not wrap the background check")
