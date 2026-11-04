class_name SimConflicts
extends RefCounted
## Bounded hostile intentions on the original bodies. Views never own combat.

const VERSION: int = 3
const NEVER: int = 0x3fffffffffffffff
const Space = preload("res://scripts/sim/conflict_space.gd")
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/conflict_schema.gd")
const Perception = preload("res://scripts/sim/conflict_perception.gd")
var perception_since_ms: int = 0
var rules: Dictionary = {}
var conflicts: Dictionary = {}
var actions: Dictionary = {}
var hits: Dictionary = {}
var projectiles: Dictionary = {}
var barriers: Dictionary = {}
var lessons: Dictionary = {}
var next_id: int = 1
var next_cost_id: int = 1
var next_hit_id: int = 1
var next_lesson_id: int = 1
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref() if _owner != null else null


static func valid_rules(data: Variant) -> bool:
	if not data is Dictionary or data.get("version") != 1 or not Shape.keys(data.get("methods"), ["sword", "qi_bolt", "qi_guard"]) or not data.get("backgrounds") is Dictionary:
		return false
	for key: String in ["step_ms", "max_duration_ms", "reaction_ms", "stagger_ms", "stop_stamina", "lesson_ms", "ai_pause_ms", "last_seen_ms"]:
		if not Shape.count(data.get(key), 1, 86400000):
			return false
	for key: String in ["engage_radius", "leash_radius", "lesson_radius", "ai_speed_fraction", "projectile_radius", "retreat_distance", "ai_ranged_spacing", "ai_melee_spacing", "cover_sample_px", "sight_radius", "last_seen_arrival_px", "threat_margin_px"]:
		if not SimSnapshotSchema._number(data.get(key)) or float(data[key]) <= 0.0:
			return false
	if float(data.ai_speed_fraction) > 1.0 or float(data.leash_radius) <= float(data.engage_radius):
		return false
	for id: Variant in data.backgrounds:
		if not id is String or not SimEmbodiment._unique_texts(data.backgrounds[id]):
			return false
		for method: String in data.backgrounds[id]:
			if not data.methods.has(method):
				return false
	for id: String in data.methods:
		var spec: Variant = data.methods[id]
		if not spec is Dictionary or not SimInventory._nonempty(spec.get("label")) or spec.get("kind") not in ["melee", "projectile", "barrier"]:
			return false
		for key: String in ["prepare_ms", "contact_ms", "recover_ms", "stamina"]:
			if not Shape.count(spec.get(key), 1, 86400000):
				return false
		if not Shape.count(spec.get("qi"), 0, 1000):
			return false
		if spec.kind != "barrier":
			if not Shape.count(spec.get("impact"), 1, 100) or not Shape.count(spec.get("pressure"), 1, 1000) or not SimSnapshotSchema._number(spec.get("reach")) or float(spec.reach) <= 0:
				return false
		if spec.kind == "melee" and not SimSnapshotSchema._range(spec.get("half_angle_degrees"), 1, 180):
			return false
		if spec.kind == "projectile" and (not SimSnapshotSchema._number(spec.get("speed")) or float(spec.speed) <= 0):
			return false
		if spec.kind == "barrier" and (not Shape.count(spec.get("capacity"), 1, 100) or not Shape.count(spec.get("duration_ms"), 1, 86400000)):
			return false
	return true


func initialize(authority: RefCounted, definitions: Dictionary) -> bool:
	if authority == null or not valid_rules(definitions):
		return false
	_owner = weakref(authority)
	rules = definitions.duplicate(true)
	perception_since_ms = int(authority.elapsed_ms)
	return true


func bind_world(authority: RefCounted) -> void:
	_owner = weakref(authority)


func home(actor: String) -> String:
	for id: String in world.regions:
		if world.regions[id].actors.has(actor):
			return id
	return ""


func body(actor: String) -> Dictionary:
	var region: String = home(actor)
	return world.regions[region].actors[actor] if not region.is_empty() else {}


func knows(actor: String, method: String) -> bool:
	if body(actor).is_empty() or not rules.methods.has(method):
		return false
	if rules.backgrounds.get(str(body(actor).definition_id), []).has(method):
		return true
	for lesson: Dictionary in lessons.values():
		if lesson.pupil == actor and lesson.status == "completed" and lesson.methods.has(method):
			return true
	return false


func conflict_for(actor: String) -> String:
	for id: String in conflicts:
		if int(conflicts[id].ended_ms) == -1 and conflicts[id].people.has(actor):
			return id
	return ""


func owns_actor(actor: String) -> bool:
	if not conflict_for(actor).is_empty():
		return true
	for row: Dictionary in conflicts.values():
		if row.get("withdrawal", {}).get("status") == "active" and row.withdrawal.actor == actor:
			return true
	for lesson: Dictionary in lessons.values():
		if lesson.status == "active" and actor in [lesson.teacher, lesson.pupil]:
			return true
	return false


func action_blocks(actor: String) -> bool:
	var id: String = conflict_for(actor)
	if id.is_empty():
		return owns_actor(actor)
	var person: Dictionary = conflicts[id].people[actor]
	return not str(person.action).is_empty() or int(person.ready_ms) > world.elapsed_ms


