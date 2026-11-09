extends RefCounted
## Candidate validation for nonhuman physical sources and successful transactions.


static func count(value: Variant, minimum: int = 0, maximum: int = SimInventory.MAX_COUNT) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum and value <= maximum


static func keys(data: Variant, expected: Array) -> bool:
	if not data is Dictionary or data.size() != expected.size():
		return false
	for key: Variant in expected:
		if not data.has(key):
			return false
	return true


static func same_record(data: Variant, expected: Dictionary) -> bool:
	if not keys(data, expected.keys()):
		return false
	for key: String in expected:
		if (expected[key] is int or expected[key] is float) and data[key] is bool:
			return false
		if data[key] != expected[key]:
			return false
	return true


static func cell_valid(value: Variant, offset: bool = false) -> bool:
	return value is Array and value.size() == 2 and count(value[0], -ReolWorld.WORLD_SIZE if offset else 0, ReolWorld.WORLD_SIZE - 1) and count(value[1], -ReolWorld.WORLD_SIZE if offset else 0, ReolWorld.WORLD_SIZE - 1)


static func position_valid(value: Variant) -> bool:
	if not SimLocalMotion._vector(value):
		return false
	for coordinate: Variant in value:
		if coordinate < 0 or coordinate >= ReolWorld.WORLD_SIZE * TileGrid.TILE_SIZE:
			return false
	return true


