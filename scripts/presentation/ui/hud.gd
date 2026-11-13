extends Control
## Native HUD. Values come from detached frames; actions leave through one signal.
signal requested(action: String, payload: Dictionary)
signal scale_applied(factor: float)
const Style = preload("res://scripts/presentation/ui/style.gd")
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Minimap = preload("res://scripts/presentation/ui/minimap.gd")
const Art = preload("res://scripts/presentation/art.gd")
const Units = preload("res://scripts/sim/kernel/units.gd")
const EventText = preload("res://scripts/presentation/ui/event_text.gd")
const BASE_SCALE: float = 0.5
var ui_percent: int = 100
var minimap := Minimap.new()
var _top := VBoxContainer.new()
var _clock: Label
var _performance: Label
var _tides: Label
var _player_values: Label
var _action_values: Label
var _progress := ProgressBar.new()
var _inspect_panel: PanelContainer
var _inspect_body := VBoxContainer.new()
var _inspect_title: Label
var _inspect_values: Label
var _commands := GridContainer.new()
var _drawer_panel: PanelContainer
var _drawer_body := VBoxContainer.new()
var _drawer_name: String = ""
var _map_panel: PanelContainer
var _probe_panel: PanelContainer
var _probe: Label
var _notice := HBoxContainer.new()
var _tool_button: Button
var _rotate_button: Button
var _receipt: Label
var _pause: Button
var _follow: Button
var _ranged: Button
var _map_in: Button
var _map_out: Button
var _map_follow: Button
var _speed_buttons: Dictionary = {}
var _player_buttons: Dictionary = {}
var _command_signature: String = ""
var _drawer_signature: String = ""
var _frame: RefCounted
var _target: Dictionary = {}
var _selected: int = 1
var _help_target: int = 0
var _modal := ColorRect.new()
var _modal_panel: PanelContainer
var _modal_body := VBoxContainer.new()
var _modal_kind: String = ""
var _amount: SpinBox
var _stock_items: ItemList
var _stock_values: Label
var _stock_kind: String = ""
var _stock_target: int = 0
var _stock_epoch: int = 0
var _stock_keys: Array = []
var _accept: Button
var _scale_input: SpinBox
var _events: RichTextLabel
var _event_signature: String = ""
var _context_panel: PanelContainer
var _context_body := VBoxContainer.new()
var _context: Dictionary = {}
var _tooltip_until: int = 0

