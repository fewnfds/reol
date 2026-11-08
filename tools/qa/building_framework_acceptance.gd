extends RefCounted
## On-demand native Main acceptance; no permanent test registration. Run write,
## stop the game process, then run read in a new process. Existing coin stock
## exercises the ordinary container UI without issuing any test goods.
const DIRECTORY: String = "res://logs/building_framework"
var main: Node
var runtime: WorldContinuityRuntime
var clock: Node
var evidence: Dictionary = {}


func run(scene: Node, mode: String) -> Dictionary:
	main = scene
	runtime = main._continuity
	clock = main.get_node("/root/GameClock")
	clock.set_paused(true)
	if DisplayServer.get_name() == "headless" or mode not in ["write", "read"]:
		return {"ok": false, "reason": "native write/read required"}
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	if mode == "read": return await _read()
	if runtime._opening_selection_available:
		runtime.select_starting_avatar("subject:player")
	clock.set_paused(true)
	for sim: VillageSimulation in runtime.world_sim.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "acceptance_setup")
			sim.actors[actor].autonomous = false
	var source: Vector2i = SimRouteTravel.cell(runtime.world_sim.regions.home.places.store.cell)
	runtime._home._player.spawn_at(source)
	runtime.prepare_player_command()
	var ui: ConstructionRuntime = runtime.construction_adapter
	ui.show_panel()
	ui.register_yard()
	var domain: SimConstruction = runtime.world_sim.construction
	if domain.sites.is_empty(): return _failure("ordinary yard registration")
	var bounds: Rect2i = domain.site_bounds()
	var origin := Vector2i(-1, -1)
	for cell: Vector2i in SimConstruction.cells_in(bounds):
		if not bounds.has_point(cell + Vector2i(0, 2)): continue
		var clear: bool = true
		for offset: int in 3:
			clear = clear and not domain.occupied(cell + Vector2i(0, offset)) and not SimMotionClearance.fixed_road_reserves(runtime.world_sim, cell + Vector2i(0, offset))
		if clear:
			origin = cell
			break
	if origin.x < 0: return _failure("three clear ordinary furniture cells")
	var table: String = _place(ui, "wood_table", origin, 1)
	ui.act("build")
	if not _advance_to_phase("construction", "work"): return _failure("table material/work arrival")
	clock.advance_msec(1234)
	if not await _checkpoint("construction"): return _failure("table checkpoint")
	if domain.projects[table].state != "built": return _failure("multi-cell table completion")
	var hits: Dictionary = runtime.world_sim.query_space(Rect2i(origin, Vector2i(1, 2)), ["construction"], "ground")
	if not bool(hits.ok) or hits.references != [{"kind": "construction", "id": table}]: return _failure("one multi-cell native instance")
	var chair: String = _place(ui, "desk_chair", origin + Vector2i(0, 2), 0)
	ui.act("build")
	if not _finish_construction(chair): return _failure("chair completion")
	ui.select_cell(origin + Vector2i(0, 2))
	ui.use_facility("sit")
	if not _advance_to_phase("facility_use", "use"): return _failure("real seat arrival")
	if not await _checkpoint("seat"): return _failure("seat checkpoint")
	var chest_cell := Vector2i(-1, -1)
	for cell: Vector2i in SimConstruction.cells_in(bounds):
		if domain.project_at(cell).is_empty() and domain.project_at(cell + Vector2i.DOWN).is_empty() and domain.terrain_open(cell + Vector2i.DOWN) and not domain.occupied(cell) and not SimMotionClearance.fixed_road_reserves(runtime.world_sim, cell):
			chest_cell = cell
			break
	if chest_cell.x < 0: return _failure("ordinary chest footprint")
	var chest: String = _place(ui, "wood_chest", chest_cell, 0)
	ui.act("build")
	if not _finish_construction(chest): return _failure("chest completion")
	ui.select_cell(chest_cell)
	for index: int in ui.item_choice.item_count:
		if ui.item_choice.get_item_metadata(index) == "coin": ui.item_choice.select(index)
	ui.amount_choice.value = 2
	var original: int = runtime.world_sim.regions.home.inventory.quantity("actor:player", "coin")
	ui.use_facility("deposit")
	if not _advance_to_phase("facility_use", "use"): return _failure("ordinary deposit arrival")
	if not await _checkpoint("deposit"): return _failure("deposit checkpoint")
	if runtime.world_sim.regions.home.inventory.quantity("actor:player", "coin") != original - 2 or runtime.world_sim.regions.home.inventory.quantity(chest + ":contents", "coin") != 2:
		return _failure("original coins conserved")
	evidence["ok"] = true
	evidence["engine"] = Engine.get_version_info().string
	evidence["renderer"] = RenderingServer.get_video_adapter_name()
	evidence["instances"] = {"table": table, "chair": chair, "chest": chest}
	_write("expected", evidence)
	return evidence


