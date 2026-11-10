extends RefCounted
## Cross-check original material, social, cash and service records before swap.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func inventory_scope(data: Variant, region: String) -> Dictionary:
	var scope: Dictionary = {"containers": {}, "operations": {}, "reservations": {}}
	if not data is Dictionary or not data.get("contracts") is Dictionary:
		return scope
	for id: Variant in data.contracts:
		var note: Variant = data.contracts[id]
		if not id is String or not note is Dictionary or note.get("region") != region:
			continue
		scope.containers[id] = true
		for suffix: String in [":fund", ":payment", ":refund"]:
			scope.operations[id + suffix] = true
	return scope


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "contracts", "next_id"]) or data.version != 1 or not data.contracts is Dictionary or data.contracts.size() > int(domain.definitions.max_contracts) or not Shape.count(data.next_id, 1, SimInventory.MAX_COUNT):
		return false
	var workers: Dictionary = {}
	var attempts: Dictionary = {}
	var events: Dictionary = {}
	for id: Variant in data.contracts:
		var note: Variant = data.contracts[id]
		if not _allocated(id, "labor:", int(data.next_id)) or not _contract(note, str(id), domain, attempts, events):
			return false
		if note.status in ["working", "paused", "payable"]:
			if workers.has(note.actor):
				return false
			workers[note.actor] = true
	for region: String in domain.world.regions:
		var sim: VillageSimulation = domain.world.regions[region]
		for event: Dictionary in sim.social.events:
			if event.kind == "labor_agreed" or event.kind == "labor_ended":
				if not events.has(region + ":" + str(event.id)):
					return false
			if event.details.get("public", {}).has("labor") and not events.has(region + ":" + str(event.id)):
				return false
	if domain.world.services != null:
		for job: Dictionary in domain.world.services.jobs.values():
			if job.kind != "claim_wage":
				continue
			var note: Dictionary = data.contracts.get(job.options.contract, {})
			if note.is_empty() or note.actor != job.actor or note.region != job.region or job.started_ms < SimBudgetedLabor._delivered_ms(note):
				return false
			if job.status == "completed" and (note.status != "paid" or note.payment_job != job.id):
				return false
			if job.status == "active" and note.status != "payable":
				return false
	return true


