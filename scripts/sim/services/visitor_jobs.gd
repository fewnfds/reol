extends RefCounted
## Timed visitor work uses the home actor and home bag, never a copied pawn.

var _owner: WeakRef
var service: RefCounted:
	get:
		return _owner.get_ref()


func _init(owner: RefCounted) -> void:
	_owner = weakref(owner)


func begin(actor_id: String, region_id: String, kind: String, options: Dictionary) -> Dictionary:
	var world: RefCounted = service.world
	var home: String = service.actor_home(actor_id)
	if home.is_empty() or not world.regions.has(region_id):
		return service.response(false, "unknown_actor", "没有可办理这件事的人或地点。")
	world.synchronize_region(home)
	world.synchronize_region(region_id)
	var actor: Dictionary = world.regions[home].actors[actor_id]
	if not world.actor_controls(actor_id, "action") or not world.actor_controls(actor_id, "motion"):
		return service.response(false, "control_missing", "眼下无法支配身体去办这件事。")
	if not actor.alive or not actor.active.is_empty() or service.owns_actor(actor_id) or world.artifacts.owns_actor(actor_id) or world.local_action_owns(actor_id):
		return service.response(false, "busy", "先完成或中断手头的事情。")
	var spec: Dictionary = {}
	match kind:
		"eat", "rest":
			spec = service.definitions.visitor[kind].duplicate(true)
			var bag: String = "actor:" + actor_id
			var already_owned: bool = kind == "eat" and world.regions[home].inventory.available(bag, spec.item) >= int(spec.amount)
			if not already_owned and world.regions[home].inventory.available(bag, service.definitions.coin_item) < int(spec.fee):
				return service.response(false, "insufficient_funds", "盘缠不够，暂时办不了这件事。")
			if kind == "eat" and not already_owned and sim_stock(world, region_id, spec.place, spec.item) < int(spec.amount):
				return service.response(false, "stock_missing", "灶房眼下没有可领的饭，稍后再来。")
		"haul_grain":
			var contract: Dictionary = service.definitions.hauling
			var route: Dictionary = world.settings.routes[contract.route]
			var held: String = SimEntrustedGoods.find(world.regions[home].inventory, actor_id, kind, str(route.item), int(contract.amount), "service")
			if held.is_empty() and world.delivery_need(contract.route) < int(contract.amount):
				return service.response(false, "no_demand", "库房眼下已有足够补给安排，暂不再雇人运粮。")
			region_id = route.from
			world.synchronize_region(region_id)
			spec = {"place": route.source, "minutes": contract.pickup_minutes, "label": contract.label}
		"return_goods":
			if options.is_empty():
				options = {"custody": SimEntrustedGoods.first_held(world.regions[home].inventory, actor_id)}
			spec = SimEntrustedGoods.return_spec(service, actor_id, home, options)
			if spec.is_empty():
				return service.response(false, "nothing_entrusted", "身上没有需要交回的受托物资。")
			var note: Dictionary = world.regions[home].inventory.custody[options.custody]
			if not note.settled_by.is_empty():
				return service.response(false, "already_returned", "这一批已经结清，无需再次归还。")
			region_id = SimEntrustedGoods.return_region(home, note)
			world.synchronize_region(region_id)
		"report", "redeem", "access":
			spec = service._institutions.prepare(actor_id, region_id, kind, options)
			if not bool(spec.get("ok", false)):
				return spec
		"trade":
			spec = service._trade.prepare(actor_id, region_id, options)
			if not bool(spec.get("ok", false)):
				return spec
		"site_loan", "site_return":
			if world.get("site_affairs") == null:
				return service.response(false, "unknown_service", "当地尚没有这份公源借用安排。")
			spec = world.site_affairs.prepare_service(actor_id, region_id, kind, options)
			if not bool(spec.get("ok", false)):
				return spec
			options = spec.options.duplicate(true)
		"claim_wage":
			spec = SimBudgetedLabor.claim_spec(world, region_id, options)
			if spec.is_empty() or world.budgeted_labor == null or not world.budgeted_labor.contracts.has(options.contract):
				return service.response(false, "invalid_contract", "没有这份已交付待验的现金差事。")
			var note: Dictionary = world.budgeted_labor.contracts[options.contract]
			if note.actor != actor_id or note.region != region_id or note.status != "payable":
				return service.response(false, "not_payable", "这笔差事尚未交付待验，或已结清。")
			var local: VillageSimulation = world.regions[region_id]
			if local.institutions.institutions[local.config.institution.id].offices[options.office].holder != options.issuer or not world.budgeted_labor._near(local, actor_id, str(options.issuer)):
				return service.response(false, "no_authority", "先当面向现任有付款权的人提出验收。")
		"collect_herb":
			spec = service.definitions.restricted_actions[kind].duplicate(true)
			if not service.has_access(actor_id, region_id, spec.scope):
				var grant: String = service.world.admissions.available_grant(actor_id, region_id)
				if grant.is_empty():
					return service.response(false, "access_denied", "没有有效签注或尚可用的一次放行，不能入圃取药。")
				options = {"admission": grant}
			elif options.has("admission"):
				return service.response(false, "invalid_basis", "请按本人实际有效的凭据办理。")
		_:
			return service.response(false, "unknown_service", "当地没有这项办理办法。")
	var sim: RefCounted = world.regions[region_id]
	var destination: Array = sim.places[spec.place].cell
	var resumed: String = ""
	if kind == "haul_grain":
		var route: Dictionary = world.settings.routes[service.definitions.hauling.route]
		resumed = SimEntrustedGoods.find(world.regions[home].inventory, actor_id, kind, str(route.item), int(service.definitions.hauling.amount), "service")
		if not resumed.is_empty():
			region_id = route.to
			destination = world.regions[region_id].places[route.target].cell
	var path: Array = service.path_between(home, actor.cell, destination)
	if path.is_empty() and not _same_cell(actor.cell, destination):
		return service.response(false, "unreachable", "这条路眼下走不通。")
	var id: String = service.allocate("job")
	var job: Dictionary = {
		"id": id, "actor": actor_id, "home": home, "region": region_id,
		"kind": kind, "label": spec.label, "status": "active", "phase": "travel",
		"path": path, "started_ms": world.elapsed_ms,
		"started": world.current_time, "stage": "pickup" if kind == "haul_grain" else "inspect" if kind == "site_return" else "service",
		"carrying": false, "options": options.duplicate(true), "spec": spec,
		"previous_autonomous": bool(actor.autonomous), "outcome": "",
	}
	if kind == "haul_grain":
		job.custody_required = true
		job.options = {"custody": str(job.id) + ":pickup" if resumed.is_empty() else resumed}
		job.route = service.definitions.hauling.route
		job.amount = int(service.definitions.hauling.amount)
		job.credit_region = str(service.definitions.hauling.credit_region)
		if not world.regions.has(job.credit_region):
			return service.response(false, "invalid_institution", "没有承诺支付这笔差事的机构。")
		if not resumed.is_empty():
			job.carrying = true
			job.stage = "delivery"
	if not world.regions[home].actor_position(actor).is_equal_approx(TileGrid.cell_to_world(SimRouteTravel.cell(actor.cell))):
		job.path.push_front(actor.cell.duplicate())
	SimRouteTravel.begin_segment(job, actor, world.elapsed_ms, float(world.regions[home].motion_rules.motion.speed))
	service.jobs[id] = job
	service.active_jobs[actor_id] = id
	service.remember_job(job)
	if kind == "haul_grain":
		world.reserve_delivery(job.route, int(job.amount))
	actor.autonomous = false
	actor.goal = job.label
	world.invalidate_region(home)
	service.record("service_started", actor_id, {"job": id, "kind": kind, "region": region_id})
	if kind in ["site_loan", "site_return"]:
		world.site_affairs.service_started(job)
	return service.response(true, "started", "已经动身办理，途中可以中断。", id)


