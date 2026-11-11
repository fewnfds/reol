extends SceneTree
## Small checks for current execution primitives. No world/content assembly.

const Kernel = preload("res://scripts/sim/execution/settlement_kernel.gd")
const ActorBatch = preload("res://scripts/sim/actor_advance.gd")
const Inventory = preload("res://scripts/sim/inventory_ledger.gd")
const SUITES: Array[String] = ["settlement", "actor_batch", "inventory", "input", "presentation", "spatial"]

class NavigationReadCheck extends RefCounted:
	var graph := SimGridNavigation.Search.new(16, true)
	var view: SimWorldGeometry.ReadView
	var result: Array[Vector2i] = []
	func run() -> void:
		result = graph.find_path(Vector2i(116, 120), Vector2i(130, 120), view.is_walkable, view.can_step, 4096)


class SignalSource extends RefCounted:
	signal changed(value: int)


class SignalView extends Node:
	var seen: Array[int] = []
	func receive(value: int) -> void:
		seen.append(value)


class SignalWork extends RefCounted:
	var source: SignalSource
	func run() -> void:
		source.changed.emit(7)


func _spatial() -> bool:
	# Freeze once, change the authoritative terrain, then use the old input on
	# actual workers. It must remain readable but fail adoption as current data.
	var world := RegionalSimulation.new()
	world.bind_map_data(WorldMapData.from_descriptor(WorldMapData.flat_descriptor(17)))
	var patch: Array = []
	for y: int in range(100, 137):
		for x: int in range(100, 137):
			patch.append([x, y, WorldMapData.TERRAIN_GRASS])
	if not bool(world.map_data.apply_terrain_patch(patch).ok):
		return false
	var geometry: SimWorldGeometry = world.geometry_read()
	var view: SimWorldGeometry.ReadView = geometry.capture(Rect2i(100, 100, 37, 37))
	var built: int = int(geometry.work.built_pages)
	var repeated: SimWorldGeometry.ReadView = geometry.capture(view.bounds)
	if not geometry.is_current(view) or geometry.work.built_pages != built or repeated.pages != view.pages:
		return false
	var expected: Array[Vector2i] = SimGridNavigation.find_path(Vector2i(116, 120), Vector2i(130, 120), world.map_data.terrain_is_walkable, world.map_data.terrain_can_step, 16, 4096)
	if expected.is_empty() or not bool(world.map_data.apply_terrain_patch([[130, 120, WorldMapData.TERRAIN_ROCK]]).ok):
		return false
	if geometry.is_current(view) or not view.is_walkable(Vector2i(130, 120)) or geometry.is_walkable(Vector2i(130, 120)) or geometry.work.built_pages != built:
		return false
	var tasks: Array[RefCounted] = []
	for index: int in 2:
		var task := NavigationReadCheck.new()
		task.view = view
		tasks.append(task)
	var batch := SimBatchExecution.new()
	batch.start(tasks, 2)
	batch.finish(true)
	if not batch.parallel or tasks[0].result != expected or tasks[1].result != expected:
		return false
	world._retire_geometry()
	if geometry.is_current(view) or geometry.capture(view.bounds) != null or world.geometry_read().is_current(view):
		return false
	# Equal-distance targets straddle chunk boundaries. The first original row
	# wins even when another worker finishes first; shooter/height filters apply.
	var bodies := SimBodyReadView.new()
	for row: int in 512:
		bodies.ids.append(str(row))
		bodies.points.append(Vector2(200 + row * 4, 0))
		bodies.levels.append(0)
	bodies.points[0] = Vector2(10, 0)
	bodies.points[65] = Vector2(10, 0)
	var starts := PackedVector2Array()
	var ends := PackedVector2Array()
	var excluded := PackedStringArray()
	var levels := PackedInt32Array()
	for shot: int in 32:
		starts.append(Vector2.ZERO if shot != 31 else Vector2(0, 50))
		ends.append(Vector2(20, 0) if shot != 31 else Vector2(20, 50))
		excluded.append("0" if shot % 2 == 0 else "none")
		levels.append(0 if shot != 30 else 1)
	var serial := SimSpatialQueries.new()
	serial.start(bodies, starts, ends, excluded, levels, 1.0, 0)
	var parallel := SimSpatialQueries.new()
	parallel.start(bodies, starts, ends, excluded, levels, 1.0, 4)
	var expected_targets: PackedInt32Array = serial.collect(starts.size())
	if parallel.collect(starts.size()) != expected_targets or not parallel.execution.parallel:
		return false
	return expected_targets[0] == 65 and expected_targets[1] == 0 and expected_targets[30] == -1 and expected_targets[31] == -1 and _field_workers() and _body_publication() and _signal_handoff() and _response_input()


