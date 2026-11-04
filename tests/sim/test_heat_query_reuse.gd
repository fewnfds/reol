extends RefCounted
## Compare the production background path with independent per-cell providers.

const EPOCH: int = 777431
const SOURCE: Vector2i = Vector2i(269, 100)


class WeatherInput extends RefCounted:
	var definitions: Dictionary
	var epoch_ms: int = EPOCH


class Authority extends RefCounted:
	var _content: ReolContentDB
	var weather: WeatherInput
	var elapsed_ms: int
	var receipts: Dictionary = {}
	var spatial: bool = false
	var cell_boundaries: bool = false

	func background(cell: Vector2i, at_ms: int) -> int:
		var value: int = int(SimClimateRules.background_at(_content.climate, weather.definitions, weather.epoch_ms, cell, at_ms).temperature_tenths)
		return value + posmod(cell.x, 3) if spatial else value

	func boundary(cell: Vector2i, at_ms: int) -> int:
		var region: String = SimClimateRules.region_at(_content.climate, cell)
		var next: int = SimClimateRules.next_background_boundary_ms(_content.climate, weather.definitions, weather.epoch_ms, region, at_ms)
		var special: int = EPOCH + (17 if posmod(cell.x, 2) == 0 else 23)
		return mini(next, special) if cell_boundaries and at_ms < special else next

	func roof(_cell: Vector2i) -> bool:
		return false

	func barrier(_cell: Vector2i) -> String:
		return "open"

	func matches(receipt: Dictionary) -> bool:
		return receipts.has(receipt.action) and SnapshotValues.normalized(receipt) == SnapshotValues.normalized(receipts[receipt.action])

	func actions() -> Array:
		return receipts.keys()


func run(runner: Object) -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "query-reuse fixtures load real bound definitions")
		return
	_background_equivalence(runner, content)
	_per_cell_providers(runner, content)
	print("SCENARIO heat query reuse: default and independently injected providers share exact fields across two climates, fallback and fractional weather epoch; custom spatial temperatures and per-cell boundaries remain distinct")


func _make(content: ReolContentDB, mode: int, now: int, spatial: bool = false, per_cell_boundary: bool = false) -> Dictionary:
	var owner := Authority.new()
	owner._content = content
	owner.weather = WeatherInput.new()
	owner.weather.definitions = content.weather.duplicate(true)
	owner.elapsed_ms = now
	owner.spatial = spatial
	owner.cell_boundaries = per_cell_boundary
	var heat := SimLocalHeat.new()
	heat.initialize(owner, content.local_heat)
	heat.set_geometry(owner.roof, owner.barrier)
	heat.set_source_validator(owner.matches, owner.actions)
	if mode != 0:
		heat.set_background(owner.background if mode & 1 else Callable(), owner.boundary if mode & 2 else Callable())
	return {"owner": owner, "heat": heat}


func _deposit(fixture: Dictionary, cell: Vector2i) -> bool:
	var receipt: Dictionary = {"action": "source:%d" % fixture.owner.receipts.size(), "actor": "holder", "object": "source",
		"at_ms": fixture.owner.elapsed_ms, "cell": [cell.x, cell.y], "amount": fixture.heat.definitions.pulse_energy}
	if not fixture.heat.deposit(receipt):
		return false
	fixture.owner.receipts[receipt.action] = receipt
	return true


func _state(fixture: Dictionary) -> Variant:
	return SnapshotValues.normalized(fixture.heat.to_dict())


func _advance(fixture: Dictionary, at_ms: int) -> bool:
	fixture.owner.elapsed_ms = at_ms
	return fixture.heat.settle_at_ms(at_ms)


func _background_equivalence(runner: Object, content: ReolContentDB) -> void:
	var boundary: int = SimWeather.next_phase_boundary_ms(content.weather, "river", EPOCH, EPOCH)
	var start: int = boundary - 11
	var fixtures: Array[Dictionary] = []
	for mode: int in 4:
		var fixture: Dictionary = _make(content, mode, start)
		runner.assert_true(_deposit(fixture, SOURCE) and _deposit(fixture, Vector2i.ZERO), "two real patches activate across the climate seam and outside-neighbor fallback: mode %d" % mode)
		fixtures.append(fixture)
	for offset: int in [0, 10, 11, 12, 899, 15000]:
		for fixture: Dictionary in fixtures:
			runner.assert_true(_advance(fixture, start + offset), "real field advances across fractional weather boundary")
		var expected: Variant = _state(fixtures[3])
		for mode: int in 3:
			runner.assert_eq(_state(fixtures[mode]), expected, "default or one-provider path preserves the entire original field: mode %d offset %d" % [mode, offset])
		if offset == 12:
			# Save inside the frozen interval, then validate using its historical
			# anchor while the owner's current time is already later than it.
			var original: Dictionary = fixtures[0]
			var saved: Dictionary = JSON.parse_string(JSON.stringify(original.heat.to_dict(), "", true, true))
			var restored: Dictionary = _make(content, 0, start + offset)
			restored.owner.receipts = original.owner.receipts.duplicate(true)
			runner.assert_true(restored.heat.restore(saved), "independent default candidate reconstructs the saved historical frozen segment")
			runner.assert_eq(_state(restored), _state(original), "restoration retains the exact field and history")
			runner.assert_true(_advance(restored, start + 15000), "restored candidate continues through later real background boundaries")
			var comparison: Dictionary = _make(content, 3, start + offset)
			comparison.owner.receipts = original.owner.receipts.duplicate(true)
			runner.assert_true(comparison.heat.restore(saved) and _advance(comparison, start + 15000), "independent per-cell provider resumes the same saved candidate")
			runner.assert_eq(_state(restored), _state(comparison), "default and per-cell history produce exactly the same full future")


func _per_cell_providers(runner: Object, content: ReolContentDB) -> void:
	var query_only: Dictionary = _make(content, 1, EPOCH, true)
	var both: Dictionary = _make(content, 3, EPOCH, true)
	for fixture: Dictionary in [query_only, both]:
		runner.assert_true(_deposit(fixture, Vector2i(100, 100)), "a spatial custom provider activates an ordinary patch")
		for row: Dictionary in fixture.heat.cells.values():
			var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
			var expected: int = (fixture.owner.background(cell, EPOCH) - int(content.local_heat.reference_tenths)) * int(content.local_heat.capacity_per_tenth)
			runner.assert_eq(int(row.baseline_energy), expected, "same-region custom coordinates retain their distinct actual baseline")
	runner.assert_true(_advance(query_only, EPOCH + 15000) and _advance(both, EPOCH + 15000), "spatial custom temperature advances under either boundary provider")
	runner.assert_eq(_state(query_only), _state(both), "default boundary reuse never coalesces custom spatial temperatures")
	for mode: int in [2, 3]:
		var fixture: Dictionary = _make(content, mode, EPOCH, false, true)
		runner.assert_true(_deposit(fixture, Vector2i(100, 100)), "a per-cell boundary provider activates a real patch")
		runner.assert_eq(fixture.heat.next_boundary_ms(), EPOCH + 17, "same-region cell-specific earliest boundary remains scheduled")
		runner.assert_true(_advance(fixture, EPOCH + 17), "the first per-cell boundary settles normally")
		runner.assert_eq(fixture.heat.next_boundary_ms(), EPOCH + 23, "the other same-region boundary survives the first cell transition")
