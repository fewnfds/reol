class_name SimActorAdvance
extends RefCounted
## Packed calculation input/output for original bodies. IDs and adoption tokens
## stay on the owner thread. No inventory, world callbacks or saved state here.

const MINUTE_MS: int = 60000
const NEED_SCALE: int = 1000000
const MAX_NEED_BALANCE: int = 100 * NEED_SCALE * MINUTE_MS
const CHUNK_SIZE: int = 32
const PARALLEL_MINIMUM: int = 64
enum InputField { HUNGER, HUNGER_CARRY, ENERGY, ENERGY_CARRY, HUNGER_RATE, ENERGY_RATE,
	FROM_MS, TO_MS, STAMINA, STAMINA_CARRY, MAX_STAMINA, STAMINA_RATE, RECOVER,
	EXERTION_MS, SEGMENT_MS, DUE_MS, MOVING, STRIDE }
enum PointField { CURRENT, ORIGIN, TARGET, FACING, STRIDE }
enum OutputField { HUNGER, ENERGY, STAMINA, STAMINA_CARRY, STRIDE }

class Chunk extends RefCounted:
	var input := PackedInt64Array()
	var points := PackedVector2Array()
	var output := PackedInt64Array()
	var poses := PackedVector2Array()
	var thread_id: int = 0
	var started_usec: int = 0
	var finished_usec: int = 0

	func seal() -> void:
		@warning_ignore("integer_division")
		var count: int = input.size() / InputField.STRIDE
		output.resize(count * OutputField.STRIDE)
		poses.resize(count * 2)

	func run() -> void:
		thread_id = OS.get_thread_caller_id()
		started_usec = Time.get_ticks_usec()
		@warning_ignore("integer_division")
		var count: int = input.size() / InputField.STRIDE
		for row: int in count:
			var i: int = row * InputField.STRIDE
			var o: int = row * OutputField.STRIDE
			var p: int = row * PointField.STRIDE
			var duration: int = input[i + InputField.TO_MS] - input[i + InputField.FROM_MS]
			output[o + OutputField.HUNGER] = SimActorAdvance.need_balance(input[i + InputField.HUNGER], input[i + InputField.HUNGER_CARRY], input[i + InputField.HUNGER_RATE], duration)
			output[o + OutputField.ENERGY] = SimActorAdvance.need_balance(input[i + InputField.ENERGY], input[i + InputField.ENERGY_CARRY], input[i + InputField.ENERGY_RATE], duration)
			var stamina: int = input[i + InputField.STAMINA]
			var carry: int = input[i + InputField.STAMINA_CARRY]
			if input[i + InputField.RECOVER] != 0:
				var recovery_ms: int = maxi(0, input[i + InputField.TO_MS] - maxi(input[i + InputField.FROM_MS], input[i + InputField.EXERTION_MS]))
				var gain: int = SimActorAdvance.stamina_gain(stamina, input[i + InputField.MAX_STAMINA], carry, input[i + InputField.STAMINA_RATE], recovery_ms)
				@warning_ignore("integer_division")
				var units: int = gain / 1000
				stamina = mini(input[i + InputField.MAX_STAMINA], stamina + units)
				carry = gain % 1000 if stamina < input[i + InputField.MAX_STAMINA] else 0
			output[o + OutputField.STAMINA] = stamina
			output[o + OutputField.STAMINA_CARRY] = carry
			var point: Vector2 = points[p + PointField.CURRENT]
			var facing: Vector2 = points[p + PointField.FACING]
			if input[i + InputField.MOVING] != 0:
				var origin: Vector2 = points[p + PointField.ORIGIN]
				var target: Vector2 = points[p + PointField.TARGET]
				var ratio: float = clampf(float(input[i + InputField.TO_MS] - input[i + InputField.SEGMENT_MS]) / float(input[i + InputField.DUE_MS] - input[i + InputField.SEGMENT_MS]), 0.0, 1.0)
				var next: Vector2 = origin.lerp(target, ratio)
				if not point.is_equal_approx(next) and not (target - origin).is_zero_approx():
					facing = (target - origin).normalized()
				point = next
			poses[row * 2] = point
			poses[row * 2 + 1] = facing
		finished_usec = Time.get_ticks_usec()

var at_ms: int = 0
var generation: int = 0
var dependency_revision: int = 0
var preparation_usec: int = 0
var measured: bool = false
var ids: Array[String] = []
var anchors := PackedInt64Array()
var action_ids: Array[String] = []
var chunks: Array[Chunk] = []
var execution := SimBatchExecution.new()
var _rows: Dictionary[String, int] = {}


func append(id: String, body: Dictionary, previous_ms: int, hunger_rate: int, energy_rate: int, recover: bool, max_stamina: int, stamina_rate: int) -> void:
	if ids.size() % CHUNK_SIZE == 0:
		chunks.append(Chunk.new())
	_rows[id] = ids.size()
	ids.append(id)
	anchors.append(previous_ms)
	var route: Dictionary = body.active
	var moving: bool = route.get("phase") == "travel" and not route.path.is_empty()
	action_ids.append(str(route.get("id", "")))
	var current: Vector2 = SimRouteTravel.point(body)
	var origin: Vector2 = Vector2(float(route.segment_from[0]), float(route.segment_from[1])) if moving else current
	var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(route.path[0])) if moving else current
	chunks.back().input.append_array(PackedInt64Array([
		roundi(float(body.hunger) * NEED_SCALE), int(body.need_carry.hunger),
		roundi(float(body.energy) * NEED_SCALE), int(body.need_carry.energy), hunger_rate, energy_rate,
		previous_ms, at_ms, int(body.stamina), int(body.stamina_carry), max_stamina, stamina_rate,
		int(recover), int(body.exertion_until_ms), int(route.segment_started_ms) if moving else 0,
		int(route.due_ms) if moving else 0, int(moving)]))
	chunks.back().points.append_array(PackedVector2Array([current, origin, target, SimRouteTravel.facing(body)]))


func start(workers: int) -> void:
	var started: int = Time.get_ticks_usec()
	var work: Array[RefCounted] = []
	for chunk: Chunk in chunks:
		chunk.seal()
		work.append(chunk)
	preparation_usec = Time.get_ticks_usec() - started
	execution.start(work, workers if ids.size() >= PARALLEL_MINIMUM else 0)


func row_for(id: String) -> Vector2i:
	var index: int = int(_rows.get(id, -1))
	@warning_ignore("integer_division")
	return Vector2i(index / CHUNK_SIZE, index % CHUNK_SIZE) if index >= 0 else Vector2i(-1, -1)


func motion_matches(id: String, body: Dictionary, route: Dictionary) -> bool:
	var index: int = int(_rows.get(id, -1))
	if index < 0 or action_ids[index] != str(route.get("id", "")):
		return false
	var row: Vector2i = row_for(id)
	var chunk: Chunk = chunks[row.x]
	var i: int = row.y * InputField.STRIDE
	var p: int = row.y * PointField.STRIDE
	return chunk.input[i + InputField.MOVING] != 0 and not route.path.is_empty() and int(route.segment_started_ms) == chunk.input[i + InputField.SEGMENT_MS] and int(route.due_ms) == chunk.input[i + InputField.DUE_MS] and SimRouteTravel.point(body) == chunk.points[p + PointField.CURRENT] and Vector2(float(route.segment_from[0]), float(route.segment_from[1])) == chunk.points[p + PointField.ORIGIN] and TileGrid.cell_to_world(SimRouteTravel.cell(route.path[0])) == chunk.points[p + PointField.TARGET]


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
