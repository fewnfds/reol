extends RefCounted
## Counter services commit institutional recognition separately from delivery.

var _owner: WeakRef
var services: RefCounted:
	get:
		return _owner.get_ref()


func _init(owner: RefCounted) -> void:
	_owner = weakref(owner)


func prepare(_actor_id: String, _region_id: String, kind: String, options: Dictionary) -> Dictionary:
	var spec: Dictionary = spec_for(kind, options)
	if spec.is_empty():
		return _failure("unknown_service", "当地没有这项事务。")
	return spec


## Canonical immutable terms; snapshot validation must not depend on today's
## balance, officer location or stock after an older job has completed.
func spec_for(kind: String, options: Dictionary) -> Dictionary:
	var definitions: Dictionary = services.definitions
	var definition: Dictionary = {}
	var terms: Dictionary = options.duplicate(true)
	match kind:
		"report": definition = definitions.report
		"redeem":
			var offer: String = str(options.get("offer", ""))
			if not definitions.redemptions.has(offer):
				return {}
			definition = definitions.redemptions[offer]
		"access":
			var scope: String = str(options.get("scope", ""))
			if not definitions.access.has(scope):
				return {}
			definition = definitions.access[scope]
		_:
			return {}
	return {"ok": true, "reason": "ready", "line": str(definition.label),
		"place": str(definition.place), "minutes": int(definition.minutes),
		"label": str(definition.label), "options": terms}


func settle(job: Dictionary) -> Dictionary:
	var world: RefCounted = services.world
	var region: String = job.region
	if not world.regions.has(region) or not world.synchronize_region(region):
		return _failure("missing_region", "办理地点已经不可用。")
	var home: String = services.actor_home(job.actor)
	if home.is_empty() or not world.synchronize_region(home):
		return _failure("missing_actor", "来访者已经不可用。")
	var actor: Dictionary = world.regions[home].actors[job.actor]
	if not actor.alive:
		return _failure("actor_unavailable", "来访者无法继续办理。")
	match str(job.kind):
		"report": return _report(job)
		"redeem": return _redeem(job)
		"access": return _access(job)
	return _failure("unknown_service", "这项事务无法办理。")


func _report(job: Dictionary) -> Dictionary:
	var sim: RefCounted = services.world.regions[job.region]
	var issuer: String = services.issuer(job.region, job.actor, "record")
	if issuer.is_empty():
		return _failure("no_registrar", "没有有权记账的人在附近，请稍后再来。")
	var ids: Array = services.receipts.keys()
	ids.sort()
	var amount: int = 0
	var pending: Array = []
	for id: String in ids:
		var receipt: Dictionary = services.receipts[id]
		if receipt.actor != job.actor or receipt.region != job.region or bool(receipt.registered):
			continue
		if not services.operations.has(receipt.operation) or not services.jobs.has(receipt.job):
			return _failure("missing_evidence", "交付依据不完整，管事暂不能入账。")
		var delivery: Dictionary = services.jobs[receipt.job]
		if delivery.kind != "haul_grain" or delivery.status != "completed":
			return _failure("missing_evidence", "还没有完成实际交付。")
		var route: Dictionary = services.world.settings.routes[delivery.route]
		var transfer: Dictionary = services.operations[receipt.operation]
		if (
			receipt.operation != str(delivery.id) + ":delivery" or delivery.actor != job.actor
			or str(receipt.region) != str(services.definitions.hauling.credit_region)
			or int(receipt.amount) != int(services.definitions.hauling.credit)
			or transfer.get("from") != delivery.home or transfer.get("to") != route.to
			or transfer.get("source") != "actor:" + str(job.actor) or transfer.get("target") != route.target
			or transfer.get("item") != route.item or int(transfer.get("amount", 0)) != int(delivery.amount)
		):
			return _failure("invalid_evidence", "这份凭据与实际交货或委托条款不符。")
		if int(receipt.amount) > SimInventory.MAX_COUNT - amount:
			return _failure("account_full", "账目金额超出可记范围。")
		amount += int(receipt.amount)
		pending.append(receipt)
	if pending.is_empty():
		return _failure("nothing_to_report", "没有新的交付凭据可报，旧凭据不会重复记功。")
	if amount > SimInventory.MAX_COUNT - sim.institutions.balance(str(sim.config.institution.id), job.actor):
		return _failure("account_full", "账目金额超出可记范围。")
	# Every precondition is checked before the first posting. Nothing yields or
	# changes appointment between these synchronous ledger operations.
	for receipt: Dictionary in pending:
		if not sim.institutions.issue(str(receipt.id) + ":credit", str(sim.config.institution.id),
			issuer, job.actor, int(receipt.amount), str(receipt.id)):
			return _failure("registration_failed", "这份凭据暂时未能登记。")
		receipt.registered = true
	services.record("registered", job.actor, {"region": job.region, "issuer": issuer, "amount": amount, "job": job.id})
	return services.response(true, "registered", "管事核验交付，为你记入%d贡献。" % amount, job.id)