func _signal_handoff() -> bool:
	var source := SignalSource.new()
	var first := SignalView.new()
	var second := SignalView.new()
	source.changed.connect(first.receive)
	source.changed.connect(second.receive)
	var bridge := ReolSimulationSignalBridge.new()
	bridge.discover(source)
	bridge.lend()
	var task := SignalWork.new()
	task.source = source
	var execution := SimBatchExecution.new()
	execution.start([task, task] as Array[RefCounted], 2)
	execution.finish(true)
	var deferred: bool = first.seen.is_empty() and second.seen.is_empty()
	bridge.reclaim()
	var restored: bool = source.changed.is_connected(first.receive) and source.changed.is_connected(second.receive)
	var delivered: bool = first.seen == [7, 7] and second.seen == [7, 7]
	first.free()
	second.free()
	return deferred and restored and delivered


func _response_input() -> bool:
	var settings: Dictionary = {"climate": JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/climate.json")),
		"weather": JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/weather.json")),
		"weather_epoch_ms": 0, "seed": 17, "tau_ms": 30000, "tide_grid_ms": 60000}
	var compiler := SimEnvironmentTargetCompiler.new()
	var temperature := SimEnvironmentTemperatureState.new()
	var phases := SimEnvironmentPhaseState.new()
	if not compiler.configure(settings) or not temperature.configure(Vector2i(32, 32), 1024, 0) or not phases.configure(Vector2i(32, 32), 1024, 0):
		return false
	var channels := PackedInt32Array()
	for cell: int in 256:
		channels.append_array(PackedInt32Array([cell, 300, 100, 400, 700, 1300, 200]))
	var reference: Array[SimFieldResponseInput] = []
	var parallel: Array[RefCounted] = []
	for index: int in 4:
		var rect := Rect2i((index % 2) * 16, (index / 2) * 16, 16, 16)
		for mode: int in 2:
			var input := SimFieldResponseInput.new()
			input.tile = {"rect": rect, "channels": channels}
			input.compiler = compiler.fork()
			input.temperature = temperature
			input.phases = phases
			input.initial_temperature = func(_cell: Vector2i, _at: int) -> Dictionary: return {"ok": true, "value_c": 19.25}
			input.initial_phase = func(_cell: Vector2i, _at: int) -> Dictionary: return {"ok": true, "values": PackedFloat64Array([1, 2, 3, 4, 5])}
			input.at_ms = 100
			input.horizon_ms = 60000
			input.tau_ms = 30000
			input.grid_ms = 60000
			if mode == 0:
				input.run()
				reference.append(input)
			else:
				parallel.append(input)
	var execution := SimBatchExecution.new()
	execution.start(parallel, 4)
	execution.finish(true)
	for index: int in 4:
		var input: SimFieldResponseInput = parallel[index]
		if not input.error.is_empty() or input.thermal_columns != reference[index].thermal_columns or input.phase_columns != reference[index].phase_columns or input.temperature != null:
			return false
	return true


func _field_workers() -> bool:
	var field := SimEnvironmentGroundField.new()
	if not field.configure(Vector2i(32, 32), 32):
		return false
	var geometry := PackedInt32Array([1, 0, 0, 32, 32, 16])
	for y: int in 32:
		for x: int in 32:
			geometry.append((2000 | (8000 << 16)) if x == 16 and y % 7 != 0 else (10000 | (10000 << 16)))
	field.set_transport(func(from: Vector2i, to: Vector2i, channel: int) -> int:
		var factors: Vector2i = SimFieldCompute.transmission(geometry, from, to)
		return factors.x if channel >= 5 else factors.y)
	for slot: int in 12:
		if not field.set_source(slot, Vector2i(3 + (slot % 4) * 7, 3 + (slot / 4) * 9), 8, PackedInt32Array([100, slot * 70, 200, 300, 1000, 2000, 3000 - slot * 100])).ok:
			return false
	var area := Rect2i(0, 0, 32, 32)
	field.request_area(area)
	while field.diagnostics().pending_tiles > 0:
		if not field.rebuild(4, 1000000).ok:
			return false
	# Geometry snapshot has the same original coordinates in this full job.
	var job: Dictionary = field._export_compute_job(area, false)
	job.geometry = geometry
	var serial := SimFieldCompute.new()
	serial.start(job, 0)
	var expected: Dictionary = serial.collect()
	var parallel := SimFieldCompute.new()
	parallel.start(job, 4)
	parallel.execution.finish(true)
	var actual: Dictionary = parallel.collect()
	if not expected.ok or not actual.ok or not parallel.execution.parallel or expected.prepared.tiles != actual.prepared.tiles:
		return false
	for tile: Dictionary in actual.prepared.tiles:
		var rect: Rect2i = field._rect_for_tile(int(tile.id))
		for y: int in rect.size.y:
			for x: int in rect.size.x:
				var reference: Dictionary = field.read_base(rect.position + Vector2i(x, y))
				var offset: int = (y * rect.size.x + x) * 7
				if reference.channels != tile.values.slice(offset, offset + 7):
					return false
	return true


