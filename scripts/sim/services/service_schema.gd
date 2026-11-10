extends RefCounted
## Validates service commands and cross-ledger evidence before a world swap.

const Inventory = preload("res://scripts/sim/inventory_ledger.gd")
const Social = preload("res://scripts/sim/social_memory.gd")
const MAX_COUNT: int = Inventory.MAX_COUNT


static func valid_definitions(data: Dictionary, world: RefCounted) -> bool:
	if data.get("version") != 1 or not _count(data.get("move_minutes_per_cell"), 1) or not _count(data.get("job_timeout"), 1) or not _number(data.get("work_energy_per_minute"), 0.0) or not _text(data.get("coin_item")):
		return false
	for field: String in ["visitor", "hauling", "report", "redemptions", "access", "restricted_actions", "help"]:
		if not data.get(field) is Dictionary:
			return false
	for kind: String in ["eat", "rest"]:
		if not data.get("returns") is Dictionary or not _text(data.returns.get("label")) or not _count(data.returns.get("minutes"), 1):
			return false
		if not data.visitor.get(kind) is Dictionary:
			return false
		var definition: Dictionary = data.visitor[kind]
		if not _place_spec(definition) or not _count(definition.get("fee"), 0):
			return false
		if kind == "eat" and (not _text(definition.get("item")) or not _count(definition.get("amount"), 1) or not _number(definition.get("hunger_gain"), 0.0, 100.0)):
			return false
		if kind == "rest" and not _number(definition.get("energy_gain"), 0.0, 100.0):
			return false
	var haul: Dictionary = data.hauling
	if not _text(haul.get("route")) or not world.routes.has(haul.route) or not _text(haul.get("label")) or not world.regions.has(haul.get("credit_region")):
		return false
	for field: String in ["amount", "pickup_minutes", "unload_minutes", "credit"]:
		if not _count(haul.get(field), 1):
			return false
	if not _count(haul.get("source_floor"), 0) or not _place_spec(data.report):
		return false
	for definition: Variant in data.redemptions.values():
		if not definition is Dictionary or not _place_spec(definition) or not _text(definition.get("source")) or not _text(definition.get("item")) or not _count(definition.get("amount"), 1) or not _count(definition.get("cost"), 1):
			return false
	for definition: Variant in data.access.values():
		if not definition is Dictionary or not _place_spec(definition) or not _count(definition.get("required_contribution"), 0):
			return false
	for definition: Variant in data.restricted_actions.values():
		if not definition is Dictionary or not _place_spec(definition) or not data.access.has(definition.get("scope")) or not _text(definition.get("item")) or not _count(definition.get("amount"), 1):
			return false
	for sim: RefCounted in world.regions.values():
		for definition: Dictionary in [data.visitor.eat, data.visitor.rest, data.report]:
			if not sim.places.has(definition.place):
				return false
		for definition: Dictionary in data.redemptions.values():
			if not sim.places.has(definition.place) or not sim.inventory.containers.has(definition.source):
				return false
		for definition: Dictionary in data.access.values():
			if not sim.places.has(definition.place):
				return false
		for definition: Dictionary in data.restricted_actions.values():
			if not sim.places.has(definition.place) or not sim.inventory.containers.has(definition.place):
				return false
	if not preload("res://scripts/sim/services/local_trade.gd").valid_definitions(data.get("trade"), world):
		return false
	for offer: Dictionary in data.trade.offers.values():
		if offer.item == data.coin_item:
			return false
	return _count(data.help.get("minimum_fee"), 1) and _number(data.help.get("rest_below"), 0.0, 100.0) and _number(data.help.get("talk_radius"), 0.1) and _count(data.help.get("seed")) and data.help.get("policy") is Dictionary


