class_name SimHealth
extends RefCounted
## Specific consequences of actual effects, not a second pool of universal HP.

const VERSION: int = 2
const MINUTE_MS: int = 60000
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/health_schema.gd")
const ParticipationIndex = preload("res://scripts/sim/execution/participation_index.gd")
const WOUND_WORK: StringName = &"health:wounds"
const CARE_WORK: StringName = &"health:care"
const CARE_PATIENTS: StringName = &"health:care_patients"
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref() if _owner != null else null
var definitions: Dictionary = {}
var source_floor: int = 1
var conflict_source_floor: int = 1
var next_id: int = 1
var wounds: Dictionary = {}
var jobs: Dictionary = {}
# Disposable participant references only. Original wounds and jobs above remain
# the authority and are the only values saved. Recovery deliberately preserves
# the original wounds dictionary's insertion order at equal times.
var _participants: SimParticipationIndex = ParticipationIndex.new()
var _wound_order: Dictionary = {}
var _next_wound_order: int = 0


static func _actor_wounds(actor: String) -> StringName:
	return StringName("health:wounds:actor:" + actor)


static func _actor_care(actor: String) -> StringName:
	return StringName("health:care:actor:" + actor)


static func _next_wound_boundary(now: int) -> int:
	@warning_ignore("integer_division")
	return (now / MINUTE_MS + 1) * MINUTE_MS


func _add_wound_participant(id: String) -> void:
	var wound: Dictionary = wounds[id]
	var actor: String = str(wound.actor)
	var actor_kind: StringName = _actor_wounds(actor)
	_participants.set_member(WOUND_WORK, id)
	_participants.set_active(WOUND_WORK, id, true)
	_participants.set_due(WOUND_WORK, id, _next_wound_boundary(int(world.elapsed_ms)))
	_participants.set_member(actor_kind, id)
	_participants.set_active(actor_kind, id, true)
	_wound_order[id] = _next_wound_order
	_next_wound_order += 1
	if wound.type == "meridian_irritation":
		_sync_care_candidate(actor)


func _remove_wound_participant(id: String) -> void:
	var wound: Dictionary = wounds[id]
	var actor: String = str(wound.actor)
	var actor_kind: StringName = _actor_wounds(actor)
	_participants.cancel_due(WOUND_WORK, id)
	_participants.set_active(WOUND_WORK, id, false)
	_participants.set_member(WOUND_WORK, id, false)
	_participants.set_active(actor_kind, id, false)
	_participants.set_member(actor_kind, id, false)
	_wound_order.erase(id)
	if wound.type == "meridian_irritation":
		_sync_care_candidate(actor)


func _sync_care_candidate(actor: String) -> void:
	# Follow the original first-source rule, including an earlier treated wound
	# taking precedence over a later untreated wound until it recovers.
	var source: String = source_of_type(actor, "meridian_irritation")
	var eligible: bool = not source.is_empty() and int(wounds[source].treated_ms) < 0
	if eligible:
		_participants.set_member(CARE_PATIENTS, actor)
		_participants.set_active(CARE_PATIENTS, actor, true)
	elif _participants.has_member(CARE_PATIENTS, actor):
		_participants.set_active(CARE_PATIENTS, actor, false)
		_participants.set_member(CARE_PATIENTS, actor, false)


func _add_care_participant(id: String) -> void:
	var job: Dictionary = jobs[id]
	_participants.set_member(CARE_WORK, id)
	_participants.set_active(CARE_WORK, id, true)
	_participants.set_due(CARE_WORK, id, int(job.due_ms))
	for actor: String in [str(job.patient), str(job.doctor)]:
		var actor_kind: StringName = _actor_care(actor)
		_participants.set_member(actor_kind, id)
		_participants.set_active(actor_kind, id, true)


func _remove_care_participant(id: String) -> void:
	var job: Dictionary = jobs[id]
	_participants.cancel_due(CARE_WORK, id)
	_participants.set_active(CARE_WORK, id, false)
	_participants.set_member(CARE_WORK, id, false)
	for actor: String in [str(job.patient), str(job.doctor)]:
		var actor_kind: StringName = _actor_care(actor)
		_participants.set_active(actor_kind, id, false)
		_participants.set_member(actor_kind, id, false)


