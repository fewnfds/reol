class_name SimActorAdvance
extends RefCounted
## Read original hot tables in chunks; produce private numeric candidates.
## Input preparation no longer serially repacks every body and callback result.
## The lease ends before original bodies, routes or domain inputs can change.

const MINUTE_MS: int = 60000
const NEED_SCALE: int = 1000000
const MAX_NEED_BALANCE: int = 100 * NEED_SCALE * MINUTE_MS
const CHUNK_SIZE: int = 64
const PARALLEL_MINIMUM: int = 64
enum PointField { CURRENT, ORIGIN, TARGET, FACING, STRIDE }
enum OutputField { HUNGER, ENERGY, STAMINA, STAMINA_CARRY, HUNGER_RATE, ENERGY_RATE,
	ANCHOR, SEGMENT_MS, DUE_MS, MOVING, ALIVE, STRIDE }

class Chunk extends RefCounted:
	var read: SimBodyRead
	var ids: Array[String]
	var first: int
	var stop: int
	var at_ms: int
	var points := PackedVector2Array()
	var output := PackedInt64Array()
	var poses := PackedVector2Array()
	var action_ids: Array[String] = []
	var thread_id: int = 0
	var started_usec: int = 0
	var finished_usec: int = 0

	func seal() -> void:
		var count: int = stop - first
		output.resize(count * OutputField.STRIDE)
		points.resize(count * PointField.STRIDE)
		poses.resize(count * 2)
		action_ids.resize(count)

	func run() -> void:
		thread_id = OS.get_thread_caller_id()
		started_usec = Time.get_ticks_usec()
		for row: int in stop - first:
			var id: String = ids[first + row]
			var body: Dictionary = read.actors[id]
			var o: int = row * OutputField.STRIDE
			var p: int = row * PointField.STRIDE
			var previous: int = int(read.anchors.get(id, read.at_ms))
			output[o + OutputField.ANCHOR] = previous
			output[o + OutputField.ALIVE] = int(body.alive)
			if not bool(body.alive):
				continue
			var duration: int = at_ms - previous
			var energy: Vector2i = read.energy_input(id, body)
			output[o + OutputField.HUNGER_RATE] = read.hunger_rate
			output[o + OutputField.ENERGY_RATE] = energy.x
			output[o + OutputField.HUNGER] = SimActorAdvance.need_balance(roundi(float(body.hunger) * NEED_SCALE), int(body.need_carry.hunger), read.hunger_rate, duration)
			output[o + OutputField.ENERGY] = SimActorAdvance.need_balance(roundi(float(body.energy) * NEED_SCALE), int(body.need_carry.energy), energy.x, duration)
			var stamina: int = int(body.stamina)
			var carry: int = int(body.stamina_carry)
			if energy.y != 0:
				var maximum: int = int(read.pawns[StringName(body.definition_id)].max_stamina)
				var recovery_ms: int = maxi(0, at_ms - maxi(previous, int(body.exertion_until_ms)))
				var gain: int = SimActorAdvance.stamina_gain(stamina, maximum, carry, read.stamina_rate, recovery_ms)
				@warning_ignore("integer_division")
				var units: int = gain / 1000
				stamina = mini(maximum, stamina + units)
				carry = gain % 1000 if stamina < maximum else 0
			output[o + OutputField.STAMINA] = stamina
			output[o + OutputField.STAMINA_CARRY] = carry
			var route: Dictionary = body.active
			var moving: bool = route.get("phase") == "travel" and not route.path.is_empty()
			var point: Vector2 = SimRouteTravel.point(body)
			var facing: Vector2 = SimRouteTravel.facing(body)
			points[p + PointField.CURRENT] = point
			points[p + PointField.FACING] = facing
			output[o + OutputField.MOVING] = int(moving)
			action_ids[row] = str(route.get("id", ""))
			if moving:
				var origin := Vector2(float(route.segment_from[0]), float(route.segment_from[1]))
				var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(route.path[0]))
				points[p + PointField.ORIGIN] = origin
				points[p + PointField.TARGET] = target
				output[o + OutputField.SEGMENT_MS] = int(route.segment_started_ms)
				output[o + OutputField.DUE_MS] = int(route.due_ms)
				var ratio: float = clampf(float(at_ms - int(route.segment_started_ms)) / float(int(route.due_ms) - int(route.segment_started_ms)), 0.0, 1.0)
				var next: Vector2 = origin.lerp(target, ratio)
				if not point.is_equal_approx(next) and not (target - origin).is_zero_approx():
					facing = (target - origin).normalized()
				point = next
			poses[row * 2] = point
			poses[row * 2 + 1] = facing
		read = null
		ids = []
		finished_usec = Time.get_ticks_usec()