static func validate_snapshot(data: Dictionary, service: RefCounted) -> bool:
	var world: RefCounted = service.world
	if data.get("version") != 5 or not _count(data.get("last_ms")) or int(data.last_ms) != world.elapsed_ms or not same_value(data.get("definitions"), service.definitions) or not _count(data.get("last_time")) or int(data.last_time) != world.current_time or not _count(data.get("next_id"), 1):
		return false
	for field: String in ["jobs", "active_jobs", "receipts", "authorizations", "help_requests", "operations", "escrow", "social"]:
		if not data.get(field) is Dictionary:
			return false
	if not data.get("events") is Array or not data.get("rng_state") is String or not str(data.rng_state).is_valid_int() or str(int(data.rng_state)) != data.rng_state:
		return false
	var escrow := Inventory.new()
	var social := Social.new()
	if not escrow.restore(data.escrow) or not social.restore(data.social):
		return false
	if not SimCapabilityConversation.valid_history(social, world._content.capability_conversation, world.current_time):
		return false
	if not escrow.reservations.is_empty() or not escrow.operations.is_empty() or not escrow.custody.is_empty():
		return false
	var expected_actors: Dictionary = {}
	for sim: RefCounted in world.regions.values():
		for actor: String in sim.synchronize_actors():
			expected_actors[actor] = true
	for courier: String in world.couriers:
		expected_actors[courier] = true
	if social.knowledge.size() != expected_actors.size():
		return false
	for actor: String in expected_actors:
		if not social.knowledge.has(actor):
			return false
	var owned: Dictionary = {}
	var ids: Dictionary = {}
	for job_id: Variant in data.jobs:
		var job: Variant = data.jobs[job_id]
		if not job is Dictionary or job.get("id") != job_id or not _id(job_id, data.next_id, ids) or not _valid_job(job, data, service):
			return false
		if job.kind == "trade" and not service._trade.valid_history(job, data):
			return false
		if job.status == "active":
			if owned.has(job.actor) or data.active_jobs.get(job.actor) != job_id:
				return false
			owned[job.actor] = job_id
	if not same_value(owned, data.active_jobs):
		return false
	for receipt_id: Variant in data.receipts:
		var receipt: Variant = data.receipts[receipt_id]
		if not receipt is Dictionary or receipt.get("id") != receipt_id or not _id(receipt_id, data.next_id, ids) or not receipt.get("registered") is bool:
			return false
		if not data.jobs.has(receipt.get("job")):
			return false
		var job: Dictionary = data.jobs[receipt.job]
		if job.kind != "haul_grain" or job.status != "completed" or receipt.get("actor") != job.actor or receipt.get("region") != service.definitions.hauling.credit_region or not _count(receipt.get("amount"), int(service.definitions.hauling.credit), int(service.definitions.hauling.credit)) or receipt.get("operation") != job.id + ":delivery" or job.get("evidence") != receipt_id:
			return false
		var route: Dictionary = world.settings.routes[job.route]
		if not _transfer_matches(data.operations.get(receipt.operation), job.home, "actor:" + String(job.actor), route.to, route.target, route.item, int(job.amount)):
			return false
		var sim: RefCounted = world.regions[receipt.region]
		var entry: Variant = sim.institutions.operations.get(String(receipt_id) + ":credit")
		if bool(receipt.registered) != (entry != null):
			return false
		if entry != null and (entry.kind != "issue" or entry.subject != job.actor or entry.evidence != receipt_id or int(entry.amount) != int(receipt.amount)):
			return false
	for key: Variant in data.authorizations:
		var permit: Variant = data.authorizations[key]
		if not permit is Dictionary or not world.regions.has(permit.get("region")) or not expected_actors.has(permit.get("actor")) or not service.definitions.access.has(permit.get("scope")) or not data.jobs.has(permit.get("job")):
			return false
		var sim: RefCounted = world.regions[permit.region]
		var job: Dictionary = data.jobs[permit.job]
		if key != str(permit.region) + ":" + str(permit.actor) + ":" + str(permit.scope) or not sim.has_actor(permit.get("issuer")) or not _count(permit.get("at"), 0, world.current_time) or job.status != "completed" or job.kind != "access" or job.actor != permit.actor or job.region != permit.region or job.options.get("scope") != permit.scope:
			return false
	for operation_id: Variant in data.operations:
		if not _text(operation_id) or not _valid_operation(data.operations[operation_id], world, escrow) or not _owned_operation(operation_id, data.operations[operation_id], data, service):
			return false
	for event: Variant in data.events:
		if not event is Dictionary or not _id(event.get("id"), data.next_id, ids) or not _text(event.get("kind")) or not expected_actors.has(event.get("actor")) or not _count(event.get("at"), 0, world.current_time) or not event.get("details") is Dictionary:
			return false
	return _valid_help(data, service, escrow, ids) and _valid_service_accounts(data, service) and SimEntrustedGoods.valid_services(data, service)


