extends RefCounted
## Plants are ordinary objects with slow, staggered receivers; no body rows.
## Growth integrates the preceding sampled rate. Environment changes may take
## up to PULSE_MS to affect a plant; brief moving influences can be missed.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Defs = preload("res://scripts/sim/kernel/nature_defs.gd")
const Cultivation = preload("res://scripts/sim/kernel/cultivation.gd")
const PULSE_MS: int = 5000
const GROUPS: int = PULSE_MS / 50
const STATE_FIELDS: Array = ["ids", "evaluations", "transitions", "collections", "generated_items"]
enum Stage { SEEDING, SPROUT, MATURE, STUMP, WITHERED }
var definitions: Dictionary = {}
var ids := PackedInt64Array()
var cohorts: Array[Array] = []
var evaluations: int = 0
var transitions: int = 0
var collections: int = 0
var generated_items: Dictionary = {} # Source evidence; Objects remains the only stock.
var work_usec: int = 0
var probe := PackedInt32Array()


func _init() -> void:
	definitions = Defs.DEFINITIONS
	for index: int in GROUPS:
		cohorts.append([])
	probe.resize(7)


func rebuild(world: RefCounted) -> bool:
	if not Defs.ERRORS.is_empty() or evaluations < 0 or transitions < 0 or collections < 0 or generated_items.size() > 256: return false
	for item: Variant in generated_items:
		if not item is String or not Defs.Items.valid(item) or not generated_items[item] is int or generated_items[item] <= 0 or generated_items[item] > 999999999999: return false
	var seen: Dictionary = {}
	for group: Array in cohorts:
		group.clear()
	for id: int in ids:
		if seen.has(id) or not world.objects.records.has(id):
			return false
		seen[id] = true
		var rec: Dictionary = world.objects.records[id]
		if rec.kind != "plant" or not definitions.has(rec.definition) or rec.tile < 0 or not rec.get("host") is int or rec.host < 0 or not rec.get("stage") is int or rec.stage < 0 or rec.stage > Stage.WITHERED or not rec.get("last_ms") is int or rec.last_ms < 0 or rec.last_ms > world.elapsed_ms or not rec.get("sources") is PackedInt32Array:
			return false
		var spec: Dictionary = definitions[rec.definition]
		for field: String in ["growth_ms", "product_ms", "age_ms", "injury_ms"]:
			if not rec.get(field) is int or rec[field] < 0 or rec[field] > 999999999999: return false
		if rec.growth_ms > int(spec.mature_ms) or rec.product_ms >= int(spec.product.period_ms) or not rec.get("rate") is int or rec.rate not in [0, 1000] or not rec.get("adverse") is bool: return false
		if rec.stage == Stage.MATURE and rec.growth_ms != int(spec.mature_ms): return false
		if rec.stage in [Stage.SEEDING, Stage.SPROUT, Stage.STUMP] and rec.growth_ms >= int(spec.mature_ms): return false
		if rec.stage in [Stage.SEEDING, Stage.SPROUT, Stage.STUMP] and rec.product_ms != 0: return false
		if rec.stage == Stage.WITHERED and (rec.hp != 0 or rec.sapient): return false
		if rec.stage != Stage.WITHERED and rec.hp <= 0: return false
		if (rec.stage == Stage.SEEDING) != rec.has("remaining_ms"): return false
		if rec.has("remaining_ms") and (not rec.remaining_ms is int or rec.remaining_ms < 1 or rec.remaining_ms > 1500 or rec.growth_ms != 0 or world.objects.count_inventory(id) != 1 or world.objects.amount(id, seed_item(rec.definition)) != 1): return false
		if rec.stage == Stage.SEEDING:
			if rec.age_ms != 0 or rec.injury_ms != 0 or rec.rate != 0 or rec.adverse or rec.sapient: return false
			for batch: Dictionary in rec.stock[seed_item(rec.definition)]:
				if batch.owner != rec.owner or batch.organization != rec.organization or batch.phase not in ["free", "issued"]: return false
		var source_seen: Dictionary = {}
		for source: int in rec.sources:
			if source_seen.has(source) or rec.stage != Stage.MATURE or source < 0 or source >= world.environment.source_cells.size() or world.environment.free_sources.has(source):
				return false
			source_seen[source] = true
		if rec.host > 0:
			var host: Dictionary = world.objects.records.get(rec.host, {})
			var cultivation: Dictionary = world.facilities.definitions.get(host.get("definition", ""), {}).get("capabilities", {}).get("cultivation", {})
			if host.is_empty() or host.kind == "blueprint" or cultivation.is_empty() or not host.get("guest") is int or host.guest != id: return false
			if rec.tile != host.tile or bool(definitions[rec.definition].blocks) or not definitions[rec.definition].substrates.has(cultivation.substrate): return false
			if rec.cells != host.cells: return false
			if host.organization != rec.organization or (host.owner > 0 and host.owner != rec.owner): return false
		cohorts[id % GROUPS].append(id)
	# Validate the reverse edge too: an empty planter may have guest=0, while a
	# positive guest must be an indexed plant actually hosted by this facility.
	for host_id: int in world.objects.records:
		var host: Dictionary = world.objects.records[host_id]
		if host.kind == "plant" and not seen.has(host_id): return false
		if not Cultivation.valid(host, world.facilities.definitions.get(host.definition, {})): return false
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
			rec.growth_ms = int(definitions[example[0]].mature_ms)
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
	assert(planter > 0)
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
		if Cultivation.ignores(rec):
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
	if host > 0:
		for cell: int in world.objects.records[host].cells:
			for other: int in world.objects.by_tile.get(cell, []):
				if other == host: continue
				var record: Dictionary = world.objects.records[other]
				if not Cultivation.ignores(record): return {"ok": false, "reason": "occupied"}
	return {"ok": true, "host": host}


