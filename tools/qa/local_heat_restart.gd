extends RefCounted
## Run through the existing loader and shared clock in two fresh game processes.
## This probe never injects heat, resources, positions or NPC decisions.


func run(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	if not suffix in ["a", "b"]:
		return {"error": "unknown evidence suffix"}
	var error: Error = runtime.load_game(ProjectSettings.globalize_path("res://tests/fixtures/session_v32.json"))
	if error != OK:
		return {"load_error": error}
	var world: RegionalSimulation = runtime.world_sim
	var report: Dictionary = {"source_ms": GameClock.elapsed_ms, "source_charge": world.artifacts.objects.hearth_stone.charge,
		"source_job": world.artifacts.active.get("player", {}).duplicate(true)}
	GameClock.advance_msec(840050 - GameClock.elapsed_ms)
	report["completed"] = {"ms": GameClock.elapsed_ms, "charge": world.artifacts.objects.hearth_stone.charge,
		"input": world.environment_fields.input_energy, "heat": world.environment_fields.local_tenths(Vector2i(254, 255)),
		"old_sample_heat": world.environment.samples.player.heat_tenths}
	GameClock.advance_msec(10000)
	report["after_exchange"] = {"loss": world.environment_fields.loss_energy, "heat": world.environment_fields.local_tenths(Vector2i(254, 255))}
	report["journey_accepted"] = runtime.travel_to("river")
	GameClock.advance_msec(977431 - GameClock.elapsed_ms)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var canonical: String = JSON.stringify(VillageRuntime._json_normalized(snapshot), "", true, true)
	var path: String = "res://logs/local_heat_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"write_error": FileAccess.get_open_error()}
	file.store_string(canonical)
	file.close()
	report.merge({"ms": GameClock.elapsed_ms, "region": runtime.current_region,
		"cell": [runtime._home._player.cell.x, runtime._home._player.cell.y],
		"charge": world.artifacts.objects.hearth_stone.charge,
		"input": world.environment_fields.input_energy, "loss": world.environment_fields.loss_energy,
		"receipts": world.environment_fields.receipts.size(), "characters": canonical.length(),
		"bytes": canonical.to_utf8_buffer().size(), "hash": canonical.hash(),
		"sha256": FileAccess.get_sha256(path)})
	var evidence := FileAccess.open("res://logs/local_heat_restart_%s.json" % suffix, FileAccess.WRITE)
	if evidence != null:
		evidence.store_string(JSON.stringify(report, "\t", true, true))
		evidence.close()
	return report
