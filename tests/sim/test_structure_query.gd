extends RefCounted
## Original geometry, costs and detached structure projections.

const QUERY = preload("res://scripts/sim/structure_query.gd")
const RoomsFixture = preload("res://tests/sim/test_rooms_and_rest.gd")
var _rooms := RoomsFixture.new()


class FlatMap extends WorldMapData:
	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_GRASS if in_bounds(cell) else -1


	func get_elevation(cell: Vector2i) -> int:
		return 0 if in_bounds(cell) else -1


func run(runner: Object) -> void:
	_real_construction_and_restore(runner)
	_fixed_workplace(runner)
	_masks_and_rejections(runner)
	print("SCENARIO structure query: original construction/workplace references, layered coverage, distinct physical facts, real door/roof changes, detached read-only results, and four-neighbor wall masks")


func _real_construction_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _rooms._world(runner)
	if world == null:
		return
	var domain: SimConstruction = world.construction
	var cell := Vector2i(110, 108)
	var door: String = _rooms._fixtures._place(runner, world, "wood_door", cell)
	var reference: Dictionary = {"kind": "construction", "id": door}
	var paper: Dictionary = QUERY.locate(world, reference)
	runner.assert_true(bool(paper.get("ok", false)), "the original blueprint is independently addressable")
	if not bool(paper.get("ok", false)):
		return
	runner.assert_eq(paper.cells, [cell], "a current single-cell project reports its actual coverage")
	runner.assert_eq(paper.layer, "ground", "the door belongs to the ground layer")
	for fact: String in ["movement_blocked", "enclosure_boundary", "roofed", "thermal_barrier", "wall_connection"]:
		runner.assert_true(not bool(paper[fact]), "paper has no physical effect: " + fact)
	runner.assert_eq(QUERY.wall_mask(world, cell), 0, "a blueprint does not form a visual wall connection")
	runner.assert_true(domain.begin("player", door).ok, "the door starts the existing paid construction process")
	_rooms._fixtures._finish(runner, world)
	var closed: Dictionary = QUERY.locate(world, reference)
	runner.assert_true(closed.state == "built" and closed.movement_blocked and closed.thermal_barrier and closed.enclosure_boundary, "a completed closed door blocks travel and heat and bounds a space")
	var support: String = _rooms._build(runner, world, "wood_wall", Vector2i(111, 108))
	runner.assert_eq(QUERY.wall_mask(world, cell), QUERY.EAST, "a real adjacent support joins the door frame to its east")
	runner.assert_true(domain.begin("player", door, "open").ok, "opening uses the original timed door action")
	_rooms._fixtures._finish(runner, world)
	var opened: Dictionary = QUERY.locate(world, reference)
	runner.assert_true(opened.open and not opened.movement_blocked and not opened.thermal_barrier and opened.enclosure_boundary, "an open door remains an enclosure boundary but allows passage and heat")
	runner.assert_eq(QUERY.wall_mask(world, cell), QUERY.EAST, "operating a door does not change its wall-frame connection")
	runner.assert_true(domain.begin("player", door, "close").ok, "a clear doorway can be closed through the same owner")
	_rooms._fixtures._finish(runner, world)
	runner.assert_true(QUERY.at_cell(world, cell, "ground").movement_blocked, "the cell query follows the actual completed closure")
	# The roof is two cells from the wall and three from the door, so removing
	# that wall really removes the last support under the existing span rule.
	var bed_cell := Vector2i(113, 108)
	var bed: String = _rooms._build(runner, world, "wood_bed", bed_cell)
	var roof: String = _rooms._fixtures._place(runner, world, "wood_roof", bed_cell)
	var layered: Dictionary = QUERY.at_cell(world, bed_cell)
	runner.assert_eq(layered.structures.size(), 2, "ground bed and upper blueprint retain separate original references")
	runner.assert_true(_has_reference(layered.structures, {"kind": "construction", "id": bed}) and _has_reference(layered.structures, {"kind": "construction", "id": roof}), "both layers point back to their existing projects")
	runner.assert_true(not layered.movement_blocked and not layered.roofed, "a low bed and paper roof do not invent collision or shelter")
	runner.assert_true(domain.begin("player", roof).ok, "the existing nearby wall supports a real roof build")
	_rooms._fixtures._finish(runner, world)
	var sheltered: Dictionary = QUERY.at_cell(world, bed_cell)
	runner.assert_true(sheltered.roofed == domain.roofed(bed_cell) and sheltered.roofed, "shelter comes from the original supported roof rule")
	runner.assert_true(not sheltered.movement_blocked and not sheltered.enclosure_boundary and not sheltered.thermal_barrier, "roof coverage and traversable furniture do not become a ground wall")
	runner.assert_eq(QUERY.at_cell(world, bed_cell, "ground").structures.size(), 1, "ground filtering excludes upper cover")
	runner.assert_eq(QUERY.at_cell(world, bed_cell, "roof").structures.size(), 1, "roof filtering excludes the original bed")
	var before: String = _facts(world)
	var detached: Dictionary = QUERY.locate(world, reference)
	detached.reference.id = "changed"
	detached.cells[0] = Vector2i.ZERO
	detached.movement_blocked = false
	reference.id = "also_changed"
	QUERY.wall_mask(world, cell)
	QUERY.at_cell(world, bed_cell)
	runner.assert_eq(_facts(world), before, "queries and mutation of their returned values preserve original state, costs and time")
	runner.assert_eq(QUERY.locate(world, {"kind": "construction", "id": door}).cells, [cell], "returned references and coverage do not alias original source data")
	var archive: Dictionary = world.to_dict()
	var restored: RegionalSimulation = _rooms._world(runner)
	var accepted: bool = restored.restore(archive)
	runner.assert_true(accepted, "the actual paid layered construction restores independently")
	if accepted:
		runner.assert_eq(QUERY.at_cell(restored, bed_cell), QUERY.at_cell(world, bed_cell), "the same original references and coverage are reconstructed after restore")
		runner.assert_eq(QUERY.wall_mask(restored, cell), QUERY.wall_mask(world, cell), "wall connectivity is derived rather than saved separately")
	runner.assert_true(domain.begin("player", support, "demolish").ok, "the original support can be dismantled with real labor")
	_rooms._fixtures._finish(runner, world)
	runner.assert_eq(QUERY.locate(world, {"kind": "construction", "id": support}), {"ok": false, "reason": "not_found"}, "removed support is no longer physical geometry")
	runner.assert_eq(QUERY.locate(world, {"kind": "construction", "id": roof}), {"ok": false, "reason": "not_found"}, "the resulting real roof collapse removes its coverage")
	runner.assert_true(not QUERY.at_cell(world, bed_cell).roofed and domain.is_bed(bed), "collapse leaves the original bed and removes only the cover")


