class_name Pawn
extends Node2D
## Named NPC view. PawnDef provides static content; PawnState contains values
## projected from the authoritative VillageSimulation actor by VillageRuntime.

const Visuals = preload("res://scripts/entities/pawn_visuals.gd")

var state: PawnState
var cell: Vector2i = Vector2i.ZERO
var pawn_id: StringName = &""
var selected: bool = false
var display_name_override: String = ""
var clothing_appearance: Dictionary = {}
var appearance_pose: Dictionary = {}
var publication_world_id: int = 0
var publication_ms: int = -1

var _world: ReolWorld
var _presentation := ReolMotionPresentation.new()
var _projected_position: Vector2 = Vector2.ZERO
var _sprite: HumanoidSprite
var _decoration_elevation: int = -2
var _decoration_text: String = ""
var _view_elevation: int = 0


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	process_priority = 20


func _ready() -> void:
	visibility_changed.connect(_refresh_processing)
	_refresh_processing()


func setup(
	definition: PawnDef,
	db: ReolContentDB,
	world_ref: ReolWorld,
	spawn_cell: Vector2i,
	sampled_elevation: int = -2
) -> void:
	state = PawnState.create(definition, db)
	pawn_id = definition.id
	_world = world_ref
	cell = spawn_cell
	project_position(TileGrid.cell_to_world(cell))
	publish_motion(GameClock.elapsed_ms, true, sampled_elevation)
	z_index = 9
	var candidate := HumanoidSprite.new()
	if candidate.configure():
		_sprite = candidate
		add_child(_sprite)
	else:
		candidate.free()
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func selection_center() -> Vector2:
	return presentation_position() + Vector2(
		0.0, -float(_view_elevation * ReolWorld.ELEVATION_PX) - 12.0
	)


func _process(_delta: float) -> void:
	# Only presentation advances here; offscreen regions own no animation nodes.
	if not is_visible_in_tree() or appearance_pose.is_empty():
		set_process(false)
		return
	# Godot retains CanvasItem drawing commands. Moving the node updates its
	# native transform; it does not require replaying clothes/text drawing in
	# GDScript on every interpolated frame.
	if _presentation.advance(GameClock.view_delta_seconds()):
		global_position = _presentation.position
	if _sprite == null and int(appearance_pose.get("time_ms", 0)) != GameClock.elapsed_ms:
		appearance_pose.time_ms = GameClock.elapsed_ms
		queue_redraw()
	if _sprite != null and not _presentation.has_pending_motion():
		set_process(false)


func _refresh_processing() -> void:
	# Hidden and settled native sprites have no per-frame work. A new complete
	# motion publication or a visibility change wakes the existing interpolator.
	set_process(is_visible_in_tree() and not appearance_pose.is_empty()
		and (_presentation.has_pending_motion() or _sprite == null))


func project_position(point: Vector2) -> void:
	_projected_position = point
	if not _presentation.initialized():
		global_position = point


func publish_motion(at_ms: int, snap: bool = false, sampled_elevation: int = -2) -> void:
	_view_elevation = sampled_elevation if sampled_elevation >= -1 else (_world.get_elevation(cell) if _world != null else 0)
	_presentation.capture(_projected_position, at_ms, 1.0 / GameClock.view_transition_rate(), snap or not is_visible_in_tree())
	global_position = _presentation.position
	_refresh_processing()


func presentation_position() -> Vector2:
	return _presentation.position if _presentation.initialized() else global_position


func refresh_appearance(sampled_elevation: int = -2) -> void:
	_view_elevation = sampled_elevation if sampled_elevation >= -1 else (_world.get_elevation(cell) if _world != null else 0)
	_refresh_processing() # A caller may supply the first pose after motion/show.
	if _sprite == null:
		queue_redraw()
		return
	var ground := Vector2(0, -float(_view_elevation * ReolWorld.ELEVATION_PX))
	_sprite.present(ground + Vector2(0, 13), state.pawn_def.color, clothing_appearance, appearance_pose)
	var text: String = display_name_override if not display_name_override.is_empty() else state.pawn_def.display_name
	if _view_elevation != _decoration_elevation or text != _decoration_text:
		_decoration_elevation = _view_elevation
		_decoration_text = text
		queue_redraw()


func _draw() -> void:
	if state == null or state.pawn_def == null:
		return
	var ground := Vector2(0.0, -float(_view_elevation * ReolWorld.ELEVATION_PX))
	var robe: Color = state.pawn_def.color
	var text: String = display_name_override if not display_name_override.is_empty() else state.display_name()
	Visuals.draw_actor(self, ground, ground, robe, text, selected, false, clothing_appearance, appearance_pose, _sprite == null)