func walking_projection(actor: String, at_ms: int = -1) -> Dictionary:
	# Walking is a narrower permission than beginning another body action.
	# This view never releases the encounter, its reaction lock or a paid cast.
	var now: int = int(world.elapsed_ms) if at_ms == -1 else at_ms
	var id: String = conflict_for(actor)
	if id.is_empty():
		return {"allowed": not owns_actor(actor), "speed_fraction": 1.0, "action": "", "reason": "occupied" if owns_actor(actor) else "free"}
	var person: Dictionary = conflicts[id].people[actor]
	var aid: String = str(person.action)
	if int(person.ready_ms) > now:
		return {"allowed": false, "speed_fraction": 0.0, "action": aid, "reason": "reaction"}
	if aid.is_empty():
		return {"allowed": true, "speed_fraction": 1.0, "action": "", "reason": "free"}
	var action: Dictionary = actions[aid]
	var practice: Variant = world.get("capability_practice")
	if action.method == "qi_guard" and action.status == "active" and now >= int(action.started_ms) and now < int(action.due_ms) and practice != null and practice.learned(actor, "mobile_guard", int(action.started_ms)):
		return {"allowed": true, "speed_fraction": float(practice.rules.nodes.mobile_guard.speed_fraction), "action": aid, "reason": "mobile_guard"}
	return {"allowed": false, "speed_fraction": 0.0, "action": aid, "reason": "committed_action"}


func previous_autonomy(actor: String) -> bool:
	var id: String = conflict_for(actor)
	if not id.is_empty():
		return bool(conflicts[id].people[actor].previous_autonomous)
	for row: Dictionary in conflicts.values():
		if row.get("withdrawal", {}).get("status") == "active" and row.withdrawal.actor == actor:
			return bool(row.people[actor].previous_autonomous)
	for lesson: Dictionary in lessons.values():
		if lesson.status == "active" and actor in [lesson.teacher, lesson.pupil]:
			return bool(lesson.teacher_autonomous if actor == lesson.teacher else lesson.pupil_autonomous)
	return false


func _available(actor: String) -> bool:
	return not body(actor).is_empty() and world.actor_controls(actor, "action") and world.actor_controls(actor, "motion") and not world.body_action_owns(actor, &"conflicts") and (world.health == null or world.health.can_fight(actor))


func _automatic(row: Dictionary, actor: String) -> bool:
	return row.people.has(actor) and bool(row.people[actor].previous_autonomous) and world.actor_controls(actor, "action") and world.actor_controls(actor, "motion") and world.actor_controls(actor, "communication")


