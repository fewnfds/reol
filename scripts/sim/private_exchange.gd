class_name SimPrivateExchange
extends RefCounted
## A single attributed private bargain. Bodies, money and the object stay in
## their original owners; a proposal is neither possession nor standing consent.

const VERSION: int = 1
const TASK: String = "private_artifact_exchange"
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const Schema = preload("res://scripts/sim/private_exchange_schema.gd")

var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref() if _owner != null else null
var definitions: Dictionary = {}
var proposals: Dictionary = {}
var jobs: Dictionary = {}
## Derived live-job IDs; original process state remains in jobs and in the save.
var active_jobs: Dictionary = {}
## Committed cash moves are separate receipts, not another wallet or balance.
var transfers: Dictionary = {}
var next_id: int = 1


static func valid_definitions(data: Variant) -> bool:
	if not data is Dictionary or not Shape.keys(data, ["version", "object", "currency", "price", "duration_ms", "interaction_cells", "max_proposals", "max_jobs", "policy"]) or data.version != VERSION:
		return false
	if not SimInventory._nonempty(data.object) or not SimInventory._nonempty(data.currency):
		return false
	if not Shape.count(data.price, 1) or not Shape.count(data.duration_ms, 1, 86400000) or not Shape.count(data.interaction_cells, 1, 8) or not Shape.count(data.max_proposals, 1, 4096) or not Shape.count(data.max_jobs, 1, 4096):
		return false
	if not Shape.keys(data.policy, ["bias", "accept_threshold", "uncertainty_band", "context_step", "weights"]) or not Shape.keys(data.policy.get("weights"), SimSocialMemory.FACTOR_DEFAULTS.keys()):
		return false
	return not SimSocialMemory.new()._normalized_policy(data.policy).is_empty()


static func empty_state() -> Dictionary:
	return {"version": VERSION, "proposals": {}, "jobs": {}, "transfers": {}, "next_id": 1}


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules):
		return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func bind_world(authority: RefCounted) -> void:
	_owner = weakref(authority)


func home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].actors.has(actor):
			return region
	return ""


func body(actor: String) -> Dictionary:
	var region: String = home(actor)
	return world.regions[region].actors[actor] if not region.is_empty() else {}


