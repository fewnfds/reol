extends VBoxContainer
## Modal keyboard/mouse editor. Captured input never reaches gameplay or GUI buttons.
signal back_requested
const Bindings = preload("res://scripts/presentation/ui/input_bindings.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
var bindings: RefCounted
var capture_action: String = ""
var _guard: Dictionary = {}
var _swap: Dictionary = {}
var _buttons: Dictionary = {}
var _status: Label
var _swap_row: HBoxContainer

func configure(source: RefCounted, height: float) -> void:
	bindings = source
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	Style.label(self, "键位设置")
	var help: Label = Style.label(self, "点按键后输入新键 · Esc取消捕获 · 支持单键和鼠标主键／侧键")
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size.y = minf(220, height)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)
	var rows := VBoxContainer.new()
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(rows)
	for spec: Dictionary in Bindings.SPECS:
		var row := HBoxContainer.new()
		rows.add_child(row)
		var label: Label = Style.label(row, spec.label)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var context: String = {Bindings.ACT: "战斗", Bindings.INTERACT: "交互／营造", Bindings.GLOBAL: "共用"}[int(spec.contexts)]
		Style.label(row, context).custom_minimum_size.x = 112
		var id: String = spec.id
		_buttons[id] = _button(row, bindings.hint(id), func(): begin_capture(id))
		_buttons[id].custom_minimum_size.x = 110
	_status = Style.label(self, "Esc返回 · 中键拖镜头／滚轮缩放、交互鼠标操作和F8/F12等保留")
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_swap_row = HBoxContainer.new()
	add_child(_swap_row)
	_button(_swap_row, "确认交换", func(): _commit(_swap))
	_button(_swap_row, "取消交换", cancel_capture)
	_swap_row.hide()
	var footer := HBoxContainer.new()
	add_child(footer)
	_button(footer, "恢复默认", func(): _commit(Bindings.defaults()))
	_button(footer, "返回设置", func(): back_requested.emit())
	bindings.changed.connect(refresh)

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.custom_minimum_size.y = 32
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func refresh() -> void:
	for id: String in _buttons: _buttons[id].text = "请按键…" if id == capture_action else bindings.hint(id)

func begin_capture(id: String) -> void:
	cancel_capture()
	capture_action = id
	_status.text = "为“%s”按下新键；Esc取消" % Bindings.action_label(id)
	refresh()

func cancel_capture() -> void:
	capture_action = ""
	_swap = {}
	_swap_row.hide()
	refresh()

func escape() -> bool:
	if capture_action.is_empty() and _swap.is_empty(): return false
	cancel_capture()
	_status.text = "已取消，原键位保留"
	return true

func focus_lost() -> void:
	cancel_capture()
	_guard = {}
	_status.text = "已退出按键捕获"

func consume(event: InputEvent) -> bool:
	if not _guard.is_empty() and Bindings.same(_guard, _identity(event)):
		if not event.is_pressed(): _guard = {}
		return true
	if capture_action.is_empty(): return false
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		escape()
		_guard = _identity(event)
		return true
	if not (event is InputEventKey or event is InputEventMouseButton): return false
	if not event.is_pressed() or event.is_echo(): return true
	var proposal: Dictionary = bindings.propose(capture_action, event)
	if proposal.ok:
		_guard = _identity(event)
		_commit(proposal.candidate)
	elif proposal.has("swap"):
		capture_action = ""
		_swap = proposal.swap
		_swap_row.show()
		_status.text = proposal.message
		_guard = _identity(event)
		refresh()
	else:
		_status.text = proposal.message + "；请换一个键或按Esc取消"
	return true

func _identity(event: InputEvent) -> Dictionary:
	if event is InputEventKey: return {"kind": "key", "code": event.physical_keycode if event.physical_keycode != 0 else event.keycode}
	if event is InputEventMouseButton: return {"kind": "mouse", "code": int(event.button_index)}
	return {}

func _exit_tree() -> void:
	if bindings != null and bindings.changed.is_connected(refresh): bindings.changed.disconnect(refresh)

func _commit(candidate: Dictionary) -> void:
	var error: Error = bindings.commit(candidate)
	if error != OK:
		_status.text = "键位未保存（%s），原设置保留" % error_string(error)
		return
	cancel_capture()
	_status.text = "键位已保存"
