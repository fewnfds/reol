extends RefCounted
## Plants are ordinary objects with slow, staggered receivers; no body rows.
## Growth integrates the preceding sampled rate. Environment changes may take
## up to PULSE_MS to affect a plant; brief moving influences can be missed.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const PULSE_MS: int = 5000
const GROUPS: int = PULSE_MS / 50
const STATE_FIELDS: Array = ["ids", "evaluations", "transitions", "collections"]
enum Stage { SEEDING, SPROUT, MATURE, STUMP, WITHERED }
var definitions: Dictionary = {}
var ids := PackedInt64Array()
var cohorts: Array[Array] = []
var evaluations: int = 0
var transitions: int = 0
var collections: int = 0
var work_usec: int = 0
var probe := PackedInt32Array()


func _init() -> void:
	definitions = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/plants.json")).types
	for index: int in GROUPS:
		cohorts.append([])
	probe.resize(7)


func rebuild(world: RefCounted) -> bool:
	var seen: Dictionary = {}
	for group: Array in cohorts:
		group.clear()
	for id: int in ids:
		if seen.has(id) or not world.objects.records.has(id):
			return false
		seen[id] = true
		var rec: Dictionary = world.objects.records[id]
		if rec.kind != "plant" or not definitions.has(rec.definition) or rec.tile < 0 or not rec.get("host") is int or rec.host < 0 or not rec.get("stage") is int or rec.stage < 0 or rec.stage > Stage.WITHERED or not rec.get("growth_ms") is int or rec.growth_ms < 0 or not rec.get("last_ms") is int or rec.last_ms > world.elapsed_ms or not rec.get("sources") is PackedInt32Array:
			return false
		if (rec.stage == Stage.SEEDING) != rec.has("remaining_ms"): return false
		if rec.has("remaining_ms") and (not rec.remaining_ms is int or rec.remaining_ms < 1): return false
		for source: int in rec.sources:
			if source < 0 or source >= world.environment.source_cells.size() or world.environment.free_sources.has(source):
				return false
		if rec.host > 0:
			var host: Dictionary = world.objects.records.get(rec.host, {})
			var cultivation: Dictionary = world.facilities.definitions.get(host.get("definition", ""), {}).get("capabilities", {}).get("cultivation", {})
			if host.is_empty() or host.kind == "blueprint" or cultivation.is_empty() or not host.get("guest") is int or host.guest != id: return false
			if not host.get("cells", PackedInt32Array([host.tile])).has(rec.tile) or bool(definitions[rec.definition].blocks) or not definitions[rec.definition].substrates.has(cultivation.substrate): return false
		cohorts[id % GROUPS].append(id)
	# Validate the reverse edge too: an empty planter may have guest=0, while a
	# positive guest must be an indexed plant actually hosted by this facility.
	for host_id: int in world.objects.records:
		var host: Dictionary = world.objects.records[host_id]
		if host.kind == "plant" and not seen.has(host_id): return false
		if not host.has("guest"): continue
		if not host.guest is int or host.guest < 0: return false
		if host.guest == 0: continue
		var cultivation: Dictionary = world.facilities.definitions.get(host.definition, {}).get("capabilities", {}).get("cultivation", {})
		if host.kind == "blueprint" or cultivation.is_empty() or not seen.has(host.guest) or world.objects.records[host.guest].host != host_id: return false
	return true