func _body_publication() -> bool:
	var world := RegionalSimulation.new()
	var poses := HumanoidPose.WorldFrame.new(world, 550)
	var action: Dictionary = {"phase": "travel", "path": [[2, 0], [2, 1]], "segment_from": [0.0, 0.0], "segment_started_ms": 0, "due_ms": 1000}
	var body: Dictionary = {"position": [0.0, 0.0], "cell": [0, 0], "facing": [1.0, 0.0], "active": action, "alive": true, "definition_id": "test"}
	var before: Dictionary = body.duplicate(true)
	var chunks: Array[RefCounted] = []
	for index: int in 2:
		var chunk := SimBodyPublication.Chunk.new()
		var id: String = "actor_" + str(index)
		chunk.roster = [{"id": id, "body": body}]
		chunk.first = 0
		chunk.stop = 1
		chunk.region = "home"
		chunk.completions = {id: {"route": action, "timeline": SimRouteTravel.Timeline.new(action, 100.0), "coarse": true}}
		chunk.poses = poses
		chunks.append(chunk)
	var batch := SimBatchExecution.new()
	batch.start(chunks, 2)
	batch.finish(true)
	if body != before or chunks[0].rows[0].pose != poses.pose_read(SimRouteTravel.Timeline.new(action, 100.0), "actor_0", body):
		return false
	var captured: Vector2 = chunks[0].rows[0].point
	body.position = [999.0, 999.0]
	return chunks[0].rows[0].point == captured and chunks[0].roster.is_empty()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var selected: Array[String] = []
	var arguments: PackedStringArray = OS.get_cmdline_user_args()
	var index: int = 0
	while index < arguments.size():
		if arguments[index] == "--list-suites":
			for name: String in SUITES:
				print(name)
			quit(0)
			return
		if arguments[index] != "--suite" or index + 1 >= arguments.size() or not SUITES.has(arguments[index + 1]):
			printerr("FAIL unknown smoke selection")
			quit(1)
			return
		selected.append(arguments[index + 1])
		index += 2
	var started: int = Time.get_ticks_usec()
	var completed: int = 0
	for name: String in SUITES:
		if not selected.is_empty() and not selected.has(name):
			continue
		print("RUN ", name)
		if call("_" + name) != true:
			printerr("FAIL ", name)
			quit(1)
			return
		completed += 1
		print("PASS ", name)
	print("Smoke: %d checks, %.3f ms; scope: execution primitives only" % [completed, (Time.get_ticks_usec() - started) / 1000.0])
	quit(0)


func _settlement() -> bool:
	var order: Array[String] = []
	var kernel := Kernel.new([&"effects"])
	# Registration and alphabetical order both disagree with the dependency.
	if not kernel.add_step(&"attack", &"effects", func(_at: int) -> void: order.append("attack"), Kernel.CallMode.TIMED, [&"heal"]):
		return false
	if not kernel.add_step(&"heal", &"effects", func(_at: int) -> void: order.append("heal")):
		return false
	if not kernel.compile() or not kernel.begin(0, 17):
		return false
	if kernel.resume(1) != Kernel.Status.PENDING or order != ["heal"]:
		return false
	if kernel.resume(1) != Kernel.Status.COMPLETE or order != ["heal", "attack"]:
		return false
	if kernel.resume(1) != Kernel.Status.COMPLETE or order != ["heal", "attack"]:
		return false
	var ready: Array[bool] = [false]
	if not kernel.set_completion_readiness(func(_at: int) -> bool: return ready[0]) or not kernel.begin(17, 50):
		return false
	if kernel.resume(8) != Kernel.Status.PENDING or kernel.progress().step != "publication" or order != ["heal", "attack", "heal", "attack"]:
		return false
	var executed: int = kernel.executed_steps
	if kernel.resume(8) != Kernel.Status.PENDING or kernel.executed_steps != executed:
		return false
	ready[0] = true
	return kernel.resume(8) == Kernel.Status.COMPLETE and kernel.executed_steps == executed and not kernel.is_pending() and _deadline_adoption()


