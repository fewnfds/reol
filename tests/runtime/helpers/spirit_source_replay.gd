extends RefCounted
## Ordinary intentions after the genuine in-progress source archive.
## No position, knowledge, resource or NPC-policy injection.

const ARCHIVE: String = "res://tests/fixtures/session_v34.json"
const FUTURE_MS: int = 7200000


func run(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	if suffix not in ["a", "b"]:
		return {"error": "invalid evidence suffix"}
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	if error != OK:
		return {"load_error": error}
	var world: RegionalSimulation = runtime.world_sim
	var source: SimSpiritSources = world.spirit_sources
	var original: Dictionary = source.active.get("player", {}).duplicate(true)
	if original.is_empty() or original.target != "body":
		return {"error": "archive has no original body-channel action"}
	var actor: Dictionary = world.regions.home.actors.player
	var object: String = str(original.object)
	var report: Dictionary = {"source_ms": GameClock.elapsed_ms, "original": original,
		"source_qi": int(actor.qi), "source_stock": source.sources.duplicate(true)}
	GameClock.advance_msec(int(original.due_ms) - GameClock.elapsed_ms)
	report["completed"] = {"ms": GameClock.elapsed_ms, "qi": int(actor.qi), "sources": source.sources.duplicate(true), "records": source.records.duplicate(true)}
	if source.owns_actor("player"):
		return {"error": "original channel did not complete", "report": report}
	if world.artifacts.objects[object].container != "actor:player":
		if not _artifact(runtime, "take", object):
			return {"error": "ordinary take failed", "report": report}
	for verb: String in ["charge", "warm"]:
		if not _artifact(runtime, verb, object):
			return {"error": "ordinary artifact use failed", "verb": verb, "report": report}
	report["after_body_use"] = {"qi": int(actor.qi), "charge": int(world.artifacts.objects[object].charge), "heat": world.environment_fields.input_energy}
	var stored: Dictionary = source.begin("player", str(original.source), "stone", object)
	if not bool(stored.ok):
		return {"error": "ordinary source storage failed", "reply": stored, "report": report}
	runtime.hold_player_motion(true)
	GameClock.advance_msec(int(source.active.player.due_ms) - GameClock.elapsed_ms)
	if source.owns_actor("player") or not _artifact(runtime, "warm", object):
		return {"error": "stored source did not feed original warmth", "report": report}
	report["after_stone_use"] = {"qi": int(actor.qi), "charge": int(world.artifacts.objects[object].charge), "heat": world.environment_fields.input_energy, "sources": source.sources.duplicate(true)}
	report["journey_accepted"] = runtime.travel_to("river")
	if not report.journey_accepted or GameClock.elapsed_ms > FUTURE_MS:
		return {"error": "ordinary departure failed", "report": report}
	GameClock.advance_msec(FUTURE_MS - GameClock.elapsed_ms)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var canonical: String = JSON.stringify(VillageRuntime._json_normalized(snapshot), "", true, true)
	var path: String = "res://logs/spirit_source_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return {"write_error": FileAccess.get_open_error()}
	file.store_string(canonical)
	file.close()
	report.merge({"ms": GameClock.elapsed_ms, "region": runtime.current_region, "journey": runtime.player_journey.duplicate(true),
		"qi": int(actor.qi), "charge": int(world.artifacts.objects[object].charge), "bytes": canonical.to_utf8_buffer().size(),
		"sha256": FileAccess.get_sha256(path), "candidate_valid": not WorldSessionSnapshot.stage(runtime, snapshot).is_empty()})
	var evidence := FileAccess.open("res://logs/spirit_source_restart_%s.json" % suffix, FileAccess.WRITE)
	if evidence != null:
		evidence.store_string(JSON.stringify(report, "\t", true, true))
		evidence.close()
	return report


func _artifact(runtime: WorldContinuityRuntime, verb: String, object: String) -> bool:
	var domain: SimArtifacts = runtime.world_sim.artifacts
	runtime.prepare_player_command()
	var reply: Dictionary = domain.begin("player", verb, object)
	if not bool(reply.ok):
		return false
	runtime.hold_player_motion()
	GameClock.advance_msec(int(domain.active.player.due_ms) - GameClock.elapsed_ms)
	return not domain.owns_actor("player") and str(domain.events.back().kind) in ["taken", "charged", "warmed"]