func initialize(world: RefCounted, count: int = 512) -> void:
	var examples: Array = [["annual_grass", Vector2i(177, 179)], ["perennial_herb", Vector2i(178, 179)],
		["old_tree", Vector2i(175, 180)], ["lotus", Vector2i(171, 177)],
		["desert_thorn", Vector2i(170, 183)], ["fire_herb", Vector2i(176, 179)]]
	for example: Array in examples:
		var id: int = create(world, example[0], Terrain.index(example[1]), false, true)
		if id > 0:
			var rec: Dictionary = world.objects.records[id]
			rec.growth_ms = int(definitions[example[0]].mature_ms) - 15000
			rec.product_ms = int(definitions[example[0]].product.period_ms) - 15000
			rec.stage = Stage.MATURE
			world.objects.add(id, str(definitions[example[0]].product.item), 3)
			if example[0] == "old_tree":
				rec["qi"] = 1000
			_sync(world, id)
	for index: int in count:
		var tile: int = Terrain.index(Vector2i(168 + posmod(index * 37, 96), 168 + posmod((index / 96) * 5 + index * 13, 96)))
		if can_plant(world, "perennial_herb", tile, true).ok:
			create(world, "perennial_herb", tile, false, true)
	var planter: int = world.facilities.seed_fixture(world, "planter", Terrain.index(Vector2i(173, 182)))
	world.objects.records[planter]["water"] = 80
	world.objects.add(1, "herb", 8)
	world.objects.add(1, "grain", 8)
	world.objects.add(1, "lotus_seed", 4)
	world.objects.add(1, "fiber", 4)
	world.objects.add(1, "water", 8)


func can_plant(world: RefCounted, definition: String, tile: int, wild: bool = false) -> Dictionary:
	if not definitions.has(definition) or tile < 0 or tile >= world.terrain.blocked.size():
		return {"ok": false, "reason": "invalid_plant_or_tile"}
	var substrate: String = world.terrain.substrate(tile)
	var host: int = 0
	for other: int in world.objects.by_tile.get(tile, []):
		var rec: Dictionary = world.objects.records[other]
		if rec.kind == "pile" or (rec.get("layer", "ground") in ["roof", "floor"] and rec.kind != "blueprint"):
			continue
		var cultivation: Dictionary = world.facilities.definitions.get(rec.definition, {}).get("capabilities", {}).get("cultivation", {})
		if rec.kind != "blueprint" and not cultivation.is_empty() and int(rec.get("guest", 0)) == 0:
			host = other
			substrate = str(cultivation.substrate)
		else:
			return {"ok": false, "reason": "occupied"}
	if host == 0 and world.terrain.flooring[tile] != 0:
		return {"ok": false, "reason": "covered_by_floor"}
	if wild and (host > 0 or not world.terrain.wild_site(tile, definitions[definition].substrates)):
		return {"ok": false, "reason": "not_a_wild_site"}
	if host == 0 and world.terrain.blocked[tile] != 0:
		return {"ok": false, "reason": "blocked"}
	if not definitions[definition].substrates.has(substrate):
		return {"ok": false, "reason": "wrong_substrate"}
	if host > 0 and bool(definitions[definition].blocks):
		return {"ok": false, "reason": "plant_too_large_for_pot"}
	return {"ok": true, "host": host}


func create(world: RefCounted, definition: String, tile: int, seeding: bool = false, wild: bool = false) -> int:
	var place: Dictionary = can_plant(world, definition, tile, wild)
	if not place.ok:
		return 0
	var spec: Dictionary = definitions[definition]
	var id: int = world.objects.create("plant", definition, tile)
	var rec: Dictionary = world.objects.records[id]
	rec.merge({"layer": "plant", "stage": Stage.SEEDING if seeding else Stage.SPROUT,
		"growth_ms": 0, "product_ms": 0, "age_ms": 0, "injury_ms": 0, "last_ms": world.elapsed_ms,
		"rate": 1000, "adverse": false, "host": place.host, "sources": PackedInt32Array(),
		"hp": int(spec.max_hp), "max_hp": int(spec.max_hp), "sapient": false}, true)
	if seeding: rec["remaining_ms"] = 1500
	if place.host > 0:
		world.objects.records[place.host]["guest"] = id
	ids.append(id)
	cohorts[id % GROUPS].append(id)
	return id


func vegetation_level(rec: Dictionary) -> int:
	if rec.kind == "resource":
		return int(rec.get("vegetation_level", 3))
	if rec.kind == "plant":
		return int(definitions[rec.definition].vegetation_level)
	return 0


func seed_item(definition: String) -> String:
	return str(definitions[definition].product.item)


