class_name InteractionRequestsRuntime
extends Node
## Visible choices and player intentions. Domain records remain authoritative.

const UI = preload("res://scripts/ui/reol_ui_theme.gd")
var panel: PanelContainer
var receiver_choice: OptionButton
var verb_choice: OptionButton
var object_choice: OptionButton
var medium_choice: OptionButton
var lots_choice: SpinBox
var _lots_row: HBoxContainer
var _reply: Label
var _body_sense: Label
var _progress: RichTextLabel
var _send: Button
var _receipt: Dictionary = {}
var _heard_care_alerts: Dictionary = {}
var _owner: WeakRef


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func setup(adapter: WorldContinuityRuntime) -> void:
	_owner = weakref(adapter)
	process_mode = Node.PROCESS_MODE_ALWAYS
	var layer := CanvasLayer.new()
	layer.layer = 6
	add_child(layer)
	var screen := Control.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(screen)
	panel = PanelContainer.new()
	panel.theme = UI.create()
	panel.add_theme_stylebox_override("panel", UI.panel(UI.GOLD))
	screen.add_child(panel)
	panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_TOP)
	panel.offset_left = -238
	panel.offset_right = 238
	panel.offset_top = 104
	var column := VBoxContainer.new()
	panel.add_child(column)
	UI.label(column, "与谁商量，想请他做什么", UI.GOLD, 20)
	UI.label(column, "对方可能不理解、不会、不愿或正忙；答应之后也要实际办事。", UI.MUTED, 13)
	_body_sense = UI.label(column, "", UI.JADE, 14)
	_body_sense.custom_minimum_size.x = 444
	receiver_choice = _field(column, "向谁提出")
	verb_choice = _field(column, "商量事项")
	object_choice = _field(column, "指认对象")
	medium_choice = _field(column, "怎样表达")
	_lots_row = HBoxContainer.new()
	column.add_child(_lots_row)
	UI.label(_lots_row, "买卖份数", UI.PAPER, 14).custom_minimum_size.x = 72
	lots_choice = SpinBox.new()
	lots_choice.min_value = 1
	lots_choice.max_value = int(adapter.world_sim.services.definitions.trade.max_lots)
	lots_choice.step = 1
	lots_choice.value = 1
	_lots_row.add_child(lots_choice)
	_lots_row.hide()
	var rules: Dictionary = adapter._home._content.interaction_requests
	for verb: String in rules.verbs:
		verb_choice.add_item(str(rules.verbs[verb].label))
		verb_choice.set_item_metadata(verb_choice.item_count - 1, verb)
	for medium: String in rules.media:
		medium_choice.add_item(str(rules.media[medium]))
		medium_choice.set_item_metadata(medium_choice.item_count - 1, medium)
	verb_choice.item_selected.connect(_on_verb_changed)
	receiver_choice.item_selected.connect(_on_receiver_changed)
	_reply = UI.label(column, "先选定当面的对象与事项。", UI.WARNING, 14)
	_reply.custom_minimum_size = Vector2(444, 54)
	_progress = RichTextLabel.new()
	_progress.bbcode_enabled = false
	_progress.scroll_active = true
	_progress.custom_minimum_size = Vector2(444, 100)
	_progress.add_theme_color_override("default_color", UI.JADE)
	_progress.add_theme_font_size_override("normal_font_size", 14)
	column.add_child(_progress)
	_send = UI.button(column, "提出请求", _submit_selected)
	var row := HBoxContainer.new()
	column.add_child(row)
	UI.button(row, "环顾四周", rebuild_choices)
	UI.button(row, "收起 · C / Esc", panel.hide)
	panel.hide()
	GameClock.time_advanced.connect(_on_time_advanced)
	adapter.avatar_changed.connect(reset_observation)


func _field(parent: Control, caption: String) -> OptionButton:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label: Label = UI.label(row, caption, UI.PAPER, 14)
	label.custom_minimum_size.x = 72
	label.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var option := OptionButton.new()
	option.custom_minimum_size = Vector2(350, 32)
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(option)
	return option


