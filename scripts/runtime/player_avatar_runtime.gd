class_name PlayerAvatarRuntime
extends Node2D
## Player perspective and input adapter. Choosing a life never copies its body.
## Opening selection exists once at time zero; loading always locks the choice.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var opening: Control
var _bird_status: PanelContainer
var _bird_actions: PanelContainer
var _name_line: Label
var _needs_line: Label
var _activity_line: Label
var _notice: Label
var _opening_notice: Label
var soul: SoulPlayerRuntime
var _owner: WeakRef
var _main: WeakRef


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(main: Node2D, adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	_main = weakref(main)
	process_mode = Node.PROCESS_MODE_ALWAYS
	adapter.avatar_adapter = self
	_build_ui()
	soul = SoulPlayerRuntime.new()
	soul.name = "SoulPlayerRuntime"
	add_child(soul)
	soul.setup(main, adapter)
	adapter.avatar_changed.connect(_on_avatar_changed)
	adapter.save_finished.connect(_on_save_finished)
	GameClock.time_advanced.connect(_on_time_advanced)
	adapter._opening_selection_available = GameClock.elapsed_ms == 0
	opening.visible = adapter._opening_selection_available
	if opening.visible:
		GameClock.set_paused(true)
	_apply_binding()


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	screen.theme = UI.create()
	layer.add_child(screen)
	_bird_status = PanelContainer.new()
	_bird_status.add_theme_stylebox_override("panel", UI.panel(UI.JADE))
	screen.add_child(_bird_status)
	_bird_status.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	_bird_status.offset_left = -314
	_bird_status.offset_right = -16
	_bird_status.offset_top = 14
	var status := VBoxContainer.new()
	_bird_status.add_child(status)
	_name_line = UI.label(status, "你 · 雀妖", UI.GOLD, 20)
	_needs_line = UI.label(status, "", UI.PAPER, 16)
	_needs_line.custom_minimum_size = Vector2(270, 48)
	_activity_line = UI.label(status, "", UI.JADE, 14)
	_activity_line.custom_minimum_size = Vector2(270, 42)
	_bird_actions = PanelContainer.new()
	_bird_actions.add_theme_stylebox_override("panel", UI.panel(UI.JADE))
	screen.add_child(_bird_actions)
	_bird_actions.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	_bird_actions.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_bird_actions.offset_left = 16
	_bird_actions.offset_right = 362
	_bird_actions.offset_top = -286
	_bird_actions.offset_bottom = -16
	var actions := VBoxContainer.new()
	_bird_actions.add_child(actions)
	UI.label(actions, "一羽之身，也有自己的天地", UI.GOLD, 18)
	UI.label(actions, "WASD 振翅 · F 落地 · T 等候\n靠近草籽、树巢和石隙，记住所见。", UI.MUTED, 14)
	var grid := GridContainer.new()
	grid.columns = 2
	actions.add_child(grid)
	for row: Array in [["forage", "啄食 · E"], ["rest", "歇翅 · R"], ["pickup", "衔药 · Q"], ["drop", "放入药圃 · G"], ["land", "就地落脚 · F"], ["cancel", "停下当前行动"]]:
		UI.button(grid, str(row[1]), submit.bind(str(row[0])))
	_notice = UI.label(actions, "探索、觅食和歇翅都能自己选择。", UI.WARNING, 14)
	_notice.custom_minimum_size = Vector2(318, 42)
	var storage := HBoxContainer.new()
	actions.add_child(storage)
	UI.button(storage, "保存 · F5", _save)
	UI.button(storage, "读取 · F9", _load)
	opening = ColorRect.new()
	(opening as ColorRect).color = Color(0.035, 0.065, 0.07, 0.95)
	screen.add_child(opening)
	opening.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	opening.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	panel.offset_left = -275
	panel.offset_right = 275
	panel.offset_top = -174
	panel.offset_bottom = 174
	var column := VBoxContainer.new()
	panel.add_child(column)
	UI.label(column, "REOL / 众生各有其道", UI.GOLD, 26)
	UI.label(column, "从一段生活开始", UI.PAPER, 20)
	UI.label(column, "同一个世界照常运转。选择这段人生的身体，\n从它能看见、能做到的事情开始。", UI.MUTED, 16)
	UI.button(column, "山门杂役 · 劳作、来往与修行", choose.bind("subject:player"))
	UI.button(column, "山间雀妖 · 振翅、觅食与衔药", choose.bind("subject:avian:moss_sparrow"))
	UI.button(column, "戒中残识 · 传意、协商与相助", choose.bind("subject:soul:yan_heng"))
	UI.button(column, "接续已有近况", _load)
	_opening_notice = UI.label(column, "", UI.WARNING, 14)
	UI.label(column, "进入世界后不能从这里免费换身。", UI.MUTED, 13)


func choose(subject: String) -> bool:
	var adapter: WorldContinuityRuntime = runtime()
	if not opening.visible or not adapter.select_starting_avatar(subject):
		return false
	var main: Node2D = _main.get_ref()
	if not adapter.human_player_active():
		main.fog.restore_exploration(FogOfWar.empty_exploration(), adapter.controlled_cell())
	GameClock.set_paused(false)
	return true


func _on_avatar_changed() -> void:
	opening.hide()
	_apply_binding()
	_notice.text = "已接续这段人生，身体与世界没有重置。"


func _apply_binding() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	var main: Node2D = _main.get_ref()
	var bird: bool = adapter.bird_player_active()
	var spirit: bool = adapter.soul_player_active()
	var human: bool = adapter.human_player_active()
	main.player.avatar_active = human and not opening.visible
	main.player._intent = Vector2.ZERO
	main.player.set_selected(human)
	main.player.motion.velocity = main.player.motion.velocity if human else Vector2.ZERO
	main.hud.set_bird_avatar(not human)
	if spirit:
		main.hud.set_soul_avatar()
	soul.set_active(spirit)
	_bird_status.visible = bird
	_bird_actions.visible = bird
	var fighting: bool = not adapter.world_sim.conflicts.conflict_for("player").is_empty()
	adapter.set_life_panels_available(human and not fighting)
	if not human:
		main.camera.follow_focus = true
		main.camera.set_focus_target(self)
		main.camera.global_position = adapter.world_sim.soul_vessels.agency.point(adapter.soul_avatar_id()) if spirit else SimAvianLife.point(adapter.world_sim.avian_life.birds[adapter.bird_avatar_id()])
		adapter.object_adapter.panel.hide()
		if adapter.spirit_adapter != null:
			adapter.spirit_adapter.reset_observation()
		adapter.soul_adapter.reset_observation()
		adapter.sparring_adapter.panel.hide()
		adapter.avian_adapter.panel.hide()
	else:
		main.camera.follow_focus = true
		main.camera.set_focus_target(main.player)
		main.fog.set_observer(0, FogOfWar.VISION_RADIUS)
	_project()


func submit(verb: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if not adapter.bird_player_active() or opening.visible:
		return SimAvianLife.response(false, "先开始这段雀身的生活。")
	var domain: SimAvianLife = adapter.world_sim.avian_life
	var result: Dictionary
	if verb == "cancel":
		result = adapter.request_player_command("cancel")
		if result.ok and not result.queued:
			result.line = "停下动作，嘴中的实物保留。"
	elif verb == "land":
		result = domain.command_land(adapter.bird_avatar_id())
	else:
		result = domain.command_activity(adapter.bird_avatar_id(), verb)
	_notice.text = str(result.line)
	_project()
	return result


func _project() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.human_player_active():
		return
	if adapter.world_sim.settlement != null and adapter.world_sim.settlement.is_pending():
		return
	if adapter.soul_player_active():
		global_position = adapter.world_sim.soul_vessels.agency.point(adapter.soul_avatar_id())
		soul.project()
		return
	var main: Node2D = _main.get_ref()
	var domain: SimAvianLife = adapter.world_sim.avian_life
	var id: String = adapter.bird_avatar_id()
	var body: Dictionary = domain.birds[id]
	global_position = SimAvianLife.point(body)
	main.fog.set_observer(int(body.altitude), int(domain.rules().observation_cells))
	main.fog.set_focus(domain.body_cell(id))
	main.world.set_focus(domain.body_cell(id))
	_name_line.text = "你 · " + str(body.label) + (" · 振翅" if int(body.altitude) > 0 else " · 落脚")
	var hungry: bool = int(body.fullness) < int(domain.rules().eat_below) * SimAvianLife.SCALE
	var tired: bool = int(body.energy) < int(domain.rules().rest_below) * SimAvianLife.SCALE
	_needs_line.text = ("腹中有些空了" if hungry else "肚里还暖") + " · " + ("双翅渐乏" if tired else "羽翼有力")
	_needs_line.text += "\n" + ("嘴中衔着一枝药" if domain.inventory.quantity("bird:" + id, "herb") > 0 else "嘴中没有衔物")
	_activity_line.text = str(body.goal)
	if not body.active.is_empty():
		_activity_line.text += "\n还需约%d秒" % ceili(float(int(body.active.due_ms) - GameClock.elapsed_ms) / 1000.0)
	main.player.visible = adapter.world_sim.regions.home.actor_is_alive("player") and main.fog.is_cell_visible(main.player.cell)
	adapter._panel.hide()
	adapter.service_adapter.panel.hide()


func _save() -> void:
	var result: Error = runtime().request_save(VillageRuntime.SAVE_PATH)
	_notice.text = "正在完成当前结算，随后保存……" if result == OK else "未能受理保存：" + error_string(result)


func _on_save_finished(path: String, result: Error) -> void:
	if path == runtime().save_path:
		_notice.text = "近况已记下。" if result == OK else "保存失败：" + error_string(result)


func _load() -> void:
	var result: Error = runtime().load_game(VillageRuntime.SAVE_PATH)
	_notice.text = "已接续保存的身体和世界。" if result == OK else "还没有可接续的近况。"
	_opening_notice.text = "" if result == OK else "未能读取近况；可选择新人生，或检查保存文件。"


func _on_time_advanced(_from: int, _to: int) -> void:
	_project()


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().bird_player_active() or opening.visible or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode in [KEY_F5, KEY_F9]:
		if event.keycode == KEY_F5:
			_save()
		else:
			_load()
		get_viewport().set_input_as_handled()
		return
	var verb: String = {KEY_E: "forage", KEY_R: "rest", KEY_Q: "pickup", KEY_G: "drop", KEY_F: "land"}.get(event.keycode, "")
	if not verb.is_empty():
		submit(verb)
		get_viewport().set_input_as_handled()
