extends RefCounted
## Independent proof of conflict history; no view or duplicate body is trusted.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const TOP: Array[String] = ["version", "perception_since_ms", "next_id", "next_cost_id", "next_hit_id", "next_lesson_id", "conflicts", "actions", "hits", "projectiles", "barriers", "lessons"]
const ENCOUNTER: Array[String] = ["id", "region", "initiator", "defender", "intent", "started_ms", "last_ms", "next_step_ms", "ended_ms", "reason", "yielded", "people", "withdrawal", "cause"]
const ACTION: Array[String] = ["id", "number", "conflict", "actor", "method", "object", "started_ms", "effect_ms", "due_ms", "finished_ms", "status", "qi_spent", "stamina_spent", "direction", "emitted", "emission", "projectile_end", "hit_ids"]
const HIT: Array[String] = ["id", "action", "actor", "attacker", "region", "type", "at_ms", "impact", "absorbed", "guard_action", "origin", "position", "segment_from", "segment_to"]
const LESSON: Array[String] = ["id", "teacher", "pupil", "methods", "region", "started_ms", "due_ms", "finished_ms", "status", "teacher_autonomous", "pupil_autonomous", "teacher_position", "pupil_position"]
const SHOT: Array[String] = ["action", "conflict", "actor", "target", "position", "origin", "direction", "level", "spawned_ms", "last_ms", "travelled"]
const FLOAT32_EPSILON: float = 1.1920928955078125e-7


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, TOP) or not Shape.count(data.version, 3, 3) or not Shape.count(data.perception_since_ms, 0, int(domain.world.elapsed_ms)):
		return false
	for key: String in ["next_id", "next_cost_id", "next_hit_id", "next_lesson_id"]:
		if not Shape.count(data[key], 1):
			return false
	for key: String in ["conflicts", "actions", "hits", "projectiles", "barriers", "lessons"]:
		if not data[key] is Dictionary:
			return false
	if data.conflicts.size() != int(data.next_id) - 1 or data.actions.size() != int(data.next_cost_id) - 1 or data.hits.size() != int(data.next_hit_id) - 1 or data.lessons.size() != int(data.next_lesson_id) - 1:
		return false
	if not _lessons(data, domain) or not _encounters(data, domain) or not _actions(data, domain) or not _hits(data, domain):
		return false
	return _barriers(data, domain) and _projectiles(data, domain) and _own_intervals(data, int(domain.world.elapsed_ms))


static func _lessons(data: Dictionary, domain: RefCounted) -> bool:
	var previous_start: int = 0
	for number: int in range(1, int(data.next_lesson_id)):
		var id: String = "conflict:lesson:%d" % number
		var row: Variant = data.lessons.get(id)
		if not Shape.keys(row, LESSON) or row.id != id or not _person(row.teacher, domain) or not _person(row.pupil, domain) or row.teacher == row.pupil or row.region != domain.home(row.teacher):
			return false
		if not row.teacher_autonomous is bool or not row.pupil_autonomous is bool or not Shape.count(row.started_ms, previous_start, int(domain.world.elapsed_ms)) or not Shape.count(row.due_ms, int(row.started_ms) + int(domain.rules.lesson_ms), int(row.started_ms) + int(domain.rules.lesson_ms)):
			return false
		previous_start = int(row.started_ms)
		if not _process_time(row, int(domain.world.elapsed_ms), ["active", "completed", "interrupted"]):
			return false
		if not Shape.position_valid(row.teacher_position) or not Shape.position_valid(row.pupil_position) or _v(row.teacher_position).distance_to(_v(row.pupil_position)) > float(domain.rules.lesson_radius):
			return false
		var expected: Array[String] = []
		for method: String in domain.rules.methods:
			if _known(str(row.teacher), method, int(row.started_ms), data, domain, number) and not _known(str(row.pupil), method, int(row.started_ms), data, domain, number):
				expected.append(method)
		if expected.is_empty() or row.methods != expected:
			return false
	return true


