extends CanvasLayer
## Playable catalog only: route intentions to existing adapters. No rule executor.
const UI = preload("res://scripts/ui/reol_ui_theme.gd")
const CATALOG: String = "res://data/scenarios/feature_tour.json"
var _main: Node2D
var _locations: Dictionary
var _chapters: Array = []
var _selected: int = 0
var _resume: bool = false
var _overlay: Control
var _title: Label
var _body: RichTextLabel
var _actions: HFlowContainer
var _notice: Label
var _list: ItemList
var _compact: PanelContainer
var _compact_text: Label
var _restart_dialog: ConfirmationDialog
var _restart_subject: String


func setup(main: Node2D, locations: Dictionary) -> void:
	_main = main
	_locations = locations
	layer = 30
	process_mode = Node.PROCESS_MODE_ALWAYS
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(CATALOG))
	_chapters = catalog.chapters
	_build()
	select_chapter(0)
	open_book()
	_resume = true


func runtime() -> WorldContinuityRuntime:
	return _main._continuity


func _build() -> void:
	var screen := Control.new()
	add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = UI.create()
	_compact = PanelContainer.new()
	screen.add_child(_compact)
	_compact.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	_compact.offset_left = -195
	_compact.offset_right = 195
	_compact.offset_top = -88
	_compact.offset_bottom = -16
	var compact_rows := VBoxContainer.new()
	_compact.add_child(compact_rows)
	_compact_text = UI.label(compact_rows, "", UI.JADE, 14)
	var compact_actions := HBoxContainer.new()
	compact_rows.add_child(compact_actions)
	UI.button(compact_actions, "功能导览 · F1", open_book)
	UI.button(compact_actions, "生活面板 · F2", toggle_life_panels)
	_overlay = ColorRect.new()
	(_overlay as ColorRect).color = Color(0.025, 0.045, 0.05, 0.9)
	screen.add_child(_overlay)
	_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	_overlay.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	var panel := PanelContainer.new()
	margin.add_child(panel)
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	var rows := VBoxContainer.new()
	panel.add_child(rows)
	var top := HBoxContainer.new()
	rows.add_child(top)
	UI.label(top, "REOL / 功能试游", UI.GOLD, 25)
	UI.button(top, "收起导览，进入世界 · F1", close_book)
	var residents: int = 0
	for sim: VillageSimulation in runtime().world_sim.regions.values():
		residents += sim.actor_ids().size()
	UI.label(rows, "%d项体验入口 · %d名居民 · 房屋 / 生活 / 草木 / 环境 / 学习 / 交锋 / 不同身体" % [_chapters.size(), residents], UI.MUTED, 14)
	var columns := HBoxContainer.new()
	columns.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rows.add_child(columns)
	_list = ItemList.new()
	_list.custom_minimum_size.x = 255
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(_list)
	for chapter: Dictionary in _chapters:
		_list.add_item(str(chapter.title))
	_list.item_selected.connect(select_chapter)
	var details := VBoxContainer.new()
	details.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	columns.add_child(details)
	_title = UI.label(details, "", UI.GOLD, 22)
	_body = RichTextLabel.new()
	_body.bbcode_enabled = false
	_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_font_size_override("normal_font_size", 17)
	details.add_child(_body)
	_actions = HFlowContainer.new()
	details.add_child(_actions)
	_notice = UI.label(details, "", UI.WARNING, 14)
	_notice.custom_minimum_size.y = 48
	var bottom := HBoxContainer.new()
	rows.add_child(bottom)
	UI.button(bottom, "上一项", _next.bind(-1))
	UI.button(bottom, "下一项", _next.bind(1))
	UI.label(bottom, "F1导览 · F2生活面板 · 空格暂停 · F5/F9独立试游存读", UI.MUTED, 13)
	_restart_dialog = ConfirmationDialog.new()
	_restart_dialog.title = "重新开始功能试游"
	_restart_dialog.dialog_text = "将重新建立小世界，并开始所选身份的人生。\n当前未保存的试游进度会丢弃；已保存的槽不会被删除。"
	_restart_dialog.ok_button_text = "重新开始"
	_restart_dialog.cancel_button_text = "继续当前试游"
	_restart_dialog.confirmed.connect(_restart)
	add_child(_restart_dialog)
	runtime().save_finished.connect(_on_save_finished)


