extends CanvasLayer
## Read-only diagnostics. Works without the editor and without simulation progress.
## No live-world access, arbitrary script evaluation, or per-frame log formatting.

const RuntimeLog = preload("res://scripts/presentation/runtime_log.gd")
var journal := RuntimeLog.new()
var _provider: Callable
var _panel := PanelContainer.new()
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
	add_child(_badge)
	_badge.text = "F12 调试"
	_badge.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_badge.offset_left = -230
	_badge.offset_right = -12
	_badge.offset_top = 12
	_badge.offset_bottom = 44
	_badge.add_theme_font_override("font", font)
	_badge.focus_mode = Control.FOCUS_NONE
	_badge.pressed.connect(toggle)
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
	_feedback.text = "F12/Esc关闭；help、status、errors、log、export；只查看诊断，不执行游戏脚本。"
	body.add_child(_feedback)
	_command.placeholder_text = "输入 help、status、errors、log 或 export"
	_command.text_submitted.connect(_submit)
	body.add_child(_command)
	_panel.hide()


func attach(provider: Callable) -> void:
	_provider = provider


func is_open() -> bool:
	return _panel.visible


func toggle() -> void:
	_panel.visible = not _panel.visible
	if _panel.visible:
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
	_badge.text = "F12 调试 · 错误 %d / 警告 %d" % [counts.errors, counts.warnings]
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
		"help": _feedback.text = "status 查看最新状态；errors 仅错误/警告；log 全部记录；export 导出JSON。"
		"status": _feedback.text = JSON.stringify(_snapshot().session)
		"errors", "log":
			_errors_only.button_pressed = text.strip_edges().to_lower() == "errors"
			_rendered_seq = -1
		"export": export_report()
		_: _feedback.text = "未知命令；输入 help 查看可用命令。"
	_next_refresh = 0


func _exit_tree() -> void:
	OS.remove_logger(journal)
