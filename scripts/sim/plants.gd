class_name SimPlants
extends RefCounted
## Original plant bodies. Stock stays in regional inventories, support state in
## construction, and identity/control in embodiment. No per-plant Node or mind.
signal plant_changed(id: String)
const VERSION: int = 1
const NEVER: int = SimInventory.MAX_COUNT
const Rules = preload("res://scripts/sim/plants/plant_rules.gd")
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Actions = preload("res://scripts/sim/plants/plant_actions.gd")
const Codec = preload("res://scripts/sim/plants/plant_snapshot.gd")
var definitions: Dictionary = {}
var bodies: Dictionary = {}
var damage_receipts: Dictionary = {}
var last_error: String = ""
var jobs: RefCounted
var elapsed_ms: int = 0
var active: Dictionary:
	get: return jobs.active if jobs != null else {}
var _owner: WeakRef
var _index := SimParticipationIndex.new()
var _cells: Dictionary[Vector2i, Dictionary] = {}
var _supports: Dictionary = {}
var _claimed: Dictionary[Vector2i, bool] = {}
var _bound_map: WeakRef
var _bound_construction: WeakRef
var world: RegionalSimulation:
	get: return _owner.get_ref() if _owner != null else null


func initialize(authority: RegionalSimulation, rules: Dictionary) -> bool:
	if not Rules.valid_definitions(rules):
		return false
	if authority._content.environment_sources == null:
		return false
	for rule: Dictionary in rules.types.values():
		if authority._content.environment_sources.intrinsic_profile(str(rule.source)).is_empty():
			return false
	_owner = weakref(authority)
	definitions = rules
	elapsed_ms = authority.elapsed_ms
	jobs = Actions.new(self)
	return true


func bind_world(authority: RegionalSimulation) -> void:
	retire_bindings()
	_owner = weakref(authority)
	if not authority.construction.structures_changed.is_connected(_structures_changed):
		authority.construction.structures_changed.connect(_structures_changed)
	_bound_construction = weakref(authority.construction)
	if authority.map_data != null and not authority.map_data.terrain_changed.is_connected(_terrain_changed):
		authority.map_data.terrain_changed.connect(_terrain_changed)
	_bound_map = weakref(authority.map_data) if authority.map_data != null else null
	_rebuild()


func retire_bindings() -> void:
	var old_map: WorldMapData = _bound_map.get_ref() if _bound_map != null else null
	if old_map != null and old_map.terrain_changed.is_connected(_terrain_changed):
		old_map.terrain_changed.disconnect(_terrain_changed)
	var old_construction: RefCounted = _bound_construction.get_ref() if _bound_construction != null else null
	if old_construction != null and old_construction.structures_changed.is_connected(_structures_changed):
		old_construction.structures_changed.disconnect(_structures_changed)
	_bound_map = null
	_bound_construction = null


func spawn(id: String, type: String, region: String, cell: Vector2i, support: String = "", natural: bool = false, initial_age_ms: int = 0, initial_growth_ms: int = 0) -> bool:
	if id.is_empty() or bodies.has(id) or not definitions.types.has(type) or not world.regions.has(region) or world.map_data == null or not world.map_data.in_bounds(cell):
		return false
	if not support.is_empty() and (not world.construction.projects.has(support) or SimRouteTravel.cell(world.construction.projects[support].cell) != cell or region != world.construction.definitions.site.region):
		return false
	var conditions: Dictionary = habitat(cell, support)
	var rule: Dictionary = definitions.types[type]
	if initial_age_ms < 0 or initial_age_ms >= NEVER - world.elapsed_ms or initial_growth_ms < 0 or initial_growth_ms > int(rule.fruit_ms) or initial_growth_ms > initial_age_ms:
		return false
	if rule.life == "annual" and initial_age_ms >= int(rule.lifespan_ms):
		return false
	if conditions.is_empty() or not rule.substrates.has(conditions.substrate) or not _rootable(cell, support, "", bool(rule.blocks)) or natural and (int(conditions.moisture) < int(rule.water_min) or int(conditions.moisture) > int(rule.water_max)):
		return false
	var row: Dictionary = {"definition": type, "region": region, "location": {"cell": [cell.x, cell.y] if support.is_empty() else [], "support": support},
		"claimed_cells": [[cell.x, cell.y]], "initial_age_ms": initial_age_ms, "born_ms": world.elapsed_ms, "age_ms": initial_age_ms, "growth_ms": initial_growth_ms, "fruit_ms": 0, "last_ms": world.elapsed_ms,
		"next_ms": SimCadence.after(world.elapsed_ms, int(definitions.sample_ms), SimCadence.phase(id, int(definitions.sample_ms))), "hp": int(rule.max_hp), "injury_carry": 0,
		"water": int(conditions.moisture) * Rules.WATER_UNIT if support.is_empty() else 0, "water_carry": 0, "stage": "growing", "dormant": false,
		"generation": 0, "body_taken": false, "produced": {}, "subject": "", "awakened_ms": -1, "awakening_operation": "", "contacts": {}, "legacy_source": "", "conditions": conditions}
	var inventory: SimInventory = world.regions[region].inventory
	row.stage = Rules.stage(row, rule)
	if rule.life == "annual":
		row.next_ms = mini(int(row.next_ms), world.elapsed_ms + int(rule.lifespan_ms) - initial_age_ms)
	if not inventory.create_container(container_id(id), {}):
		return false
	bodies[id] = row
	if not _publish_source(id, row):
		bodies.erase(id)
		inventory.containers.erase(container_id(id))
		return false
	if not support.is_empty():
		world.construction.cultivation[support].plant = id
	_track(id)
	_notify(id)
	return true


