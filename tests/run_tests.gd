extends SceneTree
## Minimal headless test runner for Reol.
##
## Run with:
##   godot --headless --path . --script res://tests/run_tests.gd
##   godot --headless --path . --script res://tests/run_tests.gd -- --list-suites
##   godot --headless --path . --script res://tests/run_tests.gd -- --suite test_terrain_edits --timing-report user://timings.jsonl
##   godot --headless --path . --script res://tests/run_tests.gd -- --shard 1/4
##
## Convention: every method named `test_*` with no arguments is a test.
## Do not use bare `assert()`: a failed assert can stop before quit() and hang CI.
## Use the helpers below, which record failures and keep going.
## Historical Q-specific groups: docs/qa/legacy-environment-regressions.md.

var passed: int = 0
var failed: int = 0
var checks: int = 0


func _initialize() -> void:
	call_deferred("_run_tests")


func test_stock_hauling() -> void:
	preload("res://tests/sim/test_stock_hauling.gd").new().run(self)


func test_action_routing() -> void:
	preload("res://tests/sim/test_action_routing.gd").new().run(self)


func test_actor_advance() -> void:
	preload("res://tests/sim/test_actor_advance.gd").new().run(self)


func _run_tests() -> void:
	var names: Array[String] = []
	for method in get_method_list():
		var method_name: String = method["name"]
		if method_name.begins_with("test_") and method["args"].is_empty():
			names.append(method_name)
	names.sort()

	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var requested: Dictionary = {}
	var report_path: String = ""
	var shard_spec: String = ""
	var list_only: bool = false
	var arg_index: int = 0
	while arg_index < arguments.size():
		var argument: String = arguments[arg_index]
		match argument:
			"--suite", "--timing-report", "--shard":
				arg_index += 1
				if arg_index >= arguments.size() or arguments[arg_index].strip_edges().is_empty() or arguments[arg_index].begins_with("--"):
					printerr("Missing value for %s" % argument)
					quit(1)
					return
				if argument == "--suite":
					requested[arguments[arg_index]] = true
				elif argument == "--shard":
					if not shard_spec.is_empty():
						printerr("--shard may be specified only once")
						quit(1)
						return
					shard_spec = arguments[arg_index]
				else:
					if not report_path.is_empty():
						printerr("--timing-report may be specified only once")
						quit(1)
						return
					report_path = arguments[arg_index]
			"--list-suites":
				list_only = true
			_:
				printerr("Unknown test argument: %s" % argument)
				quit(1)
				return
		arg_index += 1

	for requested_name in requested:
		if not names.has(requested_name):
			printerr("Unknown test suite: %s" % requested_name)
			quit(1)
			return

	var shard_index: int = 1
	var shard_count: int = 1
	if not shard_spec.is_empty():
		var parts: PackedStringArray = shard_spec.split("/", true)
		if parts.size() != 2 or not parts[0].is_valid_int() or not parts[1].is_valid_int():
			printerr("Invalid test shard; use INDEX/TOTAL with 1 <= INDEX <= TOTAL")
			quit(1)
			return
		shard_index = parts[0].to_int()
		shard_count = parts[1].to_int()
		if shard_index < 1 or shard_index > shard_count or shard_count > names.size() or str(shard_index) != parts[0] or str(shard_count) != parts[1] or not requested.is_empty():
			printerr("Invalid test shard or mixed --suite/--shard selection")
			quit(1)
			return
	var selected: Array[String] = []
	for index: int in names.size():
		var test_name: String = names[index]
		if (requested.is_empty() or requested.has(test_name)) and index % shard_count == shard_index - 1:
			selected.append(test_name)
	if list_only:
		for test_name in selected:
			print(test_name)
		quit(0)
		return

	var report: FileAccess = null
	if not report_path.is_empty():
		report = FileAccess.open(report_path, FileAccess.WRITE)
		if report == null:
			printerr("Cannot open timing report %s (error %d)" % [report_path, FileAccess.get_open_error()])
			quit(1)
			return

	print("Reol tests - Godot %s" % Engine.get_version_info()["string"])
	if not shard_spec.is_empty():
		print("Shard %s: %d of %d suites; this process is partial coverage" % [shard_spec, selected.size(), names.size()])
	if not _write_timing_event(report, {"event": "run_started", "registered_count": names.size(), "registered_suites": names, "shard_index": shard_index, "shard_count": shard_count, "suites": selected}):
		quit(1)
		return

	var timings: Array[Dictionary] = []
	for test_name in selected:
		var before: int = failed
		var checks_before: int = checks
		print("RUN  %s" % test_name)
		if not _write_timing_event(report, {"event": "suite_started", "suite": test_name}):
			quit(1)
			return
		var started: int = Time.get_ticks_usec()
		call(test_name)
		var elapsed_ms: float = float(Time.get_ticks_usec() - started) / 1000.0
		var suite_checks: int = checks - checks_before
		var suite_failures: int = failed - before
		if failed == before:
			passed += 1
			print("PASS %s" % test_name)
		print("TIME %s %.3f ms, %d checks, %d assertion failures" % [test_name, elapsed_ms, suite_checks, suite_failures])
		var timing: Dictionary = {"event": "suite_finished", "suite": test_name, "elapsed_ms": elapsed_ms, "checks": suite_checks, "assertion_failures": suite_failures}
		timings.append(timing)
		if not _write_timing_event(report, timing):
			quit(1)
			return

	print("")
	print("Results: %d passed, %d failed" % [passed, failed])
	print("Assertions: %d" % checks)
	timings.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		if float(a["elapsed_ms"]) == float(b["elapsed_ms"]):
			return str(a["suite"]) < str(b["suite"])
		return float(a["elapsed_ms"]) > float(b["elapsed_ms"])
	)
	print("Slowest suites:")
	for index in range(mini(10, timings.size())):
		var timing: Dictionary = timings[index]
		print("  %s: %.3f ms, %d checks" % [timing["suite"], timing["elapsed_ms"], timing["checks"]])
	if not _write_timing_event(report, {"event": "run_finished", "passed": passed, "failed": failed, "checks": checks}):
		quit(1)
		return
	quit(1 if failed > 0 else 0)


func _write_timing_event(report: FileAccess, event: Dictionary) -> bool:
	if report == null:
		return true
	var line: String = JSON.stringify(event)
	if not report.store_line(line):
		printerr("Cannot write timing report (error %d)" % report.get_error())
		return false
	report.flush()
	return true