func _deadline_adoption() -> bool:
	var serial := SimParticipationIndex.new()
	var batch := SimParticipationIndex.new()
	var updates: Dictionary[String, int] = {}
	for index: int in 64:
		updates["body_%02d" % index] = (index * 13) % 17
	if not batch.set_due_many(&"body", updates):
		return false
	for id: String in updates:
		serial.set_member(&"body", id)
		serial.set_due(&"body", id, updates[id])
	for round: int in 2:
		for time: int in [0, 5, 20, 100]:
			if batch.due_ids(&"body", time) != serial.due_ids(&"body", time):
				return false
		updates = {"body_03": 0, "new_body": 24}
		if not batch.set_due_many(&"body", updates, ["body_01", "body_03"]):
			return false
		for id: String in ["body_01", "body_03"]:
			serial.cancel_due(&"body", id)
		for id: String in updates:
			serial.set_member(&"body", id)
			serial.set_due(&"body", id, updates[id])
	var before: Array[String] = batch.due_ids(&"body", 100)
	return not batch.set_due_many(&"body", {"bad": -1}) and batch.due_ids(&"body", 100) == before


func _batch(workers: int) -> SimActorAdvance:
	var batch := ActorBatch.new()
	var body: Dictionary = {"alive": true, "definition_id": "sample", "active": {}, "position": [32.0, 32.0], "facing": [1.0, 0.0],
		"hunger": 80.0, "energy": 60.0, "need_carry": {"hunger": 0, "energy": 0},
		"stamina": 50, "stamina_carry": 0, "exertion_until_ms": 0}
	var read := SimBodyRead.new()
	read.hunger_rate = 1000000
	read.base_energy_rate = 2000000
	read.stamina_rate = 10
	var definition := PawnDef.new()
	definition.max_stamina = 100
	read.pawns[&"sample"] = definition
	var ids: Array[String] = []
	for row: int in 128:
		ids.append(str(row))
		read.actors[str(row)] = body
	batch.prepare(read, ids, 1500)
	batch.start(workers)
	batch.execution.finish(true)
	return batch


func _actor_batch() -> bool:
	if SimBatchExecution.resolve_workers(-1, 50, 20) != 18 or SimBatchExecution.resolve_workers(64, 50, 20) != 20 or SimBatchExecution.resolve_workers(-1, 3, 20) != 3 or SimBatchExecution.resolve_workers(-1, 1, 20) != 0 or SimBatchExecution.resolve_workers(-1, 50, 1) != 0 or SimBatchExecution.resolve_workers(0, 50, 20) != 0:
		return false
	# A resumed regional pass must finish its current publication before
	# preparing a later interval from inputs that are still being changed.
	var suspended := VillageSimulation.new()
	var authority := RegionalSimulation.new()
	suspended.actor_execution_enabled = true
	suspended._body_read_world = weakref(authority)
	suspended._sparse_actor_projection = true
	var revision_reads: Array[int] = [0]
	suspended._boundary_revision_provider = func() -> int: revision_reads[0] += 1; return 7
	suspended._native_advance = VillageSimulation.NativeAdvance.new()
	suspended._native_advance.phase = VillageSimulation.NativePhase.PROJECT
	if not suspended.prepare_actor_advance(200) or revision_reads[0] != 0 or suspended._prepared_actor_advance != null:
		return false
	var serial: SimActorAdvance = _batch(0)
	var parallel: SimActorAdvance = _batch(2)
	if not parallel.execution.parallel:
		return false
	for index: int in serial.chunks.size():
		if serial.chunks[index].output != parallel.chunks[index].output or serial.chunks[index].poses != parallel.chunks[index].poses:
			return false
	var bodies: Dictionary = {}
	var anchors: Dictionary = {}
	for id: String in serial.ids:
		bodies[id] = {"hunger": 80.0, "energy": 60.0, "need_carry": {"hunger": 0, "energy": 0}, "stamina": 50, "stamina_carry": 0}
		anchors[id] = 0
	anchors["10"] = 100 # This body's old input was already replaced.
	var rejected: Array[String] = serial.adopt_needs(bodies, anchors, serial.ids, 2)
	if rejected != ["10"] or anchors["10"] != 100 or bodies["10"].hunger != 80.0:
		return false
	if not is_equal_approx(float(bodies["0"].hunger), 79.975) or not is_equal_approx(float(bodies["0"].energy), 59.95) or bodies["0"].stamina != 65 or anchors["0"] != 1500:
		return false
	parallel.execution.cancel()
	return parallel.execution.cancelled and parallel.execution.finish() and _route_candidates()