static func definitions_valid(data: Variant) -> bool:
	if not keys(data, ["version", "species", "items_grams", "actions_ms", "manual", "gift", "site_types"]) or data.version != 1 or not keys(data.species, ["sparrow"]):
		return false
	var fields: Array = ["carry_grams", "flight_speed", "observation_cells", "interaction_cells", "hunger_per_minute", "energy_per_minute", "flight_energy_per_minute", "rest_gain_per_minute", "eat_below", "rest_below", "help_min_fullness", "help_min_energy", "seed_nourishment"]
	if not keys(data.species.sparrow, fields):
		return false
	for field: String in fields:
		if not count(data.species.sparrow[field], 1, 60000000):
			return false
	for field: String in ["eat_below", "rest_below", "help_min_fullness", "help_min_energy", "seed_nourishment"]:
		if data.species.sparrow[field] > 100:
			return false
	if not keys(data.actions_ms, ["forage", "rest", "pickup", "drop", "idle"]) or not keys(data.gift, ["grain", "seed", "foods"]) or not SimEmbodiment._unique_texts(data.gift.foods) or data.gift.foods.is_empty():
		return false
	for amount: Variant in data.actions_ms.values() + [data.gift.grain, data.gift.seed]:
		if not count(amount, 1, 3600000):
			return false
	if not keys(data.manual, ["leg_distance_px", "min_flight_energy", "ground_rest_ms", "ground_rest_gain_per_minute"]):
		return false
	for amount: Variant in data.manual.values():
		if not count(amount, 1, 60000000):
			return false
	if not data.items_grams is Dictionary or not data.items_grams.has("herb") or not data.items_grams.has("seed"):
		return false
	for item: Variant in data.items_grams:
		if not SimInventory._nonempty(item) or not count(data.items_grams[item], 1, 10000000):
			return false
	if not keys(data.site_types, ["roost", "seeds", "crevice", "garden"]):
		return false
	for id: String in data.site_types:
		var site: Variant = data.site_types[id]
		if not keys(site, ["label", "opening_mm", "altitude", "item", "initial", "capacity", "regrow_ms", "regrow_amount"]) or not SimInventory._nonempty(site.label) or not site.item is String or not count(site.altitude, 0, 1):
			return false
		for field: String in ["opening_mm", "initial", "capacity", "regrow_ms", "regrow_amount"]:
			if not count(site[field], 0, 10000000):
				return false
		if site.initial > site.capacity or site.regrow_amount > site.capacity or (site.regrow_ms == 0) != (site.regrow_amount == 0):
			return false
		if not str(site.item).is_empty() and not data.items_grams.has(site.item):
			return false
		if str(site.item).is_empty() and (site.initial != 0 or site.capacity != 0):
			return false
	return data.site_types.seeds.item == "seed" and data.site_types.crevice.item == "herb" and data.site_types.roost.altitude == 1 and data.site_types.garden.altitude == 0


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not keys(data, ["version", "elapsed_ms", "birds", "sites", "inventory", "events", "exchanges", "next_id"]) or not count(data.version, 1, 1) or not count(data.elapsed_ms) or data.elapsed_ms != domain.world.elapsed_ms or not count(data.next_id, 1):
		return false
	for field: String in ["birds", "sites", "inventory", "exchanges"]:
		if not data[field] is Dictionary:
			return false
	if not data.events is Array:
		return false
	var inv := SimInventory.new()
	if not inv.restore(data.inventory) or not inv.reservations.is_empty() or not inv.custody.is_empty():
		return false
	var containers: Array = []
	for id: Variant in data.sites:
		var site: Variant = data.sites[id]
		if not SimInventory._nonempty(id) or not keys(site, ["region", "type", "cell", "next_growth_ms"]) or not domain.world.regions.has(site.region) or not domain.definitions.site_types.has(site.type) or not cell_valid(site.cell):
			return false
		var terms: Dictionary = domain.definitions.site_types[site.type]
		if not count(site.next_growth_ms) or (int(terms.regrow_ms) == 0 and site.next_growth_ms != 0) or (int(terms.regrow_ms) > 0 and not count(site.next_growth_ms, int(data.elapsed_ms) + 1)):
			return false
		if site.type == "garden" and SimRouteTravel.cell(site.cell) != SimRouteTravel.cell(domain.world.regions[site.region].places.garden.cell):
			return false
		if not inv.containers.has(id):
			return false
		for item: String in inv.containers[id]:
			if item != terms.item:
				return false
		containers.append(id)
	var ids: Dictionary = {}
	for id: Variant in data.birds:
		if not _bird(id, data.birds[id], data, domain, inv, ids):
			return false
		containers.append("bird:" + str(id))
	if not keys(inv.containers, containers) or not domain.world.embodiment.matches_legacy_actors(domain.world._actor_ids(domain.world.regions), data.birds.keys(), domain.world.soul_vessels.bindings(), domain.world.large_bodies.bodies.keys(), domain.world.plants.subject_ids() if domain.world.plants != null else []):
		return false
	var expected_ops: Dictionary = {}
	var expected_exchanges: Dictionary = {}
	var last: int = -1
	for raw: Variant in data.events:
		if not _event(raw, data, domain, ids, expected_ops, expected_exchanges) or int(raw.at_ms) < last:
			return false
		last = int(raw.at_ms)
	if not keys(inv.operations, expected_ops.keys()) or not keys(data.exchanges, expected_exchanges.keys()):
		return false
	for id: String in expected_ops:
		if not same_record(inv.operations[id], expected_ops[id]):
			return false
	for id: String in expected_exchanges:
		if not same_record(data.exchanges[id], expected_exchanges[id]):
			return false
	return true


