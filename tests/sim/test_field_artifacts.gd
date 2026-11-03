extends RefCounted
## A field slot locates the original unique object without a stack/container copy.

const Fixtures = preload("res://tests/sim/test_conflicts.gd")
const RING: String = "stele_drawing_ring"
const SITE: String = "site:broken_stele"
const CELL := Vector2i(220, 220)
var _fixtures := Fixtures.new()


class FieldGeometry extends WorldMapData:
	var cover: Dictionary = {}
	var levels: Dictionary = {}


	func get_terrain(cell: Vector2i) -> int:
		return TERRAIN_ROCK if cover.has(cell) else TERRAIN_GRASS


	func get_elevation(cell: Vector2i) -> int:
		return int(levels.get(cell, 0))


class Slots extends RefCounted:
	## Deliberately only a finite location authority. Field purpose, activation
	## provenance and joint migration are tested by the actual field-domain suite.
	var enabled: bool = false


	func valid_slot(region: String, container: String) -> bool:
		return enabled and region == "home" and container == SITE


	func slot_cell(region: String, container: String) -> Vector2i:
		return CELL if valid_slot(region, container) else Vector2i(-1, -1)


	func owns_actor(_actor: String) -> bool:
		return false


	func previous_autonomy(_actor: String) -> bool:
		return false


	func wants_decision(_actor: String, _at_ms: int) -> bool:
		return false


	func settle_at_ms(_at_ms: int) -> void:
		pass


	func consider() -> void:
		pass


	func next_boundary_ms() -> int:
		return SimInventory.MAX_COUNT


func run(runner: Object) -> void:
	_spawn_and_definition(runner)
	_physical_research_and_memory(runner)
	_take_place_and_candidate(runner)
	_visitor_fixed_storage(runner)
	_geometry_at_start_and_completion(runner)
	print("SCENARIO field artifacts: authoritative site references, one original nonthermal ring, zero-qi physical research without use mastery, private fixed memories, guarded timed custody and cross-owner return")


func _world(runner: Object, spawn: bool = true) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._world(runner)
	if world == null:
		return null
	var slots := Slots.new()
	world.field_opportunities = slots
	world.bind_map_data(FieldGeometry.new())
	if spawn:
		slots.enabled = true
		if not world.artifacts.spawn_field_object(RING, "drawing_ring", "home", SITE):
			runner.assert_true(false, "explicit field assembler creates its actual ring once")
			return null
	_fixtures._put(world, "player", TileGrid.cell_to_world(CELL))
	return world


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _finish(runner: Object, world: RegionalSimulation, actor: String = "player") -> void:
	if not world.artifacts.active.has(actor):
		runner.assert_true(false, "completion requires the real original handling process")
		return
	runner.assert_true(world.advance_to_ms(int(world.artifacts.active[actor].due_ms)), "original shared clock completes the field object operation")


func _roundtrip(runner: Object, world: RegionalSimulation, label: String) -> void:
	var before: String = _canonical(world.artifacts.to_dict())
	var candidate := SimArtifacts.new()
	runner.assert_true(candidate.initialize(world, world._content.artifacts), label + " constructs an independent object candidate")
	runner.assert_true(candidate.restore(JSON.parse_string(before)), label + " restores actual JSON under the original body and slot authorities")
	runner.assert_eq(_canonical(candidate.to_dict()), before, label + " retains the exact original object/action/event payload")
	runner.assert_eq(_canonical(world.artifacts.to_dict()), before, label + " leaves the source object domain unchanged")


func _reject(runner: Object, world: RegionalSimulation, bad: Dictionary, label: String) -> void:
	var before: String = _canonical(world.artifacts.to_dict())
	var input: String = _canonical(bad)
	runner.assert_true(not world.artifacts.restore(bad), label + " is rejected before committing any object state")
	runner.assert_eq(_canonical(world.artifacts.to_dict()), before, label + " preserves every original object and process")
	runner.assert_eq(_canonical(bad), input, label + " does not repair the passed candidate")


