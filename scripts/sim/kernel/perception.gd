extends RefCounted
## Shared range-loss model. Personal memory is not a reference to live layout.
## No all-NPC visibility maps; candidates use cached static ray losses.

const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const State = preload("res://scripts/sim/kernel/state.gd")
const RANGE: float = 24.0
const CACHE_SIZE: int = 32768
const STATE_FIELDS: Array = ["memories", "explored", "next_ms", "previous"]
var memories: Dictionary = {}
var explored := PackedByteArray()
var loss := PackedByteArray()
var visible := PackedByteArray()
var revision: int = 0
var layout_seen: int = -1
var previous := Vector2(-1, -1)
var cache: Dictionary = {}
var ring := PackedInt64Array()
var cursor: int = 0
var next_ms: int = 0
var work_usec: int = 0


func _init() -> void:
	explored.resize(Terrain.SIZE * Terrain.SIZE)
	loss.resize(Terrain.SIZE * Terrain.SIZE)


func rebuild(world: RefCounted) -> bool:
	if explored.size() != Terrain.SIZE * Terrain.SIZE:
		return false
	for id: Variant in memories:
		if not id is int or not memories[id] is Dictionary or not memories[id].get("tile") is int or not memories[id].get("cells") is PackedInt32Array:
			return false
	rebuild_loss(world)
	update_visible(world)
	revision += 1
	return true


func rebuild_loss(world: RefCounted) -> void:
	var value := PackedByteArray()
	value.resize(loss.size())
	for rec: Dictionary in world.objects.records.values():
		if rec.tile < 0 or rec.kind == "blueprint":
			continue
		var cost: int = int(world.facilities.definitions.get(rec.definition, {}).get("perception_cost", 0))
		if rec.kind == "plant":
			cost = 2 if rec.definition == "old_tree" and rec.stage == 2 else 0
		for tile: int in rec.get("cells", PackedInt32Array([rec.tile])):
			value[tile] = maxi(value[tile], cost)
	if value != loss:
		loss = value
		cache.clear()
		ring.clear()
		cursor = 0
		revision += 1
	layout_seen = world.objects.layout_revision


func ray_loss(a: int, b: int) -> int:
	var low: int = mini(a, b)
	var high: int = maxi(a, b)
	var key: int = low + high * Terrain.SIZE * Terrain.SIZE
	if cache.has(key):
		return cache[key]
	var origin: Vector2i = Terrain.cell(low)
	var delta: Vector2i = Terrain.cell(high) - origin
	var length: int = maxi(absi(delta.x), absi(delta.y))
	var amount: int = 0
	for step: int in range(1, length):
		var point := Vector2i((Vector2(origin) + Vector2(delta) * float(step) / maxi(1, length)).round())
		amount += loss[Terrain.index(point)]
	if ring.size() < CACHE_SIZE:
		ring.append(key)
	else:
		cache.erase(ring[cursor])
		ring[cursor] = key
		cursor = (cursor + 1) % CACHE_SIZE
	cache[key] = amount
	return amount


func sees(origin: Vector2, tile: int) -> bool:
	if tile < 0 or tile >= loss.size():
		return false
	var distance: float = origin.distance_to(Terrain.center(tile))
	return distance <= RANGE and distance + ray_loss(Terrain.index(Vector2i(origin)), tile) <= RANGE


func sees_object(origin: Vector2, rec: Dictionary) -> bool:
	if sees(origin, rec.tile):
		return true
	for tile: int in rec.get("cells", PackedInt32Array()):
		if sees(origin, tile):
			return true
	return false


func update(world: RefCounted, now: int, force: bool = false) -> void:
	var changed: bool = layout_seen != world.objects.layout_revision
	if changed:
		rebuild_loss(world)
	if not force and not changed and now < next_ms:
		return
	var started: int = Time.get_ticks_usec()
	next_ms = now + 200
	var origin: Vector2 = world.combat.position(world, 1)
	update_visible(world)
	if force or changed or origin.distance_squared_to(previous) > 0.01:
		previous = origin
		var nearby: Array[int] = world.objects.nearby(origin, RANGE)
		for id: int in memories.keys():
			if sees_object(origin, memories[id]) and not nearby.has(id):
				memories.erase(id)
		for id: int in nearby:
			var rec: Dictionary = world.objects.records[id]
			if not sees_object(origin, rec):
				continue
			memories[id] = {"id": id, "kind": rec.kind, "definition": rec.definition, "tile": rec.tile,
				"cells": rec.get("cells", PackedInt32Array([rec.tile])).duplicate(), "layer": rec.get("layer", "ground"),
				"stage": rec.get("stage", -1), "sapient": rec.get("sapient", false)}
		# Exploration raster only for the player. Rays bound this work, while
		# the display circle uses continuous coordinates at render frequency.
		for ray: int in 192:
			var direction := Vector2.from_angle(float(ray) / 192.0 * TAU)
			var spent: float = 0
			var last: int = -1
			for step: int in range(1, 49):
				var point: Vector2 = origin + direction * step * 0.5
				if point.x < 0 or point.y < 0 or point.x >= Terrain.SIZE or point.y >= Terrain.SIZE:
					break
				var tile: int = Terrain.index(Vector2i(point))
				spent += 0.5
				if spent > RANGE:
					break
				explored[tile] = 255
				if last != tile:
					spent += loss[tile]
				last = tile
		revision += 1
	work_usec += Time.get_ticks_usec() - started


func update_visible(world: RefCounted) -> void:
	var origin: Vector2 = world.combat.position(world, 1)
	visible.resize(world.attack_due.size())
	visible.fill(0)
	for page: RefCounted in world.pages:
		for row: int in page.ids.size():
			var id: int = page.ids[row]
			if id > 0 and (id == 1 or sees(origin, Terrain.index(Vector2i(page.positions[row])))):
				visible[world.actor_slots[id]] = 1
