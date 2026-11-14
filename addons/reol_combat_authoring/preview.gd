@tool
extends VBoxContainer
## Editor-only geometry. The playable lab uses the real World; this never writes it.
var definition: Resource
var _validation := Label.new()
func _ready() -> void:
	custom_minimum_size = Vector2(280, 280)
	var geometry := Control.new()
	geometry.custom_minimum_size.y = 206
	geometry.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(geometry)
	var button := Button.new()
	button.text = "校验技能定义"
	_validation.custom_minimum_size = Vector2(280, 0)
	_validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_validation.add_theme_font_size_override("font_size", 12)
	add_child(_validation)
	add_child(button)
	button.pressed.connect(func():
		var errors: PackedStringArray = definition.errors()
		_validation.text = "定义校验通过；保存后重开试玩生效" if errors.is_empty() else "\n".join(errors)
		_validation.tooltip_text = _validation.text)
func _process(_delta: float) -> void:
	if is_visible_in_tree(): queue_redraw()
func _draw() -> void:
	if definition == null or definition.delivery == null: return
	var width: float = maxf(260, size.x - 12)
	var total: int = maxi(1, definition.windup + definition.active + definition.recovery)
	var offset: float = 0
	for pair: Array in [[definition.windup, Color("b59a67")], [definition.active, Color("db8665")], [definition.recovery, Color("6f9d9a")]]:
		var span: float = width * int(pair[0]) / total
		draw_rect(Rect2(offset, 12, span, 20), pair[1])
		offset += span
	var font: Font = ThemeDB.fallback_font
	draw_string(font, Vector2(0, 52), "起手 %d / 有效 %d / 收招 %d ms" % [definition.windup, definition.active, definition.recovery], HORIZONTAL_ALIGNMENT_LEFT, width, 12)
	var center := Vector2(width * 0.5, 140)
	var delivery: Resource = definition.delivery
	var scale: float = 20.0
	for x: int in range(-6, 7): draw_line(center + Vector2(x * scale, -65), center + Vector2(x * scale, 65), Color(0.5, 0.6, 0.6, 0.15))
	draw_circle(center, 7, Color("e5d0a3"))
	match delivery.kind:
		"melee":
			draw_arc(center, delivery.reach * scale, -delivery.half_angle, delivery.half_angle, 30, definition.tint, 2, true)
			for angle: float in [-delivery.half_angle, delivery.half_angle]: draw_line(center, center + Vector2.RIGHT.rotated(angle) * delivery.reach * scale, definition.tint, 1.5, true)
		"area": draw_arc(center, delivery.radius * scale, 0, TAU, 48, definition.tint, 2, true)
		"projectile", "implement":
			for index: int in delivery.count:
				var direction := Vector2.RIGHT.rotated((index - (delivery.count - 1) * 0.5) * delivery.spread)
				draw_line(center, center + direction * 90, definition.tint, 2, true)
		_: draw_arc(center, 24, 0, TAU, 24, definition.tint, 2)
