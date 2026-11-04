extends SceneTree
## Fixed-Q component stress only. Invoke once per requested cell count under
## tools.world_benchmark.run_guarded (30 seconds, 1 GiB); this script cannot
## itself enforce the process memory limit. It does not construct a game world.

const COUNTS: Array[int] = [25, 100, 128, 400, 512]
const ADVANCES: int = 40
const ADVANCE_MS: int = 1000
const RESTORES: int = 3
const PULSE_MULTIPLIER: int = 100
const SPLIT_OFFSETS: Array[int] = [1, 337, 3847, 9999, 10000, 17777, 29999, 30000, 37517, 40000]
var _ungrouped_reference: bool = false


class ReferenceHeat extends SimLocalHeat:
	func _rebuild_frozen_groups() -> void:
		_frozen_groups = null


class BenchmarkWeather extends RefCounted:
	var definitions: Dictionary = {}
	var epoch_ms: int = 0


class FieldAuthority extends RefCounted:
	var content: ReolContentDB
	# SimLocalHeat's production fallback reads these exact owner properties via
	# Object.get("_content") and Object.get("weather"). The custom backend still
	# uses the explicit callables below, preserving the original benchmark mode.
	var _content: ReolContentDB
	var weather: BenchmarkWeather
	var elapsed_ms: int = 0
	var source_receipts: Dictionary = {}

	func background(cell: Vector2i, at_ms: int) -> int:
		return int(SimClimateRules.background_at(content.climate, content.weather, 0, cell, at_ms).temperature_tenths)

	func background_boundary(cell: Vector2i, at_ms: int) -> int:
		var region: String = SimClimateRules.region_at(content.climate, cell)
		return SimClimateRules.next_background_boundary_ms(content.climate, content.weather, 0, region, at_ms)

	func roof(_cell: Vector2i) -> bool:
		return false

	func barrier(_cell: Vector2i) -> String:
		return "open"

	func matches_receipt(receipt: Dictionary) -> bool:
		var action: String = str(receipt.get("action", ""))
		# JSON decodes integral coordinates as floats. Compare the complete
		# issued record at the same JSON boundary as the production source.
		return source_receipts.has(action) and SnapshotValues.normalized(receipt) == SnapshotValues.normalized(source_receipts[action])

	func expected_actions() -> Array:
		var actions: Array = source_receipts.keys()
		actions.sort()
		return actions

	func deposit(heat: SimLocalHeat, cell: Vector2i) -> bool:
		# This component fixture owns its issued receipts. No artifact event or
		# claimed in-game action is constructed; deposit performs the real Q work.
		var action: String = "bench:source:%d" % (source_receipts.size() + 1)
		var receipt: Dictionary = {"action": action, "actor": "benchmark_holder", "object": "benchmark_source",
			"at_ms": elapsed_ms, "cell": [cell.x, cell.y], "amount": int(heat.definitions.pulse_energy)}
		if not heat.deposit(receipt):
			return false
		source_receipts[action] = receipt
		return true


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1 or args.size() > 3 or not args[0].is_valid_int() or int(args[0]) not in COUNTS:
		_fail("expected active-cell target 25/100/128/400/512, optional custom/default backend and optional ungrouped reference")
		return
	var target: int = int(args[0])
	var backend: String = "custom"
	if args.size() >= 2:
		if args[1] not in ["custom", "default"]:
			_fail("backend must be custom or default")
			return
		backend = str(args[1])
	if args.size() == 3:
		if args[2] != "ungrouped":
			_fail("third argument must be ungrouped")
			return
		_ungrouped_reference = true
	var default_backend: bool = backend == "default"
	var whole_start: int = Time.get_ticks_usec()
	var content := ReolContentDB.new()
	if not content.load_all():
		_fail("could not load the actual climate, weather and heat definitions: " + str(content.errors))
		return
	var rules: Dictionary = content.local_heat.duplicate(true)
	var default_pulse: int = int(rules.pulse_energy)
	# A stronger finite pulse keeps even patch corners visibly active during
	# measurement. Its scale is reported; all other heat rules are unchanged.
	rules.pulse_energy = default_pulse * PULSE_MULTIPLIER
	if not SimLocalHeat.valid_definitions(rules) or int(rules.max_cells) < target:
		_fail("stress pulse or requested field size violates the real definition contract")
		return
	var centers: Array[Vector2i] = _source_centers(target)
	var probes: Array[Vector2i] = [Vector2i(265, 100)]
	if target in [100, 400]:
		probes = [centers[0]]
	elif target > 25:
		probes.append(Vector2i(270, 100))
	var authority := FieldAuthority.new()
	_configure_authority(authority, content)
	var phase: Dictionary = _actual_phase(authority, probes)
	if phase.is_empty():
		_fail("no real temperature-changing weather boundary found for the field")
		return
	var boundary: int = int(phase.at_ms)
	authority.elapsed_ms = boundary - 120000
	var heat: SimLocalHeat = _new_heat(authority, rules, default_backend)
	if heat == null:
		_fail("fixed-Q component did not initialize")
		return
	var setup_start: int = Time.get_ticks_usec()
	for center: Vector2i in centers:
		if not authority.deposit(heat, center):
			_fail("genuine component deposit failed at " + str(center))
			return
	var setup_ms: float = _ms_since(setup_start)
	if heat.cells.size() != target or heat.cells.size() > int(rules.max_cells):
		_fail("source patches allocated %d cells, expected %d" % [heat.cells.size(), target])
		return
	var warm_start: int = Time.get_ticks_usec()
	# Store a real aligned historical sample before the measured interval.
	authority.elapsed_ms = boundary - 60000
	if not heat.mark_sample(authority.elapsed_ms):
		_fail("could not record the aligned thermal history")
		return
	authority.elapsed_ms = boundary - 30000
	if not heat.settle_at_ms(authority.elapsed_ms):
		_fail("field failed to settle its bounded warm-up")
		return
	var warmup_ms: float = _ms_since(warm_start)
	var visible_before: int = _visible_cells(heat)
	if visible_before != target:
		_fail("only %d of %d allocated cells have observable nonzero offsets before measurement" % [visible_before, target])
		return
	var checkpoint: Dictionary = heat.to_dict()
	var split_owner := FieldAuthority.new()
	_configure_authority(split_owner, content)
	split_owner.elapsed_ms = authority.elapsed_ms
	split_owner.source_receipts = authority.source_receipts.duplicate(true)
	var split_heat: SimLocalHeat = _new_heat(split_owner, rules, default_backend)
	if split_heat == null or not split_heat.restore(checkpoint):
		_fail("could not restore an independent checkpoint for bounded split comparison")
		return
	var measurement_start: int = authority.elapsed_ms
	var advances: Array[float] = []
	var climate_step_ms: float = -1.0
	var calls_crossing_frozen_boundaries: int = 0
	var peak_flows: int = heat.flows.size()
	for index: int in ADVANCES:
		var previous: int = authority.elapsed_ms
		var frozen_boundary: int = heat.next_boundary_ms()
		authority.elapsed_ms = measurement_start + (index + 1) * ADVANCE_MS
		var step_start: int = Time.get_ticks_usec()
		var ok: bool = heat.settle_at_ms(authority.elapsed_ms)
		var step_ms: float = _ms_since(step_start)
		if not ok:
			_fail("thermal advance failed at %d" % authority.elapsed_ms)
			return
		advances.append(step_ms)
		if frozen_boundary <= authority.elapsed_ms:
			calls_crossing_frozen_boundaries += 1
		if previous < boundary and authority.elapsed_ms >= boundary:
			climate_step_ms = step_ms
		peak_flows = maxi(peak_flows, heat.flows.size())
	if climate_step_ms < 0.0:
		_fail("measured interval did not cross the selected real climate boundary")
		return
	var visible_after: int = _visible_cells(heat)
	if visible_after != target:
		_fail("only %d of %d allocated cells have observable nonzero offsets after measurement" % [visible_after, target])
		return
	var conservation: Dictionary = _conservation(heat)
	if not bool(conservation.ok):
		_fail("fixed-Q field failed the explicit ambient/input/loss balance")
		return
	var end_state: Dictionary = heat.to_dict()
	for offset: int in SPLIT_OFFSETS:
		split_owner.elapsed_ms = measurement_start + offset
		if not split_heat.settle_at_ms(split_owner.elapsed_ms):
			_fail("bounded split advance failed at offset %d" % offset)
			return
	var split_conservation: Dictionary = _conservation(split_heat)
	if not bool(split_conservation.ok) or SnapshotValues.normalized(split_heat.to_dict()) != SnapshotValues.normalized(end_state):
		_fail("bounded split execution diverged from the measured whole field")
		return
	var persistence: Dictionary = _measure_persistence(authority, heat, rules, end_state, default_backend)
	if not bool(persistence.get("ok", false)):
		_fail("snapshot stage failed " + JSON.stringify(persistence.get("diagnostic", {}), "", true, true))
		return
	var energy_values: Dictionary = {}
	for row: Dictionary in heat.cells.values():
		energy_values[int(row.energy)] = true
	var report: Dictionary = {
		"kind": "thermal_field_component",
		"backend": backend,
		"integration_policy": "original_flows" if _ungrouped_reference else "frozen_equivalence",
		"frozen_groups_at_end": 0 if heat._frozen_groups == null else int(heat._frozen_groups.group_count),
		"distinct_energy_values_at_end": energy_values.size(),
		"state_sha256": SnapshotValues.canonical_json(SnapshotValues.normalized(end_state)).sha256_text(),
		"scope": "isolated fixed-Q field; open unroofed geometry; synthetic receipt-owning component source; actual climate and weather rules; no actor, artifact, world, rendering or full-save benchmark",
		"engine": Engine.get_version_info(), "debug_build": OS.has_feature("debug"),
		"required_external_guard": {"seconds": 30, "memory_bytes": 1073741824},
		"workload": {"target_cells": target, "allocated_cells": heat.cells.size(),
			"visible_cells_before": visible_before, "visible_cells_after": visible_after,
			"source_receipts": authority.source_receipts.size(), "source_radius": int(rules.source_radius),
			"nominal_pulse_energy": default_pulse, "pulse_multiplier": PULSE_MULTIPLIER,
			"pulse_energy": int(rules.pulse_energy), "peak_flow_records": peak_flows,
			"start_ms": measurement_start, "end_ms": authority.elapsed_ms,
			"advance_calls": advances.size(), "advance_interval_ms": ADVANCE_MS,
			"calls_crossing_frozen_boundaries": calls_crossing_frozen_boundaries,
			"split_calls": SPLIT_OFFSETS.size(), "climate_boundary": phase},
		"setup_ms": setup_ms, "warmup_ms": warmup_ms,
		"advance_ms": _distribution(advances), "advance_samples_ms": advances.duplicate(),
		"climate_boundary_advance_ms": climate_step_ms,
		"persistence": persistence, "conservation": conservation, "split_consistent": true,
		"worker_elapsed_ms": _ms_since(whole_start)}
	print("BENCHMARK_RESULT " + JSON.stringify(report, "", true, true))
	quit(0)


