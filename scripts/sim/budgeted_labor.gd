class_name SimBudgetedLabor
extends RefCounted
## Funded promises refer to original native actions, stock and appointments.
## No second body, work timer, material quantity or wallet lives here.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/labor_schema.gd")
var definitions: Dictionary = {}
var contracts: Dictionary = {}
var next_id: int = 1
var _by_actor: Dictionary = {}
var _owner: WeakRef
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "max_contracts", "deadline_ms", "claim_minutes", "cash_container", "coin", "permission", "offers"]) or data.version != 1 or not Shape.count(data.max_contracts, 1, 4096) or not Shape.count(data.deadline_ms, 60000, 86400000) or not Shape.count(data.claim_minutes, 1, 60) or data.cash_container != "records" or data.coin != "coin" or data.permission != "pay" or not data.offers is Dictionary or data.offers.is_empty():
		return false
	for id: Variant in data.offers:
		var offer: Variant = data.offers[id]
		if not SimInventory._nonempty(id) or not Shape.keys(offer, ["label", "action", "coins"]) or not SimInventory._nonempty(offer.label) or offer.action != id or not Shape.count(offer.coins, 1, 1000):
			return false
	return true


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules):
		return false
	for sim: VillageSimulation in authority.regions.values():
		for offer: Dictionary in rules.offers.values():
			var action: Dictionary = sim.config.actions.get(offer.action, {})
			if action.get("kind") != "haul" or not sim.places.has(rules.cash_container) or not sim.inventory.containers.has(rules.cash_container):
				return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func accept(actor: String, region: String, issuer: String, offer: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms:
		return reply(false, "先等世界事务结算完，再当面商量。")
	return _accept(actor, region, issuer, offer)


func accept_autonomous(actor: String, region: String, issuer: String, offer: String) -> Dictionary:
	if not world.autonomous_decision(actor):
		return reply(false, "只有本人当下的自主决策才能提出这项差事。")
	return _accept(actor, region, issuer, offer)


func _accept(actor: String, region: String, issuer: String, offer: String) -> Dictionary:
	if not world.regions.has(region) or not definitions.offers.has(offer):
		return reply(false, "没有这种现金差事。")
	var sim: VillageSimulation = world.regions[region]
	if not sim.has_actor(actor) or not sim.has_actor(issuer) or actor == issuer:
		return reply(false, "这项差事需要当地本人当面商量。")
	world.synchronize_region(region)
	var office: String = sim.institutions._office_for_permission(str(sim.config.institution.id), issuer, str(definitions.permission))
	if office.is_empty():
		return reply(false, "对方没有当前的公库付款权限，交情不能代替任职。")
	if not _near(sim, actor, issuer):
		return reply(false, "先到能签下工钱的管事身边，当面商量。")
	if _by_actor.has(actor):
		var old: Dictionary = contracts[_by_actor[actor]]
		return reply(old.offer == offer and old.region == region, "你已有一笔尚未结清的现金差事；重复商量不会再次留钱。", str(old.id))
	if contracts.size() >= int(definitions.max_contracts):
		return reply(false, "现有差事记录已满，暂不再签新约。")
	if not world.native_action_allowed(actor) or not sim.actor_state(actor).active.is_empty() or not world.standing_work.duty_for(actor, world.elapsed_ms).is_empty():
		return reply(false, "先处理手头事务或已有的照看安排，再承接现金差事。")
	var terms: Dictionary = definitions.offers[offer]
	var task: Dictionary = sim.config.actions[terms.action]
	if not SimEntrustedGoods.find(sim.inventory, actor, str(terms.action), str(task.item), int(task.amount)).is_empty():
		return reply(false, "原公差已经领出的那一批要先处理；不能事后改作有薪劳动。")
	var belief: Dictionary = sim.stock_understanding(issuer, str(task.target), str(task.item))
	if not bool(belief.known) or int(belief.amount) + _promised(region, str(task.target), str(task.item), int(belief.at)) >= int(task.stock_below):
		return reply(false, "按管事掌握的消息，这处供给没有尚待安排的缺口；可以先核对情况。")
	if sim.inventory.available(str(definitions.cash_container), str(definitions.coin)) < int(terms.coins):
		return reply(false, "公库眼下没有足够的可用工钱，不能空口雇人。")
	# Begin only the original action. It reserves material but never spends cash.
	if not sim.submit_action(actor, str(terms.action)):
		return reply(false, "眼下取不到这一批材料或道路不通，差事没有成立。")
	var id: String = "labor:" + str(next_id)
	var candidate := SimInventory.new()
	if not candidate.restore(sim.inventory.to_dict()) or not candidate.create_container(id, {}) or not candidate.transfer(id + ":fund", str(definitions.cash_container), id, str(definitions.coin), int(terms.coins)):
		sim.cancel_action(actor, "funding_failed")
		world.invalidate_region(region)
		return reply(false, "工钱没有实际留出，差事没有成立。")
	_commit(sim.inventory, candidate, [str(definitions.cash_container), id])
	next_id += 1
	var basis: Dictionary = {"amount": int(belief.amount), "at": int(belief.at), "basis": belief.basis, "source": belief.source, "event": belief.event}
	var note: Dictionary = {"id": id, "actor": actor, "region": region, "issuer": issuer, "office": office, "offer": offer,
		"signed_ms": world.elapsed_ms, "until_ms": world.elapsed_ms + int(definitions.deadline_ms),
		"basis": basis, "status": "paused", "terminal_ms": -1, "attempts": [], "agreement": "", "end_event": "", "payment_job": "", "payer": ""}
	contracts[id] = note
	_by_actor[actor] = id
	note.agreement = sim.observe("labor_agreed", issuer, actor, {"participants": {"contract": id, "offer": offer, "coins": int(terms.coins), "basis": basis.duplicate(true), "until_ms": note.until_ms, "office": office}})
	native_event("start", actor, sim.actor_state(actor).active)
	world.invalidate_region(region)
	return reply(true, "工钱已从公库实际留出。先取料送达，再当面请求验收；本趟不另记贡献。", id)


func _promised(region: String, target: String, item: String, since: int) -> int:
	var amount: int = 0
	for note: Dictionary in contracts.values():
		if note.region != region or note.status in ["cancelled", "expired"]:
			continue
		var task: Dictionary = world.regions[region].config.actions[definitions.offers[note.offer].action]
		if task.target != target or task.item != item:
			continue
		var delivered: int = _delivered_ms(note)
		# Include deliveries in the same minute as a coarse observation; a fresh
		# later observation is needed before the old deficit can issue new work.
		if delivered < 0 or delivered >= since * 60000:
			amount += int(task.amount)
	return amount


func native_event(stage: String, actor: String, action: Dictionary, event: String = "") -> String:
	if not _by_actor.has(actor):
		return ""
	var note: Dictionary = contracts[_by_actor[actor]]
	var sim: VillageSimulation = world.regions[note.region]
	if action.action != definitions.offers[note.offer].action:
		return ""
	if stage == "start" and note.status == "paused" and sim.elapsed_ms < int(note.until_ms):
		note.status = "working"
		note.attempts.append({"action": action.id, "started_ms": sim.elapsed_ms, "ended_ms": -1, "event": "", "succeeded": false})
	if note.status != "working" or note.attempts.is_empty() or note.attempts.back().action != action.id:
		return ""
	if stage in ["finish", "fail"]:
		var attempt: Dictionary = note.attempts.back()
		attempt.ended_ms = sim.elapsed_ms
		attempt.event = event
		attempt.succeeded = stage == "finish"
		note.status = "payable" if stage == "finish" else "paused"
	return str(note.id)


func resume(actor: String, id: String) -> Dictionary:
	if not contracts.has(id) or contracts[id].actor != actor or contracts[id].status != "paused":
		return reply(false, "没有本人可以续做的未交付差事。")
	var note: Dictionary = contracts[id]
	if world.elapsed_ms >= int(note.until_ms):
		return reply(false, "这笔差事已过期限，先等工钱退回公库。", id)
	var sim: VillageSimulation = world.regions[note.region]
	if not sim.submit_action(actor, str(definitions.offers[note.offer].action)):
		return reply(false, "眼下有别的事务、材料不足或道路不通，尚未续做。", id)
	world.invalidate_region(str(note.region))
	return reply(true, "续做原差事，原工钱仍在专款中；已有受托材料继续送达。", id)


func abandon(actor: String, id: String) -> Dictionary:
	if not contracts.has(id) or contracts[id].actor != actor or contracts[id].status not in ["working", "paused"]:
		return reply(false, "只有本人尚未交付的现金差事可以放弃。")
	_end(contracts[id], "cancelled", world.elapsed_ms)
	return reply(true, "已放弃差事，未挣得的工钱不归本人；随身受托物仍须实际交回。", id)


func _end(note: Dictionary, status: String, now: int) -> void:
	var sim: VillageSimulation = world.regions[note.region]
	world.synchronize_region(str(note.region))
	var action: Dictionary = sim.actor_state(note.actor).active
	if not action.is_empty() and note.status == "working" and action.id == note.attempts.back().action:
		sim.cancel_action(str(note.actor), status)
	note.status = status
	note.terminal_ms = now
	note.end_event = sim.observe("labor_ended", str(note.actor), "", {"private": {"contract": note.id, "status": status}})
	_by_actor.erase(note.actor)
	_refund(note)
	world.invalidate_region(str(note.region))


func _refund(note: Dictionary) -> void:
	var sim: VillageSimulation = world.regions[note.region]
	var id: String = str(note.id) + ":refund"
	if not sim.inventory.operations.has(id):
		sim.inventory.transfer(id, str(note.id), str(definitions.cash_container), str(definitions.coin), int(definitions.offers[note.offer].coins))


func next_boundary_ms() -> int:
	var result: int = 0x3fffffffffffffff
	for id: String in _by_actor.values():
		if contracts[id].status in ["working", "paused"]:
			result = mini(result, int(contracts[id].until_ms))
	return maxi(world.elapsed_ms + 1, result)


func settle_at_ms(now: int) -> void:
	for id: String in _by_actor.values().duplicate():
		var note: Dictionary = contracts[id]
		if note.status in ["working", "paused"] and now >= int(note.until_ms):
			_end(note, "expired", int(note.until_ms))
	for note: Dictionary in contracts.values():
		if note.status in ["cancelled", "expired"]:
			_refund(note)


static func claim_spec(authority: RefCounted, region: String, options: Dictionary) -> Dictionary:
	var rules: Dictionary = authority._content.budgeted_labor
	if not Shape.keys(options, ["contract", "issuer", "office"]) or not SimInventory._nonempty(options.contract) or not authority.regions.has(region):
		return {}
	var sim: VillageSimulation = authority.regions[region]
	if not sim.has_actor(options.issuer) or not sim.institutions.institutions[sim.config.institution.id].offices.has(options.office) or not sim.institutions.institutions[sim.config.institution.id].offices[options.office].permissions.has(rules.permission):
		return {}
	return {"place": rules.cash_container, "minutes": int(rules.claim_minutes), "label": "验收已交付的现金差事"}


func request_claim(actor: String, id: String, issuer: String) -> Dictionary:
	if not contracts.has(id) or contracts[id].actor != actor or contracts[id].status != "payable":
		return reply(false, "没有本人的已交付待验工钱；已领过的不能再领。")
	var note: Dictionary = contracts[id]
	var sim: VillageSimulation = world.regions[note.region]
	var office: String = sim.institutions._office_for_permission(str(sim.config.institution.id), issuer, str(definitions.permission))
	if office.is_empty() or not _near(sim, actor, issuer):
		return reply(false, "需要当面向目前有公库付款权的人提出验收。", id)
	return world.services.begin(actor, str(note.region), "claim_wage", {"contract": id, "issuer": issuer, "office": office})


func settle_claim(job: Dictionary) -> Dictionary:
	var id: String = str(job.options.contract)
	if not contracts.has(id) or contracts[id].actor != job.actor or contracts[id].region != job.region or contracts[id].status != "payable":
		return reply(false, "这笔工钱尚未交付待验，或已经结清。")
	var note: Dictionary = contracts[id]
	var sim: VillageSimulation = world.regions[note.region]
	var office: Dictionary = sim.institutions.institutions[sim.config.institution.id].offices[job.options.office]
	if not sim.actor_state(job.options.issuer).alive or office.holder != job.options.issuer or not office.permissions.has(definitions.permission):
		return reply(false, "验收签发人已不能代表公库；工钱仍在专款中，可另找现任办理。", id)
	if job.status != "active" or job.phase != "work" or world.elapsed_ms < int(job.due_ms) or SimRouteTravel.cell(sim.actor_state(job.actor).cell) != SimRouteTravel.cell(sim.places[definitions.cash_container].cell):
		return reply(false, "尚未实际到功德堂办完验收。", id)
	var candidate := SimInventory.new()
	if not candidate.restore(sim.inventory.to_dict()) or not candidate.transfer(id + ":payment", id, "actor:" + str(job.actor), str(definitions.coin), int(definitions.offers[note.offer].coins)):
		return reply(false, "专款或行囊空间暂不可用，未扣除任何工钱。", id)
	_commit(sim.inventory, candidate, [id, "actor:" + str(job.actor)])
	note.status = "paid"
	note.terminal_ms = world.elapsed_ms
	note.payment_job = job.id
	note.payer = job.options.issuer
	_by_actor.erase(note.actor)
	world.invalidate_region(str(note.region))
	return reply(true, "交付已验收，%d钱从原专款放入行囊；本趟没有重复记贡献。" % int(definitions.offers[note.offer].coins), id)


func _near(sim: VillageSimulation, actor: String, issuer: String) -> bool:
	return bool(sim.actor_state(actor).alive) and bool(sim.actor_state(issuer).alive) and world.actor_controls(actor, "communication") and world.actor_controls(issuer, "communication") and sim._distance(actor, issuer) <= float(world._content.interaction_requests.communication_cells)


static func _delivered_ms(note: Dictionary) -> int:
	return int(note.attempts.back().ended_ms) if not note.attempts.is_empty() and bool(note.attempts.back().succeeded) else -1


static func _commit(inventory: SimInventory, candidate: SimInventory, changed: Array[String]) -> void:
	inventory.containers = candidate.containers
	inventory.reservations = candidate.reservations
	inventory.operations = candidate.operations
	inventory.custody = candidate.custody
	for container: String in changed:
		inventory.contents_changed.emit(container)


func describe(actor: String, id: String) -> Dictionary:
	if not contracts.has(id) or contracts[id].actor != actor:
		return reply(false, "这不是本人签下的现金差事。")
	var note: Dictionary = contracts[id]
	var line: String = {"working": "正在按原约定取料送达，工钱尚未入包。", "paused": "本趟已停下，可续做或放弃；原工钱仍留存。", "payable": "你已实际交付，仍须找现任管事验收领钱。", "paid": "本趟工钱已实际领到，不能重复结算。", "cancelled": "你已放弃；受托物仍按原保管责任处理。", "expired": "原交付期限已过；未挣得的工钱不归本人。"}[note.status]
	return reply(true, str(definitions.offers[note.offer].label) + "：" + line, id)


func latest_for(actor: String) -> String:
	if _by_actor.has(actor):
		return str(_by_actor[actor])
	var latest: String = ""
	for note: Dictionary in contracts.values():
		if note.actor == actor and (latest.is_empty() or int(str(note.id).get_slice(":", 1)) > int(latest.get_slice(":", 1))):
			latest = str(note.id)
	return latest


static func reply(ok: bool, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "line": line, "id": id}


func to_dict() -> Dictionary:
	return {"version": 1, "contracts": contracts.duplicate(true), "next_id": next_id}


static func empty_state() -> Dictionary:
	return {"version": 1, "contracts": {}, "next_id": 1}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, self):
		return false
	contracts = data.contracts.duplicate(true)
	next_id = int(data.next_id)
	_by_actor.clear()
	for note: Dictionary in contracts.values():
		if note.status in ["working", "paused", "payable"]:
			_by_actor[note.actor] = note.id
	return true
