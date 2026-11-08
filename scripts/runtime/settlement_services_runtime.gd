class_name SettlementServicesRuntime
extends RefCounted
## Routes player service intentions to pure rules and formats local observations.

const DEFINITIONS_PATH: String = "res://data/definitions/settlement_services.json"

var panel: SettlementServicesPanel
var _owner: WeakRef
var _last_line: String = "到当地办事，或承担河湾到山门的运粮差事。"
var _settled_job: String = ""
var _agreement: String = ""
var _settled_agreement: String = ""
var _admission_entry: String = ""
var _admission_waiting: bool = false
var _observed_native_events: int = 0


func setup(adapter: WorldContinuityRuntime, screen: Control) -> bool:
	_owner = weakref(adapter)
	panel = SettlementServicesPanel.new()
	screen.add_child(panel)
	panel.set_gather_modes(adapter._home._content.personal_foraging)
	panel.gather_mode_changed.connect(refresh)
	panel.batch_selected.connect(refresh)
	panel.set_help_offer(int(adapter.settings.runtime.help_offer_coins))
	panel.service_requested.connect(submit)
	refresh()
	return true


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func submit(action_id: String) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null:
		return {"ok": false, "line": "世界尚未准备好。"}
	if not adapter.human_player_active():
		return {"ok": false, "line": "这些是人身的办事方法；雀身请用自己的行动。"}
	var world: RegionalSimulation = adapter.world_sim
	if world.services == null:
		return _result(false, "尚未准备好当地服务。")
	if action_id == "cancel":
		if not adapter.stop_player_action():
			return _result(false, "当前结算尚未完成，本次停止未受理。")
		return _result(true, "已停止当前行动，随身物品保留；受托公物可续做或交回。")
	if not adapter.player_journey.is_empty():
		return _result(false, "先完成或停止当前行程。")
	if action_id.begins_with("labor:"):
		adapter.prepare_player_command()
		var id: String = world.budgeted_labor.latest_for("player")
		var result: Dictionary = world.budgeted_labor.resume("player", id) if action_id == "labor:resume" else world.budgeted_labor.abandon("player", id)
		if bool(result.ok) and action_id == "labor:resume":
			adapter.hold_player_motion()
		return _result(bool(result.ok), str(result.line))
	if action_id.begins_with("production:"):
		adapter.prepare_player_command()
		var intention: String = action_id.trim_prefix("production:")
		var kind: String = intention.get_slice(":", 0)
		var id: String = intention.trim_prefix(kind + ":")
		var production: Dictionary = world.personal_production.create("player", adapter.current_region, id) if kind == "new" else world.personal_production.begin("player", id, kind)
		if bool(production.ok):
			adapter.hold_player_motion()
		return _result(bool(production.ok), str(production.line))
	var region: String = adapter.current_region
	if region.is_empty():
		return _result(false, "正在两地之间，请先到达聚落。")
	if action_id.begins_with("work:"):
		var work: Dictionary = adapter.start_home_work(action_id.trim_prefix("work:"))
		return _result(bool(work.get("ok", false)), str(work.get("line", "暂时无法劳作。")))
	if action_id.begins_with("talk:"):
		var talk: Dictionary = adapter.talk_to_selected(action_id.trim_prefix("talk:"))
		return _result(bool(talk.get("ok", false)), str(talk.get("line", "暂时无法交谈。")))
	if action_id == "meet_courier":
		if region != "river":
			return _result(false, "请先到河湾，再去仓库找运粮人。")
		var definition: Dictionary = world.settings.routes.river_road
		var cell_data: Array = world.regions.river.places[definition.source].cell
		var target := Vector2i(int(cell_data[0]), int(cell_data[1]))
		var accepted: bool = adapter.travel_to("river", target)
		return _result(accepted, "去河湾仓库等候运粮人，到达后可开口或协商报酬。" if accepted else "眼下走不到河湾仓库。")
	adapter.prepare_player_command()
	var result: Dictionary
	match action_id:
		"report": result = world.services.report_work("player", region)
		"redeem": result = world.services.redeem("player", region, "meal")
		"access": result = world.services.request_access("player", region, "gate")
		"ask_help": result = world.services.ask_help("player", "river_courier", "river_road", 0)
		"offer_help": result = world.services.ask_help("player", "river_courier", "river_road", int(adapter.settings.runtime.help_offer_coins))
		_: result = world.services.begin("player", region, action_id)
	_last_line = str(result.get("line", "这件事暂时没有办成。"))
	if bool(result.get("ok", false)) and str(result.get("id", "")).begins_with("service:help:"):
		_agreement = str(result.id)
	if bool(result.get("ok", false)) and world.services.owns_actor("player"):
		adapter.hold_player_motion()
	refresh()
	return result