func select_chapter(index: int) -> void:
	_selected = clampi(index, 0, _chapters.size() - 1)
	_list.select(_selected)
	var chapter: Dictionary = _chapters[_selected]
	_title.text = chapter.title
	_body.text = "%s\n\n怎么体验\n%s\n\n观察什么\n%s\n\n当前范围\n%s" % [chapter.summary, chapter.steps, chapter.observe, chapter.limit]
	for child: Node in _actions.get_children():
		_actions.remove_child(child)
		child.queue_free()
	for entry: Array in chapter.actions:
		UI.button(_actions, str(entry[0]), perform.bind(str(entry[1])))
	_compact_text.text = chapter.title
	_notice.text = "导览已暂停世界；选择操作或收起后继续。"


func _next(direction: int) -> void:
	select_chapter(posmod(_selected + direction, _chapters.size()))


func open_book() -> void:
	_resume = not GameClock.paused
	GameClock.set_paused(true)
	_overlay.show()
	_compact.hide()
	_list.grab_focus()


func close_book() -> void:
	_overlay.hide()
	_compact.show()
	get_viewport().gui_release_focus()
	if _resume:
		GameClock.set_paused(false)


func toggle_life_panels() -> void:
	if not runtime().human_player_active():
		return
	runtime().set_life_panels_visible(not runtime().life_panels_visible)


func perform(action: String) -> void:
	if action.begins_with("restart:"):
		_restart_subject = action.trim_prefix("restart:")
		_restart_dialog.popup_centered(Vector2i(490, 180))
		return
	if not runtime().simulation_accessible() or GameClock.has_pending_advance():
		_notice.text = "上一段结算仍在完成，请稍后再点一次。"
		return
	if action in ["save", "load"]:
		var result: Error = runtime().request_save(_main.SAVE_SLOT) if action == "save" else runtime().load_game(_main.SAVE_SLOT)
		if action == "load" and result == OK:
			_resume = not GameClock.paused
			GameClock.set_paused(true)
		_notice.text = ("已受理保存，回执见行旅面板。" if action == "save" else "已接续试游存档。") if result == OK else "未完成：" + error_string(result)
		return
	if action == "play":
		_resume = true
		close_book()
		return
	if action == "environment":
		_read_environment()
		return
	if action.begins_with("wait:"):
		if GameClock.request_wait(action.get_slice(":", 1).to_int()):
			_resume = true
			close_book()
		else:
			_notice.text = "眼下不适合等候，请先停下动作或离开危险。"
		return
	if not runtime().human_player_active():
		_notice.text = "这项操作属于人身；当前身体的键位见雀身/残识章节。可重新开始人身试游。"
		return
	if action.begins_with("walk"):
		var key: String = str(_chapters[_selected].get("place", "home"))
		if not _locations.has(key):
			return
		_hide_feature_panels()
		if runtime().travel_to("river" if action == "walk:river" else "home", _locations[key]):
			_resume = true
			close_book()
		else:
			_notice.text = "暂不能前往。请先停手或结束当前事务，也可以WASD自行走过去。"
		return
	if action == "observe":
		if runtime().natural_adapter.observe(_locations.plants):
			_resume = true
			close_book()
		else:
			_notice.text = "先走近植物区，再观察可见草药。"
		return
	if action in ["tree", "beast"]:
		var point := Vector2i(-1, -1)
		if action == "tree" and runtime().world_sim.plants.bodies.has("opening:old_tree"):
			point = runtime().world_sim.plants.cell_of("opening:old_tree")
		elif action == "beast" and not runtime().world_sim.large_bodies.bodies.is_empty():
			point = runtime().world_sim.large_bodies.body_cell(str(runtime().world_sim.large_bodies.bodies.keys()[0]))
		if point.x >= 0:
			for offset: Vector2i in SimConstruction.cells_in(Rect2i(Vector2i(-3, -3), Vector2i(7, 7))):
				if runtime().travel_to("home", point + offset):
					_resume = true
					close_book()
					return
			_notice.text = "暂时无法前往，请先停下手中事务。"
		else:
			_notice.text = "这个样本当前已不存在。"
		return
	_hide_feature_panels()
	if action.begins_with("services:"):
		runtime().set_life_panels_visible(true)
		runtime().service_adapter.panel._select_page(action.get_slice(":", 1).to_int())
	elif action.begins_with("object:"):
		if not runtime().object_adapter.select_object(action.trim_prefix("object:")):
			_notice.text = "请先到场看见该物品，或在I页选择本人已知的器物。"
			return
	elif action.begins_with("vessel:"):
		if not runtime().soul_adapter.select_vessel(action.trim_prefix("vessel:")):
			_notice.text = "先靠近灶房，看见旧戒，再查看其中的残识。"
			return
	elif action.begins_with("panel:"):
		_open_panel(action.get_slice(":", 1))
	_resume = true
	close_book()


