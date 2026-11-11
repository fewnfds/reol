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
	ANCHOR, SEGMENT_MS, DUE_MS, MOVING, ALIVE, PATH_SIZE, COARSE_LEG, CROSSING_MS, NEXT_BOUNDARY, STRIDE }

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
	var routes: Array[Dictionary] = []
	var timelines: Array[SimRouteTravel.Timeline] = []
	var thread_id: int = 0
	var started_usec: int = 0
	var finished_usec: int = 0
	var projection_proven: bool = true

	func seal() -> void:
		var count: int = stop - first
		output.resize(count * OutputField.STRIDE)
		points.resize(count * PointField.STRIDE)
		poses.resize(count * 2)
		action_ids.resize(count)
		routes.resize(count)
		timelines.resize(count)

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
				projection_proven = projection_proven and body.active.is_empty()
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
			routes[row] = route
			output[o + OutputField.COARSE_LEG] = -1
			if moving:
				var origin := Vector2(float(route.segment_from[0]), float(route.segment_from[1]))
				var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(route.path[0]))
				points[p + PointField.ORIGIN] = origin
				points[p + PointField.TARGET] = target
				output[o + OutputField.SEGMENT_MS] = int(route.segment_started_ms)
				output[o + OutputField.DUE_MS] = int(route.due_ms)
				output[o + OutputField.PATH_SIZE] = route.path.size()
				var completion: Dictionary = read.completions.get(id, {})
				projection_proven = projection_proven and read.route_events and not completion.is_empty() and is_same(completion.route, route) and int(completion.revision) == read.geometry_revision
				var timeline: SimRouteTravel.Timeline = completion.timeline if bool(completion.get("coarse", false)) and is_same(completion.route, route) else null
				if timeline != null:
					var leg: int = timeline.leg_at(at_ms)
					output[o + OutputField.COARSE_LEG] = leg
					timelines[row] = timeline
					point = timeline.point_on_leg(at_ms, leg)
					facing = timeline.heading_on_leg(at_ms, leg, facing)
				else:
					point = SimRouteTravel.projected_point(route, body, at_ms)
					if not SimRouteTravel.point(body).is_equal_approx(point) and not (target - origin).is_zero_approx():
						facing = (target - origin).normalized()
					var before: Vector2i = SimRouteTravel.cell(body.cell)
					if before != TileGrid.world_to_cell(point):
						output[o + OutputField.CROSSING_MS] = SimRouteTravel.crossing_from_cell_ms(route, before, int(route.segment_started_ms))
					if bool(read.continuations.get(id, false)) and int(read.boundaries.get(id, -1)) == at_ms and int(route.due_ms) > at_ms and TileGrid.world_to_cell(point) == SimRouteTravel.cell(route.path[0]):
						output[o + OutputField.NEXT_BOUNDARY] = mini(int(route.due_ms), int(route.started_ms) + read.timeout_ms + 1)
			poses[row * 2] = point
			poses[row * 2 + 1] = facing
		read = null
		ids = []
		finished_usec = Time.get_ticks_usec()

class ProjectionCheck extends RefCounted:
	var calculation: SimActorAdvance
	var actors: Dictionary
	var completions: Dictionary
	var first: int
	var stop: int
	var valid: bool = true

	func run() -> void:
		for index: int in range(first, stop):
			var id: String = calculation.ids[index]
			var body: Dictionary = actors[id]
			var route: Dictionary = body.active
			var moving: bool = route.get("phase") == "travel" and not route.path.is_empty()
			var row: Vector2i = calculation.row_for(id)
			var chunk: Chunk = calculation.chunks[row.x]
			if moving != (chunk.output[row.y * OutputField.STRIDE + OutputField.MOVING] != 0):
				valid = false
				break
			if moving:
				var completion: Dictionary = completions.get(id, {})
				var timeline: SimRouteTravel.Timeline = completion.timeline if bool(completion.get("coarse", false)) and is_same(completion.route, route) else null
				if calculation.motion_row(id, body, route, timeline).x < 0:
					valid = false
					break
		actors = {}
		completions = {}
		calculation = null

class AdoptionChunk extends RefCounted:
	## The owner lends disjoint original body fields only AFTER validation.
	## Motion requires a complete input and observer-isolation proof; needs
	## retain their anchor check. No effects/queries run until every writer joins.
	var calculation: SimActorAdvance
	var actors: Dictionary
	var anchors: Dictionary
	var ids: Array
	var first: int
	var stop: int
	var project_motion: bool = false
	var adopted: Array[String] = []
	var fallback: Array[String] = []
	var precise_count: int = 0
	var coarse_count: int = 0
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
			var body: Dictionary = actors[id]
			if int(anchors.get(id, calculation.at_ms)) != output[o + OutputField.ANCHOR]:
				fallback.append(id)
			else:
				if output[o + OutputField.ALIVE] != 0:
					if output[o + OutputField.HUNGER_RATE] != 0:
						SimActorAdvance.write_need(body, "hunger", output[o + OutputField.HUNGER])
					if output[o + OutputField.ENERGY_RATE] != 0:
						SimActorAdvance.write_need(body, "energy", output[o + OutputField.ENERGY])
					body.stamina = output[o + OutputField.STAMINA]
					body.stamina_carry = output[o + OutputField.STAMINA_CARRY]
				adopted.append(id)
			if project_motion and output[o + OutputField.MOVING] != 0:
				var chunk: Chunk = calculation.chunks[row.x]
				SimRouteTravel.put(body, chunk.poses[row.y * 2])
				var heading: Vector2 = chunk.poses[row.y * 2 + 1]
				body.facing = [heading.x, heading.y]
				var leg: int = int(output[o + OutputField.COARSE_LEG])
				if leg >= 0:
					chunk.timelines[row.y].materialize_leg(body.active, leg)
					coarse_count += 1
				else:
					precise_count += 1
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
var projection_check_work: Dictionary = {}
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