func assert_true(condition: bool, label: String) -> void:
	checks += 1
	if condition:
		return
	failed += 1
	printerr("FAIL %s" % label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual == expected:
		return
	failed += 1
	printerr("FAIL %s: expected %s, got %s" % [label, str(expected), str(actual)])


func assert_not_null(value: Variant, label: String) -> void:
	checks += 1
	if value != null:
		return
	failed += 1
	printerr("FAIL %s: value is null" % label)


func test_terrain_overrides() -> void:
	load("res://tests/sim/test_terrain_overrides.gd").new().run(self)


func test_environment_field_rules() -> void:
	load("res://tests/sim/test_environment_field_rules.gd").new().run(self)


func test_participation_index() -> void:
	load("res://tests/sim/test_participation_index.gd").new().run(self)


func test_health_participation() -> void:
	load("res://tests/sim/test_health_participation.gd").new().run(self)


func test_sparse_effect_change() -> void:
	load("res://tests/sim/test_sparse_effect_change.gd").new().run(self)


func test_sparse_field_restore() -> void:
	load("res://tests/sim/test_sparse_field_restore.gd").new().run(self)


func test_environment_source_bindings() -> void:
	load("res://tests/sim/test_environment_source_bindings.gd").new().run(self)


func test_world_environment_fields() -> void:
	load("res://tests/sim/test_world_environment_fields.gd").new().run(self)


func test_environment_composition() -> void:
	load("res://tests/sim/test_environment_composition.gd").new().run(self)


func test_world_field_save_boundary() -> void:
	load("res://tests/runtime/test_world_field_save_boundary.gd").new().run(self)


func test_environment_ground_cache() -> void:
	load("res://tests/sim/test_environment_ground_cache.gd").new().run(self)


func test_environment_inventory_epoch() -> void:
	load("res://tests/sim/test_environment_inventory_epoch.gd").new().run(self)


func test_environment_field_tide() -> void:
	load("res://tests/sim/test_environment_field_tide.gd").new().run(self)


func test_environment_field_index() -> void:
	load("res://tests/sim/test_environment_field_index.gd").new().run(self)


func test_environment_field_response() -> void:
	load("res://tests/sim/test_environment_field_response.gd").new().run(self)


func test_environment_field_contract() -> void:
	load("res://tests/sim/test_environment_field_contract.gd").new().run(self)


func test_environment_field_cache() -> void:
	load("res://tests/sim/test_environment_field_cache.gd").new().run(self)


func test_environment_field_compute_runtime() -> void:
	load("res://tests/runtime/test_environment_field_compute_runtime.gd").new().run(self)


func test_environment_ground_compute() -> void:
	load("res://tests/runtime/test_environment_ground_compute.gd").new().run(self)


func test_environment_temperature_state() -> void:
	load("res://tests/sim/test_environment_temperature_state.gd").new().run(self)


func test_environment_temperature_segments() -> void:
	load("res://tests/sim/test_environment_temperature_segments.gd").new().run(self)


func test_environment_source_change() -> void:
	load("res://tests/sim/test_environment_source_change.gd").new().run(self)


func test_environment_phase_state() -> void:
	load("res://tests/sim/test_environment_phase_state.gd").new().run(self)


func test_environment_response_targets() -> void:
	load("res://tests/sim/test_environment_response_targets.gd").new().run(self)


func test_environment_source_move_projection() -> void:
	load("res://tests/sim/test_environment_source_move_projection.gd").new().run(self)


func test_environment_source_response() -> void:
	load("res://tests/sim/test_environment_source_response.gd").new().run(self)


func test_environment_ground_field() -> void:
	load("res://tests/sim/test_environment_ground_field.gd").new().run(self)


func test_environment_target_compiler() -> void:
	load("res://tests/sim/test_environment_target_compiler.gd").new().run(self)


func test_environment_response_columns() -> void:
	load("res://tests/sim/test_environment_response_columns.gd").new().run(self)


func test_environment_response_file() -> void:
	load("res://tests/sim/test_environment_response_file.gd").new().run(self)


func test_terrain_view_updates() -> void:
	load("res://tests/runtime/test_terrain_view_updates.gd").new().run(self)


func test_terrain_snapshot() -> void:
	load("res://tests/runtime/test_terrain_snapshot.gd").new().run(self)


func test_terrain_edits() -> void:
	load("res://tests/runtime/test_terrain_edits.gd").new().run(self)


func test_structure_query() -> void:
	load("res://tests/sim/test_structure_query.gd").new().run(self)


func test_structure_updates() -> void:
	load("res://tests/runtime/test_structure_updates.gd").new().run(self)


func test_opening_structure_visibility() -> void:
	load("res://tests/runtime/test_opening_structure_visibility.gd").new().run(self)


func test_motion_clearance() -> void:
	load("res://tests/sim/test_motion_clearance.gd").new().run(self)


func test_motion_clearance_runtime() -> void:
	load("res://tests/runtime/test_motion_clearance_runtime.gd").new().run(self)


func test_large_body_query() -> void:
	load("res://tests/sim/test_large_body_query.gd").new().run(self)


func test_heat_source_amounts() -> void:
	load("res://tests/sim/test_heat_source_amounts.gd").new().run(self)


func test_climate_boundaries() -> void:
	load("res://tests/sim/test_climate_boundaries.gd").new().run(self)


func test_geographic_climate() -> void:
	load("res://tests/sim/test_geographic_climate.gd").new().run(self)


func test_geographic_content() -> void:
	load("res://tests/runtime/test_geographic_content.gd").new().run(self)


func test_geographic_world() -> void:
	load("res://tests/sim/test_geographic_world.gd").new().run(self)


func test_intrinsic_light() -> void:
	load("res://tests/sim/test_intrinsic_light.gd").new().run(self)


func test_climate_background() -> void:
	load("res://tests/sim/test_climate_background.gd").new().run(self)


func test_climate_envelope() -> void:
	load("res://tests/sim/test_climate_envelope.gd").new().run(self)


func test_signed_environment() -> void:
	load("res://tests/sim/test_signed_environment.gd").new().run(self)


func test_storage_query() -> void:
	load("res://tests/sim/test_storage_query.gd").new().run(self)


func test_storage_special_anchors() -> void:
	load("res://tests/sim/test_storage_special_anchors.gd").new().run(self)


func test_artifact_transfers() -> void:
	load("res://tests/sim/test_artifact_transfers.gd").new().run(self)


# ---------------------------------------------------------------------------
# Test doubles
# ---------------------------------------------------------------------------


class FakeWalkWorld extends ReolWorld:
	## Only cells listed in `open_cells` can be entered; avoids noise generation.
	var open_cells: Dictionary[Vector2i, bool] = {}


	func _ready() -> void:
		pass


	func can_move(_from_cell: Vector2i, to_cell: Vector2i) -> bool:
		return open_cells.has(to_cell)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------


func test_project_name() -> void:
	var project_name := str(ProjectSettings.get_setting("application/config/name", ""))
	assert_true(not project_name.is_empty(), "project name is set")


func test_snapshot_values() -> void:
	load("res://tests/runtime/test_snapshot_values.gd").new().run(self)


func test_content_bundle() -> void:
	load("res://tests/runtime/test_content_bundle.gd").new().run(self)


func test_world_assembly_inputs() -> void:
	load("res://tests/sim/test_world_assembly_inputs.gd").new().run(self)


func test_village_restore() -> void:
	load("res://tests/sim/test_village_restore.gd").new().run(self)


func test_world_restore_factory() -> void:
	load("res://tests/runtime/test_world_restore_factory.gd").new().run(self)


func test_save_registry() -> void:
	load("res://tests/runtime/test_save_registry.gd").new().run(self)


func test_save_session() -> void:
	load("res://tests/runtime/test_save_session.gd").new().run(self)


func test_regional_restore_boundary() -> void:
	load("res://tests/sim/test_regional_restore_boundary.gd").new().run(self)


func test_entity_query() -> void:
	load("res://tests/sim/test_entity_query.gd").new().run(self)


func test_world_object_query() -> void:
	load("res://tests/sim/test_world_object_query.gd").new().run(self)


func test_world_space() -> void:
	load("res://tests/sim/test_world_space.gd").new().run(self)


func test_object_spatial_snapshot() -> void:
	load("res://tests/sim/test_object_spatial_snapshot.gd").new().run(self)


func test_ground_placements() -> void:
	load("res://tests/sim/test_ground_placements.gd").new().run(self)


func test_object_lifecycle() -> void:
	load("res://tests/sim/test_object_lifecycle.gd").new().run(self)


func test_object_actions() -> void:
	load("res://tests/sim/test_object_actions.gd").new().run(self)


func test_object_lifecycle_import() -> void:
	load("res://tests/runtime/test_object_lifecycle_import.gd").new().run(self)


func test_object_lifecycle_continuity() -> void:
	load("res://tests/runtime/test_object_lifecycle_continuity.gd").new().run(self)


func test_map_descriptor_factory() -> void:
	load("res://tests/sim/test_map_descriptor_factory.gd").new().run(self)


func test_flat_world_map() -> void:
	load("res://tests/sim/test_flat_world_map.gd").new().run(self)


func test_flat_world_runtime() -> void:
	load("res://tests/runtime/test_flat_world_runtime.gd").new().run(self)


func test_weapon_items() -> void:
	load("res://tests/sim/test_weapon_items.gd").new().run(self)


func test_combat_health() -> void:
	load("res://tests/sim/test_combat_health.gd").new().run(self)


func test_combat_qi_ledger() -> void:
	load("res://tests/sim/test_combat_qi_ledger.gd").new().run(self)


func test_conflict_schema() -> void:
	load("res://tests/sim/test_conflict_schema.gd").new().run(self)


func test_conflict_perception() -> void:
	load("res://tests/sim/test_conflict_perception.gd").new().run(self)


func test_conflict_projectile_precision() -> void:
	load("res://tests/sim/test_conflict_projectile_precision.gd").new().run(self)


func test_conflict_perception_migration() -> void:
	load("res://tests/runtime/test_conflict_perception_migration.gd").new().run(self)


func test_source_loan() -> void:
	load("res://tests/sim/test_source_loan.gd").new().run(self)


func test_source_care() -> void:
	load("res://tests/sim/test_source_care.gd").new().run(self)


func test_capability_practice() -> void:
	load("res://tests/sim/test_capability_practice.gd").new().run(self)


func test_field_opportunity_migration() -> void:
	load("res://tests/runtime/test_field_opportunity_migration.gd").new().run(self)


func test_field_opportunity_runtime() -> void:
	load("res://tests/runtime/test_field_opportunity_runtime.gd").new().run(self)


func test_field_artifacts() -> void:
	load("res://tests/sim/test_field_artifacts.gd").new().run(self)


func test_field_opportunities() -> void:
	load("res://tests/sim/test_field_opportunities.gd").new().run(self)


func test_field_views_and_travel() -> void:
	load("res://tests/runtime/test_field_views_and_travel.gd").new().run(self)


func test_field_causality() -> void:
	load("res://tests/sim/test_field_causality.gd").new().run(self)


func test_field_opportunity_absence() -> void:
	load("res://tests/runtime/test_field_opportunity_absence.gd").new().run(self)


func test_capability_queries() -> void:
	load("res://tests/sim/test_capability_queries.gd").new().run(self)


func test_capability_migration() -> void:
	load("res://tests/runtime/test_capability_migration.gd").new().run(self)


func test_capability_runtime() -> void:
	load("res://tests/runtime/test_capability_runtime.gd").new().run(self)


func test_mobile_guard_motion() -> void:
	load("res://tests/sim/test_mobile_guard_motion.gd").new().run(self)


func test_mobile_guard_handoff() -> void:
	load("res://tests/runtime/test_mobile_guard_handoff.gd").new().run(self)


func test_mobile_guard_tactics() -> void:
	load("res://tests/runtime/test_mobile_guard_tactics.gd").new().run(self)


func test_source_care_migration() -> void:
	load("res://tests/runtime/test_source_care_migration.gd").new().run(self)


func test_source_care_continuity() -> void:
	load("res://tests/runtime/test_source_care_continuity.gd").new().run(self)


func test_conflict_agency() -> void:
	load("res://tests/sim/test_conflict_agency.gd").new().run(self)


func test_source_loan_migration() -> void:
	load("res://tests/runtime/test_source_loan_migration.gd").new().run(self)


func test_source_loan_continuity() -> void:
	load("res://tests/runtime/test_source_loan_continuity.gd").new().run(self)


func test_conflicts() -> void:
	load("res://tests/sim/test_conflicts.gd").new().run(self)


func test_weapon_items_runtime() -> void:
	load("res://tests/runtime/test_weapon_items_runtime.gd").new().run(self)


func test_conflict_runtime() -> void:
	load("res://tests/runtime/test_conflict_runtime.gd").new().run(self)


func test_conflict_migration() -> void:
	load("res://tests/runtime/test_conflict_migration.gd").new().run(self)


func test_conflict_mobility() -> void:
	load("res://tests/runtime/test_conflict_mobility.gd").new().run(self)


func test_natural_environment() -> void:
	load("res://tests/sim/test_natural_environment.gd").new().run(self)


func test_natural_world_runtime() -> void:
	load("res://tests/runtime/test_natural_world_runtime.gd").new().run(self)


func test_avian_flock() -> void:
	load("res://tests/sim/test_avian_flock.gd").new().run(self)


func test_workplaces() -> void:
	load("res://tests/sim/test_workplaces.gd").new().run(self)


func test_workplace_runtime() -> void:
	load("res://tests/runtime/test_workplace_runtime.gd").new().run(self)


func test_local_trade() -> void:
	load("res://tests/sim/test_local_trade.gd").new().run(self)


func test_budgeted_labor() -> void:
	load("res://tests/sim/test_budgeted_labor.gd").new().run(self)


func test_autonomous_livelihood() -> void:
	load("res://tests/sim/test_autonomous_livelihood.gd").new().run(self)


func test_calendar_climate() -> void:
	load("res://tests/sim/test_calendar_climate.gd").new().run(self)


func test_solar_rules() -> void:
	load("res://tests/sim/test_solar_rules.gd").new().run(self)


func test_natural_light_runtime() -> void:
	load("res://tests/runtime/test_natural_light_runtime.gd").new().run(self)


func test_environment() -> void:
	load("res://tests/sim/test_environment.gd").new().run(self)


func test_thermal_devices() -> void:
	load("res://tests/sim/test_thermal_devices.gd").new().run(self)


func test_herb_ecology_rules() -> void:
	load("res://tests/sim/test_herb_ecology_rules.gd").new().run(self)


func test_activity_ownership() -> void:
	load("res://tests/sim/test_activity_ownership.gd").new().run(self)


func test_spirit_sources() -> void:
	load("res://tests/sim/test_spirit_sources.gd").new().run(self)


func test_spirit_source_integrity() -> void:
	load("res://tests/sim/test_spirit_source_integrity.gd").new().run(self)


func test_spirit_source_continuity() -> void:
	load("res://tests/runtime/test_spirit_source_continuity.gd").new().run(self)


func test_herb_irrigation() -> void:
	load("res://tests/sim/test_herb_irrigation.gd").new().run(self)


func test_herb_ecology_runtime() -> void:
	load("res://tests/runtime/test_herb_ecology_runtime.gd").new().run(self)


func test_herb_ecology_migration() -> void:
	load("res://tests/runtime/test_herb_ecology_migration.gd").new().run(self)


func test_herb_ecology_environment() -> void:
	load("res://tests/sim/test_herb_ecology_environment.gd").new().run(self)


func test_herb_ecology_limits() -> void:
	load("res://tests/sim/test_herb_ecology_limits.gd").new().run(self)


func test_heat_topology() -> void:
	load("res://tests/sim/test_heat_topology.gd").new().run(self)


func test_artifact_warming() -> void:
	load("res://tests/sim/test_artifact_warming.gd").new().run(self)


func test_local_heat_environment() -> void:
	load("res://tests/sim/test_local_heat_environment.gd").new().run(self)


func test_local_heat_migration() -> void:
	load("res://tests/runtime/test_local_heat_migration.gd").new().run(self)


func test_local_heat_building() -> void:
	load("res://tests/sim/test_local_heat_building.gd").new().run(self)


func test_environment_runtime() -> void:
	load("res://tests/runtime/test_environment_runtime.gd").new().run(self)


func test_humanoid_appearance() -> void:
	load("res://tests/entities/test_humanoid_appearance.gd").new().run(self)


func test_body_facing() -> void:
	load("res://tests/sim/test_body_facing.gd").new().run(self)


func test_humanoid_runtime() -> void:
	load("res://tests/runtime/test_humanoid_runtime.gd").new().run(self)


func test_humanoid_archive() -> void:
	load("res://tests/runtime/test_humanoid_archive.gd").new().run(self)


func test_health_runtime() -> void:
	load("res://tests/runtime/test_health_runtime.gd").new().run(self)


func test_health() -> void:
	load("res://tests/sim/test_health.gd").new().run(self)


func test_clothing() -> void:
	load("res://tests/sim/test_clothing.gd").new().run(self)


func test_clothing_runtime() -> void:
	load("res://tests/runtime/test_clothing_runtime.gd").new().run(self)


func test_autonomous_livelihood_runtime() -> void:
	load("res://tests/runtime/test_autonomous_livelihood_runtime.gd").new().run(self)


func test_budgeted_labor_runtime() -> void:
	load("res://tests/runtime/test_budgeted_labor_runtime.gd").new().run(self)


func test_capability_conversation() -> void:
	load("res://tests/sim/test_capability_conversation.gd").new().run(self)


func test_capability_conversation_runtime() -> void:
	load("res://tests/runtime/test_capability_conversation_runtime.gd").new().run(self)


func test_local_trade_runtime() -> void:
	load("res://tests/runtime/test_local_trade_runtime.gd").new().run(self)


func test_personal_foraging() -> void:
	load("res://tests/sim/test_personal_foraging.gd").new().run(self)


func test_personal_production() -> void:
	load("res://tests/sim/test_personal_production.gd").new().run(self)


func test_personal_production_runtime() -> void:
	load("res://tests/runtime/test_personal_production_runtime.gd").new().run(self)


func test_personal_foraging_runtime() -> void:
	load("res://tests/runtime/test_personal_foraging_runtime.gd").new().run(self)


func test_entrusted_goods() -> void:
	load("res://tests/sim/test_entrusted_goods.gd").new().run(self)


func test_entrusted_goods_runtime() -> void:
	load("res://tests/runtime/test_entrusted_goods_runtime.gd").new().run(self)


func test_standing_work() -> void:
	load("res://tests/sim/test_standing_work.gd").new().run(self)


func test_standing_work_runtime() -> void:
	load("res://tests/runtime/test_standing_work_runtime.gd").new().run(self)


func test_large_bodies() -> void:
	load("res://tests/sim/test_large_bodies.gd").new().run(self)


func test_body_geometry_reuse() -> void:
	load("res://tests/sim/test_body_geometry_reuse.gd").new().run(self)


func test_light_propagation() -> void:
	load("res://tests/sim/test_light_propagation.gd").new().run(self)


func test_local_light() -> void:
	load("res://tests/sim/test_local_light.gd").new().run(self)


func test_local_light_runtime() -> void:
	load("res://tests/runtime/test_local_light_runtime.gd").new().run(self)


func test_intrinsic_light_runtime() -> void:
	load("res://tests/runtime/test_intrinsic_light_runtime.gd").new().run(self)


func test_large_bodies_runtime() -> void:
	load("res://tests/runtime/test_large_bodies_runtime.gd").new().run(self)


func test_method_records() -> void:
	load("res://tests/sim/test_method_records.gd").new().run(self)


func test_method_records_runtime() -> void:
	load("res://tests/runtime/test_method_records_runtime.gd").new().run(self)


func test_embodiment() -> void:
	var suite: Script = load("res://tests/sim/test_embodiment.gd")
	suite.new().run(self)


func test_soul_vessels() -> void:
	var suite: Script = load("res://tests/sim/test_soul_vessels.gd")
	suite.new().run(self)


func test_soul_agency() -> void:
	var suite: Script = load("res://tests/sim/test_soul_agency.gd")
	suite.new().run(self)


func test_soul_player() -> void:
	var suite: Script = load("res://tests/runtime/test_soul_player.gd")
	suite.new().run(self)


func test_social_admission() -> void:
	load("res://tests/sim/test_social_admission.gd").new().run(self)


func test_interaction_requests() -> void:
	var suite: Script = load("res://tests/sim/test_interaction_requests.gd")
	suite.new().run(self)


func test_heat_method_crafting() -> void:
	load("res://tests/sim/test_heat_method_crafting.gd").new().run(self)


func test_construction() -> void:
	load("res://tests/sim/test_construction.gd").new().run(self)


func test_construction_runtime() -> void:
	load("res://tests/runtime/test_construction_runtime.gd").new().run(self)


func test_rooms_and_rest() -> void:
	load("res://tests/sim/test_rooms_and_rest.gd").new().run(self)


func test_rooms_and_rest_runtime() -> void:
	load("res://tests/runtime/test_rooms_and_rest_runtime.gd").new().run(self)


func test_roofs_and_weather() -> void:
	load("res://tests/sim/test_roofs_and_weather.gd").new().run(self)


func test_roofs_weather_runtime() -> void:
	load("res://tests/runtime/test_roofs_weather_runtime.gd").new().run(self)


func test_heat_methods_runtime() -> void:
	load("res://tests/runtime/test_heat_methods_runtime.gd").new().run(self)


func test_interaction_requests_runtime() -> void:
	var suite: Script = load("res://tests/runtime/test_interaction_requests_runtime.gd")
	suite.new().run(self)


func test_social_admission_runtime() -> void:
	load("res://tests/runtime/test_social_admission_runtime.gd").new().run(self)


func test_soul_vessel_runtime() -> void:
	var suite: Script = load("res://tests/runtime/test_soul_vessel_runtime.gd")
	suite.new().run(self)


func test_avian_life() -> void:
	var suite: Script = load("res://tests/sim/test_avian_life.gd")
	suite.new().run(self)


func test_avian_life_runtime() -> void:
	var suite: Script = load("res://tests/runtime/test_avian_life_runtime.gd")
	suite.new().run(self)


func test_player_avatar() -> void:
	var suite: Script = load("res://tests/runtime/test_player_avatar.gd")
	suite.new().run(self)


func test_embodiment_runtime() -> void:
	var suite: Script = load("res://tests/runtime/test_embodiment_runtime.gd")
	suite.new().run(self)


func test_artifacts() -> void:
	var suite: Script = load("res://tests/sim/test_artifacts.gd")
	suite.new().run(self)


func test_artifact_understanding() -> void:
	var suite: Script = load("res://tests/sim/test_artifact_understanding.gd")
	suite.new().run(self)


func test_artifact_understanding_runtime() -> void:
	var suite: Script = load("res://tests/runtime/test_artifact_understanding_runtime.gd")
	suite.new().run(self)


func test_land_resources() -> void:
	var suite: Script = load("res://tests/sim/test_land_resources.gd")
	suite.new().run(self)


func test_land_resources_runtime() -> void:
	var suite: Script = load("res://tests/runtime/test_land_resources_runtime.gd")
	suite.new().run(self)


func test_world_objects_runtime() -> void:
	var suite: Script = load("res://tests/runtime/test_world_objects_runtime.gd")
	suite.new().run(self)


func test_project_features() -> void:
	var features: PackedStringArray = ProjectSettings.get_setting(
		"application/config/features", PackedStringArray()
	)
	assert_true(features.has("4.7"), "project targets Godot 4.7")


func test_main_scene_configured() -> void:
	var main_scene := str(ProjectSettings.get_setting("application/run/main_scene", ""))
	assert_eq(main_scene, "res://scenes/main.tscn", "main scene path")
	assert_true(ResourceLoader.exists(main_scene), "main scene exists")


func test_boot_scene_instantiates() -> void:
	var packed: PackedScene = load("res://scenes/boot.tscn") as PackedScene
	assert_not_null(packed, "boot.tscn loads as PackedScene")
	if packed == null:
		return
	var node: Node = packed.instantiate()
	assert_eq(String(node.name), "Boot", "boot root name")
	node.free()


func test_tile_grid_roundtrip() -> void:
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(0, 1),
		Vector2i(1, 1),
		Vector2i(10, 20),
		Vector2i(511, 511),
	]
	for cell in cells:
		var world_position: Vector2 = TileGrid.cell_to_world(cell)
		assert_eq(
			TileGrid.world_to_cell(world_position),
			cell,
			"grid roundtrip %s" % str(cell)
		)


