extends SceneTree
## Development-only full world opening. Uses real NPC bodies, original native
## work, pathfinding, fields and shared-clock recorder; never writes a save.

var _main: Node
var _recorder: Node
var _clock: Node
var _quit_after: bool = false
var _report: String = "res://logs/crowd-stress.json"
var _seconds: int = 30
var _revision: String = "unknown"
var _failures: Array[String] = []
var _moved: Dictionary = {}
var _starts: Dictionary = {}
var _status: Label
var _opening_wave: bool = false
var _orders: Dictionary = {}
var _legs: Dictionary = {}
var _last_sample_ms: int = 0
var _travel_actor_ms: int = 0
var _sampled_world_ms: int = 0
var _last_travelling: int = 0
var _redirects: int = 0
var _actor_workers: int = 4
const CIRCUIT: Array[String] = ["rest", "inspect", "check_store", "check_well"]


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var assembly_started: int = Time.get_ticks_usec()
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--seconds="):
			_seconds = clampi(argument.get_slice("=", 1).to_int(), 5, 300)
		elif argument.begins_with("--report="):
			_report = argument.trim_prefix("--report=")
		elif argument.begins_with("--revision="):
			_revision = argument.trim_prefix("--revision=")
		elif argument == "--quit-after-capture":
			_quit_after = true
		elif argument == "--opening-wave":
			_opening_wave = true
		elif argument.begins_with("--actor-workers="):
			_actor_workers = clampi(argument.get_slice("=", 1).to_int(), 0, 8)
	_main = load("res://scenes/main.tscn").instantiate()
	_main.set_script(load("res://tools/diagnostics/crowd_scene.gd"))
	root.add_child(_main)
	current_scene = _main
	_clock = root.get_node("GameClock")
	var runtime: Node = _main.get("_continuity")
	if runtime == null or runtime.world_sim == null or not runtime.avatar_adapter.choose("subject:player"):
		push_error("Stress opening could not assemble the ordinary world")
		quit(1)
		return
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		sim.configure_actor_execution(_actor_workers)
	# Original save hotkeys/panels must not overwrite an ordinary player slot.
	runtime.home_runtime().set_process_unhandled_key_input(false)
	for panel: Control in [runtime._panel, _main._village._panel, runtime.service_adapter.panel, _main.hud._pawn_panel]:
		# Ordinary refresh callbacks may show their panel again. A hidden parent
		# keeps this temporary demo's viewport clear without changing those APIs.
		var holder := Control.new()
		panel.get_parent().add_child(holder)
		holder.hide()
		panel.reparent(holder)
	for adapter: Node in [runtime.avatar_adapter, runtime.avatar_adapter.soul]:
		adapter.set_process_unhandled_input(false)
	var layer := CanvasLayer.new()
	root.add_child(layer)
	layer.layer = 100
	_status = Label.new()
	layer.add_child(_status)
	_status.position = Vector2(16, 146)
	_status.add_theme_font_size_override("font_size", 16)
	root.title = "Reol / temporary full-world crowd stress / no ordinary saves"
	_clock.set_paused(true)
	# Let terrain loading settle before measuring steady play, not before CPU
	# assembly. The wrapper's finite process timeout covers this warmup too.
	var until: int = Time.get_ticks_msec() + 15000
	while (not _main.world._pending_load.is_empty() or _main.world._painting_chunk.x >= 0) and Time.get_ticks_msec() < until:
		await process_frame
	if not _opening_wave:
		# One opening placement of the observer at the real gathering point lets
		# this demo exercise visible crowd rendering too. NPCs never teleport.
		var home: VillageSimulation = runtime.world_sim.regions.home
		var at: Vector2i = SimRouteTravel.cell(home.places.dorm.cell)
		home.set_actor_cell("player", at)
		_main.player.spawn_at(at)
		runtime.world_sim.invalidate_region("home")
		_main.fog.set_focus(at)
		_main.fog.update_now()
		_main.camera.global_position = TileGrid.cell_to_world(at)
	var total: int = 0
	for region: String in runtime.world_sim.regions:
		var sim: VillageSimulation = runtime.world_sim.regions[region]
		for id: String in sim.synchronize_actors():
			total += 1
			_starts[id] = sim.actor_position(sim.synchronize_actors()[id])
			if id != "player":
				_legs[id] = 0
				if sim.submit_action(id, CIRCUIT[0]):
					_orders[id] = str(sim.synchronize_actors()[id].active.id)
		runtime.world_sim.invalidate_region(region)
	_recorder = load("res://tools/diagnostics/demo_recorder.gd").new()
	root.add_child(_recorder)
	_recorder.finished.connect(_finish)
	if not _recorder.configure(_main, {"seconds": _seconds, "report": _report, "revision": _revision, "dirty": true, "assembly_usec": Time.get_ticks_usec() - assembly_started}):
		quit(1)
		return
	_status.text = "临时压力世界 · %d个真实身体 / 双聚落\n原寻路、生活、环境、共同时间 · %s\n不保存到普通档 · WASD / F3 · %d秒采样后%s" % [total, "单次出发" if _opening_wave else "抵达后用原命令持续巡行", _seconds, "退出" if _quit_after else "可继续试玩"]
	_clock.set_paused(false)
	process_frame.connect(_sample)