func create(world: RefCounted, definition: String, tile: int, seeding: bool = false, wild: bool = false) -> int:
	var place: Dictionary = can_plant(world, definition, tile, wild)
	if not place.ok:
		return 0
	var spec: Dictionary = definitions[definition]
	if place.host > 0: tile = int(world.objects.records[place.host].tile)
	var id: int = world.objects.create("plant", definition, tile)
	var rec: Dictionary = world.objects.records[id]
	rec.merge({"layer": "plant", "stage": Stage.SEEDING if seeding else Stage.SPROUT,
		"growth_ms": 0, "product_ms": 0, "age_ms": 0, "injury_ms": 0, "last_ms": world.elapsed_ms,
		"rate": 0, "adverse": false, "host": place.host, "sources": PackedInt32Array(),
		"hp": int(spec.max_hp), "max_hp": int(spec.max_hp), "sapient": false}, true)
	if seeding: rec["remaining_ms"] = 1500
	if place.host > 0:
		world.objects.records[place.host]["guest"] = id
		rec.owner = int(world.objects.records[place.host].owner)
		rec.organization = int(world.objects.records[place.host].organization)
		world.objects.reindex(id, world.objects.records[place.host].cells)
	ids.append(id)
	cohorts[id % GROUPS].append(id)
	if not seeding: _sample(world, rec, world.elapsed_ms)
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
	var right: Dictionary = world.institutions.input_right(world, actor, {seed_item(definition): 1}, "cultivate", organization)
	if right.is_empty():
		return {"reason": "missing_seed"}
	var place: Dictionary = can_plant(world, definition, tile)
	if not place.ok:
		return {"reason": place.reason}
	if int(place.host) == 0 and organization > 0 and not world.institutions.permits(actor, organization, "cultivate"): return {"reason": "not_authorized"}
	if int(place.host) > 0:
		var access: String = world.objects.Stock.access_reason(world.operation_actor(actor), world.operation_target(place.host), "sow", {"item": seed_item(definition)})
		if not access.is_empty(): return {"reason": access}
		var host: Dictionary = world.objects.records[place.host]
		var title: String = Cultivation.title_reason(actor, host, organization)
		if not title.is_empty(): return {"reason": title}
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
	var effective: int = dt * int(rec.rate) / 1000
	var growing: int = mini(effective, maxi(0, int(spec.mature_ms) - int(rec.growth_ms)))
	rec.growth_ms += growing
	if rec.host > 0:
		var host: Dictionary = world.objects.records[rec.host]
		Cultivation.advance(host, world.facilities.definitions[host.definition], dt)
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
		var space: int = maxi(0, int(spec.product.capacity) - world.objects.amount(id, str(spec.product.item)))
		rec.product_ms = int(rec.product_ms) + effective - growing if space > 0 else 0
		var period: int = int(spec.product.period_ms)
		var batches: int = int(rec.product_ms) / period
		if batches > 0:
			var amount: int = mini(batches, space)
			if amount > 0:
				world.objects.add(id, str(spec.product.item), amount)
				_generated(str(spec.product.item), amount)
			rec.product_ms = int(rec.product_ms) % period if amount < space else 0
	world.environment.sample_raw(rec.tile, probe, 0)
	if rec.stage == Stage.MATURE and bool(spec.sapient):
		rec["qi"] = mini(3000, int(rec.get("qi", 0)) + dt / 1000)
		if not rec.sapient and int(rec.age_ms) >= 30000 and world.environment.element(rec.tile, probe, 0, 1) >= 100 and world.environment.rng.randi_range(0, 7) == 0:
			rec.sapient = true
			Growth.seed(rec, "wood_breath", now)
			world.objects.layout_revision += 1
	_sample(world, rec, now)
	evaluations += 1


