extends RefCounted
## On-demand native Main acceptance. Invoke run(current_scene, "write"), stop
## the game process completely, then invoke "read" in a fresh Main process.
## Uses the ordinary developer adapter and player commands; no test registry.

const DIRECTORY: String = "res://logs/world_space_stage1"
var _main: Node
var _runtime: WorldContinuityRuntime
var _clock: Node
var _evidence: Dictionary = {}


func run(main: Node, mode: String) -> Dictionary:
	if mode not in ["write", "read"] or DisplayServer.get_name() == "headless":
		return _failed("expected native write/read")
	_main = main
	_runtime = main._continuity
	_clock = main.get_node("/root/GameClock")
	_clock.set_paused(true)
	if _runtime._opening_selection_available and not _runtime.select_starting_avatar("subject:player"):
		return _failed("ordinary avatar selection")
	_clock.set_paused(true)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DIRECTORY))
	if mode == "read":
		return await _read()
	var handling: Dictionary = await _handling()
	if not bool(handling.ok):
		return handling
	var construction: Dictionary = await _construction()
	if not bool(construction.ok):
		return construction
	_evidence["ok"] = true
	_evidence["engine"] = Engine.get_version_info().string
	_evidence["display"] = DisplayServer.get_name()
	_write_json("expected", _evidence)
	return _evidence


func _handling() -> Dictionary:
	var editor := TerrainEditorRuntime.new()
	_main.add_child(editor)
	editor.setup(_runtime)
	var prepared: Dictionary = editor.prepare()
	if not bool(prepared.ok):
		return _failed("developer preparation: " + str(prepared))
	var world: RegionalSimulation = _runtime.world_sim
	var origin: Vector2i = _runtime.controlled_cell()
	var target := Vector2i(-1, -1)
	for offset: Vector2i in [Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN, Vector2i.LEFT]:
		var candidate: Vector2i = origin + offset
		if world.object_lifecycle.ground.can_place("home", candidate, Vector2i(2, 1)).ok and _main.fog.is_cell_visible(candidate) and SimConflictSpace.clear_segment(world, TileGrid.cell_to_world(origin), TileGrid.cell_to_world(candidate), 0):
			target = candidate
			break
	if target.x < 0:
		return _failed("nearby ordinary two-cell placement")
	var created: Dictionary = editor.place_object("stone_slab", target)
	if not bool(created.ok):
		return _failed("ordinary developer placement: " + str(created))
	var id: String = created.reference.id
	# The ordinary removal consumer now queries the common space. Exercise its
	# non-anchor selection with a second independently placed original.
	var removable := Vector2i(-1, -1)
	for y: int in range(origin.y - 4, origin.y + 5):
		for x: int in range(origin.x - 4, origin.x + 5):
			var candidate := Vector2i(x, y)
			if world.object_lifecycle.ground.can_place("home", candidate, Vector2i(2, 1)).ok:
				removable = candidate
				break
		if removable.x >= 0:
			break
	var extra: Dictionary = editor.place_object("stone_slab", removable)
	if not bool(extra.ok) or not bool(editor.remove_object(removable + Vector2i.RIGHT).get("ok", false)) or world.artifacts.objects.has(extra.reference.id):
		return _failed("ordinary non-anchor removal")
	var hits: Dictionary = world.query_space(Rect2i(target, Vector2i(2, 1)), ["artifact"], "ground")
	if not bool(hits.ok) or hits.references != [created.reference]:
		return _failed("live original two-cell query")
	var start: int = Time.get_ticks_usec()
	var work: int = 0
	for _sample: int in 1000:
		var sample: Dictionary = world.query_space(Rect2i(target, Vector2i(2, 1)), ["artifact"], "ground")
		if not bool(sample.ok):
			return _failed("bounded repeated query")
		work += int(sample.work_used)
	_evidence["query_sample"] = {"queries": 1000, "elapsed_usec": Time.get_ticks_usec() - start, "work_used": work, "map_cells": 512 * 512, "scope": "native Main two-cell authority query; not whole-game frame time"}
	editor.close()
	editor.queue_free()
	if not _runtime.object_adapter.select_object(id):
		return _failed("ordinary visible object selection")
	var taking: Dictionary = _runtime.object_adapter.submit("take")
	if not bool(taking.ok):
		return _failed("ordinary take: " + str(taking))
	_clock.advance_msec(1000)
	var action: Dictionary = world.describe_actor_action("player")
	if not bool(action.ok) or action.domain != "object_lifecycle":
		return _failed("ordinary common handling observation")
	await _capture("handling_pending")
	var checkpoint: String = _hash()
	if _runtime.save_game(ProjectSettings.globalize_path(DIRECTORY + "/handling.json")) != OK:
		return _failed("ordinary in-flight handling save")
	var delta: int = int(action.due_ms) - world.elapsed_ms + 1
	_clock.advance_msec(delta)
	if world.artifacts.objects[id].container != "actor:player" or not world.query_space(Rect2i(target, Vector2i(2, 1)), ["artifact"]).references.is_empty():
		return _failed("handling completion original identity")
	_evidence["handling"] = {"checkpoint": checkpoint, "future": _hash(), "advance_ms": delta, "item": id, "cell": [target.x, target.y], "due_ms": action.due_ms}
	await _capture("handling_held")
	return {"ok": true}