func _rebuild_participants() -> void:
	# Only called after a validated restore. Iterate the original dictionary to
	# preserve its recovery order; completed history is not real-time work.
	_participants.clear()
	_wound_order.clear()
	_next_wound_order = 0
	for id: String in wounds:
		if int(wounds[id].remaining) > 0:
			_add_wound_participant(id)
	for id: String in jobs:
		if jobs[id].status == "active":
			_add_care_participant(id)


func participation_summary() -> Dictionary:
	# Diagnostics for the simulation owner and tests; never a player's knowledge.
	return {
		"active_wounds": _participants.active_ids(WOUND_WORK).size(),
		"active_care": _participants.active_ids(CARE_WORK).size(),
		"care_candidates": _participants.active_ids(CARE_PATIENTS).size(),
	}


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "interaction_cells", "diagnose_ms", "treat_ms", "material", "material_amount", "practices", "recovery", "contusion", "policy"]) or data.version != 1:
		return false
	for field: String in ["interaction_cells", "diagnose_ms", "treat_ms", "material_amount"]:
		if not Shape.count(data[field], 1, 86400000):
			return false
	if not SimInventory._nonempty(data.material) or not data.practices is Dictionary or not Shape.keys(data.recovery, ["required", "normal", "resting", "treated", "treated_resting"]) or not data.policy is Dictionary or SimSocialMemory.new()._normalized_policy(data.policy).is_empty():
		return false
	for rate: Variant in data.recovery.values():
		if not Shape.count(rate, 1, 86400):
			return false
	if not Shape.keys(data.contusion, ["recovery_per_impact", "normal", "resting", "retreat_burden", "max_impact"]):
		return false
	for amount: Variant in data.contusion.values():
		if not Shape.count(amount, 1, 86400):
			return false
	if int(data.contusion.max_impact) * int(data.contusion.recovery_per_impact) > 86400000:
		return false
	for id: Variant in data.practices:
		if not SimInventory._nonempty(id) or not SimEmbodiment._unique_texts(data.practices[id]) or data.practices[id] != ["herbal_meridian_care"]:
			return false
	return true


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules):
		return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].has_actor(actor):
			return region
	return ""


func eligible(actor: String) -> bool:
	return not home(actor).is_empty() and not world.embodiment.carrier_for_source("village_actor", actor).is_empty()


func can_diagnose(actor: String) -> bool:
	return eligible(actor) and definitions.practices.has(world.regions[home(actor)].actor_state(actor).definition_id)


func record_effect(event: Dictionary) -> void:
	if world.artifacts.events.is_empty() or world.artifacts.events.back() != event or event.kind not in ["backlash", "fractured"] or not eligible(str(event.actor)) or int(str(event.id).get_slice(":", 2)) < source_floor or wounds.has(event.id):
		return
	# Called only by the original artifact commit. No textual/visual inference.
	wounds[event.id] = {"actor": event.actor, "region": home(str(event.actor)), "type": "meridian_irritation", "at_ms": int(event.at_ms), "remaining": int(definitions.recovery.required), "treated_ms": -1, "recovered_ms": -1, "recovery": []}
	_add_wound_participant(str(event.id))
	world.invalidate_region(home(str(event.actor)))


func current_source(actor: String) -> String:
	# Existing care and channeling callers refer specifically to meridian harm.
	return source_of_type(actor, "meridian_irritation")


func source_of_type(actor: String, type: String) -> String:
	for id: String in _participants.active_ids(_actor_wounds(actor)):
		if wounds[id].actor == actor and wounds[id].type == type and int(wounds[id].remaining) > 0:
			return id
	return ""


func conflict_sources() -> Dictionary:
	var conflicts: RefCounted = world.get("conflicts")
	if conflicts == null or not conflicts.has_method("wound_sources"):
		return {}
	var result: Variant = conflicts.wound_sources()
	return result if result is Dictionary else {}


func record_conflict_effect(source_id: String) -> bool:
	var source: Variant = conflict_sources().get(source_id)
	if wounds.has(source_id) or not Schema.valid_conflict_source(source_id, source, self) or Schema.conflict_number(source_id) < conflict_source_floor or int(source.at_ms) != int(world.elapsed_ms):
		return false
	# Only a committed hit in the conflict authority can create this consequence.
	wounds[source_id] = {"actor": source.actor, "region": source.region, "type": "contusion", "impact": int(source.impact), "at_ms": int(source.at_ms), "remaining": int(source.impact) * int(definitions.contusion.recovery_per_impact), "treated_ms": -1, "recovered_ms": -1, "recovery": []}
	_add_wound_participant(source_id)
	world.invalidate_region(str(source.region))
	return true