func test_tile_grid_offsets() -> void:
	assert_eq(TileGrid.cell_to_world(Vector2i(0, 0)), Vector2(32.0, 32.0), "origin center")
	assert_eq(TileGrid.cell_to_world(Vector2i(1, 0)), Vector2(96.0, 32.0), "east offset")
	assert_eq(TileGrid.cell_to_world(Vector2i(0, 1)), Vector2(32.0, 96.0), "south offset")
	assert_eq(TileGrid.cell_to_world(Vector2i(1, 1)), Vector2(96.0, 96.0), "south-east offset")
	assert_eq(TileGrid.world_to_cell(Vector2(0.0, 0.0)), Vector2i(0, 0), "top-left corner")
	assert_eq(TileGrid.world_to_cell(Vector2(63.9, 63.9)), Vector2i(0, 0), "inside tile")
	assert_eq(TileGrid.world_to_cell(Vector2(64.0, 64.0)), Vector2i(1, 1), "next tile")


func test_input_actions_exist() -> void:
	var actions: Array[String] = [
		"move_left",
		"move_right",
		"move_up",
		"move_down",
		"camera_left",
		"camera_right",
		"camera_up",
		"camera_down",
		"center_camera",
		"zoom_in",
		"zoom_out",
		"toggle_pause",
		"speed_1",
		"speed_2",
		"speed_4",
	]
	for action in actions:
		assert_true(InputMap.has_action(action), "input action exists: %s" % action)


