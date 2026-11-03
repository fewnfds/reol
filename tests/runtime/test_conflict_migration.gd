extends RefCounted
## Genuine pre-conflict sessions pass through the ordinary main-scene loader.

const SOURCE: String = "res://tests/fixtures/session_v34.json"
const SOURCE_SHA: String = "07e4a64c2e8415afd912220b3c017bd269947c52c0a23d1536b0888d9f090c78"
const WORKPLACE: String = "res://tests/fixtures/session_v34_workplace_exchange.json"
const WORKPLACE_SHA: String = "59528cf90f23e8b0215b692e86e122589d4500012cf87edb66d06ab50881dca2"


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	var source_bytes: String = FileAccess.get_file_as_string(SOURCE)
	var workplace_bytes: String = FileAccess.get_file_as_string(WORKPLACE)
	runner.assert_eq(FileAccess.get_sha256(SOURCE), SOURCE_SHA, "original source-channel archive has its independently recorded SHA")
	runner.assert_eq(FileAccess.get_sha256(WORKPLACE), WORKPLACE_SHA, "frozen workplace exchange retains its original recorded SHA")
	runner.assert_eq(workplace_bytes.to_utf8_buffer().size(), 204472, "frozen actual workplace snapshot keeps all original bytes")
	var source: Dictionary = JSON.parse_string(source_bytes)
	var workplace: Dictionary = JSON.parse_string(workplace_bytes)
	var expected: Dictionary = {}
	for attempt: int in 2:
		GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
		var main: Node = load("res://scenes/main.tscn").instantiate()
		runner.root.add_child(main)
		var runtime: WorldContinuityRuntime = main._continuity
		if runtime == null or runtime.world_sim == null:
			runner.assert_true(false, "ordinary main initializes before new/old replacement")
			main.free()
			continue
		var path: String = "user://tests/conflict_migration_%d_%d.json" % [Time.get_ticks_usec(), attempt]
		var broken_path: String = path + ".bad.json"
		var opening: Dictionary = WorldSessionSnapshot.capture(runtime)
		runner.assert_eq(int(opening.schema_version), SessionSaveSchema.VERSION, "new ordinary game writes the current explicit root schema")
		runner.assert_eq(int(opening.continuity.world.version), RegionalSimulation.SCHEMA_VERSION, "new ordinary game writes the current regional schema")
		runner.assert_true(runtime.world_sim.artifacts.objects.has("training_sword") and runtime.world_sim.artifacts.objects.has("river_training_sword"), "new opening really has its explicit physical weapon instances")
		runner.assert_eq(runtime.save_game(path), OK, "ordinary saver records the current new opening for a genuine return load")
		var new_present: String = _canonical(WorldSessionSnapshot.capture(runtime))
		var source_future: String = _source_continuation(runtime, source, broken_path, runner)
		runner.assert_eq(runtime.load_game(path), OK, "same ordinary scene returns from the pre-conflict source world to its new opening")
		runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), new_present, "new to old to new restores every saved world and player fact")
		runner.assert_true(runtime.world_sim.artifacts.objects.has("training_sword") and runtime.world_sim.artifacts.objects.has("river_training_sword"), "returning to new game restores its own weapons once")
		var workplace_future: String = _workplace_continuation(runtime, workplace, broken_path, runner)
		if attempt == 0:
			expected = {"source": source_future, "workplace": workplace_future}
		else:
			runner.assert_eq(source_future, expected.source, "two independent main scenes continue the old source action into the identical full future")
			runner.assert_eq(workplace_future, expected.workplace, "two independent new/old replacement sequences continue the old workplace into the identical full future")
		_remove(path)
		_remove(broken_path)
		main.free()
	runner.assert_eq(FileAccess.get_file_as_string(SOURCE), source_bytes, "migration replay never overwrites the original source fixture")
	runner.assert_eq(FileAccess.get_file_as_string(WORKPLACE), workplace_bytes, "migration replay never overwrites the actual workplace fixture")
	runner.assert_eq(FileAccess.get_sha256(SOURCE), SOURCE_SHA, "source fixture remains byte-identical after both full replacement sequences")
	runner.assert_eq(FileAccess.get_sha256(WORKPLACE), WORKPLACE_SHA, "workplace fixture remains byte-identical after both full replacement sequences")
	GameClock.restore_state(clock)
	print("SCENARIO conflict migration: genuine v34 source and workplace saves, new-old-new replacement, explicit current activation, no invented combat or perception facts, original completions and atomic rejection")