func cancel(actor_id: String, reason: String) -> bool:
	if not service.active_jobs.has(actor_id):
		return false
	var job: Dictionary = service.jobs[service.active_jobs[actor_id]]
	finish(job, false, "已中断办理；已经取走的物资仍随身保存。", "cancelled")
	job.cancel_reason = reason
	return true


func settle(job: Dictionary) -> void:
	var world: RefCounted = service.world
	var actor: Dictionary = world.regions[job.home].actors[job.actor]
	if job.phase == "travel":
		if not job.path.is_empty():
			if job.kind == "haul_grain" and job.stage == "delivery" and bool(world.routes[job.route].blocked):
				job.due_ms = world.elapsed_ms + int(service.definitions.move_minutes_per_cell) * 60000
				job.outcome = "山路受阻，带着货物等候通行。"
				return
			var next: Array = job.path[0]
			var from := Vector2i(int(actor.cell[0]), int(actor.cell[1]))
			var direction := Vector2i(int(next[0]), int(next[1])) - from
			if service._can_step.is_valid() and not bool(service._can_step.call(from, direction)):
				finish(job, false, "道路受阻，已停在原处；随身物资没有消失。")
				return
			job.outcome = ""
			job.path.pop_front()
			world.regions[job.home].set_actor_cell(str(job.actor), Vector2i(int(next[0]), int(next[1])))
			world.invalidate_region(job.home)
			if not job.path.is_empty():
				SimRouteTravel.begin_segment(job, actor, world.elapsed_ms, float(world.regions[job.home].motion_rules.motion.speed))
				return
		_arrive(job)
		return
	_finish_work(job)