func _ready() -> void:
	Actions.load_definitions()
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = Style.theme()
	var top_panel: PanelContainer = _panel(self, Control.PRESET_TOP_WIDE, Vector4(8, 8, -8, 78))
	top_panel.add_child(_top)
	var first := HBoxContainer.new()
	_top.add_child(first)
	_clock = Style.label(first)
	_clock.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_pause = _button(first, "pause", "", "pause")
	for value: int in [1, 2, 4]:
		_speed_buttons[value] = _button(first, "speed", "%d×" % value, "", {"speed": value})
	_performance = Style.label(first)
	_button(first, "save", "", "save")
	_button(first, "load", "", "load")
	_button(first, "pause_menu", "", "menu")
	_tides = Style.label(_top)
	var dock: PanelContainer = _panel(self, Control.PRESET_CENTER_BOTTOM, Vector4(-292, -128, 292, -8))
	dock.add_theme_stylebox_override("panel", Style.box(Color("18251ff2"), Style.GOLD))
	var dock_body := VBoxContainer.new()
	dock.add_child(dock_body)
	_player_values = Style.label(dock_body)
	_action_values = Style.label(dock_body)
	_progress.custom_minimum_size.y = 5
	_progress.show_percentage = false
	_progress.max_value = 1.0
	dock_body.add_child(_progress)
	var combat := HBoxContainer.new()
	dock_body.add_child(combat)
	for row: Array in [["move_tool", "M", "move"], ["attack_move", "A", "attack"], ["stop", "S", "stop"], ["hold", "H", "hold"], ["work", "J", "work"], ["heal", "E", "potion"], ["ability", "", "plant"]]:
		_player_buttons[row[0]] = _button(combat, row[0], row[1], row[2])
	_ranged = _button(combat, "ranged", "弓", "target")
	_follow = _button(combat, "follow", "F", "eye")
	_inspect_panel = _panel(self, Control.PRESET_BOTTOM_LEFT, Vector4(8, -450, 330, -135))
	_inspect_panel.add_theme_stylebox_override("panel", Style.box(Color("18251ff2"), Style.TEAL))
	_inspect_panel.add_child(_inspect_body)
	_inspect_title = Style.label(_inspect_body)
	_inspect_title.add_theme_color_override("font_color", Style.TEAL)
	_inspect_values = Style.label(_inspect_body)
	_inspect_values.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_inspect_values.custom_minimum_size.x = 286
	_commands.columns = 3
	_inspect_body.add_child(_commands)
	_drawer_panel = _panel(self, Control.PRESET_BOTTOM_LEFT, Vector4(8, -546, 354, -135))
	var drawer_scroll := ScrollContainer.new()
	drawer_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_drawer_panel.add_child(drawer_scroll)
	_drawer_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	drawer_scroll.add_child(_drawer_body)
	_drawer_panel.hide()
	var toolbar: PanelContainer = _panel(self, Control.PRESET_BOTTOM_LEFT, Vector4(8, -126, 330, -8))
	var tabs := GridContainer.new()
	tabs.columns = 2
	toolbar.add_child(tabs)
	for row: Array in [["build_menu", "营造 B", "build"], ["plant_menu", "种植", "plant"], ["inventory", "背包 I", "bag"], ["character", "人物", "person"], ["travel", "地区", "map"], ["dev", "DEV", "gear"]]:
		_button(tabs, row[0], row[1], row[2])
	_map_panel = _panel(self, Control.PRESET_BOTTOM_RIGHT, Vector4(-226, -306, -8, -72))
	var map_body := VBoxContainer.new()
	_map_panel.add_child(map_body)
	minimap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	minimap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	map_body.add_child(minimap)
	var map_tools := HBoxContainer.new()
	map_body.add_child(map_tools)
	_map_out = _button(map_tools, "map_out", "−")
	_map_follow = _button(map_tools, "map_follow", "", "target")
	_map_in = _button(map_tools, "map_in", "+")
	minimap.camera_requested.connect(func(point: Vector2): requested.emit("camera", {"position": point}))
	minimap.move_requested.connect(func(point: Vector2): requested.emit("map_move", {"position": point}))
	_probe_panel = _panel(self, Control.PRESET_TOP_RIGHT, Vector4(-370, 94, -8, 222))
	_probe_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_probe = Style.label(_probe_panel, "—")
	_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_notice)
	_notice.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	_notice.position.y = 90
	_tool_button = _button(_notice, "cancel_tool", "", "target")
	_tool_button.hide()
	_rotate_button = _button(_notice, "rotate_take", "N", "rotate")
	_rotate_button.hide()
	_receipt = Style.label(_notice)
	_build_modal()
	_context_panel = _panel(self, Control.PRESET_TOP_LEFT, Vector4(0, 0, 220, 40))
	_context_panel.add_child(_context_body)
	_context_panel.hide()
	get_viewport().size_changed.connect(_layout)
	var config := ConfigFile.new()
	if config.load("user://interface.cfg") == OK: ui_percent = clampi(int(config.get_value("ui", "percent", 100)), 50, 200)
	apply_scale(ui_percent, false)

func apply_scale(percent: int, persist: bool = true) -> void:
	ui_percent = clampi(percent, 50, 200)
	scale = Vector2.ONE * BASE_SCALE * ui_percent / 100.0
	_layout()
	scale_applied.emit(scale.x)
	if persist:
		var config := ConfigFile.new()
		config.set_value("ui", "percent", ui_percent)
		config.save("user://interface.cfg")

