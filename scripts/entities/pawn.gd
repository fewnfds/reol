class_name Pawn
extends Node2D
## A named NPC placed in the world. Static data comes from PawnDef; runtime
## values live in PawnState so needs/jobs can mutate them later.

const NAME_WIDTH: float = 96.0
const NAME_SIZE: int = 12

var state: PawnState
var cell: Vector2i = Vector2i.ZERO
var pawn_id: StringName = &""
var selected: bool = false

var _world: ReolWorld


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


func selection_center() -> Vector2:
	var elevation: int = 0
	if _world != null:
		elevation = _world.get_elevation(cell)
	return global_position + Vector2(
		0.0, -float(elevation * ReolWorld.ELEVATION_PX) - 12.0
	)


func _draw() -> void:
	if state == null or state.pawn_def == null:
		return
	var elevation: int = 0
	if _world != null:
		elevation = _world.get_elevation(cell)
	var ground := Vector2(0.0, -float(elevation * ReolWorld.ELEVATION_PX))
	var robe: Color = state.pawn_def.color

	draw_circle(ground, 8.0, Color(0.0, 0.0, 0.0, 0.22))
	draw_rect(
		Rect2(ground + Vector2(-7.0, -10.0), Vector2(14.0, 20.0)),
		robe
	)
	draw_circle(ground + Vector2(0.0, -15.0), 6.0, Color("#e6d3b3"))
	if selected:
		draw_arc(ground, 18.0, 0.0, TAU, 24, Color("#e8c86a"), 2.0)

	var font: Font = ThemeDB.fallback_font
	var text: String = state.display_name()
	var text_pos: Vector2 = ground + Vector2(-NAME_WIDTH * 0.5, -30.0)
	draw_string_outline(
		font,
		text_pos,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		NAME_WIDTH,
		NAME_SIZE,
		3,
		Color(0.0, 0.0, 0.0, 0.85)
	)
	draw_string(
		font,
		text_pos,
		text,
		HORIZONTAL_ALIGNMENT_CENTER,
		NAME_WIDTH,
		NAME_SIZE,
		Color("#e8e0d0")
	)
