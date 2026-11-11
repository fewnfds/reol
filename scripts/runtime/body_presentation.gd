class_name ReolBodyPresentation
extends RefCounted
## Main-thread Node application of detached body frames. It can run while the
## original world is on its coordinator. Keep one applying frame and one latest
## waiting frame, so slow presentation neither starves late IDs nor grows a queue.
const SLICE_USEC: int = 800
const WORK_ID: StringName = &"body_nodes"
enum Stage { HOME, REMOTE, CLEANUP }

class Frame extends RefCounted:
	var publication: SimBodyPublication
	var layout: PawnViewLayout
	var home_ids: Array
	var ids: Array
	var cleanup: Array
	var stage: int = Stage.HOME
	var cursor: int = 0
	var seen: Dictionary[String, bool] = {}
	var snap: bool
	var center: Vector2i
	var radius: float
	var no_fog: bool
	var queued_usec: int

var _runtime: WeakRef
var _world_id: int = 0
var _active: Frame
var _latest: Frame
var work: Dictionary = {"frames": 0, "coalesced": 0, "row_visits": 0, "elapsed_usec": 0,
	"max_frame_age_usec": 0, "max_slice_usec": 0, "while_simulation_busy": 0}

var runtime: WorldContinuityRuntime:
	get: return _runtime.get_ref() if _runtime != null else null


func configure(adapter: WorldContinuityRuntime) -> void:
	_runtime = weakref(adapter)


func publish(publication: SimBodyPublication, layout: PawnViewLayout, snap: bool, immediate: bool) -> void:
	if publication.world_id != _world_id:
		cancel()
		_world_id = publication.world_id
	var frame := Frame.new()
	frame.publication = publication
	frame.layout = layout
	frame.home_ids = runtime.home_runtime()._pawns.keys()
	frame.ids = publication.rows.keys()
	frame.snap = snap
	frame.center = runtime.controlled_cell()
	frame.radius = float(runtime.home_runtime().simulation.config.observation_radius)
	frame.no_fog = runtime.home_runtime()._fog == null
	frame.queued_usec = Time.get_ticks_usec()
	if immediate:
		_active = frame
		_latest = null
		_step(true)
		runtime.presentation_work.cancel(WORK_ID)
		return
	if _active == null:
		_active = frame
	else:
		work.coalesced += int(_latest != null)
		_latest = frame
	runtime.presentation_work.request(WORK_ID, _step, ReolPresentationWork.Priority.VISIBLE, 50, true)


func cancel() -> void:
	_active = null
	_latest = null
	if runtime != null and runtime.presentation_work != null:
		runtime.presentation_work.cancel(WORK_ID)


func diagnostics() -> Dictionary:
	var result: Dictionary = work.duplicate()
	result["scope"] = "since adapter setup; maximum slice includes explicit/paused immediate refreshes"
	result["pending_frames"] = int(_active != null) + int(_latest != null)
	return result


func _step(unbounded: bool = false) -> bool:
	var adapter: WorldContinuityRuntime = runtime
	if adapter == null:
		_active = null
		_latest = null
		return true
	var began: int = Time.get_ticks_usec()
	var count: int = 0
	while _active != null:
		var frame: Frame = _active
		var home: VillageRuntime = adapter.home_runtime()
		match frame.stage:
			Stage.HOME:
				if frame.cursor >= frame.home_ids.size():
					frame.stage = Stage.REMOTE
					frame.cursor = 0
					continue
				var id: String = str(frame.home_ids[frame.cursor])
				frame.cursor += 1
				var pawn: Pawn = home._pawns.get(id)
				if is_instance_valid(pawn):
					home.apply_published_actor(pawn, frame.publication.rows.get(id, {}), frame.layout, frame.publication.at_ms, frame.snap, frame.publication.world_id)
			Stage.REMOTE:
				if frame.cursor >= frame.ids.size():
					frame.stage = Stage.CLEANUP
					frame.cleanup = adapter._remote_views.keys()
					frame.cursor = 0
					continue
				var id: String = str(frame.ids[frame.cursor])
				frame.cursor += 1
				var row: Dictionary = frame.publication.rows[id]
				if row.region != "home" and bool(row.alive) and frame.layout.sees(row.cell) and (not frame.no_fog or row.cell.distance_to(frame.center) <= frame.radius):
					frame.seen[id] = true
					_apply_remote(adapter, home, frame, row)
			Stage.CLEANUP:
				if frame.cursor >= frame.cleanup.size():
					work.frames += 1
					work.max_frame_age_usec = maxi(int(work.max_frame_age_usec), Time.get_ticks_usec() - frame.queued_usec)
					_active = _latest
					_latest = null
					continue
				var id: String = str(frame.cleanup[frame.cursor])
				frame.cursor += 1
				if not frame.seen.has(id) and adapter._remote_views.has(id):
					var current: Pawn = adapter._remote_views[id]
					if current.publication_world_id != frame.publication.world_id or current.publication_ms <= frame.publication.at_ms:
						if adapter._selected_remote == id:
							adapter.clear_remote_selection()
						current.hide()
						current.queue_free()
						adapter._remote_views.erase(id)
		count += 1
		if not unbounded and count % 8 == 0 and Time.get_ticks_usec() - began >= SLICE_USEC:
			break
	var elapsed: int = Time.get_ticks_usec() - began
	work.row_visits += count
	work.elapsed_usec += elapsed
	work.max_slice_usec = maxi(int(work.max_slice_usec), elapsed)
	work.while_simulation_busy += int(not adapter.simulation_accessible())
	adapter.publication_work["body_nodes"] = int(adapter.publication_work.get("body_nodes", 0)) + elapsed
	return _active == null


static func _apply_remote(adapter: WorldContinuityRuntime, home: VillageRuntime, frame: Frame, row: Dictionary) -> void:
	var id: String = str(row.id)
	if not adapter._remote_views.has(id):
		var pawn := Pawn.new()
		pawn.name = "Visitor_" + id
		var definition: PawnDef = home._content.get_pawn(StringName(row.definition_id))
		pawn.setup(definition, home._content, home._world, row.cell, int(row.elevation))
		pawn.pawn_id = StringName(id)
		pawn.display_name_override = str(adapter.settings.runtime.remote_names.get(id, definition.display_name if definition != null else id))
		pawn.hide()
		adapter.add_child(pawn)
		adapter._remote_views[id] = pawn
	home.apply_published_actor(adapter._remote_views[id], row, frame.layout, frame.publication.at_ms, frame.snap, frame.publication.world_id)
