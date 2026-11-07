extends RefCounted
## Actual lumber, construction time and original stone events meet in the same
## spatial heat authority. Fixtures supply a flat map and inactive bystanders;
## no completed structure, source receipt or stored charge is fabricated.

const Rooms = preload("res://tests/sim/test_rooms_and_rest.gd")
const Artifacts = preload("res://tests/sim/test_artifacts.gd")
var _rooms := Rooms.new()
var _artifacts := Artifacts.new()


func run(runner: Object) -> void:
	var room: Dictionary = _roofed_room(runner)
	if not room.is_empty():
		_door_exchange(runner, room)
		_wall_breach(runner, room)
		_carried_source_leaves_released_heat(runner, room)
	_support_collapse(runner)
	_two_uses_one_charge(runner)
	print("SCENARIO field/building: paid walls, doors and roofs, continuous actual temperature without room insulation, roof collapse, original finite charge and physical source receipts")


func _stone(runner: Object, world: RegionalSimulation, verb: String) -> bool:
	var reply: Dictionary = world.artifacts.begin("player", verb, "hearth_stone")
	runner.assert_true(reply.ok, "original stone action really begins: " + verb + ": " + str(reply.line))
	if not reply.ok:
		return false
	var due: int = int(world.artifacts.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(due), "original clock pays the full stone duration: " + verb)
	var expected: String = {"study": "studied", "take": "taken", "warm": "warmed", "heat": "heated"}.get(verb, "")
	runner.assert_eq(world.artifacts.events.back().kind, expected, "completed original operation has its real effect: " + verb)
	return world.artifacts.events.back().kind == expected


func _learn_and_take(runner: Object, world: RegionalSimulation) -> bool:
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	runner.assert_true(world.artifacts.spawn_opening(opening), "the actual scenario places one finite stone in the original kitchen")
	# Initial fixture placement only. Every later construction movement uses
	# its actual path, body ownership, clock and carried object reference.
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.regions.home.places.kitchen.cell))
	world.invalidate_region("home")
	return _stone(runner, world, "study") and _stone(runner, world, "take")


func _build(runner: Object, world: RegionalSimulation, type: String, cell: Vector2i) -> String:
	return _rooms._build(runner, world, type, cell)


func _finish(runner: Object, world: RegionalSimulation) -> void:
	_rooms._fixtures._finish(runner, world)


func _operate(runner: Object, world: RegionalSimulation, project: String, kind: String) -> bool:
	var reply: Dictionary = world.construction.begin("player", project, kind)
	runner.assert_true(reply.ok, "actual structure operation begins: " + kind + ": " + str(reply.line))
	if not reply.ok:
		return false
	_finish(runner, world)
	return not world.construction.owns_actor("player")


func _roofed_room(runner: Object) -> Dictionary:
	var world: RegionalSimulation = _rooms._world(runner)
	if world == null or not _learn_and_take(runner, world):
		return {}
	var stock: int = world.regions.home.inventory.quantity("store", "wood")
	var wall: String = ""
	for y: int in range(107, 110):
		for x: int in range(109, 113):
			var cell := Vector2i(x, y)
			if x not in [109, 112] and y not in [107, 109] or cell == Vector2i(109, 108):
				continue
			var id: String = _build(runner, world, "wood_wall", cell)
			if cell == Vector2i(110, 107):
				wall = id
	var door: String = _build(runner, world, "wood_door", Vector2i(109, 108))
	if not _operate(runner, world, door, "open"):
		return {}
	var first: String = _build(runner, world, "wood_roof", Vector2i(110, 108))
	var second: String = _build(runner, world, "wood_roof", Vector2i(111, 108))
	# Roof work physically walks through the open doorway to the adjacent
	# indoor stand; closing the original door leaves the actual holder inside.
	if not _operate(runner, world, door, "close"):
		return {}
	var space: Dictionary = world.construction.space_at(Vector2i(110, 108))
	runner.assert_true(space.enclosed and space.roofed and int(space.area) == 2, "actual walls and paid upper-layer roofs form a two-cell covered room")
	runner.assert_eq(world.regions.home.inventory.quantity("store", "wood"), stock - 39, "nine walls, one door and two roofs consumed exactly their original lumber")
	runner.assert_eq(world.artifacts.object_cell("hearth_stone"), Vector2i(110, 108), "actual roof and door work carried the one held stone into the room")
	runner.assert_true(world.local_heat.receipts.is_empty(), "building and carrying a charged stone alone do not create a paid warming receipt")
	return {"world": world, "door": door, "wall": wall, "roofs": [first, second]}


func _state(world: RegionalSimulation) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(world.to_dict()), "", true, true)


