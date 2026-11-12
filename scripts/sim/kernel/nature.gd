extends RefCounted
## Plants are ordinary objects with slow, staggered receivers; no body rows.
## Growth integrates the preceding sampled rate. Environment changes may take
## up to PULSE_MS to affect a plant; brief moving influences can be missed.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const PULSE_MS: int = 5000
const GROUPS: int = PULSE_MS / 50
const ACTIONS: Array[String] = ["sow", "tend", "gather", "cut", "uproot"]
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
		if rec.kind != "plant" or not definitions.has(rec.definition) or not rec.get("stage") is int or rec.stage < 0 or rec.stage > Stage.WITHERED or not rec.get("growth_ms") is int or rec.growth_ms < 0 or not rec.get("last_ms") is int or rec.last_ms > world.elapsed_ms or not rec.get("sources") is PackedInt32Array:
			return false
		for source: int in rec.sources:
			if source < 0 or source >= world.environment.source_cells.size() or world.environment.free_sources.has(source):
				return false
		if rec.host > 0 and world.objects.records.get(rec.host, {}).get("guest", 0) != id:
			return false
		cohorts[id % GROUPS].append(id)
	return true


func initialize(world: RefCounted, count: int = 512) -> void:
	var examples: Array = [["annual_grass", Vector2i(177, 179)], ["perennial_herb", Vector2i(178, 179)],
		["old_tree", Vector2i(175, 180)], ["lotus", Vector2i(171, 177)],
		["desert_thorn", Vector2i(170, 183)], ["fire_herb", Vector2i(176, 179)]]
	for example: Array in examples:
		var id: int = create(world, example[0], Terrain.index(example[1]))
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
		if can_plant(world, "perennial_herb", tile).ok:
			create(world, "perennial_herb", tile)
	var planter: int = world.facilities.seed_fixture(world, "planter", Terrain.index(Vector2i(173, 182)))
	world.objects.records[planter]["water"] = 80
	world.objects.add(1, "herb", 8)
	world.objects.add(1, "grain", 8)
	world.objects.add(1, "lotus_seed", 4)
	world.objects.add(1, "fiber", 4)
	world.objects.add(1, "water", 8)


func can_plant(world: RefCounted, definition: String, tile: int) -> Dictionary:
	if not definitions.has(definition) or tile < 0 or tile >= world.terrain.blocked.size():
		return {"ok": false, "reason": "invalid_plant_or_tile"}
	var substrate: String = world.terrain.substrate(tile)
	var host: int = 0
	for other: int in world.objects.by_tile.get(tile, []):
		var rec: Dictionary = world.objects.records[other]
		if rec.get("layer", "ground") == "roof":
			continue
		var cultivation: Dictionary = world.facilities.definitions.get(rec.definition, {}).get("capabilities", {}).get("cultivation", {})
		if rec.kind != "blueprint" and not cultivation.is_empty() and int(rec.get("guest", 0)) == 0:
			host = other
			substrate = str(cultivation.substrate)
		else:
			return {"ok": false, "reason": "occupied"}
	if host == 0 and world.terrain.blocked[tile] != 0:
		return {"ok": false, "reason": "blocked"}
	if not definitions[definition].substrates.has(substrate):
		return {"ok": false, "reason": "wrong_substrate"}
	if host > 0 and bool(definitions[definition].blocks):
		return {"ok": false, "reason": "plant_too_large_for_pot"}
	return {"ok": true, "host": host}


func create(world: RefCounted, definition: String, tile: int, seeding: bool = false) -> int:
	var place: Dictionary = can_plant(world, definition, tile)
	if not place.ok:
		return 0
	var spec: Dictionary = definitions[definition]
	var id: int = world.objects.create("plant", definition, tile)
	var rec: Dictionary = world.objects.records[id]
	rec.merge({"layer": "plant", "stage": Stage.SEEDING if seeding else Stage.SPROUT,
		"growth_ms": 0, "product_ms": 0, "age_ms": 0, "injury_ms": 0, "last_ms": world.elapsed_ms,
		"rate": 1000, "adverse": false, "host": place.host, "sources": PackedInt32Array(),
		"remaining_ms": 1500, "hp": int(spec.max_hp), "max_hp": int(spec.max_hp), "sapient": false}, true)
	if place.host > 0:
		world.objects.records[place.host]["guest"] = id
	ids.append(id)
	cohorts[id % GROUPS].append(id)
	return id