func _source_centers(count: int) -> Array[Vector2i]:
	if count in [100, 400]:
		# Identical isolated finite-pulse patches provide a real low-diversity
		# workload. Keep it separate from the irregular cross-climate lattice.
		var isolated: Array[Vector2i] = []
		for index: int in range(4 if count == 100 else 16):
			isolated.append(Vector2i(100 + (index % 4) * 8, 100 + (index / 4) * 8))
		return isolated
	# Real overlapping 5x5 source patches form exactly 5x5, 8x16 and 16x32.
	var xs: Array[int] = [265]
	var ys: Array[int] = [100]
	if count == 128:
		xs = [265, 268]
		ys = [100, 105, 110, 111]
	elif count == 512:
		xs = [265, 270, 275, 276]
		ys = [100, 105, 110, 115, 120, 125, 127]
	var result: Array[Vector2i] = []
	for x: int in xs:
		for y: int in ys:
			result.append(Vector2i(x, y))
	return result


func _configure_authority(authority: FieldAuthority, content: ReolContentDB) -> void:
	authority.content = content
	authority._content = content
	authority.weather = BenchmarkWeather.new()
	authority.weather.definitions = content.weather.duplicate(true)
	authority.weather.epoch_ms = 0


func _new_heat(authority: FieldAuthority, rules: Dictionary, default_backend: bool = false) -> SimLocalHeat:
	var heat: SimLocalHeat = ReferenceHeat.new() if _ungrouped_reference else SimLocalHeat.new()
	if not heat.initialize(authority, rules):
		return null
	if not default_backend:
		heat.set_background(Callable(authority, "background"), Callable(authority, "background_boundary"))
	heat.set_geometry(Callable(authority, "roof"), Callable(authority, "barrier"))
	heat.set_source_validator(Callable(authority, "matches_receipt"), Callable(authority, "expected_actions"))
	return heat


