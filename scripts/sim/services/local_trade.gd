extends RefCounted
## Institutional standing offers. Quotes authorize a timed visit; only the
## final two-sided commit moves real goods/money in the original inventories.

const Shape = preload("res://scripts/sim/avian_schema.gd")
var _owner: WeakRef
var services: RefCounted:
	get:
		return _owner.get_ref()


func _init(owner: RefCounted) -> void:
	_owner = weakref(owner)


static func valid_definitions(data: Variant, world: RefCounted = null) -> bool:
	if not Shape.keys(data, ["minutes", "max_lots", "cash_container", "permission", "offers"]) or not Shape.count(data.minutes, 1, 60) or not Shape.count(data.max_lots, 1, 100) or data.cash_container != "records" or data.permission != "pay" or not data.offers is Dictionary or data.offers.is_empty():
		return false
	for id: Variant in data.offers:
		var offer: Variant = data.offers[id]
		if not SimInventory._nonempty(id) or not Shape.keys(offer, ["label", "direction", "place", "item", "amount", "coins", "stock_limit"]) or not SimInventory._nonempty(offer.label) or offer.direction not in ["buy", "sell"] or not SimInventory._nonempty(offer.item) or offer.item == "coin" or not Shape.count(offer.amount, 1, 1000) or not Shape.count(offer.coins, 1, 1000) or not Shape.count(offer.stock_limit, 0, 1000000):
			return false
		for sim: RefCounted in ([] if world == null else world.regions.values()):
			if not sim.places.has(offer.place) or not sim.inventory.containers.has(offer.place) or not sim.inventory.containers.has(data.cash_container):
				return false
	return true


func spec_for(region: String, options: Dictionary) -> Dictionary:
	var world: RefCounted = services.world
	var rules: Dictionary = services.definitions.trade
	if not Shape.keys(options, ["offer", "lots", "issuer", "office"]) or not rules.offers.has(options.offer) or not Shape.count(options.lots, 1, int(rules.max_lots)) or not world.regions.has(region):
		return {}
	var sim: RefCounted = world.regions[region]
	if not sim.has_actor(options.issuer) or not sim.institutions.institutions[sim.config.institution.id].offices.has(options.office):
		return {}
	var office: Dictionary = sim.institutions.institutions[sim.config.institution.id].offices[options.office]
	if not office.permissions.has(rules.permission):
		return {}
	var offer: Dictionary = rules.offers[options.offer]
	var label: String = "%s · %d份" % [str(offer.label), int(options.lots)]
	return {"ok": true, "reason": "ready", "line": label, "place": offer.place,
		"minutes": int(rules.minutes), "label": label, "options": options.duplicate(true)}


func prepare(actor: String, region: String, options: Dictionary) -> Dictionary:
	var spec: Dictionary = spec_for(region, options)
	if spec.is_empty():
		return services.response(false, "invalid_terms", "请说明常备买卖的货类、份数和签发人，暂不接受额外条款。")
	var world: RefCounted = services.world
	var sim: RefCounted = world.regions[region]
	var home: String = services.actor_home(actor)
	var issuer: Dictionary = sim.actor_state(options.issuer)
	if not issuer.alive or sim.institutions.institutions[sim.config.institution.id].offices[options.office].holder != options.issuer or not world.actor_controls(str(options.issuer), "communication"):
		return services.response(false, "no_authority", "对方没有当前可用的公库付款权限，不能替当地许下这笔买卖。")
	var buyer: Dictionary = world.regions[home].actor_state(actor)
	if actor == options.issuer or SimRouteTravel.cell(buyer.cell).distance_to(SimRouteTravel.cell(issuer.cell)) > float(world._content.interaction_requests.communication_cells):
		return services.response(false, "unheard", "先到有权办此事的人身边当面商量。")
	# A standing policy is a quote, never an omniscient live-stock guarantee.
	return spec


func authorize(actor: String, region: String, issuer: String, offer: String, lots: Variant) -> Dictionary:
	if not services.world.regions.has(region):
		return services.response(false, "no_authority", "这里没有可替公库签这件事的人。")
	var sim: RefCounted = services.world.regions[region]
	var office: String = sim.institutions._office_for_permission(str(sim.config.institution.id), issuer, str(services.definitions.trade.permission))
	if office.is_empty():
		return services.response(false, "no_authority", "对方没有当地公库付款权限；交情不能代替任职。")
	return services.begin(actor, region, "trade", {"offer": offer, "lots": lots, "issuer": issuer, "office": office})