func adopt_resource(region: String, source: String, id: String, type: String) -> bool:
	var sim: VillageSimulation = world.regions[region]
	if not sim.land_resources.sources.has(source) or not sim.land_resources.sources[source].plant_id.is_empty():
		return false
	var terms: Dictionary = sim.land_resources.terms_for(source)
	if definitions.types[type].product.item != terms.item:
		return false
	var cell: Vector2i = SimRouteTravel.cell(sim.places[sim.config.resource_sources[source].place].cell)
	var age: int = int(definitions.types[type].fruit_ms)
	if not spawn(id, type, region, cell, "", false, age, age):
		return false
	sim.inventory.containers.erase(container_id(id))
	bodies[id].legacy_source = source
	sim.land_resources.sources[source].plant_id = id
	sim.land_resources.sources[source].next_growth_ms = NEVER
	sim.land_resources.sources[source].ecology = {}
	world.invalidate_region(region)
	return true


func container_id(id: String) -> String:
	return SimLandResources.container_id(str(bodies[id].legacy_source)) if bodies.has(id) and not str(bodies[id].legacy_source).is_empty() else "plant:" + id


func cell_of(id: String) -> Vector2i:
	var location: Dictionary = bodies[id].location
	if not str(location.support).is_empty() and not world.construction.projects.has(location.support):
		return Vector2i(-1, -1)
	return SimRouteTravel.cell(world.construction.projects[location.support].cell) if not str(location.support).is_empty() else SimRouteTravel.cell(location.cell)


func ids_at(cell: Vector2i) -> Array:
	return _cells.get(cell, {}).keys()


func blocked(cell: Vector2i) -> bool:
	for id: String in _cells.get(cell, {}):
		var row: Dictionary = bodies[id]
		if bool(definitions.types[row.definition].blocks) and row.stage not in ["root", "removed", "dead"] and str(row.location.support).is_empty():
			return true
	return false


func canopy_at(cell: Vector2i) -> int:
	var result: int = 0
	for id: String in _cells.get(cell, {}):
		if bodies[id].stage not in ["root", "dead", "removed"]:
			result = maxi(result, int(definitions.types[bodies[id].definition].canopy))
	return result


func observation(id: String) -> Dictionary:
	# Qualitative facts only. The caller must enforce current sight/distance.
	if not bodies.has(id) or bodies[id].stage == "removed":
		return {"phase": "unknown"}
	var row: Dictionary = bodies[id]
	if row.hp == 0:
		return {"phase": "dormant"}
	var inventory: SimInventory = world.regions[row.region].inventory
	if inventory.quantity(container_id(id), str(definitions.types[row.definition].product.item)) > 0:
		return {"phase": "harvestable"}
	return {"phase": "dry" if _water(row) == 0 else "dormant" if row.dormant else "growing"}


