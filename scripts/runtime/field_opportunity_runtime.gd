class_name FieldOpportunityRuntime
extends CommittedWorldCanvas
## Personal field notes and actual scenery. Destinations, bodies and objects
## remain with their original authorities; this view never generates a reward.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
var panel: PanelContainer
var site_choice: OptionButton
var entry: Button
var _details: Label
var _notice: Label
var _travel: Button
var _observe: Button
var _object: Button
var _owner: WeakRef


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	z_index = 7
	var layer := CanvasLayer.new()
	layer.layer = 7
	add_child(layer)
	var screen := Control.new()
	layer.add_child(screen)
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	entry = UI.button(screen, "野外见闻 · L", show_panel)
	entry.theme = UI.create()
	entry.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
	entry.offset_left = -364
	entry.offset_right = -16
	entry.offset_top = -338
	entry.offset_bottom = -304
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -280
	panel.offset_right = 280
	panel.offset_top = 140
	var column := VBoxContainer.new()
	panel.add_child(column)
	UI.label(column, "野外见闻 · 原路去，亲眼看", UI.GOLD, 20)
	UI.label(column, "只记本人得知的去处；旧线索不保证宝物还在，也不会告诉你远处谁已取走。", UI.MUTED, 13)
	site_choice = OptionButton.new()
	site_choice.custom_minimum_size = Vector2(520, 34)
	column.add_child(site_choice)
	site_choice.item_selected.connect(func(_index: int) -> void: refresh())
	_details = UI.label(column, "", UI.PAPER, 14)
	_details.custom_minimum_size = Vector2(520, 115)
	_notice = UI.label(column, "", UI.WARNING, 14)
	_notice.custom_minimum_size = Vector2(520, 45)
	var actions := HBoxContainer.new()
	column.add_child(actions)
	_travel = UI.button(actions, "沿路前往", travel_selected)
	_observe = UI.button(actions, "看清此处", observe_selected)
	_object = UI.button(column, "查看眼前器物", inspect_visible_object)
	UI.button(column, "向眼前的人打听去处 · C", ask_selected)
	UI.button(column, "收起 · L / Esc", panel.hide)
	panel.hide()
	GameClock.time_advanced.connect(_on_advanced)
	adapter.avatar_changed.connect(reset_observation)
	refresh()


func known_sites() -> Array[Dictionary]:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return []
	return adapter.world_sim.field_opportunities.known_sites("player")


func selected_site() -> String:
	return str(site_choice.get_selected_metadata()) if site_choice.item_count > 0 else ""


func show_panel() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return
	adapter.interaction_adapter.panel.hide()
	adapter.object_adapter.panel.hide()
	adapter.conflict_adapter.panel.hide()
	adapter.capability_adapter.panel.hide()
	adapter.spirit_adapter.panel.hide()
	adapter.sparring_adapter.panel.hide()
	panel.show()
	refresh()
	site_choice.grab_focus()


func travel_selected() -> bool:
	var id: String = selected_site()
	var accepted: bool = not id.is_empty() and runtime().travel_to_site(id)
	_notice.text = "沿着本人记得的去路出发；WASD可以中断。" if accepted else "眼下还不能安排这段行旅。"
	if accepted:
		panel.hide()
	return accepted


func observe_selected() -> Dictionary:
	var id: String = selected_site()
	if id.is_empty():
		return {"ok": false, "code": "unheard", "line": "先有本人认识的去处，再到场查看。"}
	var answer: Dictionary = runtime().world_sim.field_opportunities.observe_site("player", id)
	_notice.text = str(answer.get("line", "眼下没有看清新的情形。"))
	refresh()
	return answer


func ask_selected() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	panel.hide()
	var interaction: InteractionRequestsRuntime = adapter.interaction_adapter
	interaction.show_panel()
	for index: int in interaction.verb_choice.item_count:
		if interaction.verb_choice.get_item_metadata(index) == "field_clue":
			interaction.verb_choice.select(index)
			break
	var selected: String = adapter._selected_remote if not adapter._selected_remote.is_empty() else adapter.home_runtime()._selected_actor
	var subject: String = adapter.world_sim.embodiment.subject_for_actor(selected)
	for index: int in interaction.receiver_choice.item_count:
		if interaction.receiver_choice.get_item_metadata(index) == subject:
			interaction.receiver_choice.select(index)
			break
	interaction._on_verb_changed(interaction.verb_choice.selected)


func _visible_object() -> String:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return ""
	var domain: RefCounted = adapter.world_sim.field_opportunities
	var id: String = str(domain.definitions.site.object)
	if not adapter.world_sim.artifacts.objects.has(id) or not adapter.world_sim.artifacts.can_see("player", id):
		return ""
	var cell: Vector2i = adapter.world_sim.artifacts.object_cell(id)
	var origin: Vector2 = SimRouteTravel.point(adapter.world_sim.regions.home.synchronize_actors().player)
	var point: Vector2 = TileGrid.cell_to_world(cell)
	var item: Dictionary = adapter.world_sim.artifacts.objects[id]
	if str(item.container).begins_with("actor:") and adapter.world_sim.regions[item.region].has_actor(str(item.container).trim_prefix("actor:")):
		point = SimRouteTravel.point(adapter.world_sim.regions[item.region].synchronize_actors()[str(item.container).trim_prefix("actor:")])
	if Space.level(adapter.world_sim, origin) != Space.level(adapter.world_sim, point) or not Space.clear_segment(adapter.world_sim, origin, point, Space.level(adapter.world_sim, origin)):
		return ""
	return id if adapter.home_runtime()._fog == null or adapter.home_runtime()._fog.is_cell_visible(cell) else ""


