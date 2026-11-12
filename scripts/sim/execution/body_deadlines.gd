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
	var rows := PackedInt64Array()
	var started_usec: int
	var finished_usec: int
	var thread_id: int
	var fallback_count: int

	func run() -> void:
		started_usec = Time.get_ticks_usec()
		thread_id = OS.get_thread_caller_id()
		rows.resize((stop - first) * 3)
		var row := Query.new()
		for index: int in range(first, stop):
			row.evaluate(read, str(ids[index]))
			var offset: int = (index - first) * 3
			rows[offset] = row.boundary
			rows[offset + 1] = row.effect
			rows[offset + 2] = int(row.allowed) | (int(row.accepted) << 1) | (int(row.coarse) << 2) | (int(row.fallback) << 3)
			fallback_count += int(row.fallback)
		read = null
		ids = []
		finished_usec = Time.get_ticks_usec()

class Query extends RefCounted:
	var boundary: int
	var effect: int
	var allowed: bool
	var accepted: bool
	var coarse: bool
	var fallback: bool

	func evaluate(input: SimBodyRead, id: String) -> void:
		var body: Dictionary = input.actors[id]
		boundary = SimInventory.MAX_COUNT
		effect = SimInventory.MAX_COUNT
		allowed = false
		accepted = false
		coarse = false
		fallback = false
		if not bool(body.alive):
			return
		var route: Dictionary = body.active
		if route.is_empty():
			if bool(body.autonomous):
				self.boundary = maxi(input.at_ms + 1, int(body.retry_ms))
				self.effect = self.boundary
			return
		allowed = input.controls_action(id)
		var completion: Dictionary = input.completions.get(id, {})
		accepted = allowed and input.route_events and route.get("phase") == "travel" and not completion.is_empty() and is_same(completion.route, route) and int(completion.revision) == input.geometry_revision
		var precise: bool = accepted and input.precise_crossings(id)
		coarse = accepted and not route.path.is_empty() and not precise and not input.stock_crossing(body, completion)
		if bool(completion.get("coarse", false)) and not coarse:
			self.fallback = true # Materialization may notify other original owners.
			return
		var timeout: int = int(route.started_ms) + input.timeout_ms + 1
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
			self.fallback = true # Unknown/changed geometry uses the original executor.
			return
		self.effect = mini(int(completion.at_ms), timeout) if accepted else boundary
		return

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


func read_row(index: int, row: Query) -> void:
	@warning_ignore("integer_division")
	var chunk: Chunk = chunks[index / CHUNK_SIZE]
	var offset: int = (index % CHUNK_SIZE) * 3
	row.boundary = chunk.rows[offset]
	row.effect = chunk.rows[offset + 1]
	var flags: int = chunk.rows[offset + 2]
	row.allowed = (flags & 1) != 0
	row.accepted = (flags & 2) != 0
	row.coarse = (flags & 4) != 0
	row.fallback = (flags & 8) != 0