static func _valid_job(job: Dictionary, _data: Dictionary, service: RefCounted) -> bool:
	var world: RefCounted = service.world
	if not world.regions.has(job.get("home")) or not world.regions.has(job.get("region")) or not _text(job.get("actor")):
		return false
	var home: RefCounted = world.regions[job.home]
	if not home.has_actor(job.actor) or not job.get("kind") in ["carry_stock", "eat", "rest", "haul_grain", "report", "redeem", "access", "collect_herb", "trade", "return_goods", "claim_wage", "site_loan", "site_return"] or not job.get("status") in ["active", "completed", "failed", "cancelled"] or not job.get("phase") in ["travel", "work"]:
		return false
	if not job.get("path") is Array or not job.get("options") is Dictionary or not job.get("spec") is Dictionary or not _count(job.get("started"), 0, world.current_time) or not job.get("previous_autonomous") is bool or not job.get("carrying") is bool or not job.get("outcome") is String:
		return false
	if job.kind == "carry_stock":
		return service._hauling.valid_job(job, _data)
	var expected: Dictionary = _expected_spec(job, service)
	if expected.is_empty() or not same_value(job.spec, expected) or job.get("label") != expected.label:
		return false
	if job.kind == "haul_grain":
		if not job.get("custody_required") is bool or (job.custody_required and (not job.options.get("custody") is String or str(job.options.custody).is_empty())):
			return false
		if job.status == "active" and not job.custody_required:
			return false
		if job.get("route") != service.definitions.hauling.route or job.get("credit_region") != service.definitions.hauling.credit_region or not _count(job.get("amount"), int(service.definitions.hauling.amount), int(service.definitions.hauling.amount)) or not job.get("stage") in ["pickup", "delivery"]:
			return false
	elif job.kind == "site_return":
		if job.get("stage") not in ["inspect", "register"] or job.options.get("issuer") != job.actor or not _text(job.options.get("requester")) or service.actor_home(str(job.options.requester)).is_empty() or job.carrying:
			return false
	else:
		if job.get("stage") != "service":
			return false
	if job.kind == "site_loan" and job.carrying:
		return false
	if job.kind == "return_goods":
		var note: Dictionary = home.inventory.custody[job.options.custody]
		if job.region != SimEntrustedGoods.return_region(str(job.home), note) or (job.status == "active" and not note.settled_by.is_empty()) or (job.status == "completed" and note.settled_by != {"domain": "service", "operation": str(job.id) + ":return"}):
			return false
	if job.status == "active":
		if not _count(job.get("due_ms"), world.elapsed_ms + 1) or not _count(job.get("started_ms")) or int(job.started_ms) > world.elapsed_ms or not SimLocalMotion._vector(job.get("segment_from")) or not _count(job.get("segment_started_ms")) or int(job.segment_started_ms) > world.elapsed_ms or not home.synchronize_actors()[job.actor].active.is_empty() or home.synchronize_actors()[job.actor].autonomous:
			return false
		var previous: Array = home.synchronize_actors()[job.actor].cell
		for point: Variant in job.path:
			if not _cell(point) or (not _adjacent(previous, point) and not same_value(previous, point)):
				return false
			previous = point
		var destination: Array = world.regions[job.region].places[expected.place].cell
		if job.kind == "haul_grain" and job.stage == "delivery":
			var route: Dictionary = world.settings.routes[job.route]
			destination = world.regions[route.to].places[route.target].cell
		if not same_value(previous, destination) or (job.phase == "work" and not job.path.is_empty()):
			return false
		if job.phase == "travel":
			if bool(job.get("road_paused", false)):
				if not SimLocalMotion._vector(job.segment_from) or not home.actor_position(home.synchronize_actors()[job.actor]).is_equal_approx(Vector2(float(job.segment_from[0]), float(job.segment_from[1]))):
					return false
			elif not SimRouteTravel.valid_segment(job, home.synchronize_actors()[job.actor], world.elapsed_ms, float(home.motion_rules.motion.speed)):
				return false
		if job.carrying:
			if not job.kind in ["eat", "haul_grain"]:
				return false
			var item: String = job.spec.item if job.kind == "eat" else world.settings.routes[job.route].item
			var amount: int = int(job.spec.amount) if job.kind == "eat" else int(job.amount)
			if job.kind == "haul_grain" and bool(job.get("custody_required", false)):
				if not home.inventory.can_use("actor:" + String(job.actor), item, amount, str(job.options.custody)):
					return false
			elif home.inventory.available("actor:" + String(job.actor), item) < amount:
				return false
	else:
		if not _count(job.get("finished_at"), int(job.started), world.current_time):
			return false
	return true


