extends HBoxContainer

signal definition_picked(definition: String)
signal dismissed

const Construction = preload("res://scripts/sim/kernel/construction_defs.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const COLUMN_WIDTH: float = 188.0
const COLUMN_GAP: int = 8
const LEVEL_TITLES: Array[String] = ["建造分类", "小类", "物品", "材质"]

var _path: Array[String] = []
var _columns: Array[PanelContainer] = []
var _close_buttons: Array[Button] = []
var _leaves: Dictionary[String, Button] = {}
var _available: Dictionary = {}
var _width: float = COLUMN_WIDTH

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", COLUMN_GAP)

func open(inventory: Dictionary) -> void:
	_path.clear()
	_available = inventory.duplicate()
	_rebuild()

func fit(origin: Vector2, width: float) -> void:
	position = origin
	_width = width
	_layout_columns()

func back() -> bool:
	if _path.is_empty(): return false
	return _go_to_parent(_path.size() - 1)

func refresh(inventory: Dictionary) -> void:
	if _available == inventory: return
	_available = inventory.duplicate()
	for definition: String in _leaves:
		_update_price(definition, _leaves[definition])

func _go_to_parent(level: int) -> bool:
	_path.resize(level)
	_rebuild()
	return true

func _choose(level: int, key: String) -> void:
	_path.resize(level)
	_path.append(key)
	_rebuild()

func _rebuild() -> void:
	for panel: PanelContainer in _columns:
		remove_child(panel)
		panel.queue_free()
	_columns.clear()
	_close_buttons.clear()
	_leaves.clear()
	var choices: Dictionary = Construction.MENU
	for level: int in range(_path.size() + 1):
		_add_column(choices, level)
		if level < _path.size(): choices = choices[_path[level]]
	_layout_columns()

func _add_column(choices: Dictionary, level: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = COLUMN_WIDTH
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(panel)
	_columns.append(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	var title: String = LEVEL_TITLES[level]
	if level > 0:
		var back_button: Button = _button(header, "‹", _go_to_parent.bind(level - 1))
		back_button.tooltip_text = "返回上一级"
		title = "%s · %s" % [_path[level - 1], title]
	var label: Label = Style.label(header, title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var close_button: Button = _button(header, "×", func(): dismissed.emit())
	close_button.tooltip_text = "关闭建造"
	_close_buttons.append(close_button)
	for key: String in choices:
		if level == LEVEL_TITLES.size() - 1:
			_add_material(body, key, choices[key])
		else:
			var choice: Button = _button(body, key + "  ›", _choose.bind(level, key))
			choice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			choice.tooltip_text = key
			choice.toggle_mode = true
			choice.set_pressed_no_signal(level < _path.size() and _path[level] == key)

func _add_material(body: Control, material: String, definition: String) -> void:
	var button: Button = _button(body, "", func(): definition_picked.emit(definition))
	button.set_meta("material", material)
	button.set_meta("definition", definition)
	button.icon = Art.icon("item_" + str(Construction.DEFINITIONS[definition].item))
	button.expand_icon = true
	button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_update_price(definition, button)
	_leaves[definition] = button

func _layout_columns() -> void:
	var count: int = maxi(1, floori((_width + COLUMN_GAP) / (COLUMN_WIDTH + COLUMN_GAP)))
	var first: int = maxi(0, _columns.size() - count)
	for index: int in _columns.size():
		_columns[index].visible = index >= first
		_close_buttons[index].visible = index == first
	reset_size()

func _update_price(definition: String, button: Button) -> void:
	var spec: Dictionary = Construction.DEFINITIONS[definition]
	var owned: int = int(_available.get(spec.item, 0))
	var required: int = int(spec.amount)
	button.text = "%s\n%s %d/%d" % [button.get_meta("material"), Items.label(spec.item), owned, required]
	button.tooltip_text = "%s · %s %d/%d" % [spec.label, Items.label(spec.item), owned, required]
	button.modulate = Color.WHITE if owned >= required else Style.DANGER

func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(28, 32)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