func _spawn_and_definition(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner, false)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	var before: String = _canonical(domain.to_dict())
	var inventory: String = _canonical(world.regions.home.inventory.to_dict())
	runner.assert_true(not domain.valid_location("home", SITE) and not domain.spawn_field_object(RING, "drawing_ring", "home", SITE), "a nonexistent or unactivated field slot grants no object location or spawn")
	runner.assert_eq(_canonical(domain.to_dict()), before, "refused field assembly creates no object or history")
	(world.field_opportunities as Slots).enabled = true
	runner.assert_true(domain.valid_location("home", SITE) and not domain.valid_location("river", SITE) and not domain.valid_location("home", "site:invented"), "field authority alone decides the actual slot and its registrar")
	runner.assert_true(not domain.spawn_field_object(RING, "warm_stone", "home", SITE), "this nonthermal field-object seam does not manufacture a thermal state")
	runner.assert_true(domain.spawn_field_object(RING, "drawing_ring", "home", SITE), "authorized assembler adds the one actual ring")
	runner.assert_eq(domain.objects[RING], {"definition": "drawing_ring", "region": "home", "container": SITE}, "ring owns only its original type and unique location reference")
	runner.assert_eq(domain.object_cell(RING), CELL, "object cell is read from the field slot, not a fake village place")
	runner.assert_eq(_canonical(world.regions.home.inventory.to_dict()), inventory, "field slot creates no mirrored quantity container or stack")
	runner.assert_true(not world.regions.home.places.has(SITE) and not world.regions.home.inventory.containers.has(SITE), "POI remains separate from colony functional places")
	var assembled: String = _canonical(domain.to_dict())
	runner.assert_true(not domain.spawn_field_object(RING, "drawing_ring", "home", SITE) and not domain.spawn_field_object("duplicate_ring", "drawing_ring", "home", SITE), "duplicate identity or occupied slot cannot create a second ring")
	runner.assert_eq(_canonical(domain.to_dict()), assembled, "repeated field spawn changes no cost, event or identity")
	runner.assert_true(domain.has_capability(RING, "remote_draw") and not domain.has_capability(RING, "heat_storage") and not domain.has_capability(RING, "weapon"), "drawing capability neither adds heat nor makes a weapon")
	var verbs: Dictionary = domain.verbs_for(RING)
	runner.assert_eq(verbs.size(), 7, "ring exposes five physical operations and two distinct paid uses")
	for verb: String in ["inspect", "take", "place", "study", "examine"]:
		runner.assert_eq(verbs[verb].qi, 0, "outer-form operation keeps its original zero qi cost: " + verb)
	for verb: String in ["use_research", "draw"]:
		runner.assert_true(int(verbs[verb].qi) > 0, "new practical operation has an explicit qi cost: " + verb)
	runner.assert_true(not domain.begin("player", "use_research", RING).ok, "unheld and unstudied ring cannot begin practical research")
	for verb: String in ["draw", "heat", "warm", "charge", "force"]:
		runner.assert_true(not domain.begin("player", verb, RING).ok, "draw requires a target and thermal actions remain unsupported: " + verb)
	runner.assert_eq(_canonical(domain.to_dict()), assembled, "rejected actions do not allocate costs or processes")
	_roundtrip(runner, world, "loose site ring")
	for fault: String in ["thermal_payload", "fake_slot", "wrong_registrar"]:
		var bad: Dictionary = JSON.parse_string(assembled)
		match fault:
			"thermal_payload": bad.objects[RING]["charge"] = 0
			"fake_slot": bad.objects[RING].container = "site:invented"
			"wrong_registrar": bad.objects[RING].region = "river"
		_reject(runner, world, bad, fault)


