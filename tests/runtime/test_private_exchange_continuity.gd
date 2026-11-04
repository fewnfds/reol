extends RefCounted
## This immutable source is a real ordinary-play handover, not a staged wallet.

const ARCHIVE: String = "res://tests/fixtures/session_v42_exchange.json"
const SHA256: String = "e13c2616a25f482db2397b585417d027c2759172393c6929eb98a4713b676ebf"
const RING: String = "stele_drawing_ring"


func run(runner: Object) -> void:
	var clock: Dictionary = GameClock.to_dict()
	GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	var runtime: WorldContinuityRuntime = main._continuity
	var helper: RefCounted = load("res://tests/runtime/helpers/private_exchange_replay.gd").new()
	for cancel: bool in [false, true]:
		var first: String = ""
		for attempt: int in 2:
			runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SHA256, "continuation starts from the immutable actual v42 handover")
			var loaded: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
			runner.assert_eq(loaded, OK, "ordinary joint loader restores the real midpoint")
			if loaded != OK:
				continue
			var world: RegionalSimulation = runtime.world_sim
			runner.assert_eq(GameClock.elapsed_ms, 551887, "actual midpoint keeps its exact common instant")
			runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "coin"), 6, "midpoint has not paid the original six coins")
			runner.assert_eq(world.regions.home.inventory.available("actor:player", "coin"), 2, "midpoint reserves exactly the original four-coin quote")
			runner.assert_eq(world.artifacts.objects[RING].container, "actor:river_shi_tou", "midpoint keeps the one original ring with the seller")
			var branch: String = "cancel" if cancel else "complete"
			var suffix: String = "ci_%s_%d" % [branch, attempt]
			var reply: Dictionary = helper.replay_exchange(runtime, suffix, cancel, ARCHIVE)
			runner.assert_true(bool(reply.get("ok", false)), "actual handover continues through ordinary commands: " + str(reply.get("error", "")))
			if not bool(reply.get("ok", false)):
				continue
			world = runtime.world_sim
			var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
			var future: String = SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))
			runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "actual complete future remains a valid independent candidate")
			if attempt == 0:
				first = future
			else:
				runner.assert_eq(future, first, "independent ordinary loads produce identical complete future for " + branch)
			runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "coin"), 6 if cancel else 2, "only delivered handover charges the original quote")
			runner.assert_eq(world.artifacts.objects[RING].container, "actor:river_shi_tou" if cancel else "actor:player", "cancel/completion preserves the same unique ring's real custody")
			runner.assert_eq(world.artifacts.objects.training_sword.container, "dorm" if cancel else "actor:player", "only the actual buyer's later research and draw acquire the original sword")
			for path: String in [str(reply.full_snapshot), "res://logs/private_exchange_restart_%s.json" % suffix]:
				for ending: String in ["", ".bak", ".tmp", ".bak.tmp"]:
					if FileAccess.file_exists(path + ending):
						DirAccess.remove_absolute(ProjectSettings.globalize_path(path + ending))
			runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SHA256, "no replay or failed candidate rewrites the genuine archive")
	main.free()
	GameClock.restore_state(clock)
	print("SCENARIO private exchange continuity: immutable ordinary handover, original-loader completion/cancellation, personal research and original sword, identical joint futures")
