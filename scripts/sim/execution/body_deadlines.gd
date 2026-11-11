class_name SimBodyDeadlines
extends RefCounted
## Independent next-boundary judgments over a body read lease. Geometry repairs
## and transitions out of a coarse route stay with the owner, in ID order.
const CHUNK_SIZE: int = 64
const PARALLEL_MINIMUM: int = 128

class Chunk extends RefCounted:
	var read: SimBodyRead
	var ids: Array
	var first: int
	var stop: int
	var rows: Array[Dictionary] = []
	var started_usec: int
	var finished_usec: int
	var thread_id: int
	var fallback_count: int

	func run() -> void:
		started_usec = Time.get_ticks_usec()
		thread_id = OS.get_thread_caller_id()
		for index: int in range(first, stop):
			var row: Dictionary = query(read, str(ids[index]))
			rows.append(row)
			fallback_count += int(row.fallback)
		read = null
		ids = []
		finished_usec = Time.get_ticks_usec()

	static func query(input: SimBodyRead, id: String) -> Dictionary:
		var body: Dictionary = input.actors[id]
		var row: Dictionary = {"boundary": SimInventory.MAX_COUNT, "effect": SimInventory.MAX_COUNT,
			"allowed": false, "accepted": false, "coarse": false, "fallback": false}
		if not bool(body.alive):
			return row
		var route: Dictionary = body.active
		if route.is_empty():
			if bool(body.autonomous):
				row.boundary = maxi(input.at_ms + 1, int(body.retry_ms))
				row.effect = row.boundary
			return row
		var allowed: bool = input.controls_action(id)
		row.allowed = allowed
		var completion: Dictionary = input.completions.get(id, {})
		var accepted: bool = allowed and input.route_events and route.get("phase") == "travel" and not completion.is_empty() and is_same(completion.route, route) and int(completion.revision) == input.geometry_revision
		row.accepted = accepted
		var precise: bool = accepted and input.precise_crossings(id)
		var coarse: bool = accepted and not route.path.is_empty() and not precise and not input.stock_crossing(body, completion)
		row.coarse = coarse
		if bool(completion.get("coarse", false)) and not coarse:
			row.fallback = true # Materialization may notify other original owners.
			return row
		var timeout: int = int(route.started_ms) + input.timeout_ms + 1
		var boundary: int
		if not allowed:
			boundary = input.at_ms + 1
		elif coarse:
			boundary = maxi(input.at_ms + 1, mini(int(completion.at_ms), timeout))
		elif accepted and not precise and not input.stock_crossing(body):
			boundary = maxi(input.at_ms + 1, mini(int(route.due_ms), timeout))
		elif accepted:
			boundary = maxi(input.at_ms + 1, mini(mini(int(route.due_ms), timeout), SimRouteTravel.crossing_ms(route, body, input.at_ms)))
		elif route.get("phase") != "travel":
			boundary = maxi(input.at_ms + 1, mini(int(route.due_ms), timeout))
		else:
			row.fallback = true # Unknown/changed geometry uses the original executor.
			return row
		row.boundary = boundary
		row.effect = mini(int(completion.at_ms), timeout) if accepted else boundary
		return row

var chunks: Array[Chunk] = []
var execution := SimBatchExecution.new()
var preparation_usec: int
var has_fallback: bool = false


func compute(read: SimBodyRead, ids: Array, workers: int) -> void:
	var began: int = Time.get_ticks_usec()
	var work: Array[RefCounted] = []
	for first: int in range(0, ids.size(), CHUNK_SIZE):
		var chunk := Chunk.new()
		chunk.read = read
		chunk.ids = ids
		chunk.first = first
		chunk.stop = mini(first + CHUNK_SIZE, ids.size())
		chunks.append(chunk)
		work.append(chunk)
	preparation_usec = Time.get_ticks_usec() - began
	execution.start(work, workers)
	execution.finish(true)
	for chunk: Chunk in chunks:
		has_fallback = has_fallback or chunk.fallback_count > 0


func row_at(index: int) -> Dictionary:
	@warning_ignore("integer_division")
	return chunks[index / CHUNK_SIZE].rows[index % CHUNK_SIZE]