func legs(job: Dictionary) -> Dictionary:
	var offer: Dictionary = services.definitions.trade.offers[job.options.offer]
	var lots: int = int(job.options.lots)
	var bag: String = "actor:" + str(job.actor)
	var cash: String = str(services.definitions.trade.cash_container)
	var goods: Dictionary = {"from": job.region, "source": offer.place, "to": job.home, "target": bag, "item": offer.item, "amount": int(offer.amount) * lots}
	var money: Dictionary = {"from": job.home, "source": bag, "to": job.region, "target": cash, "item": services.definitions.coin_item, "amount": int(offer.coins) * lots}
	if offer.direction == "sell":
		goods = {"from": job.home, "source": bag, "to": job.region, "target": offer.place, "item": offer.item, "amount": int(offer.amount) * lots}
		money = {"from": job.region, "source": cash, "to": job.home, "target": bag, "item": services.definitions.coin_item, "amount": int(offer.coins) * lots}
	return {"goods": goods, "money": money}


func _can_transfer(leg: Dictionary) -> bool:
	var source: SimInventory = services.world.regions[leg.from].inventory
	var target: SimInventory = services.world.regions[leg.to].inventory
	return source.available(str(leg.source), str(leg.item)) >= int(leg.amount) and int(leg.amount) <= SimInventory.MAX_COUNT - target.quantity(str(leg.target), str(leg.item))


func settle(job: Dictionary) -> Dictionary:
	var pair: Dictionary = legs(job)
	var goods_id: String = str(job.id) + ":trade_goods"
	var money_id: String = str(job.id) + ":trade_money"
	if services.operations.has(goods_id) or services.operations.has(money_id):
		var same: bool = services.Schema.same_value(services.operations.get(goods_id), pair.goods) and services.Schema.same_value(services.operations.get(money_id), pair.money)
		return services.response(same, "already_settled", "本笔已经实际交割，不能再次付款或取货。")
	var world: RefCounted = services.world
	if job.status != "active" or job.phase != "work" or world.elapsed_ms < int(job.due_ms):
		return services.response(false, "not_finished", "尚未在交货点完成清点，钱货都还没有转移。")
	world.synchronize_region(str(job.home))
	world.synchronize_region(str(job.region))
	var local: RefCounted = world.regions[job.region]
	var actor: Dictionary = world.regions[job.home].actor_state(job.actor)
	if not actor.alive or not world.actor_controls(str(job.actor), "action") or not world.actor_controls(str(job.actor), "motion") or SimRouteTravel.cell(actor.cell) != SimRouteTravel.cell(local.places[job.spec.place].cell):
		return services.response(false, "not_present", "没有实际到交货点办完这件事，钱货仍在原处。")
	var office: Dictionary = local.institutions.institutions[local.config.institution.id].offices[job.options.office]
	if not local.actor_state(job.options.issuer).alive or office.holder != job.options.issuer or not office.permissions.has(services.definitions.trade.permission):
		return services.response(false, "mandate_lost", "签发人已不能代表公库；钱货都还在原处，这次没有成交。")
	var offer: Dictionary = services.definitions.trade.offers[job.options.offer]
	var stock: int = local.inventory.quantity(str(offer.place), str(offer.item))
	if offer.direction == "sell" and int(pair.goods.amount) > int(offer.stock_limit) - stock:
		return services.response(false, "no_demand", "清点时当地已不缺这一批，暂不再收；钱货都没有转移。")
	if offer.direction == "buy" and local.inventory.available(str(offer.place), str(offer.item)) - int(pair.goods.amount) < int(offer.stock_limit):
		return services.response(false, "stock_missing", "清点时可售现货不足，还要留下当地用量；钱货都没有转移。")
	if not _can_transfer(pair.goods) or not _can_transfer(pair.money):
		return services.response(false, "resources_missing", "清点时钱、货或可用空间不足；没有先扣一方的钱货。")
	# Both disjoint item legs and operation IDs were preflighted. No await,
	# callbacks or external mutation occurs between these two inventory writes.
	for key: String in ["goods", "money"]:
		var leg: Dictionary = pair[key]
		services.transfer(str(job.id) + ":trade_" + key, str(leg.from), str(leg.source), str(leg.to), str(leg.target), str(leg.item), int(leg.amount))
	return services.response(true, "traded", "钱货已经当场交割；所得已放入行囊。" + ("现饭要吃时再取用。" if offer.direction == "buy" and offer.item == "meal" else ""))


func valid_history(job: Dictionary, data: Dictionary) -> bool:
	var pair: Dictionary = legs(job)
	for key: String in ["goods", "money"]:
		var id: String = str(job.id) + ":trade_" + key
		if job.status == "completed":
			if not services.Schema.same_value(data.operations.get(id), pair[key]):
				return false
		elif data.operations.has(id):
			return false
	return not bool(job.carrying)
