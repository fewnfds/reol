class_name SimSpatialQueries
extends RefCounted
## Independent segment/body candidates on one frozen boundary. Effects,
## cover, consumption and body mutation remain with the calling domain owner.

const CHUNK_SIZE: int = 64
const PARALLEL_MINIMUM: int = 4096 # Body × segment candidate pairs.

class Chunk extends RefCounted:
	var bodies: SimBodyReadView
	var starts: PackedVector2Array
	var ends: PackedVector2Array
	var excluded: PackedStringArray
	var levels: PackedInt32Array
	var radius: float
	var first: int
	var stop: int
	var targets := PackedInt32Array()
	var distances := PackedFloat64Array()
	var thread_id: int
	var started_usec: int
	var finished_usec: int

	func run() -> void:
		thread_id = OS.get_thread_caller_id()
		started_usec = Time.get_ticks_usec()
		# Resolve the shared read object's columns once per task. Repeated member
		# access inside every candidate pair adds cross-core reference traffic.
		var body_ids: PackedStringArray = bodies.ids
		var body_points: PackedVector2Array = bodies.points
		var body_levels: PackedInt32Array = bodies.levels
		targets.resize(starts.size())
		targets.fill(-1)
		distances.resize(starts.size())
		for shot: int in starts.size():
			var from: Vector2 = starts[shot]
			var to: Vector2 = ends[shot]
			var nearest: float = from.distance_to(to) + 1.0
			for row: int in range(first, stop):
				if body_ids[row] == excluded[shot] or body_levels[row] != levels[shot]:
					continue
				var point: Vector2 = body_points[row]
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(point, from, to)
				if closest.distance_to(point) > radius:
					continue
				var distance: float = closest.distance_to(from)
				if distance < nearest:
					nearest = distance
					targets[shot] = row
			distances[shot] = nearest
		finished_usec = Time.get_ticks_usec()

var chunks: Array[Chunk] = []
var execution := SimBatchExecution.new()


func start(bodies: SimBodyReadView, starts: PackedVector2Array, ends: PackedVector2Array, excluded: PackedStringArray, levels: PackedInt32Array, radius: float, workers: int = SimBatchExecution.DEFAULT_WORKERS) -> void:
	assert(starts.size() == ends.size() and starts.size() == excluded.size() and starts.size() == levels.size())
	var work: Array[RefCounted] = []
	for first: int in range(0, bodies.ids.size(), CHUNK_SIZE):
		var chunk := Chunk.new()
		chunk.bodies = bodies
		chunk.starts = starts
		chunk.ends = ends
		chunk.excluded = excluded
		chunk.levels = levels
		chunk.radius = radius
		chunk.first = first
		chunk.stop = mini(first + CHUNK_SIZE, bodies.ids.size())
		chunks.append(chunk)
		work.append(chunk)
	execution.start(work, workers if bodies.ids.size() * starts.size() >= PARALLEL_MINIMUM else 0)


func collect(segment_count: int) -> PackedInt32Array:
	execution.finish(true)
	var result := PackedInt32Array()
	result.resize(segment_count)
	result.fill(-1)
	var nearest := PackedFloat64Array()
	nearest.resize(segment_count)
	nearest.fill(INF)
	# Fixed chunk order and strict comparison retain the original first body
	# on equal distance; thread scheduling never determines the contact winner.
	for chunk: Chunk in chunks:
		for shot: int in segment_count:
			if chunk.targets[shot] >= 0 and chunk.distances[shot] < nearest[shot]:
				result[shot] = chunk.targets[shot]
				nearest[shot] = chunk.distances[shot]
	return result