func _actual_phase(authority: FieldAuthority, probes: Array[Vector2i]) -> Dictionary:
	var selected: Dictionary = {}
	for cell: Vector2i in probes:
		var region: String = SimClimateRules.region_at(authority.content.climate, cell)
		var at_ms: int = SimWeather.next_phase_boundary_ms(authority.content.weather, region, 0, 600000)
		if at_ms <= 120000 or at_ms == SimInventory.MAX_COUNT:
			continue
		var before: int = authority.background(cell, at_ms - 1)
		var after: int = authority.background(cell, at_ms)
		if before == after:
			continue
		if selected.is_empty() or at_ms < int(selected.at_ms):
			selected = {"region": region, "cell": [cell.x, cell.y], "at_ms": at_ms,
				"temperature_before_tenths": before, "temperature_after_tenths": after}
	return selected


func _visible_cells(heat: SimLocalHeat) -> int:
	var visible: int = 0
	for row: Dictionary in heat.cells.values():
		var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
		if heat.current_tenths(cell) != 0:
			visible += 1
	return visible


func _conservation(heat: SimLocalHeat) -> Dictionary:
	var cells: int = 0
	for row: Dictionary in heat.cells.values():
		cells += int(row.energy)
	return {"ok": cells + heat.loss_energy == heat.input_energy + heat.ambient_in,
		"cell_energy": cells, "source_input": heat.input_energy,
		"ambient_input": heat.ambient_in, "ambient_loss": heat.loss_energy}


