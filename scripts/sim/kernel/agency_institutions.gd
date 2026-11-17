extends RefCounted
## Pure next-step methods over the same detached self/known views as Planner.
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Duties = preload("res://scripts/sim/kernel/institution_duties.gd")
const Cultivation = preload("res://scripts/sim/kernel/cultivation_duty.gd")

static func _execute(p: RefCounted, id: String, target: Dictionary, context: Dictionary = {}) -> Array:
	if target.is_empty() or int(target.get("tile", -1)) < 0 or p._denied(id, int(target.id)) or not p._spend(): return []
	var input: Dictionary = p._step(Operations.OPERATIONS[id], target, context)
	return [p._option(input, id, int(target.id))]

static func _inspect(p: RefCounted, target: Dictionary) -> Array:
	if not p._spend(): return []
	var step: Dictionary = p._inspect(target)
	return [p._option(step, "", int(target.get("id", 0)))] if not step.is_empty() else []

static func _observed(actor: Dictionary, target: int) -> int:
	var observation: Dictionary = actor.get("observations", {}).get(target, {})
	return int(observation.get("at_ms", -1)) if observation.get("direct", false) else -1

static func _channel_review(actor: Dictionary, board: Dictionary, at: int, period: int) -> Dictionary:
	var read: Dictionary = actor.get("known_channels", {}).get(int(board.get("id", 0)), {})
	if read.is_empty(): return {"step": "read_channel", "due_ms": at}
	var observed: int = _observed(actor, int(board.id))
	# Personal evidence revisions are not the carrier's content revision. A
	# newer read also supersedes an older sighting; rumours never renew a visit.
	if observed >= int(read.at_ms) and int(board.get("post_revision", -1)) > int(read.revision):
		return {"step": "read_channel", "due_ms": at}
	var last: int = int(read.at_ms)
	if int(board.get("post_revision", -1)) == int(read.revision): last = maxi(last, observed)
	var due: int = last + period
	return {"step": "inspect" if at >= due else "", "due_ms": due}

static func _matches(post: Dictionary, policy: Dictionary) -> bool:
	return post.organization == policy.organization and post.kind == policy.kind and post.target == policy.target and post.item == policy.item and post.operation == policy.operation

static func _open_posts(actor: Dictionary, policy: Dictionary) -> Array:
	var posts: Array = []
	for account: Dictionary in actor.get("known_channels", {}).values():
		for post: Dictionary in account.posts.values():
			if post.state == "open" and _matches(post, policy): posts.append(post)
	return posts

static func _service_period(read: Dictionary) -> int:
	return mini(60000, 5000 * (1 << int(read.get("empty_reads", 0))))

static func _full(target: Dictionary) -> bool:
	return int(target.get("capacity", -1)) >= 0 and int(target.get("inventory", {}).values().reduce(func(a: int, b: int): return a + b, 0)) >= int(target.capacity)

static func _actionable(actor: Dictionary, post: Dictionary, at: int) -> bool:
	if post.state != "open" or post.blocked or int(post.unclaimed) <= 0 or (int(post.deadline_ms) > 0 and at >= int(post.deadline_ms)): return false
	var operation: Dictionary = Operations.OPERATIONS["put" if post.kind == "delivery" else str(post.operation)]
	for capability: String in operation.required_capabilities:
		if not actor.body_capabilities.get(capability, false): return false
	return operation.required_method.is_empty() or Growth.introduced(actor, operation.required_method)

static func duty(p: RefCounted, goal: Dictionary) -> Array:
	var policy: Dictionary = p.actor.get("duties", {}).get(int(goal.params.appointment), {})
	if policy.is_empty(): return []
	if policy.kind == "cultivation": return Cultivation.next(p, policy)
	var step: Dictionary = _duty_step(p.actor, policy, p.known, p.at_ms)
	if step.is_empty(): return []
	var target: Dictionary = p.known.get(int(step.target), {})
	if step.kind == "inspect": return _inspect(p, target)
	return _execute(p, str(step.kind), target, step.get("input", {}))

