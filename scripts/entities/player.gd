class_name PlayerCharacter
extends CharacterBody2D
## Player body view and terrain-aware manual movement.
##
## Movement is grid-aware: the world decides whether a step is legal, and the
## player sweeps its motion in small substeps so low FPS cannot tunnel through
## blocked cells. Speed ramps up/down instead of snapping to full velocity.

signal manual_movement_started
signal resources_changed
signal cell_changed

var clothing_appearance: Dictionary = {}
var appearance_pose: Dictionary = {}
var manual_visual_moving: bool = false

const Visuals = preload("res://scripts/entities/pawn_visuals.gd")

var cell: Vector2i = Vector2i.ZERO
var altitude: int = 0
var blocked: bool = false
var state: PawnState
var selected: bool = false
var avatar_active: bool = true

var _world: ReolWorld
var motion: SimLocalMotion = SimLocalMotion.new()
var _intent: Vector2 = Vector2.ZERO
var _actor_provider: Callable
var _action_guard: Callable
var _action_continuation_guard: Callable
var _automatic_guard: Callable
var _walking_provider: Callable
var _shared_motion_executor: bool = false
var _clock: ReolGameClock
var _motion_guard: Callable
var _has_motion_guard: bool = false
var _presentation := ReolMotionPresentation.new()
var _view_elevation: int = 0
var _view_action_phase: String = ""


func _ready() -> void:
	process_priority = 20
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_world = get_parent().get_node_or_null("World") as ReolWorld
	_clock = get_node_or_null("/root/GameClock") as ReolGameClock
	z_index = 10


func setup_state(value: PawnState) -> void:
	state = value
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func selection_center() -> Vector2:
	return presentation_position() + Vector2(
		0.0,
		-float(
			_view_elevation * ReolWorld.ELEVATION_PX
			+ altitude * ReolWorld.ALTITUDE_PX
		) - 12.0
	)


func spawn_at(spawn_cell: Vector2i) -> void:
	cell = spawn_cell
	motion.relocate(TileGrid.cell_to_world(cell))
	global_position = motion.position
	publish_motion(0, true)
	blocked = false
	queue_redraw()


func set_altitude(value: int) -> void:
	altitude = clampi(value, 0, 2)
	queue_redraw()


func set_motion_guard(provider: Callable) -> void:
	_motion_guard = provider
	_has_motion_guard = true


func has_motion_control() -> bool:
	return avatar_active and (not _has_motion_guard or (_motion_guard.is_valid() and bool(_motion_guard.call())))


func bind_locomotion(world: ReolWorld, clock: ReolGameClock, actor_provider: Callable, action_guard: Callable, automatic_guard: Callable, walking_provider: Callable = Callable(), action_continuation_guard: Callable = Callable()) -> void:
	_world = world
	_clock = clock
	_actor_provider = actor_provider
	_action_guard = action_guard
	_action_continuation_guard = action_continuation_guard
	_automatic_guard = automatic_guard
	_walking_provider = walking_provider
	motion.bind_body(actor_provider.call())
	if not clock.time_advanced.is_connected(_on_time_advanced):
		clock.time_advanced.connect(_on_time_advanced)


func _physics_process(_delta: float) -> void:
	# Input sampling never displaces the body or spends simulated resources.
	_intent = Input.get_vector("move_left", "move_right", "move_up", "move_down") if avatar_active else Vector2.ZERO
	if not _intent.is_zero_approx() and _clock != null:
		_clock.cancel_wait()


func publish_motion(at_ms: int, snap: bool = false) -> void:
	_view_elevation = _world.get_elevation(cell) if _world != null else 0
	_view_action_phase = motion.phase(at_ms) if not motion.action.is_empty() else ""
	var duration: float = 1.0 / _clock.view_transition_rate() if _clock != null else 0.05
	_presentation.capture(global_position, at_ms, duration, snap)


func presentation_position() -> Vector2:
	return _presentation.position if _presentation.initialized() else global_position


func _process(_delta: float) -> void:
	if _clock != null and _presentation.advance(_clock.view_delta_seconds()):
		queue_redraw()


func _on_time_advanced(from_ms: int, to_ms: int) -> void:
	if _shared_motion_executor:
		# The owning world has already handled intent and integrated motion.
		return
	advance_motion_interval(from_ms, to_ms)


func set_shared_motion_executor(enabled: bool) -> void:
	# The regional executor calls the same body integrator at each real world
	# boundary. Its scene-clock callback must not also consume the whole span.
	_shared_motion_executor = enabled