func inspect_visible_object() -> bool:
	var id: String = _visible_object()
	if id.is_empty():
		return false
	panel.hide()
	return runtime().object_adapter.select_object(id)


func _scene_line() -> String:
	var adapter: WorldContinuityRuntime = runtime()
	var id: String = _visible_object()
	if id.is_empty():
		return "眼前未见可辨的遗迹器物；旧闻不能替你查看远处的情形。"
	var artifacts: SimArtifacts = adapter.world_sim.artifacts
	var view: Dictionary = artifacts.describe("player", id)
	var item: Dictionary = artifacts.objects[id]
	if str(item.container).begins_with("actor:"):
		var holder: String = str(item.container).trim_prefix("actor:")
		if holder == "player":
			return "本人正实际保管着：" + str(view.label)
		var pawn: Pawn = adapter.actor_view(holder)
		var region_id: String = adapter.actor_region(holder)
		if not region_id.is_empty() and is_instance_valid(pawn) and pawn.visible:
			var name_value: String = pawn.display_name_override if not pawn.display_name_override.is_empty() else adapter.world_sim.regions[region_id]._name(holder)
			return "你亲眼看见%s随身带着%s。胜负不会自动改变这件实物的归处。" % [name_value, str(view.label)]
	return "你眼前可见：%s。可到近处查看或尝试实际取用。" % str(view.label)


func reset_observation() -> void:
	if not can_refresh_canvas():
		return
	clear_committed_canvas()
	panel.hide()
	_notice.text = ""
	refresh()


func refresh() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or panel == null:
		return
	if not can_refresh_canvas():
		return
	entry.visible = adapter.human_player_active() and adapter.home_runtime()._player.avatar_active
	if not adapter.human_player_active():
		panel.hide()
	if not panel.visible:
		redraw_committed_canvas()
		return
	var old: String = selected_site()
	site_choice.clear()
	for site: Dictionary in known_sites():
		site_choice.add_item(str(site.label))
		site_choice.set_item_metadata(site_choice.item_count - 1, str(site.id))
		if str(site.id) == old:
			site_choice.select(site_choice.item_count - 1)
	var id: String = selected_site()
	_travel.disabled = id.is_empty()
	_observe.disabled = id.is_empty()
	_object.disabled = _visible_object().is_empty()
	_details.text = ("本人记得这处去路。到达后亲眼查看，才能知道那里现在是什么情形。\n\n" if not id.is_empty() else "尚未听到明确的野外去处；可向实际在眼前的人询问，或者亲自行走探查。\n\n") + _scene_line()
	redraw_committed_canvas()


func _on_advanced(_from: int, _to: int) -> void:
	refresh()


func _input(event: InputEvent) -> void:
	# Existing C/I/U adapters retain their own key handling. The higher field
	# layer must get out of their way before those ordinary handlers run.
	if panel.visible and event is InputEventKey and event.pressed and not event.echo and event.keycode in [KEY_C, KEY_I, KEY_U, KEY_K]:
		panel.hide()


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().human_player_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_L:
		if panel.visible:
			panel.hide()
		else:
			show_panel()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and panel.visible:
		panel.hide()
		get_viewport().set_input_as_handled()


func _build_canvas() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return
	var visible_sites: Dictionary = {}
	for site: Dictionary in adapter.world_sim.field_opportunities.nearby_visible_sites("player"):
		visible_sites[str(site.id)] = site
	var sites: Dictionary = visible_sites.duplicate()
	for site: Dictionary in known_sites():
		if not sites.has(str(site.id)):
			sites[str(site.id)] = site
	for site: Dictionary in sites.values():
		var cell: Vector2i = SimRouteTravel.cell(site.cell)
		var fog: FogOfWar = adapter.home_runtime()._fog
		if fog != null and not fog.is_explored(cell):
			continue
		var point: Vector2 = TileGrid.cell_to_world(cell) - Vector2(0, adapter.world_sim.map_data.get_elevation(cell) * ReolWorld.ELEVATION_PX)
		var currently_visible: bool = visible_sites.has(str(site.id)) and (fog == null or fog.is_cell_visible(cell))
		var color: Color = UI.GOLD if currently_visible else UI.MUTED.darkened(0.35)
		_draw_stele(point, color)
		capture_text_outline(ThemeDB.fallback_font, point + Vector2(-72, -44), str(site.label), HORIZONTAL_ALIGNMENT_CENTER, 144, 14, 4, UI.INK)
		capture_text(ThemeDB.fallback_font, point + Vector2(-72, -44), str(site.label), HORIZONTAL_ALIGNMENT_CENTER, 144, 14, color)


func _draw_stele(point: Vector2, color: Color) -> void:
	capture_rect(Rect2(point + Vector2(-22, -7), Vector2(44, 14)), UI.INK)
	capture_polygon(PackedVector2Array([point + Vector2(-13, 0), point + Vector2(-13, -31), point + Vector2(-1, -37), point + Vector2(4, -22), point + Vector2(13, -28), point + Vector2(13, 0)]), color.darkened(0.6))
	capture_line(point + Vector2(-7, -26), point + Vector2(-2, -20), color, 2)
	capture_line(point + Vector2(-2, -17), point + Vector2(5, -13), color, 2)
	capture_line(point + Vector2(-6, -10), point + Vector2(4, -7), color, 2)