func habitat(cell: Vector2i, support: String = "") -> Dictionary:
	var substrate: String
	var moisture: int
	if not support.is_empty():
		if not world.construction.has_capability(support, "cultivation") or not world.construction.cultivation.has(support):
			return {}
		var pot: Dictionary = world.construction.cultivation[support]
		substrate = pot.substrate
		moisture = int(pot.water) / Rules.WATER_UNIT
	else:
		var natural: Dictionary = world.map_data.natural_cell(cell)
		if natural.is_empty():
			return {}
		substrate = "water" if world.map_data.get_terrain(cell) == WorldMapData.TERRAIN_WATER else "stone" if world.map_data.get_terrain(cell) == WorldMapData.TERRAIN_ROCK else "sand" if natural.surface_id == "gravel" else "soil"
		moisture = int(natural.moisture_potential)
	var weather: Dictionary = SimClimateRules.background_at(world._content.climate, world.weather.definitions, world.weather.epoch_ms, cell, world.elapsed_ms)
	var temperature: int = int(weather.temperature_tenths)
	if world.environment_fields != null:
		var actual: Dictionary = world.environment_fields.actual_at(cell, world.elapsed_ms)
		if not bool(actual.get("ok", false)):
			return {}
		temperature = roundi(float(actual.value_c) * 10.0)
	var light: Dictionary = SimLocalLight.at_simulation_cell(world, cell)
	if not bool(light.get("supported", false)):
		return {}
	var date: Dictionary = SimWorldCalendar.date_at(world._content.climate.calendar, world.elapsed_ms)
	return {"substrate": substrate, "moisture": moisture, "temperature": temperature, "rain": weather.kind == "rain", "season": date.season, "light": int(light.total_relative)}


func _rootable(cell: Vector2i, support: String, except_id: String = "", solid: bool = false) -> bool:
	if not support.is_empty():
		return world.construction.has_capability(support, "cultivation") and world.construction.cultivation.has(support) and str(world.construction.cultivation[support].plant) in ["", except_id]
	for id: String in ids_at(cell):
		if id != except_id and bodies[id].stage != "removed" and (solid or bool(definitions.types[bodies[id].definition].blocks)):
			return false
	return world.construction.project_at(cell).is_empty() and (not solid or not _occupied(cell) and not SimMotionClearance.fixed_road_reserves(world, cell))


func next_boundary_ms() -> int:
	return mini(_index.next_due_ms(&"plants", NEVER), jobs.next_boundary_ms())


func settle_at_ms(now: int) -> bool:
	if now < elapsed_ms:
		return false
	elapsed_ms = now
	for id: String in _index.due_ids(&"plants", now):
		if not _settle_body(id, now):
			return false
	return true


func settle_budgeted(now: int, budget: int) -> Vector2i:
	if now < elapsed_ms or budget < 1:
		return Vector2i(0, SimSettlementKernel.Status.FAILED)
	elapsed_ms = now
	var ids: Array[String] = _index.due_ids(&"plants", now, budget)
	for id: String in ids:
		if not _settle_body(id, now):
			return Vector2i(1, SimSettlementKernel.Status.FAILED)
	return Vector2i(maxi(1, ids.size()), SimSettlementKernel.Status.PENDING if _index.next_due_ms(&"plants", NEVER) <= now else SimSettlementKernel.Status.COMPLETE)


func _water(row: Dictionary) -> int:
	return int(row.water) if str(row.location.support).is_empty() else int(world.construction.cultivation[row.location.support].water)