func _sample(world: RefCounted, rec: Dictionary, now: int) -> void:
	var spec: Dictionary = definitions[rec.definition]
	world.environment.sample_raw(rec.tile, probe, 0)
	var heat: float = world.environment.temperature_at(rec.tile, probe, 0)
	var water: int = world.terrain.moisture(rec.tile) + (15 if world.environment.weather == 1 else 0)
	if rec.host > 0 and world.objects.records.has(rec.host):
		water = int(world.objects.records[rec.host].water)
	var season_ok: bool = spec.seasons.has(world.environment.SEASONS[(now / world.environment.DAY_MS / 4) % 4])
	var water_ok: bool = water >= int(spec.water_min) and water <= int(spec.water_max)
	var valid: bool = season_ok and water_ok and world.environment.light >= int(spec.light_min) and heat >= float(spec.temperature[0]) / 10.0 and heat <= float(spec.temperature[1]) / 10.0
	rec.rate = 1000 if valid else 0
	rec.adverse = heat < float(spec.temperature[2]) / 10.0 or heat > float(spec.temperature[3]) / 10.0 or not water_ok or (spec.life == "annual" and not season_ok)


func _generated(item: String, amount: int) -> void:
	if amount > 0: generated_items[item] = int(generated_items.get(item, 0)) + amount


func public_state(world: RefCounted, id: int) -> Dictionary:
	var record: Dictionary = world.objects.records[id]
	if record.kind == "plant":
		var band: int = -1 # Bare terrain has no writable water reservoir.
		if record.host > 0:
			var host: Dictionary = world.objects.records[record.host]
			band = Cultivation.water_band(int(host.water), Cultivation.limit(world.facilities.definitions[host.definition], definitions[record.definition]))
		return {"host": record.host, "injured": int(record.injury_ms) > 0, "water_band": band}
	if record.kind != "blueprint" and not Cultivation.spec(world.facilities.definitions.get(record.definition, {})).is_empty(): return {"occupant": int(record.guest)}
	return {}


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
	var need: String = Cultivation.care_reason(public_state(world, target))
	if not need.is_empty(): return need
	if world.institutions.input_right(world, actor, {"water": 1}, "cultivate", int(rec.organization)).is_empty(): return "missing_water"
	return ""

func tend(world: RefCounted, actor: int, target: int, now: int) -> Dictionary:
	if world.objects.records.get(target, {}).get("kind") == "plant": evaluate(world, target, now)
	var reason: String = tend_check(world, actor, target)
	if not reason.is_empty(): return Results.refused(reason)
	var rec: Dictionary = world.objects.records[target]
	var before: int = rec.injury_ms
	var right: Dictionary = world.institutions.input_right(world, actor, {"water": 1}, "cultivate", int(rec.organization))
	world.objects.consume(actor, {"water": 1}, right)
	world.institutions.consumed(right, {"water": 1}, world.operation_time())
	var watered: int = 0
	if rec.host > 0:
		var host: Dictionary = world.objects.records[rec.host]
		var definition: Dictionary = world.facilities.definitions[host.definition]
		var before_water: int = host.water
		host.water = maxi(before_water, mini(Cultivation.limit(definition, definitions[rec.definition]), before_water + int(Cultivation.spec(definition).water_per_item)))
		watered = int(host.water) - before_water
	rec.injury_ms = maxi(0, int(rec.injury_ms) - 60000)
	_sample(world, rec, now)
	world._sync_inventory(actor)
	return Results.completed({"consumed": {"water": 1}, "injury_recovered_ms": before - int(rec.injury_ms), "water_added": watered})