static func _known(actor: String, method: String, at_ms: int, data: Dictionary, domain: RefCounted, before_lesson: int = -1) -> bool:
	if domain.rules.backgrounds.get(str(domain.body(actor).definition_id), []).has(method):
		return true
	var limit: int = int(data.next_lesson_id) if before_lesson == -1 else before_lesson
	for number: int in range(1, limit):
		var row: Dictionary = data.lessons["conflict:lesson:%d" % number]
		if row.pupil == actor and row.status == "completed" and int(row.finished_ms) <= at_ms and row.methods.has(method):
			return true
	return false


static func _encounters(data: Dictionary, domain: RefCounted) -> bool:
	var previous_start: int = 0
	for number: int in range(1, int(data.next_id)):
		var id: String = "conflict:encounter:%d" % number
		var row: Variant = data.conflicts.get(id)
		if not Shape.keys(row, ENCOUNTER) or row.id != id or not _person(row.initiator, domain) or not _person(row.defender, domain) or row.initiator == row.defender or row.region != domain.home(row.defender) or row.intent != "drive_off":
			return false
		if not row.cause is Dictionary or (not row.cause.is_empty() and (not Shape.keys(row.cause, ["domain", "id"]) or row.cause.domain != "source_care" or not SimInventory._nonempty(row.cause.id))):
			return false
		if not Shape.count(row.started_ms, previous_start, int(domain.world.elapsed_ms)) or not Shape.count(row.last_ms, int(row.started_ms), int(domain.world.elapsed_ms)) or not Shape.count(row.next_step_ms, int(row.last_ms) + int(domain.rules.step_ms), int(row.last_ms) + int(domain.rules.step_ms)) or not Shape.count(row.ended_ms, -1, int(domain.world.elapsed_ms)):
			return false
		previous_start = int(row.started_ms)
		if not Shape.keys(row.people, [row.initiator, row.defender]):
			return false
		if int(row.ended_ms) == -1:
			if row.reason != "" or row.yielded != "" or int(row.next_step_ms) <= int(domain.world.elapsed_ms) or int(domain.world.elapsed_ms) >= int(row.started_ms) + int(domain.rules.max_duration_ms):
				return false
		elif int(row.ended_ms) < int(row.last_ms) or row.reason not in ["yielded", "control_lost", "separated", "withdrawn"] or not row.yielded is String or (not row.yielded.is_empty() and not row.people.has(row.yielded)):
			return false
		if not _known(str(row.initiator), "sword", int(row.started_ms), data, domain) and not _known(str(row.initiator), "qi_bolt", int(row.started_ms), data, domain):
			return false
		if not _withdrawal(row, domain):
			return false
		for actor: String in row.people:
			var person: Variant = row.people[actor]
			if not Shape.keys(person, ["previous_autonomous", "action", "ready_ms", "sight"]) or not person.previous_autonomous is bool or not person.action is String or not Shape.count(person.ready_ms, int(row.started_ms)):
				return false
			if not _sight(person.sight, row, data, domain):
				return false
			if int(row.ended_ms) != -1 and not person.action.is_empty():
				return false
	return true


static func _sight(sight: Variant, encounter: Dictionary, data: Dictionary, domain: RefCounted) -> bool:
	if not sight is Dictionary:
		return false
	if sight.is_empty():
		return true
	if not Shape.keys(sight, ["at_ms", "observer_position", "position", "level"]):
		return false
	var earliest: int = maxi(int(encounter.started_ms), int(data.perception_since_ms))
	var latest: int = int(domain.world.elapsed_ms) if int(encounter.ended_ms) == -1 else int(encounter.ended_ms)
	if not Shape.count(sight.at_ms, earliest, latest) or not Shape.position_valid(sight.observer_position) or not Shape.position_valid(sight.position) or not Shape.count(sight.level, 0, 3):
		return false
	var observer: Vector2 = _v(sight.observer_position)
	var position: Vector2 = _v(sight.position)
	if observer.distance_to(position) > float(domain.rules.sight_radius) + 0.001:
		return false
	# These are the recorded historical points, never the target's hidden live
	# location. Static elevation is known; doors and construction can have
	# changed since the observation and must not rewrite that older evidence.
	if domain.world.get("map_data") != null and (Space.level(domain.world, observer) != int(sight.level) or Space.level(domain.world, position) != int(sight.level)):
		return false
	# Even at now, a subsequent command may have moved a body in the same
	# millisecond. Do not confuse a timestamp with a complete movement journal.
	return true