static func _bird(id: Variant, body: Variant, state: Dictionary, domain: RefCounted, inv: SimInventory, ids: Dictionary) -> bool:
	var fields: Array = ["label", "region", "home", "position", "altitude", "fullness", "energy", "carry", "autonomous", "active", "retry_ms", "known_sites", "errand", "goal"]
	if body is Dictionary and body.has("understands_gestures"):
		fields.append("understands_gestures")
		if not body.understands_gestures is bool:
			return false
	if not SimInventory._nonempty(id) or not keys(body, fields):
		return false
	if not SimInventory._nonempty(body.label) or not body.goal is String or not domain.world.regions.has(body.region) or not state.sites.has(body.home) or state.sites[body.home].type != "roost" or state.sites[body.home].region != body.region or not position_valid(body.position) or not count(body.altitude, 0, 1) or not body.autonomous is bool or not count(body.retry_ms):
		return false
	if not keys(body.carry, ["fullness", "energy"]) or not count(body.fullness, 0, 100000000) or not count(body.energy, 0, 100000000) or not count(body.carry.fullness, 0, 59999) or not count(body.carry.energy, 0, 59999):
		return false
	if not body.known_sites is Dictionary or not body.active is Dictionary or not body.errand is Dictionary or not inv.containers.has("bird:" + str(id)):
		return false
	for site_id: Variant in body.known_sites:
		var memory: Variant = body.known_sites[site_id]
		if not state.sites.has(site_id) or not keys(memory, ["at_ms", "quantity"]) or not count(memory.at_ms, 0, int(state.elapsed_ms)) or not count(memory.quantity):
			return false
	var grams: int = 0
	for item: String in inv.containers["bird:" + str(id)]:
		# Every declared unit weighs at least one gram; bound multiplication first.
		if not domain.definitions.items_grams.has(item) or inv.quantity("bird:" + str(id), item) > int(domain.rules().carry_grams):
			return false
		grams += inv.quantity("bird:" + str(id), item) * int(domain.definitions.items_grams[item])
	if grams > int(domain.rules().carry_grams):
		return false
	if not body.errand.is_empty():
		if not keys(body.errand, ["source", "target", "requester"]) or not state.sites.has(body.errand.source) or not state.sites.has(body.errand.target) or state.sites[body.errand.source].type != "crevice" or state.sites[body.errand.target].type != "garden" or not body.errand.requester is String:
			return false
		# Direct control of one's own beak needs no comprehension of another
		# actor's request. Only a commissioned errand requires understanding.
		if not body.errand.requester.is_empty() and not bool(body.get("understands_gestures", true)):
			return false
		if (body.errand.requester.is_empty() and bool(body.autonomous)) or (not body.errand.requester.is_empty() and domain.actor_region(body.errand.requester).is_empty()):
			return false
	if body.active.is_empty():
		return not bool(body.autonomous) or int(body.retry_ms) > int(state.elapsed_ms)
	var action: Dictionary = body.active
	if not keys(action, ["id", "verb", "site", "purpose", "started_ms", "due_ms", "from", "to"]) or not _id(action.id, state.next_id, ids) or not action.verb in ["fly", "forage", "rest", "pickup", "drop"] or not action.purpose in ["forage", "rest", "pickup", "drop", "explore", "recover"]:
		return false
	if not count(action.started_ms, 0, int(state.elapsed_ms)) or not count(action.due_ms, int(state.elapsed_ms) + 1) or not position_valid(action.from) or not position_valid(action.to):
		return false
	if not domain.world.embodiment.controls(SimAvianLife.subject_id(id), SimAvianLife.carrier_id(id), "motion") or not domain.world.embodiment.controls(SimAvianLife.subject_id(id), SimAvianLife.carrier_id(id), "action"):
		return false
	if action.purpose in ["explore", "recover"]:
		if bool(body.autonomous) or action.site != "" or not body.errand.is_empty():
			return false
		if action.purpose == "recover":
			return action.verb == "rest" and body.altitude == 0 and action.from == action.to and SimAvianLife.point(body).is_equal_approx(Vector2(float(action.from[0]), float(action.from[1]))) and int(action.due_ms) - int(action.started_ms) == int(domain.definitions.manual.ground_rest_ms)
		return action.verb == "fly" and _flight_valid(action, body, state, domain, Vector2(float(action.to[0]), float(action.to[1])))
	if not state.sites.has(action.site):
		return false
	var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(state.sites[action.site].cell))
	if not target.is_equal_approx(Vector2(float(action.to[0]), float(action.to[1]))) or not domain.world.embodiment.fits_opening(SimAvianLife.carrier_id(id), int(domain.definitions.site_types[state.sites[action.site].type].opening_mm)):
		return false
	var needed_type: String = {"forage": "seeds", "rest": "roost", "pickup": "crevice", "drop": "garden"}[action.purpose]
	if state.sites[action.site].type != needed_type:
		return false
	if action.purpose in ["pickup", "drop"] and body.errand.is_empty():
		return false
	if action.verb == "fly":
		return _flight_valid(action, body, state, domain, target)
	return action.verb == action.purpose and int(action.due_ms) - int(action.started_ms) == int(domain.definitions.actions_ms[action.verb]) and SimAvianLife.point(body).is_equal_approx(target) and action.from == action.to and body.altitude == domain.definitions.site_types[state.sites[action.site].type].altitude