func combat_burden(actor: String) -> int:
	var burden: int = 0
	var unit: int = int(definitions.contusion.recovery_per_impact)
	for id: String in _participants.active_ids(_actor_wounds(actor)):
		var wound: Dictionary = wounds[id]
		if wound.actor == actor and wound.type == "contusion" and int(wound.remaining) > 0:
			@warning_ignore("integer_division")
			var remaining_impact: int = (int(wound.remaining) + unit - 1) / unit
			burden += remaining_impact
	return burden


func can_fight(actor: String) -> bool:
	return eligible(actor) and bool(world.regions[home(actor)].actor_state(actor).alive) and combat_burden(actor) < int(definitions.contusion.retreat_burden)


func recovery_required(wound: Dictionary) -> int:
	return int(wound.impact) * int(definitions.contusion.recovery_per_impact) if wound.type == "contusion" else int(definitions.recovery.required)


func recovery_amount(wound: Dictionary, rested: bool, treated: bool) -> int:
	if wound.type == "contusion":
		return int(definitions.contusion.resting if rested else definitions.contusion.normal)
	var key: String = "treated_resting" if treated and rested else "treated" if treated else "resting" if rested else "normal"
	return int(definitions.recovery[key])


func blocks_channeling(actor: String) -> bool:
	return not current_source(actor).is_empty()


func owns_actor(actor: String) -> bool:
	for id: String in _participants.active_ids(_actor_care(actor)):
		var job: Dictionary = jobs[id]
		if job.status == "active" and actor in [job.patient, job.doctor]:
			return true
	return false


func previous_autonomy(actor: String) -> bool:
	for id: String in _participants.active_ids(_actor_care(actor)):
		var job: Dictionary = jobs[id]
		if job.status == "active" and actor in [job.patient, job.doctor]:
			return bool(job.patient_autonomous if actor == job.patient else job.doctor_autonomous)
	return false


func duration(verb: String) -> int:
	return int(definitions.diagnose_ms if verb == "diagnose" else definitions.treat_ms)


func social_for(patient: String, doctor: String) -> SimSocialMemory:
	return world.regions[home(doctor)].social if home(patient) == home(doctor) else (null if world.services == null else world.services.social)


func terms(patient: String, doctor: String, verb: String, source: String) -> Dictionary:
	return {"patient": patient, "doctor": doctor, "verb": verb, "source": source, "material": str(definitions.material) if verb == "treat" else "", "amount": int(definitions.material_amount) if verb == "treat" else 0}


func _available(actor: String) -> bool:
	var person: Dictionary = world.regions[home(actor)].actor_state(actor)
	return bool(person.alive) and person.active.is_empty() and world.native_action_allowed(actor) and world.actor_controls(actor, "motion") and world.actor_controls(actor, "communication")


func distance(left: String, right: String) -> float:
	return SimRouteTravel.point(world.regions[home(left)].actor_state(left)).distance_to(SimRouteTravel.point(world.regions[home(right)].actor_state(right))) / float(TileGrid.TILE_SIZE)


func diagnosis(patient: String, doctor: String, source: String) -> String:
	for id: String in world._sorted_keys(jobs):
		var job: Dictionary = jobs[id]
		if job.patient == patient and job.doctor == doctor and job.source == source and job.verb == "diagnose" and job.status == "completed":
			return id
	return ""


