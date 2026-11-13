extends PanelContainer
## One reusable bag/container workspace; immutable views, explicit owner commands.
signal requested(action: String, payload: Dictionary)
const Grid = preload("res://scripts/presentation/ui/item_grid.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
var subject_id: int = 1
var target_id: int = 0
var epoch: int = 0
var kind: String = "bag"
var bag := Grid.new()
var container := Grid.new()
var amount := SpinBox.new()
var _body := VBoxContainer.new()
var _sheets := TabContainer.new()
var _columns := HBoxContainer.new()
var _dual: bool = false
var _title: Label
var _capacity: Label
var _choice: Label
var _equip: Button
var _use: Button
var _drop: Button
var _take: Button
var _put: Button
var _active: String = "bag"
var _frame: RefCounted
var _subject: Dictionary = {}
var _target: Dictionary = {}

func _ready() -> void:
	add_child(_body)
	var head := HBoxContainer.new()
	_body.add_child(head)
	_title = Style.label(head)
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(head, "人物", func(): requested.emit("character", {}))
	_button(head, "×", func(): hide())
	_capacity = Style.label(_body)
	_body.add_child(_sheets)
	_sheets.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_sheets.custom_minimum_size.y = 230
	_sheets.get_tab_bar().focus_mode = Control.FOCUS_NONE
	bag.name = "背包"
	container.name = "容器"
	_sheets.add_child(bag)
	_sheets.add_child(container)
	_body.add_child(_columns)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.custom_minimum_size.y = 230
	_columns.hide()
	_sheets.tab_changed.connect(func(index: int): _active = "bag" if index == 0 else "container"; _refresh_controls())
	bag.chosen.connect(func(_key: String): _active = "bag"; _refresh_controls())
	container.chosen.connect(func(_key: String): _active = "container"; _refresh_controls())
	_choice = Style.label(_body)
	_choice.custom_minimum_size.y = 40
	amount.min_value = 1
	amount.max_value = 99999
	amount.step = 1
	_body.add_child(amount)
	var row := HBoxContainer.new()
	_body.add_child(row)
	for label: String in ["1", "½", "全部"]:
		_button(row, label, func(): amount.value = 1 if label == "1" else (maxi(1, int(amount.max_value) / 2) if label == "½" else amount.max_value))
	var ops := HBoxContainer.new()
	_body.add_child(ops)
	_equip = _button(ops, "装备", func(): _send("equip"))
	_use = _button(ops, "使用", func(): _send("use"))
	_drop = _button(ops, "丢下", func(): _send("drop"))
	_take = _button(ops, "拿取 ←", func(): _send("take"))
	_put = _button(ops, "放入 →", func(): _send("put"))
	hide()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func open(frame: RefCounted, mode: String, subject: int, target: int = 0) -> void:
	kind = mode
	subject_id = subject
	target_id = target
	epoch = frame.epoch
	bag.selected = ""
	container.selected = ""
	_active = "container" if mode == "take" else "bag"
	if not _dual:
		_sheets.set_tab_hidden(1, target == 0)
		_sheets.current_tab = 1 if _active == "container" else 0
	amount.value = 1
	show()
	refresh(frame, true)

func layout_columns(wide: bool) -> void:
	var dual: bool = wide and target_id > 0
	if dual == _dual: return
	var active: String = _active
	_dual = dual
	bag.reparent(_columns if dual else _sheets)
	container.reparent(_columns if dual else _sheets)
	bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag.show()
	container.show()
	_columns.visible = dual
	_sheets.visible = not dual
	if not dual:
		_sheets.set_tab_hidden(1, target_id == 0)
		_sheets.current_tab = 1 if active == "container" and target_id > 0 else 0
	_active = active

func refresh(frame: RefCounted, fog: bool) -> void:
	if not visible: return
	if frame.epoch != epoch: hide(); return
	_frame = frame
	_subject = Actions.observed(frame, subject_id, fog)
	_target = Actions.observed(frame, target_id, fog)
	if _target.get("memory", false): _target = {}
	_title.text = "#%d" % subject_id + (" ⇄ #%d" % target_id if target_id > 0 else "")
	var used: int = 0
	for count: int in _subject.get("inventory", {}).values(): used += count
	_capacity.text = "⊘" if _subject.is_empty() else "%d / %s" % [used, "∞" if int(_subject.get("capacity", -1)) < 0 else str(_subject.capacity)]
	if target_id > 0:
		var other_used: int = 0
		for count: int in _target.get("inventory", {}).values(): other_used += count
		_capacity.text += "   ⇄   " + ("⊘" if _target.is_empty() else "%d / %s" % [other_used, "∞" if int(_target.get("capacity", -1)) < 0 else str(_target.capacity)])
	bag.refresh(_subject.get("inventory", {}), _subject.get("equipment", {}), _subject.get("base_stats", {}))
	container.refresh(_target.get("inventory", {}), _subject.get("equipment", {}), _subject.get("base_stats", {}))
	_refresh_controls()

func _refresh_controls() -> void:
	if _frame == null: return
	var key: String = container.selected if _active == "container" else bag.selected
	var source: Dictionary = _target if _active == "container" else _subject
	var count: int = int(source.get("inventory", {}).get(key, 0))
	amount.max_value = maxi(1, count)
	_choice.text = "—" if key.is_empty() else Grid.item_tooltip(key, _subject.get("equipment", {}), _subject.get("base_stats", {}))
	var controllable: bool = subject_id == 1 and int(_subject.get("hp", 0)) > 0
	_equip.disabled = not controllable or _active != "bag" or count <= 0 or not Items.spec(key).has("slot")
	_use.disabled = not controllable or _active != "bag" or count <= 0 or key not in ["potion", "breath_manual"] or (key == "potion" and int(_subject.hp) >= int(_subject.get("stats", {}).get("max_hp", 100)))
	_drop.disabled = not controllable or _active != "bag" or count <= 0
	_take.visible = target_id > 0
	_put.visible = target_id > 0
	_take.disabled = not controllable or _active != "container" or count <= 0 or _target.is_empty() or _full(_subject)
	_put.disabled = not controllable or _active != "bag" or count <= 0 or _target.is_empty() or _full(_target)

func _full(record: Dictionary) -> bool:
	var capacity: int = int(record.get("capacity", -1))
	if capacity < 0: return false
	var count: int = 0
	for quantity: int in record.get("inventory", {}).values(): count += quantity
	return count >= capacity

func _send(action: String) -> void:
	_refresh_controls()
	var buttons: Dictionary = {"equip": _equip, "use": _use, "drop": _drop, "take": _take, "put": _put}
	if buttons[action].disabled: return
	amount.apply()
	var key: String = container.selected if _active == "container" else bag.selected
	var payload: Dictionary = {"kind": action, "item": key, "amount": int(amount.value), "epoch": epoch}
	if action in ["take", "put"]: payload.target = target_id
	if action == "use":
		payload.kind = "heal" if key == "potion" else "study"
		if key == "breath_manual": payload.target = 1
	requested.emit("stock_send", payload)