func _result(ok: bool, line: String) -> Dictionary:
	_last_line = line
	refresh()
	return {"ok": ok, "line": line}


func cancel_manual() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter != null and adapter.world_sim.services != null and adapter.world_sim.services.owns_actor("player"):
		adapter.world_sim.services.cancel("player", "manual_movement")
		_last_line = "行动已中断，已取出的物品仍在身上。"
		refresh()


func reset_observation() -> void:
	# UI observation belongs to this loaded timeline, never a later abandoned one.
	_settled_job = ""
	_settled_agreement = ""
	_admission_entry = ""
	_admission_waiting = false
	_agreement = ""
	_last_line = "已接续保存时的事务与凭据。"
	var adapter: WorldContinuityRuntime = runtime()
	if adapter != null:
		_observed_native_events = adapter._home.simulation.social.events.size()
		for id: String in adapter.world_sim.services.help_requests:
			var request: Dictionary = adapter.world_sim.services.help_requests[id]
			if request.actor == "player" and request.execution == "pending":
				_agreement = id


func refresh() -> void:
	if runtime() != null and runtime().world_sim.settlement.is_pending():
		return
	var adapter: WorldContinuityRuntime = runtime()
	if panel == null or adapter == null or adapter.world_sim == null:
		return
	var world: RegionalSimulation = adapter.world_sim
	_refresh_care_outcome(adapter._home.simulation)
	var inventory: SimInventory = adapter.player_inventory()
	var labor_id: String = world.budgeted_labor.latest_for("player")
	var labor_status: String = str(world.budgeted_labor.contracts[labor_id].status) if not labor_id.is_empty() else ""
	panel.set_labor("尚未签下现金差事；公库要先有真实收入。" if labor_id.is_empty() else str(world.budgeted_labor.describe("player", labor_id).line), labor_status == "paused", labor_status in ["working", "paused"])
	panel.set_terms(world.services.definitions, inventory.available("actor:player", "meal") >= int(world.services.definitions.visitor.eat.amount))
	var details: Array[String] = []
	details.append("随身：钱%d · 柴%d · 粮%d · 水%d · 饭%d · 药%d · 干药%d" % [
		inventory.quantity("actor:player", "coin"),
		inventory.quantity("actor:player", "wood"),
		inventory.quantity("actor:player", "grain"),
		inventory.quantity("actor:player", "water"),
		inventory.quantity("actor:player", "meal"),
		inventory.quantity("actor:player", "herb"),
		inventory.quantity("actor:player", "dried_herb"),
	])
	if not SimEntrustedGoods.first_held(inventory, "player").is_empty():
		details.append("其中受托：柴%d · 粮%d · 水%d · 药%d；可续做或交回" % [
			inventory.entrusted("actor:player", "wood"), inventory.entrusted("actor:player", "grain"),
			inventory.entrusted("actor:player", "water"), inventory.entrusted("actor:player", "herb")])
	var region: String = adapter.current_region
	var label: String = str(adapter.settings.regions.get(region, {}).get("label", "途中"))
	if not region.is_empty():
		var sim: VillageSimulation = world.regions[region]
		details.append("当地记账 %d 功 · %s" % [sim.institutions.balance(str(sim.config.institution.id), "player"),
			"已有通行凭据" if world.services.has_access("player", region, "gate") else "尚无通行凭据"])
	var status: Dictionary = world.services.status("player")
	details.append(adapter.known_kitchen_line())
	var busy: bool = bool(status.get("busy", false))
	var activity: String = str(status.get("line", adapter.player_goal())) if busy else adapter.player_goal()
	if not busy and not str(status.get("id", "")).is_empty() and _settled_job != str(status.id):
		_settled_job = str(status.id)
		_last_line = str(status.get("outcome", activity))
	if not _agreement.is_empty() and world.services.help_requests.has(_agreement):
		var agreement: Dictionary = world.services.help_requests[_agreement]
		if agreement.execution != "pending" and _settled_agreement != _agreement:
			_settled_agreement = _agreement
			_last_line = str(agreement.line)
	var phase: String = str(status.get("phase", ""))
	var remaining: int = int(status.get("remaining", 0))
	var seconds: bool = false
	var conversation: Dictionary = world.admissions.view("player")
	if not bool(conversation.busy) and not str(conversation.get("id", "")).is_empty() and (_admission_entry != str(conversation.id) or _admission_waiting):
		_admission_entry = str(conversation.id)
		_last_line = str(conversation.line)
		_admission_waiting = false
	if bool(conversation.busy):
		_admission_waiting = true
		activity = str(conversation.line)
		phase = "交谈"
		remaining = int(conversation.seconds)
		seconds = true
		busy = true
	var native_action: Dictionary = adapter._home.simulation.actors.player.active
	if world.personal_production.owns_actor("player"):
		var production_job: Dictionary = world.personal_production.active.player
		var batch: Dictionary = world.personal_production.batches[production_job.batch]
		activity = ("取回成品：" if production_job.kind == "collect" else "私人加工：") + str(world.personal_production.definitions.recipes[batch.recipe].label)
		phase = str(production_job.phase)
		remaining = ceili(float(int(production_job.due_ms) - world.elapsed_ms) / 60000.0)
		seconds = false
		busy = true
	if world.construction.owns_actor("player"):
		var construction_job: Dictionary = world.construction.active.player
		activity = "处理工地：" + str(world.construction.definitions.types[world.construction.projects[construction_job.project].type].label)
		phase = str(construction_job.phase)
		remaining = ceili(float(int(construction_job.due_ms) - world.elapsed_ms) / 60000.0)
		seconds = false
		busy = true
	var object_status: Dictionary = world.artifacts.status("player")
	if world.method_records.owns_actor("player"):
		activity = str(world.method_records.status("player").line)
		phase = "work"
		remaining = ceili(float(int(world.method_records.active.player.due_ms) - world.elapsed_ms) / 60000.0)
		seconds = false
		busy = true
	if world.resting.owns_actor("player"):
		var resting_job: Dictionary = world.resting.active.player
		activity = "在木床上休息" if resting_job.phase == "sleep" else "起身让出床位" if resting_job.phase == "leave" else "前往已预约的木床"
		phase = "rest" if resting_job.phase == "sleep" else "travel"
		remaining = ceili(float(int(resting_job.due_ms) - world.elapsed_ms) / 60000.0)
		seconds = false
		busy = true
	var soul_status: Dictionary = world.soul_vessels.status("player")
	if bool(soul_status.busy):
		activity = str(soul_status.line)
		phase = "work"
		remaining = int(soul_status.remaining)
		seconds = false
		busy = true
	if bool(object_status.busy):
		activity = str(object_status.line)
		phase = "work"
		seconds = object_status.has("seconds")
		remaining = int(object_status.seconds) if seconds else int(object_status.remaining)
		busy = true
	if not native_action.is_empty():
		activity = adapter._home.simulation.actor_status("player")
		phase = str(native_action.phase)
		remaining = ceili(float(int(native_action.due_ms) - int(world.elapsed_ms)) / 60000.0)
		seconds = false
		busy = true
	if not adapter.player_journey.is_empty():
		activity = "正在前往%s" % adapter._journey_label(str(adapter.player_journey.destination))
		phase = "travel"
		remaining = ceili(float(int(adapter.player_journey.due_ms) - world.elapsed_ms) / 60000.0)
		seconds = false
		busy = true
	panel.update_view(label, activity, "\n".join(details), _last_line, not region.is_empty())
	panel.set_home_work_available(region == "home")
	panel.set_resource_work(adapter._home.simulation.config, adapter._home.simulation.land_resources, adapter._home.visible_resource_sources(adapter._home.simulation))
	panel.update_activity(phase, remaining, busy, seconds)
	var batches: Array[Dictionary] = []
	for id: String in world.personal_production.batches:
		var batch: Dictionary = world.personal_production.batches[id]
		if batch.owner != "player":
			continue
		var terms: Dictionary = world.personal_production.definitions.recipes[batch.recipe]
		var state: String = {"open": "在制", "ready": "待取", "collected": "已取"}[batch.state]
		var note: String = "工时%d/%d分" % [floori(float(world.personal_production.progress(id)) / 60000.0), ceili(float(terms.work_ms) / 60000.0)] if batch.state == "open" else "成品仍在现场" if batch.state == "ready" else "已放入原行囊"
		batches.append({"id": id, "state": batch.state, "label": "%s · %s · %s · %s" % [id.trim_prefix("production_batch:"), str(adapter.settings.regions[batch.region].label), str(terms.label), state], "note": note})
	panel.set_production(world.personal_production.definitions, batches, busy or world.local_action_owns("player"))


func _refresh_care_outcome(sim: VillageSimulation) -> void:
	for index: int in range(_observed_native_events, sim.social.events.size()):
		var event: Dictionary = sim.social.events[index]
		if event.actor != "player" or event.details.get("task", "") != "irrigate_herb":
			continue
		if event.kind == "completed":
			_last_line = "已用随身私水照料药丛；药草仍须随水土与时令慢慢生长。"
		elif event.kind == "interrupted":
			_last_line = "照料已中断；没有完成浇灌，已耗工时不会退回。"
	_observed_native_events = sim.social.events.size()