func teach(teacher: String, pupil: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms or world.elapsed_ms > SimInventory.MAX_COUNT - int(rules.lesson_ms):
		return _reply(false, "先等世界事务结算到眼下，再开始示范。")
	if teacher == pupil or home(teacher).is_empty() or home(pupil).is_empty() or owns_actor(teacher) or owns_actor(pupil) or not _available(teacher) or not _available(pupil):
		return _reply(false, "眼下无法两人静下来示范，先处理手头事务。")
	if SimRouteTravel.point(body(teacher)).distance_to(SimRouteTravel.point(body(pupil))) > float(rules.lesson_radius):
		return _reply(false, "请先走到能看清示范的近处。")
	if not world.actor_controls(teacher, "communication") or not world.actor_controls(pupil, "communication") or not Perception.can_see(self, teacher, SimRouteTravel.point(body(pupil)), Space.level(world, SimRouteTravel.point(body(pupil)))):
		return _reply(false, "眼下无法当面交流并看清示范。")
	var methods: Array[String] = []
	for method: String in rules.methods:
		if knows(teacher, method) and not knows(pupil, method):
			methods.append(method)
	# The definition dictionary's insertion order is not gameplay state.
	# Canonical order keeps future lesson records stable after save/restore.
	methods.sort()
	if methods.is_empty():
		return _reply(false, "对方没有能在此刻示范给你的新手段。")
	if world.services != null:
		if float(body(teacher).hunger) <= float(world.regions[home(teacher)].config.needs.eat_below) or float(body(teacher).energy) <= float(world.regions[home(teacher)].config.needs.rest_below):
			return _reply(false, "对方正饿着或疲惫，暂不肯耗神示范。")
		# This first lesson is openly offered by the people with these backgrounds;
		# holding office is not what grants either party a technique.
		if not rules.backgrounds.has(str(body(teacher).definition_id)):
			return _reply(false, "对方还没有答应传授。")
	var id: String = "conflict:lesson:%d" % next_lesson_id
	next_lesson_id += 1
	var row: Dictionary = {"id": id, "teacher": teacher, "pupil": pupil, "methods": methods, "region": home(teacher), "started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + int(rules.lesson_ms), "finished_ms": -1, "status": "active", "teacher_autonomous": bool(body(teacher).autonomous), "pupil_autonomous": bool(body(pupil).autonomous), "teacher_position": _point(SimRouteTravel.point(body(teacher))), "pupil_position": _point(SimRouteTravel.point(body(pupil)))}
	lessons[id] = row
	for actor: String in [teacher, pupil]:
		world.regions[home(actor)].cancel_action(actor, "martial_demonstration")
		body(actor).autonomous = false
		body(actor).goal = "当面示范与练习护身手段"
		world.invalidate_region(home(actor))
	return _reply(true, "对方答应当面示范。需一起练习一分钟；会辨认木剑不等于会御气。")


func begin(initiator: String, defender: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms or world.elapsed_ms > SimInventory.MAX_COUNT - int(rules.max_duration_ms):
		return _reply(false, "先等世界事务结算到眼下，再表明敌意。")
	return _commit_begin(initiator, defender)


func begin_source_care(warning_id: String) -> Dictionary:
	# This entry owns no clock bypass flag or caller-supplied accusation. The
	# care authority must revalidate the actual due warning and original job.
	var care: RefCounted = world.get("source_care")
	if care == null or world.elapsed_ms > SimInventory.MAX_COUNT - int(rules.max_duration_ms):
		return _reply(false, "这次劝阻尚不能转为交锋。")
	var basis: Dictionary = care.due_conflict(warning_id)
	if not Shape.keys(basis, ["initiator", "defender", "source_job"]) or not SimInventory._nonempty(basis.initiator) or not SimInventory._nonempty(basis.defender) or not SimInventory._nonempty(basis.source_job):
		return _reply(false, "这次劝阻已不再具备当面驱离的依据。")
	return _commit_begin(str(basis.initiator), str(basis.defender), warning_id)


func _commit_begin(initiator: String, defender: String, warning_id: String = "") -> Dictionary:
	if (warning_id.is_empty() and world.elapsed_ms != world.target_ms) or world.elapsed_ms > SimInventory.MAX_COUNT - int(rules.max_duration_ms):
		return _reply(false, "先等世界事务结算到眼下，再表明敌意。")
	if initiator == defender or home(initiator).is_empty() or home(defender).is_empty() or owns_actor(initiator) or owns_actor(defender):
		return _reply(false, "双方眼下无法交锋，或身体已有别的占用。")
	for actor: String in [initiator, defender]:
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or (world.health != null and not world.health.can_fight(actor)):
			return _reply(false, "对方已无力再斗，或眼下无法支配身体。")
	if SimRouteTravel.point(body(initiator)).distance_to(SimRouteTravel.point(body(defender))) > float(rules.engage_radius):
		return _reply(false, "对方尚未在可交涉或交锋的近处。")
	if not knows(initiator, "sword") and not knows(initiator, "qi_bolt"):
		return _reply(false, "先实际学会一种能收放的手段，再考虑动手。")
	if not Perception.can_see(self, initiator, SimRouteTravel.point(body(defender)), Space.level(world, SimRouteTravel.point(body(defender)))):
		return _reply(false, "双方被地势或墙柜隔开，尚不能相互察觉并交锋。")
	var people: Dictionary = {}
	for actor: String in [initiator, defender]:
		people[actor] = {"previous_autonomous": bool(body(actor).autonomous) or world.activity_previous_autonomy(actor), "action": "", "ready_ms": world.elapsed_ms + (int(rules.reaction_ms) if actor == defender else 0), "sight": {}}
	# Capture both policies before any interruption callback restores one of
	# them. Source completion is collected inside the trusted synchronous handoff.
	if not warning_id.is_empty() and not world.source_care.conflict_starting(warning_id):
		return _reply(false, "这次劝阻的当面依据已经改变。")
	var id: String = "conflict:encounter:%d" % next_id
	next_id += 1
	for actor: String in [initiator, defender]:
		world.interrupt_occupation(actor, "hostile_warning")
		body(actor).autonomous = false
		body(actor).goal = "对峙：以可收放的手段驱离，不取性命"
	# Region is the responder's process/record owner, never a spatial gate.
	# Participants can travel while their original bodies stay in one owner.
	conflicts[id] = {"id": id, "region": home(defender), "initiator": initiator, "defender": defender, "intent": "drive_off", "started_ms": world.elapsed_ms, "last_ms": world.elapsed_ms, "next_step_ms": world.elapsed_ms + int(rules.step_ms), "ended_ms": -1, "reason": "", "yielded": "", "withdrawal": {}, "people": people, "cause": {"domain": "source_care", "id": warning_id} if not warning_id.is_empty() else {}}
	if not warning_id.is_empty():
		world.source_care.conflict_started(warning_id, id)
	Perception.refresh(self, conflicts[id])
	_observe("conflict_warned", initiator, defender, {})
	world.invalidate_region(home(initiator))
	world.invalidate_region(home(defender))
	return _reply(true, "你表明驱离的敌意。对方已警觉；消耗与挫伤都会留下，随时可退让离开。")


func cast(actor: String, method: String, direction: Vector2, internal: bool = false) -> Dictionary:
	if (not internal and world.elapsed_ms != world.target_ms) or not rules.methods.has(method) or world.elapsed_ms > SimInventory.MAX_COUNT - duration(method):
		return _reply(false, "尚不能在这个时刻发招。")
	var id: String = conflict_for(actor)
	if id.is_empty() or not knows(actor, method) or action_blocks(actor) or not _available(actor) or not direction.is_finite() or direction.is_zero_approx():
		return _reply(false, "眼下不能施展这项手段。")
	var spec: Dictionary = rules.methods[method]
	var item: String = world.artifacts.held_weapon(actor) if method == "sword" else ""
	if method == "sword" and item.is_empty():
		return _reply(false, "手中没有实际保管的木剑；外观预览不能代替武器。")
	if int(body(actor).qi) < int(spec.qi) or int(body(actor).stamina) < int(spec.stamina):
		return _reply(false, "体力或灵气不足，不能凭空施展。")
	if method != "sword" and world.health != null and world.health.blocks_channeling(actor):
		return _reply(false, "经脉仍有灼涩，暂不能运气施术。")
	if method == "qi_guard" and barriers.has(actor):
		return _reply(false, "已有护障尚未散去。")
	if int(spec.qi) > 0 and not world.spirit_sources.ensure_qi_baseline(actor):
		return _reply(false, "灵气收支尚不能核清，先停止运气。")
	var action_id: String = "conflict:action:%d" % next_cost_id
	var facing: Vector2 = direction.normalized()
	actions[action_id] = {"id": action_id, "number": next_cost_id, "conflict": id, "actor": actor, "method": method, "object": item, "started_ms": world.elapsed_ms, "effect_ms": world.elapsed_ms + int(spec.prepare_ms), "due_ms": world.elapsed_ms + duration(method), "finished_ms": -1, "status": "active", "qi_spent": int(spec.qi), "stamina_spent": int(spec.stamina), "direction": _point(facing), "emitted": false, "emission": {}, "projectile_end": {}, "hit_ids": []}
	next_cost_id += 1
	body(actor).qi = int(body(actor).qi) - int(spec.qi)
	body(actor).stamina = int(body(actor).stamina) - int(spec.stamina)
	body(actor).stamina_carry = 0
	body(actor).exertion_until_ms = world.elapsed_ms + duration(method) + int(world.regions[home(actor)].motion_rules.recovery.delay_ms)
	body(actor).facing = _point(facing)
	conflicts[id].people[actor].action = action_id
	world.invalidate_region(home(actor))
	return _reply(true, str(spec.label) + "已经起势；已投入的灵气与体力不会因取消返还。")


func duration(method: String) -> int:
	var spec: Dictionary = rules.methods[method]
	return int(spec.prepare_ms) + int(spec.contact_ms) + int(spec.recover_ms)


func phase(actor: String, now: int) -> String:
	var id: String = conflict_for(actor)
	if id.is_empty() or str(conflicts[id].people[actor].action).is_empty():
		return ""
	var action: Dictionary = actions[conflicts[id].people[actor].action]
	var spec: Dictionary = rules.methods[action.method]
	if now < int(action.effect_ms):
		return "prepare"
	return "contact" if now < int(action.effect_ms) + int(spec.contact_ms) else "recover"


func next_boundary_ms() -> int:
	var result: int = NEVER
	for row: Dictionary in conflicts.values():
		if int(row.ended_ms) == -1:
			result = mini(result, mini(int(row.next_step_ms), int(row.started_ms) + int(rules.max_duration_ms)))
		elif row.withdrawal.get("status") == "active":
			result = mini(result, int(row.withdrawal.next_step_ms))
	for lesson: Dictionary in lessons.values():
		if lesson.status == "active":
			result = mini(result, int(lesson.due_ms))
	for action: Dictionary in actions.values():
		if action.status == "active":
			result = mini(result, int(action.effect_ms) if not bool(action.emitted) else int(action.due_ms))
	for barrier: Dictionary in barriers.values():
		result = mini(result, int(barrier.until_ms))
	for shot: Dictionary in projectiles.values():
		result = mini(result, int(shot.last_ms) + int(rules.step_ms))
	return result


func settle_at_ms(now: int) -> void:
	_settle_lessons(now)
	_settle_withdrawals(now)
	var contacts: Array[Dictionary] = []
	for actor: String in barriers.keys():
		if now >= int(barriers[actor].until_ms):
			barriers.erase(actor)
	# Snapshot the same boundary before moving anyone; decisions never borrow a
	# hidden body's current position from the physical contact resolver below.
	for id: String in world._sorted_keys(conflicts):
		var row: Dictionary = conflicts[id]
		if int(row.ended_ms) == -1 and _row_due(row, now):
			for actor: String in row.people:
				world.synchronize_region(home(actor))
			Perception.refresh(self, row)
	var decisions: Array[Dictionary] = []
	for id: String in world._sorted_keys(conflicts):
		var row: Dictionary = conflicts[id]
		if int(row.ended_ms) != -1 or not _row_due(row, now):
			continue
		world.synchronize_region(str(row.region))
		world.synchronize_region(home(str(row.initiator)))
		world.synchronize_region(home(str(row.defender)))
		if not world.actor_controls(str(row.initiator), "action") or not world.actor_controls(str(row.defender), "action") or not world.actor_controls(str(row.initiator), "motion") or not world.actor_controls(str(row.defender), "motion"):
			_end(id, "control_lost", "")
			continue
		var delta: Vector2 = SimRouteTravel.point(body(str(row.initiator))) - SimRouteTravel.point(body(str(row.defender)))
		if delta.length() > float(rules.leash_radius) or now >= int(row.started_ms) + int(rules.max_duration_ms):
			_end(id, "separated", "")
			continue
		var motion_cues: Dictionary = {}
		for actor: String in world._sorted_keys(row.people):
			if _automatic(row, actor):
				motion_cues[actor] = Perception.cues(self, row, actor)
		for actor: String in motion_cues:
			_ai_motion(row, actor, now - int(row.last_ms), motion_cues[actor])
		for actor: String in row.people:
			var aid: String = str(row.people[actor].action)
			if aid.is_empty():
				continue
			var action: Dictionary = actions[aid]
			if not bool(action.emitted) and now >= int(action.effect_ms):
				action.emitted = true
				_emit(row, action)
			if action.method == "sword" and action.hit_ids.is_empty() and phase(actor, now) == "contact":
				var target: String = opponent(actor)
				var from: Vector2 = SimRouteTravel.point(body(actor))
				var to: Vector2 = SimRouteTravel.point(body(target))
				var spec: Dictionary = rules.methods.sword
				if Space.level(world, from) == Space.level(world, to) and Space.in_fan(from, to, _vector(action.direction), float(spec.reach), float(spec.half_angle_degrees)) and Space.clear_segment(world, from, to, Space.level(world, from)):
					contacts.append({"action": aid, "target": target, "from": _point(from), "to": _point(to), "segment_from": _point(from), "segment_to": _point(to)})
	_advance_projectiles(now, contacts)
	# Every contact at this boundary is collected before any effect is applied.
	for contact: Dictionary in contacts:
		_commit_hit(contact, now)
	for id: String in world._sorted_keys(conflicts):
		var row: Dictionary = conflicts[id]
		if int(row.ended_ms) != -1 or not _row_due(row, now):
			continue
		for actor: String in row.people:
			var aid: String = str(row.people[actor].action)
			if not aid.is_empty() and now >= int(actions[aid].due_ms):
				_finish_action(aid, "completed")
			if int(body(actor).stamina) <= int(rules.stop_stamina) or (world.health != null and not world.health.can_fight(actor)):
				_end(id, "withdrawn", actor)
				break
		if int(row.ended_ms) != -1:
			continue
		row.last_ms = now
		row.next_step_ms = now + int(rules.step_ms)
		Perception.refresh(self, row)
		for actor: String in world._sorted_keys(row.people):
			if _automatic(row, actor):
				decisions.append({"id": id, "actor": actor, "cues": Perception.cues(self, row, actor)})
		world.invalidate_region(str(row.region))
	# All current cues exist before the first NPC starts a new action. A later
	# encounter cannot react to an earlier encounter's newly committed windup.
	for decision: Dictionary in decisions:
		_ai_action(conflicts[decision.id], str(decision.actor), decision.cues)


func _row_due(row: Dictionary, now: int) -> bool:
	if now >= int(row.next_step_ms) or now >= int(row.started_ms) + int(rules.max_duration_ms):
		return true
	for person: Dictionary in row.people.values():
		if not str(person.action).is_empty():
			var action: Dictionary = actions[person.action]
			if now >= int(action.due_ms) or (not bool(action.emitted) and now >= int(action.effect_ms)):
				return true
	return false


func _emit(row: Dictionary, action: Dictionary) -> void:
	var actor: String = str(action.actor)
	var from: Vector2 = SimRouteTravel.point(body(actor))
	action.emission = {"origin": _point(from), "level": Space.level(world, from), "at_ms": world.elapsed_ms}
	if action.method == "qi_guard":
		barriers[actor] = {"action": action.id, "remaining": int(rules.methods.qi_guard.capacity), "until_ms": world.elapsed_ms + int(rules.methods.qi_guard.duration_ms)}
	elif action.method == "qi_bolt":
		projectiles[action.id] = {"action": action.id, "conflict": row.id, "actor": actor, "target": opponent(actor), "position": _point(from), "origin": _point(from), "direction": action.direction.duplicate(), "level": Space.level(world, from), "spawned_ms": world.elapsed_ms, "last_ms": world.elapsed_ms, "travelled": 0.0}


func _advance_projectiles(now: int, contacts: Array[Dictionary]) -> void:
	for id: String in world._sorted_keys(projectiles):
		var shot: Dictionary = projectiles[id]
		if now < int(shot.last_ms) + int(rules.step_ms):
			continue
		var spec: Dictionary = rules.methods.qi_bolt
		var from: Vector2 = _vector(shot.position)
		var travelled: float = minf(float(spec.reach), float(shot.travelled) + float(spec.speed) * float(now - int(shot.last_ms)) / 1000.0)
		# Vector2 uses float32 coordinates. Repeated additions at world-scale
		# positions drift sideways and along the ray; derive every destination
		# from the immutable emission and the accumulated scalar distance.
		# Keep a restored legacy shot's actual position as this segment's start.
		var to: Vector2 = _vector(shot.origin) + _vector(shot.direction) * travelled
		var target: String = ""
		var contact_point: Vector2 = to
		var nearest: float = from.distance_to(to) + 1.0
		for region: String in world.regions:
			world.synchronize_region(region)
			for candidate: String in world._sorted_keys(world.regions[region].actors):
				if candidate == str(shot.actor) or not bool(body(candidate).alive):
					continue
				var target_point: Vector2 = SimRouteTravel.point(body(candidate))
				if Space.level(world, target_point) != int(shot.level) or Space.segment_distance(from, to, target_point) > float(rules.projectile_radius):
					continue
				var closest: Vector2 = Geometry2D.get_closest_point_to_segment(target_point, from, to)
				if closest.distance_to(from) < nearest:
					nearest = closest.distance_to(from)
					target = candidate
					contact_point = closest
		if not Space.clear_segment(world, from, contact_point, int(shot.level)):
			actions[id].projectile_end = {"at_ms": now, "reason": "blocked", "position": _point(contact_point), "travelled": minf(travelled, float(shot.travelled) + from.distance_to(contact_point))}
			projectiles.erase(id)
		elif not target.is_empty():
			contacts.append({"action": id, "target": target, "from": shot.origin.duplicate(), "to": _point(SimRouteTravel.point(body(target))), "segment_from": _point(from), "segment_to": _point(to)})
			actions[id].projectile_end = {"at_ms": now, "reason": "hit", "position": _point(contact_point), "travelled": minf(travelled, float(shot.travelled) + from.distance_to(contact_point))}
			projectiles.erase(id)
		else:
			shot.position = _point(to)
			shot.travelled = travelled
			shot.last_ms = now
			if float(shot.travelled) >= float(spec.reach):
				actions[id].projectile_end = {"at_ms": now, "reason": "range", "position": shot.position.duplicate(), "travelled": float(shot.travelled)}
				projectiles.erase(id)


func _commit_hit(contact: Dictionary, now: int) -> void:
	var action: Dictionary = actions[contact.action]
	if not action.hit_ids.is_empty():
		return
	var target: String = str(contact.target)
	var spec: Dictionary = rules.methods[action.method]
	var absorbed: int = 0
	var guard_action: String = ""
	if barriers.has(target):
		var barrier: Dictionary = barriers[target]
		absorbed = mini(int(spec.impact), int(barrier.remaining))
		guard_action = str(barrier.action)
		barrier.remaining = int(barrier.remaining) - absorbed
		if int(barrier.remaining) == 0:
			barriers.erase(target)
	var impact: int = int(spec.impact) - absorbed
	var id: String = "conflict:hit:%d" % next_hit_id
	next_hit_id += 1
	hits[id] = {"id": id, "action": action.id, "actor": target, "attacker": action.actor, "region": home(target), "type": "contusion", "at_ms": now, "impact": impact, "absorbed": absorbed, "guard_action": guard_action, "origin": contact.from.duplicate(), "position": contact.to.duplicate(), "segment_from": contact.segment_from.duplicate(), "segment_to": contact.segment_to.duplicate()}
	action.hit_ids.append(id)
	if impact > 0:
		world.interrupt_occupation(target, "struck_by_conflict")
		body(target).stamina = maxi(0, int(body(target).stamina) - ceili(float(spec.pressure) * impact / int(spec.impact)))
		body(target).stamina_carry = 0
		body(target).exertion_until_ms = maxi(int(body(target).exertion_until_ms), now + int(world.regions[home(target)].motion_rules.recovery.delay_ms))
		if world.health != null:
			world.health.record_conflict_effect(id)
		var encounter: Dictionary = conflicts[action.conflict]
		var target_conflict: String = conflict_for(target)
		if not target_conflict.is_empty():
			encounter = conflicts[target_conflict]
		var interrupted: String = str(encounter.people[target].action) if encounter.people.has(target) else ""
		if not interrupted.is_empty():
			_finish_action(interrupted, "interrupted")
		if encounter.people.has(target):
			encounter.people[target].ready_ms = maxi(int(encounter.people[target].ready_ms), now + int(rules.stagger_ms))
	_observe("conflict_contact", str(action.actor), target, {"guarded": absorbed > 0})


func _finish_action(id: String, status: String) -> void:
	var action: Dictionary = actions[id]
	if action.status != "active":
		return
	action.status = status
	action.finished_ms = world.elapsed_ms
	var encounter: Dictionary = conflicts[action.conflict]
	if str(encounter.people[action.actor].action) == id:
		encounter.people[action.actor].action = ""
		encounter.people[action.actor].ready_ms = maxi(int(encounter.people[action.actor].ready_ms), world.elapsed_ms + (int(rules.ai_pause_ms) if _automatic(encounter, str(action.actor)) else 0))


func opponent(actor: String) -> String:
	var id: String = conflict_for(actor)
	if id.is_empty():
		return ""
	return str(conflicts[id].defender) if actor == conflicts[id].initiator else str(conflicts[id].initiator)


func cancel(actor: String, reason: String = "yielded") -> void:
	interrupt_lesson(actor)
	var id: String = conflict_for(actor)
	if not id.is_empty():
		_end(id, reason if reason in ["yielded", "control_lost", "separated", "withdrawn"] else "yielded", actor)


func interrupt_lesson(actor: String) -> void:
	# A bystander may be teaching in the path of somebody else's projectile.
	# End that occupation without cancelling already collected mutual hits.
	for lesson: Dictionary in lessons.values():
		if lesson.status == "active" and actor in [lesson.teacher, lesson.pupil]:
			_finish_lesson(lesson, "interrupted")


func _end(id: String, reason: String, yielded: String) -> void:
	var row: Dictionary = conflicts[id]
	if int(row.ended_ms) != -1:
		return
	if row.people.has(yielded) and bool(row.people[yielded].previous_autonomous) and not _automatic(row, yielded):
		reason = "control_lost"
	row.ended_ms = world.elapsed_ms
	row.reason = reason
	row.yielded = yielded
	if not yielded.is_empty() and _automatic(row, yielded):
		var origin: Vector2 = SimRouteTravel.point(body(yielded))
		var sight: Dictionary = row.people[yielded].sight
		var away: Vector2 = origin - _vector(sight.position) if not sight.is_empty() and world.elapsed_ms - int(sight.at_ms) <= int(rules.last_seen_ms) else -SimRouteTravel.facing(body(yielded))
		if away.is_zero_approx():
			away = -SimRouteTravel.facing(body(yielded))
		row.withdrawal = {"actor": yielded, "origin": _point(origin), "direction": _point(away.normalized()), "distance": 0.0, "last_ms": world.elapsed_ms, "next_step_ms": world.elapsed_ms + int(rules.step_ms), "finished_ms": -1, "status": "active", "reason": ""}
	for actor: String in row.people:
		var aid: String = str(row.people[actor].action)
		if not aid.is_empty():
			_finish_action(aid, "interrupted")
		body(actor).autonomous = bool(row.people[actor].previous_autonomous) and row.withdrawal.get("actor", "") != actor
		body(actor).goal = "交锋已停，挫伤与已付代价仍在；先调息"
		body(actor).retry_ms = world.elapsed_ms + int(world.regions[home(actor)].config.decision_interval) * 60000
		world.invalidate_region(home(actor))
	_observe("conflict_ended", str(row.initiator), str(row.defender), {"reason": reason})
	world.invalidate_region(str(row.region))


func _settle_withdrawals(now: int) -> void:
	for row: Dictionary in conflicts.values():
		var withdrawal: Dictionary = row.withdrawal
		if withdrawal.get("status") != "active" or now < int(withdrawal.next_step_ms):
			continue
		var actor: String = str(withdrawal.actor)
		world.synchronize_region(home(actor))
		var reason: String = ""
		if not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not world.actor_controls(actor, "communication"):
			reason = "control_lost"
		else:
			var distance: float = minf(float(rules.retreat_distance) - float(withdrawal.distance), float(world.regions[home(actor)].motion_rules.motion.speed) * float(rules.ai_speed_fraction) * (now - int(withdrawal.last_ms)) / 1000.0)
			var point: Vector2 = SimRouteTravel.point(body(actor))
			var next: Vector2 = point + _vector(withdrawal.direction) * distance
			if not Space.can_step(world, TileGrid.world_to_cell(point), TileGrid.world_to_cell(next)):
				reason = "blocked"
			else:
				SimRouteTravel.put(body(actor), next)
				body(actor).facing = withdrawal.direction.duplicate()
				withdrawal.distance = float(withdrawal.distance) + distance
				if float(withdrawal.distance) >= float(rules.retreat_distance):
					reason = "distance"
		withdrawal.last_ms = now
		withdrawal.next_step_ms = now + int(rules.step_ms)
		if not reason.is_empty():
			withdrawal.status = "completed"
			withdrawal.reason = reason
			withdrawal.finished_ms = now
			body(actor).autonomous = bool(row.people[actor].previous_autonomous)
			body(actor).goal = "退开后调息，保留先前的责任"
			body(actor).retry_ms = now + int(world.regions[home(actor)].config.decision_interval) * 60000
		world.invalidate_region(home(actor))


func _ai_motion(row: Dictionary, actor: String, elapsed: int, cues: Dictionary) -> void:
	# Motion consumes the previous interval. At an effect/completion boundary
	# use its starting permission, before current blows can change the body.
	var walking: Dictionary = walking_projection(actor, int(row.last_ms))
	if not _automatic(row, actor) or not bool(walking.allowed):
		return
	var sight: Dictionary = row.people[actor].sight
	if sight.is_empty():
		body(actor).goal = "警戒：已失去对手踪迹，不再盲追"
		return
	var visible: bool = bool(cues.visible)
	var target: Vector2 = _vector(sight.position)
	var point: Vector2 = SimRouteTravel.point(body(actor))
	var distance: float = point.distance_to(target)
	var spacing: float = float(rules.last_seen_arrival_px)
	if visible:
		spacing = float(rules.ai_ranged_spacing) if knows(actor, "qi_bolt") and int(body(actor).qi) >= int(rules.methods.qi_bolt.qi) else float(rules.ai_melee_spacing)
	body(actor).goal = "交锋：观察对手，寻机应对" if visible else "警戒：视线受阻，循最后见处查看"
	if distance <= spacing:
		return
	var budget: float = minf(distance - spacing, float(world.regions[home(actor)].motion_rules.motion.speed) * float(rules.ai_speed_fraction) * float(walking.speed_fraction) * elapsed / 1000.0)
	var step_size: float = float(world.regions[home(actor)].motion_rules.motion.sweep_px)
	while budget > 0.001:
		var step: float = minf(step_size, budget)
		var next: Vector2 = point.move_toward(target, step)
		if not Space.can_step(world, TileGrid.world_to_cell(point), TileGrid.world_to_cell(next)):
			break
		point = next
		budget -= step
	SimRouteTravel.put(body(actor), point)
	var direction: Vector2 = target - point
	if not direction.is_zero_approx():
		body(actor).facing = _point(direction.normalized())


func _ai_action(row: Dictionary, actor: String, cues: Dictionary) -> void:
	if not _automatic(row, actor) or action_blocks(actor):
		return
	var point: Vector2 = SimRouteTravel.point(body(actor))
	var direction: Vector2 = _vector(cues.target) - point if bool(cues.visible) else SimRouteTravel.facing(body(actor))
	if direction.is_zero_approx():
		direction = SimRouteTravel.facing(body(actor))
	if knows(actor, "qi_guard") and not barriers.has(actor) and not cues.danger.is_empty() and int(body(actor).qi) >= int(rules.methods.qi_guard.qi):
		var toward: Vector2 = _vector(cues.danger) - point
		cast(actor, "qi_guard", toward if not toward.is_zero_approx() else direction, true)
	elif not bool(cues.visible):
		return
	elif knows(actor, "sword") and not world.artifacts.held_weapon(actor).is_empty() and direction.length() <= float(rules.methods.sword.reach):
		cast(actor, "sword", direction, true)
	elif knows(actor, "qi_bolt") and direction.length() <= float(rules.methods.qi_bolt.reach) and int(body(actor).qi) >= int(rules.methods.qi_bolt.qi):
		cast(actor, "qi_bolt", direction, true)


func _settle_lessons(now: int) -> void:
	for lesson: Dictionary in lessons.values():
		if lesson.status != "active":
			continue
		var valid: bool = true
		for actor: String in [lesson.teacher, lesson.pupil]:
			var start: Array = lesson.teacher_position if actor == lesson.teacher else lesson.pupil_position
			valid = valid and world.actor_controls(actor, "action") and world.actor_controls(actor, "motion") and world.actor_controls(actor, "communication") and SimRouteTravel.point(body(actor)).is_equal_approx(_vector(start))
		if not valid:
			_finish_lesson(lesson, "interrupted")
		elif now >= int(lesson.due_ms):
			_finish_lesson(lesson, "completed")


func _finish_lesson(lesson: Dictionary, status: String) -> void:
	lesson.status = status
	lesson.finished_ms = world.elapsed_ms
	for actor: String in [lesson.teacher, lesson.pupil]:
		body(actor).autonomous = bool(lesson.teacher_autonomous if actor == lesson.teacher else lesson.pupil_autonomous)
		body(actor).retry_ms = world.elapsed_ms + int(world.regions[home(actor)].config.decision_interval) * 60000
		body(actor).goal = "示范练习结束" if status == "completed" else "示范中断，尚未掌握"
		world.invalidate_region(home(actor))


func qi_spending(actor: String) -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for action: Dictionary in actions.values():
		if action.actor == actor:
			rows.append({"domain": "conflict", "number": int(action.number), "at_ms": int(action.started_ms), "amount": int(action.qi_spent)})
	return rows


func wound_sources() -> Dictionary:
	var rows: Dictionary = {}
	for id: String in hits:
		var hit: Dictionary = hits[id]
		if int(hit.impact) > 0:
			rows[id] = {"id": id, "actor": hit.actor, "region": hit.region, "type": "contusion", "at_ms": int(hit.at_ms), "impact": int(hit.impact)}
	return rows


func _observe(kind: String, actor: String, target: String, details: Dictionary) -> void:
	if home(actor) == home(target):
		world.regions[home(actor)].observe(kind, actor, target, details)
		return
	# Visitors retain their original body owner. Cross-owner encounters use
	# the existing shared personal-memory book, with physical local witnesses.
	if world.services == null:
		return
	var origin: Vector2 = SimRouteTravel.point(body(actor))
	var radius: float = float(world.regions[home(target)].config.observation_radius) * TileGrid.TILE_SIZE
	var witnesses: Array[String] = []
	for region: String in world._sorted_keys(world.regions):
		for observer: String in world._sorted_keys(world.regions[region].actors):
			if observer in [actor, target] or not bool(body(observer).alive):
				continue
			var point: Vector2 = SimRouteTravel.point(body(observer))
			if point.distance_to(origin) <= radius and Space.level(world, point) == Space.level(world, origin) and Space.clear_segment(world, origin, point, Space.level(world, origin)):
				witnesses.append(observer)
	@warning_ignore("integer_division")
	world.services.social.record(kind, actor, target, details, witnesses, int(world.elapsed_ms) / 60000)


static func empty_state() -> Dictionary:
	return {"version": VERSION, "perception_since_ms": 0, "next_id": 1, "next_cost_id": 1, "next_hit_id": 1, "next_lesson_id": 1, "conflicts": {}, "actions": {}, "hits": {}, "projectiles": {}, "barriers": {}, "lessons": {}}


static func upgrade_source_care(source: Dictionary) -> Dictionary:
	# Only this exact v2 envelope can gain an empty cause. Semantic/history
	# validation still runs against the independently restored candidate world.
	if not Shape.keys(source, Schema.TOP) or not Shape.count(source.version, 2, 2) or not Shape.count(source.perception_since_ms):
		return {}
	for key: String in ["next_id", "next_cost_id", "next_hit_id", "next_lesson_id"]:
		if not Shape.count(source[key], 1):
			return {}
	for key: String in ["conflicts", "actions", "hits", "projectiles", "barriers", "lessons"]:
		if not source[key] is Dictionary:
			return {}
	if source.conflicts.size() != int(source.next_id) - 1 or source.actions.size() != int(source.next_cost_id) - 1 or source.hits.size() != int(source.next_hit_id) - 1 or source.lessons.size() != int(source.next_lesson_id) - 1:
		return {}
	var fields: Array[String] = ["id", "region", "initiator", "defender", "intent", "started_ms", "last_ms", "next_step_ms", "ended_ms", "reason", "yielded", "people", "withdrawal"]
	for row: Variant in source.conflicts.values():
		if not Shape.keys(row, fields) or not Shape.keys(row.people, [row.initiator, row.defender]):
			return {}
		if not row.withdrawal is Dictionary:
			return {}
		if not row.withdrawal.is_empty() and (not Shape.keys(row.withdrawal, ["actor", "origin", "direction", "distance", "last_ms", "next_step_ms", "finished_ms", "status", "reason"]) or row.withdrawal.get("actor") != row.defender):
			return {}
		for person: Variant in row.people.values():
			if not Shape.keys(person, ["previous_autonomous", "action", "ready_ms", "sight"]) or not person.previous_autonomous is bool or not person.action is String or not Shape.count(person.ready_ms) or not person.sight is Dictionary:
				return {}
			if not person.sight.is_empty() and not Shape.keys(person.sight, ["at_ms", "observer_position", "position", "level"]):
				return {}
	for key: String in ["actions", "hits", "projectiles", "barriers", "lessons"]:
		var shape: Array = {"actions": Schema.ACTION, "hits": Schema.HIT, "projectiles": Schema.SHOT, "barriers": ["action", "remaining", "until_ms"], "lessons": Schema.LESSON}[key]
		for row: Variant in source[key].values():
			if not Shape.keys(row, shape):
				return {}
	var result: Dictionary = source.duplicate(true)
	result.version = VERSION
	for row: Dictionary in result.conflicts.values():
		row["cause"] = {}
	return result


func to_dict() -> Dictionary:
	return {"version": VERSION, "perception_since_ms": perception_since_ms, "next_id": next_id, "next_cost_id": next_cost_id, "next_hit_id": next_hit_id, "next_lesson_id": next_lesson_id, "conflicts": conflicts.duplicate(true), "actions": actions.duplicate(true), "hits": hits.duplicate(true), "projectiles": projectiles.duplicate(true), "barriers": barriers.duplicate(true), "lessons": lessons.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if not Schema.validate(data, self):
		return false
	for field: String in ["perception_since_ms", "next_id", "next_cost_id", "next_hit_id", "next_lesson_id"]:
		set(field, int(data[field]))
	for field: String in ["conflicts", "actions", "hits", "projectiles", "barriers", "lessons"]:
		set(field, data[field].duplicate(true))
	return true


static func _point(value: Vector2) -> Array:
	return [value.x, value.y]


static func _vector(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))


static func _reply(ok: bool, line: String) -> Dictionary:
	return {"ok": ok, "line": line}