func _construction() -> Dictionary:
	var domain: SimConstruction = _runtime.world_sim.construction
	var source: Vector2i = SimRouteTravel.cell(_runtime.world_sim.regions.home.places[domain.definitions.site.source].cell)
	if not _runtime.travel_to("home", source):
		return _failed("ordinary journey to store")
	for _step: int in 300:
		if _runtime.player_journey.is_empty():
			break
		_clock.advance_msec(100)
	if not _runtime.player_journey.is_empty():
		return _failed("ordinary store journey did not finish")
	var adapter: ConstructionRuntime = _runtime.construction_adapter
	adapter.register_yard()
	if domain.sites.is_empty():
		return _failed("ordinary yard registration")
	adapter.selection = domain.site_bounds().position + Vector2i(2, 2)
	adapter.type_choice.select(0)
	adapter.place_selected()
	var project: String = adapter.selected_project()
	if project.is_empty():
		return _failed("ordinary blueprint placement")
	adapter.act("build")
	for _step: int in 200:
		if not domain.active.has("player") or domain.active.player.phase == "work":
			break
		_clock.advance_msec(maxi(1, domain.next_boundary_ms() - _runtime.world_sim.elapsed_ms))
	if not domain.active.has("player") or domain.active.player.phase != "work":
		return _failed("ordinary material pickup and work arrival")
	_clock.advance_msec(1000)
	var action: Dictionary = _runtime.world_sim.describe_actor_action("player")
	adapter.show_panel()
	await _capture("construction_pending")
	var checkpoint: String = _hash()
	if _runtime.save_game(ProjectSettings.globalize_path(DIRECTORY + "/construction.json")) != OK:
		return _failed("ordinary in-flight construction save")
	var delta: int = int(action.due_ms) - _runtime.world_sim.elapsed_ms + 1
	_clock.advance_msec(delta)
	if domain.projects[project].state != "built":
		return _failed("ordinary construction completion")
	var cell: Vector2i = SimRouteTravel.cell(domain.projects[project].cell)
	var hits: Dictionary = _runtime.world_sim.query_space(Rect2i(cell, Vector2i.ONE), ["construction"], "ground")
	if not bool(hits.ok) or hits.references != [{"kind": "construction", "id": project}]:
		return _failed("ordinary completed structure projection")
	_evidence["construction"] = {"checkpoint": checkpoint, "future": _hash(), "advance_ms": delta, "project": project, "cell": [cell.x, cell.y], "due_ms": action.due_ms}
	await _capture("construction_built")
	return {"ok": true}


func _read() -> Dictionary:
	var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + "/expected.json"))
	if not expected is Dictionary:
		return _failed("missing independent write evidence")
	var result: Dictionary = {"ok": true, "mode": "read", "cases": {}}
	for kind: String in ["handling", "construction"]:
		var old: SimWorldSpace = _runtime.world_sim.space
		if _runtime.load_game(ProjectSettings.globalize_path(DIRECTORY + "/" + kind + ".json")) != OK or _hash() != expected[kind].checkpoint:
			return _failed("independent " + kind + " checkpoint")
		if old.query(Rect2i(Vector2i(256, 256), Vector2i.ONE)).reason != "world_replaced":
			return _failed("retained old runtime space handle")
		var action: Dictionary = _runtime.world_sim.describe_actor_action("player")
		if not bool(action.ok) or action.due_ms != expected[kind].due_ms:
			return _failed("restored common action deadline")
		_clock.advance_msec(int(expected[kind].advance_ms))
		if _hash() != expected[kind].future:
			return _failed("independent " + kind + " complete future")
		await _capture(kind + "_restarted")
		result.cases[kind] = {"checkpoint_matches": true, "complete_future_matches": true, "original_deadline": action.due_ms}
	_write_json("read", result)
	return result


func _capture(label: String) -> void:
	for _frame: int in 8:
		await _main.get_tree().process_frame
	await RenderingServer.frame_post_draw
	_main.get_viewport().get_texture().get_image().save_png(DIRECTORY + "/" + label + ".png")


func _hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(_runtime))).sha256_text()


func _write_json(label: String, value: Dictionary) -> void:
	var file: FileAccess = FileAccess.open(DIRECTORY + "/" + label + ".json", FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(value, "\t", true, true))


func _failed(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
