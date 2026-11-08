class_name SettlementServicesPanel
extends PanelContainer
## Local services present intentions; eligibility and settlement remain in sim.

signal service_requested(action_id: String)
signal gather_mode_changed
signal batch_selected

const UI = preload("res://scripts/ui/reol_ui_theme.gd")

var _title: Label
var _activity: Label
var _details: Label
var _notice: Label
var _phase: Label
var _local_buttons: Array[Button] = []
var _pages: Array[Control] = []
var _tabs: Array[Button] = []
var personal_gather: CheckButton
var _personal_tasks: Dictionary = {}
var batch_choice: OptionButton
var _batch_note: Label
var _resume_batch: Button
var _collect_batch: Button
var _labor_note: Label
var _resume_labor: Button
var _abandon_labor: Button
var _resource_note: Label


func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	custom_minimum_size = Vector2(418, 0)
	mouse_filter = Control.MOUSE_FILTER_STOP
	theme = UI.create()
	add_theme_stylebox_override("panel", UI.panel(UI.GOLD.darkened(0.5)))
	var column := VBoxContainer.new()
	add_child(column)
	_title = UI.label(column, "生活与办事", UI.GOLD, 18)
	_details = UI.label(column, "", UI.PAPER)
	var activity_box := PanelContainer.new()
	activity_box.add_theme_stylebox_override("panel", UI.panel(Color("#344d43")))
	column.add_child(activity_box)
	var activity_rows := VBoxContainer.new()
	activity_rows.add_theme_constant_override("separation", 2)
	activity_box.add_child(activity_rows)
	_activity = UI.label(activity_rows, "暂未安排事务", UI.JADE)
	_phase = UI.label(activity_rows, "选择下方事项，人物会自行前往办理。", UI.MUTED, 12)
	var tab_row := GridContainer.new()
	tab_row.columns = 4
	column.add_child(tab_row)
	for tab_name: String in ["生活", "差事与凭据", "互助", "劳作", "交谈", "采集", "制作", "工钱"]:
		var index: int = _tabs.size()
		var tab: Button = UI.button(tab_row, tab_name, _select_page.bind(index))
		tab.toggle_mode = true
		_tabs.append(tab)
	for _index in range(_tabs.size()):
		var page := GridContainer.new()
		page.columns = 2
		page.custom_minimum_size.y = 66
		column.add_child(page)
		_pages.append(page)
	_action(_pages[0], "取食", "eat")
	_action(_pages[0], "歇息", "rest")
	_action(_pages[0], "贡献换饭", "redeem")
	_action(_pages[1], "承接运粮", "haul_grain")
	_action(_pages[1], "去报工", "report")
	_action(_pages[1], "申请通行", "access")
	_action(_pages[1], "凭据取药", "collect_herb")
	_action(_pages[1], "交回受托物资", "return_goods")
	_action(_pages[2], "去仓库等候", "meet_courier")
	_action(_pages[2], "请人运粮", "ask_help")
	_action(_pages[2], "商议报酬", "offer_help")
	for entry: Array in [["亲自送柴", "deliver_wood"], ["挑水", "deliver_water"],
		["运粮到灶房", "deliver_grain"], ["下厨做饭", "cook"],
		["到功德堂交工", "report"], ["查看灶房", "check_kitchen"]]:
		_action(_pages[3], str(entry[0]), "work:" + str(entry[1]))
	_action(_pages[4], "问同门灶房近况", "talk:ask")
	_action(_pages[4], "转告：余柴不多", "talk:shortage")
	_action(_pages[4], "声称：余柴充足", "talk:supplied")
	_action(_pages[4], "声称已有取药登记", "talk:claim")
	_action(_pages[4], "出示本人通行签注", "talk:show_pass")
	_action(_pages[4], "请对方核验登记", "talk:verify")
	_action(_pages[4], "出示最近核验回执", "talk:receipt")
	personal_gather = CheckButton.new()
	personal_gather.text = "自留采集"
	personal_gather.tooltip_text = "自己采集，所得留在行囊；没有送公库的公差功劳。已接下的工作不会随开关改变。"
	personal_gather.toggled.connect(func(_value: bool) -> void: gather_mode_changed.emit())
	_pages[5].add_child(personal_gather)
	UI.label(_pages[5], "关闭则按原公差送库。", UI.MUTED, 12)
	for entry: Array in [["林缘拾柴", "gather_wood"], ["采野稗脱粒", "forage_grain"],
		["汲泉入水缸", "draw_water"], ["坡边采药", "gather_herb"]]:
		_action(_pages[5], str(entry[0]), "work:" + str(entry[1]))
	_action(_pages[5], "用私水浇药", "work:irrigate_herb")
	_resource_note = UI.label(_pages[5], "药丛近况须走近查看。", UI.MUTED, 12)
	_resource_note.max_lines_visible = 3
	_action(_pages[6], "私料煮饭", "production:new:cook_rations")
	_action(_pages[6], "私料焙药", "production:new:dry_herbs")
	batch_choice = OptionButton.new()
	batch_choice.custom_minimum_size.x = 214
	batch_choice.clip_text = true
	batch_choice.item_selected.connect(func(_index: int) -> void: batch_selected.emit())
	_pages[6].add_child(batch_choice)
	_batch_note = UI.label(_pages[6], "物料投入后留在现场。", UI.MUTED, 12)
	_resume_batch = UI.button(_pages[6], "继续所选批次", _submit.bind("production:make"))
	_collect_batch = UI.button(_pages[6], "去取所选成品", _submit.bind("production:collect"))
	(_pages[7] as GridContainer).columns = 1
	UI.label(_pages[7], "C 与有付款权的管事商量承接/验收。", UI.MUTED, 12)
	_labor_note = UI.label(_pages[7], "尚未签下现金差事。", UI.PAPER, 13)
	_resume_labor = UI.button(_pages[7], "续做原差事", _submit.bind("labor:resume"))
	_abandon_labor = UI.button(_pages[7], "放弃未交付差事", _submit.bind("labor:abandon"))
	_notice = UI.label(column, "", UI.MUTED, 13)
	_notice.mouse_filter = Control.MOUSE_FILTER_PASS
	_notice.custom_minimum_size.y = 40
	_notice.max_lines_visible = 2
	var stop: Button = UI.button(column, "停止当前行动", _submit.bind("cancel"))
	stop.tooltip_text = "WASD手动行走也会中断当前行动；受托公物仍须续做或交回，不会变为私物。"
	_select_page(0)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	offset_left = 16
	offset_right = 434
	offset_top = -380
	offset_bottom = -16
	grow_vertical = Control.GROW_DIRECTION_BEGIN


