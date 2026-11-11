class_name DevelopmentInspectorPanel
extends PanelContainer
## Detached development data and explicit routes to the original action UI.
signal operation_requested(reference: Dictionary, cell: Vector2i)
signal object_selected(reference: Dictionary)
const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var _summary: Label
var _choice: OptionButton
var _values: TextEdit
var _open: Button
var _notice: Label
var _rows: Array = []
var _keys: Array[String] = []
var _cell := Vector2i(-1, -1)
var snapshot: Dictionary = {}


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_RIGHT_WIDE)
	offset_left = -394
	offset_right = -16
	offset_top = 276
	offset_bottom = -16
	var column := VBoxContainer.new()
	add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	UI.label(header, "DEV · 地块 / 全部对象", UI.PAPER, 16)
	UI.button(header, "关闭", hide)
	_summary = UI.label(column, "", UI.MUTED, 13)
	_choice = OptionButton.new()
	_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_choice.clip_text = true
	_choice.item_selected.connect(_select)
	column.add_child(_choice)
	_values = TextEdit.new()
	_values.editable = false
	_values.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_values.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_values.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_values.add_theme_font_size_override("font_size", 13)
	column.add_child(_values)
	_notice = UI.label(column, "", UI.WARNING, 12)
	_notice.hide()
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_open = UI.button(actions, "打开对应操作", _operate)
	UI.button(actions, "复制JSON", _copy)
	hide()


func present(data: Dictionary) -> void:
	var previous: String = _keys[_choice.selected] if _choice.selected >= 0 and _choice.selected < _keys.size() else ""
	if _cell != data.cell:
		previous = ""
		_notice.hide()
	snapshot = data
	_cell = data.cell
	_summary.text = "格 (%d,%d) · t=%dms\n查询=%s · DEV原状态，不写入角色认识" % [_cell.x, _cell.y, data.at_ms, data.query_status]
	_rows = data.objects
	var next: Array[String] = []
	for row: Dictionary in _rows:
		next.append(JSON.stringify(row.reference, "", true))
	if next != _keys:
		_keys = next
		_choice.clear()
		for row: Dictionary in _rows:
			_choice.add_item(str(row.label))
	var index: int = _keys.find(previous)
	if index < 0:
		index = 0
		for candidate: int in range(1, _rows.size()):
			if _rows[candidate].values.get("spatial", {}).get("layer", "") in ["ground", "air", "planned"]:
				index = candidate
				break
	_choice.select(index)
	_show_values()


func _select(_index: int) -> void:
	_notice.hide()
	_show_values()
	if not _rows.is_empty():
		object_selected.emit(_rows[_choice.selected].reference.duplicate(true))


func _show_values() -> void:
	if _rows.is_empty():
		_values.text = "查询尚未完成。"
		_open.disabled = true
		return
	var row: Dictionary = _rows[_choice.selected]
	var value: String = JSON.stringify(row.values, "  ", false, true)
	if _values.text != value:
		var scroll: float = _values.scroll_vertical
		_values.text = value
		_values.scroll_vertical = scroll
	_open.disabled = row.reference.kind not in ["terrain", "construction", "artifact", "plant", "actor", "avian", "workplace"]
	_open.text = "打开对应操作 · " + str(row.reference.kind)


func _operate() -> void:
	if not _rows.is_empty():
		operation_requested.emit(_rows[_choice.selected].reference.duplicate(true), _cell)


func _copy() -> void:
	DisplayServer.clipboard_set(JSON.stringify(snapshot, "  ", false, true))


func show_notice(message: String) -> void:
	_notice.text = message
	_notice.show()
