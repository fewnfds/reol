extends "res://tests/production_ui_smoke.gd"
## Native input against the normal hundred-resident opening; files are test-only.
var panel: PanelContainer

func capture(name_key: String) -> void:
	var directory: String = "res://logs/department-ui/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(directory + name_key + ".png")

func controls(node: Node, type_name: String) -> Array:
	var found: Array = []
	for child: Node in node.get_children():
		if child.is_class(type_name): found.append(child)
		found.append_array(controls(child, type_name))
	return found

func named_button(node: Node, text: String) -> Button:
	for value: Button in controls(node, "Button"):
		if value.text == text: return value
	return null

func edit(placeholder: String) -> LineEdit:
	for value: LineEdit in controls(panel._content, "LineEdit"):
		if value.placeholder_text == placeholder: return value
	return null

func press(text: String, node: Node = null) -> void:
	var value: Button = named_button(panel._content if node == null else node, text)
	check(value != null and not value.disabled, "Workspace button unavailable: " + text)
	if value == null or value.disabled: return
	await RenderingServer.frame_post_draw
	panel._content.get_parent().ensure_control_visible(value)
	await RenderingServer.frame_post_draw
	await process_frame
	await click(value)

func tab(index: int) -> void:
	var point: Vector2 = panel._tabs.get_global_transform_with_canvas() * panel._tabs.get_tab_rect(index).get_center()
	await mouse(MOUSE_BUTTON_LEFT, true, point); await mouse(MOUSE_BUTTON_LEFT, false, point)
	check(panel._tabs.current_tab == index, "Workspace tab inaccessible: " + str(index))
	await process_frame; await process_frame

func choose_option(value: OptionButton, index: int) -> void:
	await click(value)
	check(value.get_popup().visible, "Workspace option popup did not open")
	value.get_popup().set_focused_item(index)
	await key(KEY_ENTER, true); await key(KEY_ENTER, false)

