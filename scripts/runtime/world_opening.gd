class_name WorldOpening
extends RefCounted
## New-game scenario assembly only. Loading restores saved facts through
## WorldSessionSnapshot and never reissues this inventory, roster or history.

const SETTINGS_PATH: String = "res://data/scenarios/world_continuity.json"
const REMOTE_PREFIX: String = "river_"
const ARTIFACT_SCENARIO_PATH: String = "res://data/scenarios/artifacts.json"
const AVIAN_SCENARIO_PATH: String = "res://data/scenarios/avian_life.json"
const SOUL_SCENARIO_PATH: String = "res://data/scenarios/soul_vessels.json"

static func assemble(adapter: Node, home: VillageRuntime, opening_source_loan: bool, opening_source_care: bool, opening_field: bool) -> bool:
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
	if not raw is Dictionary:
		return false
	adapter.settings = raw
	var origin: Vector2i = home._player.cell
	adapter.centers["home"] = origin
	var reachable: Array[Vector2i] = VillageRuntime.find_reachable_cells(
		home._world, origin, int(adapter.settings.runtime.layout_radius), int(adapter.settings.runtime.layout_budget)
	)
	var desired: Vector2i = origin + _cell(adapter.settings.regions.river.offset)
	var best: Vector2i = origin
	var best_distance: int = 9223372036854775807
	for cell: Vector2i in reachable:
		if cell.distance_to(origin) < float(adapter.settings.runtime.minimum_separation):
			continue
		var distance: int = (cell - desired).length_squared()
		if distance < best_distance:
			best = cell
			best_distance = distance
	if best == origin:
		push_error("World continuity: no connected second settlement")
		return false
	adapter.centers["river"] = best
	var remote: VillageSimulation = _create_remote(home, adapter.settings, best, reachable)
	if remote == null:
		push_error("World continuity: remote settlement initialization failed")
		return false
	var route: Dictionary = adapter.settings.routes.river_road
	var road: Array[Vector2i] = VillageRuntime.find_grid_path(home._world,
		_cell(remote.places[route.source].cell), _cell(home.simulation.places[route.target].cell),
		int(adapter.settings.runtime.layout_radius), int(adapter.settings.runtime.layout_budget))
	if road.size() < 2:
		push_error("World continuity: settlement warehouses have no connected route")
		return false
	var route_cells: Array = []
	for cell: Vector2i in road:
		route_cells.append([cell.x, cell.y])
	route.path = route_cells
	route.travel_minutes = maxi(int(route.travel_minutes), (road.size() - 1) * int(home._config.move_minutes_per_cell))
	adapter.world_sim = RegionalSimulation.new()
	if not adapter.world_sim.initialize(adapter.settings, {"home": home.simulation, "river": remote}, home._content):
		push_error("World continuity: regional definitions rejected: %s" % str(adapter.world_sim.errors))
		adapter.world_sim = null
		return false
	adapter.world_sim.bind_map_data(home._world.map_data())
	home.continuity = adapter
	var service_definitions: Dictionary = home._content.settlement_services
	if not service_definitions is Dictionary or not adapter.world_sim.configure_services(service_definitions):
		push_error("World continuity: service definitions rejected")
		return false
	var artifact_scenario: Variant = JSON.parse_string(FileAccess.get_file_as_string(ARTIFACT_SCENARIO_PATH))
	if artifact_scenario is Dictionary and home.simulation.config.has("workplaces_version"):
		artifact_scenario.objects.append({"id": "training_sword", "definition": "wooden_sword", "region": "home", "container": "dorm"})
		artifact_scenario.objects.append({"id": "river_training_sword", "definition": "wooden_sword", "region": "river", "container": "actor:river_chen_shouzhuo"})
	if not artifact_scenario is Dictionary or not adapter.world_sim.artifacts.spawn_opening(artifact_scenario):
		push_error("World continuity: artifact scenario rejected")
		return false
	# A new opening explicitly installs this local arrangement. Loading a saved
	# world restores its own empty or populated affairs and never runs this again.
	if opening_source_loan:
		var source_loan_opening: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/source_loan.json"))
		if not source_loan_opening is Dictionary or not adapter.world_sim.site_affairs.spawn_opening(source_loan_opening):
			push_error("World continuity: source-loan opening rejected")
			return false
	if opening_source_care:
		var source_care_opening: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/source_care.json"))
		if not source_care_opening is Dictionary or not adapter.world_sim.source_care.spawn_opening(source_care_opening):
			push_error("World continuity: source-care opening rejected")
			return false
	var avian_scenario: Variant = JSON.parse_string(FileAccess.get_file_as_string(AVIAN_SCENARIO_PATH))
	if not avian_scenario is Dictionary:
		return false
	if home.simulation.config.has("workplaces_version"):
		var flock_scenario: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/wildlife_flocks.json"))
		if not flock_scenario is Dictionary:
			return false
		avian_scenario = AvianHabitatPlacement.assemble(avian_scenario, adapter.centers, adapter.world_sim.map_data, flock_scenario, adapter._opening_ground_open)
		if avian_scenario.is_empty():
			return false
	# Ground food sites use actual accessible terrain. Perches/crevices remain
	# elevated small-body places, not new walkable terrain tiles.
	for region: String in avian_scenario.regions:
		for row: Dictionary in avian_scenario.regions[region].sites.values():
			if row.type == "seeds":
				var origin_cell: Vector2i = adapter.centers[region]
				var adjusted: Vector2i = home._world.find_walkable_near(origin_cell + _cell(row.offset), 5) - origin_cell
				row.offset = [adjusted.x, adjusted.y]
	if not adapter.world_sim.avian_life.spawn_opening(avian_scenario, adapter.centers):
		push_error("World continuity: avian scenario rejected")
		return false
	var soul_scenario: Variant = JSON.parse_string(FileAccess.get_file_as_string(SOUL_SCENARIO_PATH))
	if not soul_scenario is Dictionary or not adapter.world_sim.soul_vessels.spawn_opening(soul_scenario):
		push_error("World continuity: soul vessel scenario rejected")
		return false
	if not LargeBodiesRuntime.assemble(adapter):
		push_error("World continuity: no clear large-body territory")
		return false
	if adapter.world_sim.elapsed_ms == 0 and not adapter.world_sim.clothing.spawn_opening():
		push_error("World continuity: clothing scenario rejected")
		return false
	# Starting money is scenario content, never minted by a service command.
	for actor_id: String in adapter.settings.runtime.starting_inventory:
		for item: String in adapter.settings.runtime.starting_inventory[actor_id]:
			home.simulation.inventory.containers["actor:" + actor_id][item] = int(adapter.settings.runtime.starting_inventory[actor_id][item])
	if opening_field and adapter.world_sim.elapsed_ms == 0 and not adapter.world_sim.field_opportunities.spawn_opening(adapter.centers):
		push_error("World continuity: no reachable field opportunity opening")
		return false
	if not adapter.world_sim.plants.spawn_opening(origin):
		push_error("World continuity: plant scenario rejected: " + adapter.world_sim.plants.last_error)
		return false
	if not adapter.world_sim.environment_fields.activate_sources():
		push_error("World continuity: environmental sources could not activate")
		return false
	return true


