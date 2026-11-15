extends "res://tests/abilities_smoke.gd"
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")
const Interaction = preload("res://scripts/presentation/ui/interaction.gd")
const ObjectCanvas = preload("res://scripts/presentation/objects_canvas.gd")
const Frame = preload("res://scripts/sim/kernel/frame.gd")
const Actions = preload("res://scripts/presentation/ui/actions.gd")

class PreviewHost extends Node2D:
	var frame: RefCounted
	var object_canvas: Node2D
	var fog_enabled: bool = false

func preview(w: RefCounted, definition: String, tile: int, facing: int = 0) -> bool:
	var host := PreviewHost.new()
	var controls := Interaction.new()
	host.object_canvas = ObjectCanvas.new()
	host.frame = Frame.new()
	host.frame.terrain = w.terrain.detached()
	host.frame.player = w.describe(1)
	host.object_canvas.objects = w.objects.layout()
	host.object_canvas.by_tile = w.objects.by_tile
	controls.host = host
	controls.tool = "build"
	controls.definition = definition
	controls.facing = facing
	controls._update_preview(tile)
	var result: bool = controls._preview_ok
	controls.free()
	host.object_canvas.free()
	host.free()
	return result

func assembly_and_validation() -> void:
	var w: RefCounted = fixture()
	for id: int in w.depot_objects:
		var record: Dictionary = w.objects.records[id]
		check(not w.terrain.can_stand(w.Terrain.center(record.tile), 0.35), "A generated depot bypassed its definition collision")
		check(record.cells == w.facilities.footprint(record.definition, record.tile, record.facing), "A generated depot bypassed its footprint")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Unified initial assembly failed restore")
	var tile: int = w.Terrain.index(Vector2i(124, 123))
	var wood: int = w.objects.total("wood")
	var id: int = w.facilities.create_completed(w, "wood_chest", tile, 0, 7)
	w.flush_topology()
	check(w.objects.total("wood") == wood, "Installing a fixture silently debited or created construction materials")
	check(w.objects.records[id].capacity == 7 and w.depot_objects.has(id), "Explicit fixture capacity or depot registration was lost")
	w.objects.add(id, "wood", 1)
	check(not w.remove_static(id) and w.depot_objects.has(id), "Failed removal partly detached a nonempty container")
	var bad: Dictionary = Persistence.capture(w)
	bad.domains.terrain.blocked[tile] = 0
	check(Persistence.candidate(bad, 0) == null, "A completed fixture with missing collision was accepted")
	bad = Persistence.capture(w)
	bad.domains.terrain.depots[0] += 1
	check(Persistence.candidate(bad, 0) == null, "Mismatched depot identity/tile pair was accepted")
	bad = Persistence.capture(w)
	bad.domains.terrain.depots.resize(0)
	check(Persistence.candidate(bad, 0) == null, "Truncated depot tiles were indexed or accepted")
	bad = Persistence.capture(w)
	bad.domains.world.depot_objects.append(id)
	bad.domains.terrain.depots.append(tile)
	check(Persistence.candidate(bad, 0) == null, "Duplicate depot registration was accepted")
	bad = Persistence.capture(w)
	bad.domains.regions.landmarks.append(w.objects.next_id + 10)
	check(Persistence.candidate(bad, 0) == null, "Missing landmark identity was accepted")
	w.pages[0].positions[1] = Vector2(123.5, 123.5)
	check(w.begin_transfer(2, {"kind": "take", "target": id, "item": "wood", "amount": 1}) == "accepted", "Removal task fixture refused")
	check(w.facilities.demolish(w, id) and not w.actions.has(2) and not w.reservations.has(id), "Demolition retained an active target/run")
	w.flush_topology()
	check(not w.depot_objects.has(id) and not w.terrain.depots.has(tile) and w.terrain.can_stand(w.Terrain.center(tile), 0.35), "Demolition retained registration or collision")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Controlled removal did not leave a valid world")
	var pile: int = 0
	for other: int in w.objects.by_tile.get(tile, []):
		if w.objects.records[other].kind == "pile": pile = other
	w.pages[0].positions[1] = w.Terrain.center(tile)
	check(pile > 0 and w.begin_transfer(2, {"kind": "take", "target": pile, "item": "wood", "amount": 1}) == "accepted", "Salvage collection fixture refused")
	advance(w, w.elapsed_ms + 400)
	check(not w.objects.records.has(pile) and w.objects.amount(2, "wood") == 1, "Empty pile cleanup interrupted its own completed transfer")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Empty pile cleanup retained a target/run reference")