func request(patient: String, doctor: String, verb: String, autonomous: bool = false) -> Dictionary:
	if patient == doctor or verb not in ["diagnose", "treat"] or not eligible(patient) or not eligible(doctor):
		return reply(false, "incapable", "这副身体还没有适用的查看与处理办法。")
	if world.elapsed_ms > SimInventory.MAX_COUNT - duration(verb) or (not autonomous and world.elapsed_ms != world.target_ms) or (autonomous and not world.autonomous_decision(patient)):
		return reply(false, "unavailable", "先等手头的世界事务接续完。")
	world.synchronize_region(home(patient))
	world.synchronize_region(home(doctor))
	if distance(patient, doctor) > float(definitions.interaction_cells):
		return reply(false, "unheard", "先到对方面前，说明哪里不适。")
	if not can_diagnose(doctor):
		return reply(false, "incapable", "对方没有处理这种经脉不适的医药经历，不能凭猜测用药。")
	var source: String = current_source(patient)
	if source.is_empty():
		return reply(false, "unavailable", "本人眼下没有这种持续不适；这不是万能治愈。")
	if not _available(patient) or not _available(doctor) or not bool(world.regions[home(doctor)].actor_state(doctor).autonomous):
		return reply(false, "unavailable", "双方需要先放下手头的事，再由本人答应接受查看或处理。")
	var prior: String = diagnosis(patient, doctor, source)
	var sim: VillageSimulation = world.regions[home(patient)]
	if verb == "treat":
		if prior.is_empty():
			return reply(false, "unavailable", "先由这位懂行者实际查看，不能只凭听说就处理。")
		if int(wounds[source].treated_ms) >= 0:
			return reply(false, "unavailable", "已经处理过，接下来需要休养，不宜重复敷药。")
		if sim.inventory.available("actor:" + patient, str(definitions.material)) < int(definitions.material_amount):
			return reply(false, "unavailable", "需要本人可处分的一份鲜药；受托公物或预约药材不能擅用。")
	var memory: SimSocialMemory = social_for(patient, doctor)
	if memory == null:
		return reply(false, "unavailable", "眼下没有办法当面商量。")
	var body: Dictionary = world.regions[home(doctor)].actor_state(doctor)
	var relation: Dictionary = memory.relation(doctor, patient)
	var context: Dictionary = {"energy": floorf(float(body.energy) / 20.0) / 5.0, "busy": 0.0, "distance": 0.0, "risk": 0.0, "duty": 0.0, "offer": 0.0,
		"benevolence": float(world.regions[home(doctor)].config.actor_profiles[doctor].get("benevolence", 0.5)), "affinity": relation.affinity, "reliability": relation.reliability, "terms": terms(patient, doctor, verb, source)}
	var rng: RandomNumberGenerator = sim._rng if home(patient) == home(doctor) else world.services._rng
	var decision: Dictionary = memory.evaluate_request(patient, doctor, "health:" + verb, context, definitions.policy, rng, world.current_time)
	if decision.get("status") != "accepted":
		return reply(false, "refused", "对方这次没有答应腾出时间；同样的条件反复请求不会重掷。")
	var id: String = "health:action:%d" % next_id
	if verb == "treat" and not sim.inventory.consume(id + ":material", "actor:" + patient, str(definitions.material), int(definitions.material_amount)):
		return reply(false, "unavailable", "药材已不可用，处理没有开始。")
	var person: Dictionary = sim.actor_state(patient)
	jobs[id] = {"id": id, "patient": patient, "doctor": doctor, "patient_region": home(patient), "doctor_region": home(doctor), "source": source, "verb": verb,
		"consent": str(decision.id), "started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + duration(verb), "finished_ms": -1, "status": "active", "patient_autonomous": bool(person.autonomous), "doctor_autonomous": bool(body.autonomous), "patient_position": person.position.duplicate(), "doctor_position": body.position.duplicate(), "diagnosis": prior if verb == "treat" else ""}
	_add_care_participant(id)
	next_id += 1
	person.autonomous = false
	body.autonomous = false
	person.goal = "请人查看不适" if verb == "diagnose" else "接受敷药处理"
	body.goal = "当面查看不适" if verb == "diagnose" else "当面处理灼涩"
	world.invalidate_region(home(patient))
	world.invalidate_region(home(doctor))
	return reply(true, "started", "双方留在原处查看，完成后才有结论。" if verb == "diagnose" else "鲜药已投入，双方正在处理；中断不会退药，完成后仍须休养。", id)


func _connected(job: Dictionary) -> bool:
	for actor: String in [str(job.patient), str(job.doctor)]:
		if not eligible(actor):
			return false
		var person: Dictionary = world.regions[home(actor)].actor_state(actor)
		var position: Array = job.patient_position if actor == job.patient else job.doctor_position
		if not bool(person.alive) or not person.active.is_empty() or person.position != position:
			return false
		for channel: String in ["action", "motion", "communication"]:
			if not world.actor_controls(actor, channel):
				return false
		var conflicts: RefCounted = world.get("conflicts")
		if conflicts != null and conflicts.owns_actor(actor):
			return false
	return distance(str(job.patient), str(job.doctor)) <= float(definitions.interaction_cells)


func _finish(job: Dictionary, outcome: String) -> void:
	job.status = outcome
	job.finished_ms = world.elapsed_ms
	_remove_care_participant(str(job.id))
	if outcome == "completed" and job.verb == "treat":
		wounds[job.source].treated_ms = world.elapsed_ms
		_sync_care_candidate(str(job.patient))
	for actor: String in [str(job.patient), str(job.doctor)]:
		var body: Dictionary = world.regions[home(actor)].actor_state(actor)
		body.autonomous = job.patient_autonomous if actor == job.patient else job.doctor_autonomous
		body.goal = "刚结束查看" if job.verb == "diagnose" else "刚结束处理，仍需休养"
		body.retry_ms = world.elapsed_ms + int(world.regions[home(actor)].config.decision_interval) * MINUTE_MS
		world.invalidate_region(home(actor))
	for actor: String in [str(job.patient), str(job.doctor)]:
		SimActionContract.job_finished(world, "health", job, actor, outcome)


func cancel(actor: String) -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	for id: String in _participants.active_ids(_actor_care(actor)):
		var job: Dictionary = jobs[id]
		if job.status == "active" and actor in [job.patient, job.doctor]:
			_finish(job, "cancelled")
			return true
	return false


func next_boundary_ms() -> int:
	var next: int = _participants.next_due_ms(WOUND_WORK, SimInventory.MAX_COUNT)
	# A caller may query after directly advancing a test world. Preserve the
	# original next-global-minute rule even if it skipped a prior boundary.
	if next != SimInventory.MAX_COUNT and next <= int(world.elapsed_ms):
		next = _next_wound_boundary(int(world.elapsed_ms))
	for id: String in _participants.active_ids(CARE_WORK):
		if not _connected(jobs[id]):
			return world.elapsed_ms + 1
	return mini(next, _participants.next_due_ms(CARE_WORK, SimInventory.MAX_COUNT))


func settle_at_ms(now: int) -> void:
	for id: String in _participants.active_ids(CARE_WORK):
		var job: Dictionary = jobs[id]
		if job.status != "active":
			continue
		world.synchronize_region(str(job.patient_region))
		world.synchronize_region(str(job.doctor_region))
		if not _connected(job):
			_finish(job, "failed")
		elif now >= int(job.due_ms):
			_finish(job, "completed" if int(wounds[job.source].remaining) > 0 else "failed")
	if now % MINUTE_MS != 0:
		return
	var wound_ids: Array[String] = _participants.active_ids(WOUND_WORK)
	wound_ids.sort_custom(func(left: String, right: String) -> bool:
		return int(_wound_order[left]) < int(_wound_order[right]))
	for id: String in wound_ids:
		var wound: Dictionary = wounds[id]
		if int(wound.remaining) <= 0 or now < int(wound.at_ms) + MINUTE_MS or not wound.recovery.is_empty() and int(wound.recovery.back().at_ms) >= now:
			_participants.set_due(WOUND_WORK, id, _next_wound_boundary(now))
			continue
		world.synchronize_region(str(wound.region))
		var actor: String = str(wound.actor)
		var body: Dictionary = world.regions[wound.region].actor_state(actor)
		var rested: bool = body.active.get("action") == "rest" and body.active.get("phase") == "work" and int(body.active.get("segment_started_ms", now)) <= now - MINUTE_MS
		if world.resting != null and world.resting.active.has(actor):
			var bed_job: Dictionary = world.resting.active[actor]
			rested = rested or bed_job.get("phase") == "sleep" and int(bed_job.get("arrived_ms", now)) <= now - MINUTE_MS
		var treated: bool = int(wound.treated_ms) >= 0 and int(wound.treated_ms) <= now - MINUTE_MS
		var amount: int = mini(int(wound.remaining), recovery_amount(wound, rested, treated))
		wound.remaining = int(wound.remaining) - amount
		wound.recovery.append({"at_ms": now, "resting": rested, "treated": treated, "amount": amount})
		if int(wound.remaining) == 0:
			wound.recovered_ms = now
			_remove_wound_participant(id)
		else:
			_participants.set_due(WOUND_WORK, id, _next_wound_boundary(now))
		world.invalidate_region(str(wound.region))


func describe(actor: String) -> String:
	if not eligible(actor):
		return ""
	var source: String = current_source(actor)
	var line: String = "身体：眼下没有持续的经脉灼涩。" if source.is_empty() else "身体：手臂灼涩，引流不顺；可以走动、吃饭和求助。" + ("已经敷药，仍须慢慢休养。" if int(wounds[source].treated_ms) >= 0 else "先停下催动，向近旁懂行者求助。")
	if combat_burden(actor) > 0:
		line += "\n筋肉受碰撞后酸痛，走动与休养仍可进行。" + ("已不宜继续交手，应先退开休养。" if not can_fight(actor) else "勉强交手会继续积累碰撞伤。")
	return line


func pending(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in world._sorted_keys(jobs):
		var job: Dictionary = jobs[id]
		if job.patient == actor:
			result.append({"domain": "health", "id": id, "performer": world.embodiment.subject_for_actor(str(job.doctor))})
	return result


func observe(actor: String, process: Dictionary) -> Dictionary:
	var job: Dictionary = jobs.get(process.get("id", ""), {})
	if job.is_empty() or actor not in [job.patient, job.doctor] or process.get("performer") != world.embodiment.subject_for_actor(str(job.doctor)):
		return SimInteractionRequests.result("unconfirmed", "本人没有这次查看或处理的记录。")
	var line: String = "双方仍在当面查看，尚无结论。" if job.verb == "diagnose" else "药已投入，处理尚未完成；中断不会退药。"
	if job.status == "completed":
		line = "对方查到经脉受回卷灼涩，建议停引流、用鲜药处理并休养。" if job.verb == "diagnose" else "敷药处理已完成；不是立即康复，还需休养。"
	elif job.status != "active":
		line = "查看中断，没有新结论。" if job.verb == "diagnose" else "处理中断；已投入的鲜药不能退回，也没有提前获得处理效果。"
	return SimInteractionRequests.result("pending" if job.status == "active" else "completed" if job.status == "completed" else "cancelled", line, process)


func wants_decision(actor: String, _at_ms: int) -> bool:
	var source: String = current_source(actor)
	return not source.is_empty() and int(wounds[source].treated_ms) < 0


func consider() -> void:
	for actor: String in _participants.active_ids(CARE_PATIENTS):
		if home(actor).is_empty():
			continue
		if not wants_decision(actor, world.elapsed_ms) or not world.autonomous_decision(actor):
			continue
		var started: bool = false
		var source: String = current_source(actor)
		for other: String in world._actor_ids(world.regions):
			if other == actor or distance(actor, other) > float(definitions.interaction_cells):
				continue
			var verb: String = "diagnose" if diagnosis(actor, other, source).is_empty() else "treat"
			if request(actor, other, verb, true).ok:
				started = true
				break
		if not started:
			world.regions[home(actor)]._choose_routine(actor, false)


static func empty_state(floor_value: int = 1) -> Dictionary:
	return {"version": VERSION, "source_floor": floor_value, "conflict_source_floor": 1, "next_id": 1, "wounds": {}, "jobs": {}}


func to_dict() -> Dictionary:
	return {"version": VERSION, "source_floor": source_floor, "conflict_source_floor": conflict_source_floor, "next_id": next_id, "wounds": wounds.duplicate(true), "jobs": jobs.duplicate(true)}


static func upgrade_legacy(data: Variant) -> Dictionary:
	if not data is Dictionary:
		return {}
	var upgraded: Dictionary = data.duplicate(true)
	if upgraded.get("version") == 1 and Shape.keys(upgraded, ["version", "source_floor", "next_id", "wounds", "jobs"]):
		upgraded.version = VERSION
		upgraded["conflict_source_floor"] = 1
	return upgraded


func restore(data: Variant) -> bool:
	data = upgrade_legacy(data)
	if not Schema.validate(data, self):
		return false
	source_floor = int(data.source_floor)
	conflict_source_floor = int(data.conflict_source_floor)
	next_id = int(data.next_id)
	wounds = data.wounds.duplicate(true)
	jobs = data.jobs.duplicate(true)
	_rebuild_participants()
	return true


static func reply(ok: bool, code: String, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "code": code, "line": line, "id": id}