static func _withdrawal(encounter: Dictionary, domain: RefCounted) -> bool:
	var row: Variant = encounter.withdrawal
	if not row is Dictionary:
		return false
	if row.is_empty():
		# Manual participants and a body that lost a control channel need not
		# have an automatic retreat. Saved legacy retreats remain decisions,
		# not a policy we retroactively recalculate at load time.
		if int(encounter.ended_ms) == -1 or encounter.yielded == "":
			return true
		var person: Variant = encounter.people.get(encounter.yielded)
		if not person is Dictionary or not person.get("previous_autonomous") is bool:
			return false
		if not bool(person.previous_autonomous) or encounter.reason == "control_lost":
			return true
		# V2 never created initiator retreats. A cause-free historical decision
		# stays valid; an automatic defender or new care initiator still needs
		# its actual retreat proof and cannot erase that physical process.
		return encounter.yielded != encounter.defender and encounter.cause.is_empty()
	if int(encounter.ended_ms) == -1 or not encounter.people.has(encounter.yielded) or not Shape.keys(row, ["actor", "origin", "direction", "distance", "last_ms", "next_step_ms", "finished_ms", "status", "reason"]) or row.actor != encounter.yielded or not Shape.position_valid(row.origin) or not _unit(row.direction) or not _distance(row.distance, 0, float(domain.rules.retreat_distance)):
		return false
	if not Shape.count(row.last_ms, int(encounter.ended_ms), int(domain.world.elapsed_ms)) or not Shape.count(row.next_step_ms, int(row.last_ms) + int(domain.rules.step_ms), int(row.last_ms) + int(domain.rules.step_ms)) or not Shape.count(row.finished_ms, -1, int(domain.world.elapsed_ms)):
		return false
	var speed: float = float(domain.world.regions[domain.home(str(row.actor))].motion_rules.motion.speed) * float(domain.rules.ai_speed_fraction)
	if float(row.distance) > speed * float(int(row.last_ms) - int(encounter.ended_ms)) / 1000.0 + 0.001:
		return false
	if row.status == "active":
		return row.finished_ms == -1 and row.reason == "" and int(row.next_step_ms) > int(domain.world.elapsed_ms) and float(row.distance) < float(domain.rules.retreat_distance)
	if row.status != "completed" or int(row.finished_ms) < int(encounter.ended_ms) or row.reason not in ["distance", "blocked", "control_lost"]:
		return false
	if row.finished_ms != row.last_ms:
		return false
	return row.reason != "distance" or absf(float(row.distance) - float(domain.rules.retreat_distance)) < 0.001


