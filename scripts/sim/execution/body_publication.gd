class_name SimBodyPublication
extends RefCounted
## Detached complete body presentation. Original dictionaries are lent only
## during the read phase; no owner advances until collection. Published rows
## retain values and private pose dictionaries, never bodies or action tables.
const CHUNK_SIZE: int = 64
const PARALLEL_MINIMUM: int = 256

class Chunk extends RefCounted:
	var roster: Array[Dictionary]
	var first: int
	var stop: int
	var completions: Dictionary
	var region: String
	var poses: HumanoidPose.WorldFrame
	var journey: Dictionary
	var local_action: Dictionary
	var manual_moving: bool
	var clothing_worn: Dictionary
	var clothing_objects: Dictionary
	var clothing_types: Dictionary
	var wet_threshold: int
	var rows: Array[Dictionary] = []
	var started_usec: int
	var finished_usec: int
	var thread_id: int

	func run() -> void:
		started_usec = Time.get_ticks_usec()
		thread_id = OS.get_thread_caller_id()
		for index: int in range(first, stop):
			var id: String = roster[index].id
			var body: Dictionary = roster[index].body
			var completion: Dictionary = completions.get(id, {})
			var timeline: SimRouteTravel.Timeline = completion.timeline if bool(completion.get("coarse", false)) and is_same(completion.route, body.active) and body.active.get("phase") == "travel" else null
			var leg: int = -1
			var point: Vector2
			if body.active.get("phase") == "travel":
				if timeline != null:
					leg = timeline.leg_at(poses.at_ms)
					point = timeline.point_on_leg(poses.at_ms, leg)
				else:
					point = SimRouteTravel.projected_point(body.active, body, poses.at_ms)
			else:
				point = SimRouteTravel.point(body)
			var clothing: Dictionary = {}
			for slot: String in ["body", "outer"]:
				var garment_id: String = str(clothing_worn.get(id, {}).get(slot, ""))
				if garment_id.is_empty():
					continue
				var garment: Dictionary = clothing_objects[garment_id]
				clothing[slot] = {"shape": clothing_types[garment.type].shape, "color": garment.color, "wet": int(garment.wet) >= wet_threshold}
			rows.append({"id": id, "region": region, "definition_id": str(body.definition_id),
				"alive": bool(body.alive), "point": point, "cell": TileGrid.world_to_cell(point),
				"clothing": clothing,
				"pose": poses.pose_read(timeline, id, body, leg, journey if id == "player" else {}, manual_moving if id == "player" else false, local_action if id == "player" else {})})
		# Stop retaining lent inputs before announcing completion.
		roster = []
		completions = {}
		poses = null
		journey = {}
		local_action = {}
		clothing_worn = {}
		clothing_objects = {}
		clothing_types = {}
		finished_usec = Time.get_ticks_usec()

var world_id: int
var at_ms: int
var rows: Dictionary[String, Dictionary] = {}
var work: Dictionary = {}


static func capture(world: RegionalSimulation, now: int, workers: int = 4, selected: Array[String] = [], journey: Dictionary = {}, manual_moving: bool = false, local_action: Dictionary = {}) -> SimBodyPublication:
	var started: int = Time.get_ticks_usec()
	var frame := SimBodyPublication.new()
	frame.world_id = world.get_instance_id()
	frame.at_ms = now
	var poses := HumanoidPose.WorldFrame.new(world, now)
	var chunks: Array[RefCounted] = []
	var count: int = 0
	for region: String in world.regions:
		var sim: VillageSimulation = world.regions[region]
		var roster: Array[Dictionary] = sim.body_read_roster()
		count += roster.size()
		for first: int in range(0, roster.size(), CHUNK_SIZE):
			var chunk := Chunk.new()
			chunk.roster = roster
			chunk.first = first
			chunk.stop = mini(first + CHUNK_SIZE, roster.size())
			chunk.completions = sim.native_route_projections()
			chunk.region = region
			chunk.poses = poses
			chunk.journey = journey
			chunk.manual_moving = manual_moving
			chunk.local_action = local_action
			chunk.clothing_worn = world.clothing._worn
			chunk.clothing_objects = world.clothing.objects
			chunk.clothing_types = world.clothing.definitions.types
			chunk.wet_threshold = int(world.clothing.definitions.wet_threshold)
			chunks.append(chunk)
	var preparation: int = Time.get_ticks_usec() - started
	var batch := SimBatchExecution.new()
	batch.start(chunks, workers if count >= PARALLEL_MINIMUM else 0)
	batch.finish(true)
	var adopt_started: int = Time.get_ticks_usec()
	var worker_usec: int = 0
	var threads: Dictionary = {}
	for chunk: Chunk in chunks:
		worker_usec += chunk.finished_usec - chunk.started_usec
		threads[chunk.thread_id] = true
		for row: Dictionary in chunk.rows:
			if str(row.id) == "player" or str(row.id) in selected:
				var sim: VillageSimulation = world.regions[row.region]
				var needs: Dictionary = sim.projected_actor_needs(str(row.id))
				var surface: Dictionary = {}
				for key: String in ["definition_id", "hunger", "energy", "qi", "stamina", "mood", "rank_id"]:
					surface[key] = needs[key]
				if str(row.id) == "player":
					var elapsed: int = maxi(0, int(world.current_time) - sim.tick_index)
					surface.hunger = maxf(0.0, float(surface.hunger) - float(sim.config.needs.hunger_per_minute) * elapsed)
					var rate: float = float(sim.config.needs.energy_per_minute) + (float(sim.config.needs.work_energy_per_minute) if not needs.active.is_empty() else 0.0)
					surface.energy = maxf(0.0, float(surface.energy) - rate * elapsed)
				row["needs"] = surface
			frame.rows[str(row.id)] = row
	frame.work = {"rows": count, "parallel": batch.parallel, "workers": batch.worker_count, "prepare_usec": preparation,
		"dispatch_usec": batch.dispatch_usec, "elapsed_usec": batch.completed_usec - batch.submitted_usec,
		"worker_usec": worker_usec, "adopt_usec": Time.get_ticks_usec() - adopt_started, "threads": threads.keys()}
	return frame