func show_panel() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return
	adapter.object_adapter.panel.hide()
	adapter.avian_adapter.panel.hide()
	adapter.soul_adapter.panel.hide()
	adapter.sparring_adapter.panel.hide()
	if adapter.field_adapter != null:
		adapter.field_adapter.panel.hide()
	if adapter.capability_adapter != null:
		adapter.capability_adapter.panel.hide()
	if adapter.spirit_adapter != null:
		adapter.spirit_adapter.panel.hide()
	if adapter.heat_method_adapter != null:
		adapter.heat_method_adapter.panel.hide()
	if _receipt.is_empty():
		var ongoing: Array[Dictionary] = SimInteractionRequests.pending(adapter.world_sim, adapter.avatar_subject)
		if not ongoing.is_empty():
			_receipt = ongoing.back()
		else:
			_receipt = SimCapabilityConversation.latest(adapter.world_sim, "player")
	panel.show()
	rebuild_choices()
	refresh_progress()
	if is_inside_tree():
		receiver_choice.grab_focus()


func receivers() -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return choices
	var world: RegionalSimulation = adapter.world_sim
	var from: Vector2i = adapter.controlled_cell()
	for region: String in SimAvianLife.sorted_keys(world.regions):
		var sim: VillageSimulation = world.regions[region]
		for actor: String in SimAvianLife.sorted_keys(sim.synchronize_actors()):
			var person: Dictionary = sim.synchronize_actors()[actor]
			var cell: Vector2i = SimRouteTravel.cell(person.cell)
			if actor != "player" and bool(person.alive) and from.distance_to(cell) <= float(adapter._home.simulation.config.observation_radius) and _seen(cell):
				choices.append({"key": world.embodiment.subject_for_actor(actor), "label": str(adapter.settings.runtime.remote_names.get(actor, sim._name(actor)))})
	for bird_id: String in SimAvianLife.sorted_keys(world.avian_life.birds):
		if world.avian_life.visible_to("player", bird_id) and _seen(world.avian_life.body_cell(bird_id)):
			choices.append({"key": SimAvianLife.subject_id(bird_id), "label": str(world.avian_life.describe("player", bird_id).label)})
	for id: String in SimAvianLife.sorted_keys(world.large_bodies.bodies):
		if world.large_bodies.visible_to("player", id) and adapter.large_body_adapter != null and adapter.large_body_adapter.is_visible_body(id):
			choices.append({"key": SimLargeBodies.subject_id(id), "label": str(world.large_bodies.bodies[id].label)})
	return choices