func screen_to_ui(point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * point

func commit_scale() -> void:
	_scale_input.apply()
	requested.emit("ui_scale", {"percent": int(_scale_input.value)})

func _panel(parent: Node, preset: int, offsets: Vector4) -> PanelContainer:
	var result := PanelContainer.new()
	parent.add_child(result)
	result.set_anchors_and_offsets_preset(preset)
	result.offset_left = offsets.x
	result.offset_top = offsets.y
	result.offset_right = offsets.z
	result.offset_bottom = offsets.w
	return result

func _button(parent: Node, action: String, text: String = "", glyph: String = "", payload: Dictionary = {}) -> Button:
	var value := Button.new()
	value.text = text
	if not glyph.is_empty(): value.icon = Style.icon(glyph)
	value.custom_minimum_size = Vector2(36, 32)
	value.focus_mode = Control.FOCUS_NONE
	value.pressed.connect(func(): requested.emit(action, payload))
	parent.add_child(value)
	return value

func _clear(parent: Node) -> void:
	for child: Node in parent.get_children():
		parent.remove_child(child)
		child.queue_free()

func _layout() -> void:
	size = get_viewport_rect().size / scale
	var width: float = size.x
	var dock_width: float = minf(584, maxf(490, width - 590))
	var dock: Control = _player_values.get_parent().get_parent()
	dock.offset_left = -dock_width * 0.5
	dock.offset_right = dock_width * 0.5
	if width < 1220:
		_probe_panel.offset_top = 340
		_probe_panel.offset_bottom = 468
		_inspect_panel.anchor_top = 0
		_inspect_panel.anchor_bottom = 0
		_inspect_panel.offset_top = 92
		_inspect_panel.offset_bottom = maxf(270, size.y - 140)
		_map_panel.anchor_top = 0
		_map_panel.anchor_bottom = 0
		_map_panel.offset_top = 94
		_map_panel.offset_bottom = 328
	else:
		_probe_panel.offset_top = 94
		_probe_panel.offset_bottom = 222
		_inspect_panel.anchor_top = 1
		_inspect_panel.anchor_bottom = 1
		_inspect_panel.offset_top = -450
		_inspect_panel.offset_bottom = -135
		_map_panel.anchor_top = 1
		_map_panel.anchor_bottom = 1
		_map_panel.offset_top = -306
		_map_panel.offset_bottom = -72
	_notice.offset_left = -180
	_notice.offset_right = 180

func refresh(frame: RefCounted, selected: int, use_fog: bool, actual_speed: float, following: bool, ranged: bool, help_target: int) -> void:
	_frame = frame
	_selected = selected
	_help_target = help_target
	_target = Actions.observed(frame, selected, use_fog)
	var player: Dictionary = frame.player
	var calendar: Dictionary = frame.counters.get("calendar", {})
	set_text(_clock, "%s %s  %.1fs" % [str(calendar.get("season", "")), str(calendar.get("weather", "")), frame.world_ms / 1000.0])
	set_text(_performance, "FPS %d  %.2f / %.0f×" % [Engine.get_frames_per_second(), actual_speed, frame.speed])
	_pause.icon = Style.icon("play" if frame.paused else "pause")
	for value: int in _speed_buttons:
		_speed_buttons[value].modulate = Style.GOLD if frame.speed == value else Color.WHITE
	var tide_text := PackedStringArray()
	for i: int in mini(frame.tides.size(), 5): tide_text.append("%s %d%%" % [["金", "木", "水", "火", "土"][i], frame.tides[i]])
	set_text(_tides, "   ".join(tide_text))
	set_text(_player_values, "#1  HP %d  耐受 %.0f/%.0f  精力 %d  饥饿 %d" % [int(player.get("hp", 0)), float(player.get("tolerance", 0)), float(player.get("max_tolerance", 100)), int(player.get("energy", 0)), int(player.get("hunger", 0))])
	var action: Dictionary = player.get("action", {})
	var current: String = action_name(str(action.get("kind", "")))
	if action.is_empty(): current = "移动" if int(player.get("mode", 4)) in [0, 3, 6, 9, 10] else "—"
	var action_target: int = int(action.get("target", 0))
	if action_target > 0: current += " #%d" % action_target
	set_text(_action_values, "%.1f°C   灵气 %d   %s" % [float(player.get("temperature", 0)), int(player.get("qi", 0)), current])
	_progress.visible = action.has("started_ms")
	if _progress.visible:
		var start: int = action.started_ms
		_progress.value = clampf(float(frame.world_ms - start) / maxi(1, int(player.get("due_ms", start)) - start), 0.0, 1.0)
	var dead: bool = int(player.get("hp", 0)) <= 0
	for key: String in _player_buttons: _player_buttons[key].disabled = dead
	_player_buttons.heal.disabled = dead or int(player.get("hp", 0)) >= 100 or int(player.get("inventory", {}).get("potion", 0)) <= 0
	_player_buttons.ability.disabled = dead or not player.get("abilities", {}).get("wood_mend", false)
	_follow.modulate = Style.GOLD if following else Color.WHITE
	_ranged.modulate = Style.GOLD if ranged else Color.WHITE
	_ranged.text = "弓" if ranged else "剑"
	_map_out.disabled = minimap.span >= 512.0
	_map_in.disabled = minimap.span <= 32.0
	_map_follow.modulate = Style.GOLD if minimap.follow_player else Color.WHITE
	if dead:
		show_tool("skull", "HP 0", true)
	_inspect_panel.visible = not _target.is_empty() and _drawer_name.is_empty()
	if not _target.is_empty():
		set_text(_inspect_title, ("◷ " if _target.get("memory", false) else "") + Actions.title(_target))
		var rows := PackedStringArray()
		if _target.has("hp"): rows.append("HP %d   %s" % [int(_target.hp), str(_target.get("mode", ""))])
		if _target.has("tolerance"): rows.append("耐受 %.1f / %.0f" % [float(_target.tolerance), float(_target.max_tolerance)])
		if _target.has("position"):
			var point: Vector2 = _target.position
			rows.append("(%.2f, %.2f)   视距 %.1f" % [point.x, point.y, float(_target.get("sight_range", 0))])
		if _target.has("energy"): rows.append("精力 %d   饥饿 %d" % [int(_target.energy), int(_target.hunger)])
		if _target.has("temperature"): rows.append("%.2f°C" % float(_target.temperature))
		if _target.has("elements"): rows.append(elements(_target.elements))
		if _target.has("growth_ms"): rows.append("生长 %.1fs   阶段 %d   速率 %d" % [int(_target.growth_ms) / 1000.0, int(_target.stage), int(_target.get("rate", 0))])
		if _target.has("remaining_ms"): rows.append("%.1fs" % (int(_target.remaining_ms) / 1000.0))
		if _target.has("inventory"):
			var stock := PackedStringArray()
			for key: String in _target.inventory: stock.append("%s %d" % [Actions.items.get(key, {}).get("label", key), _target.inventory[key]])
			if not stock.is_empty(): rows.append("  ".join(stock).left(90))
		set_text(_inspect_values, "\n".join(rows))
	var commands: Array[Dictionary] = Actions.for_target(_target, player, help_target)
	var signature: String = str(commands) + str(selected)
	if signature != _command_signature:
		_command_signature = signature
		_clear(_commands)
		for spec: Dictionary in commands:
			var button: Button = _button(_commands, spec.id, spec.text, spec.icon, {"target": selected})
			button.disabled = not spec.enabled
	if not _drawer_name.is_empty(): _refresh_drawer()
	if _drawer_name == "character": _refresh_events()
	if _modal_kind in ["take", "put", "drop"]: _refresh_stock()
	if Time.get_ticks_msec() > _tooltip_until: set_text(_receipt, "")

func show_tool(glyph: String, caption: String = "", locked: bool = false) -> void:
	_tool_button.visible = not glyph.is_empty()
	_tool_button.icon = Style.icon(glyph) if not glyph.is_empty() else null
	_tool_button.text = caption
	_tool_button.disabled = locked
	_rotate_button.visible = glyph == "build" and not locked

func feedback(text: String, ok: bool) -> void:
	set_text(_receipt, text)
	_receipt.modulate = Style.TEAL if ok else Style.DANGER
	_tooltip_until = Time.get_ticks_msec() + 3500

func probe(frame: RefCounted, valid: bool) -> void:
	_probe_panel.visible = not blocks_world()
	if not _probe_panel.visible or not valid: return
	var data: Dictionary = frame.tile_probe
	if data.is_empty(): return
	# Show the completed sample as a whole while the next query is in flight.
	var tile: int = data.tile
	var point := Vector2i(tile % 512, tile / 512)
	set_text(_probe, "(%d,%d)   %.2f°C   #%d\n环境 %.1f  热 +%d  冷 −%d\n%s / %d / %d\n%s" % [point.x, point.y, float(data.get("temperature", 0)), int(data.get("room", -1)), float(data.get("ambient", 0)), int(data.get("heat", 0)), int(data.get("cold", 0)), str(data.get("substrate", "")), int(data.get("cover", 0)), int(data.get("flooring", 0)), elements(data.get("elements", []))])

static func elements(values: Variant) -> String:
	var output := PackedStringArray()
	for i: int in mini(values.size(), 5): output.append("%s %d" % [["金", "木", "水", "火", "土"][i], values[i]])
	return " ".join(output)

static func set_text(label: Label, text: String) -> void:
	if label.text != text: label.text = text

static func action_name(kind: String) -> String:
	return "—" if kind.is_empty() else EventText.name(kind)


func toggle_drawer(kind: String) -> void:
	_drawer_name = "" if _drawer_name == kind else kind
	_drawer_panel.visible = not _drawer_name.is_empty()
	_drawer_signature = ""
	_event_signature = ""
	if _frame != null: _refresh_drawer()

func _refresh_drawer() -> void:
	var signature: String = _drawer_name + str(_frame.player.get("inventory", {})) + str(_frame.player.get("methods", {})) + str(_frame.player.get("practice", 0))
	var subject: Dictionary = _target if _target.get("kind", "") == "actor" and not _target.get("memory", false) else _frame.player
	if _drawer_name == "character": signature += "#%d:%d" % [int(subject.get("id", 1)), int(subject.get("qi", 0))]
	if signature == _drawer_signature: return
	_drawer_signature = signature
	_clear(_drawer_body)
	var header := HBoxContainer.new()
	_drawer_body.add_child(header)
	Style.label(header, str({"build": "营造", "plant": "种植", "character": "人物", "travel": "地区", "dev": "DEV"}.get(_drawer_name, _drawer_name))).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(header, "close_drawer", "", "close")
	var grid := GridContainer.new()
	grid.columns = 2
	_drawer_body.add_child(grid)
	var inventory: Dictionary = _frame.player.get("inventory", {})
	if _drawer_name in ["build", "plant"]:
		var definitions: Dictionary = Actions.buildings if _drawer_name == "build" else Actions.plants
		for key: String in definitions:
			var definition: Dictionary = definitions[key]
			var item: String = str(definition.get("item", "")) if _drawer_name == "build" else str(definition.get("product", {}).get("item", ""))
			var amount: int = int(definition.get("amount", 1))
			var button: Button = _button(grid, "place_build" if _drawer_name == "build" else "place_plant", str(definition.get("label", key)), "", {"definition": key})
			button.icon = Art.icon(Actions.art_key(key))
			button.expand_icon = true
			button.custom_minimum_size.x = 150
			var cost: Label = Style.label(grid, "%s %d/%d" % [Actions.items.get(item, {}).get("label", item), int(inventory.get(item, 0)), amount])
			cost.modulate = Color.WHITE if int(inventory.get(item, 0)) >= amount else Style.DANGER
			grid.columns = 2
	elif _drawer_name == "character":
		Style.label(_drawer_body, "#%d" % int(subject.get("id", 1)))
		_button(grid, "unused", "属性", "lock").disabled = true
		if int(subject.get("id", 1)) == 1:
			_button(grid, "inventory", "背包", "bag")
			_button(grid, "study", "读书", "book").disabled = int(inventory.get("breath_manual", 0)) <= 0
			_button(grid, "ability", "回春", "plant").disabled = not _frame.player.get("abilities", {}).get("wood_mend", false)
			Style.label(_drawer_body, "灵气 %d   修行 %d" % [int(subject.get("qi", 0)), int(subject.get("practice", 0))])
			Style.label(_drawer_body, str(subject.get("methods", {}).keys()))
		Style.label(_drawer_body, "事件")
		_events = RichTextLabel.new()
		_events.custom_minimum_size = Vector2(304, 260)
		_events.scroll_following = true
		_events.selection_enabled = true
		_drawer_body.add_child(_events)
		_event_signature = ""
	elif _drawer_name == "travel":
		for i: int in 3: _button(grid, "journey", ["谷地", "寒林", "旱地"][i], "map", {"region": i})
	elif _drawer_name == "dev":
		for i: int in 5: _button(grid, "weather", ["自动", "晴", "雨", "寒风", "热浪"][i], "", {"weather": i - 1})
		for i: int in 3: _button(grid, "body", ["普通", "飞行", "大体型"][i], "person", {"flight": int(i == 1), "large": i == 2})
		_button(grid, "source", "场源", "target")
		_button(grid, "source_overlay", "场源标记", "eye")
		_button(grid, "gallery", "图鉴 F8", "book")
		_button(grid, "debug", "F12", "gear")

func _refresh_events() -> void:
	var subject: Dictionary = _target if _target.get("kind", "") == "actor" and not _target.get("memory", false) else _frame.player
	var signature: String = "%d:%d" % [int(subject.get("id", 1)), int(subject.get("events_version", 0))]
	if signature == _event_signature or not is_instance_valid(_events): return
	_event_signature = signature
	var lines := PackedStringArray()
	for event: Dictionary in subject.get("events", []): lines.append(EventText.line(event))
	_events.text = "\n".join(lines)

func _build_modal() -> void:
	add_child(_modal)
	_modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_modal.color = Color(0, 0, 0, 0.38)
	_modal.mouse_filter = Control.MOUSE_FILTER_STOP
	_modal_panel = _panel(_modal, Control.PRESET_CENTER, Vector4(-260, -190, 260, 190))
	_modal_panel.add_child(_modal_body)
	_modal.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			requested.emit("close_modal", {})
			_modal.accept_event())
	_modal.hide()

