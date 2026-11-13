extends RefCounted
## Current-format domain state. Domain field lists live with their owners;
## runtime caches, display frames, locks, Callables and engine objects are rebuilt.

const World = preload("res://scripts/sim/kernel/world.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Equipment = preload("res://scripts/sim/kernel/equipment.gd")


static func capture(world: RefCounted) -> Dictionary:
	var result: Dictionary = {"domains": {}, "pages": []}
	for key: String in world.state_owners():
		var owner: RefCounted = world.state_owners()[key]
		result.domains[key] = State.capture(owner, owner.STATE_FIELDS)
	for page: RefCounted in world.pages:
		result.pages.append(State.capture(page, Units.STATE_FIELDS))
	return result


static func candidate(data: Dictionary, workers: int) -> RefCounted:
	if not data.get("domains") is Dictionary or not data.get("pages") is Array:
		return null
	var world := World.new()
	var owners: Dictionary = world.state_owners()
	for key: String in owners:
		if not data.domains.get(key) is Dictionary or not State.matches(owners[key], owners[key].STATE_FIELDS, data.domains[key]):
			return null
	for members: Variant in data.domains.terrain.room_cells:
		if not members is PackedInt32Array:
			return null
	for key: String in owners:
		State.apply(owners[key], owners[key].STATE_FIELDS, data.domains[key])
	if not _terrain_valid(world.terrain) or world.elapsed_ms < 0 or world.elapsed_ms % 50 != 0:
		return null
	if not _objects_valid(world):
		return null
	var slot: int = 0
	for value: Variant in data.pages:
		var page := Units.new()
		if not value is Dictionary or not State.matches(page, Units.STATE_FIELDS, value):
			return null
		# Validate typed routes before Array.assign; malformed files cannot assert.
		for route: Variant in value.routes:
			if not route is PackedVector2Array:
				return null
		State.apply(page, Units.STATE_FIELDS, value)
		page.cargo.resize(page.ids.size())
		page.potions.resize(page.ids.size())
		if not _page_valid(page, world, slot):
			return null
		page.terrain = world.terrain
		page.environment = world.environment
		world.pages.append(page)
		slot += page.ids.size()
	if slot == 0 or slot > 60000 or world.attack_due.size() != slot or world.actor_slots.size() != world.actor_count:
		return null
	for id: int in world.actor_slots:
		Equipment.rebuild(world, id, false)
		var body_slot: int = world.actor_slots[id]
		if world.pages[body_slot / 256].health[body_slot % 256] > world.pages[body_slot / 256].max_health[body_slot % 256]: return null
	for index: int in range(0, world.pages.size() - 1):
		if world.pages[index].ids.size() != Units.PAGE_SIZE:
			return null
	if not _processes_valid(world):
		return null
	var environment: RefCounted = world.environment
	if not _environment_valid(environment, world):
		return null
	environment.terrain = world.terrain
	environment.field.resize(world.terrain.SIZE * world.terrain.SIZE * environment.CHANNELS)
	environment.heads.resize(environment.BUCKETS * environment.BUCKETS)
	environment.mobile_cells.resize(environment.mobile_units.size())
	environment.links.resize(environment.mobile_units.size())
	environment.rebuild_static()
	environment.index_mobile(world.pages, world.actor_slots)
	if not world.nature.rebuild(world) or not world.combat.valid(world):
		return null
	if not world.regions.valid(world):
		return null
	if not world.person_events.rebuild(world.elapsed_ms):
		return null
	if not world.perception.rebuild(world):
		return null
	world.configure_lanes(workers)
	return world


static func _terrain_valid(terrain: RefCounted) -> bool:
	var size: int = terrain.SIZE * terrain.SIZE
	if terrain.blocked.size() != size or terrain.enclosures.size() != size or terrain.rooms.size() != size:
		return false
	if terrain.base.size() != size or terrain.cover.size() != size or terrain.flooring.size() != size:
		return false
	for tile: int in size:
		if terrain.base[tile] < 1 or terrain.base[tile] > 3 or terrain.cover[tile] > 1 or terrain.flooring[tile] > 1:
			return false
	for members: Variant in terrain.room_cells:
		if not members is PackedInt32Array or members.is_empty():
			return false
		for tile: int in members:
			if tile < 0 or tile >= size:
				return false
	for cells: PackedInt32Array in [terrain.resources, terrain.depots, terrain.structures, terrain.source_cells]:
		for tile: int in cells:
			if tile < 0 or tile >= size:
				return false
	if terrain.resources.is_empty() or terrain.depots.is_empty():
		return false
	for room: int in terrain.rooms:
		if room < -1 or room >= terrain.room_cells.size():
			return false
	return true


static func _objects_valid(world: RefCounted) -> bool:
	for id: Variant in world.objects.records:
		var record: Variant = world.objects.records[id]
		if not id is int or id <= 0 or id >= world.objects.next_id or not record is Dictionary:
			return false
		if record.get("id") != id or not record.get("kind") is String or not record.get("definition") is String or not record.get("inventory") is Dictionary or not record.get("capacity") is int or not record.get("tile") is int:
			return false
		if record.kind != "actor" and not record.get("hp") is int:
			return false
		var tile: int = record.tile
		if tile < -1 or tile >= world.terrain.blocked.size():
			return false
		if record.kind == "actor" and tile != -1:
			return false
		if record.kind == "actor":
			if not Equipment.valid_record(record): return false
			for equipped: String in record.equipment.values():
				world.objects.totals[equipped] = int(world.objects.totals.get(equipped, 0)) + 1
		if record.has("facing") and (not record.facing is int or record.facing < 0 or record.facing > 3):
			return false
		if (not record.get("sight_range") is float and not record.get("sight_range") is int) or not is_finite(float(record.sight_range)) or record.sight_range < 0 or record.sight_range > world.terrain.SIZE * 2.0:
			return false
		for contents: Variant in [record.inventory, record.get("materials", {})]:
			if not contents is Dictionary:
				return false
			for item: Variant in contents:
				var count: Variant = contents[item]
				if not item is String or not Items.valid(item) or not count is int or count < 0:
					return false
				world.objects.totals[item] = int(world.objects.totals.get(item, 0)) + count
		if record.capacity >= 0 and world.objects.count_inventory(id) > record.capacity:
			return false
		if tile >= 0:
			world.objects._index_bucket(id, tile)
			var members: Variant = record.get("cells", PackedInt32Array([tile]))
			if not members is PackedInt32Array or members.is_empty():
				return false
			for member: int in members:
				if member < 0 or member >= world.terrain.blocked.size():
					return false
				if not world.objects.by_tile.has(member):
					world.objects.by_tile[member] = []
				world.objects.by_tile[member].append(id)
				world.objects._index_bucket(id, member)
	return true


static func _page_valid(page: RefCounted, world: RefCounted, start: int) -> bool:
	var count: int = page.ids.size()
	if count < 1 or count > Units.PAGE_SIZE:
		return false
	for field: String in ["positions", "targets", "modes", "health", "energy", "hunger", "body_heat", "tolerance", "thermal_carry", "flight", "radii", "potions", "cargo", "source_ids", "due_ms", "route_cursors", "routes"]:
		if page.get(field).size() != count:
			return false
	if page.elements.size() != count * 5 or page.exposure.size() != count * 7:
		return false
	for row: int in count:
		var id: int = page.ids[row]
		if id == 0 and page.modes[row] == Units.Mode.FREE:
			world.free_slots.append(start + row)
			continue
		if not world.objects.records.has(id) or world.objects.records[id].kind != "actor" or world.actor_slots.has(id):
			return false
		if not page.positions[row].is_finite() or page.positions[row].x < 0 or page.positions[row].y < 0 or page.positions[row].x >= world.terrain.SIZE or page.positions[row].y >= world.terrain.SIZE or not is_finite(page.body_heat[row]):
			return false
		if not is_finite(page.tolerance[row]) or page.tolerance[row] < 0 or page.tolerance[row] > Units.MAX_TOLERANCE or not is_finite(page.thermal_carry[row]) or page.thermal_carry[row] < 0 or page.thermal_carry[row] >= 1.0:
			return false
		if page.modes[row] > Units.Mode.COMBAT_MOVE or page.modes[row] == Units.Mode.FREE or page.health[row] < 0 or page.energy[row] < 0 or page.hunger[row] < 0 or page.source_ids[row] < 0 or page.source_ids[row] >= world.source_objects.size() or not page.targets[row].is_finite() or page.targets[row].x < 0 or page.targets[row].y < 0 or page.targets[row].x >= world.terrain.SIZE or page.targets[row].y >= world.terrain.SIZE:
			return false
		if page.route_cursors[row] < 0 or page.route_cursors[row] > page.routes[row].size():
			return false
		for point: Vector2 in page.routes[row]:
			if not point.is_finite() or point.x < 0 or point.y < 0 or point.x >= world.terrain.SIZE or point.y >= world.terrain.SIZE:
				return false
		world.actor_slots[id] = start + row
		if not is_finite(page.radii[row]) or page.radii[row] < 0.1 or page.radii[row] > 1.0 or page.flight[row] > 1:
			return false
		page.cargo[row] = world.objects.amount(id, "wood")
		page.potions[row] = world.objects.amount(id, "potion")
	return true


static func _processes_valid(world: RefCounted) -> bool:
	if world.source_objects.size() != world.terrain.resources.size() or world.depot_objects.size() != world.terrain.depots.size():
		return false
	for id: int in world.source_objects:
		if not world.objects.records.has(id) or world.objects.records[id].kind != "resource":
			return false
	for id: int in world.depot_objects:
		if not world.objects.records.has(id) or world.objects.records[id].kind != "chest":
			return false
	for target: Variant in world.reservations:
		if not world.objects.records.has(target) or not world.actor_slots.has(world.reservations[target]):
			return false
	for actor: Variant in world.actions:
		var action: Variant = world.actions[actor]
		if not world.actor_slots.has(actor) or not action is Dictionary or not action.get("kind") is String or action.kind not in ["take", "put", "construct", "rest", "cook", "eat", "demolish", "sow", "tend", "gather", "cut", "uproot", "talk", "trade", "request_help", "learn", "study", "practice"] or not action.get("target") is int or not world.objects.records.has(action.target):
			return false
		if action.kind in ["take", "put"] and (not action.get("item") is String or not Items.valid(action.item) or not action.get("amount") is int or action.amount <= 0):
			return false
	return true


static func _environment_valid(environment: RefCounted, world: RefCounted) -> bool:
	var size: int = environment.source_cells.size()
	if environment.source_channels.size() != size or environment.source_strengths.size() != size or environment.enabled.size() != size or environment.room_temperature.size() != world.terrain.room_cells.size() or environment.tides.size() != 5:
		return false
	for source: int in size:
		if environment.source_cells[source] < 0 or environment.source_cells[source] >= world.terrain.blocked.size() or environment.source_channels[source] < 0 or environment.source_channels[source] >= 7:
			return false
	if environment.weather < 0 or environment.weather >= environment.WEATHER.size() or environment.weather_override < -1 or environment.weather_override >= environment.WEATHER.size() or not is_finite(environment.ambient_temperature):
		return false
	for heat: float in environment.room_temperature:
		if not is_finite(heat):
			return false
	for tide: int in environment.tides:
		if tide < 95 or tide > 105:
			return false
	return true