static func _create_remote(home: VillageRuntime, settings: Dictionary, origin: Vector2i, reachable: Array[Vector2i]) -> VillageSimulation:
	var config: Dictionary = home._config.duplicate(true)
	config.seed = int(config.seed) + int(settings.runtime.remote_seed_offset)
	config.controlled_actor = REMOTE_PREFIX + "player"
	config.autonomous_controller = true
	var profiles: Dictionary = {}
	var cells: Dictionary = {}
	var used: Dictionary = {}
	for original: String in config.actor_profiles:
		var id: String = REMOTE_PREFIX + original
		var profile: Dictionary = config.actor_profiles[original].duplicate(true)
		profile.definition_id = str(profile.get("definition_id", original))
		profile.autonomous = true
		profiles[id] = profile
		var placed: Vector2i = _nearest_unused(origin, reachable, used)
		if placed.x < 0:
			return null
		cells[id] = [placed.x, placed.y]
		used[placed] = true
	config.actor_profiles = profiles
	for office: Dictionary in config.institution.offices.values():
		office.holder = REMOTE_PREFIX + str(office.holder)
	config.institution.id = "river_sect"
	config.scenario.requester = REMOTE_PREFIX + str(config.scenario.requester)
	var helpers: Array = []
	for id: String in config.scenario.helpers:
		helpers.append(REMOTE_PREFIX + id)
	config.scenario.helpers = helpers
	# Each village starts with real stock. The first needs help; the second has
	# a surplus, but keeps a reserve for its own inhabitants.
	for region: String in ["home", "river"]:
		var stock: Dictionary = settings.regions[region].stock_overrides
		for container: String in stock:
			var destination: Dictionary = config.initial_stock[container] if region == "river" else home.simulation.inventory.containers[container]
			for item: String in stock[container]:
				destination[item] = stock[container][item]
	var places: Dictionary = {}
	for definition: Dictionary in config.place_defs:
		var target: Vector2i = origin + _cell(definition.offset)
		var placed: Vector2i = _nearest_unused(target, reachable, used)
		if placed.x < 0:
			return null
		used[placed] = true
		places[definition.id] = {"cell": [placed.x, placed.y], "label": str(definition.label)}
	if config.has("workplaces_version"):
		if not SimWorkplaces.attach_opening_layout(places, cells, home._world.map_data(), str(config.institution.id), home._content.workplaces):
			# The remote opening has its own terrain; find a real room footprint.
			var initial: Array = places.records.cell.duplicate()
			var desired: Vector2i = _cell(initial)
			var ordered: Array[Vector2i] = reachable.duplicate()
			ordered.sort_custom(func(a: Vector2i, b: Vector2i) -> bool: return (a - desired).length_squared() < (b - desired).length_squared())
			var assembled: bool = false
			for cell: Vector2i in ordered:
				if cell.distance_to(desired) > 12.0:
					break
				if used.has(cell):
					continue
				places.records.cell = [cell.x, cell.y]
				if SimWorkplaces.attach_opening_layout(places, cells, home._world.map_data(), str(config.institution.id), home._content.workplaces):
					assembled = true
					break
			if not assembled:
				return null
	var result := VillageSimulation.new()
	# New optional definition fields added with dot syntax may be StringName
	# keys; definitions use the same JSON-only boundary as saved state.
	config = SnapshotValues.for_save(config)
	places = SnapshotValues.for_save(places)
	if not result.initialize(home._content, config, cells, places, home.simulation.elapsed_ms):
		push_error("World continuity: remote configuration rejected: %s" % str(result.errors))
		return null
	return result


static func _nearest_unused(desired: Vector2i, candidates: Array[Vector2i], used: Dictionary) -> Vector2i:
	var result := Vector2i(-1, -1)
	var best: int = 9223372036854775807
	for cell: Vector2i in candidates:
		if used.has(cell):
			continue
		var distance: int = (cell - desired).length_squared()
		if distance < best:
			best = distance
			result = cell
	return result


static func _cell(raw: Array) -> Vector2i:
	return Vector2i(int(raw[0]), int(raw[1]))