func _measure_persistence(authority: FieldAuthority, heat: SimLocalHeat, rules: Dictionary, expected: Dictionary, default_backend: bool) -> Dictionary:
	var captures: Array[float] = []
	var encodes: Array[float] = []
	var decodes: Array[float] = []
	var restores: Array[float] = []
	var bytes: int = 0
	for repeat: int in RESTORES:
		var start: int = Time.get_ticks_usec()
		var snapshot: Dictionary = heat.to_dict()
		captures.append(_ms_since(start))
		start = Time.get_ticks_usec()
		var encoded: String = JSON.stringify(snapshot, "", true, true)
		encodes.append(_ms_since(start))
		bytes = encoded.to_utf8_buffer().size()
		start = Time.get_ticks_usec()
		var decoded: Variant = JSON.parse_string(encoded)
		decodes.append(_ms_since(start))
		if not decoded is Dictionary:
			return {"ok": false, "diagnostic": {"stage": "json_decode", "repeat": repeat,
				"actual_type": type_string(typeof(decoded)), "snapshot_bytes": bytes}}
		var copy: SimLocalHeat = _new_heat(authority, rules, default_backend)
		if copy == null:
			return {"ok": false, "diagnostic": {"stage": "candidate_initialization", "repeat": repeat}}
		start = Time.get_ticks_usec()
		var ok: bool = copy.restore(decoded)
		restores.append(_ms_since(start))
		if not ok:
			return {"ok": false, "diagnostic": _diagnose_restore(authority, copy, rules, snapshot, decoded, repeat, default_backend)}
		var balance: Dictionary = _conservation(copy)
		if not bool(balance.ok):
			return {"ok": false, "diagnostic": {"stage": "restored_conservation", "repeat": repeat, "balance": balance}}
		var restored: Variant = SnapshotValues.normalized(copy.to_dict())
		var original: Variant = SnapshotValues.normalized(expected)
		if restored != original:
			return {"ok": false, "diagnostic": {"stage": "restored_snapshot_difference", "repeat": repeat,
				"first_difference": _first_difference(original, restored, "$")}}
	return {"ok": true, "repetitions": RESTORES, "snapshot_bytes": bytes,
		"capture_ms": _distribution(captures), "json_encode_ms": _distribution(encodes),
		"json_decode_ms": _distribution(decodes), "restore_ms": _distribution(restores)}