func test_world_terrain_and_elevation() -> void:
	var world := ReolWorld.new()
	world.initialize()
	var cells: Array[Vector2i] = [
		Vector2i(0, 0),
		Vector2i(1, 0),
		Vector2i(256, 256),
		Vector2i(511, 511),
	]
	for cell in cells:
		var terrain: int = world.get_terrain(cell)
		assert_true(
			terrain >= ReolWorld.TERRAIN_WATER and terrain <= ReolWorld.TERRAIN_ROCK,
			"terrain range at %s" % str(cell)
		)
		var elevation: int = world.get_elevation(cell)
		assert_true(
			elevation >= 0 and elevation < ReolWorld.ELEVATION_LEVELS,
			"elevation range at %s" % str(cell)
		)
	assert_eq(
		world.world_rect().size,
		Vector2(32768.0, 32768.0),
		"world rect covers 512x512 tiles"
	)
	assert_true(
		not world.can_move(Vector2i(0, 0), Vector2i(-1, 0)),
		"cannot move out of bounds"
	)
	world.free()


func test_world_map_data() -> void:
	load("res://tests/sim/test_world_map_data.gd").new().run(self)


func test_world_map_runtime() -> void:
	load("res://tests/runtime/test_world_map_runtime.gd").new().run(self)


func test_fog_visibility_states() -> void:
	var world := ReolWorld.new()
	world.initialize()
	var fog := FogOfWar.new()
	fog.setup(world, Vector2i(256, 256))

	var center := Vector2i(256, 256)
	assert_true(fog.is_cell_visible(center), "spawn cell is visible")
	assert_true(fog.is_explored(center), "spawn cell is explored")

	var far := Vector2i(306, 256)
	assert_eq(
		fog.get_state(far),
		FogOfWar.STATE_HIDDEN,
		"far cell starts hidden"
	)

	fog.set_focus(far)
	fog.update_now()
	assert_eq(
		fog.get_state(center),
		FogOfWar.STATE_EXPLORED,
		"old visible cell becomes explored"
	)
	assert_true(fog.is_cell_visible(far), "new focus cell is visible")

	fog.free()
	world.free()


