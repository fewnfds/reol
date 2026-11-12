extends Node2D
## Retained object appearance. Following reads only a holder's detached view,
## never custody, visibility or any other simulation state.

var shape: String = ""
var _holder: WeakRef
var _offset: Vector2
var _point: Vector2


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	process_priority = 21 # After the player's and NPCs' interpolation.
	z_as_relative = false
	z_index = 7


func present(kind: String, point: Vector2, holder: Node2D) -> void:
	if shape != kind:
		shape = kind
		queue_redraw()
	_holder = weakref(holder) if holder != null else null
	_point = point
	_offset = point - holder.presentation_position() if holder != null else Vector2.ZERO
	set_process(holder != null)
	_follow()


func display_point() -> Vector2:
	var holder: Node2D = _holder.get_ref() as Node2D if _holder != null else null
	return holder.presentation_position() + _offset if holder != null else _point


func _process(_delta: float) -> void:
	_follow()


func _follow() -> void:
	var holder: Node2D = _holder.get_ref() as Node2D if _holder != null else null
	visible = _holder == null or holder != null and holder.is_visible_in_tree()
	global_position = display_point()


func _draw() -> void:
	paint(self, shape, Vector2.ZERO)


static func paint(canvas: CanvasItem, kind: String, point: Vector2) -> void:
	match kind:
		"physical":
			canvas.draw_rect(Rect2(point - Vector2(9, 7), Vector2(18, 14)), Color("#777b7b"))
			canvas.draw_rect(Rect2(point - Vector2(9, 7), Vector2(18, 14)), Color("#c0c4bf"), false, 1.5)
		"weapon":
			var tip: Vector2 = point + Vector2(8, -15)
			var pommel: Vector2 = point + Vector2(-8, 14)
			canvas.draw_line(pommel, tip, Color("#251c20"), 8)
			canvas.draw_line(point + Vector2(-2, 4), tip, Color("#d6ad71"), 5)
			canvas.draw_line(pommel, point + Vector2(-2, 4), Color("#6b513b"), 5)
			canvas.draw_line(point + Vector2(-8, 0), point + Vector2(5, 7), Color("#251c20"), 6)
			canvas.draw_line(point + Vector2(-8, 0), point + Vector2(5, 7), Color("#b8804b"), 3)
		"remote_draw":
			canvas.draw_arc(point, 9.0, 0.0, TAU, 24, Color("#251c20"), 6.0)
			canvas.draw_arc(point, 9.0, 0.0, TAU, 24, Color("#a8926a"), 3.0)
			canvas.draw_arc(point, 8.0, PI * 1.1, PI * 1.8, 8, Color("#ded8b9"), 1.0)
			canvas.draw_line(point + Vector2(7, -6), point + Vector2(11, -5), Color("#e6e4d2"), 2.0)
			canvas.draw_line(point + Vector2(-8, 3), point + Vector2(-11, 5), Color("#c2c8bf"), 2.0)
		"warm", "cool":
			var rim := Color("#f1bd8a") if kind == "warm" else Color("#c3e8ed")
			var body := Color("#a64f36") if kind == "warm" else Color("#588fa5")
			var outline := PackedVector2Array([point + Vector2(-8, -6), point + Vector2(2, -10), point + Vector2(10, -3), point + Vector2(8, 7), point + Vector2(-4, 10), point + Vector2(-10, 3)])
			canvas.draw_circle(point, 13, Color("#251c20"))
			canvas.draw_colored_polygon(outline, body)
			canvas.draw_polyline(PackedVector2Array([outline[0], outline[1], outline[2], outline[3], outline[4], outline[5], outline[0]]), rim, 2.0)
			canvas.draw_line(point + Vector2(-5, -3), point + Vector2(4, 4), rim, 1.5)
		"intrinsic_light":
			canvas.draw_circle(point, 11, Color("#302826"))
			canvas.draw_circle(point, 7, Color("#b5a86d"))
			canvas.draw_circle(point + Vector2(-2, -2), 3, Color("#f4e8ad"))
		_:
			var diamond := PackedVector2Array([point + Vector2(0, -9), point + Vector2(8, 0), point + Vector2(0, 9), point + Vector2(-8, 0)])
			canvas.draw_circle(point, 13, Color("#251c20"))
			canvas.draw_colored_polygon(diamond, Color("#a6553b"))
			canvas.draw_polyline(PackedVector2Array([diamond[0], diamond[1], diamond[2], diamond[3], diamond[0]]), Color("#f0c989"), 2)
			canvas.draw_line(point + Vector2(-3, -3), point + Vector2(3, 3), Color("#e8b479"), 1.5)