static func _contract(note: Variant, id: String, domain: RefCounted, attempts: Dictionary, events: Dictionary) -> bool:
	var world: RefCounted = domain.world
	if not Shape.keys(note, ["id", "actor", "region", "issuer", "office", "offer", "signed_ms", "until_ms", "basis", "status", "terminal_ms", "attempts", "agreement", "end_event", "payment_job", "payer"]) or note.id != id or not world.regions.has(note.region) or not domain.definitions.offers.has(note.offer) or note.status not in ["working", "paused", "payable", "paid", "cancelled", "expired"]:
		return false
	var sim: VillageSimulation = world.regions[note.region]
	var offices: Dictionary = sim.institutions.institutions[sim.config.institution.id].offices
	if not sim.has_actor(note.actor) or not sim.has_actor(note.issuer) or note.actor == note.issuer or not offices.has(note.office) or not offices[note.office].permissions.has(domain.definitions.permission) or not Shape.count(note.signed_ms, 0, world.elapsed_ms) or not Shape.count(note.until_ms, int(note.signed_ms), SimInventory.MAX_COUNT) or int(note.until_ms) - int(note.signed_ms) != int(domain.definitions.deadline_ms) or not note.attempts is Array or note.attempts.is_empty():
		return false
	var task: Dictionary = sim.config.actions[domain.definitions.offers[note.offer].action]
	var coins: int = int(domain.definitions.offers[note.offer].coins)
	if not _basis(note, sim, task):
		return false
	var agreement: Dictionary = sim.social._event_by_id.get(note.agreement, {})
	var details: Dictionary = {"contract": id, "offer": note.offer, "coins": coins, "basis": note.basis, "until_ms": note.until_ms, "office": note.office}
	if agreement.get("kind") != "labor_agreed" or agreement.get("actor") != note.issuer or agreement.get("target") != note.actor or agreement.get("tick") != floori(float(note.signed_ms) / 60000.0) or not Shape.same_record(agreement.details.get("participants"), details):
		return false
	events[str(note.region) + ":" + str(note.agreement)] = true
	var previous: int = int(note.signed_ms)
	var succeeded: bool = false
	for index: int in note.attempts.size():
		var attempt: Variant = note.attempts[index]
		if not Shape.keys(attempt, ["action", "started_ms", "ended_ms", "event", "succeeded"]) or not _allocated(attempt.action, "action:", sim._next_id) or not Shape.count(attempt.started_ms, previous, mini(world.elapsed_ms, int(note.until_ms) - 1)) or not attempt.succeeded is bool or succeeded:
			return false
		var key: String = str(note.region) + ":" + str(attempt.action)
		if attempts.has(key):
			return false
		attempts[key] = true
		var active: Dictionary = sim.synchronize_actors()[note.actor].active
		if attempt.ended_ms == -1:
			if note.status != "working" or index != note.attempts.size() - 1 or attempt.succeeded or attempt.event != "" or active.get("id") != attempt.action or active.get("action") != task_id(domain, note) or active.get("started_ms") != attempt.started_ms:
				return false
		else:
			if not Shape.count(attempt.ended_ms, int(attempt.started_ms), mini(world.elapsed_ms, int(note.until_ms))) or active.get("id") == attempt.action:
				return false
			var event: Dictionary = sim.social._event_by_id.get(attempt.event, {})
			if event.get("kind") != ("completed" if attempt.succeeded else "interrupted") or event.get("actor") != note.actor or event.get("tick") != floori(float(attempt.ended_ms) / 60000.0) or event.details.get("task") != task_id(domain, note) or event.details.get("public", {}).get("work_credit") != 0 or event.details.get("public", {}).get("labor") != id or event.details.get("private", {}).get("action_id") != attempt.action:
				return false
			var event_key: String = str(note.region) + ":" + str(attempt.event)
			if events.has(event_key):
				return false
			events[event_key] = true
			previous = int(attempt.ended_ms)
			succeeded = bool(attempt.succeeded)
			var delivery: Variant = sim.inventory.operations.get(str(attempt.action) + ":delivery")
			if succeeded != (delivery != null) or succeeded and not Shape.same_record(delivery, _transfer("actor:" + str(note.actor), str(task.target), str(task.item), int(task.amount))):
				return false
	if (note.status in ["payable", "paid"]) != succeeded or note.status == "working" and note.attempts.back().ended_ms != -1:
		return false
	if note.status in ["working", "paused"] and int(note.until_ms) <= world.elapsed_ms:
		return false
	var inventory: SimInventory = sim.inventory
	if not inventory.containers.has(id) or not Shape.same_record(inventory.operations.get(id + ":fund"), _transfer(str(domain.definitions.cash_container), id, str(domain.definitions.coin), coins)):
		return false
	var refunded: bool = inventory.operations.has(id + ":refund")
	var paid: bool = inventory.operations.has(id + ":payment")
	if paid != (note.status == "paid") or refunded and note.status not in ["cancelled", "expired"]:
		return false
	var held: Dictionary = {str(domain.definitions.coin): 0 if paid or refunded else coins}
	if not Shape.same_record(inventory.containers[id], held):
		return false
	if refunded and not Shape.same_record(inventory.operations[id + ":refund"], _transfer(id, str(domain.definitions.cash_container), str(domain.definitions.coin), coins)):
		return false
	if paid:
		if not Shape.same_record(inventory.operations[id + ":payment"], _transfer(id, "actor:" + str(note.actor), str(domain.definitions.coin), coins)) or world.services == null or not world.services.jobs.has(note.payment_job):
			return false
		var job: Dictionary = world.services.jobs[note.payment_job]
		if job.kind != "claim_wage" or job.status != "completed" or job.options.contract != id or job.actor != note.actor or job.region != note.region or job.options.issuer != note.payer or not Shape.count(note.terminal_ms, previous, world.elapsed_ms) or job.finished_at != floori(float(note.terminal_ms) / 60000.0):
			return false
	elif note.payment_job != "" or note.payer != "":
		return false
	if note.status in ["cancelled", "expired"]:
		if not Shape.count(note.terminal_ms, previous, mini(world.elapsed_ms, int(note.until_ms))) or note.status == "expired" and note.terminal_ms != note.until_ms:
			return false
		var ended: Dictionary = sim.social._event_by_id.get(note.end_event, {})
		if ended.get("kind") != "labor_ended" or ended.get("actor") != note.actor or ended.get("tick") != floori(float(note.terminal_ms) / 60000.0) or not Shape.same_record(ended.details.get("private"), {"contract": id, "status": note.status}):
			return false
		events[str(note.region) + ":" + str(note.end_event)] = true
	elif note.end_event != "" or note.status != "paid" and note.terminal_ms != -1:
		return false
	return true


static func _basis(note: Dictionary, sim: VillageSimulation, task: Dictionary) -> bool:
	var basis: Variant = note.basis
	if not Shape.keys(basis, ["amount", "at", "basis", "source", "event"]) or not Shape.count(basis.amount, 0, int(task.stock_below) - 1) or not Shape.count(basis.at, 0, floori(float(note.signed_ms) / 60000.0)) or not sim.has_actor(basis.source):
		return false
	if basis.basis == "observed":
		return basis.source == note.issuer and basis.event == ""
	if basis.basis != "said":
		return false
	var event: Dictionary = sim.social._event_by_id.get(basis.event, {})
	return event.get("kind") == "stock_statement" and event.get("tick") == basis.at and event.details.get("participants", {}).get("location") == task.target and event.details.get("participants", {}).get("item") == task.item and event.details.get("participants", {}).get("amount") == basis.amount and sim.social.knowledge[note.issuer].has(basis.event)


static func task_id(domain: RefCounted, note: Dictionary) -> String:
	return str(domain.definitions.offers[note.offer].action)


static func _allocated(id: Variant, prefix: String, limit: int) -> bool:
	if not id is String or not id.begins_with(prefix):
		return false
	var raw: String = id.trim_prefix(prefix)
	return raw.is_valid_int() and str(int(raw)) == raw and int(raw) >= 1 and int(raw) < limit


static func _transfer(source: String, target: String, item: String, amount: int) -> Dictionary:
	return {"kind": "transfer", "source": source, "target": target, "item": item, "amount": amount, "reservation_id": ""}
