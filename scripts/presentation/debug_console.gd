extends CanvasLayer
## Read-only diagnostics. Works without the editor and without simulation progress.
## No live-world access, arbitrary script evaluation, or per-frame log formatting.

signal tool_requested(action: String, payload: Dictionary)
signal launcher_resized(bottom_space: float)

const RuntimeLog = preload("res://scripts/presentation/runtime_log.gd")
const Style = preload("res://scripts/presentation/ui/style.gd")
const LAUNCHER_MARGIN: float = 8.0
var journal := RuntimeLog.new()
var _provider: Callable
var _panel := PanelContainer.new()
var _launcher_panel := PanelContainer.new()
var _launcher_available: bool = false
var _dev_tools := GridContainer.new()
var _region_tools := GridContainer.new()
var _badge := Button.new()
var _status := Label.new()
var _output := RichTextLabel.new()
var _command := LineEdit.new()
var _feedback := Label.new()
var _errors_only := CheckButton.new()
var _next_refresh: int = 0
var _rendered_seq: int = -1


func _enter_tree() -> void:
	OS.add_logger(journal)


func _ready() -> void:
	layer = 100
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Microsoft YaHei UI", "Microsoft YaHei", "Noto Sans CJK SC"])
	_build_launcher()
	add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_panel.anchor_left = 0.3
	_panel.anchor_top = 0.35
	_panel.offset_left = 0
	_panel.offset_top = 0
	_panel.offset_right = -12
	_panel.offset_bottom = -12
	_panel.add_theme_font_override("font", font)
	_panel.add_theme_font_size_override("font_size", 14)
	var body := VBoxContainer.new()
	_panel.add_child(body)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_status)
	var row := HBoxContainer.new()
	body.add_child(row)
	_errors_only.text = "仅错误/警告"
	_errors_only.toggled.connect(func(_value: bool): _rendered_seq = -1)
	row.add_child(_errors_only)
	for title: String in ["导出诊断", "复制诊断", "关闭"]:
		var button := Button.new()
		button.text = title
		button.pressed.connect(_action.bind(title))
		row.add_child(button)
	_output.selection_enabled = true
	_output.scroll_following = true
	_output.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(_output)
	_feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_feedback.text = "F12/Esc关闭；help、status、decisions、errors、log、export；只查看诊断，不执行游戏脚本。"
	body.add_child(_feedback)
	_command.placeholder_text = "输入 help、status、decisions、errors、log 或 export"
	_command.text_submitted.connect(_submit)
	body.add_child(_command)
	_panel.hide()


func _build_launcher() -> void:
	add_child(_launcher_panel)
	_launcher_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	_launcher_panel.theme = Style.theme()
	_launcher_panel.add_theme_stylebox_override("panel", Style.box(Color("18251ff2"), Style.GOLD))
	var body := VBoxContainer.new()
	_launcher_panel.add_child(body)
	_dev_tools.columns = 3
	_region_tools.columns = 3
	body.add_child(_dev_tools)
	body.add_child(_region_tools)
	for i: int in 5:
		_tool_button(_dev_tools, "weather", ["自动", "晴", "雨", "寒风", "热浪"][i], "", {"weather": i - 1})
	for i: int in 3:
		_tool_button(_dev_tools, "body", ["普通", "飞行", "大体型"][i], "person", {"flight": int(i == 1), "large": i == 2})
		_tool_button(_region_tools, "journey", ["谷地", "寒林", "旱地"][i], "map", {"region": i})
	_tool_button(_dev_tools, "source", "场源", "target")
	_tool_button(_dev_tools, "source_overlay", "场源标记", "eye")
	_tool_button(_dev_tools, "action_trace", "反应追踪", "gear")
	close_tools()
	_badge.text = "F12 调试 · 错误 0 / 警告 0"
	_badge.focus_mode = Control.FOCUS_NONE
	_badge.pressed.connect(toggle)
	body.add_child(_badge)
	var row := HBoxContainer.new()
	body.add_child(row)
	_tool_button(row, "gallery", "图鉴", "book").tooltip_text = "素材图鉴 · F8"
	_tool_button(row, "dev", "DEV", "gear")
	_tool_button(row, "travel", "地区", "map")
	_launcher_panel.minimum_size_changed.connect(_fit_launcher)
	_fit_launcher()
	_launcher_panel.hide()


func _tool_button(parent: Control, action: String, title: String, icon: String, payload: Dictionary = {}) -> Button:
	var button := Button.new()
	button.text = title
	if not icon.is_empty(): button.icon = Style.icon(icon)
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.pressed.connect(func(): tool_requested.emit(action, payload))
	parent.add_child(button)
	return button


func _fit_launcher() -> void:
	var extent: Vector2 = _launcher_panel.get_combined_minimum_size()
	var margin: float = LAUNCHER_MARGIN * _launcher_panel.scale.x
	_launcher_panel.offset_left = -margin - extent.x
	_launcher_panel.offset_top = -margin - extent.y
	_launcher_panel.offset_right = -margin
	_launcher_panel.offset_bottom = -margin
	_launcher_panel.pivot_offset = extent
	launcher_resized.emit(extent.y + LAUNCHER_MARGIN)


func toggle_tools(kind: String) -> void:
	_dev_tools.visible = kind == "dev" and not _dev_tools.visible
	_region_tools.visible = kind == "travel" and not _region_tools.visible