func test_can_step_blocks_corner_cut() -> void:
	var fake := FakeWalkWorld.new()
	fake.open_cells[Vector2i(1, 1)] = true
	assert_true(
		not fake.can_step(Vector2i.ZERO, Vector2i(1, 1)),
		"diagonal is blocked when both orthogonal sides are blocked"
	)
	fake.open_cells[Vector2i(1, 0)] = true
	assert_true(
		fake.can_step(Vector2i.ZERO, Vector2i(1, 1)),
		"diagonal is allowed when one orthogonal side is open"
	)
	fake.free()


func test_player_cannot_cut_blocked_corner() -> void:
	var host := Node2D.new()
	var fake := FakeWalkWorld.new()
	fake.name = "World"
	fake.open_cells[Vector2i(1, 1)] = true
	host.add_child(fake)
	var player: PlayerCharacter = PlayerCharacter.new()
	player.motion.rules = JSON.parse_string(FileAccess.get_file_as_string(SimLocalMotion.RULES_PATH))
	host.add_child(player)
	get_root().add_child(host)
	player._ready()

	player.spawn_at(Vector2i.ZERO)
	player._move_step(Vector2(60.0, 60.0))
	assert_eq(player.cell, Vector2i.ZERO, "blocked corner keeps the player in place")
	assert_true(player.blocked, "blocked corner sets the blocked flag")

	fake.open_cells[Vector2i(1, 0)] = true
	player.spawn_at(Vector2i.ZERO)
	player._move_step(Vector2(60.0, 60.0))
	assert_eq(player.cell, Vector2i(1, 1), "an open side allows the diagonal step")

	host.free()