func motion_row(id: String, body: Dictionary, route: Dictionary, timeline: SimRouteTravel.Timeline = null) -> Vector2i:
	# Prior ordered observers can replace a later body's route or cursor. The
	# original object, cursor, point and coarse proof must still be the same;
	# otherwise its owner runs the existing projection/repair path.
	var row: Vector2i = row_for(id)
	if row.x < 0:
		return row
	var chunk: Chunk = chunks[row.x]
	if not is_same(chunk.routes[row.y], route) or not is_same(chunk.timelines[row.y], timeline) or chunk.action_ids[row.y] != str(route.get("id", "")):
		return Vector2i(-1, -1)
	var o: int = row.y * OutputField.STRIDE
	var p: int = row.y * PointField.STRIDE
	if chunk.output[o + OutputField.MOVING] == 0 or route.path.is_empty() or route.path.size() != chunk.output[o + OutputField.PATH_SIZE]:
		return Vector2i(-1, -1)
	if int(route.segment_started_ms) != chunk.output[o + OutputField.SEGMENT_MS] or int(route.due_ms) != chunk.output[o + OutputField.DUE_MS]:
		return Vector2i(-1, -1)
	if SimRouteTravel.point(body) != chunk.points[p + PointField.CURRENT] or SimRouteTravel.facing(body) != chunk.points[p + PointField.FACING]:
		return Vector2i(-1, -1)
	if Vector2(float(route.segment_from[0]), float(route.segment_from[1])) != chunk.points[p + PointField.ORIGIN] or TileGrid.cell_to_world(SimRouteTravel.cell(route.path[0])) != chunk.points[p + PointField.TARGET]:
		return Vector2i(-1, -1)
	return row


func projection_is_proven() -> bool:
	for chunk: Chunk in chunks:
		if not chunk.projection_proven:
			return false
	return true


func projection_matches(actors: Dictionary, completions: Dictionary, workers: int) -> bool:
	# Validate all original inputs before ANY motion writer runs. A resource
	# callback between preparation and adoption may have changed a body even
	# when no geometry/control version changed. No observer runs in this pass.
	var began: int = Time.get_ticks_usec()
	var tasks: Array[RefCounted] = []
	for first: int in range(0, ids.size(), CHUNK_SIZE):
		var task := ProjectionCheck.new()
		task.calculation = self
		task.actors = actors
		task.completions = completions
		task.first = first
		task.stop = mini(first + CHUNK_SIZE, ids.size())
		tasks.append(task)
	var batch := SimBatchExecution.new()
	batch.start(tasks, workers)
	batch.finish(true)
	var valid: bool = true
	for task: ProjectionCheck in tasks:
		valid = valid and task.valid
	projection_check_work = {"projection_check_batches": 1, "projection_check_parallel_batches": int(batch.parallel),
		"projection_check_elapsed_usec": Time.get_ticks_usec() - began, "projection_check_rejected_batches": int(not valid)}
	return valid


func adopt_needs(actors: Dictionary, anchors: Dictionary, projecting: Array, workers: int, project_motion: bool = false) -> Array[String]:
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
		chunk.project_motion = project_motion
		work.append(chunk)
	var batch := SimBatchExecution.new()
	batch.start(work, workers)
	batch.finish(true)
	var fallback: Array[String] = []
	var count: int = 0
	var worker_usec: int = 0
	var precise_count: int = 0
	var coarse_count: int = 0
	var threads: Dictionary = {}
	for chunk: AdoptionChunk in work:
		# Only the owner writes the shared anchor index, after every private
		# body partition finishes. No two tasks ever write the same Dictionary.
		for id: String in chunk.adopted:
			anchors[id] = at_ms
		count += chunk.adopted.size()
		fallback.append_array(chunk.fallback)
		worker_usec += chunk.elapsed_usec
		precise_count += chunk.precise_count
		coarse_count += chunk.coarse_count
		threads[chunk.thread_id] = true
	adoption_work = {"adoption_batches": 1, "adoption_parallel_batches": int(batch.parallel),
		"adopted": count, "adoption_worker_usec": worker_usec, "adoption_elapsed_usec": Time.get_ticks_usec() - began,
		"adoption_dispatch_usec": batch.dispatch_usec, "discarded": fallback.size(), "threads": threads,
		"motion_partition_batches": int(project_motion), "motion_partition_parallel_batches": int(project_motion and batch.parallel),
		"motion_adopted": precise_count, "coarse_motion_adopted": coarse_count}
	adoption_work.merge(projection_check_work)
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
