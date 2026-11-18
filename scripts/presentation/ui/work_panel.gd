extends PanelContainer
## A role-independent workspace; live facts never rebuild an edited form.
signal requested(action: String, payload: Dictionary)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Rules = preload("res://scripts/sim/kernel/department_rules.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const DUTY_LABELS: Dictionary = {"produce": "加工", "haul": "搬运", "gather": "采集", "cultivate": "田务"}
const RIGHTS: Dictionary = {"view": "查阅", "people": "人员分工", "facilities": "设施管辖", "production": "生产管理", "supply": "供料与仓储", "delegate": "授权"}
const STATES: Dictionary = {"active": "进行中", "completed": "已完成", "cancelled": "已取消", "expired": "已结束本期", "requested": "待供方受理", "accepted": "已受理，待实际送达", "passive": "静置", "finish": "收尾", "idle": "空闲", "interaction": "执行活动", "work": "作业", "combat": "战斗"}
var department: int = 0
var _scope: String = ""
var _epoch: int = 0
var _view: Dictionary = {}
var _signature: String = ""
var _subscription: Dictionary = {}
var _body := VBoxContainer.new()
var _content := VBoxContainer.new()
var _departments := OptionButton.new()
var _scopes := OptionButton.new()
var _tabs := TabBar.new()
var _title: Label
var _live: Dictionary = {}
var _request_list: VBoxContainer
var _request_signature: String = ""
var _my_list: VBoxContainer
var _my_signature: String = ""

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	fit(get_parent_control().size)
	add_child(_body)
	var head := HBoxContainer.new()
	_body.add_child(head)
	_title = Style.label(head, "职责与管理")
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button(head, "关闭", func(): hide())
	var navigation := HBoxContainer.new()
	_body.add_child(navigation)
	navigation.add_child(_departments); navigation.add_child(_scopes)
	_departments.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_departments.item_selected.connect(func(index: int):
		department = int(_departments.get_item_metadata(index)); _scope = ""; _signature = ""; subscribe())
	_scopes.item_selected.connect(func(index: int): _scope = str(_scopes.get_item_metadata(index)); _signature = ""; subscribe())
	for title: String in ["概览", "人员与分组", "设施与库存", "生产", "供料", "授权"]: _tabs.add_tab(title)
	_body.add_child(_tabs)
	_tabs.tab_changed.connect(func(_index: int): _signature = ""; subscribe())
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_body.add_child(scroll)
	_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content)
	visibility_changed.connect(subscribe)
	hide()

func fit(available: Vector2) -> void:
	size = Vector2(minf(960, maxf(420, available.x - 24)), minf(640, maxf(300, available.y - 24)))
	position = (available - size) * 0.5

func subscribe() -> void:
	_subscription = {"department": department, "group": _scope, "page": _tabs.current_tab}
	var request: Dictionary = _subscription.duplicate(); request["enabled"] = visible
	requested.emit("work_view", request)

func button(parent: Node, title: String, action: Callable, enabled: bool = true) -> Button:
	var value := Button.new(); value.text = title; value.disabled = not enabled
	value.pressed.connect(action); parent.add_child(value)
	return value

func line(parent: Node, text: String) -> Label:
	var value: Label = Style.label(parent, text)
	value.autowrap_mode = TextServer.AUTOWRAP_OFF if parent is HFlowContainer else TextServer.AUTOWRAP_WORD_SMART
	value.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return value

func row(parent: Node = null) -> HFlowContainer:
	var value := HFlowContainer.new(); (parent if parent != null else _content).add_child(value); return value

func number(parent: Node, minimum: int = 1, maximum: int = 1000000, initial: int = 100) -> SpinBox:
	var value := SpinBox.new(); value.min_value = minimum; value.max_value = maximum; value.value = initial
	parent.add_child(value); return value

func options(parent: Node, entries: Array, label: String = "title") -> OptionButton:
	var value := OptionButton.new(); parent.add_child(value)
	for entry: Dictionary in entries: value.add_item(str(entry.get(label, entry.id)), int(entry.id))
	return value