func set_labor(line: String, can_resume: bool, can_abandon: bool) -> void:
	_labor_note.text = line
	_resume_labor.disabled = not can_resume
	_abandon_labor.disabled = not can_abandon


func update_view(place: String, activity: String, details: String, notice: String, local: bool) -> void:
	_title.text = "生活与办事 · %s" % place
	_activity.text = activity
	_details.text = details
	update_notice(notice)
	for button: Button in _local_buttons:
		button.disabled = not local


func update_notice(notice: String) -> void:
	_notice.text = notice
	_notice.tooltip_text = notice


func update_activity(phase: String, remaining: int, busy: bool, seconds: bool = false) -> void:
	if not busy:
		_phase.text = "选择事项后会自行前往；WASD可中断。"
		return
	if phase == "rest":
		_phase.text = "持续休息 · 精神充足或肚饿时起身，可主动停下。"
		return
	var phase_text: String = {"travel": "前往办理地点", "work": "正在办理"}.get(phase, phase)
	_phase.text = "%s · 距下一步 %d %s" % [phase_text, maxi(0, remaining), "秒" if seconds else "分钟"]


func set_home_work_available(available: bool) -> void:
	for button: Button in _local_buttons:
		var action: String = str(button.get_meta("service_action", ""))
		if action.begins_with("work:") or action.begins_with("talk:"):
			button.disabled = not available
			if action.begins_with("work:"):
				button.tooltip_text = ("带自己的水走到药丛照料；耗时而不记公差贡献。" if action == "work:irrigate_herb" else "使用真实材料并消耗时间；先完成劳动，再到功德堂登记。") if available else "这是山门的杂务，请先回山门。"
			else:
				button.tooltip_text = "先选中附近同门；听到不等于采信，说法不改变真实库存。" if available else "先回山门，与当地同门当面交谈。"


func set_help_offer(amount: int) -> void:
	for button: Button in _local_buttons:
		if button.get_meta("service_action", "") == "offer_help":
			button.text = "出%d钱请人" % amount
			button.tooltip_text = "报酬先托管，实际送达才支付；已有承诺不会被挤掉。"