static func _actions(data: Dictionary, domain: RefCounted) -> bool:
	var previous_start: int = 0
	var active: Dictionary = {}
	for number: int in range(1, int(data.next_cost_id)):
		var id: String = "conflict:action:%d" % number
		var row: Variant = data.actions.get(id)
		if not Shape.keys(row, ACTION) or row.id != id or not Shape.count(row.number, number, number) or not _person(row.actor, domain) or not row.conflict is String or not data.conflicts.has(row.conflict) or not row.method is String or not domain.rules.methods.has(row.method):
			return false
		var encounter: Dictionary = data.conflicts[row.conflict]
		if not encounter.people.has(row.actor) or not Shape.count(row.started_ms, maxi(previous_start, int(encounter.started_ms)), int(domain.world.elapsed_ms)) or int(encounter.ended_ms) != -1 and int(row.started_ms) > int(encounter.ended_ms):
			return false
		previous_start = int(row.started_ms)
		if not _known(str(row.actor), str(row.method), int(row.started_ms), data, domain) or not _process_time(row, int(domain.world.elapsed_ms), ["active", "completed", "interrupted"]):
			return false
		var spec: Dictionary = domain.rules.methods[row.method]
		if not Shape.count(row.effect_ms, int(row.started_ms) + int(spec.prepare_ms), int(row.started_ms) + int(spec.prepare_ms)) or not Shape.count(row.due_ms, int(row.started_ms) + domain.duration(str(row.method)), int(row.started_ms) + domain.duration(str(row.method))) or row.qi_spent != spec.qi or row.stamina_spent != spec.stamina or not Shape.count(row.qi_spent) or not Shape.count(row.stamina_spent) or not _unit(row.direction):
			return false
		if not row.emitted is bool or not row.emission is Dictionary or not row.projectile_end is Dictionary or not row.hit_ids is Array or row.hit_ids.size() > 1:
			return false
		if row.method == "sword":
			if not row.object is String or not domain.world.artifacts.objects.has(row.object) or not domain.world.artifacts.has_capability(row.object, "weapon"):
				return false
		elif row.object != "":
			return false
		if bool(row.emitted):
			if not Shape.keys(row.emission, ["origin", "level", "at_ms"]) or not Shape.position_valid(row.emission.origin) or not Shape.count(row.emission.level, 0, 3) or not Shape.count(row.emission.at_ms, int(row.effect_ms), mini(int(row.due_ms), int(domain.world.elapsed_ms))):
				return false
			if domain.world.get("map_data") != null and Space.level(domain.world, _v(row.emission.origin)) != int(row.emission.level):
				return false
		elif not row.emission.is_empty() or not row.projectile_end.is_empty() or not row.hit_ids.is_empty() or row.status == "completed":
			return false
		if row.status == "active":
			if int(encounter.ended_ms) != -1 or encounter.people[row.actor].action != id or active.has(row.actor) or (not bool(row.emitted) and int(row.effect_ms) <= int(domain.world.elapsed_ms)):
				return false
			active[row.actor] = id
		elif encounter.people[row.actor].action == id or int(encounter.ended_ms) != -1 and int(row.finished_ms) > int(encounter.ended_ms):
			return false
		if row.method != "qi_bolt" and not row.projectile_end.is_empty():
			return false
		if row.method == "qi_guard" and not row.hit_ids.is_empty():
			return false
	for encounter: Dictionary in data.conflicts.values():
		for actor: String in encounter.people:
			var id: String = str(encounter.people[actor].action)
			if not id.is_empty() and (not active.has(actor) or active[actor] != id or data.actions[id].conflict != encounter.id):
				return false
	return _action_intervals(data, int(domain.world.elapsed_ms))