func _run() -> void:
	game = Game.new()
	game.controls.bindings.config_path = "user://department-ui-controls.cfg"
	game.feedback.config_path = "user://department-ui-feedback.cfg"
	game.paused = true; game.runner.control(true, 1)
	root.add_child(game); current_scene = game; root.grab_focus()
	check(await until(func(): return game.frame != null, 8000), "Department normal opening absent")
	if game.frame == null: game.queue_free(); quit(1); return
	panel = game.ui.work_panel
	var open_button: Button = named_button(game.ui, "职责")
	check(open_button != null, "HUD workspace entry missing")
	if open_button != null: await click(open_button)
	check(await until(func(): return panel.visible and not panel._view.is_empty()), "Workspace did not subscribe")
	var kitchen_index: int = -1
	for index: int in panel._departments.item_count:
		if panel._departments.get_item_text(index).ends_with("膳堂"): kitchen_index = index; break
	check(kitchen_index >= 0, "Normal opening lacks managed kitchen")
	if kitchen_index >= 0: await choose_option(panel._departments, kitchen_index)
	check(await until(func(): return panel._view.get("title", "").ends_with("膳堂")), "Workspace did not switch department")
	check(game.frame.ids.size() == 100 and game.frame.player.action.is_empty(), "UI opened a fixture or started a world action")
	await capture("normal-overview")
	await tab(3)
	check(await until(func(): return named_button(panel._content, "下达目标") != null), "Production form absent")
	var before_orders: int = panel._view.get("orders", []).size()
	var amount: SpinBox = controls(named_button(panel._content, "下达目标").get_parent(), "SpinBox")[0]
	amount.value = 6
	await press("下达目标")
	check(await until(func(): return panel._view.get("orders", []).size() == before_orders + 1), "Native target command did not reach canonical owner")
	var new_order: int = 0
	for order: Dictionary in panel._view.orders: new_order = maxi(new_order, int(order.id))
	var bind: Button = named_button(panel._content, "绑定")
	var choice: OptionButton = controls(bind.get_parent(), "OptionButton")[0]
	for index: int in choice.item_count:
		if choice.get_item_id(index) == new_order: await choose_option(choice, index); break
	await press("绑定")
	check(await until(func(): return panel._view.get("production", {}).values().any(func(c: Dictionary): return c.order == new_order)), "Native table binding not applied")
	await capture("production")
	await tab(4)
	check(await until(func(): return edit("物品名称，如谷物") != null), "Supply form absent")
	var input: LineEdit = edit("物品名称，如谷物")
	input.text = "谷物"
	check(panel.item_key(input.text) == "grain" and panel.item_key("  grain  ") == "grain", "Named material selection did not resolve to its actual definition")
	for id: String in panel.Items.load_definitions():
		if panel.Items.spec(id).has("slot"):
			var graded: String = panel.Items.key_for(id, 2)
			check(panel.item_key(panel.item_name(graded)) == graded, "Storage form renamed a quality variant into its base item")
			break
	panel._content.get_parent().ensure_control_visible(input)
	await process_frame; await process_frame
	input.grab_focus(); input.caret_column = 1
	var form_id: int = input.get_instance_id()
	# Request publication changes live rows, not the edit form or its caret.
	var target: int = int(panel._view.facilities[0].id)
	game.runner.send({"kind": "management", "department": panel.department, "op": "request_supply", "supplier": panel._view.supplier, "target": target, "item": "water", "amount": 1})
	check(await until(func(): return panel._view.get("supply_requests", []).any(func(r: Dictionary): return r.item == "water")), "Live request did not publish")
	check(is_instance_valid(input) and input.get_instance_id() == form_id and input.has_focus() and input.text == "谷物" and input.caret_column == 1, "Live supply refresh destroyed the edited form or focus")
	await capture("supply-edit-focus")
	input.release_focus()
	await tab(5)
	check(await until(func(): return not panel._view.get("candidates", []).is_empty()), "Authority candidates not published on demand")
	var title: LineEdit = edit("自定义身份名称")
	title.text = "试验厨房协理"
	var grant_button: Button = named_button(panel._content, "更新所选人的授权")
	# The candidate selector is the only OptionButton directly in the content.
	var worker: OptionButton
	for child: Node in panel._content.get_children():
		if child is OptionButton: worker = child; break
	var worker_index: int = -1
	for index: int in worker.item_count:
		if worker.get_item_id(index) == 2: worker_index = index; break
	check(worker_index >= 0, "Authority form was built from an earlier page's snapshot")
	panel._content.get_parent().ensure_control_visible(worker)
	await process_frame; await process_frame
	if worker_index >= 0: await choose_option(worker, worker_index)
	for toggle: CheckButton in controls(panel._content, "CheckButton"):
		if toggle.text == "查阅": toggle.button_pressed = true
	await press(grant_button.text)
	check(await until(func(): return panel._view.get("grants", {}).get(2, {}).get("title") == "试验厨房协理"), "Custom title and capability grant did not apply")
	root.size = Vector2i(1280, 720); game.ui.apply_scale(125, false)
	await process_frame; await process_frame
	var bounds: Rect2 = panel.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, panel.size)
	check(bounds.position.x >= -1 and bounds.position.y >= -1 and bounds.end.x <= root.size.x + 1 and bounds.end.y <= root.size.y + 1, "Scaled workspace escaped viewport")
	await capture("custom-authority-125")
	check(game.frame.player.action.is_empty() and game.frame.combat.is_empty(), "Panel mouse input leaked into physical world actions")
	await key(KEY_ESCAPE, true); await key(KEY_ESCAPE, false)
	check(not panel.visible and not game.ui._modal.visible, "Escape did not close only the workspace")
	game.controls.action("work_panel", {})
	check(await until(func(): return panel.visible and not panel._view.is_empty()), "Workspace failed to reopen")
	var path: String = "user://department-ui-session.reol"
	var sequence: int = game.runner.send({"kind": "save", "path": path})
	check(await until(func(): return game._last_receipt.contains("save #%d " % sequence) and game._last_receipt.ends_with(": saved"), 4000), "Workspace actual save failed")
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch, 5000), "Workspace actual reload failed")
	check(not panel.visible, "Old workspace remained actionable across epoch change")
	game.controls.action("work_panel", {})
	check(await until(func(): return panel.visible and panel._view.get("grants", {}).get(2, {}).get("title") == "试验厨房协理"), "Restored workspace lost management state")
	await capture("restored")
	# Load an employee variant of this same normal opening, no developer gifts.
	var loaded: Dictionary = FileAccess.open(path, FileAccess.READ).get_var(false)
	for d: Dictionary in loaded.state.domains.institutions.departments.values():
		d.grants.erase(1)
		if d.title.ends_with("膳堂"): d.workers[1] = {"duties": ["produce"], "groups": [], "department_wide": true}
	var file := FileAccess.open(path, FileAccess.WRITE); file.store_var(loaded, false); file.close()
	epoch = game.frame.epoch; game.runner.send({"kind": "load", "path": path})
	check(await until(func(): return game.frame.epoch > epoch, 5000), "Employee normal save variant did not load")
	game.controls.action("work_panel", {})
	check(await until(func(): return panel.visible and panel._view.get("capabilities", ["pending"]).is_empty()), "Ordinary employee gained management rights")
	await tab(0)
	check(await until(func(): return panel._my_list != null and panel._view.get("workers", []).size() == 1), "Employee cannot read their own assignment")
	await tab(2)
	check(named_button(panel._content, "应用仓储规则") == null and named_button(panel._content, "纳管") == null, "Employee retained editable management controls")
	await capture("employee")
	game.queue_free(); await process_frame; await process_frame
	for cleanup: String in [path, path + ".bak", path + ".tmp", "user://department-ui-controls.cfg", "user://department-ui-feedback.cfg"]:
		if FileAccess.file_exists(cleanup): DirAccess.remove_absolute(cleanup)
	print("DEPARTMENT_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