func plant_site(world: RefCounted, actor: int, definition: String, tile: int, organization: int = 0) -> Dictionary:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return {"reason": "dead"}
	if not definitions.has(definition): return {"reason": "missing_seed"}
	if organization > 0 and not world.institutions.permits(actor, organization, "cultivate"): return {"reason": "not_authorized"}
	var right: Dictionary = world.institutions.input_right(world, actor, {seed_item(definition): 1}, "cultivate", organization)
	if right.is_empty():
		return {"reason": "missing_seed"}
	var place: Dictionary = can_plant(world, definition, tile)
	if not place.ok:
		return {"reason": place.reason}
	if int(place.host) > 0:
		var access: String = world.objects.Stock.access_reason(world.operation_actor(actor), world.operation_target(place.host), "sow", {"item": seed_item(definition)})
		if not access.is_empty(): return {"reason": access}
		var host: Dictionary = world.objects.records[place.host]
		if int(host.organization) != organization or (host.owner > 0 and host.owner != actor): return {"reason": "incompatible_cultivation_title"}
	var id: int = create(world, definition, tile, true)
	world.objects.records[id].owner = right.owner
	world.objects.records[id].organization = right.organization
	world.objects.transfer(actor, id, seed_item(definition), 1, right)
	world._sync_inventory(actor)
	return {"reason": "accepted", "target": id}


func pulse(world: RefCounted, now: int) -> void:
	var started: int = Time.get_ticks_usec()
	for id: int in cohorts[(now / 50) % GROUPS].duplicate():
		if world.objects.records.has(id):
			evaluate(world, id, now)
	work_usec += Time.get_ticks_usec() - started


func evaluate(world: RefCounted, id: int, now: int) -> void:
	var rec: Dictionary = world.objects.records[id]
	if rec.stage in [Stage.SEEDING, Stage.WITHERED]:
		rec.last_ms = now
		return
	var spec: Dictionary = definitions[rec.definition]
	var dt: int = maxi(0, now - int(rec.last_ms))
	rec.last_ms = now
	rec.age_ms += dt
	rec.growth_ms += dt * int(rec.rate) / 1000
	if rec.adverse:
		rec.injury_ms += dt
	else:
		rec.injury_ms = maxi(0, int(rec.injury_ms) - dt)
	if rec.injury_ms >= int(spec.injury_ms) or rec.age_ms >= int(spec.lifespan_ms) or rec.hp <= 0:
		rec.stage = Stage.WITHERED
		rec.hp = 0
		rec.sapient = false
		_sync(world, id)
		return
	var previous: int = rec.stage
	if rec.growth_ms >= int(spec.mature_ms):
		rec.stage = Stage.MATURE
	if previous != rec.stage:
		transitions += 1
		_sync(world, id)
	elif rec.get("pending_block", false):
		_sync(world, id)
	if rec.stage == Stage.MATURE and int(rec.rate) > 0:
		rec.product_ms += dt * int(rec.rate) / 1000
		var period: int = int(spec.product.period_ms)
		var batches: int = int(rec.product_ms) / period
		if batches > 0:
			var amount: int = mini(batches, maxi(0, int(spec.product.capacity) - world.objects.amount(id, str(spec.product.item))))
			world.objects.add(id, str(spec.product.item), amount)
			rec.product_ms = int(rec.product_ms) % period
	world.environment.sample_raw(rec.tile, probe, 0)
	if rec.stage == Stage.MATURE and bool(spec.sapient):
		rec["qi"] = mini(3000, int(rec.get("qi", 0)) + dt / 1000)
		if not rec.sapient and int(rec.age_ms) >= 30000 and world.environment.element(rec.tile, probe, 0, 1) >= 100 and world.environment.rng.randi_range(0, 7) == 0:
			rec.sapient = true
			Growth.seed(rec, "wood_breath", now)
			world.objects.layout_revision += 1
	var heat: float = world.environment.temperature_at(rec.tile, probe, 0)
	var water: int = world.terrain.moisture(rec.tile) + (15 if world.environment.weather == 1 else 0)
	if rec.host > 0 and world.objects.records.has(rec.host):
		water = int(world.objects.records[rec.host].get("water", 70))
		var used: int = int(world.objects.records[rec.host].get("water_ms", 0)) + dt
		world.objects.records[rec.host]["water"] = maxi(0, water - used / 10000)
		world.objects.records[rec.host]["water_ms"] = used % 10000
	var valid: bool = spec.seasons.has(world.environment.SEASONS[(now / world.environment.DAY_MS / 4) % 4]) and water >= int(spec.water_min) and water <= int(spec.water_max) and world.environment.light >= int(spec.light_min) and heat >= float(spec.temperature[0]) / 10.0 and heat <= float(spec.temperature[1]) / 10.0
	rec.rate = 1000 if valid else 0
	rec.adverse = heat < float(spec.temperature[2]) / 10.0 or heat > float(spec.temperature[3]) / 10.0 or (spec.life == "annual" and not valid)
	evaluations += 1