func test_diagonal_corner_rule() -> void:
	assert_true(
		ReolWorld.diagonal_step_allowed(Vector2i(1, 0), false, false),
		"cardinal steps ignore the corner rule"
	)
	assert_true(
		ReolWorld.diagonal_step_allowed(Vector2i(1, 1), true, false),
		"diagonal allowed when the x-side is open"
	)
	assert_true(
		ReolWorld.diagonal_step_allowed(Vector2i(-1, 1), false, true),
		"diagonal allowed when the y-side is open"
	)
	assert_true(
		not ReolWorld.diagonal_step_allowed(Vector2i(1, 1), false, false),
		"diagonal blocked when both sides are blocked"
	)

	var world := ReolWorld.new()
	world.initialize()
	assert_true(
		world.can_step(Vector2i(256, 256), Vector2i.ZERO),
		"zero step is always legal"
	)
	world.free()


func test_elevation_step_rule() -> void:
	assert_true(
		ReolWorld.elevation_step_allowed(1, 2),
		"one-level step is allowed"
	)
	assert_true(
		ReolWorld.elevation_step_allowed(2, 2),
		"same elevation is allowed"
	)
	assert_true(
		not ReolWorld.elevation_step_allowed(0, 2),
		"two-level cliff is blocked"
	)


func test_game_clock_time_math() -> void:
	var clock := ReolGameClock.new()
	clock.advance_ticks(60)
	assert_eq(clock.get_hour(), 1, "60 ticks = 01:00")
	assert_eq(clock.get_minute(), 0, "60 ticks have zero minutes")

	clock.advance_ticks(1439)
	assert_eq(clock.get_day(), 1, "1499 ticks enter day 1")
	assert_eq(clock.get_hour(), 0, "1499 ticks wrap to 00:xx")
	assert_eq(clock.get_minute(), 59, "1499 ticks have 59 minutes")
	assert_eq(clock.format_time(), "第 2 天 00:59", "formatted clock")

	clock.set_speed(2.0)
	assert_eq(clock.speed, 2.0, "speed can be set to 2x")
	clock.set_speed(10.0)
	assert_eq(clock.speed, 4.0, "speed clamps to 4x")
	clock.free()


func test_content_db_loads() -> void:
	var db := ReolContentDB.new()
	assert_true(db.load_all(), "content loads: %s" % str(db.errors))
	if not db.errors.is_empty():
		return
	assert_eq(db.ranks.size(), 3, "three rank definitions")
	assert_eq(db.origins.size(), 3, "three origin definitions")
	assert_eq(db.pawns.size(), 6, "player + five named pawns")
	assert_not_null(db.get_pawn(&"player"), "player definition exists")
	assert_not_null(db.get_pawn(&"su_zhi"), "su_zhi definition exists")
	assert_eq(
		db.get_rank(&"outer_disciple").required_contribution,
		100,
		"outer disciple needs 100 contribution"
	)
	assert_eq(
		db.get_origin(&"drifter").starting_rank_id,
		&"servant",
		"drifter starts as a servant"
	)


func test_pawn_state_and_promotion() -> void:
	var db := ReolContentDB.new()
	if not db.load_all():
		assert_true(false, "content loads for the pawn state test")
		return
	var definition: PawnDef = db.get_pawn(&"player")
	var state := PawnState.create(definition, db)
	assert_eq(state.rank_name(), "杂役", "player starts as a servant")
	assert_eq(state.origin_name(), "流民", "player origin is drifter")
	assert_eq(state.qi, 20, "player starts with full qi")
	state.adjust_hunger(-150.0)
	assert_eq(state.hunger, 0.0, "hunger clamps at zero")
	state.adjust_qi(999)
	assert_eq(state.qi, definition.max_qi, "qi clamps at max")

	var next_rank: RankDef = db.get_rank(&"outer_disciple")
	assert_true(not state.can_promote_to(next_rank, 0), "eligibility reads institutional balance")
	assert_true(state.can_promote_to(next_rank, 100), "eligibility accepts recognized contribution")
	assert_true(state.promote_to(next_rank, 100), "approved promotion succeeds")
	assert_eq(state.rank.id, &"outer_disciple", "rank changed")


func test_scripts_parse() -> void:
	var files: Array[String] = []
	_collect_gd_files("res://scripts", files)
	_collect_gd_files("res://tests", files)

	for path in files:
		if path == "res://tests/run_tests.gd":
			continue
		var resource: Resource = load(path)
		assert_not_null(resource, "parse %s" % path)


func test_sim_ledgers() -> void:
	load("res://tests/sim/test_sim_ledgers.gd").new().run(self)


func test_social_memory() -> void:
	load("res://tests/sim/test_social_memory.gd").new().run(self)


func test_village_navigation() -> void:
	load("res://tests/runtime/test_village_navigation.gd").new().run_tests(self)


func test_village_runtime() -> void:
	load("res://tests/runtime/test_village_runtime.gd").new().run_tests(self)


func test_village_simulation() -> void:
	load("res://tests/sim/test_village_simulation.gd").new().run(self)


func test_village_batch() -> void:
	load("res://tests/sim/test_village_batch.gd").new().run(self)


func test_regional_simulation() -> void:
	load("res://tests/sim/test_regional_simulation.gd").new().run(self)


func test_world_continuity_runtime() -> void:
	load("res://tests/runtime/test_world_continuity_runtime.gd").new().run(self)


func test_world_persistence() -> void:
	load("res://tests/runtime/test_world_persistence.gd").new().run(self)


func test_clock_scheduling() -> void:
	load("res://tests/runtime/test_clock_scheduling.gd").new().run(self)


func test_simulation_pacing() -> void:
	load("res://tests/runtime/test_simulation_pacing.gd").new().run(self)


func test_clock_world_commit() -> void:
	load("res://tests/runtime/test_clock_world_commit.gd").new().run(self)


func test_local_motion() -> void:
	load("res://tests/sim/test_local_motion.gd").new().run(self)


func test_shared_actions() -> void:
	load("res://tests/runtime/test_shared_actions.gd").new().run(self)


func test_life_execution() -> void:
	load("res://tests/runtime/test_life_execution.gd").new().run(self)


func test_sparring() -> void:
	load("res://tests/sim/test_sparring.gd").new().run(self)


func test_sparring_runtime() -> void:
	load("res://tests/runtime/test_sparring_runtime.gd").new().run(self)


func test_artifact_heat_methods() -> void:
	load("res://tests/sim/test_artifact_heat_methods.gd").new().run(self)


func test_stock_information() -> void:
	load("res://tests/sim/test_stock_information.gd").new().run(self)