func set_resource_work(config: Dictionary, domain: SimLandResources, visible_sources: Dictionary = {}) -> void:
	_resource_note.text = "药丛近况须走近查看。"
	_resource_note.tooltip_text = _resource_note.text
	for button: Button in _local_buttons:
		var action: String = str(button.get_meta("service_action", "")).trim_prefix("work:")
		if not action in ["gather_wood", "forage_grain", "draw_water", "gather_herb", "irrigate_herb"]:
			continue
		var irrigation: bool = action == "irrigate_herb"
		if personal_gather.button_pressed and not irrigation:
			action = str(_personal_tasks.get(action, ""))
		if not config.actions.has(action):
			button.disabled = true
			button.tooltip_text = "这段旧世界尚未记录此处的采集来源。"
			if irrigation:
				_resource_note.text = "这段旧世界没有登记可照料的药丛。"
				_resource_note.tooltip_text = _resource_note.text
			continue
		var terms: Dictionary = config.actions[action]
		button.text = str(terms.label)
		var observed: bool = bool(visible_sources.get(str(terms.resource), false))
		var description: String = domain.describe("player", str(terms.resource)) if observed else str(domain.terms_for(str(terms.resource)).get("description", "")) + " 眼下看不清此处近况。"
		if irrigation:
			button.tooltip_text = "%s\n需自己的%d份水、%d分钟劳动；完成才浇入，不记公差贡献。" % [description, int(terms.amount), int(terms.minutes)]
			if observed:
				_resource_note.text = description
				_resource_note.tooltip_text = description
		else:
			button.tooltip_text = "%s\n采集需%d分钟；%s" % [description, int(terms.minutes), "完成后实物留在行囊，不发公差贡献。" if terms.kind == "forage" else "采出后另行送库，途中中断保留已采物。"]


func set_gather_modes(rules: Dictionary) -> void:
	_personal_tasks.clear()
	for id: String in rules.actions:
		_personal_tasks[str(rules.actions[id].public_action)] = id


func selected_batch() -> String:
	return "" if batch_choice.selected < 0 else str(batch_choice.get_item_metadata(batch_choice.selected))


func set_production(definitions: Dictionary, rows: Array[Dictionary], busy: bool) -> void:
	var selected: String = selected_batch()
	var signature: String = JSON.stringify(rows)
	if str(batch_choice.get_meta("rows", "")) != signature:
		batch_choice.clear()
		for row: Dictionary in rows:
			batch_choice.add_item(str(row.label))
			batch_choice.set_item_metadata(batch_choice.item_count - 1, row.id)
			if row.id == selected:
				batch_choice.select(batch_choice.item_count - 1)
		batch_choice.set_meta("rows", signature)
	batch_choice.disabled = rows.is_empty()
	_resume_batch.disabled = true
	_collect_batch.disabled = true
	_batch_note.text = "还没有自己的批次。"
	for row: Dictionary in rows:
		if row.id == selected_batch():
			_resume_batch.disabled = busy or row.state != "open"
			_collect_batch.disabled = busy or row.state != "ready"
			_batch_note.text = str(row.note)
			batch_choice.tooltip_text = str(row.label) + "\n" + str(row.note)
	for button: Button in _local_buttons:
		var action: String = str(button.get_meta("service_action", ""))
		if action.begins_with("production:new:"):
			var terms: Dictionary = definitions.recipes[action.trim_prefix("production:new:")]
			var names: Dictionary = {"wood": "柴", "grain": "粮", "water": "水", "herb": "药草", "meal": "饭", "dried_herb": "干药"}
			var materials: Array[String] = []
			for item: String in terms.inputs.merged(terms.fuel):
				materials.append("%d%s" % [int(terms.inputs.merged(terms.fuel)[item]), str(names.get(item, item))])
			button.tooltip_text = "%s；需%d分钟劳动。\n点火烧柴，停工保留原料与工时；做好后另去取。" % ["、".join(materials), ceili(float(terms.work_ms) / 60000.0)]
			button.disabled = button.disabled or busy


func set_terms(definitions: Dictionary, carried_meal: bool) -> void:
	for button: Button in _local_buttons:
		match str(button.get_meta("service_action", "")):
			"eat": button.text = "吃随身饭" if carried_meal else "取食 · %d钱" % int(definitions.visitor.eat.fee)
			"rest": button.text = "歇息 · %d钱" % int(definitions.visitor.rest.fee)
			"redeem": button.text = "换饭 · %d功" % int(definitions.redemptions.meal.cost)
			"access": button.tooltip_text = "须有当地认可的%d贡献与有权签发者；申请不扣贡献。" % int(definitions.access.gate.required_contribution)
			"haul_grain": button.tooltip_text = "实际送%d份粮；交付后另向山门报工，核验记%d贡献。" % [int(definitions.hauling.amount), int(definitions.hauling.credit)]


func _action(parent: Control, caption: String, action_id: String) -> void:
	var button: Button = UI.button(parent, caption, _submit.bind(action_id))
	button.set_meta("service_action", action_id)
	_local_buttons.append(button)


func _select_page(index: int) -> void:
	for page_index in range(_pages.size()):
		_pages[page_index].visible = page_index == index
	for tab_index in range(_tabs.size()):
		_tabs[tab_index].set_pressed_no_signal(tab_index == index)


func _submit(action_id: String) -> void:
	if action_id in ["production:make", "production:collect"]:
		action_id += ":" + selected_batch()
	var public: String = action_id.trim_prefix("work:")
	if personal_gather.button_pressed and action_id.begins_with("work:") and _personal_tasks.has(public):
		action_id = "work:" + str(_personal_tasks[public])
	service_requested.emit(action_id)