func _sync(world: RefCounted, id: int) -> void:
	var rec: Dictionary = world.objects.records[id]
	var spec: Dictionary = definitions[rec.definition]
	var active: bool = rec.stage == Stage.MATURE
	if not active:
		for source: int in rec.sources:
			world.environment.release_source(source)
		rec.sources.clear()
	elif rec.sources.is_empty():
		for emission: Dictionary in spec.get("emissions", []):
			rec.sources.append(world.environment.add_source(rec.tile, int(emission.channel), int(emission.strength)))
	if bool(spec.blocks):
		var solid: bool = active
		if solid:
			for page: RefCounted in world.pages:
				for row: int in page.positions.size():
					if page.ids[row] > 0 and page.health[row] > 0 and page.flight[row] == 0 and world._body_overlaps_tile(page.positions[row], page.radii[row], rec.tile):
						solid = false
		rec["pending_block"] = active and not solid
		world.queue_structure(rec.tile, solid, false, not solid)
	world.objects.layout_revision += 1


func tend_check(world: RefCounted, actor: int, target: int) -> String:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor): return "dead"
	var rec: Dictionary = world.objects.records.get(target, {})
	if rec.get("kind") != "plant" or rec.get("stage") not in [Stage.SPROUT, Stage.MATURE, Stage.STUMP]: return "not_living_plant"
	var access: String = world.objects.Stock.access_reason(world.operation_actor(actor), world.operation_target(target), "tend", {"item": "water"})
	if not access.is_empty(): return access
	if world.institutions.input_right(world, actor, {"water": 1}, "cultivate", int(rec.organization)).is_empty(): return "missing_water"
	return ""

func tend(world: RefCounted, actor: int, target: int, _now: int) -> Dictionary:
	var reason: String = tend_check(world, actor, target)
	if not reason.is_empty(): return Results.refused(reason)
	var rec: Dictionary = world.objects.records[target]
	var before: int = rec.injury_ms
	var right: Dictionary = world.institutions.input_right(world, actor, {"water": 1}, "cultivate", int(rec.organization))
	world.objects.consume(actor, {"water": 1}, right)
	world.institutions.consumed(right, {"water": 1}, world.operation_time())
	if rec.host > 0 and world.objects.records.has(rec.host): world.objects.records[rec.host]["water"] = 80
	rec.injury_ms = maxi(0, int(rec.injury_ms) - 60000)
	world._sync_inventory(actor)
	return Results.completed({"consumed": {"water": 1}, "injury_recovered_ms": before - int(rec.injury_ms)})

func finish(world: RefCounted, actor: int, action: Dictionary, now: int) -> String:
	return commit(world, actor, action, now).reason

