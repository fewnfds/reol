extends RefCounted
## Shape is staged before other owners; causal checks run on the full candidate.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const PROPOSAL_KEYS: Array[String] = ["id", "buyer", "seller", "buyer_subject", "seller_subject", "object", "source_event", "price", "currency", "decision", "at_ms", "artifact_floor"]
const JOB_KEYS: Array[String] = ["id", "proposal", "buyer", "seller", "buyer_region", "seller_region", "object", "source_event", "consent", "reservation", "artifact_action", "artifact_event", "artifact_release", "started_ms", "due_ms", "finished_ms", "status", "cancelled_by", "cancel_reason", "buyer_position", "seller_position", "buyer_autonomous", "seller_autonomous", "buyer_goal", "seller_goal", "buyer_retry_ms", "seller_retry_ms", "receipt"]
const TRANSFER_KEYS: Array[String] = ["job", "from", "to", "source", "target", "item", "amount", "artifact_event", "consent", "at_ms"]


static func inventory_scope(data: Variant, region: String) -> Dictionary:
	var result: Dictionary = {"reservations": {}, "operations": {}}
	if not data is Dictionary or not data.get("jobs") is Dictionary:
		return result
	for job: Variant in data.jobs.values():
		if job is Dictionary and job.get("status") == "active" and job.get("buyer_region") == region and SimInventory._nonempty(job.get("reservation")):
			result.reservations[job.reservation] = true
		elif job is Dictionary and job.get("status") == "completed" and job.get("buyer_region") == region and SimInventory._nonempty(job.get("receipt")):
			result.operations[job.receipt] = true
	return result


static func shape_valid(data: Variant, domain: RefCounted) -> bool:
	if not data is Dictionary or not Shape.keys(data, ["version", "proposals", "jobs", "transfers", "next_id"]) or data.version != SimPrivateExchange.VERSION or not data.proposals is Dictionary or not data.jobs is Dictionary or not data.transfers is Dictionary or not Shape.count(data.next_id, 1):
		return false
	if data.proposals.size() > int(domain.definitions.max_proposals) or data.jobs.size() > int(domain.definitions.max_jobs):
		return false
	var allocated: Dictionary = {}
	for id: Variant in data.proposals:
		var proposal: Variant = data.proposals[id]
		if not proposal is Dictionary or not Shape.keys(proposal, PROPOSAL_KEYS) or proposal.get("id") != id or not _allocated(id, "proposal", int(data.next_id), allocated):
			return false
		for field: String in ["buyer", "seller", "buyer_subject", "seller_subject", "object", "source_event", "currency", "decision"]:
			if not SimInventory._nonempty(proposal.get(field)):
				return false
		if proposal.buyer == proposal.seller or not Shape.count(proposal.get("price"), 1) or not Shape.count(proposal.get("at_ms")) or not Shape.count(proposal.get("artifact_floor"), 1):
			return false
	for id: Variant in data.jobs:
		var job: Variant = data.jobs[id]
		if not job is Dictionary or not Shape.keys(job, JOB_KEYS) or job.get("id") != id or not _allocated(id, "action", int(data.next_id), allocated):
			return false
		for field: String in ["proposal", "buyer", "seller", "buyer_region", "seller_region", "object", "source_event", "consent", "reservation", "artifact_action"]:
			if not SimInventory._nonempty(job.get(field)):
				return false
		if not job.get("artifact_event") is String or not job.get("artifact_release") is String or not job.get("status") in ["active", "completed", "cancelled", "failed"] or not job.get("cancelled_by") is String or not job.get("cancel_reason") is String or not job.get("receipt") is String:
			return false
		if not Shape.count(job.get("started_ms")) or not Shape.count(job.get("due_ms")) or not _signed_time(job.get("finished_ms")) or not Shape.position_valid(job.get("buyer_position")) or not Shape.position_valid(job.get("seller_position")):
			return false
		if not job.get("buyer_autonomous") is bool or not job.get("seller_autonomous") is bool:
			return false
		if not job.get("buyer_goal") is String or not job.get("seller_goal") is String or not Shape.count(job.get("buyer_retry_ms")) or not Shape.count(job.get("seller_retry_ms")):
			return false
	for id: Variant in data.transfers:
		var transfer: Variant = data.transfers[id]
		if not SimInventory._nonempty(id) or not Shape.keys(transfer, TRANSFER_KEYS):
			return false
		for field: String in ["job", "from", "to", "source", "target", "item", "artifact_event", "consent"]:
			if not SimInventory._nonempty(transfer.get(field)):
				return false
		if not Shape.count(transfer.get("amount"), 1) or not Shape.count(transfer.get("at_ms")):
			return false
	return true