func open_stock(kind: String, target: int) -> void:
	_stock_kind = kind
	_stock_target = target
	_stock_epoch = _frame.epoch
	_modal_kind = kind
	_stock_keys = []
	_clear(_modal_body)
	var row := HBoxContainer.new()
	_modal_body.add_child(row)
	Style.label(row, "#1" if kind == "drop" else "#1 ⇄ #%d" % target).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button(row, "close_modal", "", "close")
	_stock_items = ItemList.new()
	_stock_items.custom_minimum_size.y = 112
	_stock_items.fixed_icon_size = Vector2i(24,24)
	_stock_items.item_selected.connect(func(_index: int): _refresh_stock())
	_modal_body.add_child(_stock_items)
	_stock_values = Style.label(_modal_body)
	_amount = SpinBox.new()
	_amount.min_value = 1
	_amount.max_value = 99999
	_amount.value = 1
	_modal_body.add_child(_amount)
	var amounts := HBoxContainer.new()
	_modal_body.add_child(amounts)
	for amount: String in ["1", "½", "全部"]:
		var button := Button.new()
		button.text = amount
		button.pressed.connect(func(): _amount.value = 1 if amount == "1" else (maxi(1, int(_amount.max_value) / 2) if amount == "½" else _amount.max_value))
		amounts.add_child(button)
	_accept = _button(_modal_body, "stock_commit", action_name(kind) if kind != "drop" else "丢下", kind)
	_refresh_stock()
	_modal.show()
	_amount.get_line_edit().grab_focus()