static func _hits(data: Dictionary, domain: RefCounted) -> bool:
	var previous_at: int = 0
	var used_actions: Dictionary = {}
	for number: int in range(1, int(data.next_hit_id)):
		var id: String = "conflict:hit:%d" % number
		var hit: Variant = data.hits.get(id)
		if not Shape.keys(hit, HIT) or hit.id != id or not hit.action is String or not data.actions.has(hit.action) or not _person(hit.actor, domain) or not _person(hit.attacker, domain) or hit.actor == hit.attacker or hit.region != domain.home(hit.actor) or hit.type != "contusion" or not Shape.count(hit.at_ms, previous_at, int(domain.world.elapsed_ms)):
			return false
		previous_at = int(hit.at_ms)
		var action: Dictionary = data.actions[hit.action]
		if not bool(action.emitted) or action.actor != hit.attacker or action.method == "qi_guard" or action.hit_ids != [id] or used_actions.has(action.id):
			return false
		used_actions[action.id] = true
		var spec: Dictionary = domain.rules.methods[action.method]
		if not Shape.count(hit.impact, 0, int(spec.impact)) or not Shape.count(hit.absorbed, 0, int(spec.impact)) or int(hit.impact) + int(hit.absorbed) != int(spec.impact) or not hit.guard_action is String:
			return false
		for field: String in ["origin", "position", "segment_from", "segment_to"]:
			if not Shape.position_valid(hit[field]):
				return false
		if not _v(hit.origin).is_equal_approx(_v(action.emission.origin)) or int(hit.at_ms) < int(action.emission.at_ms):
			return false
		if domain.world.get("map_data") != null and Space.level(domain.world, _v(hit.position)) != int(action.emission.level):
			return false
		if action.method == "sword":
			if int(hit.at_ms) >= int(action.effect_ms) + int(spec.contact_ms) or int(hit.at_ms) > _end_time(action, int(domain.world.elapsed_ms)) or hit.segment_from != hit.origin or hit.segment_to != hit.position or not Space.in_fan(_v(hit.origin), _v(hit.position), _v(action.direction), float(spec.reach), float(spec.half_angle_degrees)):
				return false
		else:
			var elapsed: int = int(hit.at_ms) - int(action.emission.at_ms)
			if elapsed < int(domain.rules.step_ms) or posmod(elapsed, int(domain.rules.step_ms)) != 0:
				return false
			var limit: float = minf(float(spec.reach), float(spec.speed) * float(int(hit.at_ms) - int(action.emission.at_ms)) / 1000.0)
			var before: float = minf(float(spec.reach), float(spec.speed) * float(elapsed - int(domain.rules.step_ms)) / 1000.0)
			var tolerance: float = _projectile_tolerance(_v(hit.origin), limit, spec, int(domain.rules.step_ms))
			if not _on_ray(_v(hit.segment_from), action.emission, action.direction, limit, tolerance) or not _on_ray(_v(hit.segment_to), action.emission, action.direction, limit, tolerance) or _v(hit.segment_from).distance_to(_v(hit.segment_to)) > float(spec.speed) * int(domain.rules.step_ms) / 1000.0 + tolerance or Space.segment_distance(_v(hit.segment_from), _v(hit.segment_to), _v(hit.position)) > float(domain.rules.projectile_radius) + 0.001:
				return false
			if _v(hit.segment_from).distance_to(_v(hit.origin) + _v(action.direction) * before) > tolerance or _v(hit.segment_to).distance_to(_v(hit.origin) + _v(action.direction) * limit) > tolerance:
				return false
			if action.projectile_end.get("reason") != "hit" or action.projectile_end.get("at_ms") != hit.at_ms:
				return false
			var closest: Vector2 = Geometry2D.get_closest_point_to_segment(_v(hit.position), _v(hit.segment_from), _v(hit.segment_to))
			if not action.projectile_end.get("position") is Array or _v(action.projectile_end.position).distance_to(closest) > tolerance:
				return false
	for action: Dictionary in data.actions.values():
		if not action.hit_ids.is_empty() and not used_actions.has(action.id):
			return false
	return true


static func _barriers(data: Dictionary, domain: RefCounted) -> bool:
	var expected: Dictionary = {}
	var guard_actions: Array[Dictionary] = []
	for number: int in range(1, int(data.next_cost_id)):
		var action: Dictionary = data.actions["conflict:action:%d" % number]
		if action.method != "qi_guard" or not bool(action.emitted):
			continue
		for prior: Dictionary in guard_actions:
			if prior.actor == action.actor and int(prior.emission.at_ms) + int(domain.rules.methods.qi_guard.duration_ms) > int(action.emission.at_ms) and _guard_remaining(prior.id, int(action.emission.at_ms), -1, data, domain, true) > 0:
				return false
		guard_actions.append(action)
		var remaining: int = int(domain.rules.methods.qi_guard.capacity)
		var until: int = int(action.emission.at_ms) + int(domain.rules.methods.qi_guard.duration_ms)
		for hit_number: int in range(1, int(data.next_hit_id)):
			var hit: Dictionary = data.hits["conflict:hit:%d" % hit_number]
			if hit.guard_action != action.id:
				continue
			var impact: int = int(domain.rules.methods[data.actions[hit.action].method].impact)
			if hit.actor != action.actor or int(hit.at_ms) < int(action.emission.at_ms) or int(hit.at_ms) >= until or int(hit.absorbed) != mini(remaining, impact) or int(hit.absorbed) <= 0:
				return false
			remaining -= int(hit.absorbed)
		if remaining > 0 and until > int(domain.world.elapsed_ms):
			if expected.has(action.actor):
				return false
			expected[action.actor] = {"action": action.id, "remaining": remaining, "until_ms": until}
	for number: int in range(1, int(data.next_hit_id)):
		var hit: Dictionary = data.hits["conflict:hit:%d" % number]
		var available: String = ""
		var amount: int = 0
		for action: Dictionary in guard_actions:
			if action.actor != hit.actor or int(action.emission.at_ms) > int(hit.at_ms) or int(action.emission.at_ms) + int(domain.rules.methods.qi_guard.duration_ms) <= int(hit.at_ms):
				continue
			var remaining: int = _guard_remaining(action.id, int(hit.at_ms), number, data, domain)
			if remaining > 0:
				if not available.is_empty():
					return false
				available = str(action.id)
				amount = mini(remaining, int(domain.rules.methods[data.actions[hit.action].method].impact))
		if hit.guard_action != available or int(hit.absorbed) != amount:
			return false
	if not Shape.keys(data.barriers, expected.keys()):
		return false
	for actor: String in expected:
		var barrier: Variant = data.barriers[actor]
		var proof: Dictionary = expected[actor]
		if not Shape.keys(barrier, ["action", "remaining", "until_ms"]) or not barrier.action is String or barrier.action != proof.action:
			return false
		# JSON restores integral numbers as floats. Check scalar integer values,
		# never nested Dictionary equality, while still rejecting bools/fractions.
		if not Shape.count(barrier.remaining, int(proof.remaining), int(proof.remaining)) or not Shape.count(barrier.until_ms, int(proof.until_ms), int(proof.until_ms)):
			return false
	return true