static func _owned_operation(id: String, operation: Dictionary, data: Dictionary, service: RefCounted) -> bool:
	var owner: String = id.get_slice(":", 0) + ":" + id.get_slice(":", 1) + ":" + id.get_slice(":", 2)
	var suffix: String = id.trim_prefix(owner + ":")
	if data.jobs.has(owner):
		var job: Dictionary = data.jobs[owner]
		var bag: String = "actor:" + str(job.actor)
		if job.kind == "carry_stock":
			var options: Dictionary = job.options
			return _transfer_matches(operation, options.source.region, options.source.container, job.home, bag, options.item, int(options.amount)) if suffix == "pickup" else suffix == "delivery" and job.status == "completed" and _transfer_matches(operation, job.home, bag, options.target.region, options.target.container, options.item, int(options.amount))
		match suffix:
			"trade_goods", "trade_money":
				return job.kind == "trade" and job.status == "completed" and same_value(operation, service._trade.legs(job)[suffix.trim_prefix("trade_")])
			"fee":
				return job.kind in ["eat", "rest"] and _transfer_matches(operation, job.home, bag, job.region, "records", service.definitions.coin_item, int(job.spec.fee))
			"pickup":
				if job.kind == "eat":
					return _transfer_matches(operation, job.region, job.spec.place, job.home, bag, job.spec.item, int(job.spec.amount))
				if job.kind == "haul_grain":
					var route: Dictionary = service.world.settings.routes[job.route]
					return _transfer_matches(operation, route.from, route.source, job.home, bag, route.item, int(job.amount))
			"delivery":
				if job.kind == "haul_grain":
					var route: Dictionary = service.world.settings.routes[job.route]
					return job.status == "completed" and _transfer_matches(operation, job.home, bag, route.to, route.target, route.item, int(job.amount))
			"return":
				if job.kind != "return_goods" or job.status != "completed":
					return false
				var note: Dictionary = service.world.regions[job.home].inventory.custody[job.options.custody]
				return _transfer_matches(operation, job.home, bag, job.region, job.spec.place, note.item, int(note.amount))
			"collection":
				return job.kind == "collect_herb" and job.status == "completed" and _transfer_matches(operation, job.region, job.spec.place, job.home, bag, job.spec.item, int(job.spec.amount))
			"redeem":
				if job.kind == "redeem" and job.status == "completed":
					var definition: Dictionary = service.definitions.redemptions[job.options.offer]
					return _transfer_matches(operation, job.region, definition.source, job.home, bag, definition.item, int(definition.amount))
		return false
	if data.help_requests.has(owner):
		var agreement: Dictionary = data.help_requests[owner]
		match suffix:
			"escrow": return _transfer_matches(operation, agreement.home, "actor:" + str(agreement.actor), "escrow", agreement.escrow, service.definitions.coin_item, int(agreement.offer))
			"payment": return agreement.execution == "fulfilled" and _transfer_matches(operation, "escrow", agreement.escrow, "escrow", agreement.wallet, service.definitions.coin_item, int(agreement.offer))
			"refund": return agreement.execution == "failed" and _transfer_matches(operation, "escrow", agreement.escrow, agreement.home, "actor:" + str(agreement.actor), service.definitions.coin_item, int(agreement.offer))
	return false


