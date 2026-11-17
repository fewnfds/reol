extends "res://tests/institution_duties_smoke.gd"
const SharedPlanner = preload("res://scripts/sim/kernel/agency_planner.gd")
const Coordination = preload("res://scripts/sim/kernel/agency_institutions.gd")

func plan(w: RefCounted, actor: Dictionary, known: Dictionary, at: int) -> RefCounted:
	var p := SharedPlanner.new()
	p.configure(actor, w.operation_target(int(actor.id)), known, {}, Vector2(190, 190), at, {"window_ms": at, "work": 0, "cursor": 0, "goal_cursor": 0}, {})
	return p

func local_revision_and_review() -> void:
	var f: Dictionary = duties_fixture()
	var w: RefCounted = f.world
	w.release(3); w.objects.records[3].autonomous = false
	w.objects.add(f.stove, "meal", 6, Stock.right(0, f.org))
	var actor: Dictionary = w.livelihood._self_view(w, 3)
	var known: Dictionary = w.knowledge.known(3, 0)
	for target: int in [f.source, f.stove, f.destination, f.board]:
		known[target] = w.operation_target(target)
		actor.observations[target] = {"at_ms": 60000, "revision": 1, "direct": true}
	actor.known_channels[f.board] = {"at_ms": 0, "revision": 0, "empty_reads": 6, "posts": {}}
	var goal: Dictionary = {"params": {"appointment": int(f.kitchen)}}
	var policy: Dictionary = actor.duties[int(f.kitchen)]
	var p: RefCounted = plan(w, actor, known, 60000)
	check(Coordination.duty(p, goal).is_empty(), "A fresh unchanged board and sufficient stock forced another physical read")
	check(not Coordination.review_due(actor, policy, 60000, known), "A settled stock duty continued to block voluntary teaching")
	known[f.board].post_revision = 1
	p = plan(w, actor, known, 60000)
	check(Coordination.duty(p, goal).is_empty(), "Sufficient stock caused a board visit without any local responsibility to handle")
	known[f.stove].inventory.meal = 0
	known[f.stove].contents.erase("meal")
	p = plan(w, actor, known, 60000)
	var options: Array = Coordination.duty(p, goal)
	check(not options.is_empty() and options[0].step.input.kind == "read_channel", "A locally observed revision change did not refresh a needed notice")
	actor.known_channels[f.board].merge({"at_ms": 60000, "revision": 1}, true)
	p = plan(w, actor, known, 60000)
	options = Coordination.duty(p, goal)
	check(not options.is_empty() and options[0].step.input.kind == "post_duty" and Coordination.review_due(actor, actor.duties[f.kitchen], 60000, known), "Consent urgency disagreed with a ready shortage action")
	# A current contents read supersedes the old carrier image retained in the
	# detached view. Its smaller revision is not evidence of a new change.
	actor.known_channels[f.board].merge({"at_ms": 60000, "revision": 2}, true)
	actor.observations[f.board].at_ms = 50000
	p = plan(w, actor, known, 60000)
	options = Coordination.duty(p, goal)
	check(options.is_empty() or options[0].step.input.kind != "read_channel", "An older carrier image forced a second read of newer contents")
	# Enough goods do not hide a related open matter that still needs closing.
	known[f.stove] = w.operation_target(int(f.stove))
	actor.known_channels[f.board].merge({"at_ms": 60000, "revision": 1}, true)
	actor.observations[f.board].at_ms = 60000
	var post: Dictionary = policy.duplicate(true)
	post.merge({"state": "open", "matter": 42, "closed_ms": -1, "blocked": false, "reported": 0, "total": 6, "deadline_ms": 120000}, true)
	actor.known_channels[f.board].posts[42] = post
	p = plan(w, actor, known, 60000)
	options = Coordination.duty(p, goal)
	check(not options.is_empty() and options[0].step.input.kind == "close_post", "Sufficient goods abandoned a related open matter")
	check(Coordination.review_due(actor, policy, 60000, known), "A locally completed open matter was omitted from duty urgency")
	post.target = int(f.destination); post.blocked = true
	p = plan(w, actor, known, 60000)
	check(Coordination.duty(p, goal).is_empty() and not Coordination.review_due(actor, policy, 60000, known), "An unrelated blocked matter made a satisfied duty urgent")
	# Ordinary members only inspect an old carrier. Reading its public contents
	# is needed after actually seeing that its revision differs from their copy.
	actor.duties = {}; actor.responsibilities = {}; known[f.board].post_revision = 0
	actor.known_channels[f.board] = {"at_ms": 0, "revision": 0, "empty_reads": 6, "posts": {}}
	actor.observations[f.board].at_ms = 50000
	var service: Dictionary = {"params": {"organization": int(f.org)}}
	p = plan(w, actor, known, 60000)
	check(Coordination.service(p, service).is_empty(), "An unchanged carrier sighting failed to postpone a redundant remote visit")
	check(Coordination.next_due(actor, known, 60000) == 110000, "Scheduling ignored the same unchanged sighting used by planning")
	check(Coordination.next_due(actor, known, 120000) == 180000, "An overdue service review created a one-second polling loop")
	actor.observations[f.board].at_ms = 0
	p = plan(w, actor, known, 60000)
	options = Coordination.service(p, service)
	check(not options.is_empty() and options[0].step.kind == "inspect", "An expired carrier observation was treated as a new contents reading")
	actor.observations[f.board] = {"at_ms": 60000, "revision": 2, "direct": false}
	p = plan(w, actor, known, 60000)
	options = Coordination.service(p, service)
	check(not options.is_empty() and options[0].step.kind == "inspect", "A relayed carrier observation reset the recipient's direct inspection age")
	actor.responsibilities = {42: {}}
	check(Coordination.next_due(actor, known, 60000) == -1, "A member already serving a matter was repeatedly awakened for unavailable idle service")
	actor.responsibilities = {}; known[f.board].tile = -1
	check(Coordination.next_due(actor, known, 60000) == -1, "A personally absent carrier kept scheduling fruitless visits")

func _run() -> void:
	local_revision_and_review()
	print("INSTITUTION_OBSERVATION_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
