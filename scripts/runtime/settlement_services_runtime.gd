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
var _care_world: WeakRef


func setup(adapter: WorldContinuityRuntime, screen: Control) -> bool:
	_owner = weakref(adapter)
	panel = SettlementServicesPanel.new()
	screen.add_child(panel)
	panel.set_gather_modes(adapter._home._content.personal_foraging)
	panel.gather_mode_changed.connect(refresh)
	panel.batch_selected.connect(refresh)
	panel.set_help_offer(int(adapter.settings.runtime.help_offer_coins))
	panel.service_requested.connect(submit)
	panel.haul_requested.connect(submit_haul)
	panel.haul_page_opened.connect(refresh_hauling)
	refresh()
	return true


func runtime() -> WorldContinuityRuntime:
	return _owner.get_ref() as WorldContinuityRuntime if _owner != null else null


func submit_haul(source: Dictionary, target: Dictionary, item: String, amount: int) -> Dictionary:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or not adapter.human_player_active() or not adapter.player_journey.is_empty():
		return _result(false, "先以人身停下行程，再安排搬运。")
	adapter.prepare_player_command()
	var result: Dictionary = adapter.world_sim.services.begin_haul("player", source, target, item, amount)
	if bool(result.ok):
		adapter.hold_player_motion(true)
	return _result(bool(result.ok), str(result.line))


func refresh_hauling() -> void:
	var adapter: WorldContinuityRuntime = runtime()
	if adapter == null or adapter.world_sim == null or not adapter.world_sim.accepts_commands() or adapter.world_sim.settlement.is_pending():
		return
	var world: RegionalSimulation = adapter.world_sim
	var rows: Array[Dictionary] = [{"label": "本人行囊", "reference": {"region": "home", "container": "actor:player"}}]
	for region: String in SimAvianLife.sorted_keys(world.regions):
		for place: String in SimAvianLife.sorted_keys(world.regions[region].places):
			rows.append({"label": "%s · %s" % [str(adapter.settings.regions[region].label), str(world.regions[region].places[place].label)], "reference": {"region": region, "container": place}})
	var fog: FogOfWar = adapter.home_runtime()._fog
	for id: String in SimAvianLife.sorted_keys(world.construction.projects):
		if not world.construction.has_capability(id, "storage"):
			continue
		var project: Dictionary = world.construction.projects[id]
		var cell: Vector2i = SimRouteTravel.cell(project.cell)
		if not world.construction.can_observe("player", cell) or fog != null and not fog.is_cell_visible(cell):
			continue
		rows.append({"label": "%s · %d,%d" % [str(world.construction.definitions.types[project.type].label), cell.x, cell.y], "reference": {"region": world.construction.definitions.site.region, "container": id + ":contents"}})
	panel.set_haul_endpoints(rows, int(world._content.local_actions.hauling.max_units))


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
		var result: Dictionary = adapter.request_player_command("cancel")
		if not result.ok or result.queued:
			return _result(bool(result.ok), str(result.line))
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
	var adapter: WorldContinuityRuntime = runtime()
	if panel == null or adapter == null or adapter.world_sim == null:
		return
	# Command acknowledgements are presentation state. Publish them even while
	# the last complete activity/inventory projection must remain unchanged.
	panel.update_notice(_last_line)
	if adapter.world_sim.settlement != null and adapter.world_sim.settlement.is_pending():
		return
	var world: RegionalSimulation = adapter.world_sim
	var old_world: RegionalSimulation = _care_world.get_ref() if _care_world != null else null
	if old_world != world:
		if old_world != null and old_world.action_finished.is_connected(_plant_action_finished):
			old_world.action_finished.disconnect(_plant_action_finished)
		world.action_finished.connect(_plant_action_finished)
		_care_world = weakref(world)
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
	var execution: Dictionary = world.describe_actor_action("player")
	if bool(execution.ok):
		var labels: Dictionary = {"plants": "处理草木", "construction": "营造", "facility_use": "使用家具", "clothing": "整理衣物", "health": "查看与处理伤势", "private_exchange": "交接器物", "conflicts": "交锋", "sparring": "切磋", "capability_practice": "亲身练习"}
		activity = str(conversation.line) if bool(conversation.busy) else str(labels.get(execution.domain, adapter.player_goal()))
		phase = str(execution.phase)
		remaining = ceili(float(execution.remaining_ms) / 1000.0)
		seconds = true
		busy = true
	if not adapter.player_journey.is_empty():
		activity = "正在前往%s" % adapter._journey_label(str(adapter.player_journey.destination))
		phase = "travel"
		remaining = ceili(float(int(adapter.player_journey.due_ms) - world.elapsed_ms) / 60000.0)
		seconds = false
		busy = true
	panel.update_view(label, activity, "\n".join(details), _last_line, not region.is_empty())
	panel.set_home_work_available(region == "home")
	panel.set_resource_work(adapter._home.simulation.config, adapter._home.simulation.land_resources, adapter._home.visible_resource_sources(adapter._home.simulation), int(world.plants.definitions.action_ms))
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


func _plant_action_finished(outcome: Dictionary) -> void:
	if outcome.get("domain") != "plants" or outcome.get("actor") != "player" or outcome.get("intent") != "water":
		return
	_last_line = "已用随身私水照料药丛；药草仍须随水土与时令慢慢生长。" if outcome.status == "completed" else "照料已中断；已耗工时不会退回，水按实际回执结算。"
