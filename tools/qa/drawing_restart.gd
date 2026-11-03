extends SceneTree
## A fresh OS process per run; no dependence on a previous runtime singleton.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var clock: Node = root.get_node("GameClock")
	clock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true})
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	var runtime: Node = main._continuity
	var helper: RefCounted = load("res://tests/runtime/helpers/drawing_replay.gd").new()
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 2 or args[0] not in ["prepare", "replay"] or not args[1].is_valid_identifier():
		printerr("DRAWING RESTART expects prepare|replay and suffix")
		quit(1)
		return
	var result: Dictionary
	if args[0] == "prepare":
		result = helper.prepare_research(runtime)
		print("DRAWING RESTART research ", result)
		if bool(result.get("ok", false)):
			result = helper.prepare_draw(runtime)
			print("DRAWING RESTART draw ", result)
	else:
		for kind: String in ["research", "draw", "cancel"]:
			if kind == "research":
				result = helper.replay_research(runtime, args[1] + "_" + kind, "res://tests/fixtures/session_v41_research.json")
			else:
				result = helper.replay_draw(runtime, args[1] + "_" + kind, kind == "cancel", "res://tests/fixtures/session_v41_draw.json")
			print("DRAWING RESTART ", kind, " ", result)
			if not bool(result.get("ok", false)):
				break
	quit(0 if bool(result.get("ok", false)) else 1)