func close_tools() -> bool:
	var was_open: bool = _dev_tools.visible or _region_tools.visible
	_dev_tools.hide()
	_region_tools.hide()
	return was_open


func set_launcher_available(value: bool) -> void:
	_launcher_available = value
	_launcher_panel.visible = value and not is_open()
	if not value: close_tools()


func attach(provider: Callable) -> void:
	_provider = provider

func set_ui_scale(factor: float) -> void:
	_launcher_panel.scale = Vector2.ONE * factor
	_fit_launcher()


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	_launcher_panel.visible = _launcher_available and not _panel.visible
	if _panel.visible:
		close_tools()
		_next_refresh = 0
		_command.grab_focus()
	else:
		_command.release_focus()


func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_F12 or (event.keycode == KEY_ESCAPE and is_open()):
			toggle()
			get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	if now < _next_refresh:
		return
	_next_refresh = now + 250
	var counts: Dictionary = journal.summary()
	var caption: String = "F12 调试 · 错误 %d / 警告 %d" % [counts.errors, counts.warnings]
	if _badge.text != caption: _badge.text = caption
	_badge.modulate = Color(1.0, 0.45, 0.4) if counts.errors > 0 else Color.WHITE
	if not is_open():
		return
	var data: Dictionary = _session()
	var player: Dictionary = data.get("player", {})
	var mailbox: Dictionary = data.get("mailbox", {})
	_status.text = "世界 %sms | 暂停 %s | 快照年龄 %.1fms | 序号 %s\n玩家#1 HP %s | mode %s | 位置 %s | 行动 %s\n模拟线程 %s | 指令在途 %s / 待受理 %s | 最近结果 %s\n鼠标下UI %s | 焦点 %s | 日志保留最近 %d 条" % [
		data.get("world_ms", "?"), data.get("paused", "?"), float(data.get("frame_age_ms", 0)), data.get("sequence", "?"),
		player.get("hp", "?"), player.get("mode", "?"), player.get("position", "?"), player.get("action", {}),
		mailbox.get("thread_alive", "?"), mailbox.get("pending", "?"), mailbox.get("queued", "?"), data.get("last_result", ""),
		data.get("hovered_control", ""), data.get("focused_control", ""), counts.retained]
	if _rendered_seq != counts.sequence:
		var lines := PackedStringArray()
		for entry: Dictionary in journal.snapshot():
			if _errors_only.button_pressed and entry.level == "info":
				continue
			lines.append("[%dms %s T%d] %s" % [entry.real_ms, entry.level, entry.thread, entry.text])
		_output.text = "\n".join(lines.slice(-120))
		_rendered_seq = counts.sequence


func _session() -> Dictionary:
	return _provider.call() if _provider.is_valid() else {"state": "场景未连接"}


func _snapshot() -> Dictionary:
	return {"captured_at": Time.get_datetime_string_from_system(), "session": _session(),
		"log_summary": journal.summary(), "logs": journal.snapshot()}


func export_report() -> String:
	var directory: String = "user://diagnostics"
	var error: Error = DirAccess.make_dir_recursive_absolute(directory)
	if error != OK:
		_feedback.text = "创建诊断目录失败: %s" % error_string(error)
		return ""
	var path: String = "%s/reol-%s-%d.json" % [directory, Time.get_datetime_string_from_system().replace(":", "-"), Time.get_ticks_usec()]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_feedback.text = "写入诊断失败: %s" % error_string(FileAccess.get_open_error())
		return ""
	file.store_string(JSON.stringify(_snapshot(), "\t"))
	file.flush()
	var written: Error = file.get_error()
	file.close()
	if written != OK:
		_feedback.text = "写入诊断失败: %s" % error_string(written)
		return ""
	_feedback.text = "已导出: " + ProjectSettings.globalize_path(path)
	print("DIAGNOSTIC_REPORT ", ProjectSettings.globalize_path(path))
	return path


func _action(title: String) -> void:
	match title:
		"导出诊断": export_report()
		"复制诊断":
			DisplayServer.clipboard_set(JSON.stringify(_snapshot(), "\t"))
			_feedback.text = "诊断已复制"
		"关闭": toggle()


func _submit(text: String) -> void:
	_command.clear()
	match text.strip_edges().to_lower():
		"help": _feedback.text = "status 查看最新状态；actions 查看DEV反应追踪；decisions 查看单位决策；errors 仅错误/警告；log 全部记录；export 导出JSON。"
		"decisions":
			var snapshot: Dictionary = _session()
			_output.text = JSON.stringify({"recent": snapshot.get("decision_trace", []), "selected": snapshot.get("inspected", {}).get("decision", {}), "selected_agency": snapshot.get("inspected", {}).get("agency", {}), "player": snapshot.get("player", {}).get("decision", {}), "player_agency": snapshot.get("player", {}).get("agency", {})}, "\t")
			_feedback.text = "最近选择、个人目的与当前任务；诊断信息不进入单位认识。"
			_rendered_seq = journal.summary().sequence
		"actions":
			_output.text = JSON.stringify(_session().get("action_trace", []), "\t")
			_rendered_seq = journal.summary().sequence
		"status": _feedback.text = JSON.stringify(_snapshot().session)
		"errors", "log":
			_errors_only.button_pressed = text.strip_edges().to_lower() == "errors"
			_rendered_seq = -1
		"export": export_report()
		_: _feedback.text = "未知命令；输入 help 查看可用命令。"
	_next_refresh = 0


func _exit_tree() -> void:
	OS.remove_logger(journal)
