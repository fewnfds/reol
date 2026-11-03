extends SceneTree
## Actual ordinary opening/route probes; all game-dependent classes load late.


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var main: Node = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	var runtime: Node = main._continuity
	var helper: RefCounted = load("res://tests/runtime/helpers/field_replay.gd").new()
	var selected: Array = OS.get_cmdline_user_args()
	var mode: String = str(selected[0]) if not selected.is_empty() else "trip"
	var answer: Dictionary = helper.prepare_npc(runtime) if mode == "npc" else helper.prepare_trip(runtime)
	print("FIELD PREPARE ", mode, " ", answer)
	if not bool(answer.get("ok", false)):
		quit(1)
		return
	answer = helper.replay_npc(runtime, "probe_npc") if mode == "npc" else helper.replay_trip(runtime, "probe_trip")
	print("FIELD FUTURE ", mode, " ", answer)
	quit(0 if bool(answer.get("ok", false)) else 1)