func _clone(runner: Object, world: RegionalSimulation) -> RegionalSimulation:
	var snapshot: Dictionary = JSON.parse_string(_state(world))
	var copy: RegionalSimulation = _rooms._world(runner)
	if copy == null:
		return null
	var restored: bool = copy.restore(snapshot)
	runner.assert_true(restored, "independent real-world candidate restores the built room, carried object and field receipts together")
	return copy if restored else null


func _assert_same_actual(runner: Object, world: RegionalSimulation, control: RegionalSimulation, label: String) -> void:
	if world.elapsed_ms != control.elapsed_ms:
		runner.assert_true(false, label + " compares the same shared instant")
		return
	for cell: Vector2i in [Vector2i(108, 108), Vector2i(109, 108), Vector2i(110, 107), Vector2i(110, 108), Vector2i(111, 108)]:
		var changed: Dictionary = world.local_heat.actual_at(cell, world.elapsed_ms)
		var unchanged: Dictionary = control.local_heat.actual_at(cell, control.elapsed_ms)
		var available: bool = bool(changed.get("ok", false)) and bool(unchanged.get("ok", false))
		runner.assert_true(available, label + " exposes actual field values at " + str(cell))
		if available:
			runner.assert_true(absf(float(changed.value_c) - float(unchanged.value_c)) < 0.00001, label + " preserves actual temperature at " + str(cell))


func _commit_against_old_layout(runner: Object, world: RegionalSimulation, project: String, kind: String) -> RegionalSimulation:
	var response: Dictionary = world.construction.begin("player", project, kind)
	runner.assert_true(response.ok, "timed topology operation is genuinely accepted: " + kind + ": " + str(response.line))
	if not response.ok:
		return null
	for index: int in range(120):
		if not world.construction.active.has("player") or world.construction.active.player.phase == "work":
			break
		if not world.advance_to_ms(maxi(world.elapsed_ms + 1, world.construction.next_boundary_ms())):
			runner.assert_true(false, "actual topology worker route reaches its work phase")
			return null
	if not world.construction.active.has("player") or world.construction.active.player.phase != "work":
		runner.assert_true(false, "topology operation remains an actual pending timed work action")
		return null
	var due: int = int(world.construction.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(due - 1), "old physical layout remains in effect until the final work millisecond")
	var control: RegionalSimulation = _clone(runner, world)
	if control == null:
		return null
	runner.assert_true(control.construction.cancel("player"), "the comparison world legitimately cancels unfinished work and retains its old structure")
	runner.assert_true(control.advance_to_ms(due) and world.advance_to_ms(due), "both original worlds reach the exact same topology commit timestamp")
	_assert_same_actual(runner, world, control, "committing " + kind + " at its actual deadline")
	return control


func _door_exchange(runner: Object, fixture: Dictionary) -> void:
	var world: RegionalSimulation = _clone(runner, fixture.world)
	if world == null or not _stone(runner, world, "warm"):
		return
	var closed: RegionalSimulation = _commit_against_old_layout(runner, world, fixture.door, "open")
	if closed == null:
		return
	runner.assert_true(not world.construction.blocked(Vector2i(109, 108)) and closed.construction.blocked(Vector2i(109, 108)), "only completed original door handling changes the physical opening")
	var at_ms: int = world.elapsed_ms + 60000
	runner.assert_true(world.advance_to_ms(at_ms) and closed.advance_to_ms(at_ms), "open and closed layouts evolve from their identical actual commit-time heat")
	_assert_same_actual(runner, world, closed, "the current outdoor field does not apply door insulation")
	if not _stone(runner, world, "warm"):
		return
	var opened: RegionalSimulation = _commit_against_old_layout(runner, world, fixture.door, "close")
	if opened == null:
		return
	runner.assert_true(world.construction.blocked(Vector2i(109, 108)) and not opened.construction.blocked(Vector2i(109, 108)), "a second timed physical action closes only the chosen world's door")
	at_ms = world.elapsed_ms + 60000
	runner.assert_true(world.advance_to_ms(at_ms) and opened.advance_to_ms(at_ms), "closed and still-open doors use the same future time interval")
	_assert_same_actual(runner, world, opened, "the current outdoor field also ignores the closed door")


