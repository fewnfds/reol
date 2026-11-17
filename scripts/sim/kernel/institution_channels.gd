extends RefCounted
## Physical records and explicit reports belong to Institutions. A board never
## reads remote stock, deaths or current fulfilment when somebody consults it.
const State = preload("res://scripts/sim/kernel/state.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Results = preload("res://scripts/sim/kernel/activity_results.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const CHANNEL_LIMIT: int = 128
const POST_LIMIT: int = 32
const SIGNATURE_LIMIT: int = 64

static func metadata(owner: RefCounted, channel: int) -> Dictionary:
	return {"post_revision": int(owner.channels.get(channel, {}).get("revision", 0))}

static func _board(owner: RefCounted, channel: int) -> Dictionary:
	if not owner.channels.has(channel): owner.channels[channel] = {"revision": 0, "posts": {}}
	return owner.channels[channel]

static func _index(owner: RefCounted, channel: int, matter: int, share: int, actor: int) -> void:
	if not owner._channel_shares.has(actor): owner._channel_shares[actor] = []
	owner._channel_shares[actor].append({"channel": channel, "matter": matter, "share": share})

static func _unindex_post(owner: RefCounted, channel: int, post: Dictionary) -> void:
	for signature: Dictionary in post.signatures.values():
		var actor: int = signature.actor
		if not owner._channel_shares.has(actor): continue
		owner._channel_shares[actor] = owner._channel_shares[actor].filter(func(value: Dictionary): return value.channel != channel or value.matter != post.matter)
		if owner._channel_shares[actor].is_empty(): owner._channel_shares.erase(actor)

static func forget(owner: RefCounted, channel: int) -> void:
	for post: Dictionary in owner.channels.get(channel, {}).get("posts", {}).values(): _unindex_post(owner, channel, post)
	owner.channels.erase(channel)

static func retains_matter(owner: RefCounted, id: int) -> bool:
	for channel: Dictionary in owner.channels.values():
		if channel.posts.get(id, {}).get("state") == "open": return true
	return false

static func retains_share(owner: RefCounted, share: Dictionary) -> bool:
	return retains_matter(owner, int(share.matter))

static func own_receipts(owner: RefCounted, actor: int, pending: bool = false) -> Array:
	var result: Array = []
	for reference: Dictionary in owner._channel_shares.get(actor, []):
		var post: Dictionary = owner.channels.get(reference.channel, {}).get("posts", {}).get(reference.matter, {})
		var share: Dictionary = owner.shares.get(reference.share, {})
		if post.get("state") != "open" or share.is_empty(): continue
		var signature: Dictionary = post.signatures.get(reference.share, {})
		if pending and (share.state == "accepted" or (signature.get("reported", 0) == share.fulfilled and signature.get("status") != "accepted")): continue
		result.append({"channel": reference.channel, "matter": reference.matter, "share": share.id, "fulfilled": share.fulfilled, "state": share.state})
	return result

static func post_view(post: Dictionary) -> Dictionary:
	var result: Dictionary = State.copy(post.terms)
	result.merge({"matter": post.matter, "organization": post.organization, "issuer": post.issuer, "state": post.state, "closed_ms": post.closed_ms, "unclaimed": int(post.terms.total), "reported": 0, "blocked": false})
	for signature: Dictionary in post.signatures.values():
		result.unclaimed -= int(signature.quota) if signature.status == "accepted" else int(signature.reported)
		result.reported += int(signature.reported)
		result.blocked = result.blocked or signature.status == "blocked"
	return result

static func read(owner: RefCounted, world: RefCounted, actor: int, channel: int, at: int) -> Dictionary:
	var board: Dictionary = _board(owner, channel)
	world.knowledge.read_channel(world, actor, channel, board, at)
	return Results.completed({"channel": channel, "posts": board.posts.size()}, "records_read")

static func _clues(world: RefCounted, actor: int, targets: Array, at: int) -> Array:
	var result: Array = []
	for target: int in targets:
		var clue: Dictionary = world.knowledge.records.get(actor, {}).get("subjects", {}).get(target, {})
		if clue.is_empty() or int(clue.view.tile) < 0: return []
		var value: Dictionary = {}
		for field: String in ["id", "kind", "definition", "tile", "owner", "organization", "sapient"]: value[field] = clue.view[field]
		result.append({"view": value, "seen_ms": int(clue.seen_ms), "observer": int(clue.observer), "source": int(clue.source), "origin": str(clue.origin), "hops": int(clue.hops)})
	return result

static func _key(organization: int, duty: Dictionary) -> String:
	return "%d:%s:%d:%s:%s" % [organization, duty.kind, duty.target, duty.item, duty.operation]

static func _close(owner: RefCounted, world: RefCounted, actor: int, channel: int, post: Dictionary, at: int) -> bool:
	var board: Dictionary = owner.channels[channel]
	if not owner.matters.has(post.matter) or not owner.Matters._can_manage(owner, world, actor, owner.matters[post.matter]): return false
	if owner.matters.has(post.matter) and owner.matters[post.matter].state == "active" and not owner.cancel_matter(world, actor, post.matter): return false
	post.state = "closed"; post.closed_ms = at; board.revision += 1
	_unindex_post(owner, channel, post)
	return true

static func close_post(owner: RefCounted, world: RefCounted, actor: int, channel: int, matter: int, at: int) -> Dictionary:
	var post: Dictionary = _board(owner, channel).posts.get(matter, {})
	read(owner, world, actor, channel, at)
	if post.get("state") != "open": return Results.refused("post_unavailable")
	if not _close(owner, world, actor, channel, post, at): return Results.refused("not_authorized")
	read(owner, world, actor, channel, at)
	return Results.completed({"matter": matter, "channel": channel}, "post_closed")

static func post_duty(owner: RefCounted, world: RefCounted, actor: int, channel: int, appointment: int, at: int) -> Dictionary:
	var duty: Dictionary = owner.Duties.views(owner, actor).get(appointment, {})
	if duty.is_empty() or duty.get("channel") != channel: return Results.refused("not_authorized")
	var knowledge: Dictionary = world.knowledge.records.get(actor, {}).get("subjects", {}).get(int(duty.target), {})
	if knowledge.is_empty() or knowledge.origin not in ["seen", "receipt", "seed"] or not knowledge.view.has("inventory") or at - int(knowledge.seen_ms) > int(duty.review_ms): return Results.refused("inspection_required")
	var target: Dictionary = world.knowledge.view(actor, int(duty.target), at)
	if int(target.get("tile", -1)) < 0: return Results.refused("known_target_gone")
	var count: int = Stock.known_quantity(world.operation_actor(actor), target, duty.item, "take", int(duty.organization))
	var board: Dictionary = _board(owner, channel)
	var key: String = _key(int(duty.organization), duty)
	for other: int in owner.channels:
		for post: Dictionary in owner.channels[other].posts.values():
			if post.state != "open" or post.key != key: continue
			if other != channel: return Results.refused("already_posted_elsewhere")
			var public: Dictionary = post_view(post)
			var elapsed: bool = int(post.terms.deadline_ms) > 0 and at >= int(post.terms.deadline_ms)
			if count >= int(duty.desired) or elapsed or public.blocked or int(public.reported) >= int(post.terms.total):
				if not _close(owner, world, actor, channel, post, at): return Results.refused("not_authorized")
				read(owner, world, actor, channel, at)
				return Results.completed({"closed": int(post.matter)}, "post_closed")
			else:
				read(owner, world, actor, channel, at)
				return Results.completed({"matter": int(post.matter)}, "already_posted")
	if count >= int(duty.low):
		read(owner, world, actor, channel, at)
		return Results.completed({}, "stock_sufficient")
	if duty.kind == "delivery" and int(target.get("capacity", -1)) >= 0 and int(target.get("inventory", {}).values().reduce(func(a: int, b: int): return a + b, 0)) >= int(target.capacity):
		read(owner, world, actor, channel, at)
		return Results.completed({}, "destination_full")
	var last_closed: int = -1
	for channel_record: Dictionary in owner.channels.values():
		for post: Dictionary in channel_record.posts.values():
			if post.key == key and post.state == "closed": last_closed = maxi(last_closed, int(post.closed_ms))
	if int(knowledge.seen_ms) < last_closed: return Results.refused("inspection_required")
	for source: int in duty.sources:
		var observation: Dictionary = world.knowledge.records.get(actor, {}).get("subjects", {}).get(source, {})
		if observation.is_empty() or observation.origin == "heard" or not observation.view.has("inventory") or int(observation.seen_ms) < last_closed or at - int(observation.seen_ms) > int(duty.review_ms): return Results.refused("inspection_required")
	if not owner.Duties.sources_ready(duty, world.operation_actor(actor), world.knowledge.known(actor, at)):
		read(owner, world, actor, channel, at)
		return Results.completed({}, "source_unavailable")
	var targets: Array = [int(duty.target)] + duty.sources
	var clues: Array = _clues(world, actor, targets, at)
	if clues.size() != targets.size(): return Results.refused("unknown_task")
	if board.posts.size() >= POST_LIMIT:
		for id: int in board.posts.keys():
			if board.posts[id].state == "closed": board.posts.erase(id); break
	if board.posts.size() >= POST_LIMIT: return Results.refused("record_capacity")
	var total: int = int(duty.desired) - count
	var id: int = owner.create_matter(world, actor, {"kind": duty.kind, "organization": duty.organization, "target": duty.target, "item": duty.item, "operation": duty.operation, "sources": duty.sources, "total": total, "quota": mini(int(duty.quota), total), "deadline_ms": at + int(duty.deadline_ms)})
	if id == 0: return Results.refused("cannot_commission")
	var matter: Dictionary = owner.matters[id]
	var terms: Dictionary = {}
	for field: String in ["kind", "target", "item", "operation", "sources", "total", "quota", "deadline_ms", "version"]: terms[field] = State.copy(matter[field])
	board.posts[id] = {"matter": id, "organization": duty.organization, "issuer": actor, "appointment": appointment, "key": key, "terms": terms, "clues": clues, "signatures": {}, "state": "open", "posted_ms": at, "closed_ms": -1}
	board.revision += 1
	read(owner, world, actor, channel, at)
	return Results.completed({"matter": id, "channel": channel}, "matter_posted")

static func accept(owner: RefCounted, world: RefCounted, actor: int, channel: int, matter: int, at: int) -> Dictionary:
	var board: Dictionary = _board(owner, channel)
	var post: Dictionary = board.posts.get(matter, {})
	read(owner, world, actor, channel, at)
	if post.get("state") != "open" or post.signatures.size() >= SIGNATURE_LIMIT: return Results.refused("post_unavailable")
	var public: Dictionary = post_view(post)
	if public.blocked or int(public.unclaimed) <= 0 or (int(public.deadline_ms) > 0 and at >= int(public.deadline_ms)): return Results.refused("no_open_share")
	var operation: String = "put" if post.terms.kind == "delivery" else str(post.terms.operation)
	var view: Dictionary = world.operation_actor(actor)
	if not Operations.capability_reason(world.objects.records[actor], operation).is_empty() or (not Operations.OPERATIONS[operation].required_method.is_empty() and not preload("res://scripts/sim/kernel/growth.gd").introduced(view, Operations.OPERATIONS[operation].required_method)): return Results.refused("refused_capability")
	var share: int = owner.accept_share(world, actor, matter, mini(int(public.quota), int(public.unclaimed)))
	if share == 0: return Results.refused("cannot_accept_share")
	if not post.signatures.has(share):
		post.signatures[share] = {"actor": actor, "quota": owner.shares[share].quota, "reported": 0, "status": "accepted", "at_ms": at}
		_index(owner, channel, matter, share, actor)
		board.revision += 1
	read(owner, world, actor, channel, at)
	return Results.completed({"matter": matter, "share": share}, "accepted_share")

static func report(owner: RefCounted, world: RefCounted, actor: int, channel: int, share: int, blocked: bool, at: int) -> Dictionary:
	var obligation: Dictionary = owner.shares.get(share, {})
	if obligation.get("actor") != actor: return Results.refused("not_authorized")
	var board: Dictionary = _board(owner, channel)
	var post: Dictionary = board.posts.get(int(obligation.matter), {})
	read(owner, world, actor, channel, at)
	if post.get("state") != "open" or not post.signatures.has(share) or post.signatures[share].actor != actor: return Results.refused("post_unavailable")
	if blocked and obligation.state == "accepted" and not owner.release_share(world, actor, share): return Results.refused("cannot_release_share")
	var status: String = "blocked" if blocked else str(obligation.state)
	post.signatures[share].merge({"reported": int(obligation.fulfilled), "status": status, "at_ms": at}, true)
	board.revision += 1
	read(owner, world, actor, channel, at)
	return Results.completed({"matter": obligation.matter, "share": share, "reported": obligation.fulfilled, "blocked": blocked}, "matter_reported")

static func input_valid(owner: RefCounted, action: Dictionary) -> bool:
	match Operations.OPERATIONS.get(action.get("kind", ""), {}).get("handler", ""):
		"post_duty": return action.get("appointment") is int and action.appointment > 0 and action.appointment < owner.next_appointment
		"accept_post", "close_post": return action.get("matter") is int and action.matter > 0 and action.matter < owner.next_matter
		"report_matter": return action.get("share") is int and action.share > 0 and action.share < owner.next_share and action.get("blocked", false) is bool
	return true

static func commit(owner: RefCounted, world: RefCounted, actor: int, action: Dictionary, at: int) -> Dictionary:
	var channel: int = action.target
	var record: Dictionary = world.objects.records.get(channel, {})
	if not world.combat.alive(world, actor) or record.is_empty() or record.kind == "blueprint" or not owner.memberships.get(int(record.organization), {}).has(actor) or not world.facilities.definitions.get(record.definition, {}).get("capabilities", {}).has("records"): return Results.refused("not_authorized")
	if not input_valid(owner, action) or (not owner.channels.has(channel) and owner.channels.size() >= CHANNEL_LIMIT): return Results.refused("invalid_records_operation")
	match Operations.OPERATIONS[action.kind].handler:
		"read_channel": return read(owner, world, actor, channel, at)
		"post_duty": return post_duty(owner, world, actor, channel, action.appointment, at)
		"accept_post": return accept(owner, world, actor, channel, action.matter, at)
		"close_post": return close_post(owner, world, actor, channel, action.matter, at)
		"report_matter": return report(owner, world, actor, channel, action.share, bool(action.get("blocked", false)), at)
	return Results.refused("unknown_operation")

static func public_valid(owner: RefCounted, world: RefCounted, value: Variant) -> bool:
	if not value is Dictionary or value.size() != 17 or not value.get("matter") is int or value.matter < 1 or value.matter >= owner.next_matter or not value.get("organization") is int or not value.get("issuer") is int: return false
	if value.get("kind") not in ["delivery", "produce"]: return false
	if not value.get("closed_ms") is int or (value.get("state") == "open" and value.closed_ms != -1) or (value.get("state") == "closed" and (value.closed_ms < 0 or value.closed_ms > world.elapsed_ms)): return false
	var terms: Dictionary = {}
	for field: String in ["kind", "target", "item", "operation", "sources", "total", "quota", "deadline_ms", "version"]:
		if not value.has(field): return false
		terms[field] = value[field]
	terms.merge({"id": value.matter, "issuer": value.issuer, "organization": value.organization, "created_ms": 0, "state": "active", "archived": 0})
	if not owner.Matters._matter_valid(owner, world, terms) or value.get("state") not in ["open", "closed"] or not value.get("unclaimed") is int or not value.get("reported") is int or not value.get("blocked") is bool: return false
	return value.unclaimed >= 0 and value.unclaimed <= value.total and value.reported >= 0 and value.reported <= value.total and value.unclaimed + value.reported <= value.total

static func valid(owner: RefCounted, world: RefCounted) -> bool:
	if owner.channels.size() > CHANNEL_LIMIT: return false
	owner._channel_shares.clear()
	var open_keys: Dictionary = {}
	for id: Variant in owner.channels:
		var board: Variant = owner.channels[id]
		var record: Dictionary = world.objects.records.get(id, {})
		if not id is int or record.is_empty() or record.kind == "blueprint" or not world.facilities.definitions.get(record.definition, {}).get("capabilities", {}).has("records") or not board is Dictionary or board.size() != 2 or not board.get("revision") is int or board.revision < 0 or board.revision > 999999999999 or not board.get("posts") is Dictionary or board.posts.size() > POST_LIMIT: return false
		for matter_id: Variant in board.posts:
			var post: Variant = board.posts[matter_id]
			if not matter_id is int or matter_id < 1 or matter_id >= owner.next_matter or not post is Dictionary or post.size() != 11 or post.get("matter") != matter_id: return false
			for field: String in ["issuer", "appointment", "posted_ms", "closed_ms", "organization"]:
				if not post.get(field) is int: return false
			if post.issuer < 1 or post.issuer >= world.objects.next_id or post.appointment < 1 or post.appointment >= owner.next_appointment or not owner.organizations.has(post.organization) or record.organization != post.organization: return false
			if post.get("state") not in ["open", "closed"] or post.posted_ms < 0 or post.posted_ms > world.elapsed_ms or (post.state == "open" and post.closed_ms != -1) or (post.state == "closed" and (post.closed_ms < post.posted_ms or post.closed_ms > world.elapsed_ms)): return false
			if not post.get("terms") is Dictionary or post.terms.size() != 9: return false
			var terms: Dictionary = post.terms.duplicate(true)
			terms.merge({"id": matter_id, "issuer": post.issuer, "organization": post.organization, "created_ms": post.posted_ms, "state": "active", "archived": 0})
			if post.terms.get("kind") not in ["delivery", "produce"] or not owner.Matters._matter_valid(owner, world, terms) or not post.get("key") is String or post.key != _key(int(post.organization), post.terms): return false
			var appointment: Dictionary = owner.appointments.get(int(post.appointment), {})
			if appointment.get("actor") != post.issuer or appointment.get("organization") != post.organization: return false
			# Published terms may predate a legitimate revision. Identity and subject
			# never change; a snapshot of the current version must match in full.
			var canonical: Dictionary = owner.matters.get(matter_id, {})
			if not canonical.is_empty():
				for field: String in ["issuer", "organization", "kind", "target", "item", "operation", "sources", "created_ms"]:
					if canonical[field] != terms[field]: return false
				if int(terms.version) > int(canonical.version): return false
				if terms.version == canonical.version:
					for field: String in ["total", "quota", "deadline_ms"]:
						if canonical[field] != terms[field]: return false
			if post.state == "open":
				if not owner.matters.has(matter_id) or open_keys.has(post.key): return false
				open_keys[post.key] = true
			if not post.get("clues") is Array or post.clues.size() != 1 + post.terms.sources.size(): return false
			var expected: Array = [int(post.terms.target)] + post.terms.sources
			for index: int in post.clues.size():
				var clue: Variant = post.clues[index]
				if not clue is Dictionary or clue.size() != 6 or not clue.get("view") is Dictionary or clue.view.size() != 7 or not world.knowledge._valid_view(clue.view, expected[index], world.objects.next_id, world.elapsed_ms): return false
				if not clue.get("seen_ms") is int or clue.seen_ms < 0 or clue.seen_ms > post.posted_ms or not clue.get("observer") is int or clue.observer < 0 or clue.observer >= world.objects.next_id: return false
				var evidence: Dictionary = clue.duplicate(); evidence.erase("view"); evidence["received_ms"] = post.posted_ms
				if evidence.get("origin") == "seen": evidence.origin = "receipt"
				if not world.knowledge._valid_teaching(evidence, int(post.issuer), world.objects.next_id, world.elapsed_ms): return false
			if not post.get("signatures") is Dictionary or post.signatures.size() > SIGNATURE_LIMIT: return false
			var occupied: int = 0
			for share_id: Variant in post.signatures:
				var signature: Variant = post.signatures[share_id]
				if not share_id is int or share_id < 1 or share_id >= owner.next_share or not signature is Dictionary or signature.size() != 5: return false
				for field: String in ["actor", "quota", "reported", "at_ms"]:
					if not signature.get(field) is int: return false
				if signature.actor < 1 or signature.actor >= world.objects.next_id or signature.quota < 1 or signature.quota > int(post.terms.total) or signature.reported < 0 or signature.reported > signature.quota or signature.get("status") not in ["accepted", "completed", "released", "blocked"] or signature.at_ms < post.posted_ms or signature.at_ms > world.elapsed_ms: return false
				if signature.status == "completed" and signature.reported != signature.quota: return false
				occupied += int(signature.quota) if signature.status == "accepted" else int(signature.reported)
				if post.state == "open":
					var share: Dictionary = owner.shares.get(share_id, {})
					if share.get("matter") != matter_id or share.get("actor") != signature.actor or share.get("quota") != signature.quota or int(share.fulfilled) < int(signature.reported): return false
					_index(owner, id, matter_id, share_id, int(signature.actor))
			if occupied > int(post.terms.total): return false
	return true