func _source_continuation(runtime: WorldContinuityRuntime, source: Dictionary, broken_path: String, runner: Object) -> String:
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(SOURCE))
	runner.assert_eq(error, OK, "new ordinary main loads the immutable pre-conflict source session through its normal absolute-path loader")
	if error != OK:
		return ""
	_assert_activation(runtime, source, runner, "source")
	var world: RegionalSimulation = runtime.world_sim
	runner.assert_eq(GameClock.elapsed_ms, 930050, "migration resumes the actual partial source-channel millisecond")
	runner.assert_eq(_canonical(world.spirit_sources.active), _canonical(source.continuity.world.spirit_sources.active), "original active source work is retained verbatim")
	runner.assert_true(not world.regions.home.config.has("workplaces_version") and not world.regions.river.config.has("workplaces_version"), "old source session is not retrofitted with the new opening rooms")
	var original: Dictionary = world.spirit_sources.active.get("player", {}).duplicate(true)
	runner.assert_true(not original.is_empty(), "old source action genuinely remains pending after migration")
	if original.is_empty():
		return ""
	for actor: String in source.continuity.world.spirit_sources.qi_baselines:
		var baseline: Dictionary = world.spirit_sources.qi_baselines[actor].duplicate(true)
		runner.assert_eq(int(baseline.conflict_floor), 1, "migration activates conflict cost reconciliation from its actual empty beginning")
		runner.assert_eq(int(baseline.practice_floor), 1, "later practice activation starts before the first future original practice allocation")
		baseline.erase("conflict_floor")
		baseline.erase("practice_floor")
		runner.assert_eq(_canonical(baseline), _canonical(source.continuity.world.spirit_sources.qi_baselines[actor]), "new cost reconciliation retains the original qi provenance")
	var bad_legacy: Dictionary = source.duplicate(true)
	bad_legacy.continuity.world["conflicts"] = SimConflicts.empty_state()
	_reject(runtime, broken_path, bad_legacy, runner, "legacy envelope cannot smuggle an already-added modern conflict domain")
	var before_qi: int = int(world.regions.home.actors.player.qi)
	GameClock.advance_msec(int(original.due_ms) - GameClock.elapsed_ms)
	runner.assert_eq(int(world.regions.home.actors.player.qi), before_qi + 1, "original capacity-limited body channel completes without duplicate qi or combat costs")
	runner.assert_true(not world.spirit_sources.owns_actor("player"), "completed original source work releases the same player's body")
	runner.assert_eq(int(world.spirit_sources.sources.hearth_seam.spent), 6, "one original source batch is actually spent after migration")
	runner.assert_eq(int(world.spirit_sources.records[original.id].output), 1, "original capacity-limited receipt contains the actual accepted output")
	runner.assert_eq(int(world.spirit_sources.records[original.id].loss), 3, "original source conversion loss is preserved")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "completed migrated source has an independently valid current session candidate")
	return _canonical(snapshot)


func _workplace_continuation(runtime: WorldContinuityRuntime, source: Dictionary, broken_path: String, runner: Object) -> String:
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(WORKPLACE))
	runner.assert_eq(error, OK, "returned new game loads the real pre-conflict workplace exchange through the ordinary loader")
	if error != OK:
		return ""
	_assert_activation(runtime, source, runner, "workplace")
	var world: RegionalSimulation = runtime.world_sim
	runner.assert_eq(GameClock.elapsed_ms, 721000, "workplace archive resumes its actual fractional processing instant")
	for region: String in ["home", "river"]:
		runner.assert_eq(_canonical(world.regions[region].places), _canonical(source.continuity.world.regions[region].places), "saved room and public record carriers replace the previous live layout: " + region)
		runner.assert_true(world.regions[region].config.has("workplaces_version"), "real archived office remains enabled after migration: " + region)
	runner.assert_eq(_canonical(world.services.to_dict()), _canonical(source.continuity.world.services), "all actual pending exchange facts and private social history survive unchanged")
	var job_id: String = str(world.services.active_jobs.get("player", ""))
	runner.assert_true(not job_id.is_empty(), "actual reward processing still owns the original player")
	if job_id.is_empty():
		return ""
	var job: Dictionary = world.services.jobs[job_id]
	runner.assert_eq(job.kind, "redeem", "migration does not reinterpret original processing as a combat action")
	var home: VillageSimulation = world.regions.home
	var institution: String = str(home.config.institution.id)
	var credit: int = home.institutions.balance(institution, "player")
	var meals: int = home.inventory.quantity("actor:player", "meal")
	var forged: Dictionary = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.conflicts.next_hit_id = 2
	_reject(runtime, broken_path, forged, runner, "current envelope cannot add a missing conflict hit history")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.continuity.world.health.conflict_source_floor = 2
	_reject(runtime, broken_path, forged, runner, "new health source floor cannot skip genuine conflict provenance")
	forged = WorldSessionSnapshot.capture(runtime)
	forged.simulation.places.records.workspace.fixtures.register.institution = "private_notebook"
	forged.continuity.world.regions.home.places.records.workspace.fixtures.register.institution = "private_notebook"
	_reject(runtime, broken_path, forged, runner, "modern migration keeps actual public-record carrier authorization")
	GameClock.advance_msec(int(job.due_ms) - GameClock.elapsed_ms)
	runner.assert_eq(job.status, "completed", "original staffed reward completes at its saved actual due time")
	runner.assert_eq(home.institutions.balance(institution, "player"), credit - 1, "staffed processing spends one original contribution claim")
	runner.assert_eq(home.inventory.quantity("actor:player", "meal"), meals + 1, "same original player receives one actual stocked meal")
	runner.assert_true(not world.services.owns_actor("player"), "completed actual exchange releases its execution owner")
	GameClock.advance_msec(0)
	runner.assert_eq(home.institutions.balance(institution, "player"), credit - 1, "settling current time again does not repeat the contribution debit")
	runner.assert_eq(home.inventory.quantity("actor:player", "meal"), meals + 1, "settling current time again does not duplicate the actual reward")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "completed migrated workplace has an independently valid full session candidate")
	return _canonical(snapshot)