func test_settlement_services() -> void:
	load("res://tests/sim/test_settlement_services.gd").new().run(self)


func test_settlement_services_runtime() -> void:
	load("res://tests/runtime/test_settlement_services_runtime.gd").new().run(self)


func test_world_presentation() -> void:
	load("res://tests/runtime/test_world_presentation.gd").new().run(self)


func test_demo_refactor() -> void:
	load("res://tests/runtime/test_demo_refactor.gd").new().run(self)


func test_sim_schema() -> void:
	load("res://tests/sim/test_sim_schema.gd").new().run(self)


func test_required_directories() -> void:
	for path in ["res://scenes", "res://scripts", "res://tests", "res://assets"]:
		var dir := DirAccess.open(path)
		assert_not_null(dir, "directory exists: %s" % path)
		if dir != null:
			dir.list_dir_end()


# ---------------------------------------------------------------------------
# Succession resolver
# ---------------------------------------------------------------------------


func test_succession_weak_usurper_freezes_old_claim() -> void:
	var resolver := SuccessionResolver.new()
	var traits: Array[StringName] = [&"paranoid"]
	var candidates: Array[SuccessionResolver.Candidate] = [
		SuccessionResolver.Candidate.new(&"usurper", {
			&"mandate": 0.30,
			&"backing": 0.45,
			&"power": 0.55,
			&"control": 0.60,
			&"standing": 0.40,
			&"purse": 0.30,
			&"predecessor": 0.20,
			&"outside": 0.20,
		}, traits),
	]
	var claims: Array[SuccessionResolver.ClaimCase] = [
		SuccessionResolver.ClaimCase.new(&"old_contribution", &"contribution", {
			&"validity": 0.60,
			&"burden": 0.85,
			&"continuity": 0.45,
			&"affinity": 0.20,
			&"bond": 0.25,
			&"leverage": 0.15,
			&"visibility": 0.40,
			&"precedent": 0.55,
			&"need": 0.20,
			&"old_regime": 0.80,
		}),
	]

	var result: Dictionary = resolver.resolve_succession(candidates, claims)
	assert_true(float(result["legitimacy"]) < 0.60, "weak usurper has low legitimacy")
	var decision: Dictionary = result["claims"][0]
	assert_eq(decision["action"], &"freeze", "weak usurper freezes old-regime claim")
	assert_true(decision["reasons"].size() > 0, "freeze explains itself")
	var tags: Array[StringName] = []
	for reason in decision["reasons"]:
		tags.append(reason["tag"])
	assert_true(tags.has(&"treasury_strained"), "freeze cites empty treasury")
	assert_true(tags.has(&"weak_mandate"), "freeze cites weak mandate")


func test_succession_legitimate_heir_honors_ally() -> void:
	var resolver := SuccessionResolver.new()
	var traits: Array[StringName] = [&"honorable"]
	var candidates: Array[SuccessionResolver.Candidate] = [
		SuccessionResolver.Candidate.new(&"heir", {
			&"mandate": 0.90,
			&"backing": 0.80,
			&"power": 0.75,
			&"control": 0.90,
			&"standing": 0.80,
			&"purse": 0.80,
			&"predecessor": 0.90,
			&"outside": 0.60,
		}, traits),
	]
	var claims: Array[SuccessionResolver.ClaimCase] = [
		SuccessionResolver.ClaimCase.new(&"loyal_contribution", &"contribution", {
			&"validity": 0.90,
			&"burden": 0.20,
			&"continuity": 0.80,
			&"affinity": 0.80,
			&"bond": 0.75,
			&"leverage": 0.35,
			&"visibility": 0.65,
			&"precedent": 0.40,
			&"need": 0.30,
			&"old_regime": 0.20,
		}),
	]

	var result: Dictionary = resolver.resolve_succession(candidates, claims)
	assert_true(float(result["legitimacy"]) > 0.75, "legitimate heir has strong mandate")
	assert_eq(result["claims"][0]["action"], &"honor", "legitimate heir honors allied claim")


func test_succession_weak_ruler_bargains_with_powerful_holder() -> void:
	var resolver := SuccessionResolver.new()
	var traits: Array[StringName] = [&"pragmatic"]
	var candidates: Array[SuccessionResolver.Candidate] = [
		SuccessionResolver.Candidate.new(&"compromise", {
			&"mandate": 0.45,
			&"backing": 0.55,
			&"power": 0.50,
			&"control": 0.60,
			&"standing": 0.50,
			&"purse": 0.40,
			&"predecessor": 0.35,
			&"outside": 0.30,
		}, traits),
	]
	var claims: Array[SuccessionResolver.ClaimCase] = [
		SuccessionResolver.ClaimCase.new(&"sealed_claim", &"contribution", {
			&"validity": 0.95,
			&"burden": 0.70,
			&"continuity": 0.70,
			&"affinity": 0.35,
			&"bond": 0.40,
			&"leverage": 0.90,
			&"visibility": 0.90,
			&"precedent": 0.60,
			&"need": 0.80,
			&"old_regime": 0.50,
		}),
	]

	var result: Dictionary = resolver.resolve_succession(candidates, claims)
	var decision: Dictionary = result["claims"][0]
	assert_eq(decision["action"], &"bargain", "powerful holder gets a bargain, not a repudiation")
	assert_true(decision["unavailable"].has(&"repudiate"), "repudiation is gated by retaliation risk")


func test_succession_secure_ruler_repudiates_dubious_claim() -> void:
	var resolver := SuccessionResolver.new()
	var candidates: Array[SuccessionResolver.Candidate] = [
		SuccessionResolver.Candidate.new(&"secure", {
			&"mandate": 0.90,
			&"backing": 0.85,
			&"power": 0.80,
			&"control": 0.85,
			&"standing": 0.80,
			&"purse": 0.75,
			&"predecessor": 0.80,
			&"outside": 0.60,
		}),
	]
	var claims: Array[SuccessionResolver.ClaimCase] = [
		SuccessionResolver.ClaimCase.new(&"dubious_claim", &"contribution", {
			&"validity": 0.10,
			&"burden": 0.55,
			&"continuity": 0.10,
			&"affinity": 0.25,
			&"bond": 0.30,
			&"leverage": 0.10,
			&"visibility": 0.20,
			&"precedent": 0.10,
			&"need": 0.10,
			&"old_regime": 0.40,
		}),
	]

	var result: Dictionary = resolver.resolve_succession(candidates, claims)
	var decision: Dictionary = result["claims"][0]
	assert_eq(decision["action"], &"repudiate", "secure ruler repudiates a dubious private claim")
	assert_true(decision["unavailable"].has(&"honor"), "unproven claim cannot be honored")
	assert_true(decision["unavailable"].has(&"discount"), "unproven claim cannot be discounted")