static func _valid_service_accounts(data: Dictionary, service: RefCounted) -> bool:
	for region_id: String in service.world.regions:
		var sim: RefCounted = service.world.regions[region_id]
		for entry: Dictionary in sim.institutions.entries:
			var id: String = entry.operation_id
			if not id.begins_with("service:") and not str(entry.evidence).begins_with("service:"):
				if not sim.has_actor(entry.subject):
					return false
				continue
			if entry.kind == "issue":
				if not data.receipts.has(entry.evidence):
					return false
				var receipt: Dictionary = data.receipts[entry.evidence]
				if id != str(receipt.id) + ":credit" or receipt.region != region_id or receipt.actor != entry.subject or not bool(receipt.registered) or int(receipt.amount) != int(entry.amount):
					return false
			else:
				if not data.jobs.has(entry.evidence):
					return false
				var job: Dictionary = data.jobs[entry.evidence]
				if job.kind != "redeem" or job.status != "completed" or job.region != region_id or id != str(job.id) + ":debit" or entry.subject != job.actor:
					return false
				var offer: Dictionary = service.definitions.redemptions[job.options.offer]
				if int(entry.amount) != int(offer.cost) or not data.operations.has(str(job.id) + ":redeem"):
					return false
	return true


static func _expected_spec(job: Dictionary, service: RefCounted) -> Dictionary:
	match str(job.kind):
		"eat", "rest": return service.definitions.visitor[job.kind]
		"haul_grain":
			var haul: Dictionary = service.definitions.hauling
			return {"place": service.world.settings.routes[haul.route].source, "minutes": haul.pickup_minutes, "label": haul.label}
		"collect_herb": return service.definitions.restricted_actions[job.kind]
		"trade": return service._trade.spec_for(str(job.region), job.options)
		"claim_wage": return SimBudgetedLabor.claim_spec(service.world, str(job.region), job.options)
		"return_goods": return SimEntrustedGoods.return_spec(service, str(job.actor), str(job.home), job.options)
		"site_loan", "site_return":
			if service.world.get("site_affairs") == null:
				return {}
			return service.world.site_affairs.service_spec(str(job.kind), str(job.region), job.options, str(job.get("stage", "")))
		_:
			return service._institutions.spec_for(job.kind, job.options)


static func _valid_help(data: Dictionary, service: RefCounted, escrow: RefCounted, ids: Dictionary) -> bool:
	var world: RefCounted = service.world
	var expected_containers: Dictionary = {}
	var wallet_totals: Dictionary = {}
	var pending_couriers: Dictionary = {}
	var claimed_shipments: Dictionary = {}
	for request_id: Variant in data.help_requests:
		var request: Variant = data.help_requests[request_id]
		if not request is Dictionary or request.get("id") != request_id or not _id(request_id, data.next_id, ids) or not world.couriers.has(request.get("courier")) or not world.routes.has(request.get("route")) or not world.regions.has(request.get("home")) or not world.regions[request.home].has_actor(request.get("actor")):
			return false
		if not _count(request.get("offer"), int(service.definitions.help.minimum_fee)) or request.get("escrow") != "escrow:" + str(request_id) or request.get("wallet") != "wallet:" + str(request.courier) or not escrow.containers.has(request.escrow) or not escrow.containers.has(request.wallet) or not _count(request.get("at"), 0, world.current_time):
			return false
		expected_containers[request.escrow] = true
		expected_containers[request.wallet] = true
		if not wallet_totals.has(request.wallet):
			wallet_totals[request.wallet] = 0
		if not request.get("status") in ["accepted", "refused"] or not request.get("execution") in ["pending", "fulfilled", "failed"]:
			return false
		if request.status == "accepted":
			if not world.shipments.has(request.get("shipment")) or world.shipments[request.shipment].route != request.route or claimed_shipments.has(request.shipment):
				return false
			claimed_shipments[request.shipment] = true
			if (request.execution == "fulfilled") != (world.shipments[request.shipment].status == "delivered"):
				return false
			if request.execution == "pending":
				if pending_couriers.has(request.courier) or world.couriers[request.courier].shipment != request.shipment:
					return false
				pending_couriers[request.courier] = true
			else:
				if int(request.offer) > MAX_COUNT - int(wallet_totals[request.wallet]):
					return false
				wallet_totals[request.wallet] = int(wallet_totals[request.wallet]) + int(request.offer)
			if escrow.quantity(request.escrow, service.definitions.coin_item) != (int(request.offer) if request.execution == "pending" else 0):
				return false
		elif request.execution != "failed" or escrow.quantity(request.escrow, service.definitions.coin_item) != 0:
			return false
		if escrow.containers[request.escrow].size() != 1:
			return false
		if not _transfer_matches(data.operations.get(str(request_id) + ":escrow"), request.home, "actor:" + str(request.actor), "escrow", request.escrow, service.definitions.coin_item, int(request.offer)):
			return false
		var payment: String = ":payment" if request.execution == "fulfilled" else ":refund"
		if request.execution != "pending" and not data.operations.has(str(request_id) + payment):
			return false
	if escrow.containers.size() != expected_containers.size():
		return false
	for wallet: String in wallet_totals:
		var items: Dictionary = escrow.containers[wallet]
		if items.size() > 1 or (items.size() == 1 and not items.has(service.definitions.coin_item)) or escrow.quantity(wallet, service.definitions.coin_item) != int(wallet_totals[wallet]):
			return false
	return true