func _physical_research_and_memory(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	var view: Dictionary = domain.describe("player", RING)
	runner.assert_true(view.known and not view.method and not str(view.line).contains("剑招"), "seeing the ring provides its own outer-form clue, not sword or magical mastery")
	runner.assert_true(not SimArtifacts.Understanding.remembered(domain, "player", RING).known, "currently visible appearance does not fabricate a historical note")
	var qi: int = int(world.regions.home.actors.player.qi)
	var checkpoint: String = _canonical(world.spirit_sources.qi_baselines)
	runner.assert_true(domain.begin("player", "study", RING).ok, "player deliberately begins physical outer-form research")
	_finish(runner, world)
	view = domain.describe("player", RING)
	runner.assert_true(view.known and view.label == "引物环" and not view.method, "studied outer form can identify the ring without granting its future use")
	runner.assert_eq(world.regions.home.actors.player.qi, qi, "outer-form research preserves original body qi")
	runner.assert_true(world.spirit_sources.qi_baselines.is_empty(), "zero-qi shape study creates no unexplained baseline")
	runner.assert_eq(_canonical(world.spirit_sources.qi_baselines), checkpoint, "shape study changes no qi checkpoint")
	runner.assert_true(world.spirit_sources.active.is_empty() and world.spirit_sources.records.is_empty() and world.spirit_sources.next_id == 1, "shape study manufactures no source conversion or source allocation")
	var memory: Dictionary = SimArtifacts.Understanding.remembered(domain, "player", RING)
	runner.assert_true(memory.known and memory.label == "引物环" and not memory.method and not memory.near and not memory.held, "hidden memory keeps identification separate from use and current access")
	_fixtures._put(world, "player", TileGrid.cell_to_world(Vector2i(20, 20)))
	_fixtures._put(world, "chen_shouzhuo", TileGrid.cell_to_world(CELL))
	runner.assert_true(domain.begin("chen_shouzhuo", "take", RING).ok, "another original body can later take the same loose ring")
	_finish(runner, world, "chen_shouzhuo")
	_fixtures._put(world, "chen_shouzhuo", TileGrid.cell_to_world(Vector2i(300, 300)))
	runner.assert_eq(_canonical(SimArtifacts.Understanding.remembered(domain, "player", RING)), _canonical(memory), "unseen later custody and motion do not rewrite the player's old record")
	runner.assert_true(not domain.describe("chen_shouzhuo", RING).method, "taking the ring grants no future pulling method to an NPC")
	_roundtrip(runner, world, "identified ring now held elsewhere")


func _take_place_and_candidate(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	runner.assert_true(domain.begin("player", "take", RING).ok, "taking uses the original paid-time object process")
	runner.assert_true(world.advance_to_ms(17000), "actual take reaches a partial time")
	runner.assert_eq(domain.objects[RING].container, SITE, "partial taking does not transfer the ring early")
	_fixtures._put(world, "chen_shouzhuo", TileGrid.cell_to_world(CELL))
	runner.assert_true(not domain.begin("chen_shouzhuo", "take", RING).ok, "one original ring cannot be handled by a second actor concurrently")
	_roundtrip(runner, world, "in-flight take from field slot")
	var bad: Dictionary = JSON.parse_string(_canonical(domain.to_dict()))
	bad.active.player.verb = "draw"
	_reject(runner, world, bad, "unimplemented active draw")
	_finish(runner, world)
	runner.assert_eq(domain.objects[RING].container, "actor:player", "completed take changes the one original object's container")
	runner.assert_true(not domain.begin("chen_shouzhuo", "take", RING).ok, "being nearby does not let another actor take a held ring")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "drawing_ring"), 0, "held unique ring is not also a counted inventory stack")
	_fixtures._put(world, "player", TileGrid.cell_to_world(Vector2i(20, 20)))
	runner.assert_true(not domain.begin("player", "place", RING).ok, "ring cannot be placed remotely by merely holding it")
	_fixtures._put(world, "player", TileGrid.cell_to_world(CELL))
	runner.assert_true(domain.begin("player", "place", RING).ok, "holder can spend original time returning it to the real slot")
	_fixtures._put(world, "player", TileGrid.cell_to_world(Vector2i(20, 20)))
	bad = JSON.parse_string(_canonical(domain.to_dict()))
	_reject(runner, world, bad, "ongoing placement after leaving the slot")
	_finish(runner, world)
	runner.assert_eq(domain.objects[RING].container, "actor:player", "leaving before completion cannot teleport a held object back to the field")
	_fixtures._put(world, "player", TileGrid.cell_to_world(CELL))
	runner.assert_true(domain.begin("player", "place", RING).ok, "failed placement retains the same ring for a real retry")
	_finish(runner, world)
	runner.assert_eq(domain.objects[RING].container, SITE, "actual completed placement returns the same unique ring")
	_roundtrip(runner, world, "returned site ring with completed handling history")


