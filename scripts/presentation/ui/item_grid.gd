extends ScrollContainer
## Shared detached inventory view for a person or a container.
signal chosen(key: String)
const Items = preload("res://scripts/sim/kernel/items.gd")
const Equipment = preload("res://scripts/sim/kernel/equipment.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
var selected: String = ""
var buttons: Dictionary = {}
var _grid := GridContainer.new()
var _signature: String = ""

func _ready() -> void:
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	custom_minimum_size = Vector2(294, 200)
	_grid.columns = 4
	_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_child(_grid)

func refresh(contents: Dictionary, equipped: Dictionary = {}, base: Dictionary = {}) -> void:
	if not contents.has(selected): selected = ""
	var signature: String = str(contents) + str(equipped) + str(base) + selected
	if signature == _signature: return
	_signature = signature
	buttons.clear()
	var keys: Array = contents.keys()
	keys.sort()
	while _grid.get_child_count() < maxi(16, keys.size()): _create_slot()
	for index: int in _grid.get_child_count():
		var button: Button = _grid.get_child(index)
		button.visible = index < maxi(16, keys.size())
		var filled: bool = index < keys.size()
		button.disabled = not filled
		for child: CanvasItem in button.get_children(): child.visible = filled
		if not filled:
			button.set_meta("item_key", "")
			button.tooltip_text = ""
			button.modulate = Color.WHITE
			continue
		var key: String = keys[index]
		buttons[key] = button
		button.set_meta("item_key", key)
		button.modulate = Style.GOLD if selected == key else Color.WHITE
		button.get_node("Icon").texture = item_icon(key)
		var quality: Label = button.get_node("Quality")
		quality.text = "Q%d" % Items.quality(key)
		quality.add_theme_color_override("font_color", [Color.WHITE, Style.TEAL, Style.GOLD][Items.quality(key) - 1])
		button.get_node("Count").text = str(contents[key])
		button.tooltip_text = item_tooltip(key, equipped, base)

func _create_slot() -> void:
	var button := Button.new()
	button.custom_minimum_size = Vector2(64, 64)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.focus_mode = Control.FOCUS_NONE
	_grid.add_child(button)
	# Read the slot's current binding, never a key captured before a refresh.
	button.pressed.connect(func(): select(str(button.get_meta("item_key", ""))))
	var image := TextureRect.new()
	image.name = "Icon"
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	button.add_child(image)
	image.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	image.offset_left = 12
	image.offset_right = -12
	image.offset_top = 10
	image.offset_bottom = -12
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var quality := Style.label(button)
	quality.name = "Quality"
	quality.position = Vector2(3, 0)
	var count := Style.label(button)
	count.name = "Count"
	count.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	count.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	count.grow_vertical = Control.GROW_DIRECTION_BEGIN
	count.position = Vector2(40, 40)

func select(key: String) -> void:
	selected = key
	_signature = ""
	chosen.emit(key)

static func item_icon(key: String) -> Texture2D:
	var spec: Dictionary = Items.spec(key)
	if spec.has("icon"): return Style.icon(spec.icon)
	return Art.icon("item_" + Items.definition(key))

static func item_tooltip(key: String, equipped: Dictionary = {}, base: Dictionary = {}) -> String:
	var lines := PackedStringArray(["%s  Q%d" % [Items.label(key), Items.quality(key)]])
	var bonus: Dictionary = Items.bonuses(key)
	var slot: String = str(Items.spec(key).get("slot", ""))
	if not Items.SLOTS.has(slot): return lines[0]
	var changed: Dictionary = Items.bonuses(str(equipped.get(slot, "")))
	changed.merge(bonus, true)
	var current: Dictionary = Equipment.values({"equipment": equipped, "base_stats": base})
	var next_equipment: Dictionary = equipped.duplicate()
	next_equipment[slot] = key
	var next: Dictionary = Equipment.values({"equipment": next_equipment, "base_stats": base})
	for stat: String in changed:
		lines.append("%s  %.2f  Δ%+.2f" % [stat_name(stat), float(next[stat]), float(next[stat]) - float(current[stat])])
	return "\n".join(lines)

static func stat_name(stat: String) -> String:
	return str({"max_hp": "生命上限", "melee": "近战", "ranged": "远程", "armor": "防御", "speed": "移速"}.get(stat, stat))
