extends "res://scripts/main.gd"
## Explicit stress opening only. No files or ordinary scenario are modified.

class CrowdVillage extends VillageRuntime:
	var residents: int = 16
	func request_save(_path: String = SAVE_PATH) -> Error:
		return ERR_UNAVAILABLE
	func save_game(_path: String = SAVE_PATH) -> Error:
		return ERR_UNAVAILABLE
	func load_game(_path: String = SAVE_PATH) -> Error:
		return ERR_UNAVAILABLE
	func _load_config() -> bool:
		if not super._load_config():
			return false
		if OS.get_cmdline_user_args().has("--complex") or residents > 512:
			_config.navigation_radius = 64
			_config.navigation_budget = 16384
		for index: int in range(6, residents):
			_config.actor_profiles["crowd_%04d" % index] = {"definition_id": "a_he", "autonomous": true, "hunger": 90.0, "energy": 90.0}
		return true


func _resident_count() -> int:
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--residents="):
			return clampi(argument.get_slice("=", 1).to_int(), 6, 4096)
	return 16


func _create_village_runtime() -> VillageRuntime:
	var adapter := CrowdVillage.new()
	adapter.residents = _resident_count()
	return adapter


func _spawn_named_pawns(spawn_cell: Vector2i) -> void:
	super._spawn_named_pawns(spawn_cell)
	var used: Dictionary = {spawn_cell: true}
	for pawn: Pawn in _pawns:
		used[pawn.cell] = true
	# The ordinary office/facilities and axial plant samples are assembled
	# after spawning. Reserve their whole footprint, even for thousands of
	# extras; leaving only the axial cells free cannot fit the office walls.
	for y: int in range(-10, 11):
		for x: int in range(-10, 11):
			used[spawn_cell + Vector2i(x, y)] = true
	var spread: int = mini(64, maxi(22, ceili(sqrt(float(_resident_count()))) + 4))
	var reachable: Array[Vector2i] = VillageRuntime.find_reachable_cells(world, spawn_cell, spread, 32768)
	var cursor: int = 0
	for index: int in range(6, _resident_count()):
		var cell: Vector2i = spawn_cell
		# Stable spatial spread, not a stack of clones at a single point.
		while cursor < reachable.size() and used.has(reachable[cursor]):
			cursor += 1
		if cursor < reachable.size():
			cell = reachable[cursor]
			cursor += 1
		used[cell] = true
		var pawn := Pawn.new()
		pawn.name = "Crowd_%04d" % index
		pawn.setup(_content.get_pawn(&"a_he"), _content, world, cell)
		pawn.pawn_id = StringName("crowd_%04d" % index)
		pawn.display_name_override = "行者%03d" % index
		add_child(pawn)
		_pawns.append(pawn)