static func _duty_step(actor: Dictionary, policy: Dictionary, known: Dictionary, at: int) -> Dictionary:
	var target: Dictionary = known.get(int(policy.target), {})
	if int(target.get("tile", -1)) < 0: return {}
	# Inspect sources first, so the destination observation is still recent on
	# arriving at the records desk. Existing notices do not require a new source.
	var known_open: bool = false
	var last_closed: int = -1
	for account: Dictionary in actor.get("known_channels", {}).values():
		for post: Dictionary in account.posts.values():
			if not _matches(post, policy): continue
			if post.state == "open": known_open = true
			else: last_closed = maxi(last_closed, int(post.closed_ms))
	var needs_sources: bool = not target.has("inventory") or Stock.known_quantity(actor, target, str(policy.item), "take", int(policy.organization)) < int(policy.low)
	if not known_open and needs_sources:
		for source: int in policy.sources:
			var place: Dictionary = known.get(source, {})
			if int(place.get("tile", -1)) < 0: return {}
			if _needs_inspection(actor, place, at, int(policy.review_ms), last_closed): return {"kind": "inspect", "target": source}
	if _needs_inspection(actor, target, at, int(policy.review_ms), last_closed): return {"kind": "inspect", "target": int(policy.target)}
	var count: int = Stock.known_quantity(actor, target, str(policy.item), "take", int(policy.organization))
	if not known_open and count >= int(policy.low): return {}
	var board: Dictionary = known.get(int(policy.channel), {})
	if int(board.get("tile", -1)) < 0: return {}
	var review: Dictionary = _channel_review(actor, board, at, int(policy.review_ms))
	if not str(review.step).is_empty(): return {"kind": review.step, "target": int(board.id)}
	for channel: int in actor.get("known_channels", {}):
		for post: Dictionary in actor.known_channels[channel].posts.values():
			if post.state != "open" or not _matches(post, policy): continue
			if count >= int(policy.desired) or post.blocked or int(post.reported) >= int(post.total) or (int(post.deadline_ms) > 0 and at >= int(post.deadline_ms)):
				return {"kind": "close_post", "target": channel, "input": {"matter": int(post.matter)}} if int(known.get(channel, {}).get("tile", -1)) >= 0 else {}
			return {} # The locally recorded matter is still being handled.
	if count >= int(policy.low) or (policy.kind == "delivery" and _full(target)) or (policy.kind == "produce" and not target.get("process", {}).is_empty()): return {}
	if not Duties.sources_ready(policy, actor, known): return {}
	return {"kind": "post_duty", "target": int(board.id), "input": {"appointment": int(policy.appointment)}}

static func _needs_inspection(actor: Dictionary, place: Dictionary, at: int, period: int, after: int) -> bool:
	var seen: int = _observed(actor, int(place.id))
	return not place.has("inventory") or seen < 0 or at >= seen + period or seen < after

static func service(p: RefCounted, goal: Dictionary) -> Array:
	if not p.actor.get("responsibilities", {}).is_empty(): return []
	for board: Dictionary in p.ordered_targets:
		if int(board.get("organization", 0)) != int(goal.params.organization) or not board.has("post_revision") or not p._spend(): continue
		var read: Dictionary = p.actor.get("known_channels", {}).get(int(board.id), {})
		var review: Dictionary = _channel_review(p.actor, board, p.at_ms, _service_period(read))
		if review.step == "read_channel": return _execute(p, "read_channel", board)
		if not read.is_empty():
			for post: Dictionary in read.posts.values():
				if not _actionable(p.actor, post, p.at_ms): continue
				return _execute(p, "accept_post", board, {"matter": int(post.matter)})
		if review.step == "inspect": return _inspect(p, board)
	return []

static func reports(p: RefCounted) -> Array:
	for receipt: Dictionary in p.actor.get("reports", []):
		var board: Dictionary = p.known.get(int(receipt.channel), {})
		var step: Array = _execute(p, "report_matter", board, {"share": int(receipt.share)})
		if not step.is_empty(): return step
	return []