func seed_item(definition: String) -> String:
	return str(definitions[definition].product.item)


func plant_site(world: RefCounted, actor: int, definition: String, tile: int) -> Dictionary:
	if not definitions.has(definition) or world.objects.amount(actor, seed_item(definition)) <= 0:
		return {"reason": "missing_seed"}
	var place: Dictionary = can_plant(world, definition, tile)
	if not place.ok:
		return {"reason": place.reason}
	var id: int = create(world, definition, tile, true)
	world.objects.transfer(actor, id, seed_item(definition), 1)
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
			rec["methods"] = {"wood_breath": {"teacher": 0, "learned_ms": now}}
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
					if page.ids[row] > 0 and page.health[row] > 0 and Terrain.index(Vector2i(page.positions[row])) == rec.tile:
						solid = false
		rec["pending_block"] = active and not solid
		world.queue_structure(rec.tile, solid, false, not solid)
	world.objects.layout_revision += 1


func finish(world: RefCounted, actor: int, action: Dictionary, now: int) -> String:
	var rec: Dictionary = world.objects.records[action.target]
	var spec: Dictionary = definitions[rec.definition]
	match action.kind:
		"sow":
			if rec.stage != Stage.SEEDING or world.objects.amount(action.target, seed_item(rec.definition)) < 1:
				return "no_seed_site"
			world.objects.add(action.target, seed_item(rec.definition), -1)
			rec.stage = Stage.SPROUT
			rec.last_ms = now
			world.objects.layout_revision += 1
		"tend":
			if rec.stage not in [Stage.SPROUT, Stage.MATURE, Stage.STUMP]:
				return "not_living_plant"
			if world.objects.amount(actor, "water") < 1:
				return "missing_water"
			world.objects.add(actor, "water", -1)
			if rec.host > 0 and world.objects.records.has(rec.host):
				world.objects.records[rec.host]["water"] = 80
			rec.injury_ms = maxi(0, int(rec.injury_ms) - 60000)
		"gather":
			if rec.stage != Stage.MATURE:
				return "not_mature"
			var moved: int = world.objects.transfer(action.target, actor, str(spec.product.item), int(spec.product.capacity))
			if moved <= 0:
				return "no_product_or_full"
			collections += moved
		"cut", "uproot":
			if action.kind == "cut" and rec.stage != Stage.MATURE:
				return "not_mature"
			var body_count: int = int(spec.body_product.amount) if rec.stage == Stage.MATURE else 0
			var capacity: int = world.objects.records[actor].capacity
			if capacity >= 0 and world.objects.count_inventory(actor) + world.objects.count_inventory(action.target) + body_count > capacity:
				return "inventory_full"
			if rec.stage == Stage.MATURE:
				world.objects.add(action.target, str(spec.body_product.item), int(spec.body_product.amount))
			for item: String in rec.inventory.keys():
				world.objects.transfer(action.target, actor, item, world.objects.amount(action.target, item))
			if world.objects.count_inventory(action.target) > 0:
				return "inventory_full"
			if action.kind == "cut" and bool(spec.regrow) and rec.stage != Stage.WITHERED:
				rec.stage = Stage.STUMP
				rec.growth_ms = 0
				rec.product_ms = 0
				rec.sapient = false
				_sync(world, action.target)
			else:
				remove(world, action.target, now)
	world._sync_inventory(actor)
	return "completed"


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
		for item: String in rec.inventory.keys():
			world.objects.transfer(id, pile, item, world.objects.amount(id, item))
	world.objects.remove_empty(id)
