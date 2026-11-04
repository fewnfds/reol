extends SceneTree
## Real-device scale probe. Run with -- 1, 4, 16, 24 or 64 under an external process
## guard. Optional second argument "reference" disables production geometry
## reuse for the measured worlds; independent restores keep production policy.
## Counts identify original artifacts, never a requested heat-cell count.

const SAMPLES: int = 40
const STEP_MS: int = 1000
const FUTURE_MS: int = 7337
const FUTURE_SLICES: Array = [[337, 5000, 7337], [1, 1199, 7336, 7337]]

var _failed: int = 0
var _reference_geometry: bool = false
var _original_max_cells: int = -1
var _benchmark_max_cells: int = -1


func _initialize() -> void:
	call_deferred("_run")


func _check(condition: bool, label: String) -> bool:
	if not condition:
		_failed += 1
		printerr("BENCHMARK_CHECK_FAILED " + label)
	return condition


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() < 1 or args.size() > 2 or not args[0].is_valid_int() or int(args[0]) not in [1, 4, 16, 24, 64] or (args.size() == 2 and args[1] != "reference"):
		_fail("expected actual artifact count 1, 4, 16, 24 or 64, optionally followed by reference")
		return
	var count: int = int(args[0])
	_reference_geometry = args.size() == 2
	var started: int = Time.get_ticks_usec()
	var off: RegionalSimulation = _make_world(count)
	var enabled: RegionalSimulation = _make_world(count)
	var assembly_ms: float = _ms_since(started)
	if off == null or enabled == null:
		_fail("ordinary regional assembly rejected the declared opening workload")
		return
	started = Time.get_ticks_usec()
	if not _actions(off, count, "study") or not _actions(enabled, count, "study") or not _actions(enabled, count, "enable"):
		_fail("real personal study or activation failed; no stock was injected")
		return
	if not _check(off.advance_to_ms(int(enabled.elapsed_ms)), "off baseline reaches the activation clock"):
		_fail("could not align the off baseline")
		return
	var setup_ms: float = _ms_since(started)
	var start_ms: int = int(enabled.elapsed_ms)
	var off_result: Dictionary = _measure(off, count, "off")
	if off_result.is_empty():
		_fail("off measurement, restore or future comparison failed")
		return
	var enabled_result: Dictionary = _measure(enabled, count, "enabled")
	if enabled_result.is_empty():
		_fail("enabled measurement, restore or future comparison failed")
		return
	_check(int(off_result.initial.enabled_devices) == 0 and int(off_result.final.enabled_devices) == 0, "off baseline contains no enabled device")
	_check(int(off_result.initial.cells) == 0 and int(off_result.final.cells) == 0 and int(off_result.final.flows) == 0, "off baseline retains a quiet field")
	_check(int(off_result.final.continuous_input) == 0 and int(off_result.final.absorbed_energy) == 0, "off baseline transfers no device energy")
	_check(int(enabled_result.initial.devices) == count and int(enabled_result.initial.enabled_devices) == count, "requested count equals actual enabled original artifacts")
	_check(int(enabled_result.final.devices) == count and int(enabled_result.final.enabled_devices) == count, "the measured workload retains every actual enabled artifact")
	_check(int(enabled_result.initial.cells) == count * 25 and int(enabled_result.final.cells) == count * 25 and int(enabled_result.initial.flows) > 0, "real nonoverlapping devices allocate exactly their 25 actual cells each")
	for id: String in enabled_result.device_changes:
		var change: Dictionary = enabled_result.device_changes[id]
		if change.mode == "emit":
			_check(int(change.emitted_q) > 0 and int(change.stored_q_change) == -int(change.emitted_q), id + " spends actual finite source stock during measurement")
		else:
			_check(int(change.absorbed_q) > 0 and int(change.stored_q_change) == int(change.absorbed_q), id + " stores actual absorbed heat during measurement")
	if _failed > 0:
		_fail("the measured workload failed its physical checks")
		return
	var report: Dictionary = {
		"benchmark": "thermal_device_scale", "requested_artifacts": count,
		"heat_cell_budget": {"loaded_original_max_cells": _original_max_cells,
			"benchmark_max_cells": _benchmark_max_cells,
			"changed": _original_max_cells != _benchmark_max_cells,
			"scope": "Only each independent in-memory benchmark content binding before world initialization; formal data definition is unchanged.",
			"other_thermal_rules": "unchanged from loaded content"},
		"geometry_policy": "uncached_reference" if _reference_geometry else "production",
		"engine": Engine.get_version_info(), "os": OS.get_name(),
		"processor": OS.get_processor_name(), "logical_processors": OS.get_processor_count(),
		"start_time_ms": start_ms, "sample_count": SAMPLES, "step_ms": STEP_MS,
		"assembly_ms": assembly_ms, "real_action_setup_and_off_alignment_ms": setup_ms,
		"opening_changes": {
			"additional_home_operators": count, "operator_definition": "player", "autonomous": false,
			"additional_fixed_home_places": count, "place_origin_cell": [116, 116],
			"place_grid_columns": 4, "place_spacing_cells": 8,
			"device_definitions": "Cloned fire_stone/cold_stone alternately; only storage_place changes.",
			"device_rules": "Original action durations, qi costs, rate, capacity and opening stock are retained.",
			"baseline": "Both worlds complete personal study; only enabled completes enable. Existing residents are nonautonomous, helpers empty, home opening grain zero, river IDs prefixed, as in the regional fixture."
		},
		"off": off_result, "enabled": enabled_result,
		"limitations": "One externally guarded headless process; off measured first, enabled second. For 24/64 sources the in-memory max_cells bound is raised solely for this isolated benchmark, so these results do not establish production capacity beyond its original bound. Extra operators and places are declared before initialization. No rendering, frame-time or FPS capacity is measured. Forty timing samples are descriptive; p99 is their maximum."
	}
	print("BENCHMARK_JSON " + JSON.stringify(report, "", true, true))
	quit(0)