func facility_name(record: Dictionary) -> String:
	return str(Query.BUILDINGS.get(record.definition, {}).get("label", record.definition))

func send(op: String, data: Dictionary) -> void:
	var command: Dictionary = {"kind": "management", "op": op, "department": int(_view.get("id", 0)), "revision": int(_view.get("revision", 0)), "group": _scope, "epoch": _epoch}
	command.merge(data, true); requested.emit("management", command)

func adopt(data: Dictionary, epoch: int) -> void:
	if not visible: return
	if data.get("request", {}) != _subscription: return # A late previous page must not build this page's form.
	if epoch != _epoch: _epoch = epoch; _signature = ""
	var chosen: Dictionary = data.get("selected", {})
	var variable: Array = []
	if _tabs.current_tab == 3:
		for order: Dictionary in chosen.get("orders", []): variable.append(order.id)
	var signature: String = str(chosen.get("revision", -1)) + ":" + str(chosen.get("id", 0)) + ":" + str(chosen.get("scope", "")) + ":" + str(_tabs.current_tab) + str(variable) + str(chosen.get("capabilities", [])) + str(chosen.get("scopes", []))
	_view = chosen
	department = int(chosen.get("id", 0)); _scope = str(chosen.get("scope", ""))
	if signature != _signature:
		_signature = signature
		_departments.clear(); _scopes.clear()
		for entry: Dictionary in data.get("departments", []):
			_departments.add_item(entry.title); _departments.set_item_metadata(_departments.item_count - 1, entry.id)
			if entry.id == department: _departments.select(_departments.item_count - 1)
		for scope: String in chosen.get("scopes", []):
			_scopes.add_item("部门全域" if scope.is_empty() else scope); _scopes.set_item_metadata(_scopes.item_count - 1, scope)
			if scope == _scope: _scopes.select(_scopes.item_count - 1)
		_title.text = "职责与管理 · " + str(chosen.get("title", "我的工作"))
		render()
	update_live()

func inventory_text(values: Dictionary) -> String:
	var parts: PackedStringArray = []
	for item: String in values: parts.append("%s ×%d" % [item_name(item), int(values[item])])
	return "、".join(parts) if not parts.is_empty() else "空"

func item_name(item: String) -> String:
	return Items.label(item) + (" Q%d" % Items.quality(item) if Items.quality(item) > 1 else "")

func item_key(value: String) -> String:
	var name: String = value.strip_edges()
	if Items.valid(name): return name
	var grade: int = 1
	var suffix: int = name.rfind(" Q")
	if suffix >= 0 and name.substr(suffix + 2).is_valid_int():
		grade = int(name.substr(suffix + 2)); name = name.left(suffix)
	for id: String in Items.load_definitions():
		if Items.label(id) == name:
			var key: String = Items.key_for(id, grade)
			if Items.valid(key): return key
	return value.strip_edges() # The owner reports unknown names without guessing.