func _fixed_workplace(runner: Object) -> void:
	# This uses real opening layout assembly without registering another worksite.
	var world: RegionalSimulation = _rooms._fixtures._world(runner)
	if world == null:
		return
	for region: String in ["home", "river"]:
		var sim: VillageSimulation = world.regions[region]
		var attached: bool = SimWorkplaces.enable_opening(sim.config, sim.places, sim.actors, FlatMap.new(), str(sim.config.institution.id))
		runner.assert_true(attached, "the original " + region + " office receives its saved physical layout")
		if not attached:
			return
	var before: String = _facts(world)
	var home: VillageSimulation = world.regions.home
	var layout: Dictionary = home.places.records.workspace
	var walls_ref: Dictionary = {"kind": "workplace", "region": "home", "part": "walls"}
	var walls: Dictionary = QUERY.locate(world, walls_ref)
	runner.assert_true(bool(walls.get("ok", false)), "the fixed wall component resolves its original workplace owner")
	if not bool(walls.get("ok", false)):
		return
	runner.assert_eq(walls.state_owner, "village_simulation", "opening furniture is not copied into construction ownership")
	runner.assert_eq(walls.cells.size(), layout.walls.size(), "one fixed wall-component reference covers all its saved cells")
	var wall: Vector2i = SimRouteTravel.cell(layout.walls[0])
	var wall_cell: Dictionary = QUERY.at_cell(world, wall)
	runner.assert_true(wall_cell.movement_blocked and wall_cell.enclosure_boundary and wall_cell.roofed and wall_cell.thermal_barrier, "fixed wall and upper roof compose independent cell facts")
	runner.assert_true(_has_reference(wall_cell.structures, walls_ref), "reverse lookup returns the original multi-cell component reference")
	var door: Vector2i = SimRouteTravel.cell(layout.door)
	var opening: Dictionary = QUERY.at_cell(world, door, "ground")
	runner.assert_true(not opening.movement_blocked and not opening.thermal_barrier and opening.enclosure_boundary, "the saved fixed doorway is an opening, with no invented door switch")
	runner.assert_true(QUERY.wall_mask(world, door) != 0, "the fixed doorway frame connects to its real walls")
	for part: String in ["desk", "archive"]:
		var fixture_cell: Vector2i = SimRouteTravel.cell(layout.fixtures[part].cell)
		var found: Dictionary = QUERY.at_cell(world, fixture_cell, "ground")
		runner.assert_eq(found.structures.size(), 1, "the " + part + " is one original physical fixture")
		runner.assert_true(found.movement_blocked and not found.enclosure_boundary and not found.thermal_barrier and not found.roofed, "furniture collision does not imply a wall, heat barrier or upper roof")
		runner.assert_eq(QUERY.wall_mask(world, fixture_cell), 0, "solid furniture is not a connecting wall")
	runner.assert_eq(QUERY.locate(world, {"kind": "workplace", "region": "home", "part": "register"}), {"ok": false, "reason": "unsupported_part"}, "the register record sharing the archive does not become a second physical cabinet")
	var river: Dictionary = QUERY.locate(world, {"kind": "workplace", "region": "river", "part": "walls"})
	runner.assert_true(river.ok and river.region == "river" and river.reference != walls.reference, "region-qualified references distinguish the two real office owners")
	walls.cells[0] = Vector2i.ZERO
	walls.reference.region = "changed"
	runner.assert_eq(_facts(world), before, "fixed geometry queries never alter opening layouts, authority, stock or clocks")
	runner.assert_true(QUERY.locate(world, walls_ref).cells.has(wall), "mutating returned component coverage cannot move a saved wall")