func _place(ui: ConstructionRuntime, type: String, cell: Vector2i, rotation: int) -> String:
	for index: int in ui.type_choice.item_count:
		if ui.type_choice.get_item_metadata(index) == type: ui.type_choice.select(index)
	ui.rotation_choice.select(rotation)
	ui.select_cell(cell)
	ui.place_selected()
	return ui.selected_project()


func _advance_to_phase(domain_name: String, phase: String) -> bool:
	var domain: RefCounted = runtime.world_sim.get(domain_name)
	for _step: int in 200:
		if not domain.active.has("player"): return false
		if domain.active.player.phase == phase: return true
		clock.advance_msec(maxi(1, domain.next_boundary_ms() - runtime.world_sim.elapsed_ms))
	return false


func _finish_construction(id: String) -> bool:
	for _step: int in 200:
		var domain: SimConstruction = runtime.world_sim.construction
		if not domain.active.has("player"): return domain.projects.get(id, {}).get("state") == "built"
		clock.advance_msec(maxi(1, domain.next_boundary_ms() - runtime.world_sim.elapsed_ms))
	return false


func _checkpoint(label: String) -> bool:
	var job: Dictionary = runtime.world_sim.describe_actor_action("player")
	if not job.get("ok", false): return false
	var before: String = _hash()
	if runtime.save_game(ProjectSettings.globalize_path(DIRECTORY + "/" + label + ".json")) != OK: return false
	await _capture(label + "_pending")
	var delta: int = int(job.due_ms) - runtime.world_sim.elapsed_ms + 1
	clock.advance_msec(delta)
	if clock.has_pending_advance(): return false
	evidence[label] = {"checkpoint": before, "future": _hash(), "advance_ms": delta, "due_ms": int(job.due_ms)}
	await _capture(label + "_finished")
	return true


func _read() -> Dictionary:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "/expected.json"))
	if not expected is Dictionary: return _failure("missing write evidence")
	var result: Dictionary = {"ok": true, "cases": {}}
	for label: String in ["construction", "seat", "deposit"]:
		if runtime.load_game(ProjectSettings.globalize_path(DIRECTORY + "/" + label + ".json")) != OK or _hash() != expected[label].checkpoint:
			return _failure(label + " independent checkpoint")
		var job: Dictionary = runtime.world_sim.describe_actor_action("player")
		if not job.get("ok", false) or int(job.due_ms) != int(expected[label].due_ms): return _failure(label + " deadline")
		clock.advance_msec(int(expected[label].advance_ms))
		if _hash() != expected[label].future: return _failure(label + " entire future")
		result.cases[label] = {"checkpoint_matches": true, "entire_future_matches": true, "due_ms": int(job.due_ms)}
		await _capture(label + "_restarted")
	_write("read", result)
	return result


func _hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime))).sha256_text()


func _capture(label: String) -> void:
	runtime.construction_adapter.show_panel()
	for _frame: int in 4: await main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	main.get_viewport().get_texture().get_image().save_png(DIRECTORY + "/" + label + ".png")


func _write(label: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(DIRECTORY + "/" + label + ".json", FileAccess.WRITE)
	if file != null: file.store_string(JSON.stringify(value, "\t", true, true))


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