static func cross_valid(domain: RefCounted) -> bool:
	var world: RefCounted = domain.world
	if world == null or world.artifacts == null:
		return false
	if domain.proposals.is_empty() and domain.jobs.is_empty():
		return domain.transfers.is_empty() and _no_orphan_records(domain, {}, {})
	if world.services == null:
		return false
	var memory: SimSocialMemory = world.services.social
	var proposal_signatures: Dictionary = {}
	var decision_ids: Dictionary = {}
	for proposal: Dictionary in domain.proposals.values():
		if domain.home(str(proposal.buyer)).is_empty() or domain.home(str(proposal.seller)).is_empty() or proposal.object != domain.definitions.object or int(proposal.price) != int(domain.definitions.price) or proposal.currency != domain.definitions.currency:
			return false
		if proposal.buyer_subject != world.embodiment.subject_for_actor(str(proposal.buyer)) or proposal.seller_subject != world.embodiment.subject_for_actor(str(proposal.seller)) or int(proposal.at_ms) > int(world.elapsed_ms):
			return false
		var source: Dictionary = _event(world.artifacts.events, str(proposal.source_event))
		if not _source_for(source, str(proposal.seller), str(proposal.object)) or int(source.at_ms) > int(proposal.at_ms):
			return false
		var terms: Dictionary = domain._terms(str(proposal.buyer), str(proposal.seller), str(proposal.object), str(proposal.source_event))
		var signature: String = JSON.stringify(SnapshotValues.normalized(terms), "", true)
		if proposal_signatures.has(signature) or decision_ids.has(proposal.decision):
			return false
		proposal_signatures[signature] = true
		decision_ids[proposal.decision] = true
		var decision: Dictionary = domain._decision(str(proposal.decision))
		if decision.get("task") != SimPrivateExchange.TASK or decision.get("requester") != proposal.buyer or decision.get("responder") != proposal.seller or decision.get("status") not in ["accepted", "refused"] or int(decision.get("tick", -1)) != floori(float(proposal.at_ms) / 60000.0):
			return false
		var decision_terms: Dictionary = terms.duplicate(true)
		decision_terms["artifact_floor"] = int(proposal.artifact_floor)
		if SnapshotValues.normalized(decision.get("context", {}).get("terms")) != SnapshotValues.normalized(decision_terms) or SnapshotValues.normalized(decision.get("policy")) != SnapshotValues.normalized(memory._normalized_policy(domain.definitions.policy)):
			return false
		if not SimArtifacts.Schema.serial_floor_valid(world.artifacts, int(proposal.artifact_floor), int(proposal.at_ms)):
			return false
		var source_row: Dictionary = {"object": proposal.object, "actor": proposal.seller, "region": domain.home(str(proposal.seller)), "started_ms": int(proposal.at_ms), "id": "artifact:action:%d" % int(proposal.artifact_floor)}
		if SimArtifacts.Schema.holder_source_before(source_row, world.artifacts) != proposal.source_event:
			return false
	var consent_ids: Dictionary = {}
	var actions: Dictionary = {}
	var reservation_ids: Dictionary = {}
	var receipt_ids: Dictionary = {}
	var all_jobs: Array = domain.jobs.values()
	for job: Dictionary in all_jobs:
		var proposal: Dictionary = domain.proposals.get(job.proposal, {})
		if proposal.is_empty() or domain._decision(str(proposal.decision)).get("status") != "accepted":
			return false
		for field: String in ["buyer", "seller", "object", "source_event"]:
			if job[field] != proposal[field]:
				return false
		if job.buyer_region != domain.home(str(job.buyer)) or job.seller_region != domain.home(str(job.seller)) or job.reservation != str(job.id) + ":coin":
			return false
		if not bool(job.seller_autonomous):
			return false
		if int(job.started_ms) < int(proposal.at_ms) or int(job.started_ms) > int(world.elapsed_ms) or int(job.due_ms) - int(job.started_ms) != int(domain.definitions.duration_ms):
			return false
		if consent_ids.has(job.consent) or reservation_ids.has(job.reservation) or actions.has(job.artifact_action):
			return false
		consent_ids[job.consent] = true
		reservation_ids[job.reservation] = true
		actions[job.artifact_action] = true
		var action_number: int = SimArtifacts.Schema._action_number(str(job.artifact_action))
		var source: Dictionary = _event(world.artifacts.events, str(job.source_event))
		if action_number < int(proposal.artifact_floor) or action_number >= world.artifacts.next_id or SimArtifacts.Schema._serial_number(str(source.get("id", "")), "event") >= action_number:
			return false
		if not consent_valid(memory, proposal, job) or not _historical_distance(domain, job):
			return false
		for other: Dictionary in all_jobs:
			if other.id == job.id or not _overlap(job, other):
				continue
			if job.object == other.object or job.buyer in [other.buyer, other.seller] or job.seller in [other.buyer, other.seller]:
				return false
		for previous: Dictionary in all_jobs:
			if previous.id != job.id and previous.proposal == job.proposal and previous.status == "cancelled" and previous.cancelled_by == previous.seller and previous.cancel_reason == "seller_withdrew" and _job_before(previous, job):
				return false
		if not _artifact_actions_valid(domain, job):
			return false
		if not _other_occupations_valid(world, job):
			return false
		var inventory: SimInventory = world.regions[job.buyer_region].inventory
		var reserved: Dictionary = inventory.reservations.get(job.reservation, {})
		if job.status == "active":
			if int(job.finished_ms) != -1 or int(job.due_ms) <= int(world.elapsed_ms) or not job.receipt.is_empty() or inventory.operations.has(str(job.id) + ":payment") or not job.artifact_event.is_empty() or not job.artifact_release.is_empty() or not job.cancelled_by.is_empty() or not job.cancel_reason.is_empty() or not domain._connected(job):
				return false
		elif job.status == "completed":
			if not reserved.is_empty() or int(job.finished_ms) != int(job.due_ms) or int(job.finished_ms) > int(world.elapsed_ms) or str(job.artifact_event).is_empty() or not job.artifact_release.is_empty() or not job.cancelled_by.is_empty() or not job.cancel_reason.is_empty() or job.receipt != str(job.id) + ":payment" or receipt_ids.has(job.receipt):
				return false
			var receipt: Dictionary = {"job": job.id, "from": job.buyer_region, "to": job.seller_region, "source": "actor:" + str(job.buyer), "target": "actor:" + str(job.seller), "item": str(domain.definitions.currency), "amount": int(domain.definitions.price), "artifact_event": job.artifact_event, "consent": job.consent, "at_ms": int(job.finished_ms)}
			if SnapshotValues.normalized(domain.transfers.get(job.receipt, {})) != SnapshotValues.normalized(receipt):
				return false
			var operation: Dictionary = {"kind": "consume", "container": "actor:" + str(job.buyer), "item": str(domain.definitions.currency), "amount": int(domain.definitions.price)}
			if job.buyer_region == job.seller_region:
				operation = {"kind": "transfer", "source": "actor:" + str(job.buyer), "target": "actor:" + str(job.seller), "item": str(domain.definitions.currency), "amount": int(domain.definitions.price), "reservation_id": str(job.reservation)}
			if SnapshotValues.normalized(inventory.operations.get(job.receipt, {})) != SnapshotValues.normalized(operation):
				return false
			receipt_ids[job.receipt] = true
		else:
			if not reserved.is_empty() or not job.receipt.is_empty() or inventory.operations.has(str(job.id) + ":payment") or not job.artifact_event.is_empty() or int(job.finished_ms) < int(job.started_ms) or int(job.finished_ms) > mini(int(job.due_ms), int(world.elapsed_ms)):
				return false
			if SimArtifacts.Schema._serial_number(job.artifact_release, "release") <= action_number or SimArtifacts.Schema._serial_number(job.artifact_release, "release") >= int(world.artifacts.next_id):
				return false
			if (job.status == "cancelled" and (job.cancelled_by not in [job.buyer, job.seller] or job.cancel_reason.is_empty())) or (job.status == "failed" and (not job.cancelled_by.is_empty() or not job.cancel_reason.is_empty())):
				return false
			if job.cancel_reason == "seller_withdrew" and job.cancelled_by != job.seller:
				return false
	if receipt_ids.size() != domain.transfers.size():
		return false
	for id: Variant in domain.transfers:
		if not receipt_ids.has(id):
			return false
	return _no_orphan_records(domain, decision_ids, consent_ids)