static func blocked(p: RefCounted, terms: Dictionary) -> Array:
	var receipt: Dictionary = {}
	for entry: Dictionary in p.actor.get("channel_receipts", []):
		if entry.share == terms.share: receipt = entry; break
	if receipt.is_empty(): return []
	var target: Dictionary = p.known.get(int(terms.target), {})
	var stopped: bool = not target.is_empty() and (int(target.get("tile", -1)) < 0 or p.known_dead(target))
	if terms.kind == "delivery":
		stopped = stopped or (int(target.get("capacity", -1)) >= 0 and int(target.get("inventory", {}).values().reduce(func(a: int, b: int): return a + b, 0)) >= int(target.capacity))
	var failure: String = str(p.actor.get("operation_failures", {}).get("%s:%d" % ["put" if terms.kind == "delivery" else str(terms.operation), int(terms.target)], ""))
	stopped = stopped or failure in ["path_failed", "no_operation_place", "not_authorized", "target_gone"]
	if not stopped:
		if terms.kind == "produce" and target.get("process", {}).get("operation") == terms.operation and int(target.process.get("output_organization", 0)) == int(terms.organization): return []
		if failure in ["target_busy", "in_process_conflict"]: return []
		var required: Dictionary = {str(terms.item): 1} if terms.kind == "delivery" else Operations.OPERATIONS[terms.operation].required_items
		stopped = source_shortfall(p, required, int(terms.organization), "supply" if terms.kind == "delivery" else Stock.input_purpose(Operations.OPERATIONS[terms.operation]), terms.sources)
	if not stopped: return []
	return _execute(p, "report_matter", p.known.get(int(receipt.channel), {}), {"share": int(terms.share), "blocked": true})

static func source_shortfall(p: RefCounted, required: Dictionary, organization: int, purpose: String, sources: Array) -> bool:
	for item: String in required:
		var count: int = 0
		for bundle: Dictionary in p.actor.bundles:
			if int(bundle.organization) != organization or (organization > 0 and (bundle.purpose != purpose or (purpose == "supply" and int(bundle.get("origin", 0)) not in sources))): continue
			count += int(bundle.items.get(item, 0))
		var complete: bool = not sources.is_empty()
		for source: int in sources:
			var place: Dictionary = p.known.get(source, {})
			if place.is_empty(): complete = false; continue
			if int(place.get("tile", -1)) < 0: continue
			if not place.has("inventory"): complete = false; continue
			if purpose == "supply" and Operations.OPERATIONS.get(place.get("process", {}).get("operation", ""), {}).get("recipe", {}).get("outputs", {}).has(item): complete = false
			count += Duties.source_quantity(p.actor, place, item, organization, purpose)
		if complete and count < int(required[item]): return true
	return false

static func next_due(actor: Dictionary, clues: Dictionary, at: int) -> int:
	var due: int = at + 3600001
	for policy: Dictionary in actor.get("duties", {}).values():
		if policy.kind == "cultivation":
			for target: int in Duties.targets(policy):
				var observed: int = int(actor.get("observations", {}).get(target, {}).get("at_ms", at))
				var review: int = observed + int(policy.review_ms)
				due = mini(due, review if review > at else at + int(policy.review_ms))
			continue
		var observed: int = _observed(actor, int(policy.target))
		var review: int = observed + int(policy.review_ms)
		due = mini(due, review if review > at else at + int(policy.review_ms))
		var account: Dictionary = actor.get("known_channels", {}).get(int(policy.channel), {})
		var target: Dictionary = clues.get(int(policy.target), {})
		if not _open_posts(actor, policy).is_empty() or not target.has("inventory") or Stock.known_quantity(actor, target, str(policy.item), "take", int(policy.organization)) < int(policy.low):
			var board: Dictionary = clues.get(int(policy.channel), {})
			if not board.is_empty():
				review = int(_channel_review(actor, board, at, int(policy.review_ms)).due_ms)
				due = mini(due, review if review > at else at + int(policy.review_ms))
		for post: Dictionary in account.get("posts", {}).values():
			if post.state == "open" and int(post.deadline_ms) > at: due = mini(due, int(post.deadline_ms))
	for board: Dictionary in clues.values():
		if not actor.get("responsibilities", {}).is_empty() or int(board.get("tile", -1)) < 0 or not board.has("post_revision") or not actor.get("permissions", {}).has(int(board.get("organization", 0))): continue
		var read: Dictionary = actor.get("known_channels", {}).get(int(board.id), {})
		var period: int = _service_period(read)
		var review: int = int(_channel_review(actor, board, at, period).due_ms)
		due = mini(due, review if review > at else at + period)
	return due if due <= at + 3600000 else -1

static func review_due(actor: Dictionary, policy: Dictionary, at: int, clues: Dictionary = {}) -> bool:
	if policy.is_empty(): return false
	if policy.kind == "cultivation": return Cultivation.needs_review(actor, policy, at, clues)
	return not _duty_step(actor, policy, clues, at).is_empty()
