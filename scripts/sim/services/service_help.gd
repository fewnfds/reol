extends RefCounted
## One courier's accepted promise cannot be pre-empted by another request.

var _owner: WeakRef
var service: RefCounted:
	get:
		return _owner.get_ref()


func _init(owner: RefCounted) -> void:
	_owner = weakref(owner)


func ask(actor_id: String, courier_id: String, route_id: String, offer: int) -> Dictionary:
	var world: RefCounted = service.world
	var home: String = service.actor_home(actor_id)
	if home.is_empty() or not world.couriers.has(courier_id) or not world.routes.has(route_id) or offer < 0:
		return _refuse("invalid_request", "没有能够受理这件事的人。")
	if not world.actor_controls(actor_id, "communication"):
		return _refuse("cannot_communicate", "你眼下无法与对方交谈。")
	var courier: Dictionary = world.couriers[courier_id]
	if courier.route != route_id:
		return _refuse("wrong_route", "对方不承办这条路上的运输。")
	# A repeat of the accepted agreement returns the same promise, without
	# charging escrow again or interrupting its already-running journey.
	for existing: Dictionary in service.help_requests.values():
		if existing.actor == actor_id and existing.courier == courier_id and existing.route == route_id and int(existing.offer) == offer and existing.status == "accepted" and existing.execution == "pending":
			return existing.duplicate(true)
	world.synchronize_region(home)
	var actor: Dictionary = world.regions[home].actors[actor_id]
	if not actor.alive:
		return _refuse("unavailable", "你眼下无法与对方交谈。")
	var position := Vector2(float(actor.cell[0]), float(actor.cell[1]))
	if position.distance_to(world.courier_cell(courier_id)) > float(service.definitions.help.talk_radius):
		return _refuse("out_of_range", "相距太远，先走近运粮人再商量。")
	if courier.phase != "idle" or service.courier_claimed(courier_id):
		return _refuse("existing_commitment", "对方已有承诺，不能为你的请求插队。")
	if float(courier.energy) < float(service.definitions.help.rest_below):
		return _refuse("exhausted", "对方疲惫不堪，想先歇一会儿。")
	if bool(world.routes[route_id].blocked):
		return _refuse("road_blocked", "山路不通，对方暂时接不了这趟。")
	var definition: Dictionary = world.settings.routes[route_id]
	world.synchronize_region(definition.from)
	var need: int = world.delivery_need(route_id)
	var surplus: int = world.regions[definition.from].inventory.available(definition.source, definition.item) - int(definition.reserve_floor)
	if need <= 0 or surplus <= 0:
		return _refuse("no_valid_work", "眼下没有既需要又有余粮可运的差事。")
	if offer < int(service.definitions.help.minimum_fee):
		return _refuse("offer_too_low", "这一趟有路费和耽搁，对方希望你补足盘缠。")
	var bag: String = "actor:" + actor_id
	if world.regions[home].inventory.available(bag, service.definitions.coin_item) < offer:
		return _refuse("insufficient_funds", "你拿不出约定的盘缠，对方没有接下差事。")
	var context: Dictionary = {"energy": float(courier.energy) / 100.0, "busy": 0.0,
		"distance": position.distance_to(world.courier_cell(courier_id)) / float(service.definitions.help.talk_radius),
		"duty": 1.0, "offer": minf(1.0, float(offer) / float(service.definitions.help.minimum_fee)),
		"benevolence": 0.5, "terms": {"route": route_id, "coins": offer, "need": need, "surplus": surplus}}
	var decision: Dictionary = service.social.evaluate_request(actor_id, courier_id, "paid_haul", context, service.definitions.help.policy, service._rng, world.current_time)
	if decision.get("status") != "accepted":
		return _refuse("unwilling", "对方权衡后没有答应，可以换个条件再谈。")
	var id: String = service.allocate("help")
	var container: String = "escrow:" + id
	service.escrow.create_container(container, {})
	var wallet: String = "wallet:" + courier_id
	if not service.escrow.containers.has(wallet):
		service.escrow.create_container(wallet, {})
	if not service.transfer(id + ":escrow", home, bag, "escrow", container, service.definitions.coin_item, offer):
		return _refuse("payment_failed", "盘缠没有托管成功，约定没有成立。")
	var agreement: Dictionary = {"id": id, "actor": actor_id, "home": home, "courier": courier_id,
		"route": route_id, "offer": offer, "status": "accepted", "execution": "pending",
		"shipment": "", "escrow": container, "wallet": wallet, "at": world.current_time,
		"decision": decision.id, "ok": true, "reason": "accepted", "line": "对方收下委托，盘缠先托管，送达后支付。"}
	service.help_requests[id] = agreement
	world.routes[route_id].demand = maxi(int(world.routes[route_id].demand), need)
	world._try_dispatch(route_id, true)
	if courier.phase != "outbound" or str(courier.shipment).is_empty():
		service.transfer(id + ":refund", "escrow", container, home, bag, service.definitions.coin_item, offer)
		agreement.status = "refused"
		agreement.execution = "failed"
		agreement.ok = false
		agreement.reason = "dispatch_failed"
		agreement.line = "临行条件发生变化，盘缠已退还。"
	else:
		agreement.shipment = courier.shipment
	service.record("help_agreed", actor_id, {"agreement": id, "shipment": agreement.shipment})
	return agreement.duplicate(true)


func settle() -> void:
	var world: RefCounted = service.world
	for agreement: Dictionary in service.help_requests.values():
		if agreement.status != "accepted" or agreement.execution != "pending" or not world.shipments.has(agreement.shipment):
			continue
		if world.shipments[agreement.shipment].status == "delivered":
			if service.transfer(agreement.id + ":payment", "escrow", agreement.escrow, "escrow", agreement.wallet, service.definitions.coin_item, int(agreement.offer)):
				agreement.execution = "fulfilled"
				agreement.completed_at = world.current_time
				agreement.line = "对方已经送到粮食，托管盘缠已支付。"
				service.record("help_fulfilled", agreement.actor, {"agreement": agreement.id, "shipment": agreement.shipment})


func _refuse(reason: String, line: String) -> Dictionary:
	var result: Dictionary = service.response(false, reason, line)
	result.status = "refused"
	return result