static func consent_valid(memory: SimSocialMemory, proposal: Dictionary, job: Dictionary) -> bool:
	var event: Dictionary = memory._event_by_id.get(job.consent, {})
	var details: Dictionary = {"participants": {"proposal": proposal.id, "job": job.id, "object": job.object, "source_event": job.source_event, "price": int(proposal.price), "currency": proposal.currency, "at_ms": int(job.started_ms), "buyer_position": job.buyer_position, "seller_position": job.seller_position}, "private": {"decision": proposal.decision}}
	if event.get("kind") != "private_exchange_consent" or event.get("actor") != job.seller or event.get("target") != job.buyer or event.get("witnesses") != [] or int(event.get("tick", -1)) != floori(float(job.started_ms) / 60000.0):
		return false
	if SnapshotValues.normalized(event.get("details")) != SnapshotValues.normalized(details):
		return false
	return memory.knowledge.get(job.buyer, {}).get(job.consent, {}).get("direct") == true and memory.knowledge.get(job.seller, {}).get(job.consent, {}).get("direct") == true


static func _historical_distance(domain: RefCounted, job: Dictionary) -> bool:
	var left := Vector2(float(job.buyer_position[0]), float(job.buyer_position[1]))
	var right := Vector2(float(job.seller_position[0]), float(job.seller_position[1]))
	var limit: float = minf(float(domain.definitions.interaction_cells), float(domain.world._content.interaction_requests.communication_cells)) * TileGrid.TILE_SIZE
	# Saved positions support distance and fixed elevation, not historical walls.
	return left.distance_to(right) <= limit and Space.level(domain.world, left) == Space.level(domain.world, right)