func finish(world: RefCounted, actor: int, action: Dictionary, now: int) -> String:
	return commit(world, actor, action, now).reason

func commit(world: RefCounted, actor: int, action: Dictionary, now: int) -> Dictionary:
	if not world.actor_slots.has(actor) or not world.combat.alive(world, actor) or not world.objects.records.has(action.target): return Results.refused("dead_or_missing")
	var operation: Dictionary = world.Operations.OPERATIONS.get(action.get("operation_id", action.kind), {})
	if operation.get("executor") != "nature" or operation.get("handler") != action.kind: return Results.refused("unknown_operation")
	var access: String = world.OperationQuery.access_reason(operation, world.operation_actor(actor), world.operation_target(action.target), action)
	if not access.is_empty(): return Results.refused(access)
	var rec: Dictionary = world.objects.records[action.target]
	if action.kind == "plant_crop":
		var query: Dictionary = world.OperationQuery.evaluate(operation, world.operation_actor(actor), world.operation_target(action.target), action)
		if not query.ready: return Results.refused(query.reason)
		var planted: Dictionary = plant_site(world, actor, operation.plant_definition, rec.tile, int(rec.organization))
		if planted.reason != "accepted": return Results.refused(planted.reason)
		var outcome: Dictionary = _finish_sowing(world, int(planted.target), now, int(operation.duration_ms))
		outcome.facts["planted"] = int(planted.target)
		outcome.facts["host"] = action.target
		world.knowledge.created(world, actor, int(planted.target), now)
		world._sync_inventory(actor)
		return outcome
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
	if rec.kind != "plant": return Results.refused("invalid_target")
	# Resolve the preceding sampled interval before harvesting or removing stock;
	# freeing a full crop must not retroactively make that interval productive.
	if rec.kind == "plant" and action.kind in ["gather", "cut", "uproot"]: evaluate(world, action.target, now)
	var spec: Dictionary = definitions[rec.definition]
	match action.kind:
		"sow":
			return _finish_sowing(world, action.target, now)
		"tend":
			var result: Dictionary = world.DomainOps.commit(world, actor, action.target, "tend", now)
			return Results.completed(result.facts) if result.ok else Results.refused(result.reason)
		"gather":
			if rec.stage != Stage.MATURE:
				return Results.refused("not_mature")
			var moved: int = world.institutions.acquire_yield(world, actor, action.target, str(spec.product.item), mini(int(spec.product.capacity), int(action.get("amount", spec.product.capacity))), now, str(action.get("purpose", "cultivate")))
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
				_generated(str(spec.body_product.item), int(spec.body_product.amount))
				facts["produced"] = {str(spec.body_product.item): int(spec.body_product.amount)}
			var received: Dictionary = {}
			for item: String in world.objects.inventory_summary(action.target):
				if rec.stage == Stage.SEEDING: continue # Unconsumed input returns as original batches in the remains pile.
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
				if int(rec.host) > 0: world.knowledge.refresh(world, actor, int(rec.host), now)
	world._sync_inventory(actor)
	return Results.completed(facts)


func _finish_sowing(world: RefCounted, target: int, now: int, worked_ms: int = -1) -> Dictionary:
	var rec: Dictionary = world.objects.records[target]
	if rec.stage != Stage.SEEDING or world.objects.amount(target, seed_item(rec.definition)) != 1: return Results.refused("no_seed_site")
	var facts: Dictionary = {"definition": rec.definition, "consumed": {seed_item(rec.definition): 1}, "worked_ms": int(rec.remaining_ms) if worked_ms < 0 else worked_ms, "remaining_ms": 0, "stage": Stage.SPROUT}
	facts["entrustments"] = world.institutions.complete_asset(world, target, "stock", now)
	world.objects.add(target, seed_item(rec.definition), -1)
	rec.stage = Stage.SPROUT
	rec.last_ms = now
	rec.erase("remaining_ms")
	_sample(world, rec, now)
	world.objects.layout_revision += 1
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