func offered_objects(buyer: String, seller: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world == null or world.artifacts == null or home(buyer).is_empty() or home(seller).is_empty() or buyer == seller:
		return result
	var id: String = str(definitions.object)
	var item: Dictionary = world.artifacts.objects.get(id, {})
	if item.is_empty() or item.region != home(seller) or item.container != "actor:" + seller:
		return result
	if not bool(body(seller).alive) or not world.artifacts.can_see(buyer, id):
		return result
	var view: Dictionary = world.artifacts.describe(buyer, id)
	result.append({"id": id, "label": "%s · 出价%d钱" % [str(view.get("label", "灰纹铜环")), int(definitions.price)]})
	return result


func owns_actor(actor: String) -> bool:
	for id: String in active_jobs:
		var job: Dictionary = jobs[id]
		if actor in [job.buyer, job.seller]:
			return true
	return false


func previous_autonomy(actor: String) -> bool:
	for id: String in active_jobs:
		var job: Dictionary = jobs[id]
		if actor in [job.buyer, job.seller]:
			return bool(job.buyer_autonomous if actor == job.buyer else job.seller_autonomous)
	return false


func target_in_use(object_id: String, except_id: String = "") -> bool:
	for id: String in active_jobs:
		var job: Dictionary = jobs[id]
		if id != except_id and job.object == object_id:
			return true
	return false


func _talk(buyer: String, seller: String) -> bool:
	if body(buyer).is_empty() or body(seller).is_empty():
		return false
	for actor: String in [buyer, seller]:
		for channel: String in ["action", "motion", "communication"]:
			if not world.actor_controls(actor, channel):
				return false
	var from: Vector2 = SimRouteTravel.point(body(buyer))
	var to: Vector2 = SimRouteTravel.point(body(seller))
	var distance: float = minf(float(definitions.interaction_cells), float(world._content.interaction_requests.communication_cells)) * TileGrid.TILE_SIZE
	var level: int = Space.level(world, from)
	return from.distance_to(to) <= distance and level == Space.level(world, to) and Space.clear_segment(world, from, to, level)


func _available(actor: String) -> bool:
	var person: Dictionary = body(actor)
	return not person.is_empty() and bool(person.alive) and person.active.is_empty() and world.native_action_allowed(actor) and _no_duty(actor) and (world.health == null or world.health.can_fight(actor))


func _no_duty(actor: String) -> bool:
	var person: Dictionary = body(actor)
	return not person.is_empty() and person.receipts.is_empty() and (world.standing_work == null or world.standing_work.duty_for(actor, int(world.elapsed_ms)).is_empty()) and (world.construction == null or world.construction.duty_for(actor).is_empty()) and (world.resting == null or world.resting.duty_for(actor).is_empty()) and not SimWorkplaces.has_desk_duty(world.regions[home(actor)], actor)


func _terms(buyer: String, seller: String, object_id: String, source_event: String) -> Dictionary:
	return {"buyer": buyer, "seller": seller, "buyer_subject": world.embodiment.subject_for_actor(buyer), "seller_subject": world.embodiment.subject_for_actor(seller), "object": object_id, "source_event": source_event, "price": int(definitions.price), "currency": str(definitions.currency)}


func _offer_value(seller: String) -> float:
	# Value the cash when this person actually has the existing meal purpose
	# and lacks its desired provisions. No food, pay or purpose is invented.
	var livelihood: RefCounted = world.get("autonomous_livelihood")
	if livelihood == null or not livelihood.plans.has(seller):
		return 0.0
	var rules: Dictionary = livelihood.definitions
	var ledger: SimInventory = world.regions[home(seller)].inventory
	return 1.0 if ledger.available("actor:" + seller, str(rules.desired_item)) < int(rules.desired_amount) else 0.0


func _find_proposal(terms: Dictionary) -> Dictionary:
	for proposal: Dictionary in proposals.values():
		var current: Dictionary = proposal.duplicate(true)
		for field: String in ["id", "decision", "at_ms", "artifact_floor"]:
			current.erase(field)
		if SnapshotValues.normalized(current) == SnapshotValues.normalized(terms):
			return proposal
	return {}


func _decision(id: String) -> Dictionary:
	if world.services == null:
		return {}
	for row: Dictionary in world.services.social.requests.values():
		if row.id == id:
			return row
	return {}


func _seller_withdrew(proposal_id: String) -> bool:
	# A prior inclination is not renewed consent after the seller explicitly
	# withdrew. This first slice has no independent seller re-consent action.
	for job: Dictionary in jobs.values():
		if job.proposal == proposal_id and job.status == "cancelled" and job.cancelled_by == job.seller and job.cancel_reason == "seller_withdrew":
			return true
	return false


func request(buyer: String, seller: String, object_id: String) -> Dictionary:
	if world != null and world.artifact_transfers.checking:
		return _reply(false, "unavailable", "器物变更仍在校验，请稍后再商量。")
	if world == null or world.services == null or world.artifacts == null or buyer == seller or home(buyer).is_empty() or home(seller).is_empty():
		return _reply(false, "unavailable", "须与眼前能交流的人商量这枚环。")
	if world.elapsed_ms != world.target_ms or world.elapsed_ms > SimInventory.MAX_COUNT - int(definitions.duration_ms):
		return _reply(false, "unavailable", "先等当前世界事务接续完，再商量交接。")
	if not world.synchronize_region(home(buyer)) or not world.synchronize_region(home(seller)):
		return _reply(false, "unavailable", "双方的事情尚未接续到此刻。")
	if not _talk(buyer, seller):
		return _reply(false, "unheard", "先到能互相看清、当面交流的位置。")
	if not _available(buyer) or not _available(seller) or not bool(body(seller).autonomous):
		return _reply(false, "unavailable", "双方须先停下手头的事；对方忙时不能强行交割。")
	if object_id != definitions.object or offered_objects(buyer, seller).is_empty():
		return _reply(false, "unavailable", "先亲眼看清对方实际持有的那枚旧环。")
	if world.artifacts.target_in_use(object_id) or (world.soul_vessels != null and world.soul_vessels.target_in_use(object_id)) or (world.spirit_sources != null and world.spirit_sources.target_in_use(object_id)):
		return _reply(false, "unavailable", "这枚环正用于别的事，请先等它空下来。")
	var source_event: String = world.artifacts.current_holder_source(object_id, seller)
	if source_event.is_empty():
		return _reply(false, "unavailable", "眼下无法核对对方实际取得这枚环的来源。")
	var source: SimInventory = world.regions[home(buyer)].inventory
	var target: SimInventory = world.regions[home(seller)].inventory
	var currency: String = str(definitions.currency)
	var price: int = int(definitions.price)
	if not source.containers.has("actor:" + buyer) or not target.containers.has("actor:" + seller) or source.available("actor:" + buyer, currency) < price or target.quantity("actor:" + seller, currency) > SimInventory.MAX_COUNT - price:
		return _reply(false, "unavailable", "可处分的钱不足，或对方当前不能收下报价。")
	if jobs.size() >= int(definitions.max_jobs) or next_id > SimInventory.MAX_COUNT - 2 or not world.artifacts.can_reserve_exchange_action():
		return _reply(false, "unavailable", "当前不能安排新的交接。")
	var terms: Dictionary = _terms(buyer, seller, object_id, source_event)
	var proposal: Dictionary = _find_proposal(terms)
	if not proposal.is_empty() and _seller_withdrew(str(proposal.id)):
		return _reply(false, "refused", "对方已撤回这次同意；旧判断不能代替重新同意。")
	var memory: SimSocialMemory = world.services.social
	if proposal.is_empty():
		if proposals.size() >= int(definitions.max_proposals):
			return _reply(false, "unavailable", "暂不能记录新的商量。")
		var relation: Dictionary = memory.relation(seller, buyer)
		var profile: Dictionary = world.regions[home(seller)].config.actor_profiles.get(seller, {})
		var floor: int = int(world.artifacts.next_id)
		var decision_terms: Dictionary = terms.duplicate(true)
		decision_terms["artifact_floor"] = floor
		var context: Dictionary = {"energy": float(body(seller).energy) / 100.0, "busy": 0.0, "distance": 0.0, "risk": 0.0, "duty": 0.0, "offer": _offer_value(seller), "benevolence": float(profile.get("benevolence", 0.5)), "affinity": relation.affinity, "reliability": relation.reliability, "terms": decision_terms}
		var decision: Dictionary = memory.evaluate_request(buyer, seller, TASK, context, definitions.policy, world.services._rng, world.current_time)
		if str(decision.get("id", "")).is_empty():
			return _reply(false, "unavailable", "眼下不能形成这次当面商量。")
		proposal = terms.duplicate(true)
		proposal["id"] = _allocate("proposal")
		proposal["decision"] = str(decision.id)
		proposal["at_ms"] = int(world.elapsed_ms)
		proposal["artifact_floor"] = floor
		proposals[proposal.id] = proposal
	var choice: Dictionary = _decision(str(proposal.decision))
	if choice.get("status") != "accepted":
		return _reply(false, "refused", "对方这次不愿交换；同一件物的同一报价不会反复重掷。")
	# Repeated requests reuse inclination, but every attempted handover still
	# requires a fresh explicit request, preflight and recorded present consent.
	var id: String = "private_exchange:action:%d" % next_id
	var reservation: String = id + ":coin"
	if not source.reserve(reservation, "actor:" + buyer, currency, price, buyer):
		return _reply(false, "unavailable", "钱已不可处分，这次没有开始交接。")
	var buyer_body: Dictionary = body(buyer)
	var seller_body: Dictionary = body(seller)
	var details: Dictionary = {"participants": {"proposal": proposal.id, "job": id, "object": object_id, "source_event": source_event, "price": price, "currency": currency, "at_ms": int(world.elapsed_ms), "buyer_position": buyer_body.position.duplicate(), "seller_position": seller_body.position.duplicate()}, "private": {"decision": proposal.decision}}
	var witnesses: Array[String] = []
	var consent: String = memory.record("private_exchange_consent", seller, buyer, details, witnesses, world.current_time)
	if consent.is_empty():
		source.release(reservation)
		return _reply(false, "unavailable", "未能记录当面同意，这次没有开始交接。")
	# Capacity was checked before the decision and no other action runs in this
	# synchronous request. Both allocated identifiers now have a live job.
	var action: String = world.artifacts.reserve_exchange_action()
	if action.is_empty():
		source.release(reservation)
		push_error("Private exchange lost its preflighted artifact sequence")
		return _reply(false, "unavailable", "暂不能记录这次交接。")
	next_id += 1
	jobs[id] = {"id": id, "proposal": proposal.id, "buyer": buyer, "seller": seller, "buyer_region": home(buyer), "seller_region": home(seller), "object": object_id, "source_event": source_event, "consent": consent, "reservation": reservation, "artifact_action": action, "artifact_event": "", "artifact_release": "", "started_ms": int(world.elapsed_ms), "due_ms": int(world.elapsed_ms) + int(definitions.duration_ms), "finished_ms": -1, "status": "active", "cancelled_by": "", "cancel_reason": "", "buyer_position": buyer_body.position.duplicate(), "seller_position": seller_body.position.duplicate(), "buyer_autonomous": bool(buyer_body.autonomous), "seller_autonomous": bool(seller_body.autonomous), "buyer_goal": str(buyer_body.goal), "seller_goal": str(seller_body.goal), "buyer_retry_ms": int(buyer_body.retry_ms), "seller_retry_ms": int(seller_body.retry_ms), "receipt": ""}
	active_jobs[id] = true
	buyer_body.autonomous = false
	seller_body.autonomous = false
	buyer_body.goal = "当面交割旧环"
	seller_body.goal = "当面交割旧环"
	world.invalidate_region(home(buyer))
	world.invalidate_region(home(seller))
	return _reply(true, "started", "双方同意以%d钱当面交割；钱暂留在原行囊，完成才换手。" % price, id)


func _connected(job: Dictionary) -> bool:
	var proposal: Dictionary = proposals.get(job.proposal, {})
	if proposal.is_empty() or world.services == null or _decision(str(proposal.decision)).get("status") != "accepted" or not Schema.consent_valid(world.services.social, proposal, job):
		return false
	if home(str(job.buyer)) != job.buyer_region or home(str(job.seller)) != job.seller_region or not _talk(str(job.buyer), str(job.seller)):
		return false
	for actor: String in [str(job.buyer), str(job.seller)]:
		var person: Dictionary = body(actor)
		var position: Array = job.buyer_position if actor == job.buyer else job.seller_position
		if person.is_empty() or not bool(person.alive) or not person.active.is_empty() or bool(person.autonomous) or person.position != position:
			return false
		if world.body_action_owns(actor, &"private_exchange") or not _no_duty(actor):
			return false
		if world.health != null and not world.health.can_fight(actor):
			return false
	var item: Dictionary = world.artifacts.objects.get(job.object, {})
	if item.get("region") != job.seller_region or item.get("container") != "actor:" + str(job.seller) or world.artifacts.current_holder_source(str(job.object), str(job.seller)) != job.source_event:
		return false
	if world.artifacts.target_in_use(str(job.object), str(job.id)) or (world.soul_vessels != null and world.soul_vessels.target_in_use(str(job.object))) or (world.spirit_sources != null and world.spirit_sources.target_in_use(str(job.object))):
		return false
	var ledger: SimInventory = world.regions[job.buyer_region].inventory
	var seller_ledger: SimInventory = world.regions[job.seller_region].inventory
	return SnapshotValues.normalized(ledger.reservations.get(job.reservation, {})) == SnapshotValues.normalized({"container": "actor:" + str(job.buyer), "item": str(definitions.currency), "amount": int(definitions.price), "owner_id": str(job.buyer)}) and seller_ledger.containers.has("actor:" + str(job.seller)) and seller_ledger.quantity("actor:" + str(job.seller), str(definitions.currency)) <= SimInventory.MAX_COUNT - int(definitions.price)


func _money_candidates(job: Dictionary) -> Dictionary:
	# One clone per original ledger: same-region parties must never replace one
	# another with two independent copies. No real wallet changes during preflight.
	var source: SimInventory = world.regions[job.buyer_region].inventory
	var target: SimInventory = world.regions[job.seller_region].inventory
	var first := SimInventory.new()
	if not first.restore(source.to_dict()):
		return {}
	var second: SimInventory = first
	if source != target:
		second = SimInventory.new()
		if not second.restore(target.to_dict()):
			return {}
	var currency: String = str(definitions.currency)
	var price: int = int(definitions.price)
	var buyer_container: String = "actor:" + str(job.buyer)
	var seller_container: String = "actor:" + str(job.seller)
	var payment_id: String = str(job.id) + ":payment"
	if first.operations.has(payment_id) or not first.reservations.has(job.reservation) or not first.containers.has(buyer_container) or not second.containers.has(seller_container):
		return {}
	if source == target:
		# Native transfer consumes its exact reservation and leaves the original
		# ledger operation as independent payment evidence.
		if not first.transfer(payment_id, buyer_container, seller_container, currency, price, str(job.reservation)):
			return {}
	else:
		if second.quantity(seller_container, currency) > SimInventory.MAX_COUNT - price:
			return {}
		first.release(str(job.reservation))
		if not first.consume(payment_id, buyer_container, currency, price):
			return {}
		second.containers[seller_container][currency] = second.quantity(seller_container, currency) + price
	return {"source": first, "target": second, "same": source == target}


func _complete(job: Dictionary) -> bool:
	if not world.artifacts.synchronize_environment_transfer() or world.private_exchange != self:
		return false
	var payment_id: String = str(job.id) + ":payment"
	if job.status != "active" or transfers.has(payment_id) or not _connected(job) or not world.artifacts.can_record_exchange(job):
		return false
	var prepared: Dictionary = _money_candidates(job)
	if prepared.is_empty():
		return false
	var change: Dictionary = SimArtifactTransfers.describe(str(job.object), world.artifacts.objects[job.object], str(job.buyer_region), "actor:" + str(job.buyer), int(world.elapsed_ms), str(job.artifact_action), "private_exchange")
	if not world.artifact_transfers.allows(change):
		return false
	var environment: Dictionary = world.artifacts.prepare_environment_transfer(change)
	if not bool(environment.get("ok", false)):
		return false
	# No await, callback, save or other rule runs in this commit section. The
	# artifact preflight and cloned ledgers have already checked every failure.
	var event_id: String = world.artifacts.record_exchange(job)
	if event_id.is_empty():
		world.artifacts.cancel_environment_transfer(environment)
		return false
	world.artifacts.finish_environment_transfer(environment)
	var source: SimInventory = world.regions[job.buyer_region].inventory
	var target: SimInventory = world.regions[job.seller_region].inventory
	var first: SimInventory = prepared.source
	var second: SimInventory = prepared.target
	source.containers = first.containers
	source.reservations = first.reservations
	source.operations = first.operations
	if not bool(prepared.same):
		target.containers = second.containers
		target.reservations = second.reservations
		target.operations = second.operations
	job.artifact_event = event_id
	transfers[payment_id] = {"job": job.id, "from": job.buyer_region, "to": job.seller_region, "source": "actor:" + str(job.buyer), "target": "actor:" + str(job.seller), "item": str(definitions.currency), "amount": int(definitions.price), "artifact_event": event_id, "consent": job.consent, "at_ms": int(world.elapsed_ms)}
	job.receipt = payment_id
	source.contents_changed.emit("actor:" + str(job.buyer))
	target.contents_changed.emit("actor:" + str(job.seller))
	_finish(job, "completed")
	world.artifact_transfers.publish(change)
	return true


func _finish(job: Dictionary, outcome: String, cancelled_by: String = "", reason: String = "") -> bool:
	if job.status != "active":
		return false
	if outcome != "completed":
		var release: String = world.artifacts.reserve_exchange_release()
		if release.is_empty():
			push_error("Private exchange could not allocate its reserved terminal order")
			return false
		job.artifact_release = release
		if world.regions.has(job.buyer_region):
			world.regions[job.buyer_region].inventory.release(str(job.reservation))
	job.status = outcome
	job.cancelled_by = cancelled_by
	job.cancel_reason = reason
	job.finished_ms = int(world.elapsed_ms)
	active_jobs.erase(str(job.id))
	for actor: String in [str(job.buyer), str(job.seller)]:
		var person: Dictionary = body(actor)
		if person.is_empty():
			continue
		person.autonomous = bool(job.buyer_autonomous if actor == job.buyer else job.seller_autonomous)
		person.goal = str(job.buyer_goal if actor == job.buyer else job.seller_goal)
		person.retry_ms = int(job.buyer_retry_ms if actor == job.buyer else job.seller_retry_ms)
		world.invalidate_region(home(actor))
	return true


func cancel(actor: String, reason: String = "cancelled") -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if world != null and world.artifact_transfers.checking:
		return false
	for id: String in active_jobs.keys():
		var job: Dictionary = jobs[id]
		if actor in [job.buyer, job.seller]:
			var recorded_reason: String = reason if not reason.is_empty() else "cancelled"
			if recorded_reason == "seller_withdrew" and actor != job.seller:
				recorded_reason = "cancelled"
			return _finish(job, "cancelled", actor, recorded_reason)
	return false


func next_boundary_ms() -> int:
	var next: int = SimInventory.MAX_COUNT
	for id: String in active_jobs:
		var job: Dictionary = jobs[id]
		if not _connected(job):
			return mini(SimInventory.MAX_COUNT, int(world.elapsed_ms) + 1)
		next = mini(next, int(job.due_ms))
	return next


func settle_at_ms(now: int) -> void:
	for id: String in world._sorted_keys(active_jobs):
		if not active_jobs.has(id):
			continue
		var job: Dictionary = jobs[id]
		world.synchronize_region(str(job.buyer_region))
		world.synchronize_region(str(job.seller_region))
		if not _connected(job):
			_finish(job, "failed")
		elif now >= int(job.due_ms) and not _complete(job):
			_finish(job, "failed")


func pending(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var selected: Dictionary = {}
	for job: Dictionary in jobs.values():
		if actor not in [job.buyer, job.seller]:
			continue
		if selected.is_empty() or (job.status == "active" and selected.status != "active") or (job.status == selected.status and _later(job, selected)) or (job.status != "active" and selected.status != "active" and _later(job, selected)):
			selected = job
	if not selected.is_empty():
		result.append({"domain": "private_exchange", "id": selected.id, "performer": world.embodiment.subject_for_actor(str(selected.seller))})
	return result


static func _later(left: Dictionary, right: Dictionary) -> bool:
	if int(left.started_ms) != int(right.started_ms):
		return int(left.started_ms) > int(right.started_ms)
	return int(str(left.id).get_slice(":", 2)) > int(str(right.id).get_slice(":", 2))


func observe(actor: String, process: Dictionary) -> Dictionary:
	var job: Dictionary = jobs.get(process.get("id", ""), {})
	if job.is_empty() or actor not in [job.buyer, job.seller] or process.get("domain") != "private_exchange" or process.get("performer") != world.embodiment.subject_for_actor(str(job.seller)):
		return SimInteractionRequests.result("unconfirmed", "本人没有这次旧环交接的记录。")
	var line: String = "双方正在当面交割；钱与环仍在原处。"
	if job.status == "completed":
		line = "交割完成：原报价已付，原环已交到买方手边。"
	elif job.status != "active":
		line = "交接已中止，预约释放，钱与环没有转移。"
	return SimInteractionRequests.result("pending" if job.status == "active" else "completed" if job.status == "completed" else "cancelled", line, process)


func to_dict() -> Dictionary:
	return {"version": VERSION, "proposals": proposals.duplicate(true), "jobs": jobs.duplicate(true), "transfers": transfers.duplicate(true), "next_id": next_id}


func restore(data: Dictionary) -> bool:
	if not Schema.shape_valid(data, self):
		return false
	proposals = data.proposals.duplicate(true)
	jobs = data.jobs.duplicate(true)
	active_jobs.clear()
	for id: String in jobs:
		if jobs[id].status == "active":
			active_jobs[id] = true
	transfers = data.transfers.duplicate(true)
	next_id = int(data.next_id)
	return true


func cross_valid() -> bool:
	return Schema.cross_valid(self)


func _allocate(kind: String) -> String:
	var result: String = "private_exchange:%s:%d" % [kind, next_id]
	next_id += 1
	return result


static func _reply(ok: bool, code: String, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "code": code, "line": line, "id": id}