func _sample() -> void:
	var runtime: Node = _main.get("_continuity")
	var world: RegionalSimulation = runtime.world_sim
	if not world.accepts_commands() or int(_clock.elapsed_ms) == _last_sample_ms:
		return
	var span: int = int(_clock.elapsed_ms) - _last_sample_ms
	_sampled_world_ms += span
	_travel_actor_ms += _last_travelling * span
	_last_sample_ms = int(_clock.elapsed_ms)
	_last_travelling = 0
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		for id: String in sim.actors:
			if not _moved.has(id) and _starts.has(id) and sim.projected_actor_position(id) != _starts[id]:
				_moved[id] = true
			var person: Dictionary = sim.actor_state(id)
			if not _opening_wave and _legs.has(id) and bool(person.alive):
				# Redirect only our own arrived order, through original cancellation
				# and submission. Never teleport or replace a domain-owned process.
				if person.active.get("id", "") == _orders.get(id, "") and person.active.get("phase") == "work":
					sim.cancel_action(id, "stress_circuit")
					world.invalidate_region(world.clothing.home(id), id)
					_legs[id] = (int(_legs[id]) + 1) % CIRCUIT.size()
					_redirects += 1
				if person.active.is_empty() and sim.submit_action(id, CIRCUIT[int(_legs[id])]):
					_orders[id] = str(person.active.id)
					world.invalidate_region(world.clothing.home(id), id)
			if person.active.get("phase") == "travel":
				_last_travelling += 1


func _finish(ok: bool) -> void:
	process_frame.disconnect(_sample)
	# Capture after timing ends so the GPU readback is not a gameplay spike.
	if DisplayServer.get_name() != "headless":
		root.get_texture().get_image().save_png(_report.trim_suffix(".json") + ".png")
	var visible: int = 1 if _main.player.is_visible_in_tree() else 0
	for pawn: Node2D in _main._village._pawns.values():
		if pawn.is_visible_in_tree():
			visible += 1
	for pawn: Node2D in _main._continuity._remote_views.values():
		if pawn.is_visible_in_tree():
			visible += 1
	var crowd: Dictionary = {"actors": _starts.size(), "moved": _moved.size(), "mode": "opening_wave" if _opening_wave else "sustained_circuit", "mean_travelling": float(_travel_actor_ms) / maxi(1, _sampled_world_ms), "visible_at_finish": visible, "redirects": _redirects}
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(_report))
	if not raw is Dictionary:
		push_error("Crowd recorder did not write a valid report")
		_main.free()
		quit(1)
		return
	var report: Dictionary = raw
	report["crowd"] = crowd
	var file := FileAccess.open(_report, FileAccess.WRITE)
	if file == null:
		_failures.append("Could not append workload evidence to the report")
	else:
		file.store_string(JSON.stringify(report, "\t", true))
		file.close()
	print("CROWD_STRESS ", JSON.stringify(crowd), " ok=", ok, " report=", _report)
	if _moved.size() < _starts.size() / 2:
		_failures.append("Too few original NPCs actually moved; this is not a valid movement load")
	if not _failures.is_empty():
		push_error(str(_failures))
	if _quit_after or not ok or not _failures.is_empty():
		_main.free()
		quit(0 if ok and _failures.is_empty() else 1)
	elif not _opening_wave:
		# Keep the same circuit playable after recording stops.
		process_frame.connect(_sample)