func _visitor_fixed_storage(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	var actor: String = "river_chen_shouzhuo"
	_fixtures._put(world, actor, TileGrid.cell_to_world(CELL))
	runner.assert_true(domain.begin(actor, "take", RING).ok, "visitor can act at the physical site despite another original region owner")
	_finish(runner, world, actor)
	runner.assert_eq(domain.objects[RING].region, "river", "held object follows the visitor's original body registrar")
	runner.assert_eq(domain.objects[RING].container, "actor:" + actor, "visitor holds exactly the original ring")
	runner.assert_eq(domain.storage_region("river", SITE), "home", "fixed field storage retains its actual registrar independent of holder")
	_roundtrip(runner, world, "ring held by another region's original body")
	runner.assert_true(domain.begin(actor, "place", RING).ok, "visitor may physically return the held ring to the actual home field slot")
	_finish(runner, world, actor)
	runner.assert_eq(domain.objects[RING].region, "home", "return commits the original field registrar")
	runner.assert_eq(domain.objects[RING].container, SITE, "return creates no river-local mirror of the field slot")
	_roundtrip(runner, world, "visitor return to the original field slot")


func _geometry_at_start_and_completion(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	var geometry: FieldGeometry = world.map_data as FieldGeometry
	var near: Vector2i = CELL - Vector2i(2, 0)
	var between: Vector2i = CELL - Vector2i(1, 0)
	_fixtures._put(world, "player", TileGrid.cell_to_world(near))
	runner.assert_true(domain.can_see("player", RING) and domain._near("player", RING), "same-level clear segment permits nearby real ring handling")
	geometry.cover[between] = true
	runner.assert_true(not domain.can_see("player", RING) and not domain._near("player", RING), "real intervening cover blocks both ring observation and handling")
	var before: String = _canonical(domain.to_dict())
	for verb: String in ["inspect", "examine", "study", "take"]:
		runner.assert_true(not domain.begin("player", verb, RING).ok, "ring rejects operation through actual cover: " + verb)
	runner.assert_eq(_canonical(domain.to_dict()), before, "covered ring cannot allocate a handling action")
	geometry.cover.clear()
	geometry.levels[CELL] = 1
	runner.assert_true(not domain.can_see("player", RING) and not domain.begin("player", "take", RING).ok, "another height cannot be bypassed by being close on the grid")
	geometry.levels.clear()
	_fixtures._put(world, "player", TileGrid.cell_to_world(CELL - Vector2i(3, 0)))
	runner.assert_true(domain.can_see("player", RING) and not domain.begin("player", "take", RING).ok, "seeing a ring outside handling range does not permit taking it")
	_fixtures._put(world, "player", TileGrid.cell_to_world(near))
	runner.assert_true(domain.begin("player", "take", RING).ok, "actual taking starts with valid geometry")
	geometry.cover[between] = true
	_finish(runner, world)
	runner.assert_eq(domain.objects[RING].container, SITE, "cover added during handling prevents transfer at completion")
	runner.assert_eq(domain.events.back().kind, "failed", "failed physical continuation keeps an actual terminal record")
	geometry.cover.clear()
	runner.assert_true(domain.begin("player", "take", RING).ok, "cleared actual segment allows taking the original ring again")
	_finish(runner, world)
	runner.assert_eq(domain.objects[RING].container, "actor:player", "clear completion transfers the actual object")
	geometry.cover[between] = true
	runner.assert_true(not domain.begin("player", "place", RING).ok, "holding a ring cannot place it through cover into its fixed slot")
	geometry.cover.clear()
	geometry.levels[CELL] = 1
	runner.assert_true(not domain.begin("player", "place", RING).ok, "holding a ring cannot place it onto a different height")
	geometry.levels.clear()
	runner.assert_true(domain.begin("player", "place", RING).ok, "actual slot placement starts with clear same-level geometry")
	geometry.cover[between] = true
	_finish(runner, world)
	runner.assert_eq(domain.objects[RING].container, "actor:player", "new cover at placement completion retains the same held object")
	geometry.cover.clear()
	runner.assert_true(domain.begin("player", "place", RING).ok, "cleared placement can be retried without an object copy")
	_finish(runner, world)
	runner.assert_eq(domain.objects[RING].container, SITE, "successful placement returns only the original unique ring")
	_roundtrip(runner, world, "physical ring failures and successful return")