func render() -> void:
	_live.clear()
	_request_list = null; _request_signature = ""; _my_list = null; _my_signature = ""
	for child: Node in _content.get_children(): _content.remove_child(child); child.queue_free()
	if _view.is_empty(): line(_content, "当前没有部门分工或管理授权。身份名称不自动授予权力。"); return
	var caps: Array = _view.get("capabilities", [])
	match _tabs.current_tab:
		0:
			var names: PackedStringArray = []
			for capability: String in caps: names.append(RIGHTS[capability])
			line(_content, "可办理：" + ("我的工作安排" if names.is_empty() else "、".join(names)))
			line(_content, "人员 %d · 设施 %d
管理命令直接受理，生产和搬运必须实际到场。" % [_view.workers.size(), _view.facilities.size()])
			line(_content, "暂停批次保留工时和原料；取消整批清工时，不耗料、不产物。目标暂停只停新批。")
			for worker: Dictionary in _view.workers: _live["person:%d" % worker.id] = line(_content, "")
			_my_list = VBoxContainer.new(); _content.add_child(_my_list)
		1: people(caps)
		2: facilities(caps)
		3: production(caps)
		4: supply(caps)
		5: authority(caps)
	update_live()

func people(caps: Array) -> void:
	var scope_title: String = "部门全域" if _scope.is_empty() else _scope
	line(_content, "名单范围 · %s / %s · %d 人" % [_view.title, scope_title, _view.workers.size()])
	line(_content, "地图绿名表示所有直接及间接下属。可切换上方的部门和分组查看相应名单。")
	for worker: Dictionary in _view.workers:
		_live["person:%d" % worker.id] = line(_content, "")
		var controls := row()
		var duties: Dictionary = {}; var groups: Dictionary = {}
		for duty: String in Rules.DUTIES:
			var toggle := CheckButton.new(); toggle.text = DUTY_LABELS[duty]; toggle.button_pressed = duty in worker.duties; toggle.disabled = "people" not in caps or not _scope.is_empty(); controls.add_child(toggle); duties[duty] = toggle
		var wide := CheckButton.new(); wide.text = "部门直属（全域）"; wide.button_pressed = worker.department_wide; wide.disabled = "people" not in caps or not _scope.is_empty(); _content.add_child(wide)
		var group_row := row()
		for group: String in _view.groups:
			var toggle := CheckButton.new(); toggle.text = group; toggle.button_pressed = group in worker.groups; toggle.disabled = "people" not in caps; group_row.add_child(toggle); groups[group] = toggle
		button(group_row, "应用分工", func():
			if not _scope.is_empty(): send("member", {"worker": worker.id, "enabled": groups[_scope].button_pressed}); return
			var chosen_duties: Array = []; var chosen_groups: Array = []
			for key: String in duties:
				if duties[key].button_pressed: chosen_duties.append(key)
			for key: String in groups:
				if groups[key].button_pressed: chosen_groups.append(key)
			send("assign", {"worker": worker.id, "duties": chosen_duties, "groups": chosen_groups, "department_wide": wide.button_pressed}), "people" in caps)
	if "people" not in caps: return
	var add_row := row(); var member := options(add_row, _view.get("candidates", []), "name")
	button(add_row, "加入本部门（先待命）", func():
		if member.selected < 0: return
		if _scope.is_empty(): send("assign", {"worker": member.get_selected_id(), "duties": [], "groups": [], "department_wide": false})
		else: send("member", {"worker": member.get_selected_id(), "enabled": true}))
	if not _scope.is_empty(): return
	line(_content, "工作组可共享人员与设施；取消全部分组不会自动扩大为全域。")
	var name := LineEdit.new(); name.placeholder_text = "新建或更新工作组名称"; _content.add_child(name)
	var checks: Dictionary = {}
	for f: Dictionary in _view.facilities:
		var toggle := CheckButton.new(); toggle.text = "#%d %s" % [f.id, facility_name(f)]; _content.add_child(toggle); checks[int(f.id)] = toggle
	button(_content, "保存工作组设施", func():
		var selected: Array = []
		for id: int in checks:
			if checks[id].button_pressed: selected.append(id)
		send("group", {"group": name.text.strip_edges(), "facilities": selected}))

func facilities(caps: Array) -> void:
	for f: Dictionary in _view.facilities:
		_live["facility:%d" % f.id] = line(_content, "")
		var controls := row()
		for mode: String in ["pause", "resume", "cancel"]:
			var control: Button = button(controls, {"pause": "暂停批次", "resume": "继续批次", "cancel": "取消整批"}[mode], func():
				for current: Dictionary in _view.facilities:
					if current.id == f.id and not current.process.is_empty(): send("batch", {"facility": f.id, "process": current.process.id, "mode": mode}), "production" in caps)
			_live["batch:%d:%s" % [f.id, mode]] = control
		if "supply" in caps:
			var policy := LineEdit.new(); policy.placeholder_text = "收纳物品名称，逗号分隔；留空不限"
			var labels: PackedStringArray = []
			for item: String in f.get("storage_policy", {}).get("items", []): labels.append(item_name(item))
			policy.text = "、".join(labels); _content.add_child(policy)
			var filter_row := row(); line(filter_row, "品质范围"); var low := number(filter_row, 1, 99, int(f.get("storage_policy", {}).get("min_tier", 1))); var high := number(filter_row, 1, 99, int(f.get("storage_policy", {}).get("max_tier", 99)))
			var destinations := LineEdit.new(); destinations.placeholder_text = "供给设施编号，逗号分隔；留空公共供给"; destinations.size_flags_horizontal = Control.SIZE_EXPAND_FILL; filter_row.add_child(destinations)
			var selected: PackedStringArray = []
			for target: int in f.get("storage_policy", {}).get("destinations", []): selected.append(str(target))
			destinations.text = ",".join(selected)
			button(filter_row, "应用仓储规则", func():
				var items: Array = []; var targets: Array = []
				for value: String in policy.text.replace("，", ",").replace("、", ",").split(",", false):
					if not value.strip_edges().is_empty(): items.append(item_key(value))
				for value: String in destinations.text.replace("，", ",").replace("、", ",").split(",", false):
					if not value.strip_edges().is_empty(): targets.append(int(value.strip_edges()))
				send("storage", {"facility": f.id, "items": items, "min_tier": int(low.value), "max_tier": int(high.value), "destinations": targets}))
	if "facilities" in caps and _scope.is_empty():
		var attach_row := row(); line(attach_row, "纳管本宗未分配设施ID"); var id := number(attach_row, 1, 1000000, 1)
		button(attach_row, "纳管", func(): send("attach", {"facility": int(id.value)}))

func production(caps: Array) -> void:
	for order: Dictionary in _view.get("orders", []):
		_live["order:%d" % order.id] = line(_content, "")
		var controls := row()
		for mode: String in ["pause", "resume", "cancel"]:
			button(controls, {"pause": "停开新批", "resume": "恢复新批", "cancel": "撤销目标"}[mode], func(): send("order_control", {"order": order.id, "mode": mode}), "production" in caps)
	if "production" not in caps: return
	line(_content, "部门全域下达总目标；切换工作组后，可从上级目标分配本组数量。整批可略超目标。")
	var create_row := row(); var operation := OptionButton.new(); create_row.add_child(operation)
	for id: String in Operations.OPERATIONS:
		if not Operations.OPERATIONS[id].recipe.is_empty(): operation.add_item(Operations.OPERATIONS[id].title); operation.set_item_metadata(operation.item_count - 1, id)
	var amount := number(create_row)
	var parents: Array = [{"id": 0, "title": "部门总目标"}] if _scope.is_empty() else []
	for order: Dictionary in _view.get("parent_orders", []): parents.append({"id": order.id, "title": "#%d %s · 可分配%d" % [order.id, Operations.OPERATIONS[order.operation].title, order.unallocated]})
	var parent := options(create_row, parents)
	var repeat := CheckButton.new(); repeat.text = "每天续单"; repeat.disabled = not _scope.is_empty(); create_row.add_child(repeat)
	button(create_row, "下达目标", func():
		if operation.selected < 0: return
		if parent.selected < 0: return
		var id: String = str(operation.get_item_metadata(operation.selected))
		var item: String = str(Operations.OPERATIONS[id].recipe.outputs.keys()[0])
		if not _scope.is_empty():
			for order: Dictionary in _view.get("parent_orders", []):
				if order.id == parent.get_selected_id(): id = order.operation; item = order.item; break
		send("order", {"operation": id, "item": item, "total": int(amount.value), "parent_order": parent.get_selected_id(), "repeat": repeat.button_pressed}))
	operation.disabled = not _scope.is_empty()
	line(_content, "工作台绑定目标（在制旧锅保留原目标归属）。")
	for f: Dictionary in _view.facilities:
		if not preload("res://scripts/sim/kernel/operation_query.gd").BUILDINGS.get(f.definition, {}).get("capabilities", {}).has("workbench"): continue
		var controls := row(); line(controls, "%s #%d" % [facility_name(f), f.id])
		var choices: Array = []
		for order: Dictionary in _view.get("orders", []):
			if order.state == "active": choices.append({"id": order.id, "title": "#%d %s %s" % [order.id, Operations.OPERATIONS[order.operation].title, order.group]})
		var choice := options(controls, choices)
		for index: int in choice.item_count:
			if choice.get_item_id(index) == int(_view.get("production", {}).get(f.id, {}).get("order", 0)): choice.select(index)
		button(controls, "绑定", func():
			if choice.selected >= 0: send("configure", {"facility": f.id, "order": choice.get_selected_id()}))

func supply(caps: Array) -> void:
	_request_list = VBoxContainer.new(); _content.add_child(_request_list)
	if "supply" not in caps: return
	var controls := row(); line(controls, "默认供方"); var supplier := options(controls, [{"id": 0, "title": "无（本部门备料）"}] + _view.get("suppliers", []))
	for index: int in supplier.item_count:
		if supplier.get_item_id(index) == _view.get("supplier", 0): supplier.select(index)
	button(controls, "设置供方", func():
		if supplier.selected >= 0: send("supplier", {"supplier": supplier.get_selected_id()}), _scope.is_empty())
	var request_row := row(); line(request_row, "接收设施")
	var places: Array = []
	for f: Dictionary in _view.facilities: places.append({"id": f.id, "title": "%s #%d" % [facility_name(f), f.id]})
	var target := options(request_row, places)
	var item := LineEdit.new(); item.placeholder_text = "物品名称，如谷物"; request_row.add_child(item); var amount := number(request_row, 1, 10000, 2)
	button(request_row, "提出供料需求", func():
		if supplier.selected >= 0 and target.selected >= 0: send("request_supply", {"supplier": supplier.get_selected_id(), "target": target.get_selected_id(), "item": item_key(item.text), "amount": int(amount.value)}))
	line(_content, "受理表示接下需求；领货时才预约具体原料与空间，送达才记收货。NPC管事会为启用配方提出缺料需求。")

func authority(caps: Array) -> void:
	line(_content, "自定义头衔只说明身份，权限取决于能力、部门和组域。管理不会占用人物身体。")
	for id: int in _view.get("grants", {}):
		var grant: Dictionary = _view.grants[id]; var labels: PackedStringArray = []
		for cap: String in grant.capabilities: labels.append(RIGHTS[cap])
		line(_content, "#%d %s：%s" % [id, grant.title, "、".join(labels)])
	if "people" in caps and _scope.is_empty():
		var coordinator_row := row(); line(coordinator_row, "自动协调人")
		var candidates: Array = [{"id": 0, "name": "无（手动管理）"}] + _view.get("candidates", [])
		var coordinator := options(coordinator_row, candidates, "name")
		for index: int in coordinator.item_count:
			if coordinator.get_item_id(index) == _view.get("head", 0): coordinator.select(index)
		button(coordinator_row, "指定协调人", func(): send("coordinator", {"worker": coordinator.get_selected_id()}))
		line(_content, "协调人须先获得本部门的供料与仓储权限；他会沿相同管理命令维护缺料需求。")
	if "delegate" not in caps: return
	var worker := options(_content, _view.get("candidates", []), "name")
	var title := LineEdit.new(); title.placeholder_text = "自定义身份名称"; _content.add_child(title)
	var checks: Dictionary = {}
	for capability: String in Rules.CAPABILITIES:
		if capability not in caps: continue
		var toggle := CheckButton.new(); toggle.text = RIGHTS[capability]; _content.add_child(toggle); checks[capability] = toggle
	var descendants := CheckButton.new(); descendants.text = "同时管理子部门（须持有对应向下授权）"; descendants.disabled = not _scope.is_empty(); _content.add_child(descendants)
	button(_content, "更新所选人的授权", func():
		if worker.selected < 0: return
		var rights: Array = []
		for capability: String in checks:
			if checks[capability].button_pressed: rights.append(capability)
		send("grant", {"worker": worker.get_selected_id(), "title": title.text, "capabilities": rights, "descendants": descendants.button_pressed}))
	if _scope.is_empty():
		var name := LineEdit.new(); name.placeholder_text = "新增下属部门名称"; _content.add_child(name)
		button(_content, "建立下属部门", func(): send("create", {"title": name.text.strip_edges()}))

func update_live() -> void:
	if _my_list != null and is_instance_valid(_my_list):
		var signature: String = str(_view.get("my_work", []))
		if signature != _my_signature:
			_my_signature = signature
			for child: Node in _my_list.get_children(): _my_list.remove_child(child); child.queue_free()
			line(_my_list, "我的可办工作（实际执行仍检查工位、原料与权限）")
			var count: int = 0
			for offer: Dictionary in _view.get("my_work", []):
				if offer.kind == "management": continue
				count += 1
				var title: String = ("%s · 设施#%d" % [Operations.OPERATIONS[offer.operation].title, offer.target]) if offer.kind == "produce" else ("%s ×%d → 设施#%d" % [Items.label(offer.item), offer.amount, offer.target])
				button(_my_list, "接手：" + title, func(): requested.emit("department_work", {"kind": "department_work", "offer": offer, "epoch": _epoch}))
			if count == 0: line(_my_list, "目前没有就绪的本职工作；可检查本人分组、工位原料或现有动作。")
	if _request_list != null and is_instance_valid(_request_list):
		var ids: Array = []
		for request: Dictionary in _view.get("supply_requests", []): ids.append(request.id)
		if str(ids) != _request_signature:
			_request_signature = str(ids)
			for child: Node in _request_list.get_children(): _request_list.remove_child(child); child.queue_free()
			for key: String in _live.keys():
				if key.begins_with("request:") or key.begins_with("accept:"): _live.erase(key)
			for request: Dictionary in _view.get("supply_requests", []):
				_live["request:%d" % request.id] = line(_request_list, "")
				if request.supplier == _view.id: _live["accept:%d" % request.id] = button(_request_list, "受理供料 #%d" % request.id, func(): send("accept_supply", {"request": request.id}), "supply" in _view.capabilities and _scope.is_empty())
				button(_request_list, "撤销需求 #%d（在途实物退回）" % request.id, func(): send("cancel_supply", {"request": request.id}), "supply" in _view.capabilities)
	for worker: Dictionary in _view.get("workers", []):
		var key: String = "person:%d" % worker.id
		if _live.has(key): _live[key].text = "%s · %s · %s" % [worker.name, worker.role, STATES.get(worker.working, worker.working)]
	for f: Dictionary in _view.get("facilities", []):
		var key: String = "facility:%d" % f.id
		var process: Dictionary = f.get("process", {})
		if _live.has(key):
			var activity: String = "无在制批次" if process.is_empty() else ("已暂停 · " if process.paused else "") + str(STATES.get(process.stage, process.stage)) + " · 剩余标准劳动 %.1f 秒" % (float(process.remaining_ms) / 1000.0)
			_live[key].text = "#%d %s · 容量%d · 已预约%d
%s
%s" % [f.id, facility_name(f), f.capacity, f.reserved_capacity, inventory_text(f.inventory), activity]
		for mode: String in ["pause", "resume", "cancel"]:
			var button_key: String = "batch:%d:%s" % [f.id, mode]
			if _live.has(button_key): _live[button_key].disabled = "production" not in _view.capabilities or process.is_empty() or (mode == "pause" and process.get("paused", false)) or (mode == "resume" and not process.get("paused", false))
	for order: Dictionary in _view.get("orders", []):
		var key: String = "order:%d" % order.id
		if _live.has(key): _live[key].text = "目标 #%d %s · %s
%s %d / %d · 在制%d%s" % [order.id, order.group if not order.group.is_empty() else "部门", STATES.get(order.state, order.state), Items.label(order.item), order.fulfilled, order.total, order.wip, " · 停开新批" if order.paused else ""]
	for request: Dictionary in _view.get("supply_requests", []):
		var key: String = "request:%d" % request.id
		if _live.has(key): _live[key].text = "需求 #%d %s ×%d → 设施#%d · 在途%d · 已送达%d · %s" % [request.id, Items.label(request.item), request.amount, request.target, request.get("in_transit", 0), request.received, STATES.get(request.state, request.state)]
		key = "accept:%d" % request.id
		if _live.has(key): _live[key].disabled = "supply" not in _view.capabilities or not _scope.is_empty() or request.state != "requested"