static func _artifact_actions_valid(domain: RefCounted, job: Dictionary) -> bool:
	var artifact: RefCounted = domain.world.artifacts
	var found: int = 0
	var rows: Array = artifact.events.duplicate()
	rows.append_array(artifact.active.values())
	for row: Dictionary in rows:
		var action: String = str(row.get("action", row.get("id", "")))
		if action == job.artifact_action:
			found += 1
			if job.status != "completed" or row.get("id") != job.artifact_event or row.get("kind") != "exchanged" or row.get("exchange") != job.id:
				return false
			continue
		if not _overlap(job, row):
			continue
		if row.get("actor") in [job.buyer, job.seller] or row.get("method", {}).get("guide") in [job.buyer, job.seller] or row.get("object") == job.object or row.get("draw", {}).get("target") == job.object:
			return false
	return found == (1 if job.status == "completed" else 0)


static func _other_occupations_valid(world: RefCounted, job: Dictionary) -> bool:
	# These original domains do not share the artifact serial. Compare only
	# proven half-open millisecond intervals, allowing adjacent boundaries.
	if world.health != null:
		for care: Dictionary in world.health.jobs.values():
			if (care.patient in [job.buyer, job.seller] or care.doctor in [job.buyer, job.seller]) and _external_overlap(job, care):
				return false
	if world.field_opportunities != null:
		for trip: Dictionary in world.field_opportunities.trips.values():
			if trip.actor in [job.buyer, job.seller] and _external_overlap(job, trip):
				return false
	return true