func commit(world: RefCounted, actor: int, action: Dictionary, now: int) -> Dictionary:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not world.objects.records.has(action.target): return Results.refused("dead_or_missing")
	var access: String = world.OperationQuery.access_reason(world.Operations.OPERATIONS[action.kind], world.operation_actor(actor), world.operation_target(action.target), action)
	if not access.is_empty(): return Results.refused(access)
	var rec: Dictionary = world.objects.records[action.target]
	var facts: Dictionary = {"definition": rec.definition}
	if rec.kind == "resource":
		if action.kind not in ["cut", "uproot"]:
			return Results.refused("not_a_growing_plant")
		var level: int = vegetation_level(rec)
		if level == 0 or (action.kind == "cut" and level < 3):
			return Results.refused("already_cleared_or_cut")
		rec["vegetation_level"] = 2 if action.kind == "cut" else 0
		# These resource fixtures already contain all their timber. Clearing
		# changes the plant body into a stump/loose stock without minting wood.
		world.objects.layout_revision += 1
		return Results.completed({"vegetation_level": rec.vegetation_level})
	var spec: Dictionary = definitions[rec.definition]
	match action.kind:
		"sow":
			if rec.stage != Stage.SEEDING or world.objects.amount(action.target, seed_item(rec.definition)) < 1:
				return Results.refused("no_seed_site")
			facts.merge({"consumed": {seed_item(rec.definition): 1}, "worked_ms": int(rec.remaining_ms), "remaining_ms": 0, "stage": Stage.SPROUT})
			facts["entrustments"] = world.institutions.complete_asset(world, action.target, "stock", now)
			world.objects.add(action.target, seed_item(rec.definition), -1)
			rec.stage = Stage.SPROUT
			rec.last_ms = now
			rec.erase("remaining_ms")
			world.objects.layout_revision += 1
		"tend":
			var result: Dictionary = world.DomainOps.commit(world, actor, action.target, "tend", now)
			return Results.completed(result.facts) if result.ok else Results.refused(result.reason)
		"gather":
			if rec.stage != Stage.MATURE:
				return Results.refused("not_mature")
			var moved: int = world.institutions.acquire_yield(world, actor, action.target, str(spec.product.item), mini(int(spec.product.capacity), int(action.get("amount", spec.product.capacity))), now)
			if moved <= 0:
				return Results.refused("no_product_or_full")
			facts.merge({"item": str(spec.product.item), "amount": moved, "source": action.target, "destination": actor})
			collections += moved
			world.reactions.submit(world, {"event": "gathered", "actor": actor, "target": action.target, "at_ms": now, "amount": moved, "activation": 0, "position": world.position_at(actor, now)})
		"cut", "uproot":
			if action.kind == "cut" and rec.stage != Stage.MATURE:
				return Results.refused("not_mature")
			if rec.stage == Stage.MATURE:
				world.objects.add(action.target, str(spec.body_product.item), int(spec.body_product.amount))
				facts["produced"] = {str(spec.body_product.item): int(spec.body_product.amount)}
			var received: Dictionary = {}
			for item: String in world.objects.inventory_summary(action.target):
				var amount: int = world.institutions.acquire_yield(world, actor, action.target, item, world.objects.amount(action.target, item), now)
				if amount > 0: received[item] = amount
			facts["received"] = received
			if world.objects.count_inventory(action.target) > 0:
				var pile: int = world.objects.create("pile", "plant_remains", rec.tile)
				facts["remains_pile"] = pile
				var remains: Dictionary = {}
				for item: String in world.objects.inventory_summary(action.target):
					remains[item] = world.objects.transfer(action.target, pile, item, world.objects.amount(action.target, item))
				facts["remains"] = remains
			if action.kind == "cut" and bool(spec.regrow) and rec.stage != Stage.WITHERED:
				rec.stage = Stage.STUMP
				rec.growth_ms = 0
				rec.product_ms = 0
				rec.sapient = false
				facts["stage"] = Stage.STUMP
				_sync(world, action.target)
			else:
				facts["removed"] = action.target
				remove(world, action.target, now)
	world._sync_inventory(actor)
	return Results.completed(facts)


func remove(world: RefCounted, id: int, at: int = -1) -> void:
	world.forget_target(id, at)
	var rec: Dictionary = world.objects.records[id]
	rec.stage = Stage.WITHERED
	_sync(world, id)
	if rec.host > 0 and world.objects.records.has(rec.host):
		world.objects.records[rec.host]["guest"] = 0
	ids.remove_at(ids.find(id))
	cohorts[id % GROUPS].erase(id)
	if world.objects.count_inventory(id) > 0:
		var pile: int = world.objects.create("pile", "plant_remains", rec.tile)
		for item: String in world.objects.inventory_summary(id):
			world.objects.transfer(id, pile, item, world.objects.amount(id, item))
	world.objects.remove_empty(id)