func _settle_body(id: String, now: int, refresh_conditions: bool = true) -> bool:
	var row: Dictionary = bodies[id].duplicate(true)
	var rule: Dictionary = definitions.types[row.definition]
	var dt: int = now - int(row.last_ms)
	var old_stage: String = str(row.stage)
	var old_dormant: bool = bool(row.dormant)
	if dt < 0:
		return false
	row.age_ms = int(row.age_ms) + dt
	var water: int = _water(row)
	var growing: bool = Rules.growing(row, rule, row.conditions, water)
	if row.stage == "root" and bool(rule.blocks) and _occupied(cell_of(id)):
		growing = false
	var unsafe: bool = int(row.conditions.temperature) < int(rule.temperature[2]) or int(row.conditions.temperature) > int(rule.temperature[3]) or not rule.substrates.has(row.conditions.substrate) or water == 0
	if unsafe:
		row.injury_carry = int(row.injury_carry) + dt
		@warning_ignore("integer_division")
		var damage: int = int(row.injury_carry) / int(rule.injury_ms)
		row.injury_carry = int(row.injury_carry) % int(rule.injury_ms)
		row.hp = maxi(0, int(row.hp) - damage)
	if rule.life == "annual" and int(row.age_ms) >= int(rule.lifespan_ms):
		row.hp = 0
	if growing:
		if row.stage == "root" and bool(rule.regrow):
			row.stage = "growing"
			row.body_taken = false
		row.fruit_ms = int(row.fruit_ms) + maxi(0, int(row.growth_ms) + dt - int(rule.fruit_ms))
		row.growth_ms = mini(int(rule.fruit_ms), int(row.growth_ms) + dt)
	row.dormant = not growing
	row.last_ms = now
	row.stage = Rules.stage(row, rule)
	var gain: int = 0
	var inventory: SimInventory = world.regions[row.region].inventory
	if row.stage == "fruiting" and int(row.fruit_ms) >= int(rule.product.period_ms):
		@warning_ignore("integer_division")
		var periods: int = int(row.fruit_ms) / int(rule.product.period_ms)
		gain = mini(periods, int(rule.product.capacity) - inventory.quantity(container_id(id), str(rule.product.item)))
		row.fruit_ms = int(row.fruit_ms) % int(rule.product.period_ms)
	if row.stage in ["dead", "removed"]:
		row.fruit_ms = 0
	# Water is a finite local reserve, independent of habitat potential. Rain
	# refills only exposed roots; aquatic substrate stays supplied by its water.
	var depletion: int = int(row.water_carry) + dt
	@warning_ignore("integer_division")
	var next_water: int = clampi(water + (dt * 2 if bool(row.conditions.rain) and not world.construction.roofed(cell_of(id)) else -depletion / 100), 0, 100 * Rules.WATER_UNIT)
	row.water_carry = depletion % 100
	if row.conditions.substrate == "water":
		next_water = 100 * Rules.WATER_UNIT
	if str(row.location.support).is_empty():
		row.water = next_water
	if refresh_conditions:
		row.conditions = habitat(cell_of(id), str(row.location.support))
		if row.conditions.is_empty():
			return false
	row.next_ms = NEVER if row.stage in ["dead", "removed"] else SimCadence.after(now, int(definitions.sample_ms), SimCadence.phase(id, int(definitions.sample_ms)))
	if rule.life == "annual" and row.hp > 0 and row.stage != "removed":
		row.next_ms = mini(int(row.next_ms), int(row.born_ms) + int(rule.lifespan_ms) - int(row.initial_age_ms))
	if not _publish_source(id, row):
		return false
	if not str(row.location.support).is_empty():
		var terms: Dictionary = world.construction.definitions.types[world.construction.projects[row.location.support].type].capabilities.cultivation
		world.construction.cultivation[row.location.support].water = mini(int(terms.water_capacity), next_water)
	if gain > 0:
		var item: String = str(rule.product.item)
		inventory.containers[container_id(id)][item] = inventory.quantity(container_id(id), item) + gain
		inventory.contents_changed.emit(container_id(id))
		row.produced[item] = int(row.produced.get(item, 0)) + gain
		if not str(row.legacy_source).is_empty():
			world.regions[row.region].land_resources.sources[row.legacy_source].produced += gain
	bodies[id] = row
	_track(id)
	if old_stage != row.stage or old_dormant != row.dormant or gain > 0:
		_notify(id)
	return true


func _occupied(cell: Vector2i) -> bool:
	for sim: VillageSimulation in world.regions.values():
		for body: Dictionary in sim.synchronize_actors().values():
			if bool(body.alive) and SimRouteTravel.cell(body.cell) == cell:
				return true
	return world.large_bodies.blocked(cell) or SimMotionClearance.active_segment_reserves(world, cell)


func _track(id: String) -> void:
	var row: Dictionary = bodies[id]
	for raw: Array in row.claimed_cells:
		_claimed[SimRouteTravel.cell(raw)] = true
	_index.set_member(&"plants", id, row.stage not in ["dead", "removed"])
	if row.stage not in ["dead", "removed"]:
		_index.set_due(&"plants", id, int(row.next_ms))
	if row.stage != "removed":
		var cell: Vector2i = cell_of(id)
		if not _cells.has(cell):
			_cells[cell] = {}
		_cells[cell][id] = true
		if not str(row.location.support).is_empty():
			_supports[row.location.support] = id


