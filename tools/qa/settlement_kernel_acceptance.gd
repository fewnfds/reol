extends RefCounted
## On-demand native Main acceptance, with a real process stop between write
## and read. Logs and saves are local artifacts, never content dependencies.
const DIRECTORY: String = "res://logs/settlement_kernel_close_20261109"
var main: Node
var runtime: WorldContinuityRuntime
var clock: Node


func run(scene: Node, mode: String) -> Dictionary:
	main = scene
	runtime = main._continuity
	clock = main.get_node("/root/GameClock")
	clock.set_paused(true)
	if DisplayServer.get_name() == "headless":
		return {"ok": false, "reason": "native process required"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	if mode == "write":
		return await _write_case()
	if mode == "read":
		return await _read_case()
	if mode == "performance":
		return await _performance()
	if mode == "publication":
		return _publication()
	if mode == "publication_finish":
		return await _publication_finish()
	return {"ok": false, "reason": "unknown mode"}


func _publication() -> Dictionary:
	if runtime._opening_selection_available:
		runtime.select_starting_avatar("subject:player")
	runtime.settlement_work_budget = 2147483647
	for region: VillageSimulation in runtime.world_sim.regions.values():
		for actor: String in region.actors:
			region.actors[actor].autonomous = false
			region.cancel_action(actor, "publication_qa")
	var domain: SimConstruction = runtime.world_sim.construction
	var source: Vector2i = SimRouteTravel.cell(runtime.world_sim.regions.home.places[domain.definitions.site.source].cell)
	runtime.home_runtime()._player.spawn_at(source)
	var view: ConstructionRuntime = runtime.construction_adapter
	var registered: Dictionary = domain.register_site("player", view.find_yard_origin())
	if not registered.ok:
		return registered
	var placed: Dictionary = {"ok": false}
	for cell: Vector2i in SimConstruction.cells_in(domain.site_bounds(registered.site)):
		if SimMotionClearance.fixed_road_reserves(runtime.world_sim, cell) or domain.occupied(cell):
			continue
		placed = domain.place("player", "wood_wall", cell)
		if placed.ok:
			break
	if not placed.ok or not domain.begin("player", str(placed.project)).ok:
		return {"ok": false, "reason": "real construction start"}
	var id: String = placed.project
	for _attempt: int in 100:
		if domain.active.get("player", {}).get("phase") == "work":
			break
		clock.advance_msec(domain.next_boundary_ms() - clock.elapsed_ms)
	if domain.active.get("player", {}).get("phase") != "work":
		return {"ok": false, "reason": "real construction work phase"}
	clock.advance_msec(int(domain.active.player.due_ms) - clock.elapsed_ms - 1)
	view.show_panel()
	view.refresh_choices(id)
	view.refresh()
	view.refresh_committed_canvas()
	runtime.set_meta("qa_details", view._details.text)
	runtime.set_meta("qa_commands", view._canvas_commands.duplicate())
	runtime.set_meta("qa_project", id)
	runtime.settlement_work_budget = 1
	clock.advance_msec(1)
	for _attempt: int in 1000:
		if domain.projects[id].state == "built" and runtime.world_sim.settlement.is_pending():
			break
		clock._process(0.0)
	clock.set_paused(true)
	var result: Dictionary = {"ok": domain.projects[id].state == "built" and runtime.world_sim.settlement.is_pending(), "clock": clock.elapsed_ms, "world": runtime.world_sim.elapsed_ms, "held": runtime.world_sim.settlement.progress(), "details_held": view._details.text == runtime.get_meta("qa_details"), "canvas_held": view._canvas_commands == runtime.get_meta("qa_commands"), "project": id}
	_store("publication_partial", result)
	return result


func _publication_finish() -> Dictionary:
	var view: ConstructionRuntime = runtime.construction_adapter
	runtime.settlement_work_budget = 4096
	# This request was deliberately stopped by a fresh user-style pause.
	clock.set_paused(false)
	if not await _drain():
		return {"ok": false, "reason": "publication continuation"}
	clock.set_paused(true)
	await RenderingServer.frame_post_draw
	var result: Dictionary = {"ok": not runtime.world_sim.settlement.is_pending(), "at_ms": clock.elapsed_ms, "details_updated": view._details.text != runtime.get_meta("qa_details"), "canvas_updated": view._canvas_commands != runtime.get_meta("qa_commands"), "sight_flushed": view._pending_sight_cells.is_empty()}
	_store("publication_complete", result)
	return result


func _write_case() -> Dictionary:
	if runtime._opening_selection_available:
		runtime.select_starting_avatar("subject:player")
	# Keep the original world; no fixture goods or replacement bodies.
	if clock.has_pending_advance():
		clock.advance_msec(1)
		if not await _drain():
			return {"ok": false, "reason": "initial accepted interval"}
	var initial_path: String = ProjectSettings.globalize_path(DIRECTORY + "/initial.json")
	if runtime.save_game(initial_path) != OK:
		return {"ok": false, "reason": "initial save"}
	var start: int = clock.elapsed_ms
	runtime.settlement_work_budget = 1
	clock.advance_msec(200)
	var partial: bool = runtime.world_sim.settlement.is_pending() and clock.elapsed_ms == start and WorldSessionSnapshot.capture(runtime).is_empty()
	var held: Dictionary = runtime.world_sim.settlement.progress()
	if not partial or not await _drain():
		return {"ok": false, "reason": "native work-budget continuation", "progress": held}
	var limited: String = _hash()
	runtime.settlement_work_budget = 2147483647
	if runtime.load_game(initial_path) != OK:
		return {"ok": false, "reason": "original-owner rebind"}
	clock.advance_msec(200)
	if _hash() != limited:
		return {"ok": false, "reason": "limited and uninterrupted native future"}
	var checkpoint: String = _hash()
	if runtime.save_game(ProjectSettings.globalize_path(DIRECTORY + "/checkpoint.json")) != OK:
		return {"ok": false, "reason": "completed checkpoint"}
	clock.advance_msec(5000)
	var result: Dictionary = {"ok": true, "engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(), "checkpoint": checkpoint, "future": _hash(), "advance_ms": 5000, "limited_matches": true, "rejected_partial": partial, "held_stage": held.step}
	_store("expected", result)
	return result


func _read_case() -> Dictionary:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "/expected.json"))
	if not expected is Dictionary or runtime.load_game(ProjectSettings.globalize_path(DIRECTORY + "/checkpoint.json")) != OK:
		return {"ok": false, "reason": "independent checkpoint load"}
	var matched: bool = _hash() == expected.checkpoint
	runtime.settlement_work_budget = 2147483647
	clock.advance_msec(int(expected.advance_ms))
	var result: Dictionary = {"ok": matched and _hash() == expected.future, "checkpoint_matches": matched, "entire_future_matches": _hash() == expected.future, "at_ms": clock.elapsed_ms}
	_store("read", result)
	return result


