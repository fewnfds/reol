extends PanelContainer
## One reusable bag/container workspace; immutable views, explicit owner commands.
signal requested(action: String, payload: Dictionary)
const Grid = preload("res://scripts/presentation/ui/item_grid.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const PERSONAL_SLOTS: int = 12
var subject_id: int = 1
var target_id: int = 0
var epoch: int = 0
var kind: String = "bag"
var operation: String = ""
var bag := Grid.new()
var cargo := Grid.new()
var container := Grid.new()
var amount := SpinBox.new()
var _quantities := VBoxContainer.new()
var _actions := HBoxContainer.new()
var _body := VBoxContainer.new()
var _sheets := TabContainer.new()
var _columns := HBoxContainer.new()
var _bag_sheet := ScrollContainer.new()
var _container_sheet := ScrollContainer.new()
var _bag_sections := VBoxContainer.new()
var _bag_items: Dictionary = {}
var _shipment: Dictionary = {}
var _page: int = 0
var _page_count: int = 1
var _pager := HBoxContainer.new()
var _page_label: Label
var _previous_page: Button
var _next_page: Button
var _dual: bool = false
var _moving_sheets: bool = false
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
var _show_purpose: bool = false
var _show_donation: bool = false
const PURPOSE_TITLES: Dictionary = {"cook": "炊事", "produce": "加工炼制", "construct": "施工", "cultivate": "种植养护", "equip": "配用装备", "study": "借阅", "supply": "搬运供给"}

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
	container.columns = 4
	_add_sheet(_bag_sheet, "背包", _bag_sections)
	_add_sheet(_container_sheet, "容器", container)
	bag.columns = 4
	bag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bag.minimum_slots = PERSONAL_SLOTS
	var personal_header: HBoxContainer = _add_bag_section("个人背包", bag)
	personal_header.add_child(_pager)
	_previous_page = _button(_pager, "‹", _step_page.bind(-1))
	_previous_page.tooltip_text = "上一页"
	_page_label = Style.label(_pager)
	_next_page = _button(_pager, "›", _step_page.bind(1))
	_next_page.tooltip_text = "下一页"
	cargo.columns = 1
	cargo.minimum_slots = 1
	cargo.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_add_bag_section("搬运格", cargo)
	_body.add_child(_columns)
	_columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_columns.custom_minimum_size.y = 230
	_columns.hide()
	_sheets.tab_changed.connect(_tab_changed)
	bag.chosen.connect(func(_key: String): _select_section("bag"))
	cargo.chosen.connect(func(_key: String): _select_section("cargo"))
	container.chosen.connect(func(_key: String): _select_section("container"))
	_choice = Style.label(_body)
	_choice.custom_minimum_size.y = 40
	amount.min_value = 1
	amount.max_value = 99999
	amount.step = 1
	_body.add_child(_quantities)
	_quantities.add_child(amount)
	_purpose.tooltip_text = "从公库领料时声明用途；归还原受托物资不需要重新领用。"
	_body.add_child(_purpose)
	_donate.text = "将自有物资捐给所属组织"
	_body.add_child(_donate)
	var row := HBoxContainer.new()
	_quantities.add_child(row)
	for label: String in ["1", "½", "全部"]:
		_button(row, label, func(): amount.value = 1 if label == "1" else (maxi(1, int(amount.max_value) / 2) if label == "½" else amount.max_value))
	_body.add_child(_actions)
	_equip = _button(_actions, "装备", func(): _send("equip"))
	_use = _button(_actions, "使用", func(): _send("use"))
	_drop = _button(_actions, "丢下", func(): _send("drop"))
	_take = _button(_actions, "拿取 ←", func(): _send("take"))
	_put = _button(_actions, "放入 →", func(): _send("put"))
	hide()

func _button(parent: Node, text: String, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.focus_mode = Control.FOCUS_NONE
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _add_sheet(sheet: ScrollContainer, title: String, content: Control) -> void:
	sheet.name = title
	sheet.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sheet.custom_minimum_size.x = 294
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sheet.add_child(content)
	_sheets.add_child(sheet)

func _add_bag_section(title: String, grid: GridContainer) -> HBoxContainer:
	var section := VBoxContainer.new()
	_bag_sections.add_child(section)
	var header := HBoxContainer.new()
	section.add_child(header)
	Style.label(header, title).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	section.add_child(grid)
	return header

func open(frame: RefCounted, mode: String, subject: int, target: int = 0) -> void:
	var definition: Dictionary = Actions.Operations.OPERATIONS.get(mode, {})
	operation = mode if definition.get("executor") == "transfer" else ""
	kind = str(definition.handler) if not operation.is_empty() else mode
	subject_id = subject
	target_id = target
	epoch = frame.epoch
	bag.select("", false)
	cargo.select("", false)
	container.select("", false)
	_page = 0
	_bag_sheet.scroll_vertical = 0
	_container_sheet.scroll_vertical = 0
	_active = "container" if kind == "take" else "bag"
	_moving_sheets = true
	_sheets.tabs_visible = target > 0
	if not _dual:
		_sheets.set_tab_hidden(1, target == 0)
		_sheets.current_tab = 1 if _active == "container" else 0
	_moving_sheets = false
	amount.value = 1
	_purpose_signature = ""
	_donate.button_pressed = false
	show()
	refresh(frame, true)

func layout_columns(wide: bool) -> void:
	var dual: bool = wide and target_id > 0
	if dual == _dual: return
	_moving_sheets = true
	_dual = dual
	_bag_sheet.reparent(_columns if dual else _sheets)
	_container_sheet.reparent(_columns if dual else _sheets)
	_bag_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_container_sheet.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if dual:
		_bag_sheet.show()
		_container_sheet.show()
	else:
		_sheets.set_tab_hidden(1, target_id == 0)
		_sheets.current_tab = 1 if _active == "container" and target_id > 0 else 0
	_columns.visible = dual
	_sheets.visible = not dual
	_moving_sheets = false

func _tab_changed(index: int) -> void:
	if not _moving_sheets: _select_section("bag" if index == 0 else "container")

func _select_section(section: String) -> void:
	_active = section
	if section != "bag": bag.select("", false)
	if section != "cargo": cargo.select("", false)
	if section != "container": container.select("", false)
	_refresh_controls()

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
	_show_purpose = target_id > 0 and not organizations.is_empty() and subject_id == 1
	_show_donation = target_id > 0 and org > 0 and subject_id == 1
	var signature: String = str(organizations) + str(_subject.get("permissions", {})) + str(_subject.get("scope_grants", []))
	if signature != _purpose_signature:
		var selected_purpose: Variant = _purpose.get_item_metadata(_purpose.selected) if _purpose.item_count > 0 else {}
		_purpose_signature = signature
		_purpose.clear()
		_purpose.add_item("普通取放／归还受托物资")
		_purpose.set_item_metadata(0, {})
		for organization: int in organizations:
			for purpose: String in PURPOSE_TITLES:
				if preload("res://scripts/sim/kernel/stock_rules.gd").permits_purpose(_subject, organization, purpose):
					var choice: Dictionary = {"purpose": purpose, "source_organization": organization}
					_purpose.add_item("领用 #%d：" % organization + PURPOSE_TITLES[purpose])
					_purpose.set_item_metadata(_purpose.item_count - 1, choice)
					if selected_purpose == choice: _purpose.select(_purpose.item_count - 1)
	_title.text = "#%d ⇄ #%d" % [subject_id, target_id] if target_id > 0 else Actions.title(_subject)
	_capacity.visible = target_id > 0 or int(_subject.get("capacity", -1)) >= 0
	var used: int = 0
	for count: int in _subject.get("inventory", {}).values(): used += count
	_capacity.text = "⊘" if _subject.is_empty() else "%d / %s" % [used, "∞" if int(_subject.get("capacity", -1)) < 0 else str(_subject.capacity)]
	if target_id > 0:
		var other_used: int = 0
		for count: int in _target.get("inventory", {}).values(): other_used += count
		_capacity.text += "   ⇄   " + ("⊘" if _target.is_empty() else "%d / %s" % [other_used, "∞" if int(_target.get("capacity", -1)) < 0 else str(_target.capacity)])
	_refresh_bag()
	container.refresh(_target.get("inventory", {}), _subject.get("equipment", {}), _subject.get("base_stats", {}))
	_refresh_controls()

func _refresh_bag() -> void:
	_shipment = _subject.get("carried_shipment", {})
	_bag_items = _subject.get("inventory", {})
	var cargo_items: Dictionary = {}
	if not _shipment.is_empty():
		var item: String = _shipment.item
		var count: int = int(_shipment.count)
		cargo_items[item] = count
		_bag_items = _bag_items.duplicate()
		var remainder: int = int(_bag_items.get(item, 0)) - count
		if remainder > 0: _bag_items[item] = remainder
		else: _bag_items.erase(item)
	cargo.refresh(cargo_items)
	if _active == "cargo" and cargo.selected.is_empty(): _active = "bag"
	_refresh_bag_page()

func _refresh_bag_page() -> void:
	var keys: Array = _bag_items.keys()
	keys.sort()
	_page_count = maxi(1, ceili(float(keys.size()) / PERSONAL_SLOTS))
	_page = clampi(_page, 0, _page_count - 1)
	_pager.visible = _page_count > 1
	_page_label.text = "%d / %d" % [_page + 1, _page_count]
	_previous_page.disabled = _page == 0
	_next_page.disabled = _page == _page_count - 1
	var page_items: Dictionary = {}
	for key: String in keys.slice(_page * PERSONAL_SLOTS, (_page + 1) * PERSONAL_SLOTS):
		page_items[key] = _bag_items[key]
	bag.refresh(page_items, _subject.get("equipment", {}), _subject.get("base_stats", {}))

func _step_page(direction: int) -> void:
	_page += direction
	bag.select("", false)
	_refresh_bag_page()
	_select_section("bag")

func _selected_key() -> String:
	match _active:
		"container": return container.selected
		"cargo": return cargo.selected
		_: return bag.selected

func _refresh_controls() -> void:
	if _frame == null: return
	var key: String = _selected_key()
	var contents: Dictionary = _target.get("inventory", {}) if _active == "container" else _bag_items
	var count: int = int(contents.get(key, 0))
	var viewing_cargo: bool = _active == "cargo"
	_quantities.visible = not viewing_cargo
	_actions.visible = not viewing_cargo
	_purpose.visible = _show_purpose and not viewing_cargo
	_donate.visible = _show_donation and not viewing_cargo
	amount.max_value = maxi(1, count)
	_choice.text = "—" if key.is_empty() else Grid.item_tooltip(key, _subject.get("equipment", {}), _subject.get("base_stats", {}))
	if viewing_cargo and not _shipment.is_empty():
		_choice.text = "%s ×%d · %s" % [Items.label(key), int(_shipment.count), "退运中" if _shipment.state == "returning" else "运送中"]
	if _active == "bag" and not key.is_empty() and _subject.has("stock_rights"):
		var own: int = 0
		var entrusted: int = 0
		for batch: Dictionary in _subject.stock_rights.get(key, []):
			if key == _shipment.get("item") and batch.entrust == _shipment.entrust and batch.phase == "issued": continue
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
	var take_context: Dictionary = {"item": key}
	if _purpose.visible and _purpose.item_count > 0: take_context.merge(_purpose.get_item_metadata(_purpose.selected))
	_take.disabled = not controllable or _active != "container" or count <= 0 or _target.is_empty() or _full(_subject) or not Actions.Query.evaluate(Actions.Operations.OPERATIONS.take, _subject, _target, take_context).ready
	_put.disabled = not controllable or _active != "bag" or count <= 0 or _target.is_empty() or _full(_target) or not Actions.Query.evaluate(Actions.Operations.OPERATIONS.put, _subject, _target, {"item": key, "donate": _donate.button_pressed}).ready

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
	var key: String = _selected_key()
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