func _hide_feature_panels() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	adapter.set_life_panels_visible(false)
	for domain: Node in [adapter.object_adapter, adapter.interaction_adapter, adapter.construction_adapter, adapter.heat_method_adapter,
		adapter.capability_adapter, adapter.field_adapter, adapter.clothing_adapter, adapter.conflict_adapter,
		adapter.sparring_adapter, adapter.avian_adapter, adapter.soul_adapter, adapter.spirit_adapter, adapter.natural_adapter]:
		domain.panel.hide()


func _open_panel(key: String) -> void:
	var adapter: WorldContinuityRuntime = runtime()
	match key:
		"interaction": adapter.interaction_adapter.show_panel()
		"construction": adapter.construction_adapter.show_panel()
		"methods": adapter.heat_method_adapter.show_panel()
		"capability": adapter.capability_adapter.show_panel()
		"field": adapter.field_adapter.show_panel()
		"spirit": adapter.spirit_adapter.show_panel()
		"clothing":
			adapter.clothing_adapter.panel.show()
			adapter.clothing_adapter.refresh()
		"conflict":
			adapter.conflict_adapter.panel.show()
			adapter.conflict_adapter.refresh()
		"sparring":
			adapter.sparring_adapter.panel.show()
			adapter.sparring_adapter.refresh()
		"avian":
			adapter.avian_adapter.panel.show()
			adapter.avian_adapter.refresh()
		"travel": adapter.set_life_panels_visible(true)


func _read_environment() -> void:
	var fields: SimWorldEnvironmentFields = runtime().world_sim.environment_fields
	var lines: Array[String] = ["开发观察 · 完整边界 %dms（不写入角色认识）" % GameClock.elapsed_ms]
	for row: Array in [["本人", runtime().controlled_cell()], ["暖源房", _locations.warm_room], ["寒源房", _locations.cold_room], ["院外", _locations.yard]]:
		var point: Vector2i = row[1]
		var context: Dictionary = fields.context_at(point)
		if not context.ok:
			lines.append("%s %s · 环境暂不可用" % [row[0], point])
			continue
		var elements: PackedFloat64Array = context.elements
		lines.append("%s %s · %s\n温度 %.2f℃ · 照度 %.0f\n木 %.1f / 火 %.1f / 土 %.1f / 金 %.1f / 水 %.1f" % [row[0], point,
			"有屋顶" if context.roofed else "露天", context.temperature_c, context.light_relative,
			elements[0], elements[1], elements[2], elements[3], elements[4]])
	_body.text = "\n\n".join(lines)
	_notice.text = "世界仍暂停。继续运行一段时间，再次读取即可比较变化；这些数值仅供开发观察。"


func _on_save_finished(path: String, result: Error) -> void:
	if path == _main.SAVE_SLOT:
		_notice.text = "试游近况已保存，可关闭后重开本demo读取。" if result == OK else "保存失败：" + error_string(result)


func _restart() -> void:
	GameClock.set_paused(true)
	while not runtime().simulation_accessible() or GameClock.has_pending_advance():
		await get_tree().process_frame
	get_tree().set_meta("feature_tour_avatar", _restart_subject)
	get_tree().reload_current_scene()


func _input(event: InputEvent) -> void:
	if not event is InputEventKey or not event.pressed or event.echo:
		return
	if _restart_dialog.visible:
		return
	if event.keycode == KEY_F1:
		if _overlay.visible:
			close_book()
		else:
			open_book()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and _overlay.visible:
		close_book()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_F2 and not _overlay.visible:
		toggle_life_panels()
		get_viewport().set_input_as_handled()
	elif _overlay.visible and (event.keycode in [KEY_W, KEY_A, KEY_S, KEY_D, KEY_SPACE, KEY_1, KEY_2, KEY_4, KEY_T] or event.shift_pressed):
		get_viewport().set_input_as_handled()