func _wall_breach(runner: Object, fixture: Dictionary) -> void:
	var world: RegionalSimulation = _clone(runner, fixture.world)
	if world == null or not _stone(runner, world, "warm"):
		return
	var enclosed: RegionalSimulation = _commit_against_old_layout(runner, world, fixture.wall, "demolish")
	if enclosed == null:
		return
	runner.assert_true(not world.construction.space_at(Vector2i(110, 108)).enclosed and enclosed.construction.space_at(Vector2i(110, 108)).enclosed, "real wall removal changes enclosure rather than applying a room-name temperature reset")
	for id: String in fixture.roofs:
		runner.assert_eq(world.construction.projects[id].state, "built", "remaining original walls keep this roof physically supported after a breach")
	var end: int = world.elapsed_ms + 60000
	runner.assert_true(world.advance_to_ms(end) and enclosed.advance_to_ms(end), "breached and intact rooms advance an identical further minute")
	_assert_same_actual(runner, world, enclosed, "the current outdoor field does not apply wall insulation")


func _support_collapse(runner: Object) -> void:
	var world: RegionalSimulation = _rooms._world(runner)
	if world == null or not _learn_and_take(runner, world):
		return
	var support: String = _build(runner, world, "wood_wall", Vector2i(111, 108))
	var first: String = _build(runner, world, "wood_roof", Vector2i(110, 108))
	var second: String = _build(runner, world, "wood_roof", Vector2i(109, 108))
	runner.assert_true(world.construction.roofed(Vector2i(110, 108)) and world.construction.roofed(Vector2i(109, 108)), "one paid original support carries two separately built real roof pieces")
	if not _stone(runner, world, "warm"):
		return
	var covered: RegionalSimulation = _commit_against_old_layout(runner, world, support, "demolish")
	if covered == null:
		return
	for id: String in [first, second]:
		runner.assert_eq(world.construction.projects[id].state, "removed", "removing the sole real support collapses an actual roof in the same transaction")
		runner.assert_eq(world.construction.projects[id].removed_ms, world.elapsed_ms, "roof collapse shares the support removal's exact world millisecond")
		runner.assert_eq(world.regions.home.inventory.quantity(id, "wood"), 2, "a collapsed roof leaves its finite original salvage instead of refunding heat or material twice")
	runner.assert_true(not world.construction.roofed(Vector2i(110, 108)) and covered.construction.roofed(Vector2i(110, 108)), "physical collapse removes only the changed world's actual overhead cover")
	var end: int = world.elapsed_ms + 60000
	runner.assert_true(world.advance_to_ms(end) and covered.advance_to_ms(end), "collapsed and still-supported roof layouts evolve from the same pre-collapse field")
	_assert_same_actual(runner, world, covered, "the current outdoor field does not apply roof insulation")
	var restarted: RegionalSimulation = _clone(runner, world)
	if restarted != null:
		runner.assert_eq(_state(restarted), _state(world), "actual support collapse, salvage and fixed-cell heat survive one joint JSON candidate")