static func same_value(left: Variant, right: Variant) -> bool:
	return JSON.stringify(JSON.parse_string(JSON.stringify(left, "", true, true)), "", true, true) == JSON.stringify(JSON.parse_string(JSON.stringify(right, "", true, true)), "", true, true)


static func _valid_operation(value: Variant, world: RefCounted, escrow: RefCounted) -> bool:
	if not value is Dictionary or not _text(value.get("item")) or not _count(value.get("amount"), 1):
		return false
	for side: String in ["from", "to"]:
		if not value.get(side) is String or (value[side] != "escrow" and not world.regions.has(value[side])):
			return false
	var source: RefCounted = escrow if value.from == "escrow" else world.regions[value.from].inventory
	var target: RefCounted = escrow if value.to == "escrow" else world.regions[value.to].inventory
	return source.containers.has(value.get("source")) and target.containers.has(value.get("target"))


static func _transfer_matches(value: Variant, origin: String, source: String, destination: String, target: String, item: String, amount: int) -> bool:
	return same_value(value, {"from": origin, "source": source, "to": destination, "target": target, "item": item, "amount": amount})


static func _place_spec(data: Dictionary) -> bool:
	return _text(data.get("label")) and _text(data.get("place")) and _count(data.get("minutes"), 1)


static func _id(value: Variant, next: int, seen: Dictionary) -> bool:
	if not _text(value) or not str(value).begins_with("service:") or seen.has(value):
		return false
	var suffix: String = str(value).get_slice(":", 2)
	if not suffix.is_valid_int() or int(suffix) < 1 or int(suffix) >= next:
		return false
	seen[value] = true
	return true


static func _number(value: Variant, minimum: float = 0.0, maximum: float = float(MAX_COUNT)) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and float(value) >= minimum and float(value) <= maximum


static func _count(value: Variant, minimum: int = 0, maximum: int = MAX_COUNT) -> bool:
	return _number(value, float(minimum), float(maximum)) and float(value) == floorf(float(value))


static func _text(value: Variant) -> bool:
	return value is String and not str(value).strip_edges().is_empty()


static func _cell(value: Variant) -> bool:
	return value is Array and value.size() == 2 and _count(value[0], 0, 2147483647) and _count(value[1], 0, 2147483647)


static func _adjacent(left: Array, right: Array) -> bool:
	var dx: int = absi(int(left[0]) - int(right[0]))
	var dy: int = absi(int(left[1]) - int(right[1]))
	return dx <= 1 and dy <= 1 and dx + dy > 0
