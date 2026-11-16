extends RefCounted
## Pure next-step methods over the same detached self/known views as Planner.
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Duties = preload("res://scripts/sim/kernel/institution_duties.gd")

static func _execute(p: RefCounted, id: String, target: Dictionary, context: Dictionary = {}) -> Array:
	if target.is_empty() or int(target.get("tile", -1)) < 0 or p._denied(id, int(target.id)) or not p._spend(): return []
	var input: Dictionary = p._step(Operations.OPERATIONS[id], target, context)
	return [p._option(input, id, int(target.id))]

static func _inspect(p: RefCounted, target: Dictionary) -> Array:
	if not p._spend(): return []
	var step: Dictionary = p._inspect(target)
	return [p._option(step, "", int(target.get("id", 0)))] if not step.is_empty() else []

static func _fresh(p: RefCounted, target: int, period: int) -> bool:
	var account: Dictionary = p.actor.get("observations", {}).get(target, {})
	return account.get("direct", false) and p.at_ms - int(account.get("at_ms", -period)) < period

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
	var target: Dictionary = p.known.get(int(policy.target), {})
	if int(target.get("tile", -1)) < 0: return []
	# Inspect sources first, so the destination observation is still recent on
	# arriving at the records desk. Existing notices do not require a new source.
	var known_open: bool = false
	var last_closed: int = -1
	for account: Dictionary in p.actor.get("known_channels", {}).values():
		for post: Dictionary in account.posts.values():
			if post.organization != policy.organization or post.kind != policy.kind or post.target != policy.target or post.item != policy.item or post.operation != policy.operation: continue
			if post.state == "open": known_open = true
			else: last_closed = maxi(last_closed, int(post.closed_ms))
	var needs_sources: bool = not target.has("inventory") or Stock.known_quantity(p.actor, target, str(policy.item), "take", int(policy.organization)) < int(policy.low)
	if not known_open and needs_sources:
		for source: int in policy.sources:
			var place: Dictionary = p.known.get(source, {})
			if int(place.get("tile", -1)) < 0: return []
			if not place.has("inventory") or not _fresh(p, source, int(policy.review_ms)) or int(p.actor.observations.get(source, {}).get("at_ms", -1)) < last_closed: return _inspect(p, place)
	if not target.has("inventory") or not _fresh(p, int(policy.target), int(policy.review_ms)) or int(p.actor.observations.get(int(policy.target), {}).get("at_ms", -1)) < last_closed: return _inspect(p, target)
	var board: Dictionary = p.known.get(int(policy.channel), {})
	var read: Dictionary = p.actor.get("known_channels", {}).get(int(policy.channel), {})
	if read.is_empty() or int(board.get("post_revision", 0)) != int(read.get("revision", -1)) or p.at_ms - int(read.at_ms) >= int(policy.review_ms): return _execute(p, "read_channel", board)
	var count: int = Stock.known_quantity(p.actor, target, str(policy.item), "take", int(policy.organization))
	for channel: int in p.actor.get("known_channels", {}):
		for post: Dictionary in p.actor.known_channels[channel].posts.values():
			if post.state != "open" or post.organization != policy.organization or post.kind != policy.kind or post.target != policy.target or post.item != policy.item or post.operation != policy.operation: continue
			if count >= int(policy.desired) or post.blocked or int(post.reported) >= int(post.total) or (int(post.deadline_ms) > 0 and p.at_ms >= int(post.deadline_ms)):
				return _execute(p, "close_post", p.known.get(channel, {}), {"matter": int(post.matter)})
			return [] # The locally recorded matter is still being handled.
	if count >= int(policy.low): return []
	if policy.kind == "delivery" and _full(target): return []
	if policy.kind == "produce" and not target.get("process", {}).is_empty(): return []
	for source: int in policy.sources:
		var place: Dictionary = p.known.get(source, {})
		if int(place.get("tile", -1)) < 0: return []
		if not place.has("inventory") or not _fresh(p, source, int(policy.review_ms)): return _inspect(p, place)
	if not Duties.sources_ready(policy, p.actor, p.known): return []
	return _execute(p, "post_duty", board, {"appointment": int(policy.appointment)})

static func service(p: RefCounted, goal: Dictionary) -> Array:
	if not p.actor.get("responsibilities", {}).is_empty(): return []
	for board: Dictionary in p.ordered_targets:
		if int(board.get("organization", 0)) != int(goal.params.organization) or not board.has("post_revision") or not p._spend(): continue
		var read: Dictionary = p.actor.get("known_channels", {}).get(int(board.id), {})
		if read.is_empty() or int(read.revision) != int(board.post_revision): return _execute(p, "read_channel", board)
		if not read.is_empty():
			for post: Dictionary in read.posts.values():
				if not _actionable(p.actor, post, p.at_ms): continue
				return _execute(p, "accept_post", board, {"matter": int(post.matter)})
		var due: int = int(read.get("at_ms", -60000)) + mini(60000, 5000 * (1 << int(read.get("empty_reads", 0))))
		if p.at_ms >= due and not _fresh(p, int(board.id), 10000): return _execute(p, "read_channel", board)
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
	var stopped: bool = not target.is_empty() and int(target.get("tile", -1)) < 0
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
			if int(bundle.organization) != organization or bundle.purpose != purpose or (purpose == "supply" and int(bundle.get("origin", 0)) not in sources): continue
			count += int(bundle.items.get(item, 0))
		var complete: bool = not sources.is_empty()
		for source: int in sources:
			var place: Dictionary = p.known.get(source, {})
			if place.is_empty(): complete = false; continue
			if int(place.get("tile", -1)) < 0: continue
			if not place.has("inventory"): complete = false; continue
			if purpose == "supply" and Operations.OPERATIONS.get(place.get("process", {}).get("operation", ""), {}).get("recipe", {}).get("outputs", {}).has(item): complete = false
			count += Stock.known_quantity(p.actor, place, item, "take", organization)
		if complete and count < int(required[item]): return true
	return false

static func next_due(actor: Dictionary, clues: Dictionary, at: int) -> int:
	var due: int = at + 3600001
	for policy: Dictionary in actor.get("duties", {}).values():
		var observed: int = int(actor.get("observations", {}).get(int(policy.target), {}).get("at_ms", at))
		var review: int = observed + int(policy.review_ms)
		due = mini(due, review if review > at else at + int(policy.review_ms))
		var account: Dictionary = actor.get("known_channels", {}).get(int(policy.channel), {})
		review = int(account.get("at_ms", at)) + int(policy.review_ms)
		due = mini(due, review if review > at else at + int(policy.review_ms))
		for post: Dictionary in account.get("posts", {}).values():
			if post.state == "open" and int(post.deadline_ms) > at: due = mini(due, int(post.deadline_ms))
	for board: Dictionary in clues.values():
		if not board.has("post_revision") or not actor.get("permissions", {}).has(int(board.get("organization", 0))): continue
		var read: Dictionary = actor.get("known_channels", {}).get(int(board.id), {})
		if not read.is_empty() and not _recent_observation(actor, int(board.id), at): due = mini(due, maxi(at + 1000, int(read.at_ms) + mini(60000, 5000 * (1 << int(read.empty_reads)))))
	return due if due <= at + 3600000 else -1

static func _recent_observation(actor: Dictionary, target: int, at: int) -> bool:
	var observation: Dictionary = actor.get("observations", {}).get(target, {})
	return observation.get("direct", false) and at - int(observation.get("at_ms", -10000)) < 10000