func _carried_source_leaves_released_heat(runner: Object, fixture: Dictionary) -> void:
	var world: RegionalSimulation = _clone(runner, fixture.world)
	if world == null or not _operate(runner, world, fixture.door, "open"):
		return
	var control: RegionalSimulation = _clone(runner, world)
	if control == null or not _stone(runner, world, "warm"):
		return
	var origin: Vector2i = world.artifacts.object_cell("hearth_stone")
	var source: Dictionary = world.artifacts.events.back().duplicate(true)
	var charge: int = int(world.artifacts.objects.hearth_stone.charge)
	var warm_at: int = world.elapsed_ms
	if not world.advance_to_ms(warm_at + 1000) or not control.advance_to_ms(warm_at + 1000):
		runner.assert_true(false, "warming and control worlds reach the same field-response instant")
		return
	var warm: Dictionary = world.local_heat.actual_at(origin, world.elapsed_ms)
	var cold: Dictionary = control.local_heat.actual_at(origin, control.elapsed_ms)
	var available: bool = bool(warm.get("ok", false)) and bool(cold.get("ok", false))
	runner.assert_true(available, "released and control temperatures are both available at the original location")
	if available:
		runner.assert_true(float(warm.value_c) > float(cold.value_c), "the completed pulse gradually heats its original location")
	if not world.advance_to_ms(warm_at + 59999) or not control.advance_to_ms(warm_at + 60000):
		runner.assert_true(false, "pulse and baseline reach the true source-expiry boundary")
		return
	var before_expiry: Dictionary = world.local_heat.actual_at(origin, world.elapsed_ms)
	if not world.advance_to_ms(warm_at + 60000):
		runner.assert_true(false, "the temporary source expires at its real deadline")
		return
	var at_expiry: Dictionary = world.local_heat.actual_at(origin, world.elapsed_ms)
	var baseline_expiry: Dictionary = control.local_heat.actual_at(origin, control.elapsed_ms)
	available = bool(before_expiry.get("ok", false)) and bool(at_expiry.get("ok", false)) and bool(baseline_expiry.get("ok", false))
	runner.assert_true(available, "temperature remains queryable immediately before and after source expiry")
	if available:
		runner.assert_true(absf(float(at_expiry.value_c) - float(before_expiry.value_c)) < 0.01, "source expiry does not instantly reset the actual temperature")
		var residual: float = float(at_expiry.value_c) - float(baseline_expiry.value_c)
		runner.assert_true(residual > 0.0, "expired source leaves an actual temperature residual")
		if not world.advance_to_ms(warm_at + 61000) or not control.advance_to_ms(warm_at + 61000):
			runner.assert_true(false, "both worlds reach the same post-expiry instant")
			return
		var after_expiry: Dictionary = world.local_heat.actual_at(origin, world.elapsed_ms)
		var baseline_after: Dictionary = control.local_heat.actual_at(origin, control.elapsed_ms)
		var after_available: bool = bool(after_expiry.get("ok", false)) and bool(baseline_after.get("ok", false))
		runner.assert_true(after_available, "post-expiry residual and baseline remain queryable")
		if after_available:
			var later_residual: float = float(after_expiry.value_c) - float(baseline_after.value_c)
			runner.assert_true(later_residual > 0.0 and later_residual < residual, "the residual gradually decays rather than following the item")
	var bed: String = _build(runner, world, "wood_bed", Vector2i(114, 110))
	if bed.is_empty() or not world.construction.projects.has(bed):
		runner.assert_true(false, "the actual bed exists before checking its carrier")
		return
	var arrived: Vector2i = world.artifacts.object_cell("hearth_stone")
	runner.assert_true(arrived.distance_to(origin) > 2.0 and world.construction.projects[bed].state == "built", "real hauling and labor physically carry the same stone out of its earlier release patch")
	runner.assert_eq(world.artifacts.objects.hearth_stone.container, "actor:player", "carried source still references the original body's single hand-held location")
	runner.assert_eq(world.local_heat.receipts.size(), 1, "the only released heat remains tied to its one actual completed warming action")
	runner.assert_eq(world.local_heat.receipts[source.action].cell, [origin.x, origin.y], "the original source receipt stays at the actual historical release cell")
	runner.assert_eq(int(world.artifacts.objects.hearth_stone.charge), charge, "carrying the original item and building do not debit its stored charge again")
	if not control.advance_to_ms(world.elapsed_ms):
		runner.assert_true(false, "control reaches the same later shared time")
		return
	warm = world.local_heat.actual_at(origin, world.elapsed_ms)
	cold = control.local_heat.actual_at(origin, control.elapsed_ms)
	available = bool(warm.get("ok", false)) and bool(cold.get("ok", false))
	runner.assert_true(available, "original location and baseline remain queryable after the carrier leaves")
	if available:
		runner.assert_true(float(warm.value_c) > float(cold.value_c), "released heat persists locally after the temporary source expires and the carrier leaves")
	var restored: RegionalSimulation = _clone(runner, world)
	if restored != null:
		runner.assert_eq(_state(restored), _state(world), "the carried object, paid receipt and residual field jointly restore")


func _two_uses_one_charge(runner: Object) -> void:
	var world: RegionalSimulation = _artifacts._world(runner)
	if world == null or not _stone(runner, world, "study") or not _stone(runner, world, "take"):
		return
	var sim: VillageSimulation = world.regions.home
	var meal: int = sim.inventory.quantity("kitchen", "meal")
	var receipts: int = world.local_heat.receipts.size()
	for verb: String in ["warm", "heat", "warm", "heat"]:
		if not _stone(runner, world, verb):
			return
		if verb == "warm":
			receipts += 1
			runner.assert_true(world.local_heat.receipts.has(world.artifacts.events.back().action), "each actual warming action owns its one receipt")
		runner.assert_eq(world.local_heat.receipts.size(), receipts, "cooking never creates a second free warming receipt")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 0, "two actual room releases and two cooking batches compete for the same six opening charges")
	runner.assert_eq(sim.inventory.quantity("kitchen", "meal"), meal + 12, "cooking still creates exactly its two original real recipe outputs")
	runner.assert_eq(world.local_heat.receipts.size(), 2, "only actual warmed operations produce local heat receipts, not cooking events")
	runner.assert_true(not world.artifacts.begin("player", "warm", "hearth_stone").ok, "spent original storage cannot grant another warming effect")
	var before: String = _state(world)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms), "repeated same-time settlement is accepted without replaying completed work")
	runner.assert_eq(_state(world), before, "repeated settlement duplicates neither meals, charge consumption nor thermal receipts")
	var restored: RegionalSimulation = _artifacts._world(runner)
	runner.assert_true(restored.restore(JSON.parse_string(_state(world))), "cooking, warming and depleted original charge jointly restore against their actual events")