func objects_for(verb: String, receiver_subject: String = "") -> Array[Dictionary]:
	var choices: Array[Dictionary] = []
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return choices
	var world: RegionalSimulation = adapter.world_sim
	if verb == "private_exchange":
		var exchange: RefCounted = world.get("private_exchange")
		if exchange == null:
			return choices
		var receiver: String = receiver_subject
		if receiver.is_empty() and receiver_choice != null and receiver_choice.item_count > 0:
			receiver = str(receiver_choice.get_selected_metadata())
		var visible: bool = false
		for person: Dictionary in receivers():
			if person.key == receiver:
				visible = true
				break
		var target: Dictionary = SimInteractionRequests._resolve(world, receiver)
		if not visible or target.is_empty() or target.kind != "human":
			return choices
		for entry: Dictionary in exchange.offered_objects("player", str(target.id)):
			var id: String = str(entry.id)
			if _seen(world.artifacts.object_cell(id)):
				var name: String = str(world.artifacts.describe("player", id).label)
				var duration: String = str(float(exchange.definitions.duration_ms) / 1000.0)
				choices.append({"key": {"kind": "private_artifact", "id": id}, "label": "%s · 出价%d钱 · 交割%s秒" % [name, int(exchange.definitions.price), duration]})
	elif verb == "field_clue":
		choices.append({"key": {"kind": "field_question", "id": "nearby_ruins"}, "label": "近来听说的野外去处"})
	elif verb in ["explain_source", "ask_source_care", "withdraw_source_care"]:
		var care: RefCounted = world.get("source_care")
		if care == null:
			return choices
		var receiver: String = receiver_subject
		if receiver.is_empty() and receiver_choice != null and receiver_choice.item_count > 0:
			receiver = str(receiver_choice.get_selected_metadata())
		var target: Dictionary = SimInteractionRequests._resolve(world, receiver)
		if target.is_empty() or target.kind != "human":
			return choices
		var rows: Array[Dictionary] = care.basis_for("player", str(target.id)) if verb == "explain_source" else care.arrangements_for("player", str(target.id))
		for entry: Dictionary in rows:
			choices.append({"key": {"kind": "care_basis" if verb == "explain_source" else "care_arrangement", "id": str(entry.id)}, "label": str(entry.label)})
	elif verb in ["site_arrangement", "borrow_source", "verify_return"]:
		var affairs: RefCounted = world.get("site_affairs")
		if affairs == null:
			return choices
		var rows: Array[Dictionary] = []
		var kind: String = ""
		if verb == "site_arrangement":
			var receiver: String = receiver_subject
			if receiver.is_empty() and receiver_choice != null and receiver_choice.item_count > 0:
				receiver = str(receiver_choice.get_selected_metadata())
			var target: Dictionary = SimInteractionRequests._resolve(world, receiver)
			if target.is_empty() or target.kind != "human":
				return choices
			rows = affairs.inquiry_cases("player", str(target.id))
			kind = "site_case"
		elif verb == "borrow_source":
			rows = affairs.offers_for("player")
			kind = "source_offer"
		else:
			rows = affairs.notes_for("player")
			kind = "source_note"
		for entry: Dictionary in rows:
			choices.append({"key": {"kind": kind, "id": str(entry.id)}, "label": str(entry.label)})
	elif verb == "converse":
		for id: String in world._content.capability_conversation.topics:
			choices.append({"key": {"kind": "conversation_topic", "id": id}, "label": str(world._content.capability_conversation.topics[id])})
	elif verb in ["diagnose", "treat"]:
		if world.health.eligible("player"):
			choices.append({"key": {"kind": "body", "id": "player"}, "label": "本人身体"})
	elif verb == "accept_labor":
		for id: String in world.budgeted_labor.definitions.offers:
			choices.append({"key": {"kind": "labor_offer", "id": id}, "label": str(world.budgeted_labor.definitions.offers[id].label)})
	elif verb == "claim_wage":
		for note: Dictionary in world.budgeted_labor.contracts.values():
			if note.actor == "player" and note.status == "payable":
				choices.append({"key": {"kind": "labor_contract", "id": str(note.id)}, "label": str(world.budgeted_labor.definitions.offers[note.offer].label) + " · 已交付待验"})
	elif verb == "offer_food":
		var rules: Dictionary = world.large_bodies.definitions
		if adapter.player_inventory().available("actor:player", str(rules.food)) >= int(rules.food_amount):
			choices.append({"key": {"kind": "provisions", "id": str(rules.food)}, "label": "行囊中的一份饭食"})
	elif verb in ["examine", "study"]:
		for object_id: String in SimAvianLife.sorted_keys(world.artifacts.objects):
			if world.artifacts.can_see("player", object_id) and _seen(world.artifacts.object_cell(object_id)):
				choices.append({"key": {"kind": "artifact", "id": object_id}, "label": str(world.artifacts.describe("player", object_id).label)})
	elif verb == "fetch_herb":
		for site_id: String in SimAvianLife.sorted_keys(world.avian_life.sites):
			var site: Dictionary = world.avian_life.sites[site_id]
			var cell: Vector2i = SimRouteTravel.cell(site.cell)
			if site.type == "crevice" and adapter.controlled_cell().distance_to(cell) <= float(adapter._home.simulation.config.observation_radius) and _seen(cell):
				var delta: Vector2i = cell - adapter.controlled_cell()
				var direction: String = ("北" if delta.y < 0 else "南" if delta.y > 0 else "") + ("东" if delta.x > 0 else "西" if delta.x < 0 else "")
				choices.append({"key": {"kind": "avian_site", "id": site_id}, "label": "石隙药枝 · " + (direction + "侧" if not direction.is_empty() else "就在近旁")})
	elif verb == "trade" and world.services != null:
		for offer: String in world.services.definitions.trade.offers:
			choices.append({"key": {"kind": "trade_offer", "id": offer}, "label": str(world.services.definitions.trade.offers[offer].label)})
	elif verb == "watch_supply":
		for id: String in world.standing_work.definitions.plans:
			var plan: Dictionary = world.standing_work.definitions.plans[id]
			var home: String = world.services.actor_home("player")
			var cell: Vector2i = SimRouteTravel.cell(world.regions[home].places[plan.place].cell)
			if adapter.controlled_cell().distance_to(cell) <= float(adapter._home.simulation.config.observation_radius) and _seen(cell):
				choices.append({"key": {"kind": "work_plan", "id": id}, "label": str(plan.label)})
	elif verb == "withdraw_work":
		for note: Dictionary in world.standing_work.entries.values():
			if note.requester == "player" and world.elapsed_ms < int(note.until_ms) and note.status != "refused":
				choices.append({"key": {"kind": "work_agreement", "id": str(note.id)}, "label": str(world.standing_work.definitions.plans[note.plan].label) + " · " + world.regions[note.region]._name(str(note.responder))})
	return choices