func _redeem(job: Dictionary) -> Dictionary:
	var offer_id: String = str(job.options.get("offer", ""))
	if not services.definitions.redemptions.has(offer_id):
		return _failure("unknown_offer", "这项兑换已不再提供。")
	var offer: Dictionary = services.definitions.redemptions[offer_id]
	var sim: RefCounted = services.world.regions[job.region]
	var issuer: String = services.issuer(job.region, job.actor, "pay")
	if issuer.is_empty():
		return _failure("no_pay_officer", "没有有权兑付的人在附近。")
	var institution: String = str(sim.config.institution.id)
	var cost: int = int(offer.cost)
	if sim.institutions.balance(institution, job.actor) < cost:
		return _failure("insufficient_credit", "当地认可的贡献不足，不能兑换。")
	var home: String = services.actor_home(job.actor)
	var bag: String = "actor:" + str(job.actor)
	var inventory: RefCounted = services.world.regions[home].inventory
	if sim.inventory.available(str(offer.source), str(offer.item)) < int(offer.amount):
		return _failure("stock_missing", "账上有功，但眼下没有实物可兑；贡献没有扣除。")
	if int(offer.amount) > SimInventory.MAX_COUNT - inventory.quantity(bag, str(offer.item)):
		return _failure("bag_full", "随身容器已满，贡献没有扣除。")
	var debit_id: String = str(job.id) + ":debit"
	var transfer_id: String = str(job.id) + ":redeem"
	if not sim.institutions.debit(debit_id, institution, issuer, job.actor, cost, str(job.id)):
		return _failure("debit_failed", "账目暂不能兑付。")
	# Quantity and signing preconditions passed in this same commit point.
	if not services.transfer(transfer_id, job.region, str(offer.source), home, bag, str(offer.item), int(offer.amount)):
		return _failure("transfer_failed", "交货未能完成。")
	services.record("redeemed", job.actor, {"region": job.region, "issuer": issuer, "cost": cost, "job": job.id})
	return services.response(true, "redeemed", "已扣%d贡献，实物放入你的行囊。" % cost, job.id)


func _access(job: Dictionary) -> Dictionary:
	var scope: String = str(job.options.get("scope", ""))
	if not services.definitions.access.has(scope):
		return _failure("unknown_scope", "这项通行申请已经失效。")
	var sim: RefCounted = services.world.regions[job.region]
	var issuer: String = services.issuer(job.region, job.actor, "authorize")
	if issuer.is_empty():
		return _failure("no_authorizer", "附近没有能作此决定的人。")
	var required: int = int(services.definitions.access[scope].required_contribution)
	if sim.institutions.balance(str(sim.config.institution.id), job.actor) < required:
		return _failure("ineligible", "管事客气地回绝了：礼数照旧，但尚不符合当地通行资格。")
	var key: String = str(job.region) + ":" + str(job.actor) + ":" + scope
	services.authorizations[key] = {"region": job.region, "actor": job.actor, "scope": scope,
		"issuer": issuer, "job": job.id, "at": services.world.current_time}
	services.record("authorized", job.actor, {"region": job.region, "issuer": issuer, "scope": scope, "job": job.id})
	return services.response(true, "authorized", "管事签下药圃通行凭据，可以凭据入圃取药。", job.id)


func _failure(reason: String, line: String) -> Dictionary:
	return services.response(false, reason, line)