static func _guard_remaining(id: String, at_ms: int, before_hit: int, data: Dictionary, domain: RefCounted, strict_time: bool = false) -> int:
	var remaining: int = int(domain.rules.methods.qi_guard.capacity)
	var limit: int = int(data.next_hit_id) if before_hit == -1 else before_hit
	for number: int in range(1, limit):
		var hit: Dictionary = data.hits["conflict:hit:%d" % number]
		if hit.guard_action == id and (int(hit.at_ms) < at_ms if strict_time else int(hit.at_ms) <= at_ms):
			remaining -= int(hit.absorbed)
	return remaining


static func _projectiles(data: Dictionary, domain: RefCounted) -> bool:
	var expected: Dictionary = {}
	for action: Dictionary in data.actions.values():
		if action.method != "qi_bolt" or not bool(action.emitted):
			continue
		var spec: Dictionary = domain.rules.methods.qi_bolt
		if action.projectile_end.is_empty():
			expected[action.id] = true
			var shot: Variant = data.projectiles.get(action.id)
			if not Shape.keys(shot, SHOT) or shot.action != action.id or shot.conflict != action.conflict or shot.actor != action.actor or not _person(shot.target, domain) or shot.target == shot.actor or shot.origin != action.emission.origin or shot.direction != action.direction or shot.level != action.emission.level or shot.spawned_ms != action.emission.at_ms:
				return false
			if not Shape.count(shot.last_ms, int(shot.spawned_ms), int(domain.world.elapsed_ms)) or int(shot.last_ms) + int(domain.rules.step_ms) <= int(domain.world.elapsed_ms) or not Shape.position_valid(shot.position) or not _distance(shot.travelled, 0, float(spec.reach), false):
				return false
			if posmod(int(shot.last_ms) - int(shot.spawned_ms), int(domain.rules.step_ms)) != 0:
				return false
			var distance: float = float(spec.speed) * float(int(shot.last_ms) - int(shot.spawned_ms)) / 1000.0
			var tolerance: float = _projectile_tolerance(_v(shot.origin), distance, spec, int(domain.rules.step_ms))
			if absf(float(shot.travelled) - distance) > 0.001 or _v(shot.position).distance_to(_v(shot.origin) + _v(shot.direction) * distance) > tolerance:
				return false
		else:
			var end: Dictionary = action.projectile_end
			var maximum_error: float = _projectile_tolerance(_v(action.emission.origin), float(spec.reach), spec, int(domain.rules.step_ms))
			if not Shape.keys(end, ["at_ms", "reason", "position", "travelled"]) or end.reason not in ["blocked", "range", "hit"] or not Shape.count(end.at_ms, int(action.emission.at_ms), int(domain.world.elapsed_ms)) or not Shape.position_valid(end.position) or not _distance(end.travelled, 0, float(spec.reach) + maximum_error):
				return false
			var elapsed: int = int(end.at_ms) - int(action.emission.at_ms)
			if elapsed < int(domain.rules.step_ms) or posmod(elapsed, int(domain.rules.step_ms)) != 0:
				return false
			var limit: float = minf(float(spec.reach), float(spec.speed) * float(int(end.at_ms) - int(action.emission.at_ms)) / 1000.0)
			var tolerance: float = _projectile_tolerance(_v(action.emission.origin), limit, spec, int(domain.rules.step_ms))
			if float(end.travelled) > limit + tolerance or not _on_ray(_v(end.position), action.emission, action.direction, float(end.travelled), tolerance) or absf(_v(end.position).distance_to(_v(action.emission.origin)) - float(end.travelled)) > tolerance:
				return false
			if end.reason == "range" and (absf(float(end.travelled) - float(spec.reach)) > 0.001 or not action.hit_ids.is_empty()):
				return false
			if end.reason == "hit" and action.hit_ids.size() != 1 or end.reason != "hit" and not action.hit_ids.is_empty():
				return false
	return Shape.keys(data.projectiles, expected.keys())