func _assert_activation(runtime: WorldContinuityRuntime, source: Dictionary, runner: Object, label: String) -> void:
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var world: RegionalSimulation = runtime.world_sim
	runner.assert_eq(int(snapshot.schema_version), SessionSaveSchema.VERSION, label + " explicitly upgrades root schema to the current version")
	runner.assert_eq(int(world.to_dict().version), RegionalSimulation.SCHEMA_VERSION, label + " explicitly upgrades regional schema to the current version")
	var empty_conflicts: Dictionary = SimConflicts.empty_state()
	empty_conflicts.perception_since_ms = world.elapsed_ms
	runner.assert_eq(_canonical(world.conflicts.to_dict()), _canonical(empty_conflicts), label + " adds an empty conflict history at the saved present rather than imagined past battles, teaching or sight")
	runner.assert_eq(_canonical(world.artifacts.objects), _canonical(source.continuity.world.artifacts.objects), label + " gains no weapon or duplicate item from the modern opening")
	runner.assert_true(not world.artifacts.objects.has("training_sword") and not world.artifacts.objects.has("river_training_sword"), label + " does not inherit new opening weapons across replacement")
	for method: String in ["sword", "qi_bolt", "qi_guard"]:
		runner.assert_true(not world.conflicts.knows("player", method), label + " grants no combat technique without actual learning: " + method)
	runner.assert_eq(int(world.health.to_dict().version), 2, label + " upgrades original health schema explicitly")
	runner.assert_eq(int(world.health.conflict_source_floor), 1, label + " does not suppress future sourced combat wounds")
	runner.assert_eq(_canonical(world.health.wounds), _canonical(source.continuity.world.health.wounds), label + " preserves old actual wounds without inventing contusions")
	runner.assert_eq(_canonical(world.health.jobs), _canonical(source.continuity.world.health.jobs), label + " preserves old medical actions")
	runner.assert_eq(_canonical(snapshot.simulation), _canonical(source.simulation), label + " changes no existing local bodies, stock, public claims, rooms or unfinished local work")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), label + " migrated present can be independently staged without rewriting facts")


func _reject(runtime: WorldContinuityRuntime, path: String, forged: Dictionary, runner: Object, label: String) -> void:
	var before: String = _canonical(WorldSessionSnapshot.capture(runtime))
	var live: RegionalSimulation = runtime.world_sim
	var terrain: WorldMapData = runtime.world_sim.map_data
	runner.assert_eq(SimSaveStore.save_file(path, forged), OK, label + " writes an ordinary readable but invalid candidate file")
	runner.assert_true(runtime.load_game(path) != OK, label + " is rejected by the ordinary loader")
	runner.assert_true(runtime.world_sim == live and runtime.world_sim.map_data == terrain, label + " preserves original live world and map owners")
	runner.assert_eq(_canonical(WorldSessionSnapshot.capture(runtime)), before, label + " cannot partly alter clock, player, pending jobs, claims or resources")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _remove(path: String) -> void:
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