func _forget(id: String) -> void:
	var row: Dictionary = bodies[id]
	var cell: Vector2i = cell_of(id)
	if _cells.has(cell):
		_cells[cell].erase(id)
		if _cells[cell].is_empty():
			_cells.erase(cell)
	if not str(row.location.support).is_empty():
		_supports.erase(row.location.support)
	_index.set_member(&"plants", id, false)


func _rebuild() -> void:
	_index = SimParticipationIndex.new()
	_cells.clear()
	_supports.clear()
	_claimed.clear()
	for id: String in bodies:
		_track(id)


func source_for(id: String, row: Dictionary = {}) -> Dictionary:
	if row.is_empty():
		row = bodies[id]
	var source: Dictionary = world._content.environment_sources.intrinsic_profile(str(definitions.types[row.definition].source))
	if row.stage in ["dead", "removed", "root"] or source.is_empty() or not str(row.location.support).is_empty() and not world.construction.projects.has(row.location.support):
		return {}
	var cell: Vector2i = SimRouteTravel.cell(world.construction.projects[row.location.support].cell) if not str(row.location.support).is_empty() else SimRouteTravel.cell(row.location.cell)
	var channels: PackedInt32Array = SimEnvironmentFieldRules.source_to_packed_channels(source.elements, int(source.thermal_grade))
	return {"cell": cell, "radius": int(source.radius_cells), "channels": channels}


func _publish_source(id: String, row: Dictionary) -> bool:
	if not world.environment_fields is SimWorldEnvironmentFields or not world.environment_fields._active:
		return true
	return world.environment_fields.replace_domain_source("plant:" + id, source_for(id, row), world.elapsed_ms)