func _refresh_stock() -> void:
	if _frame.epoch != _stock_epoch: close_modal(); return
	var target: Dictionary = Actions.observed(_frame, _stock_target, true)
	var player: Dictionary = _frame.player.get("inventory", {})
	var other: Dictionary = target.get("inventory", {}) if not target.get("memory", false) else {}
	var source: Dictionary = other if _stock_kind == "take" else player
	var keys: Array = source.keys()
	keys.sort()
	if keys != _stock_keys:
		var selected: int = _stock_index()
		var previous: String = str(_stock_keys[selected]) if selected >= 0 and selected < _stock_keys.size() else ""
		_stock_keys = keys
		_stock_items.clear()
		for key: String in keys: _stock_items.add_item(str(Actions.items.get(key, {}).get("label", key)), Art.icon(Actions.art_key(key)))
		if not keys.is_empty(): _stock_items.select(keys.find(previous) if keys.has(previous) else 0)
	var index: int = _stock_index()
	var chosen: String = str(keys[index]) if index >= 0 and index < keys.size() else ""
	var available: int = int(source.get(chosen, 0))
	var destination: Dictionary = _frame.player if _stock_kind == "take" else target
	var capacity: int = int(destination.get("capacity", -1))
	if _stock_kind != "drop" and capacity >= 0:
		var used: int = 0
		for count: int in destination.get("inventory", {}).values(): used += count
		available = mini(available, maxi(0, capacity - used))
	set_text(_stock_values, "#1  %d       #%d  %s" % [int(player.get(chosen, 0)), _stock_target, str(other.get(chosen, "—"))])
	_amount.max_value = maxi(1, available)
	_accept.disabled = available <= 0 or int(_frame.player.get("hp", 0)) <= 0 or (_stock_kind != "drop" and (target.is_empty() or target.get("memory", false)))