func _masks_and_rejections(runner: Object) -> void:
	var world: RegionalSimulation = _mask_world()
	var center := Vector2i(31, 31)
	var before: String = _facts(world)
	runner.assert_eq(QUERY.wall_mask(world, center), 15, "N=1 E=2 S=4 W=8 form the four-way cross across cell 32")
	runner.assert_eq(QUERY.wall_mask(world, center + Vector2i.UP), QUERY.SOUTH, "an end cap reports only its true southern connection")
	var only_observed: Callable = func(cell: Vector2i) -> bool: return cell != center + Vector2i.RIGHT
	var visible_mask: int = QUERY.wall_mask(world, center, only_observed)
	runner.assert_eq(visible_mask, QUERY.NORTH | QUERY.SOUTH | QUERY.WEST, "presentation does not query an unseen eastern neighbour")
	world.construction.projects["construction:3"].state = "removed"
	world.construction._reindex()
	runner.assert_eq(QUERY.wall_mask(world, center, only_observed), visible_mask, "unseen destruction cannot alter the visible wall arms")
	world.construction.projects["construction:3"].state = "built"
	world.construction._reindex()
	world.construction.projects["construction:3"].open = true
	world.construction._reindex()
	runner.assert_eq(QUERY.wall_mask(world, center), 15, "an opened eastern door keeps its frame connection")
	world.construction.projects["construction:2"].state = "blueprint"
	world.construction._reindex()
	runner.assert_eq(QUERY.wall_mask(world, center), QUERY.EAST | QUERY.SOUTH | QUERY.WEST, "paper neighbors do not connect to built walls")
	runner.assert_eq(QUERY.wall_mask(world, center + Vector2i.UP), 0, "a blueprint at the center has no physical wall mask")
	world.construction.projects["construction:3"].state = "removed"
	world.construction._reindex()
	runner.assert_eq(QUERY.wall_mask(world, center), QUERY.SOUTH | QUERY.WEST, "removing a neighboring door immediately changes the derived corner")
	runner.assert_eq(QUERY.at_cell(world, center + Vector2i.RIGHT).structures, [], "removed history is absent from indexed cell queries")
	var stable: String = _facts(world)
	var bad_references: Array = [null, {}, {"kind": "construction"}, {"kind": "construction", "id": ""}, {"kind": "construction", "id": 1}, {"kind": "construction", "id": "construction:1", "cell": [31, 31]}, {"kind": "workplace", "region": 1, "part": "walls"}]
	for bad: Variant in bad_references:
		runner.assert_eq(QUERY.locate(world, bad), {"ok": false, "reason": "invalid_reference"}, "malformed references do not bypass their original owner")
	runner.assert_eq(QUERY.locate(world, {"kind": "actor", "id": "construction:1"}), {"ok": false, "reason": "unsupported_kind"}, "the structure lookup does not conflate entity kinds")
	runner.assert_eq(QUERY.locate(world, {"kind": "construction", "id": "missing"}), {"ok": false, "reason": "not_found"}, "missing original project is explicit")
	runner.assert_eq(QUERY.at_cell(world, center, "other"), {"ok": false, "reason": "invalid_layer"}, "unsupported layers do not silently select ground")
	runner.assert_eq(QUERY.at_cell(world, Vector2i(-1, 0)), {"ok": false, "reason": "invalid_cell"}, "invalid map cells are rejected")
	runner.assert_eq(QUERY.locate(null, {"kind": "construction", "id": "construction:1"}), {"ok": false, "reason": "world_unavailable"}, "an absent world is explicit")
	runner.assert_eq(QUERY.wall_mask(null, center), 0, "the visual mask has no effect without a source world")
	runner.assert_eq(_facts(world), stable, "all rejected queries retain source geometry and pending shared time")
	runner.assert_true(before != stable and world.elapsed_ms == 37 and world.target_ms == 41, "only explicit fixture geometry edits occurred; queries did not settle pending time")


