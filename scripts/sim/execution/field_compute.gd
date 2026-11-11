class_name SimFieldCompute
extends RefCounted
## Same integer max-field equation and supercover transport as the existing
## CPU/GPU cache. Each tile owns its output; input is the original compact job.
const SIDE: int = 16
const CHANNELS: int = 7

class Tile extends RefCounted:
	var job: Dictionary
	var rect: Rect2i
	var values := PackedInt32Array()
	var thread_id: int
	var started_usec: int
	var finished_usec: int

	func run() -> void:
		thread_id = OS.get_thread_caller_id()
		started_usec = Time.get_ticks_usec()
		var params: PackedInt32Array = job.compute_params
		var slots: PackedInt32Array = job.slots
		var kernels: PackedInt32Array = job.kernels
		var offsets: PackedInt32Array = job.radius_offsets
		var geometry: PackedInt32Array = job.get("geometry", PackedInt32Array([0]))
		var capacity: int = params[2]
		values.resize(rect.get_area() * CHANNELS)
		# Source stamping visits only its intersecting footprint. Unlike a
		# receiver×all-sources scan this retains locality as source count grows.
		for slot: int in capacity:
			var radius: int = slots[capacity * 2 + slot]
			if radius <= 0:
				continue
			var source := Vector2i(slots[slot], slots[capacity + slot])
			var area: Rect2i = rect.intersection(Rect2i(source - Vector2i.ONE * (radius - 1), Vector2i.ONE * (radius * 2 - 1)))
			if not area.has_area():
				continue
			var strength_offset: int = capacity * 4 + slot * CHANNELS
			for y: int in range(area.position.y, area.end.y):
				for x: int in range(area.position.x, area.end.x):
					var weight: int = kernels[offsets[radius] + absi(y - source.y) * radius + absi(x - source.x)]
					if weight <= 0:
						continue
					var point := Vector2i(x, y)
					var transport: Vector2i = SimFieldCompute.transmission(geometry, source, point)
					var output: int = ((y - rect.position.y) * rect.size.x + x - rect.position.x) * CHANNELS
					for channel: int in CHANNELS:
						var strength: int = slots[strength_offset + channel]
						if strength <= values[output + channel]:
							continue
						@warning_ignore("integer_division")
						var grade: int = (strength * weight + 500000) / 1000000
						@warning_ignore("integer_division")
						grade = (grade * (transport.x if channel >= 5 else transport.y) + 5000) / 10000
						values[output + channel] = maxi(values[output + channel], grade)
		finished_usec = Time.get_ticks_usec()

var execution := SimBatchExecution.new()
var tiles: Array[RefCounted] = []
var job: Dictionary
var work: Dictionary = {}


func start(input: Dictionary, workers: int) -> void:
	job = input
	var params: PackedInt32Array = job.compute_params
	var area := Rect2i(params[4], params[5], params[6], params[7])
	for y: int in range(area.position.y, area.end.y, SIDE):
		for x: int in range(area.position.x, area.end.x, SIDE):
			var tile := Tile.new()
			tile.job = job
			tile.rect = Rect2i(Vector2i(x, y), Vector2i(mini(SIDE, area.end.x - x), mini(SIDE, area.end.y - y)))
			tiles.append(tile)
	execution.start(tiles, workers)


func collect() -> Dictionary:
	if not execution.finish():
		return {"ok": true, "pending": true}
	var started: int = Time.get_ticks_usec()
	var output := PackedInt32Array()
	var area: Rect2i = job.area
	output.resize(area.get_area() * CHANNELS)
	var local: PackedInt32Array = job.compute_params
	var thread_ids: Dictionary = {}
	var worker_usec: int = 0
	for tile: Tile in tiles:
		thread_ids[tile.thread_id] = true
		worker_usec += tile.finished_usec - tile.started_usec
		for row: int in tile.rect.size.y:
			var target: int = ((tile.rect.position.y + row - local[5]) * area.size.x + tile.rect.position.x - local[4]) * CHANNELS
			for index: int in tile.rect.size.x * CHANNELS:
				output[target + index] = tile.values[row * tile.rect.size.x * CHANNELS + index]
	var prepared: Dictionary = SimEnvironmentFieldCache.prepare_compute_result(job, output)
	work = {"parallel": execution.parallel, "workers": execution.worker_count, "tiles": tiles.size(), "worker_usec": worker_usec,
		"elapsed_usec": execution.completed_usec - execution.submitted_usec,
		"prepare_result_usec": Time.get_ticks_usec() - started, "threads": thread_ids.keys()}
	return {"ok": bool(prepared.get("ok", false)), "pending": false, "prepared": prepared, "metrics": work}


static func transmission(geometry: PackedInt32Array, from: Vector2i, to: Vector2i) -> Vector2i:
	if geometry[0] == 0 or from == to:
		return Vector2i(10000, 10000)
	var extent := Vector2i(absi(to.x - from.x), absi(to.y - from.y))
	if extent.x > geometry[5] or extent.y > geometry[5]:
		return Vector2i.ZERO
	var direction := Vector2i(signi(to.x - from.x), signi(to.y - from.y))
	var crossed := Vector2i.ZERO
	var at: Vector2i = from
	var thermal: int = 10000
	var elements: int = 10000
	while at != to:
		var x_cross: int = (1 + 2 * crossed.x) * extent.y
		var y_cross: int = (1 + 2 * crossed.y) * extent.x
		if x_cross == y_cross:
			var first: int = permeability(geometry, at + Vector2i(direction.x, 0))
			var second: int = permeability(geometry, at + Vector2i(0, direction.y))
			@warning_ignore("integer_division")
			thermal = (thermal * (first & 65535) / 10000) * (second & 65535) / 10000
			@warning_ignore("integer_division")
			elements = (elements * (first >> 16) / 10000) * (second >> 16) / 10000
			at += direction
			crossed += Vector2i.ONE
		elif x_cross < y_cross:
			at.x += direction.x
			crossed.x += 1
		else:
			at.y += direction.y
			crossed.y += 1
		if at != to:
			var term: int = permeability(geometry, at)
			@warning_ignore("integer_division")
			thermal = thermal * (term & 65535) / 10000
			@warning_ignore("integer_division")
			elements = elements * (term >> 16) / 10000
		if thermal == 0 and elements == 0:
			break
	return Vector2i(thermal, elements)


static func permeability(geometry: PackedInt32Array, cell: Vector2i) -> int:
	var local: Vector2i = cell - Vector2i(geometry[1], geometry[2])
	assert(local.x >= 0 and local.y >= 0 and local.x < geometry[3] and local.y < geometry[4])
	return geometry[6 + local.y * geometry[3] + local.x]