func independent_layers() -> void:
	var w: RefCounted = fixture()
	var first: int = w.Terrain.index(Vector2i(124, 123))
	var floor: int = w.facilities.create_completed(w, "wood_floor", first)
	var wall: int = w.facilities.create_completed(w, "wood_wall", first)
	w.flush_topology()
	check(w.facilities.demolish(w, floor), "Layered floor removal failed")
	w.flush_topology()
	check(w.terrain.flooring[first] == 0 and w.terrain.blocked[first] != 0 and w.terrain.enclosures[first] != 0 and w.objects.records.has(wall), "Removing a floor erased surviving wall facts")
	var second: int = w.Terrain.index(Vector2i(126, 123))
	floor = w.facilities.create_completed(w, "wood_floor", second)
	wall = w.facilities.create_completed(w, "wood_wall", second)
	w.flush_topology()
	check(w.facilities.demolish(w, wall), "Layered wall removal failed")
	w.flush_topology()
	check(w.terrain.flooring[second] != 0 and w.terrain.blocked[second] == 0 and w.terrain.enclosures[second] == 0 and w.objects.records.has(floor), "Removing a wall erased its surviving floor")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Independent layers failed restore after removal")

func cultivation_restore() -> void:
	var w: RefCounted = fixture()
	var tile: int = w.Terrain.index(Vector2i(124, 123))
	var pot: int = w.facilities.create_completed(w, "planter", tile)
	w.flush_topology()
	var plant: int = w.nature.create(w, "perennial_herb", tile)
	var wild: int = w.nature.create(w, "perennial_herb", tile + 3)
	check(plant > 0 and wild > 0 and Persistence.candidate(Persistence.capture(w), 0) != null, "Potted and ordinary plants failed valid restore")
	for invalid: String in ["missing_host", "host_type", "host_negative", "missing_facility", "actor_host", "different_cell", "missing_guest", "guest_type", "guest_missing_plant", "guest_wrong_host", "unindexed_guest", "unindexed_natural"]:
		var bad: Dictionary = Persistence.capture(w)
		var records: Dictionary = bad.domains.objects.records
		match invalid:
			"missing_host": records[plant].erase("host")
			"host_type": records[plant].host = "bad"
			"host_negative": records[plant].host = -1
			"missing_facility": records[plant].host = w.objects.next_id + 10
			"actor_host":
				records[plant].host = 1
				records[1]["guest"] = plant
			"different_cell": records[plant].tile = tile + 5
			"missing_guest": records[pot].erase("guest")
			"guest_type": records[pot].guest = "bad"
			"guest_missing_plant": records[pot].guest = w.objects.next_id + 10
			"guest_wrong_host": records[pot].guest = wild
			"unindexed_guest": bad.domains.nature.ids.remove_at(bad.domains.nature.ids.find(plant))
			"unindexed_natural": bad.domains.nature.ids.remove_at(bad.domains.nature.ids.find(wild))
		check(Persistence.candidate(bad, 0) == null, "Invalid cultivation relationship was accepted: " + invalid)
	w.pages[0].positions[1] = Vector2(123.5, 123.5)
	check(w.begin_interaction(2, {"kind": "tend", "target": plant}) == "accepted", "Potted work removal fixture refused")
	check(w.facilities.demolish(w, pot) and not w.objects.records.has(plant) and not w.actions.has(2), "Removing a cultivation facility retained its plant or worker")
	w.flush_topology()
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Removing a populated planter failed restore")