func _arrive(job: Dictionary) -> void:
	var world: RefCounted = service.world
	var home: RefCounted = world.regions[job.home]
	var actor: Dictionary = home.actors[job.actor]
	var local: RefCounted = world.regions[job.region]
	world.synchronize_region(job.region)
	if job.kind == "eat":
		var spec: Dictionary = job.spec
		var bag: String = "actor:" + str(job.actor)
		if home.inventory.available(bag, spec.item) < int(spec.amount):
			var fee: int = int(spec.fee)
			var coin: String = service.definitions.coin_item
			if home.inventory.available(bag, coin) < fee or fee > service.Inventory.MAX_COUNT - local.inventory.quantity("records", coin) or local.inventory.available(spec.place, spec.item) < int(spec.amount) or int(spec.amount) > service.Inventory.MAX_COUNT - home.inventory.quantity(bag, spec.item):
				finish(job, false, "盘缠或现饭不足，这次没有领到饭。")
				return
			if fee > 0:
				service.transfer(job.id + ":fee", job.home, bag, job.region, "records", coin, fee)
			if not service.transfer(job.id + ":pickup", job.region, spec.place, job.home, bag, spec.item, int(spec.amount)):
				finish(job, false, "赶到时已经没有饭了，可以稍后再来。")
				return
		job.fee_paid = true
		job.carrying = true
	elif job.kind == "haul_grain" and job.stage == "pickup":
		var route: Dictionary = world.settings.routes[job.route]
		var bag: String = "actor:" + str(job.actor)
		if not home.inventory.custody.has(job.options.custody):
			if local.inventory.available(route.source, route.item) - int(service.definitions.hauling.source_floor) < int(job.amount):
				finish(job, false, "可外运的粮食不足，差事没有取到货。")
				return
			if not service.transfer(job.id + ":pickup", route.from, route.source, job.home, bag, route.item, int(job.amount)):
				finish(job, false, "粮食没有取出，差事暂时无法继续。")
				return
			home.inventory.entrust(str(job.options.custody), bag, str(route.item), int(job.amount), SimEntrustedGoods.service_basis(world, job))
		job.carrying = true
	job.phase = "work"
	var minutes: int = int(service.definitions.hauling.unload_minutes) if job.kind == "haul_grain" and job.stage == "delivery" else int(job.spec.minutes)
	job.segment_started_ms = world.elapsed_ms
	job.segment_from = actor.position.duplicate() if home.actors.has(job.actor) else []
	job.due_ms = world.elapsed_ms + minutes * 60000


