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
var visual_offset: Vector2 = Vector2.ZERO
var caption_visible: bool = true
var clothing_appearance: Dictionary = {}
var appearance_pose: Dictionary = {}

var _world: ReolWorld


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func setup(
	definition: PawnDef,
	db: ReolContentDB,
	world_ref: ReolWorld,
	spawn_cell: Vector2i
) -> void:
	state = PawnState.create(definition, db)
	pawn_id = definition.id
	_world = world_ref
	cell = spawn_cell
	global_position = TileGrid.cell_to_world(cell)
	z_index = 9
	queue_redraw()


func set_selected(value: bool) -> void:
	selected = value
	queue_redraw()


func set_view_layout(layout: Dictionary) -> void:
	visual_offset = layout.get("offset", Vector2.ZERO)
	caption_visible = bool(layout.get("caption_visible", true))
	queue_redraw()


func selection_center() -> Vector2:
	var elevation: int = 0
	if _world != null:
		elevation = _world.get_elevation(cell)
	return global_position + visual_offset + Vector2(
		0.0, -float(elevation * ReolWorld.ELEVATION_PX) - 12.0
	)


func _process(_delta: float) -> void:
	# Only presentation advances here; offscreen regions own no animation nodes.
	if not is_visible_in_tree() or appearance_pose.is_empty():
		return
	if int(appearance_pose.get("time_ms", 0)) != GameClock.elapsed_ms:
		appearance_pose.time_ms = GameClock.elapsed_ms
		queue_redraw()


func _draw() -> void:
	if state == null or state.pawn_def == null:
		return
	var elevation: int = 0
	if _world != null:
		elevation = _world.get_elevation(cell)
	var ground: Vector2 = visual_offset + Vector2(0.0, -float(elevation * ReolWorld.ELEVATION_PX))
	var robe: Color = state.pawn_def.color
	var text: String = display_name_override if not display_name_override.is_empty() else state.display_name()
	if not caption_visible and not selected:
		text = ""
	Visuals.draw_actor(self, ground, ground, robe, text, selected, false, clothing_appearance, appearance_pose)