func _make_world(count: int) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not _check(content.load_all(), "load original content before declaring the benchmark opening"):
		return null
	var loaded_max_cells: int = int(content.local_heat.max_cells)
	var benchmark_max_cells: int = maxi(loaded_max_cells, count * 25)
	if _original_max_cells < 0:
		_original_max_cells = loaded_max_cells
		_benchmark_max_cells = benchmark_max_cells
	if not _check(loaded_max_cells == _original_max_cells and benchmark_max_cells == _benchmark_max_cells, "every independent world uses the same original and benchmark heat-cell limits"):
		return null
	# Change only the isolated in-memory definition before any world owner is
	# assembled; all other thermal rules still come from the loaded content.
	content.local_heat.max_cells = benchmark_max_cells
	var opening: Array[Dictionary] = []
	for index: int in range(count):
		var id: String = _device_id(index)
		var template: String = "fire_stone" if index % 2 == 0 else "cold_stone"
		var definition: Dictionary = content.artifacts.types[template].duplicate(true)
		definition.storage_place = id
		content.artifacts.types[id] = definition
		opening.append({"id": id, "definition": id, "region": "home", "container": id})
	var instances: Dictionary = {}
	for region: String in ["home", "river"]:
		var village: VillageSimulation = _make_village(content, region, count)
		if village == null:
			return null
		instances[region] = village
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	var world := RegionalSimulation.new()
	if not _check(world.initialize(settings, instances, content), "initialize ordinary regional owners: " + str(world.errors)):
		return null
	if not _check(world._content == content and world.local_heat.definitions == content.local_heat, "the world binds the same benchmark thermal content used to assemble it"):
		return null
	if _reference_geometry:
		# Rebind only the callback policy before any object/action/thermal source
		# exists. This changes no definition, clock, Q, stock or event history.
		world.local_heat.set_geometry(world.construction.thermal_roofed, world.construction.thermal_barrier)
		world.local_heat.refresh_geometry()
	if not _check(world.artifacts.spawn_opening({"version": 1, "objects": opening, "experiences": {}}), "issue only the declared original devices"):
		return null
	world.set_active_region("")
	return world