func _route_candidates() -> bool:
	# A candidate must match the original projection, including exact vertices,
	# turns, crossing timestamps and a zero-length initial centering segment.
	for coarse: bool in [false, true]:
		for centering: bool in [false, true]:
			for now: int in [0, 1, 500, 1000, 1001, 2000]:
				var origin: Vector2 = TileGrid.cell_to_world(Vector2i.ZERO)
				var path: Array = [[1, 0], [1, 1]]
				if centering:
					path.push_front([0, 0])
				var route: Dictionary = {"id": "route", "phase": "travel", "action": "inspect", "path": path,
					"started_ms": 0, "segment_started_ms": 0, "segment_from": [origin.x, origin.y], "due_ms": 1 if centering else 1000}
				var body: Dictionary = {"alive": true, "active": route, "position": [origin.x, origin.y], "cell": [0, 0], "facing": [-1.0, 0.0],
					"hunger": 80.0, "energy": 60.0, "need_carry": {"hunger": 0, "energy": 0}, "stamina": 50, "stamina_carry": 0}
				var actual := VillageSimulation.new()
				actual._actors = {"body": body}
				var expected := VillageSimulation.new()
				expected._actors = actual._actors.duplicate(true)
				var timeline: SimRouteTravel.Timeline
				if coarse:
					timeline = SimRouteTravel.Timeline.new(route, 32.0)
					actual._route_completions = {"body": {"route": route, "timeline": timeline, "coarse": true}}
					expected._route_completions = {"body": {"route": expected._actors.body.active,
						"timeline": SimRouteTravel.Timeline.new(expected._actors.body.active, 32.0), "coarse": true}}
				var read := SimBodyRead.new()
				read.actors = actual._actors
				read.completions = actual._route_completions
				var calculation := ActorBatch.new()
				calculation.prepare(read, ["body"], now)
				calculation.start(0)
				if calculation.motion_row("body", body, route, timeline).x < 0 or calculation.motion_row("body", body, route.duplicate(true), timeline).x >= 0:
					return false
				# Earlier ordered observers may replace this point before adoption.
				body.position[0] += 1.0
				var rejected: bool = calculation.motion_row("body", body, route, timeline).x < 0
				body.position[0] -= 1.0
				if not rejected:
					return false
				body.facing[0] = 1.0
				rejected = calculation.motion_row("body", body, route, timeline).x < 0
				body.facing[0] = -1.0
				if not rejected:
					return false
				var actual_crossings: Array = []
				var expected_crossings: Array = []
				actual.body_cell_crossed.connect(func(id: String, cell: Vector2i, at: int) -> void: actual_crossings.append([id, cell, at]))
				expected.body_cell_crossed.connect(func(id: String, cell: Vector2i, at: int) -> void: expected_crossings.append([id, cell, at]))
				if coarse:
					actual.project_coarse_native_route("body", route, now, calculation)
					expected.project_coarse_native_route("body", expected._actors.body.active, now)
				else:
					actual.project_actor_route("body", route, now, calculation)
					expected.project_actor_route("body", expected._actors.body.active, now)
				if actual._actors != expected._actors or actual_crossings != expected_crossings:
					return false
	return true


func _inventory() -> bool:
	var inventory := Inventory.new()
	if not inventory.create_container("store", {"wood": 5}) or not inventory.create_container("bag", {}):
		return false
	if not inventory.transfer("take", "store", "bag", "wood", 3):
		return false
	if not inventory.transfer("take", "store", "bag", "wood", 3):
		return false
	if inventory.transfer("too_much", "store", "bag", "wood", 3):
		return false
	return inventory.quantity("store", "wood") == 2 and inventory.quantity("bag", "wood") == 3