func _structures_changed(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		for id: String in ids_at(cell):
			var support: String = str(bodies[id].location.support)
			if support.is_empty() or world.construction.has_capability(support, "cultivation"):
				if not _settle_body(id, world.elapsed_ms):
					world.errors.append("Plant structure response failed")
				else:
					jobs.reconcile_target(id)
				continue
			# The old interval has settled. Keep the original body and give it an
			# explicit damaged ground result when its physical support is lost.
			if not _settle_body(id, world.elapsed_ms, false):
				world.errors.append("Plant lost-support interval failed")
				continue
			_forget(id)
			bodies[id].location = {"cell": [cell.x, cell.y], "support": ""}
			bodies[id].hp = maxi(0, int(bodies[id].hp) / 2)
			if bodies[id].hp == 0:
				bodies[id].stage = "dead"
				bodies[id].next_ms = NEVER
			bodies[id].conditions = habitat(cell)
			world.construction.cultivation[support].plant = ""
			if not _publish_source(id, bodies[id]):
				world.errors.append("Plant support source response failed")
			_track(id)
			_notify(id)
			jobs.reconcile_target(id)


func _terrain_changed(cells: Array[Vector2i]) -> void:
	for cell: Vector2i in cells:
		for id: String in ids_at(cell):
			if not _settle_body(id, world.elapsed_ms):
				world.errors.append("Plant terrain response failed")
			else:
				jobs.reconcile_target(id)


func subject_ids() -> Array:
	var result: Array = []
	for id: String in bodies:
		if not str(bodies[id].subject).is_empty():
			result.append(id)
	return result


func awaken(id: String, operation: String) -> bool:
	if operation.is_empty() or not bodies.has(id) or not bool(definitions.types[bodies[id].definition].sapient) or bodies[id].stage in ["dead", "removed"]:
		return false
	if not str(bodies[id].subject).is_empty():
		return bodies[id].awakening_operation == operation
	var subject: String = "subject:plant:" + id
	var carrier: String = "body:plant:" + id
	var channels: Array[String] = ["communication"]
	if not world.embodiment.bind_new_creature(subject, carrier, "rooted_plant", {"kind": "plant", "id": id}, channels):
		return false
	bodies[id].subject = subject
	bodies[id].awakened_ms = world.elapsed_ms
	bodies[id].awakening_operation = operation
	bodies[id].contacts = {} # No pre-awakening memories are invented.
	_notify(id)
	jobs.reconcile_target(id)
	return true


func previous_autonomy(actor: String) -> bool:
	return bool(active.get(actor, {}).get("previous_autonomous", false))


func cancel(actor: String) -> bool:
	return jobs.cancel(actor)


func communicate(actor: String, id: String, request: String) -> Dictionary:
	if not world.accepts_commands() or world.elapsed_ms != world.target_ms or not bodies.has(id) or str(bodies[id].subject).is_empty() or bodies[id].stage in ["dead", "removed"]:
		return {"ok": false, "reason": "no_response"}
	var row: Dictionary = bodies[id]
	if not world.regions[row.region].has_actor(actor) or not world.actor_controls(actor, "communication") or SimRouteTravel.point(world.regions[row.region].synchronize_actor(actor)).distance_to(TileGrid.cell_to_world(cell_of(id))) > 3.0 * TileGrid.TILE_SIZE:
		return {"ok": false, "reason": "out_of_reach"}
	row.contacts[actor] = {"at_ms": world.elapsed_ms, "consent": request == "ask_harvest"}
	return {"ok": true, "reason": "accepted" if request == "ask_harvest" else "refused", "line": "枝叶微动：可取熟果，请勿伤根。" if request == "ask_harvest" else "枝叶收拢，未应允此事。"}


func damage(id: String, amount: int, operation: String) -> bool:
	var request: Dictionary = {"plant": id, "amount": amount}
	if damage_receipts.has(operation):
		return damage_receipts[operation] == request
	if operation.is_empty() or amount < 1 or not bodies.has(id) or not world.accepts_commands() or bodies[id].stage in ["dead", "removed"] or not _settle_body(id, world.elapsed_ms):
		return false
	var candidate: Dictionary = bodies[id].duplicate(true)
	candidate.hp = maxi(0, int(candidate.hp) - amount)
	if candidate.hp == 0:
		candidate.stage = "dead"
		candidate.next_ms = NEVER
	if not _publish_source(id, candidate):
		return false
	_forget(id)
	bodies[id] = candidate
	damage_receipts[operation] = request
	_track(id)
	_notify(id)
	jobs.reconcile_target(id)
	return true


func owns_actor(actor: String) -> bool:
	return jobs.active.has(actor)


func to_dict() -> Dictionary:
	return {"version": VERSION, "elapsed_ms": elapsed_ms, "bodies": bodies.duplicate(true), "damage_receipts": damage_receipts.duplicate(true), "jobs": jobs.to_dict()}


func restore(data: Dictionary) -> bool:
	return Codec.restore(self, data)


func cross_valid() -> bool:
	return Codec.cross_valid(self)


func _notify(id: String) -> void:
	if world.world_events != null:
		world.world_events.notify("plant:" + id, world.elapsed_ms)
	plant_changed.emit(id)


func overrides_flora(cell: Vector2i) -> bool:
	return _claimed.has(cell)


func spawn_opening(center: Vector2i) -> bool:
	var scenario: Dictionary = world._content.plant_scenario
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		for source: String in sim.land_resources.sources:
			var type: String = str(sim.config.resource_sources[source].definition)
			if scenario.adopt_sources.has(type) and not adopt_resource(region, source, "source:" + region + ":" + source, str(scenario.adopt_sources[type])):
				last_error = "source:" + region + ":" + source
				return false
	for sample: Dictionary in scenario.samples:
		var placed: bool = false
		for radius: int in range(2, 10):
			for direction: Vector2i in [Vector2i.LEFT, Vector2i.UP, Vector2i.RIGHT, Vector2i.DOWN]:
				var cell: Vector2i = center + direction * radius
				if not world.map_data.in_bounds(cell) or _occupied(cell):
					continue
				if spawn(str(sample.id), str(sample.definition), "home", cell, "", bool(sample.get("natural", false)), int(sample.get("age_ms", 0)), int(sample.get("growth_ms", 0))):
					placed = true
					break
			if placed:
				break
		if not placed:
			last_error = "sample:" + str(sample.id)
			return false
		if bool(definitions.types[sample.definition].sapient) and not world.world_events.enqueue("awakening:" + str(sample.id), "plant_awakening", world.elapsed_ms + 60000, {"plant": sample.id}, {"topics": ["plant:" + str(sample.id)]}):
			return false
	return true