class AdoptionChunk extends RefCounted:
	## The owner lends disjoint original need fields only AFTER candidate
	## validation. Every reader has ended; no effects/queries run until join.
	var calculation: SimActorAdvance
	var actors: Dictionary
	var anchors: Dictionary
	var ids: Array
	var first: int
	var stop: int
	var adopted: Array[String] = []
	var fallback: Array[String] = []
	var elapsed_usec: int
	var thread_id: int

	func run() -> void:
		var began: int = Time.get_ticks_usec()
		thread_id = OS.get_thread_caller_id()
		for index: int in range(first, stop):
			var id: String = str(ids[index])
			var row: Vector2i = calculation.row_for(id)
			if row.x < 0:
				fallback.append(id)
				continue
			var output: PackedInt64Array = calculation.chunks[row.x].output
			var o: int = row.y * OutputField.STRIDE
			if int(anchors.get(id, calculation.at_ms)) != output[o + OutputField.ANCHOR]:
				fallback.append(id)
				continue
			var body: Dictionary = actors[id]
			if output[o + OutputField.ALIVE] != 0:
				if output[o + OutputField.HUNGER_RATE] != 0:
					SimActorAdvance.write_need(body, "hunger", output[o + OutputField.HUNGER])
				if output[o + OutputField.ENERGY_RATE] != 0:
					SimActorAdvance.write_need(body, "energy", output[o + OutputField.ENERGY])
				body.stamina = output[o + OutputField.STAMINA]
				body.stamina_carry = output[o + OutputField.STAMINA_CARRY]
			adopted.append(id)
		actors = {}
		anchors = {}
		ids = []
		calculation = null
		elapsed_usec = Time.get_ticks_usec() - began

var at_ms: int = 0
var generation: int = 0
var dependency_revision: int = 0
var preparation_usec: int = 0
var measured: bool = false
var ids: Array[String] = []
var chunks: Array[Chunk] = []
var execution := SimBatchExecution.new()
var adoption_work: Dictionary = {}
var _rows: Dictionary[String, int] = {}


func prepare(read: SimBodyRead, selected: Array[String], to_ms: int) -> void:
	var started: int = Time.get_ticks_usec()
	at_ms = to_ms
	ids = selected
	for index: int in ids.size():
		_rows[ids[index]] = index
	for first: int in range(0, ids.size(), CHUNK_SIZE):
		var chunk := Chunk.new()
		chunk.read = read
		chunk.ids = ids
		chunk.first = first
		chunk.stop = mini(first + CHUNK_SIZE, ids.size())
		chunk.at_ms = at_ms
		chunk.seal()
		chunks.append(chunk)
	preparation_usec = Time.get_ticks_usec() - started


func start(workers: int) -> void:
	var work: Array[RefCounted] = []
	for chunk: Chunk in chunks:
		work.append(chunk)
	execution.start(work, workers if ids.size() >= PARALLEL_MINIMUM else 0)