func _input() -> bool:
	# Backlog must offer a completed boundary before starting another interval.
	var clock := ReolGameClock.new()
	var calls: Array[int] = [0]
	var boundaries: Array[int] = []
	clock.bind_interval_executor(func(from: int, to: int) -> int:
		calls[0] += 1
		return from if calls[0] == 1 else to)
	clock.input_boundary.connect(func() -> void:
		if not clock.has_pending_advance(): boundaries.append(clock.elapsed_ms))
	clock.advance_frame(0.2)
	clock.request_input_boundary()
	clock.advance_frame(0.0)
	var offered: bool = boundaries == [50] and calls[0] == 2
	clock.advance_frame(0.0)
	var caught_up: bool = clock.elapsed_ms == 200 and boundaries == [50]
	clock.free()
	if not offered or not caught_up:
		return false
	# Never execute a replaced destination, expired dodge or prior-avatar input.
	var buffer := ReolPlayerCommandBuffer.new()
	var finished: Array[int] = []
	buffer.finished.connect(func(id: int, _kind: String, _result: Dictionary) -> void: finished.append(id))
	buffer.enqueue("travel", {"region": "home"}, "session:a", 0)
	buffer.enqueue("travel", {"region": "river"}, "session:a", 1)
	buffer.enqueue("sidestep", {"direction": Vector2.RIGHT}, "session:a", 2)
	buffer.expire("session:a", 303)
	var command: Dictionary = buffer.take()
	if finished != [1, 3] or command.get("id") != 2 or command.args.region != "river" or buffer.pending():
		return false
	buffer.enqueue("cancel", {}, "session:a", 304)
	buffer.expire("session:b", 305)
	return not buffer.pending() and finished == [1, 3, 4]


func _presentation() -> bool:
	var queue := ReolPresentationWork.new()
	var now: Array[int] = [0]
	var order: Array[String] = []
	queue.host_time = func() -> int: return now[0]
	queue.request(&"terrain", func() -> bool: order.append("old"); return true,
		ReolPresentationWork.Priority.BACKGROUND, 10)
	queue.request(&"light", func() -> bool: order.append("light"); now[0] += 1200; return true,
		ReolPresentationWork.Priority.VISIBLE, 10)
	queue.run_pending(1000)
	var valid: bool = order == ["light"] and queue.diagnostics().pending == 1
	# Repeated changes keep the original deadline but use the latest projection.
	now[0] = 5000
	queue.request(&"terrain", func() -> bool: order.append("latest"); return true,
		ReolPresentationWork.Priority.BACKGROUND, 10)
	queue.request(&"new_light", func() -> bool: order.append("new_light"); return true,
		ReolPresentationWork.Priority.VISIBLE, 0)
	now[0] = 10000
	queue.run_pending(0)
	queue.run_pending(0)
	valid = valid and order == ["light", "new_light", "latest"] and queue.diagnostics().pending == 0
	# A blocked completed-world query must not starve another overdue projection.
	queue.request(&"blocked", func() -> bool: return false, ReolPresentationWork.Priority.VISIBLE, 0)
	queue.request(&"ready", func() -> bool: order.append("ready"); return true, ReolPresentationWork.Priority.BACKGROUND, 0)
	queue.run_pending(0)
	valid = valid and order.back() == "ready" and queue.diagnostics().pending == 1
	queue.clear()
	# A newer dirty mark inside a callback survives acknowledgement of old work.
	queue.request(&"replace", func() -> bool:
		queue.request(&"replace", func() -> bool: order.append("replacement"); return true,
			ReolPresentationWork.Priority.VISIBLE, 0)
		return true, ReolPresentationWork.Priority.VISIBLE, 0)
	queue.run_pending(1000)
	valid = valid and queue.diagnostics().pending == 1
	queue.run_pending(1000)
	valid = valid and order.back() == "replacement" and queue.diagnostics().pending == 0
	queue.request(&"cancelled", func() -> bool: order.append("wrong"); return true,
		ReolPresentationWork.Priority.VISIBLE, 0)
	queue.clear()
	queue.run_pending(1000)
	valid = valid and order.back() == "replacement"
	# While the world is loaned out, only explicitly detached projections run.
	queue.request(&"live_world", func() -> bool: order.append("live_world"); return true,
		ReolPresentationWork.Priority.VISIBLE, 0)
	var partial: Array[int] = [0]
	queue.request(&"detached", func() -> bool:
		partial[0] += 1
		return partial[0] == 2, ReolPresentationWork.Priority.VISIBLE, 0, true)
	queue.run_pending(1000, true)
	valid = valid and partial[0] == 1 and order.back() == "replacement" and queue.diagnostics().pending == 2
	queue.run_pending(1000, true)
	valid = valid and partial[0] == 2 and queue.diagnostics().pending == 1
	queue.run_pending(1000)
	valid = valid and order.back() == "live_world" and queue.diagnostics().pending == 0
	queue.free()
	return valid