func placement_contract() -> void:
	Actions.load_definitions()
	var w: RefCounted = fixture()
	w.objects.transfer(w.source_objects[0], 1, "wood", 50)
	var resource: int = w.source_objects[0]
	var resource_tile: int = w.objects.records[resource].tile
	check(w.nature.finish(w, 1, {"kind": "uproot", "target": resource}, 0) == "completed", "Clearing a resource fixture failed")
	var ground: int = w.Terrain.index(Vector2i(124, 123))
	var floor_tile: int = w.Terrain.index(Vector2i(126, 123))
	w.facilities.create_completed(w, "wood_wall", ground)
	w.facilities.create_completed(w, "wood_floor", floor_tile)
	var plant: int = w.nature.create(w, "perennial_herb", w.Terrain.index(Vector2i(128, 123)))
	check(plant > 0, "Placement vegetation fixture failed")
	w.flush_topology()
	var cases: Array = [["wood_wall", resource_tile, 0, true], ["wood_floor", resource_tile, 0, true], ["wood_wall", ground, 0, false], ["wood_floor", ground, 0, true], ["wood_wall", floor_tile, 0, true], ["wood_floor", floor_tile, 0, false], ["wood_roof", ground, 0, true], ["wood_wall", w.Terrain.index(Vector2i(128, 123)), 0, false], ["wood_floor", w.Terrain.index(Vector2i(128, 123)), 0, true], ["wood_table", w.Terrain.index(Vector2i(140, 123)), 1, true], ["wood_table", w.Terrain.index(Vector2i(511, 511)), 1, false]]
	for entry: Array in cases:
		var cells: PackedInt32Array = w.facilities.footprint(entry[0], entry[1], entry[2])
		var backend: bool = w.facilities.placement(w, str(w.facilities.definitions[entry[0]].get("layer", "ground")), cells) == "accepted"
		check(backend == entry[3] and preview(w, entry[0], entry[1], entry[2]) == backend, "Preview/authoritative placement diverged: " + str(entry))
	check(w.facilities.blueprint(w, 1, "wood_wall", resource_tile).reason == "accepted", "Shared rule accepted a preview but not actual cleared-resource construction")

func remove_every_registration() -> void:
	var w: RefCounted = fixture()
	var targets: PackedInt64Array = w.depot_objects.duplicate()
	targets.append_array(w.regions.landmarks)
	for target: int in targets:
		var point: Vector2 = w.facilities.interaction_point(w, target, w.Terrain.center(w.objects.records[target].tile) + Vector2(0, 2), 0.35, false, "demolish")
		check(point.x >= 0, "Registered fixture had no demolition access")
		if point.x < 0: continue
		w.pages[0].positions[0] = point
		check(w.command({"kind": "demolish", "target": target}).ok, "Normal demolition command refused a registered fixture")
		advance(w, w.elapsed_ms + 400)
		check(not w.objects.records.has(target), "Normal demolition did not remove the registered fixture")
	check(w.depot_objects.is_empty() and w.terrain.depots.is_empty() and w.regions.landmarks.is_empty(), "Last registered fixture could not be removed")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Legal empty depot/landmark registries were rejected")
	var path: String = "user://facility-lifecycle-smoke.reol"
	var io := SessionIO.new()
	for kind: String in ["save", "load"]:
		check(io.submit({"kind": kind, "path": path}, Persistence.capture(w) if kind == "save" else {}, func(): pass, 0), "Lifecycle I/O job refused")
		var result: Dictionary = {}
		var limit: int = Time.get_ticks_msec() + 2000
		while result.is_empty() and Time.get_ticks_msec() < limit:
			await process_frame
			result = io.poll()
		check(result.get("ok", false), "Legal demolition failed actual file " + kind + ": " + str(result.get("reason", "timeout")))
	io.close()
	for suffix: String in ["", ".bak", ".tmp"]:
		if FileAccess.file_exists(path + suffix): DirAccess.remove_absolute(path + suffix)
	var replacement: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(124, 123)))
	w.flush_topology()
	check(w.depot_objects == PackedInt64Array([replacement]) and Persistence.candidate(Persistence.capture(w), 0) != null, "Replacement storage depended on initial depot identities/count")

func _run() -> void:
	assembly_and_validation()
	independent_layers()
	cultivation_restore()
	placement_contract()
	await remove_every_registration()
	print("FACILITY_LIFECYCLE_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
