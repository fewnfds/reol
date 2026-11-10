extends RefCounted
## Composes voice intent, actual human routes and cross-domain consent off-line.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func validate(data: Variant, domain: RefCounted, source: Dictionary) -> bool:
	if not Shape.keys(data, ["version", "manual", "voice", "errands", "events", "social", "next_id"]) or data.version != 1 or not data.manual is String or not data.voice is Dictionary or not data.errands is Dictionary or not data.events is Array or not Shape.count(data.next_id, 1):
		return false
	var social := SimSocialMemory.new()
	if not data.social is Dictionary or not social.restore(data.social):
		return false
	if str(data.manual).is_empty():
		return data.voice.is_empty() and data.errands.is_empty() and data.events.is_empty() and data.next_id == 1 and social._actors.is_empty()
	if not source.residents.has(data.manual):
		return false
	var world: RefCounted = domain.world
	var soul: String = str(data.manual)
	var subject: String = "subject:soul:" + soul
	if not social._actors.has(subject):
		return false
	var allowed: Dictionary = {subject: true}
	for sim: RefCounted in world.regions.values():
		for actor: String in sim.synchronize_actors():
			allowed[world.embodiment.subject_for_actor(actor)] = true
	for id: String in social._actors:
		if not allowed.has(id):
			return false
	for observer: String in social.relationships:
		for other: String in social.relationships[observer]:
			if observer != subject and other != subject:
				return false
	for request: Dictionary in social.requests.values():
		if request.requester != subject or request.task != "carry_vessel" or not allowed.has(request.responder) or request.responder == subject or int(request.tick) > world.current_time:
			return false
	if not social.events.is_empty():
		return false
	var allocated: Dictionary = {}
	if not data.voice.is_empty():
		var row: Dictionary = data.voice
		if not Shape.keys(row, ["id", "soul", "verb", "target", "started_ms", "due_ms", "spent"]) or row.soul != soul or not domain.definitions.agency.actions.has(row.verb) or not row.target is String or not _allocated(row.id, "action", int(data.next_id), allocated):
			return false
		var terms: Dictionary = domain.definitions.agency.actions[row.verb]
		if not Shape.count(row.started_ms, 0, int(world.elapsed_ms)) or not Shape.count(row.due_ms, int(world.elapsed_ms) + 1) or row.due_ms - row.started_ms != terms.ms or not Shape.count(row.spent) or row.spent != terms.attention:
			return false
		if row.verb == "call" and domain.actor_home(row.target).is_empty() or row.verb != "call" and not row.target.is_empty():
			return false
		if source.residents[soul].awake == (row.verb == "wake") or not world.embodiment.controls(subject, "vessel:" + str(source.residents[soul].vessel), "communication"):
			return false
		for job: Dictionary in source.active.values():
			if job.soul == soul:
				return false
	var vessel: String = str(source.residents[soul].vessel)
	for actor: Variant in data.errands:
		var job: Variant = data.errands[actor]
		if not Shape.keys(job, ["id", "soul", "actor", "region", "request", "vessel", "goal_region", "goal_place", "phase", "path", "due_ms", "segment_started_ms", "segment_from", "started_ms", "previous_autonomous", "picked"]) or job.actor != actor or job.soul != soul or job.vessel != vessel or not job.previous_autonomous is bool or not job.picked is bool or not _allocated(job.id, "errand", int(data.next_id), allocated):
			return false
		if not job.region is String or not world.regions.has(job.region) or domain.actor_home(actor) != job.region or not job.goal_region is String or not world.regions.has(job.goal_region) or not world.regions[job.goal_region].places.has(job.goal_place) or not job.phase in ["approach", "pickup", "carry"] or not Shape.count(job.started_ms, 0, int(world.elapsed_ms)) or not Shape.count(job.due_ms, int(world.elapsed_ms) + 1):
			return false
		var profile: Dictionary = domain.definitions.minds[source.residents[soul].definition]
		if job.goal_region != profile.goal_region or job.goal_place != profile.goal_place or bool(job.picked) != (job.phase == "carry") or not _consent(social, job.request, subject, world.embodiment.subject_for_actor(actor), vessel, job.goal_region, job.goal_place):
			return false
		var body: Dictionary = world.regions[job.region].synchronize_actors()[actor]
		if body.autonomous or not body.active.is_empty() or source.active.has(actor) or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or world.artifacts.owns_actor(actor) or world.services != null and world.services.owns_actor(actor):
			return false
		var item: Dictionary = source.vessels[vessel]
		if job.picked and (item.region != job.region or item.container != "actor:" + str(actor)) or not job.picked and str(item.container).begins_with("actor:"):
			return false
		if not job.path is Array:
			return false
		for cell: Variant in job.path:
			if not Shape.cell_valid(cell):
				return false
		if job.phase == "pickup":
			if not job.path.is_empty() or not Shape.count(job.segment_started_ms, 0, int(world.elapsed_ms)) or job.due_ms > world.elapsed_ms + int(domain.definitions.verbs.take.ms):
				return false
		else:
			if not SimRouteTravel.valid_segment(job, body, int(world.elapsed_ms), float(world.regions[job.region].motion_rules.motion.speed)):
				return false
			var previous: Vector2i = SimRouteTravel.cell(body.cell)
			for cell: Array in job.path:
				var next: Vector2i = SimRouteTravel.cell(cell)
				if absi(next.x - previous.x) > 1 or absi(next.y - previous.y) > 1:
					return false
				previous = next
			var goal: Vector2i = SimRouteTravel.cell(world.regions[job.goal_region].places[job.goal_place].cell)
			if not job.path.is_empty() and job.phase == "carry" and previous != goal:
				return false
	var prior_ms: int = 0
	for event: Variant in data.events:
		if not Shape.keys(event, ["id", "soul", "actor", "kind", "at_ms", "line", "request"]) or not _allocated(event.id, "event", int(data.next_id), allocated) or event.soul != soul or not event.actor is String or not event.line is String or not event.request is String or not Shape.count(event.at_ms, prior_ms, int(world.elapsed_ms)):
			return false
		if not event.actor.is_empty() and domain.actor_home(event.actor).is_empty() or not event.kind in ["accepted", "refused", "unheard", "arrived", "interrupted", "observed", "wake", "sleep", "cancelled"]:
			return false
		if event.kind in ["accepted", "arrived", "interrupted"]:
			var profile: Dictionary = domain.definitions.minds[source.residents[soul].definition]
			if not _consent(social, event.request, subject, world.embodiment.subject_for_actor(event.actor), vessel, profile.goal_region, profile.goal_place):
				return false
		prior_ms = int(event.at_ms)
	return true


static func _consent(social: SimSocialMemory, id: Variant, subject: String, responder: String, vessel: String, region: String, place: String) -> bool:
	if not id is String:
		return false
	for request: Dictionary in social.requests.values():
		var terms: Dictionary = request.context.get("terms", {})
		if request.id == id and request.requester == subject and request.responder == responder and request.status == "accepted" and terms.get("vessel") == vessel and terms.get("region") == region and terms.get("place") == place:
			return true
	return false


static func _allocated(value: Variant, kind: String, next_id: int, seen: Dictionary) -> bool:
	if not value is String or seen.has(value) or value.get_slice_count(":") != 3 or not value.begins_with("soul_agency:" + kind + ":"):
		return false
	var suffix: String = value.get_slice(":", 2)
	if not suffix.is_valid_int() or suffix != str(int(suffix)) or not Shape.count(int(suffix), 1, next_id - 1):
		return false
	seen[value] = true
	return true