func _finish_work(job: Dictionary) -> void:
	var world: RefCounted = service.world
	var home: RefCounted = world.regions[job.home]
	var actor: Dictionary = home.actors[job.actor]
	var bag: String = "actor:" + str(job.actor)
	world.synchronize_region(job.region)
	match str(job.kind):
		"eat", "rest":
			var fee: int = int(job.spec.fee) if job.kind == "rest" else 0
			var coin: String = service.definitions.coin_item
			var local: RefCounted = world.regions[job.region]
			if home.inventory.available(bag, coin) < fee or fee > service.Inventory.MAX_COUNT - local.inventory.quantity("records", coin):
				finish(job, false, "盘缠不够，先把取出的饭留在袋里。")
				return
			if job.kind == "eat" and home.inventory.available(bag, job.spec.item) < int(job.spec.amount):
				finish(job, false, "随身的饭已经不在，不能重复取食。")
				return
			if fee > 0:
				service.transfer(job.id + ":fee", job.home, bag, job.region, "records", coin, fee)
			if job.kind == "eat":
				home.inventory.consume(job.id + ":consume", bag, job.spec.item, int(job.spec.amount))
				actor.hunger = minf(100.0, float(actor.hunger) + float(job.spec.hunger_gain))
			else:
				actor.energy = minf(100.0, float(actor.energy) + float(job.spec.energy_gain))
			finish(job, true, "已在当地吃过饭。" if job.kind == "eat" else "已在当地歇息，精神恢复了。")
		"haul_grain":
			var route: Dictionary = world.settings.routes[job.route]
			if job.stage == "pickup":
				job.region = route.to
				job.stage = "delivery"
				var target: Array = world.regions[route.to].places[route.target].cell
				job.path = service.path_between(job.home, actor.cell, target)
				if job.path.is_empty() and not _same_cell(actor.cell, target):
					finish(job, false, "取到了粮食，但回程不通；粮食仍在你身上。")
					return
				job.phase = "travel"
				SimRouteTravel.begin_segment(job, actor, world.elapsed_ms, float(home.motion_rules.motion.speed))
				return
			if not service.transfer(job.id + ":delivery", job.home, bag, route.to, route.target, route.item, int(job.amount), str(job.options.custody)):
				finish(job, false, "这次没有完成交货；粮食仍在随身容器。")
				return
			var evidence: String = service.allocate("evidence")
			service.receipts[evidence] = {"id": evidence, "actor": job.actor, "region": job.credit_region,
				"amount": int(service.definitions.hauling.credit), "job": job.id,
				"operation": job.id + ":delivery", "registered": false}
			job.evidence = evidence
			finish(job, true, "粮食已经入库，拿着交付凭据向管事报工。")
		"return_goods":
			var note: Dictionary = home.inventory.custody[job.options.custody]
			if job.status != "active" or job.phase != "work" or world.elapsed_ms < int(job.due_ms) or not world.actor_controls(str(job.actor), "action") or not world.actor_controls(str(job.actor), "motion") or not actor.alive or not _same_cell(actor.cell, world.regions[job.region].places[job.spec.place].cell):
				return
			if service.transfer(str(job.id) + ":return", str(job.home), bag, str(job.region), str(job.spec.place), str(note.item), int(note.amount), str(job.options.custody)):
				finish(job, true, "这一批受托物资已实际交回；没有额外记功，私物仍在行囊。")
			else:
				finish(job, false, "眼下无法交回，物资与保管责任仍留在身上。")
		"collect_herb":
			if not service.collection_allowed(job):
				finish(job, false, "凭据或本次放行已不可用，不能取药。")
			elif service.transfer(job.id + ":collection", job.region, job.spec.place, job.home, bag, job.spec.item, int(job.spec.amount)):
				if job.options.has("admission"):
					world.admissions.consume(job.options.admission, job.id)
				finish(job, true, "药草已实际放入行囊；一次放行已经用完。" if job.options.has("admission") else "凭据已查验，药草已经放入你的行囊。")
			else:
				finish(job, false, "药圃眼下没有可领的药草。")
		"trade":
			var result: Dictionary = service._trade.settle(job)
			finish(job, bool(result.ok), str(result.line))
		"claim_wage":
			var result: Dictionary = world.budgeted_labor.settle_claim(job)
			finish(job, bool(result.ok), str(result.line))
		"site_loan", "site_return":
			var result: Dictionary = world.site_affairs.settle_service(job)
			if not bool(result.get("ok", false)):
				finish(job, false, str(result.get("line", "这次尚未办成公源借还事项。")))
				return
			var next_stage: String = str(result.get("next_stage", ""))
			if next_stage == "register" and job.kind == "site_return" and job.stage == "inspect":
				_continue_site_register(job, str(result.line))
			elif next_stage.is_empty():
				finish(job, true, str(result.line))
			else:
				finish(job, false, "核验过程的后续步骤不可用，已发生的现场事实仍保留。")
		_:
			var result: Dictionary = service._institutions.settle(job)
			finish(job, bool(result.get("ok", false)), str(result.get("line", "办理结束。")))


