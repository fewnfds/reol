extends RefCounted
## Original regional owners, configured before enabling the new source. These
## fixtures never fabricate completed artifact/spirit effects or old archives.

const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")


static func rules() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/spirit_sources.json"))


static func canonical(value: Variant) -> String:
	return JSON.stringify(VillageRuntime._json_normalized(value), "", true, true)


static func make(runner: Object, options: Dictionary = {}) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "spirit fixture loads original content: " + str(content.errors))
		return null
	content.spirit_sources = options.get("rules", rules()).duplicate(true)
	if options.has("opening_charge"):
		content.artifacts.types.warm_stone.opening_charge = int(options.opening_charge)
	if options.has("max_qi"):
		content.get_pawn(&"player").max_qi = int(options.max_qi)
	var fixture: RefCounted = RegionalFixtures.new()
	var regions: Dictionary = {}
	var at_ms: int = int(options.get("at_ms", 0))
	for id: String in ["home", "river"]:
		var village: VillageSimulation = fixture._make_village(content, id, false)
		if village == null:
			runner.assert_true(false, "spirit fixture initializes original village: " + id)
			return null
		if at_ms > 0:
			var cells: Dictionary = {}
			for actor: String in village.actors:
				cells[actor] = village.actors[actor].cell.duplicate()
			if not village.initialize(content, village.config, cells, village.places, at_ms):
				runner.assert_true(false, "nonzero spirit fixture initializes every original source at its actual opening")
				return null
		village.set_navigation(path)
		if id == "home":
			for actor: String in options.get("profiles", {}):
				for field: String in options.profiles[actor]:
					village.config.actor_profiles[actor][field] = options.profiles[actor][field]
					if village.actors[actor].has(field):
						village.actors[actor][field] = options.profiles[actor][field]
		regions[id] = village
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	var world := RegionalSimulation.new()
	if not world.initialize(settings, regions, content):
		runner.assert_true(false, "spirit fixture binds original regional owners: " + str(world.errors))
		return null
	if bool(options.get("services", false)):
		var service_rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SettlementServicesRuntime.DEFINITIONS_PATH))
		if not world.configure_services(service_rules):
			runner.assert_true(false, "autonomous spirit fixture binds the existing actual social-service decision authority")
			return null
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	if bool(options.get("known", true)):
		opening.experiences["subject:player"] = ["stone_handling"]
	if bool(options.get("second_stone", false)):
		opening.objects.append({"id": "second_stone", "definition": "warm_stone", "region": "home", "container": "kitchen"})
	if not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "spirit fixture registers the original unique stone instances")
		return null
	for actor: String in world.regions.home.actors:
		world.regions.home.set_actor_cell(actor, SimRouteTravel.cell(world.regions.home.places.kitchen.cell))
	# Deliberately configured starting reserves, before any source baseline or
	# earned effect exists. Other tests deplete reserves through real actions.
	for actor: String in options.get("qi", {}):
		world.regions.home.actors[actor].qi = int(options.qi[actor])
	world.invalidate_region("home")
	world.set_active_region("")
	return world


static func path(from_cell: Vector2i, to_cell: Vector2i) -> Array[Vector2i]:
	# A static callable survives after make's temporary fixture is released.
	var result: Array[Vector2i] = [from_cell]
	var cursor: Vector2i = from_cell
	while cursor.x != to_cell.x:
		cursor.x += 1 if cursor.x < to_cell.x else -1
		result.append(cursor)
	while cursor.y != to_cell.y:
		cursor.y += 1 if cursor.y < to_cell.y else -1
		result.append(cursor)
	return result


static func artifact(runner: Object, world: RegionalSimulation, actor: String, verb: String, object_id: String = "hearth_stone") -> String:
	var answer: Dictionary = world.artifacts.begin(actor, verb, object_id)
	runner.assert_true(bool(answer.ok), "original artifact action begins: %s/%s/%s: %s" % [actor, verb, object_id, str(answer.line)])
	if not bool(answer.ok):
		return ""
	var id: String = str(world.artifacts.active[actor].id)
	runner.assert_true(world.advance_to_ms(int(world.artifacts.active[actor].due_ms)), "original artifact action reaches its real completion: " + verb)
	return id


static func finish(runner: Object, world: RegionalSimulation, actor: String = "player") -> String:
	if not world.spirit_sources.active.has(actor):
		runner.assert_true(false, "spirit completion requires a genuinely active original body")
		return ""
	var id: String = str(world.spirit_sources.active[actor].id)
	runner.assert_true(world.advance_to_ms(int(world.spirit_sources.active[actor].due_ms)), "source operation reaches its original shared-time deadline")
	return id


static func valid_restore(runner: Object, world: RegionalSimulation, options: Dictionary = {}) -> RegionalSimulation:
	var restored: RegionalSimulation = make(runner, options)
	if restored == null:
		return null
	if not restored.restore(JSON.parse_string(canonical(world.to_dict()))):
		runner.assert_true(false, "complete source, original body and artifact restore independently")
		return null
	return restored