static func _own_intervals(data: Dictionary, now: int) -> bool:
	var ranges: Array[Dictionary] = []
	for row: Dictionary in data.conflicts.values():
		for actor: String in row.people:
			ranges.append({"actor": actor, "start": int(row.started_ms), "end": int(row.ended_ms) if int(row.ended_ms) != -1 else now + 1})
		if not row.withdrawal.is_empty():
			var retreat: Dictionary = row.withdrawal
			ranges.append({"actor": retreat.actor, "start": int(row.ended_ms), "end": int(retreat.finished_ms) if retreat.status == "completed" else now + 1})
	for row: Dictionary in data.lessons.values():
		for actor: String in [row.teacher, row.pupil]:
			ranges.append({"actor": actor, "start": int(row.started_ms), "end": _end_time(row, now) if row.status != "active" else now + 1})
	for index: int in ranges.size():
		for prior_index: int in range(index):
			if ranges[index].actor == ranges[prior_index].actor and _overlap(ranges[index], ranges[prior_index]):
				return false
	return true


static func _action_intervals(data: Dictionary, now: int) -> bool:
	var previous: Dictionary = {}
	for number: int in range(1, int(data.next_cost_id)):
		var row: Dictionary = data.actions["conflict:action:%d" % number]
		if int(row.started_ms) < int(previous.get(row.actor, -1)):
			return false
		previous[row.actor] = _end_time(row, now) if row.status != "active" else int(row.due_ms)
	return true


static func cross_valid(domain: RefCounted) -> bool:
	var data: Dictionary = domain.to_dict()
	if not validate(data, domain):
		return false
	var active_actors: Dictionary = {}
	for encounter: Dictionary in data.conflicts.values():
		if int(encounter.ended_ms) == -1:
			for actor: String in encounter.people:
				active_actors[actor] = true
		if not encounter.withdrawal.is_empty() and encounter.withdrawal.status == "active":
			var retreat: Dictionary = encounter.withdrawal
			active_actors[retreat.actor] = true
			if not SimRouteTravel.point(domain.body(str(retreat.actor))).is_equal_approx(_v(retreat.origin) + _v(retreat.direction) * float(retreat.distance)):
				return false
	for lesson: Dictionary in data.lessons.values():
		if lesson.status == "active":
			for actor: String in [lesson.teacher, lesson.pupil]:
				active_actors[actor] = true
				var position: Array = lesson.teacher_position if actor == lesson.teacher else lesson.pupil_position
				if not SimRouteTravel.point(domain.body(actor)).is_equal_approx(_v(position)):
					return false
	for actor: String in active_actors:
		var body: Dictionary = domain.body(actor)
		if bool(body.autonomous) or not body.active.is_empty() or not domain.world.actor_controls(actor, "action") or not domain.world.actor_controls(actor, "motion") or domain.world.body_action_owns(actor, &"conflicts"):
			return false
		var id: String = domain.conflict_for(actor)
		if not id.is_empty():
			var action_id: String = str(data.conflicts[id].people[actor].action)
			if not action_id.is_empty() and data.actions[action_id].method == "sword" and domain.world.artifacts.held_weapon(actor) != data.actions[action_id].object:
				return false
	var sources: Variant = domain.world.get("spirit_sources")
	if sources != null:
		var jobs: Array = sources.active.values()
		jobs.append_array(sources.records.values())
		for job: Dictionary in jobs:
			for encounter: Dictionary in data.conflicts.values():
				if encounter.people.has(job.actor) and _interval_overlap(int(job.started_ms), int(job.get("finished_ms", job.due_ms)), int(encounter.started_ms), int(encounter.ended_ms) if int(encounter.ended_ms) != -1 else int(domain.world.elapsed_ms) + 1):
					return false
			for lesson: Dictionary in data.lessons.values():
				if job.actor in [lesson.teacher, lesson.pupil] and _interval_overlap(int(job.started_ms), int(job.get("finished_ms", job.due_ms)), int(lesson.started_ms), _end_time(lesson, int(domain.world.elapsed_ms)) if lesson.status != "active" else int(domain.world.elapsed_ms) + 1):
					return false
			for encounter: Dictionary in data.conflicts.values():
				var retreat: Dictionary = encounter.withdrawal
				if not retreat.is_empty() and retreat.actor == job.actor and _interval_overlap(int(job.started_ms), int(job.get("finished_ms", job.due_ms)), int(encounter.ended_ms), int(retreat.finished_ms) if retreat.status == "completed" else int(domain.world.elapsed_ms) + 1):
					return false
	return true