func _seen(cell: Vector2i) -> bool:
	return runtime()._home._fog == null or runtime()._home._fog.is_cell_visible(cell)


func rebuild_choices() -> void:
	_fill(receiver_choice, receivers())
	_fill(object_choice, objects_for(str(verb_choice.get_selected_metadata())))
	_lots_row.visible = verb_choice.get_selected_metadata() == "trade"
	_send.disabled = receiver_choice.item_count == 0 or object_choice.item_count == 0


func _fill(option: OptionButton, choices: Array[Dictionary]) -> void:
	var selected: Variant = option.get_selected_metadata() if option.item_count > 0 else null
	option.clear()
	for row: Dictionary in choices:
		option.add_item(str(row.label))
		option.set_item_metadata(option.item_count - 1, row.key)
		if row.key == selected:
			option.select(option.item_count - 1)


func _on_verb_changed(_index: int) -> void:
	rebuild_choices()


func _on_receiver_changed(_index: int) -> void:
	_fill(object_choice, objects_for(str(verb_choice.get_selected_metadata())))
	_send.disabled = receiver_choice.item_count == 0 or object_choice.item_count == 0


func _submit_selected() -> void:
	if receiver_choice.item_count == 0 or object_choice.item_count == 0:
		return
	var terms: Dictionary = {"lots": int(lots_choice.value)} if verb_choice.get_selected_metadata() == "trade" else {}
	submit(str(receiver_choice.get_selected_metadata()), str(verb_choice.get_selected_metadata()), object_choice.get_selected_metadata(), str(medium_choice.get_selected_metadata()), terms)


