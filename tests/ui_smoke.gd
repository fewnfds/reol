extends SceneTree
## Focus, coordinate and knowledge counterexamples for the native interaction UI.
## Run explicitly for UI changes; not part of the kernel's headless suite.
const Game = preload("res://scripts/presentation/game.gd")
const Actions = preload("res://scripts/presentation/ui/actions.gd")
const Art = preload("res://scripts/presentation/art.gd")
const CAPTURE_DIR = "res://logs/ui-smoke/"
var game: Node2D
var errors: Array[String] = []

func _initialize() -> void:
	call_deferred("run")

func check(ok: bool, message: String) -> void:
	if not ok:
		errors.append(message)
		push_error(message)

func settle(frames: int = 4) -> void:
	for index: int in frames: await process_frame

func key(code: Key) -> void:
	var event := InputEventKey.new()
	event.keycode = code
	event.physical_keycode = code
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func click(at: Vector2, button: MouseButton = MOUSE_BUTTON_LEFT) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = at
	Input.parse_input_event(motion)
	var event := InputEventMouseButton.new()
	event.position = at
	event.button_index = button
	event.pressed = true
	Input.parse_input_event(event)
	event = event.duplicate()
	event.pressed = false
	Input.parse_input_event(event)

func screen(point: Vector2) -> Vector2:
	return game.get_canvas_transform() * (point * Art.TILE)

func capture(name_key: String) -> void:
	if DisplayServer.get_name() == "headless": return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(CAPTURE_DIR))
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(CAPTURE_DIR + name_key + ".png")