func row_for(id: String) -> Vector2i:
	var index: int = int(_rows.get(id, -1))
	@warning_ignore("integer_division")
	return Vector2i(index / CHUNK_SIZE, index % CHUNK_SIZE) if index >= 0 else Vector2i(-1, -1)


func motion_matches(id: String, body: Dictionary, route: Dictionary) -> bool:
	var row: Vector2i = row_for(id)
	if row.x < 0:
		return false
	var chunk: Chunk = chunks[row.x]
	if chunk.action_ids[row.y] != str(route.get("id", "")):
		return false
	var o: int = row.y * OutputField.STRIDE
	var p: int = row.y * PointField.STRIDE
	return chunk.output[o + OutputField.MOVING] != 0 and not route.path.is_empty() and int(route.segment_started_ms) == chunk.output[o + OutputField.SEGMENT_MS] and int(route.due_ms) == chunk.output[o + OutputField.DUE_MS] and SimRouteTravel.point(body) == chunk.points[p + PointField.CURRENT] and Vector2(float(route.segment_from[0]), float(route.segment_from[1])) == chunk.points[p + PointField.ORIGIN] and TileGrid.cell_to_world(SimRouteTravel.cell(route.path[0])) == chunk.points[p + PointField.TARGET]


func adopt_needs(actors: Dictionary, anchors: Dictionary, projecting: Array, workers: int) -> Array[String]:
	var began: int = Time.get_ticks_usec()
	var work: Array[RefCounted] = []
	for first: int in range(0, projecting.size(), CHUNK_SIZE):
		var chunk := AdoptionChunk.new()
		chunk.calculation = self
		chunk.actors = actors
		chunk.anchors = anchors
		chunk.ids = projecting
		chunk.first = first
		chunk.stop = mini(first + CHUNK_SIZE, projecting.size())
		work.append(chunk)
	var batch := SimBatchExecution.new()
	batch.start(work, workers)
	batch.finish(true)
	var fallback: Array[String] = []
	var count: int = 0
	var worker_usec: int = 0
	var threads: Dictionary = {}
	for chunk: AdoptionChunk in work:
		# Only the owner writes the shared anchor index, after every private
		# body partition finishes. No two tasks ever write the same Dictionary.
		for id: String in chunk.adopted:
			anchors[id] = at_ms
		count += chunk.adopted.size()
		fallback.append_array(chunk.fallback)
		worker_usec += chunk.elapsed_usec
		threads[chunk.thread_id] = true
	adoption_work = {"adoption_batches": 1, "adoption_parallel_batches": int(batch.parallel),
		"adopted": count, "adoption_worker_usec": worker_usec, "adoption_elapsed_usec": Time.get_ticks_usec() - began,
		"adoption_dispatch_usec": batch.dispatch_usec, "discarded": fallback.size(), "threads": threads}
	return fallback


static func need_balance(available: int, carry: int, rate: int, duration_ms: int) -> int:
	# Remaining fixed-point need, including its fractional debt. Saturate before
	# multiplication, retaining the existing huge-jump and recovery semantics.
	var balance: int = available * MINUTE_MS - carry
	if rate > 0:
		return 0 if duration_ms >= ceili(float(balance) / rate) else balance - rate * duration_ms
	if rate < 0:
		return MAX_NEED_BALANCE if duration_ms >= ceili(float(MAX_NEED_BALANCE - balance) / -rate) else balance - rate * duration_ms
	return balance


static func write_need(body: Dictionary, kind: String, balance: int) -> void:
	@warning_ignore("integer_division")
	var available: int = balance / MINUTE_MS + int(balance % MINUTE_MS != 0)
	body[kind] = float(available) / NEED_SCALE
	body.need_carry[kind] = available * MINUTE_MS - balance


static func stamina_gain(current: int, maximum: int, carry: int, rate: int, duration_ms: int) -> int:
	var missing: int = maximum - current
	return 0 if missing == 0 else carry + rate * mini(duration_ms, ceili(float(missing * 1000) / rate))