func _make_village(content: ReolContentDB, region: String, count: int) -> VillageSimulation:
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/village.json"))
	var origin := Vector2i(100, 100) if region == "home" else Vector2i(150, 100)
	var profiles: Dictionary = {}
	var cells: Dictionary = {}
	var index: int = 0
	for definition_id: String in settings.actor_profiles:
		var actor: String = definition_id if region == "home" else region + "_" + definition_id
		var profile: Dictionary = settings.actor_profiles[definition_id].duplicate(true)
		profile["definition_id"] = definition_id
		profile["autonomous"] = false
		profiles[actor] = profile
		cells[actor] = [origin.x + index % 3, origin.y + int(index / 3)]
		index += 1
	if region == "home":
		for device_index: int in range(count):
			var id: String = _device_id(device_index)
			var offset: Array[int] = [16 + (device_index % 4) * 8, 16 + int(device_index / 4) * 8]
			settings.place_defs.append({"id": id, "label": id, "offset": offset})
			settings.initial_stock[id] = {}
			var profile: Dictionary = settings.actor_profiles.player.duplicate(true)
			profile["definition_id"] = "player"
			profile["autonomous"] = false
			profiles[_operator_id(device_index)] = profile
			cells[_operator_id(device_index)] = [origin.x + offset[0], origin.y + offset[1]]
	settings.actor_profiles = profiles
	settings["controlled_actor"] = "player" if region == "home" else "river_player"
	settings["autonomous_controller"] = false
	settings.scenario.helpers = []
	settings.initial_stock.store.grain = 0 if region == "home" else 100
	if region == "river":
		settings.scenario.requester = "river_" + str(settings.scenario.requester)
		settings.institution.id = "river_sect"
		for office: Dictionary in settings.institution.offices.values():
			office.holder = "river_" + str(office.holder)
	var places: Dictionary = {}
	for definition: Dictionary in settings.place_defs:
		places[definition.id] = {"label": definition.label, "cell": [origin.x + int(definition.offset[0]), origin.y + int(definition.offset[1])]}
	var village := VillageSimulation.new()
	if not _check(village.initialize(content, settings, cells, places), "initialize declared " + region + " actors and places: " + str(village.errors)):
		return null
	village.set_navigation(_path)
	return village


func _actions(world: RegionalSimulation, count: int, verb: String) -> bool:
	var due_ms: int = int(world.elapsed_ms)
	for index: int in range(count):
		var actor: String = _operator_id(index)
		var result: Dictionary = world.artifacts.begin(actor, verb, _device_id(index))
		if not _check(bool(result.get("ok", false)), "%s/%s starts a real action: %s" % [actor, verb, result]):
			return false
		due_ms = maxi(due_ms, int(world.artifacts.active[actor].due_ms))
	if not _check(world.advance_to_ms(due_ms) and int(world.elapsed_ms) == due_ms, verb + " reaches all actual deadlines"):
		return false
	for index: int in range(count):
		var complete: bool = world.artifacts.shape_studied(_operator_id(index), _device_id(index)) if verb == "study" else bool(world.artifacts.objects[_device_id(index)].enabled)
		if not _check(complete and not world.artifacts.active.has(_operator_id(index)), "%s/%s completes successfully" % [_operator_id(index), verb]):
			return false
	return true