func _mask_world() -> RegionalSimulation:
	# Deliberately minimal geometry fixture, not a fabricated save candidate.
	# Real construction, material, support and restore contracts are tested above.
	var world := RegionalSimulation.new()
	world.regions = {"home": VillageSimulation.new()}
	world.elapsed_ms = 37
	world.target_ms = 41
	var domain := SimConstruction.new()
	world.construction = domain
	domain.bind_world(world)
	domain.definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/construction.json"))
	domain.definitions["site"] = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/construction.json")).site
	domain.sites = {"sect_yard": {"region": "home", "origin": [29, 29], "size": [7, 5]}}
	var cells: Array[Vector2i] = [Vector2i(31, 31), Vector2i(31, 30), Vector2i(32, 31), Vector2i(31, 32), Vector2i(30, 31)]
	for index: int in cells.size():
		var cell: Vector2i = cells[index]
		domain.projects["construction:%d" % (index + 1)] = {"site": "sect_yard", "type": "wood_door" if index == 2 else "wood_wall", "cell": [cell.x, cell.y], "state": "built", "rotation": 0, "hp": 100, "open": false, "material_cell": [cell.x, cell.y]}
	domain._reindex()
	return world


func _has_reference(rows: Array, reference: Dictionary) -> bool:
	for row: Dictionary in rows:
		if row.reference == reference:
			return true
	return false


func _facts(world: RegionalSimulation) -> String:
	# RegionalSimulation.to_dict would intentionally synchronize quiet regions.
	var regions: Dictionary = {}
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		regions[region] = sim.to_dict() if sim.land_resources != null else {"elapsed_ms": sim.elapsed_ms, "config": sim.config, "actors": sim.actors, "places": sim.places, "inventory": sim.inventory.to_dict()}
	return JSON.stringify(SnapshotValues.normalized({"elapsed_ms": world.elapsed_ms, "target_ms": world.target_ms, "regions": regions, "construction": {} if world.construction == null else world.construction.to_dict()}))