func _continue_site_register(job: Dictionary, line: String) -> void:
	var world: RefCounted = service.world
	var spec: Dictionary = world.site_affairs.service_spec(str(job.kind), str(job.region), job.options, "register")
	if spec.is_empty() or not bool(spec.get("ok", false)) or not world.regions[job.region].places.has(spec.get("place")):
		finish(job, false, "现场已核验，登记条款暂不可用；现场证据仍保留。")
		return
	var home: RefCounted = world.regions[job.home]
	var actor: Dictionary = home.actors[job.actor]
	var destination: Array = world.regions[job.region].places[spec.place].cell
	job.stage = "register"
	job.spec = spec
	job.label = str(spec.label)
	job.outcome = line
	job.path = service.path_between(str(job.home), actor.cell, destination)
	if job.path.is_empty() and not _same_cell(actor.cell, destination):
		finish(job, false, "现场已核验，但回桌道路不通；尚未登记，现场证据仍保留。")
		return
	job.phase = "travel"
	SimRouteTravel.begin_segment(job, actor, world.elapsed_ms, float(home.motion_rules.motion.speed))
	actor.goal = str(job.label)
	world.invalidate_region(str(job.home))


func finish(job: Dictionary, succeeded: bool, line: String, status: String = "") -> void:
	if job.status != "active":
		return
	var world: RefCounted = service.world
	var actor: Dictionary = world.regions[job.home].actors[job.actor]
	job.status = status if not status.is_empty() else ("completed" if succeeded else "failed")
	job.finished_at = world.current_time
	job.outcome = line
	service.active_jobs.erase(job.actor)
	# Releasing a claimed delivery sends a fresh correction through the normal
	# delayed channel. A supplier does not silently learn today's stock.
	if job.kind == "haul_grain" and not succeeded:
		world.request_delivery(job.route)
	actor.autonomous = bool(job.previous_autonomous)
	actor.goal = line
	world.invalidate_region(job.home)
	service.record("service_completed" if succeeded else "service_interrupted", job.actor, {"job": job.id, "line": line})
	if job.kind in ["site_loan", "site_return"] and world.get("site_affairs") != null:
		world.site_affairs.service_finished(job)


static func sim_stock(world: RefCounted, region_id: String, container: String, item: String) -> int:
	return world.regions[region_id].inventory.available(container, item)


static func _same_cell(left: Array, right: Array) -> bool:
	# JSON numbers restore as floats; a view sync writes integer coordinates.
	# Array equality distinguishes these types even when they name the same cell.
	return Vector2i(int(left[0]), int(left[1])) == Vector2i(int(right[0]), int(right[1]))