func submit(receiver: String, verb: String, object: Dictionary, medium: String = "spoken", conditions: Dictionary = {}) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active():
		return SimInteractionRequests.result("invalid", "这段人生还没有这种当面表达方式。")
	var needs_stillness: bool = verb in ["diagnose", "treat"] and not adapter._home._player.motion.velocity.is_zero_approx()
	if verb == "private_exchange":
		needs_stillness = adapter._home._player.altitude != 0 or adapter._home._player.motion.velocity != Vector2.ZERO
	if not adapter.player_journey.is_empty() or not adapter._home._player.motion.action.is_empty() or needs_stillness:
		var busy: Dictionary = SimInteractionRequests.result("unavailable", "先停稳，再当面指认或交谈。")
		_reply.text = str(adapter._home._content.interaction_requests.status_labels[busy.status]) + "：" + str(busy.line)
		return busy
	var visible: bool = false
	for row: Dictionary in receivers():
		if row.key == receiver:
			visible = true
	var known: bool = false
	for row: Dictionary in objects_for(verb, receiver):
		if row.key == object:
			known = true
	var answer: Dictionary
	if not visible or not known:
		answer = SimInteractionRequests.result("unheard", "先看清当面的人和要谈的对象，再提出请求。")
	else:
		adapter.prepare_player_command()
		answer = SimInteractionRequests.submit(adapter.world_sim, {"sender": adapter.avatar_subject, "receiver": receiver, "verb": verb, "object": object, "medium": medium, "conditions": conditions})
		if verb == "private_exchange" and bool(answer.ok) and answer.status == "started":
			adapter.hold_player_motion(true)
	if not answer.process.is_empty():
		_receipt = answer.process.duplicate(true)
	_reply.text = str(adapter._home._content.interaction_requests.status_labels[answer.status]) + "：" + str(answer.line)
	if verb in ["offer_food", "site_arrangement", "borrow_source", "verify_return", "explain_source", "ask_source_care", "withdraw_source_care"]:
		rebuild_choices()
	adapter._refresh_panel()
	refresh_progress()
	return answer


func refresh_progress() -> void:
	if runtime() != null and runtime().world_sim.settlement.is_pending():
		return
	if not panel.visible:
		return
	if not runtime().human_player_active():
		panel.hide()
		return
	_body_sense.text = runtime().world_sim.health.describe("player")
	_progress.text = str(SimInteractionRequests.observe(runtime().world_sim, runtime().avatar_subject, _receipt).line) if not _receipt.is_empty() else "请求不会直接发放物品、手法或机构认可。"


func reset_observation() -> void:
	_receipt = {}
	_heard_care_alerts.clear()
	_reply.text = "先选定当面的对象与事项。"
	_body_sense.text = ""
	_progress.text = ""
	panel.hide()


func _on_time_advanced(_from: int, _to: int) -> void:
	_receive_care_alerts()
	refresh_progress()


func receive_current_care_alerts() -> void:
	# Loading replaces the view's deduplication cache. Deliver an already
	# received, still-live warning before a saved running clock can advance.
	_receive_care_alerts()


func _receive_care_alerts() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null or adapter.world_sim.source_care == null:
		return
	# The old human body can be autonomous in a bird or spirit life. Only the
	# currently inhabited human subject's actual received warning interrupts it.
	var sender: Dictionary = SimInteractionRequests._resolve(adapter.world_sim, adapter.avatar_subject)
	if sender.is_empty() or sender.kind != "human" or not adapter.human_player_active():
		return
	for alert: Dictionary in adapter.world_sim.source_care.alerts_for(str(sender.id)):
		if _heard_care_alerts.has(alert.id):
			continue
		_heard_care_alerts[alert.id] = true
		GameClock.cancel_wait()
		GameClock.set_speed(1.0)
		GameClock.set_paused(true)
		_receipt = alert.process.duplicate(true)
		show_panel()
		for index: int in receiver_choice.item_count:
			if receiver_choice.get_item_metadata(index) == _receipt.performer:
				receiver_choice.select(index)
		for index: int in verb_choice.item_count:
			if verb_choice.get_item_metadata(index) == "explain_source":
				verb_choice.select(index)
		rebuild_choices()
		_reply.text = str(alert.line)
		break


func _unhandled_input(event: InputEvent) -> void:
	if not runtime().human_player_active() or not event is InputEventKey or not event.pressed or event.echo:
		return
	if event.keycode == KEY_C:
		if panel.visible:
			panel.hide()
		else:
			show_panel()
		get_viewport().set_input_as_handled()
	elif event.keycode == KEY_ESCAPE and panel.visible:
		panel.hide()
		get_viewport().set_input_as_handled()
