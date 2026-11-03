extends RefCounted
## Replays ordinary intentions after the genuine clicked irrigation archive.
## No injection of positions, stock, ecology, NPC policy or resources.

const ARCHIVE: String = "res://tests/fixtures/session_v33.json"
const SOURCE_MS: int = 1333120
const COMPLETE_MS: int = 1423120
const FUTURE_MS: int = 7200000


func run(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	if suffix not in ["a", "b"]:
		return {"error": "invalid evidence suffix"}
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	if error != OK:
		return {"load_error": error}
	var world: RegionalSimulation = runtime.world_sim
	var sim: VillageSimulation = world.regions.home
	var report: Dictionary = {"source_ms": GameClock.elapsed_ms, "source_water": sim.inventory.quantity("actor:player", "water"),
		"source_action": sim.actors.player.active.duplicate(true)}
	if GameClock.elapsed_ms != SOURCE_MS or sim.actors.player.active.get("action") != "irrigate_herb":
		return {"error": "unexpected original action"}
	GameClock.advance_msec(COMPLETE_MS - GameClock.elapsed_ms)
	report["completed"] = {"ms": GameClock.elapsed_ms, "water": sim.inventory.quantity("actor:player", "water"),
		"soil": sim.land_resources.sources.herb_slope.ecology.duplicate(true), "active": sim.actors.player.active.duplicate(true)}
	for action: String in ["keep_herb", "keep_wood"]:
		var reply: Dictionary = runtime.service_adapter.submit("work:" + action)
		report[action] = reply.duplicate(true)
		if not reply.ok or not _finish_native(sim, 1800000):
			return {"error": "ordinary work failed", "action": action, "report": report}
		report[action]["ms"] = GameClock.elapsed_ms
		report[action]["bag"] = sim.inventory.containers["actor:player"].duplicate(true)
	var created: Dictionary = world.personal_production.create("player", "home", "dry_herbs")
	report["production"] = created.duplicate(true)
	if not created.ok or not _finish_production(world, 1800000):
		return {"error": "ordinary drying failed", "report": report}
	var batch: String = str(created.batch)
	var collected: Dictionary = world.personal_production.begin("player", batch, "collect")
	if not collected.ok or not _finish_production(world, 600000):
		return {"error": "ordinary collection failed", "report": report}
	report["collected"] = {"ms": GameClock.elapsed_ms, "bag": sim.inventory.containers["actor:player"].duplicate(true)}
	report["journey_accepted"] = runtime.travel_to("river")
	if GameClock.elapsed_ms > FUTURE_MS:
		return {"error": "unexpected future overrun", "report": report}
	GameClock.advance_msec(FUTURE_MS - GameClock.elapsed_ms)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var canonical: String = JSON.stringify(VillageRuntime._json_normalized(snapshot), "", true, true)
	var path: String = "res://logs/herb_ecology_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"write_error": FileAccess.get_open_error()}
	file.store_string(canonical)
	file.close()
	report.merge({"ms": GameClock.elapsed_ms, "region": runtime.current_region, "journey": runtime.player_journey.duplicate(true),
		"bag": sim.inventory.containers["actor:player"].duplicate(true), "herb_source": sim.land_resources.sources.herb_slope.duplicate(true),
		"bytes": canonical.to_utf8_buffer().size(), "sha256": FileAccess.get_sha256(path),
		"candidate_valid": not WorldSessionSnapshot.stage(runtime, snapshot).is_empty()})
	var evidence := FileAccess.open("res://logs/herb_ecology_restart_%s.json" % suffix, FileAccess.WRITE)
	if evidence != null:
		evidence.store_string(JSON.stringify(report, "\t", true, true))
		evidence.close()
	return report


func _finish_native(sim: VillageSimulation, duration: int) -> bool:
	var stop: int = GameClock.elapsed_ms + duration
	while not sim.actors.player.active.is_empty() and GameClock.elapsed_ms < stop:
		GameClock.advance_msec(mini(60000, stop - GameClock.elapsed_ms))
	return sim.actors.player.active.is_empty()


func _finish_production(world: RegionalSimulation, duration: int) -> bool:
	var stop: int = GameClock.elapsed_ms + duration
	while world.personal_production.active.has("player") and GameClock.elapsed_ms < stop:
		GameClock.advance_msec(mini(60000, stop - GameClock.elapsed_ms))
	return not world.personal_production.active.has("player")