func _diagnose_restore(authority: FieldAuthority, copy: SimLocalHeat, rules: Dictionary, snapshot: Dictionary, decoded: Dictionary, repeat: int, default_backend: bool) -> Dictionary:
	# These extra read-only checks run only after the timed restore has failed.
	var memory_copy: SimLocalHeat = _new_heat(authority, rules, default_backend)
	var memory_ok: bool = memory_copy != null and memory_copy.restore(snapshot)
	var baseline_sum: int = 0
	for row: Dictionary in decoded.cells.values():
		baseline_sum += int(row.baseline_energy)
	return {"stage": "restore", "repeat": repeat, "in_memory_restore_ok": memory_ok,
		"json_first_difference": _first_difference(SnapshotValues.normalized(snapshot), decoded, "$"),
		"receipt_mismatch": _receipt_mismatch(authority, decoded.receipts),
		"frozen_segment_valid": SimThermalSchema._frozen_segment(copy, decoded, authority.elapsed_ms, baseline_sum, {}, {}),
		"historical_sample_valid": SimThermalSchema._sample(copy, decoded, authority.elapsed_ms)}


func _receipt_mismatch(authority: FieldAuthority, receipts: Dictionary) -> Dictionary:
	for action: String in receipts:
		var row: Dictionary = receipts[action]
		if authority.matches_receipt(row):
			continue
		if not authority.source_receipts.has(action):
			return {"action": action, "reason": "not issued by the fixture source"}
		var issued: Dictionary = authority.source_receipts[action]
		for field: String in issued:
			if not row.has(field):
				return {"action": action, "field": field, "reason": "missing field"}
			if row[field] != issued[field]:
				var detail: Dictionary = {"action": action, "field": field,
					"issued": issued[field], "decoded": row[field],
					"issued_type": type_string(typeof(issued[field])), "decoded_type": type_string(typeof(row[field]))}
				if issued[field] is Array and row[field] is Array:
					detail["issued_item_types"] = _item_types(issued[field])
					detail["decoded_item_types"] = _item_types(row[field])
				return detail
		return {"action": action, "reason": "record shape or numeric type rejected",
			"issued": issued, "decoded": row}
	return {}


func _item_types(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value: Variant in values:
		result.append(type_string(typeof(value)))
	return result


func _first_difference(expected: Variant, actual: Variant, path: String) -> Dictionary:
	if expected is Dictionary and actual is Dictionary:
		for key: Variant in expected:
			var next: String = path + "." + str(key)
			if not actual.has(key):
				return {"path": next, "reason": "missing key", "expected": expected[key]}
			var difference: Dictionary = _first_difference(expected[key], actual[key], next)
			if not difference.is_empty():
				return difference
		for key: Variant in actual:
			if not expected.has(key):
				return {"path": path + "." + str(key), "reason": "unexpected key", "actual": actual[key]}
		return {}
	if expected is Array and actual is Array:
		if expected.size() != actual.size():
			return {"path": path, "reason": "array size", "expected": expected.size(), "actual": actual.size()}
		for index: int in expected.size():
			var difference: Dictionary = _first_difference(expected[index], actual[index], path + "[%d]" % index)
			if not difference.is_empty():
				return difference
		return {}
	if typeof(expected) != typeof(actual) or expected != actual:
		return {"path": path, "expected": expected, "actual": actual,
			"expected_type": type_string(typeof(expected)), "actual_type": type_string(typeof(actual))}
	return {}


func _distribution(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	var total: float = 0.0
	for value: float in values:
		total += value
	return {"samples": values.size(), "p50": _percentile(sorted, 0.50),
		"p95": _percentile(sorted, 0.95), "p99": _percentile(sorted, 0.99), "max": sorted[-1],
		"mean": total / float(values.size())}


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(values.size() * fraction) - 1, 0, values.size() - 1)]


func _ms_since(start: int) -> float:
	return float(Time.get_ticks_usec() - start) / 1000.0


func _fail(message: String) -> void:
	printerr("BENCHMARK_ERROR " + message)
	quit(1)
