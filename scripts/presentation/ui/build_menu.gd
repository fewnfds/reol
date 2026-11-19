extends HBoxContainer

signal definition_picked(definition: String)
signal dismissed

const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const COLUMN_WIDTH: float = 188.0
const COLUMN_GAP: int = 8
const CATEGORY_PATHS: Dictionary = {
	"wood_wall": ["建筑", "墙"],
	"stone_wall": ["建筑", "墙"],
	"wood_door": ["建筑", "门窗", "门"],
	"wood_window": ["建筑", "门窗", "窗"],
	"wood_floor": ["建筑", "地板"],
	"cook_stove": ["建筑", "工作", "工作台", "灶台"],
	"water_well": ["建筑", "工作", "取水", "汲水井"],
	"granary": ["建筑", "工作", "仓储", "粮仓"],
	"cultivation_bed": ["建筑", "工作", "栽培", "栽培畦"],
	"wood_bed": ["家具", "起居", "床"],
	"long_bed": ["家具", "起居", "床"],
	"wood_table": ["家具", "起居", "桌"],
	"wood_chair": ["家具", "起居", "椅"],
	"wood_screen": ["家具", "起居", "屏风"],
	"wood_chest": ["家具", "收纳", "储藏箱"],
	"desk_chair": ["家具", "工作", "书案座椅"],
	"notice_desk": ["家具", "工作", "告示案"],
	"planter": ["家具", "栽培", "花盆"],
}

var _catalog: Dictionary = {"groups": {}, "definitions": []}
var _path: Array[String] = []
var _columns: Array[PanelContainer] = []
var _close_buttons: Array[Button] = []
var _leaves: Dictionary[String, Button] = {}
var _available: Dictionary = {}
var _width: float = COLUMN_WIDTH

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", COLUMN_GAP)
	for definition: String in Actions.buildings:
		var branch: Dictionary = _catalog
		for category: String in CATEGORY_PATHS.get(definition, ["其他"]):
			if not branch.groups.has(category):
				branch.groups[category] = {"groups": {}, "definitions": []}
			branch = branch.groups[category]
		branch.definitions.append(definition)

func open(inventory: Dictionary) -> void:
	_path.clear()
	_available = inventory
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
	_available = inventory
	for definition: String in _leaves:
		_update_price(definition, _leaves[definition])

func _go_to_parent(level: int) -> bool:
	_path.resize(level)
	_rebuild()
	return true

func _choose_group(level: int, category: String) -> void:
	_path.resize(level)
	_path.append(category)
	_rebuild()

func _rebuild() -> void:
	for panel: PanelContainer in _columns:
		remove_child(panel)
		panel.queue_free()
	_columns.clear()
	_close_buttons.clear()
	_leaves.clear()
	var branch: Dictionary = _catalog
	_add_column("建造", branch, 0)
	for index: int in _path.size():
		var category: String = _path[index]
		branch = branch.groups[category]
		_add_column(category, branch, index + 1)
	_layout_columns()

func _add_column(title: String, branch: Dictionary, level: int) -> void:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = COLUMN_WIDTH
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	add_child(panel)
	_columns.append(panel)
	var body := VBoxContainer.new()
	panel.add_child(body)
	var header := HBoxContainer.new()
	body.add_child(header)
	if level > 0:
		var back_button: Button = _button(header, "‹", _go_to_parent.bind(level - 1))
		back_button.tooltip_text = "返回上一级"
	Style.label(header, title).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var close_button: Button = _button(header, "×", func(): dismissed.emit())
	close_button.tooltip_text = "关闭建造"
	_close_buttons.append(close_button)
	for category: String in branch.groups:
		var group_button: Button = _button(body, category + "  ›", _choose_group.bind(level, category))
		group_button.toggle_mode = true
		group_button.set_pressed_no_signal(level < _path.size() and _path[level] == category)
	for definition: String in branch.definitions:
		var button: Button = _button(body, "", func(): definition_picked.emit(definition))
		button.set_meta("definition", definition)
		button.icon = Art.icon(Actions.art_key(definition))
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
	var spec: Dictionary = Actions.buildings[definition]
	var owned: int = int(_available.get(spec.item, 0))
	var required: int = int(spec.amount)
	button.text = "%s\n%s %d/%d" % [spec.label, Items.label(spec.item), owned, required]
	button.tooltip_text = button.text
	button.modulate = Color.WHITE if owned >= required else Style.DANGER

func _button(parent: Control, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(28, 32)
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button