func _measure(world: RegionalSimulation, count: int, label: String) -> Dictionary:
	var initial: Dictionary = _metrics(world)
	if not _conserved(world, label + " initial"):
		return {}
	var timings: Array[float] = []
	var samples: Array[Dictionary] = []
	for index: int in range(SAMPLES):
		var from_ms: int = int(world.elapsed_ms)
		var started: int = Time.get_ticks_usec()
		var reached: bool = world.advance_to_ms(from_ms + STEP_MS)
		var duration_ms: float = _ms_since(started)
		timings.append(duration_ms)
		samples.append({"index": index, "from_ms": from_ms, "to_ms": int(world.elapsed_ms), "advance_ms": duration_ms})
		if not _check(reached and int(world.elapsed_ms) == from_ms + STEP_MS, "%s sample %d reaches its full interval" % [label, index]):
			return {}
	var final: Dictionary = _metrics(world)
	if not _conserved(world, label + " measured"):
		return {}
	var started: int = Time.get_ticks_usec()
	var snapshot: Dictionary = world.to_dict()
	var capture_ms: float = _ms_since(started)
	if not _check(not snapshot.is_empty(), label + " captures the complete regional world"):
		return {}
	started = Time.get_ticks_usec()
	var encoded: String = JSON.stringify(snapshot, "", true, true)
	var encode_ms: float = _ms_since(started)
	started = Time.get_ticks_usec()
	var decoded: Variant = JSON.parse_string(encoded)
	var decode_ms: float = _ms_since(started)
	if not _check(decoded is Dictionary, label + " decodes the complete JSON world"):
		return {}
	var candidates: Array[RegionalSimulation] = []
	var restores: Array[Dictionary] = []
	var canonical_snapshot: String = _json(snapshot)
	for schedule_index: int in range(FUTURE_SLICES.size()):
		started = Time.get_ticks_usec()
		var candidate: RegionalSimulation = _make_world(count)
		var candidate_setup_ms: float = _ms_since(started)
		if candidate == null:
			return {}
		if not _check(candidate._content != world._content and candidate._content.local_heat == world._content.local_heat and candidate.local_heat.definitions == world.local_heat.definitions, label + " independent restore candidate binds identical benchmark heat content"):
			return {}
		started = Time.get_ticks_usec()
		var restored: bool = candidate.restore(decoded)
		var restore_ms: float = _ms_since(started)
		if not _check(restored, label + " independently restores complete JSON state"):
			return {}
		if not _check(candidate.local_heat.definitions == world.local_heat.definitions and candidate._content.local_heat == world._content.local_heat, label + " restored candidate retains the same benchmark heat rules"):
			return {}
		_check(candidate != world and candidate.local_heat != world.local_heat and candidate.artifacts != world.artifacts, label + " restore retains independent original owners")
		if not _check(_json(candidate.to_dict()) == canonical_snapshot, label + " JSON restore preserves every saved domain"):
			return {}
		candidates.append(candidate)
		restores.append({"candidate_setup_ms": candidate_setup_ms, "restore_ms": restore_ms,
			"decode_setup_restore_ms": decode_ms + candidate_setup_ms + restore_ms,
			"capture_encode_decode_setup_restore_ms": capture_ms + encode_ms + decode_ms + candidate_setup_ms + restore_ms})
	var from_ms: int = int(world.elapsed_ms)
	if not _check(world.advance_to_ms(from_ms + FUTURE_MS), label + " whole advance reaches the comparison future"):
		return {}
	if not _conserved(world, label + " whole future"):
		return {}
	var canonical_future: String = _json(world.to_dict())
	for schedule_index: int in range(candidates.size()):
		var candidate: RegionalSimulation = candidates[schedule_index]
		for offset: int in FUTURE_SLICES[schedule_index]:
			if not _check(candidate.advance_to_ms(from_ms + offset), "%s split schedule %d reaches %dms" % [label, schedule_index, offset]):
				return {}
		if not _conserved(candidate, label + " split future") or not _check(_json(candidate.to_dict()) == canonical_future, label + " distinct slicing schedules yield the same full future"):
			return {}
	var changes: Dictionary = {}
	for id: String in initial.device_stock:
		var before: Dictionary = initial.device_stock[id]
		var after: Dictionary = final.device_stock[id]
		changes[id] = {"mode": after.mode, "stored_q_change": int(after.stored_q) - int(before.stored_q),
			"emitted_q": int(after.emitted_q) - int(before.emitted_q), "absorbed_q": int(after.absorbed_q) - int(before.absorbed_q)}
	return {"initial": initial, "final": final, "device_changes": changes,
		"advance_ms": _distribution(timings), "advance_samples": samples,
		"persistence_ms": {"capture": capture_ms, "json_encode": encode_ms, "json_decode": decode_ms, "independent_restores": restores},
		"json_bytes": encoded.to_utf8_buffer().size(), "future_ms": FUTURE_MS,
		"snapshot_sha256": canonical_snapshot.sha256_text(), "future_sha256": canonical_future.sha256_text(),
		"whole_offsets_ms": [FUTURE_MS], "split_offsets_ms": FUTURE_SLICES,
		"complete_restore_equal": true, "all_complete_futures_equal": true, "energy_and_stock_conserved": true}


