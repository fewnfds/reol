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
var operation: String = ""
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
var _purpose := OptionButton.new()
var _donate := CheckButton.new()
var _purpose_signature: String = ""
const PURPOSE_TITLES: Dictionary = {"cook": "烹饪", "construct": "施工", "cultivate": "种植养护", "equip": "配用装备", "study": "借阅", "supply": "搬运供给"}

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
	_purpose.tooltip_text = "从公库领料时声明用途；归还原受托物资不需要重新领用。"
	_body.add_child(_purpose)
	_donate.text = "将自有物资捐给所属组织"
	_body.add_child(_donate)
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
	var definition: Dictionary = Actions.Operations.OPERATIONS.get(mode, {})
	operation = mode if definition.get("executor") == "transfer" else ""
	kind = str(definition.handler) if not operation.is_empty() else mode
	subject_id = subject
	target_id = target
	epoch = frame.epoch
	bag.selected = ""
	container.selected = ""
	_active = "container" if kind == "take" else "bag"
	if not _dual:
		_sheets.set_tab_hidden(1, target == 0)
		_sheets.current_tab = 1 if _active == "container" else 0
	amount.value = 1
	_purpose_signature = ""
	_donate.button_pressed = false
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
	var org: int = int(_target.get("organization", 0))
	var organizations: Array = _target.get("stock_organizations", []).duplicate()
	if org > 0 and not organizations.has(org): organizations.append(org)
	_purpose.visible = target_id > 0 and not organizations.is_empty() and subject_id == 1
	_donate.visible = target_id > 0 and org > 0 and subject_id == 1
	var signature: String = str(organizations) + str(_subject.get("permissions", {}))
	if signature != _purpose_signature:
		var selected_purpose: Variant = _purpose.get_item_metadata(_purpose.selected) if _purpose.item_count > 0 else {}
		_purpose_signature = signature
		_purpose.clear()
		_purpose.add_item("普通取放／归还受托物资")
		_purpose.set_item_metadata(0, {})
		for organization: int in organizations:
			for purpose: String in PURPOSE_TITLES:
				if purpose in _subject.get("permissions", {}).get(organization, []):
					var choice: Dictionary = {"purpose": purpose, "source_organization": organization}
					_purpose.add_item("领用 #%d：" % organization + PURPOSE_TITLES[purpose])
					_purpose.set_item_metadata(_purpose.item_count - 1, choice)
					if selected_purpose == choice: _purpose.select(_purpose.item_count - 1)
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
	if _active == "bag" and not key.is_empty() and _subject.has("stock_rights"):
		var own: int = 0
		var entrusted: int = 0
		for batch: Dictionary in _subject.stock_rights.get(key, []):
			if batch.owner == subject_id and batch.entrust == 0: own += int(batch.count)
			if batch.entrust > 0: entrusted += int(batch.count)
		_choice.text += "\n自有 %d　受托 %d　其他保管 %d" % [own, entrusted, count - own - entrusted]
	var controllable: bool = subject_id == 1 and int(_subject.get("hp", 0)) > 0
	_equip.disabled = not controllable or _active != "bag" or count <= 0 or key not in _subject.get("equippable", []) or not Items.spec(key).has("slot")
	var usable: bool = int(_subject.get("usable_inventory", {}).get(key, 0)) > 0 if key == "potion" else int(_subject.get("readable", {}).get(key, 0)) > 0
	_use.disabled = not controllable or _active != "bag" or count <= 0 or not usable or key not in ["potion", "breath_manual"] or (key == "potion" and int(_subject.hp) >= int(_subject.get("stats", {}).get("max_hp", 100)))
	_drop.disabled = not controllable or _active != "bag" or count <= 0
	_take.visible = target_id > 0
	_put.visible = target_id > 0
	_take.disabled = not controllable or _active != "container" or count <= 0 or _target.is_empty() or _full(_subject) or not Actions.Query.evaluate(Actions.Operations.OPERATIONS.take, _subject, _target).ready
	_put.disabled = not controllable or _active != "bag" or count <= 0 or _target.is_empty() or _full(_target) or not Actions.Query.evaluate(Actions.Operations.OPERATIONS.put, _subject, _target).ready

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
	if action == kind and not operation.is_empty(): payload.kind = operation
	if action in ["take", "put"]:
		payload.target = target_id
		if _purpose.visible and action == "take": payload.merge(_purpose.get_item_metadata(_purpose.selected))
		if _donate.visible and action == "put": payload["donate"] = _donate.button_pressed
	if action == "use":
		payload.kind = "heal" if key == "potion" else "study"
		if key == "breath_manual": payload.target = 1
	requested.emit("stock_send", payload)