func test_succession_expensive_valid_claim_is_discounted() -> void:
	var resolver := SuccessionResolver.new()
	var candidates: Array[SuccessionResolver.Candidate] = [
		SuccessionResolver.Candidate.new(&"moderate", {
			&"mandate": 0.65,
			&"backing": 0.65,
			&"power": 0.65,
			&"control": 0.65,
			&"standing": 0.65,
			&"purse": 0.55,
			&"predecessor": 0.60,
			&"outside": 0.50,
		}),
	]
	var claims: Array[SuccessionResolver.ClaimCase] = [
		SuccessionResolver.ClaimCase.new(&"expensive_claim", &"contribution", {
			&"validity": 0.85,
			&"burden": 0.85,
			&"continuity": 0.60,
			&"affinity": 0.50,
			&"bond": 0.40,
			&"leverage": 0.20,
			&"visibility": 0.40,
			&"precedent": 0.70,
			&"need": 0.20,
			&"old_regime": 0.30,
		}),
	]

	var result: Dictionary = resolver.resolve_succession(candidates, claims)
	var decision: Dictionary = result["claims"][0]
	assert_eq(decision["action"], &"discount", "valid but expensive claim is discounted")
	var ratio: float = decision["discount_ratio"]
	assert_true(ratio > 0.60 and ratio < 0.90, "discount ratio is computed, not fixed at 80%")
	assert_true(not is_equal_approx(ratio, 0.80), "discount ratio is not the old constant")


func test_succession_contest_penalty_and_rivals() -> void:
	var resolver := SuccessionResolver.new()
	var candidates: Array[SuccessionResolver.Candidate] = [
		SuccessionResolver.Candidate.new(&"elder", {
			&"mandate": 0.70,
			&"backing": 0.70,
			&"power": 0.70,
			&"control": 0.70,
			&"standing": 0.70,
			&"purse": 0.70,
			&"predecessor": 0.70,
			&"outside": 0.70,
		}),
		SuccessionResolver.Candidate.new(&"rival", {
			&"mandate": 0.68,
			&"backing": 0.68,
			&"power": 0.68,
			&"control": 0.68,
			&"standing": 0.68,
			&"purse": 0.68,
			&"predecessor": 0.68,
			&"outside": 0.68,
		}),
	]

	var result: Dictionary = resolver.resolve_candidates(candidates)
	assert_eq(result["winner"], &"elder", "higher score wins")
	assert_true(result["contested"], "near-tie is a contested succession")
	assert_true(result["unresolved_rivals"].has(&"rival"), "runner-up remains a rival")
	assert_true(float(result["legitimacy"]) < 0.60, "contest penalizes legitimacy")


func test_succession_interregnum_with_no_eligible_candidate() -> void:
	var resolver := SuccessionResolver.new()
	var blocked := SuccessionResolver.Candidate.new(&"blocked", {
		&"mandate": 0.90,
		&"backing": 0.90,
		&"power": 0.90,
		&"control": 0.90,
		&"standing": 0.90,
		&"purse": 0.90,
		&"predecessor": 0.90,
		&"outside": 0.90,
	})
	blocked.eligible = false
	blocked.ineligible_reason = "fails office charter"
	var candidates: Array[SuccessionResolver.Candidate] = [blocked]

	var result: Dictionary = resolver.resolve_candidates(candidates)
	assert_true(result["interregnum"], "no eligible candidate means interregnum")
	assert_eq(result["winner"], &"", "interregnum has no winner")
	assert_true(float(result["insecurity"]) >= 1.0, "interregnum is maximally insecure")


func test_succession_sealed_artifact_blocks_repudiation() -> void:
	var resolver := SuccessionResolver.new()
	var tags: Array[StringName] = [&"sealed_artifact"]
	var claim := SuccessionResolver.ClaimCase.new(&"artifact_claim", &"contribution", {
		&"validity": 0.95,
		&"burden": 0.80,
		&"continuity": 0.50,
		&"affinity": 0.20,
		&"bond": 0.20,
		&"leverage": 0.10,
		&"visibility": 0.30,
		&"precedent": 0.40,
		&"need": 0.10,
		&"old_regime": 0.60,
	}, tags)
	var context: Dictionary = {
		"insecurity": 0.40,
		"legitimacy": 0.60,
	}

	var decision: Dictionary = resolver.resolve_claim(claim, context)
	assert_true(decision["unavailable"].has(&"repudiate"), "sealed artifact blocks repudiation")
	assert_true(
		decision["unavailable"][&"repudiate"] == &"artifact_validated",
		"repudiation gate names the artifact"
	)


func test_succession_discount_ratio_varies_with_evidence() -> void:
	var resolver := SuccessionResolver.new()
	var strong: float = resolver._discount_ratio({
		&"validity": 0.90,
		&"continuity": 0.80,
		&"burden": 0.20,
	})
	var weak: float = resolver._discount_ratio({
		&"validity": 0.30,
		&"continuity": 0.20,
		&"burden": 0.90,
	})
	assert_true(strong > weak + 0.20, "better evidence recovers more")
	assert_true(strong <= 0.90 and weak >= 0.15, "discount ratio stays in bounds")


func test_succession_policy_override_changes_winner() -> void:
	var resolver := SuccessionResolver.new()
	var candidates: Array[SuccessionResolver.Candidate] = [
		SuccessionResolver.Candidate.new(&"traditional", {
			&"mandate": 1.0,
			&"power": 0.0,
		}),
		SuccessionResolver.Candidate.new(&"warlord", {
			&"mandate": 0.0,
			&"power": 1.0,
		}),
	]

	var before: Dictionary = resolver.resolve_candidates(candidates)
	assert_eq(before["winner"], &"traditional", "default weights favor mandate")

	resolver.apply_policy({
		"candidate_weights": {
			&"mandate": 0.0,
			&"power": 1.0,
		},
	})
	var after: Dictionary = resolver.resolve_candidates(candidates)
	assert_eq(after["winner"], &"warlord", "policy override can favor power")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------


func _collect_gd_files(path: String, out: Array[String]) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full := path.path_join(entry)
		if dir.current_is_dir():
			_collect_gd_files(full, out)
		elif entry.ends_with(".gd"):
			out.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func test_artifact_drawing() -> void:
	load("res://tests/sim/test_artifact_drawing.gd").new().run(self)


func test_drawing_migration() -> void:
	load("res://tests/runtime/test_drawing_migration.gd").new().run(self)


func test_drawing_runtime() -> void:
	load("res://tests/runtime/test_drawing_runtime.gd").new().run(self)


func test_drawing_continuity() -> void:
	load("res://tests/runtime/test_drawing_continuity.gd").new().run(self)


func test_private_exchange() -> void:
	load("res://tests/sim/test_private_exchange.gd").new().run(self)


func test_private_exchange_runtime() -> void:
	load("res://tests/runtime/test_private_exchange_runtime.gd").new().run(self)


func test_private_exchange_migration() -> void:
	load("res://tests/runtime/test_private_exchange_migration.gd").new().run(self)


func test_private_exchange_order() -> void:
	load("res://tests/sim/test_private_exchange_order.gd").new().run(self)


func test_private_exchange_continuity() -> void:
	load("res://tests/runtime/test_private_exchange_continuity.gd").new().run(self)


func test_building_framework() -> void:
	load("res://tests/sim/test_building_framework.gd").new().run(self)


func test_settlement_kernel() -> void:
	load("res://tests/sim/test_settlement_kernel.gd").new().run(self)


func test_event_queue() -> void:
	load("res://tests/sim/test_event_queue.gd").new().run(self)


func test_plants() -> void:
	load("res://tests/sim/test_plants.gd").new().run(self)