func run() -> void:
	game = Game.new()
	game.runner.control(true, 1)
	game.paused = true
	root.add_child(game)
	var deadline: int = Time.get_ticks_msec() + 4000
	while game.frame == null and Time.get_ticks_msec() < deadline: await process_frame
	check(game.frame != null, "UI runner did not publish")
	if game.frame == null: game.queue_free(); await settle(); quit(1); return
	await settle(8)
	game.ui.apply_scale(100, false)
	await settle(4)
	for value: int in [8, 16, 1]:
		click(game.ui._speed_buttons[value].get_global_rect().get_center())
		await settle(4)
		check(game.frame.speed == value and game.frame.paused, "Acceleration button %d failed or unpaused the world: %s" % [value, str(game.frame.speed)])
	var known_chest: int = 0
	for id: int in game.object_canvas.objects:
		var rec: Dictionary = game.object_canvas.objects[id]
		if rec.kind == "chest" and rec.tile == 186 * 512 + 176: known_chest = id; break
	check(known_chest > 0, "Initial visible chest absent")
	# A target's context click uses the object under the pointer, not stale selection.
	click(screen(Vector2(176.5,186.5)), MOUSE_BUTTON_RIGHT)
	await settle(12)
	check(game.selected == known_chest and game.ui._context_panel.visible, "Right click did not expose the chest menu")
	await capture("context")
	var context_point := Vector2.ZERO
	for button: Node in game.ui._context_body.get_children():
		if button is Button and button.text == "拿取 R": context_point = button.get_global_rect().get_center()
	check(not context_point.is_zero_approx(), "Chest take action absent")
	click(context_point)
	await settle()
	check(game.ui.inventory.visible and game.ui.inventory.kind == "take", "GUI button did not open container grid")
	# Focused numeric entry must not change speed, pause or the current world action.
	var before_mode: int = int(game.frame.player.mode)
	var before_speed: float = game.speed
	var before_paused: bool = game.paused
	for code: Key in [KEY_1,KEY_2,KEY_4,KEY_8,KEY_SPACE,KEY_S,KEY_B,KEY_DELETE]: key(code)
	await settle(4)
	check(game.speed == before_speed and game.paused == before_paused and int(game.frame.player.mode) == before_mode, "Quantity entry leaked world keys")
	var first_slot: Button = game.ui.inventory.container.buttons["grain"]
	var changed_contents: Dictionary = game.frame.inspected.inventory.duplicate()
	changed_contents["grain"] += 1
	game.ui.inventory.container.refresh(changed_contents)
	check(game.ui.inventory.container.buttons["grain"] == first_slot, "Quantity refresh destroyed a live slot control")
	await capture("inventory")
	click(game.ui.inventory.container.buttons["grain"].get_global_rect().get_center())
	await settle(3)
	check(game.ui.inventory.container.selected == "grain", "Scaled inventory grid could not select an item")
	await capture("inventory-list")
	key(KEY_ESCAPE)
	await settle()
	check(not game.ui.inventory.visible, "Escape failed to cancel quantity entry")
	# Numeric inventory actions must commit the requested amount exactly once.
	game.controls.action("take", {"target":known_chest})
	await settle()
	game.ui.inventory.container.select("grain")
	game.ui.inventory.amount.value = 2
	click(game.ui.inventory._take.get_global_rect().get_center())
	await settle(8)
	check(str(game.frame.player.action.get("kind", "")) == "take" and int(game.frame.player.action.get("amount", 0)) == 2, "Quantity button did not submit exactly two items")
	game.controls.action("stop", {})
	game.ui.inventory.hide()
	root.gui_release_focus()
	await settle(6)
	# Attack tool cancellation cannot additionally move the protagonist.
	key(KEY_A)
	await settle()
	check(game.controls.tool == "attack", "A did not select attack tool")
	var previous_seq: int = game._pending_move
	click(screen(Vector2(174.3,188.7)), MOUSE_BUTTON_RIGHT)
	await settle()
	check(game.controls.tool.is_empty() and game._pending_move == previous_seq, "Right cancel also sent movement")
	# Continuous main-map and mini-map coordinates must preserve the foot inverse.
	game.controls.action("move_tool", {})
	var goal := Vector2(171.37,189.83)
	click(screen(goal))
	await settle(8)
	check(game.frame.player.destination.distance_to(Art.body_position(goal)) < 0.001, "Mouse destination was snapped or offset")
	var map_point := Vector2(179.37,189.83)
	game.controls.action("map_move", {"position":map_point})
	await settle(8)
	check(game.frame.player.destination.distance_to(map_point) < 0.001, "Minimap added the foot offset twice")
	# Building preview is visual state; rotation and cancel cannot commit a building.
	key(KEY_B)
	await settle()
	check(game.ui._drawer_name == "build", "B did not open build drawer")
	await capture("build-drawer")
	game.controls.action("place_build", {"definition":"long_bed"})
	var before_facing: int = game.controls.facing
	key(KEY_R)
	await settle()
	check(game.controls.facing == (before_facing + 1) % 4 and game.controls.tool == "build", "R did not rotate the placement tool")
	var motion := InputEventMouseMotion.new()
	motion.position = screen(Vector2(171.4,188.4))
	Input.parse_input_event(motion)
	await settle()
	await capture("build-tool")
	key(KEY_ESCAPE)
	await settle()
	check(game.controls.tool.is_empty(), "Escape did not leave placement")
	# A real selected object must downgrade to frozen appearance after leaving sight.
	var fake: RefCounted = game.frame.get_script().new()
	fake.player = game.frame.player
	fake.actor_slots = {}
	fake.inspected = {"id":known_chest,"kind":"chest","inventory":{"wood":99999}}
	fake.perception = {"tiles":PackedByteArray(), "memories":{known_chest:{"id":known_chest,"kind":"chest","definition":"wood_chest","cells":PackedInt32Array([0]),"tile":0}}}
	fake.perception.tiles.resize(512*512)
	var memory: Dictionary = Actions.observed(fake,known_chest,true)
	check(memory.get("memory",false) and not memory.has("inventory"), "Inspector exposed a hidden live inventory")
	# A held map click may move only the camera, never enqueue a world click.
	var old_target: Vector2 = game.frame.player.destination
	var local := Vector2(40,40)
	var expected: Vector2 = game.ui.minimap.world_point(local)
	click(game.ui.minimap.get_global_transform_with_canvas() * local)
	await settle()
	check(not game.following and game.camera.position.distance_to(Art.body_foot(expected)*32) < 0.01 and game.frame.player.destination == old_target, "Minimap camera click leaked to the world")
	await capture("minimap")
	game.controls.action("follow", {})
	game.controls.reset_session()
	check(game.ui.modal_kind().is_empty() and game.controls.tool.is_empty() and not game.ui._context_panel.visible, "Session reset retained stale UI state")
	# Resume a real quantity transfer; the accepted command is not completion.
	var pile: int = 0
	for id: int in game.object_canvas.objects:
		var rec: Dictionary = game.object_canvas.objects[id]
		if rec.kind == "pile" and rec.tile == 186 * 512 + 178: pile = id; break
	check(pile > 0, "Material pile absent")
	game.controls._select(pile, 186 * 512 + 178)
	await settle(8)
	game.controls.action("take", {"target":pile})
	await settle()
	check(game.ui.inventory.container.buttons.has("wood"), "Material pile did not expose wood")
	if game.ui.inventory.container.buttons.has("wood"):
		game.ui.inventory.container.select("wood")
		game.ui.inventory.amount.value = 4
		click(game.ui.inventory._take.get_global_rect().get_center())
		await settle(4)
		game.ui.inventory.hide()
		root.gui_release_focus()
		await settle(6)
		game.controls.action("pause", {})
		await create_timer(1.8).timeout
		check(int(game.frame.player.inventory.get("wood", 0)) == 4, "Two-stage take did not transfer exactly four wood")
		game.controls.action("place_build", {"definition":"wood_wall"})
		game.controls._confirm_tool(Vector2(174.3,188.2))
		await settle(12)
		check(int(game.frame.player.inventory.get("wood",0)) == 1 and str(game.frame.inspected.get("kind","")) == "blueprint", "Placement did not select the real paid blueprint")
		await create_timer(0.9).timeout
		await capture("construction")
		game.controls.action("stop", {})
		game.controls.action("pause", {})
		await settle(6)
	# Resizing and UI scaling must keep the player commands accessible.
	root.size = Vector2i(1920,1080)
	await settle(8)
	await capture("layout-1080")
	root.size = Vector2i(1280,720)
	var world_transform: Transform2D = game.get_canvas_transform()
	game.ui.apply_scale(125, false)
	await settle(8)
	await capture("layout-scaled")
	check(game.ui._player_buttons.stop.get_global_rect().end.x < game.ui.size.x, "UI scaling pushed player actions off screen")
	check(game.get_canvas_transform().is_equal_approx(world_transform), "UI scaling changed world pixels")
	for percent: int in [50, 200]:
		game.ui.apply_scale(percent, false)
		await settle(8)
		check(game.ui.ui_percent == percent, "UI numeric scale was not applied")
		check(game.ui._player_buttons.stop.get_global_rect().end.y <= root.get_visible_rect().size.y, "UI commands fell below the viewport")
		check(not game.ui._player_buttons.stop.get_global_rect().intersects(game.ui._map_panel.get_global_rect()), "Minimap covered the command dock")
		await capture("scale-%d" % percent)
	game.ui.apply_scale(100, false)
	game.controls._select(1, -1)
	await settle(6)
	game.controls.action("character", {})
	await settle(5)
	check(is_instance_valid(game.ui._events) and game.ui._events.text.contains("拿取"), "Character drawer lacked localized actual events")
	await capture("person-events")
	game.controls.action("inventory", {})
	await settle(5)
	check(game.ui._drawer_panel.visible and game.ui.inventory.visible, "Character and bag could not be open together")
	click(game.ui.inventory.bag.buttons["iron_sword@2"].get_global_rect().get_center())
	await settle(3)
	click(game.ui.inventory._equip.get_global_rect().get_center())
	await settle(8)
	check(game.frame.player.equipment.get("weapon", "") == "iron_sword@2" and int(game.frame.player.stats.melee) == 38, "Grid equip did not change actual derived combat stats")
	await capture("equipment-bag")
	game.controls.action("unequip", {"slot":"weapon"})
	await settle(8)
	check(game.frame.player.equipment.is_empty() and game.frame.player.inventory.get("iron_sword@2", 0) == 1, "Unequip lost or duplicated the item")
	game.ui.inventory.amount.get_line_edit().grab_focus()
	var outside_goal := Vector2(172.3, 190.7)
	click(screen(outside_goal), MOUSE_BUTTON_RIGHT)
	await settle(8)
	check(game.ui.inventory.visible and game.frame.player.destination.distance_to(Art.body_position(outside_goal)) < 0.001, "Leaving bag numeric entry did not restore world mouse control")
	for percent: int in [50, 200]:
		game.ui.apply_scale(percent, false)
		await settle(6)
		check(game.ui.inventory.get_global_rect().end.x <= root.get_visible_rect().size.x and game.ui.inventory.get_global_rect().end.y <= root.get_visible_rect().size.y, "Bag clipped after scaling")
		await capture("bag-scale-%d" % percent)
	game.ui.apply_scale(100, false)
	game.ui.inventory.hide()
	game.controls.action("close_drawer", {})
	game.controls._select(2, -1)
	await settle(8)
	game.controls.action("character", {})
	game.ui.open_bag(2)
	await settle(4)
	check(game.ui.character.subject_id == 2 and game.ui.inventory.subject_id == 2, "NPC inspection switched to a different identity")
	game.ui.inventory.bag.select("potion")
	check(game.ui.inventory._use.disabled and game.ui.inventory._equip.disabled and game.ui.inventory._drop.disabled, "NPC bag inspection granted control")
	await capture("npc-readonly")
	game.ui.inventory.hide()
	game.controls.action("close_drawer", {})
	# Exercise the actual numeric form without overwriting the user's preferences.
	game.ui.requested.disconnect(game.controls.action)
	var form_handler: Callable = func(kind: String, payload: Dictionary):
		if kind == "ui_scale_commit": game.ui.commit_scale()
		elif kind == "ui_scale": game.ui.apply_scale(int(payload.percent), false)
	game.ui.requested.connect(form_handler)
	game.ui.open_simple("settings")
	await settle(3)
	var confirm: Button
	for node: Node in game.ui._modal_body.get_children():
		if node is Button and node.text == "确认": confirm = node
	for value: int in [175,300,20]:
		game.ui._scale_input.get_line_edit().text = str(value)
		click(confirm.get_global_rect().get_center())
		await settle(3)
		check(game.ui.ui_percent == clampi(value,50,200), "Scale form ignored unsubmitted text or its limits")
	await capture("settings")
	game.ui.close_modal()
	game.ui.requested.disconnect(form_handler)
	game.ui.requested.connect(game.controls.action)
	game.ui.apply_scale(100, false)
	print("UI_SMOKE ",JSON.stringify({"errors":errors,"minimap_rebuilds":game.ui.minimap.rebuilds,"minimap_usec":game.ui.minimap.work_usec}))
	game.queue_free()
	await settle(3)
	quit(0 if errors.is_empty() else 1)