static func _person(actor: Variant, domain: RefCounted) -> bool:
	return actor is String and not actor.is_empty() and not domain.body(actor).is_empty()


static func _process_time(row: Dictionary, now: int, statuses: Array[String]) -> bool:
	if row.status not in statuses or not Shape.count(row.finished_ms, -1, now):
		return false
	if row.status == "active":
		return row.finished_ms == -1 and int(row.due_ms) > now
	return int(row.finished_ms) >= int(row.started_ms) and int(row.finished_ms) <= int(row.due_ms) and (row.status != "completed" or row.finished_ms == row.due_ms)


static func _unit(value: Variant) -> bool:
	return value is Array and value.size() == 2 and SimSnapshotSchema._number(value[0]) and SimSnapshotSchema._number(value[1]) and absf(_v(value).length() - 1.0) < 0.00001


static func _v(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func _on_ray(point: Vector2, emission: Dictionary, direction: Array, limit: float, tolerance: float = 0.001) -> bool:
	var delta: Vector2 = point - _v(emission.origin)
	var distance: float = delta.dot(_v(direction))
	return distance >= -tolerance and distance <= limit + tolerance and absf(delta.cross(_v(direction))) <= tolerance


static func _projectile_tolerance(origin: Vector2, distance: float, spec: Dictionary, step_ms: int) -> float:
	var per_step: float = float(spec.speed) * float(step_ms) / 1000.0
	var steps: float = clampf(ceilf(distance / per_step), 1.0, ceilf(float(spec.reach) / per_step))
	var scale: float = maxf(maxf(absf(origin.x), absf(origin.y)) + float(spec.reach), 1.0)
	# Old shots were accumulated in float32 world coordinates. Each possible
	# addition contributes bounded coordinate rounding, plus two endpoint
	# operations. This stays below 1/8 pixel over this world's entire bounded
	# map/range; it never uses relative Vector2.is_equal_approx at 16k positions.
	# Current destinations are origin-derived and do not accumulate that drift.
	return maxf(0.001, scale * FLOAT32_EPSILON * (steps + 2.0))


static func _distance(value: Variant, minimum: float, maximum: float, inclusive: bool = true) -> bool:
	return SimSnapshotSchema._number(value) and float(value) >= minimum and (float(value) <= maximum if inclusive else float(value) < maximum)


static func _end_time(row: Dictionary, now: int) -> int:
	return int(row.finished_ms) if row.status != "active" else mini(now, int(row.due_ms))


static func _overlap(a: Dictionary, b: Dictionary) -> bool:
	return _interval_overlap(int(a.start), int(a.end), int(b.start), int(b.end))


static func _interval_overlap(a_start: int, a_end: int, b_start: int, b_end: int) -> bool:
	return a_start < b_end and b_start < a_end