func _metrics(world: RegionalSimulation) -> Dictionary:
	var heat: RefCounted = world.local_heat
	var energy: int = 0
	for row: Dictionary in heat.cells.values():
		energy += int(row.energy)
	var actors: int = 0
	var places: int = 0
	for village: VillageSimulation in world.regions.values():
		actors += village.actors.size()
		places += village.places.size()
	var stock: Dictionary = {}
	var enabled: int = 0
	for id: String in world.artifacts.objects:
		if not world.artifacts.has_capability(id, "thermal_exchange"):
			continue
		var item: Dictionary = world.artifacts.objects[id]
		var rule: Dictionary = world.artifacts.definitions.types[item.definition].thermal
		enabled += 1 if bool(item.enabled) else 0
		var cell: Vector2i = world.artifacts.object_cell(id)
		stock[id] = {"definition": item.definition, "mode": rule.mode, "region": item.region, "container": item.container,
			"cell": [cell.x, cell.y], "enabled": item.enabled, "stored_q": int(item.stored_q),
			"opening_q": int(rule.opening_q), "capacity_q": int(rule.capacity_q), "rate_q_per_ms": int(rule.rate_q_per_ms),
			"emitted_q": int(heat.device_input.get(id, 0)), "absorbed_q": int(heat.device_absorbed.get(id, 0))}
	return {"at_ms": int(world.elapsed_ms), "regions": world.regions.size(), "actors": actors,
		"couriers": world.couriers.size(), "fixed_places": places, "devices": stock.size(), "enabled_devices": enabled,
		"cells": heat.cells.size(), "flows": heat.flows.size(), "cell_energy": energy,
		"input_energy": int(heat.input_energy), "ambient_in": int(heat.ambient_in), "loss_energy": int(heat.loss_energy),
		"continuous_input": int(heat.continuous_input), "absorbed_energy": int(heat.absorbed_energy), "device_stock": stock}


func _conserved(world: RegionalSimulation, label: String) -> bool:
	var metrics: Dictionary = _metrics(world)
	_check(int(metrics.cell_energy) + int(metrics.loss_energy) + int(metrics.absorbed_energy) == int(metrics.input_energy) + int(metrics.ambient_in) + int(metrics.continuous_input), label + " field conserves energy")
	var emitted: int = 0
	var absorbed: int = 0
	for id: String in metrics.device_stock:
		var item: Dictionary = metrics.device_stock[id]
		_check(int(item.stored_q) >= 0 and int(item.stored_q) <= int(item.capacity_q), label + "/" + id + " retains finite stock")
		if item.mode == "emit":
			_check(int(item.stored_q) + int(item.emitted_q) == int(item.opening_q) and int(item.absorbed_q) == 0, label + "/" + id + " shares one source balance")
		else:
			_check(int(item.stored_q) == int(item.opening_q) + int(item.absorbed_q) and int(item.emitted_q) == 0, label + "/" + id + " shares one sink balance")
		emitted += int(item.emitted_q)
		absorbed += int(item.absorbed_q)
	_check(emitted == int(metrics.continuous_input) and absorbed == int(metrics.absorbed_energy), label + " device ledgers match the field totals")
	_check(world.errors.is_empty(), label + " has no regional errors")
	for village: VillageSimulation in world.regions.values():
		_check(village.errors.is_empty(), label + " has no village errors")
	return _failed == 0


func _distribution(values: Array[float]) -> Dictionary:
	var sorted: Array[float] = values.duplicate()
	sorted.sort()
	return {"count": sorted.size(), "p50": _percentile(sorted, 0.50), "p95": _percentile(sorted, 0.95),
		"p99": _percentile(sorted, 0.99), "max": sorted[-1], "method": "nearest rank"}


func _percentile(values: Array[float], fraction: float) -> float:
	return values[clampi(ceili(values.size() * fraction) - 1, 0, values.size() - 1)]


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _device_id(index: int) -> String:
	return "bench_thermal_%02d" % index


func _operator_id(index: int) -> String:
	return "bench_operator_%02d" % index


func _path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [from_cell]
	var cursor: Vector2i = from_cell
	while cursor.x != to_cell.x:
		cursor.x += 1 if cursor.x < to_cell.x else -1
		path.append(cursor)
	while cursor.y != to_cell.y:
		cursor.y += 1 if cursor.y < to_cell.y else -1
		path.append(cursor)
	return path


func _ms_since(started: int) -> float:
	return float(Time.get_ticks_usec() - started) / 1000.0


func _fail(message: String) -> void:
	printerr("BENCHMARK_ERROR " + message)
	quit(1)