static func _external_overlap(exchange: Dictionary, other: Dictionary) -> bool:
	var end_exchange: int = SimInventory.MAX_COUNT if exchange.status == "active" else int(exchange.finished_ms)
	var end_other: int = SimInventory.MAX_COUNT if other.status == "active" else int(other.finished_ms)
	if end_exchange <= int(exchange.started_ms) or end_other <= int(other.started_ms):
		return false
	return int(exchange.started_ms) < end_other and int(other.started_ms) < end_exchange


static func _no_orphan_records(domain: RefCounted, decisions: Dictionary, consents: Dictionary) -> bool:
	var world: RefCounted = domain.world
	if world.services != null:
		for decision: Dictionary in world.services.social.requests.values():
			if decision.get("task") == SimPrivateExchange.TASK and not decisions.has(decision.id):
				return false
		for event: Dictionary in world.services.social.events:
			if event.get("kind") == "private_exchange_consent" and not consents.has(event.id):
				return false
	var reservations: Dictionary = {}
	var operations: Dictionary = {}
	for job: Dictionary in domain.jobs.values():
		if job.status == "active":
			reservations[job.reservation] = job.buyer_region
		elif job.status == "completed":
			operations[job.receipt] = job.buyer_region
	for region: String in world.regions:
		for id: String in world.regions[region].inventory.reservations:
			if id.begins_with("private_exchange:") and reservations.get(id, "") != region:
				return false
		for id: String in world.regions[region].inventory.operations:
			if id.begins_with("private_exchange:") and operations.get(id, "") != region:
				return false
	return true


static func _source_for(event: Dictionary, seller: String, object_id: String) -> bool:
	return event.get("object") == object_id and ((event.get("kind") == "taken" and event.get("actor") == seller) or (event.get("kind") == "exchanged" and event.get("recipient") == seller))


static func _event(events: Array, id: String) -> Dictionary:
	for event: Dictionary in events:
		if event.id == id:
			return event
	return {}


static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	var end_a: Array = _end_point(a)
	var end_b: Array = _end_point(b)
	return _point_before(int(a.get("started_ms", 0)), _start_order(a), int(end_b[0]), int(end_b[1])) and _point_before(int(b.get("started_ms", 0)), _start_order(b), int(end_a[0]), int(end_a[1]))


static func _job_before(previous: Dictionary, next: Dictionary) -> bool:
	var end: Array = _end_point(previous)
	return _point_before(int(end[0]), int(end[1]), int(next.started_ms), _start_order(next))


static func _point_before(left_ms: int, left_order: int, right_ms: int, right_order: int) -> bool:
	return left_ms < right_ms or (left_ms == right_ms and left_order < right_order)


static func _start_order(row: Dictionary) -> int:
	return SimArtifacts.Schema._action_number(str(row.get("artifact_action", row.get("action", row.get("id", "")))))


static func _end_point(row: Dictionary) -> Array:
	if row.has("artifact_action"):
		if row.get("status") == "active":
			return [SimInventory.MAX_COUNT, SimInventory.MAX_COUNT]
		var kind: String = "event" if row.get("status") == "completed" else "release"
		var id: String = str(row.get("artifact_event", "")) if kind == "event" else str(row.get("artifact_release", ""))
		return [int(row.get("finished_ms", 0)), SimArtifacts.Schema._serial_number(id, kind)]
	if row.has("at_ms"):
		return [int(row.at_ms), SimArtifacts.Schema._serial_number(str(row.get("id", "")), "event")]
	return [SimInventory.MAX_COUNT, SimInventory.MAX_COUNT]


static func _allocated(value: Variant, kind: String, next_id: int, used: Dictionary) -> bool:
	if not value is String or not value.begins_with("private_exchange:" + kind + ":") or value.get_slice_count(":") != 3:
		return false
	var suffix: String = value.get_slice(":", 2)
	if not suffix.is_valid_int() or suffix != str(int(suffix)) or int(suffix) < 1 or int(suffix) >= next_id or used.has(suffix):
		return false
	used[suffix] = true
	return true


static func _signed_time(value: Variant) -> bool:
	return value == -1 or Shape.count(value)
