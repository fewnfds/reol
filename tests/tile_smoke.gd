extends RefCounted
## Tile layers and vegetation use the existing six-person smoke world.
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")


static func run(w: RefCounted, check: Callable) -> void:
	for source: int in w.source_objects:
		if w.nature.vegetation_level(w.objects.records[source]) >= 3:
			check.call(w.terrain.wild_site(w.objects.records[source].tile, ["soil"]), "Natural timber spawned on a floor, in a room or outside soil")
	var tile: int = Terrain.index(Vector2i(140, 140))
	var grass: int = w.nature.create(w, "annual_grass", tile)
	w.objects.add(grass, "grain", 2)
	w.objects.transfer(w.source_objects[0], 1, "wood", 4)
	var topology: int = w.topology_revision
	var site: Dictionary = w.facilities.blueprint(w, 1, "wood_floor", tile)
	check.call(site.get("target", 0) > 0 and w.objects.records.has(grass) and w.terrain.flooring[tile] == 0, "Floor blueprint cleared grass before completion")
	if site.get("target", 0) == 0:
		return
	check.call(not w.nature.can_plant(w, "old_tree", tile).ok, "Planting ignored an existing floor blueprint")
	w.facilities.demolish(w, site.target)
	check.call(w.objects.records.has(grass), "Canceling a floor removed its living grass")
	site = w.facilities.blueprint(w, 1, "wood_floor", tile)
	var grain: int = w.objects.total("grain")
	check.call(w.facilities.finish(w, 1, {"kind": "construct", "target": site.target}, w.elapsed_ms) == "completed", "A floor could not cover low vegetation")
	w.flush_topology()
	check.call(not w.objects.records.has(grass) and w.terrain.flooring[tile] == 1 and w.terrain.cover[tile] == 0 and w.terrain.substrate(tile) == "soil" and w.topology_revision == topology, "Floor completion corrupted vegetation, substrate or topology")
	check.call(w.objects.audit_total("grain") == grain, "Floor covering destroyed stored plant products")
	check.call(not w.nature.can_plant(w, "annual_grass", tile, true).ok and not w.nature.can_plant(w, "annual_grass", tile).ok, "Bare plants can grow through a completed floor")
	var pot: int = w.facilities.seed_fixture(w, "planter", tile)
	var guest: int = w.nature.create(w, "perennial_herb", tile)
	check.call(guest > 0 and w.objects.records[guest].host == pot and not w.nature.can_plant(w, "old_tree", tile).ok, "Floor-hosted cultivation lost its host or admitted a tree")
	var saved: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check.call(saved != null and saved.terrain.base == w.terrain.base and saved.terrain.cover == w.terrain.cover and saved.terrain.flooring == w.terrain.flooring and saved.objects.records[pot].guest == guest, "Tile layers or floor-hosted plants did not reload")
	w.facilities.demolish(w, site.target)
	check.call(w.terrain.flooring[tile] == 0 and w.terrain.substrate(tile) == "soil" and w.objects.records.has(pot) and w.objects.records.has(guest), "Floor demolition removed furniture/plants or failed to expose soil")
	var source: int = w.source_objects[0]
	var timber: int = w.objects.total("wood")
	var source_tile: int = w.objects.records[source].tile
	check.call(w.facilities.placement(w, "floor", PackedInt32Array([source_tile])) == "clear_shrub_tree_or_stump_first", "Standing timber did not block flooring")
	w.nature.finish(w, 1, {"kind": "cut", "target": source}, w.elapsed_ms)
	check.call(w.facilities.placement(w, "floor", PackedInt32Array([source_tile])) == "clear_shrub_tree_or_stump_first", "A stump did not block flooring")
	w.nature.finish(w, 1, {"kind": "uproot", "target": source}, w.elapsed_ms)
	check.call(w.facilities.placement(w, "floor", PackedInt32Array([source_tile])) == "accepted" and w.objects.audit_total("wood") == timber and w.source_objects[0] == source, "Uprooting lost timber/source identity or left an invisible blocker")
	var water: int = Terrain.index(Vector2i(172, 176))
	check.call(w.nature.can_plant(w, "lotus", water, true).ok and not w.nature.can_plant(w, "old_tree", water, true).ok and w.facilities.placement(w, "floor", PackedInt32Array([water])) != "accepted", "Water accepted a tree/floor or rejected its aquatic plant")
	check.call(w.facilities.footprint("wood_floor", Terrain.SIZE * Terrain.SIZE).is_empty(), "Out-of-map construction returned an invalid footprint")
	var plant: int = w.nature.create(w, "annual_grass", tile + 2)
	w.objects.records[plant].stage = 2
	var capacity: int = w.objects.records[1].capacity
	w.objects.records[1].capacity = w.objects.count_inventory(1)
	grain = w.objects.total("grain") + 2
	check.call(w.nature.finish(w, 1, {"kind": "uproot", "target": plant}, w.elapsed_ms) == "completed" and not w.objects.records.has(plant) and w.objects.audit_total("grain") == grain, "A full backpack prevented clearing or lost/duplicated its product")
	w.objects.records[1].capacity = capacity
	var bed_tile: int = Terrain.index(Vector2i(145, 140))
	check.call(w.facilities.footprint("long_bed", bed_tile, 1) == PackedInt32Array([bed_tile, bed_tile + 1]) and w.facilities.footprint("long_bed", bed_tile, 2) == PackedInt32Array([bed_tile, bed_tile + Terrain.SIZE]), "Cardinal rotation did not rotate the multi-cell footprint")
	w.objects.transfer(w.source_objects[0], 1, "wood", 8)
	var bed: Dictionary = w.facilities.blueprint(w, 1, "long_bed", bed_tile, 1)
	check.call(bed.get("target", 0) > 0, "A rotated fixture blueprint could not be created")
	if bed.get("target", 0) > 0:
		check.call(w.facilities.finish(w, 1, {"kind": "construct", "target": bed.target}, w.elapsed_ms) == "completed" and w.objects.layout()[bed.target].facing == 1, "Completion or detached layout lost fixture orientation")
		saved = Persistence.candidate(Persistence.capture(w), 0)
		check.call(saved != null and saved.objects.records[bed.target].facing == 1 and saved.objects.records[bed.target].cells == PackedInt32Array([bed_tile,bed_tile+1]), "Save/load lost fixture orientation or its rotated occupancy")