func commit_stock() -> void:
	_amount.apply()
	var selected: int = _stock_index()
	if _accept.disabled or selected < 0: return
	requested.emit("stock_send", {"kind": _stock_kind, "target": _stock_target, "item": _stock_keys[selected], "amount": int(_amount.value), "epoch": _stock_epoch})
	close_modal()

func _stock_index() -> int:
	var selected: PackedInt32Array = _stock_items.get_selected_items()
	return selected[0] if not selected.is_empty() else -1

func open_simple(kind: String) -> void:
	_modal_kind = kind
	_clear(_modal_body)
	if kind == "pause":
		for row: Array in [["resume", "继续", "play"], ["save", "保存 F5", "save"], ["load", "读取 F9", "load"], ["settings", "设置", "gear"]]: _button(_modal_body, row[0], row[1], row[2])
	elif kind == "trade":
		var row := HBoxContainer.new()
		_modal_body.add_child(row)
		_button(row, "unused", "药物 ×1", "potion").disabled = true
		Style.label(row, "⇄")
		_button(row, "unused", "吐纳秘籍 ×1", "book").disabled = true
		_button(_modal_body, "trade_commit", "交换", "link", {"target": _selected}).disabled = int(_frame.player.get("inventory", {}).get("potion", 0)) < 1
		_button(_modal_body, "close_modal", "", "close")
	elif kind == "settings":
		Style.label(_modal_body, "UI")
		_scale_input = SpinBox.new()
		_scale_input.min_value = 50
		_scale_input.max_value = 200
		_scale_input.step = 1
		_scale_input.value = ui_percent
		_scale_input.suffix = "%"
		_modal_body.add_child(_scale_input)
		_button(_modal_body, "ui_scale_commit", "确认", "check")
		_button(_modal_body, "close_settings", "", "close")
	_modal.show()