func _performance() -> Dictionary:
	runtime.settlement_work_budget = 4096
	clock.set_paused(false)
	for _frame: int in 120:
		await RenderingServer.frame_post_draw
	var samples: Array[float] = []
	var start: int = clock.elapsed_ms
	var boundaries: int = int(runtime.world_sim.simulation_work.boundaries)
	var previous_us: int = Time.get_ticks_usec()
	for _frame: int in 600:
		await RenderingServer.frame_post_draw
		var now_us: int = Time.get_ticks_usec()
		samples.append(float(now_us - previous_us) / 1000.0)
		previous_us = now_us
	clock.set_paused(true)
	samples.sort()
	var result: Dictionary = {"ok": true, "frames": samples.size(), "renderer": RenderingServer.get_video_adapter_name(), "p95_frame_ms": samples[569], "p99_frame_ms": samples[593], "max_frame_ms": samples[-1], "min_frame_ms": samples[0], "simulated_ms": clock.elapsed_ms - start, "boundaries": int(runtime.world_sim.simulation_work.boundaries) - boundaries, "pending": runtime.world_sim.settlement.is_pending(), "scope": "ordinary opening, native Main, rendered frame intervals including pacing; no dense-world claim"}
	_store("performance", result)
	return result


func _drain() -> bool:
	for _frame: int in 2000:
		if not clock.has_pending_advance():
			return true
		clock._process(0.0)
		await main.get_tree().process_frame
	return false


func _hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime))).sha256_text()


func _store(label: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(DIRECTORY + "/" + label + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "\t", true, true))