static func _flight_valid(action: Dictionary, body: Dictionary, state: Dictionary, domain: RefCounted, target: Vector2) -> bool:
	var origin := Vector2(float(action.from[0]), float(action.from[1]))
	if action.purpose == "explore" and origin.distance_to(target) > float(domain.definitions.manual.leg_distance_px) + 0.02:
		return false
	var duration: int = maxi(1, ceili(origin.distance_to(target) / float(domain.rules().flight_speed) * 1000))
	if int(action.due_ms) - int(action.started_ms) != duration or body.altitude != 1:
		return false
	var fraction: float = float(int(state.elapsed_ms) - int(action.started_ms)) / duration
	return SimAvianLife.point(body).is_equal_approx(origin.lerp(target, fraction))


static func _id(value: Variant, limit: int, used: Dictionary) -> bool:
	if not value is String or not value.begins_with("avian:") or not value.trim_prefix("avian:").is_valid_int() or used.has(value):
		return false
	var number: int = value.trim_prefix("avian:").to_int()
	if number < 1 or number >= limit:
		return false
	used[value] = true
	return true


static func _event(event: Variant, state: Dictionary, domain: RefCounted, ids: Dictionary, ops: Dictionary, exchanges: Dictionary) -> bool:
	if not keys(event, ["id", "kind", "bird", "site", "at_ms", "line", "details"]) or not _id(event.id, int(state.next_id), ids) or not count(event.at_ms, 0, int(state.elapsed_ms)) or not event.line is String or not event.details is Dictionary or not state.sites.has(event.site):
		return false
	if event.kind == "ripened":
		var site: Dictionary = domain.definitions.site_types[state.sites[event.site].type]
		return event.bird == "" and keys(event.details, ["item", "amount"]) and event.details.item == site.item and count(event.details.amount, 1, int(site.regrow_amount))
	if not state.birds.has(event.bird):
		return false
	var details: Dictionary = event.details
	if event.kind == "agreed":
		return bool(state.birds[event.bird].get("understands_gestures", true)) and keys(details, ["actor"]) and not domain.actor_region(str(details.actor)).is_empty()
	if event.kind == "offered":
		if not keys(details, ["actor", "action", "food", "grain", "seed"]) or domain.actor_region(str(details.actor)).is_empty() or not domain.definitions.gift.foods.has(details.food) or details.grain != domain.definitions.gift.grain or details.seed != domain.definitions.gift.seed or not _id(details.action, int(state.next_id), ids):
			return false
		var sim: RefCounted = domain.world.regions[domain.actor_region(str(details.actor))]
		return same_record(sim.inventory.operations.get(str(details.action) + ":grain"), {"kind": "consume", "container": "actor:" + str(details.actor), "item": details.food, "amount": int(details.grain)})
	if not event.kind in ["forage", "rest", "pickup", "drop", "failed", "cancelled"] or not keys(details, ["action"]) or not _id(details.action, int(state.next_id), ids):
		return false
	if event.kind == "forage":
		ops[str(details.action) + ":eat"] = {"kind": "consume", "container": event.site, "item": "seed", "amount": 1}
	elif event.kind == "pickup":
		ops[str(details.action) + ":pick"] = {"kind": "transfer", "source": event.site, "target": "bird:" + str(event.bird), "item": "herb", "amount": 1, "reservation_id": ""}
	elif event.kind == "drop":
		exchanges[str(details.action) + ":delivery"] = {"from": "avian", "to": state.sites[event.site].region, "source": "bird:" + str(event.bird), "target": "garden", "item": "herb", "amount": 1}
	return true