func close_modal() -> void:
	_modal.hide()
	_modal_kind = ""
	get_viewport().gui_release_focus()

func context_menu(data: Dictionary, at: Vector2, payload: Dictionary) -> void:
	_context = payload.duplicate()
	_clear(_context_body)
	for spec: Dictionary in Actions.for_target(data, _frame.player, _help_target):
		var button: Button = _button(_context_body, spec.id, spec.text, spec.icon, payload)
		button.disabled = not spec.enabled
	_button(_context_body, "context_move", "移动 M", "move", payload)
	_context_panel.size = Vector2(220, 0)
	_context_panel.position = screen_to_ui(at).clamp(Vector2(0, 84), size - Vector2(224, 350))
	_context_panel.show()

func close_context() -> void:
	_context_panel.hide()

func blocks_world() -> bool:
	return _modal.visible or _context_panel.visible

func modal_kind() -> String:
	return _modal_kind

func close_layer() -> bool:
	if _modal.visible:
		requested.emit("close_modal", {})
		return true
	if _context_panel.visible:
		close_context()
		return true
	if not _drawer_name.is_empty():
		toggle_drawer(_drawer_name)
		return true
	return false

func reset_session() -> void:
	close_context()
	close_modal()
	set_text(_probe, "—")
	_drawer_name = ""
	_drawer_panel.hide()
	_command_signature = ""
	show_tool("")