func prepare_motion_interval() -> void:
	# The world adapter invokes this before projecting any automatic journey.
	# It hands off the sampled intent only; it does not integrate displacement.
	if has_motion_control() and motion.action.is_empty() and not _intent.is_zero_approx():
		manual_movement_started.emit()


func advance_motion_interval(from_ms: int, to_ms: int, project: bool = true, prepare_intent: bool = true) -> void:
	if _world == null:
		return
	var controlled: bool = has_motion_control()
	if not motion.action.is_empty():
		var guard: Callable = _action_continuation_guard if _action_continuation_guard.is_valid() else _action_guard
		controlled = controlled and guard.is_valid() and bool(guard.call())
	elif prepare_intent and controlled and not _intent.is_zero_approx():
		manual_movement_started.emit()
	var automatic: bool = _automatic_guard.is_valid() and bool(_automatic_guard.call())
	var previous_position: Vector2 = motion.position
	if automatic and motion.action.is_empty():
		motion.velocity = Vector2.ZERO
	else:
		var walking: Dictionary = _walking_provider.call() if _walking_provider.is_valid() else {"allowed": true, "speed_fraction": 1.0}
		# Sidestep has its own action qualification and must not become a second
		# cast-time movement path merely because ordinary walking was allowed.
		controlled = controlled and (not motion.action.is_empty() or bool(walking.allowed))
		motion.advance(from_ms, to_ms, _intent, _world.can_step, controlled, float(walking.speed_fraction))
	manual_visual_moving = not automatic and motion.action.is_empty() and not motion.velocity.is_zero_approx() and not previous_position.is_equal_approx(motion.position)
	if project:
		_project_motion()


func request_sidestep(direction: Vector2 = Vector2.ZERO) -> bool:
	if _clock == null or not has_motion_control() or not _actor_provider.is_valid() or not _action_guard.is_valid() or not bool(_action_guard.call()) or not motion.action.is_empty():
		return false
	if direction.is_zero_approx():
		direction = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var actor: Dictionary = _actor_provider.call()
	if not direction.is_finite() or not bool(actor.get("alive", false)) or int(actor.get("stamina", 0)) < int(motion.rules.sidestep.stamina):
		return false
	_clock.cancel_wait()
	manual_movement_started.emit()
	var accepted: bool = motion.begin_sidestep(_clock.elapsed_ms, direction, actor)
	if accepted and state != null:
		state.stamina = int(actor.stamina)
		resources_changed.emit()
	_project_motion()
	return accepted


func _project_motion() -> void:
	var previous_cell: Vector2i = cell
	global_position = motion.position
	cell = motion.cell()
	blocked = motion.blocked
	if cell != previous_cell:
		cell_changed.emit()
	queue_redraw()


func restore_motion(data: Dictionary, point: Vector2, now: int) -> bool:
	if not motion.restore(data, point, now):
		return false
	_intent = Vector2.ZERO
	manual_visual_moving = not motion.velocity.is_zero_approx()
	_project_motion()
	publish_motion(now, true)
	return true


func _draw() -> void:
	# The layered renderer sets its own local drawing transforms. Pass the
	# interpolated offset as geometry so body, shadow and caption share the
	# camera's presentation position instead of jumping to each simulation step.
	var ground_offset: Vector2 = presentation_position() - global_position + Vector2(
		0.0, -float(_view_elevation * ReolWorld.ELEVATION_PX)
	)
	var body_offset := ground_offset - Vector2(
		0.0, float(altitude * ReolWorld.ALTITUDE_PX)
	)

	if not _view_action_phase.is_empty():
		var phase: String = _view_action_phase
		var color := Color("#e9c98b") if phase == "起势" else Color("#87c9cf")
		draw_arc(ground_offset, 23.0, -PI * 0.8, PI * 0.8, 14, color, 2.5)
		draw_string(ThemeDB.fallback_font, body_offset + Vector2(-15, -48), phase, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, color)

	var robe := Color("#b23a2f")
	var caption: String = ""
	if state != null and state.pawn_def != null:
		robe = state.pawn_def.color
		caption = state.display_name()
	appearance_pose["time_ms"] = _clock.elapsed_ms if _clock != null else 0
	Visuals.draw_actor(self, ground_offset, body_offset, robe, caption if avatar_active else "无名杂役", selected, avatar_active, clothing_appearance, appearance_pose)
