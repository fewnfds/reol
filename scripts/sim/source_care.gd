class_name SimSourceCare
extends RefCounted
## A finite intention and attributed conversations, never another body or ledger.

const VERSION: int = 1
const NEVER: int = 0x3fffffffffffffff
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/source_care_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
var definitions: Dictionary = {}
var arrangements: Dictionary = {}
var warnings: Dictionary = {}
var explanations: Dictionary = {}
var next_warning_id: int = 1
var next_explanation_id: int = 1
var _handed_off: Dictionary = {}
var _committing: String = ""
var _interrupted_source: String = ""
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref() if _owner != null else null


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "watch_action", "observation_ms", "revisit_ms", "grace_ms", "max_arrangements", "max_warnings", "max_explanations", "interaction_px", "policy", "labels"]) or not Shape.count(data.version, 1, 1) or not SimInventory._nonempty(data.watch_action): return false
	for key: String in ["observation_ms", "revisit_ms", "grace_ms"]:
		if not Shape.count(data[key], 1, 86400000): return false
	for key: String in ["max_arrangements", "max_warnings", "max_explanations"]:
		if not Shape.count(data[key], 1, 4096): return false
	if not SimSnapshotSchema._number(data.interaction_px) or float(data.interaction_px) <= 0.0 or not data.policy is Dictionary or SimSocialMemory.new()._normalized_policy(data.policy).is_empty(): return false
	if not Shape.keys(data.labels, ["arrangement", "warning", "unauthenticated", "accepted", "refused"]): return false
	for value: Variant in data.labels.values():
		if not SimInventory._nonempty(value): return false
	return true


static func empty_state() -> Dictionary:
	return {"version": VERSION, "arrangements": {}, "warnings": {}, "explanations": {}, "next_warning_id": 1, "next_explanation_id": 1}


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules): return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func bind_world(authority: RefCounted) -> void:
	_owner = weakref(authority)


func spawn_opening(scenario: Dictionary) -> bool:
	if world == null or world.site_affairs == null or not arrangements.is_empty() or not warnings.is_empty() or not explanations.is_empty() or world.elapsed_ms != world.target_ms or not Shape.keys(scenario, ["version", "arrangements"]) or not Shape.count(scenario.version, 1, 1) or not scenario.arrangements is Array or scenario.arrangements.is_empty() or scenario.arrangements.size() > int(definitions.max_arrangements): return false
	var pending_rows: Dictionary = {}
	var guards: Dictionary = {}
	for value: Variant in scenario.arrangements:
		if not Shape.keys(value, ["id", "case", "guard", "duration_ms"]) or not SimInventory._nonempty(value.id) or pending_rows.has(value.id) or guards.has(value.guard) or not Shape.count(value.duration_ms, 1, 86400000) or not world.site_affairs.cases.has(value.case): return false
		var case_row: Dictionary = world.site_affairs.cases[value.case]
		var sim: VillageSimulation = world.regions[case_row.region]
		var office: Dictionary = sim.institutions.institutions.get(case_row.institution, {}).get("offices", {}).get(case_row.office, {})
		var issuer: String = str(office.get("holder", ""))
		if not sim.actors.has(value.guard) or not sim.actors.has(issuer) or issuer == value.guard or not office.get("permissions", []).has(case_row.permission) or not sim.config.actions.has(definitions.watch_action) or sim.config.actions[definitions.watch_action].get("kind") != "visit" or sim.config.actions[definitions.watch_action].get("target") != case_row.return_place or world.elapsed_ms > SimInventory.MAX_COUNT - int(value.duration_ms): return false
		pending_rows[value.id] = {"id": value.id, "case": value.case, "region": case_row.region, "guard": value.guard, "issuer": issuer, "office": case_row.office, "started_ms": int(world.elapsed_ms), "until_ms": int(world.elapsed_ms) + int(value.duration_ms), "status": "active", "ended_ms": -1, "event": "", "end_event": "", "next_observation_ms": -1, "next_visit_ms": int(world.elapsed_ms) + int(definitions.revisit_ms), "visit_action": ""}
		guards[value.guard] = true
	for row: Dictionary in pending_rows.values():
		row.event = _record(row, "source_care_opened", str(row.issuer), str(row.guard), {"arrangement": row.id, "case": row.case, "office": row.office, "until_ms": row.until_ms, "basis": "opening_accepted"})
		arrangements[row.id] = row
		world.invalidate_region(str(row.region))
	return true


func wants_decision(actor: String, at_ms: int) -> bool:
	var row: Dictionary = _arrangement_for(actor)
	if row.is_empty() or at_ms < int(row.next_visit_ms) or at_ms >= int(row.until_ms) or not _authorized(row): return false
	var person: Dictionary = _body(actor)
	return not person.is_empty() and bool(person.autonomous) and person.active.is_empty() and _needs_met(row) and _healthy_to_watch(row) and _no_other_duty(row, at_ms) and world.native_action_allowed(actor)


func note_decision(actor: String, at_ms: int) -> void:
	if wants_decision(actor, at_ms): _handed_off[actor] = at_ms


func consider() -> void:
	for actor: String in world._sorted_keys(_handed_off):
		if int(_handed_off[actor]) != int(world.elapsed_ms) or not world.autonomous_decision(actor) or not wants_decision(actor, int(world.elapsed_ms)): continue
		var row: Dictionary = _arrangement_for(actor)
		var sim: VillageSimulation = world.regions[row.region]
		if sim.submit_action(actor, str(definitions.watch_action)):
			row.visit_action = str(sim.actors[actor].active.id)
			row.next_visit_ms = world.elapsed_ms + int(definitions.revisit_ms)
			row.next_observation_ms = world.elapsed_ms + int(definitions.observation_ms) if _has_source(row) else -1
			world.invalidate_region(str(row.region))
		else:
			row.next_visit_ms = world.elapsed_ms + int(sim.config.retry_minutes) * 60000
	_handled_handoffs()


func _handled_handoffs() -> void:
	# Handoffs are transient scheduling hints, never a second saved intention.
	_handed_off.clear()


func next_boundary_ms() -> int:
	var boundary: int = NEVER
	for row: Dictionary in arrangements.values():
		if row.status != "active": continue
		boundary = mini(boundary, int(row.until_ms))
		if int(row.next_observation_ms) >= 0: boundary = mini(boundary, int(row.next_observation_ms))
		var person: Dictionary = _body(str(row.guard))
		if not person.is_empty() and bool(person.autonomous):
			if person.active.is_empty() and _needs_met(row) and _healthy_to_watch(row) and _no_other_duty(row, int(world.elapsed_ms)) and world.native_action_allowed(str(row.guard)):
				boundary = mini(boundary, maxi(int(row.next_visit_ms), int(person.retry_ms)))
			elif _own_visit(row):
				boundary = mini(boundary, _need_boundary(row))
	for warning: Dictionary in warnings.values():
		if warning.status == "active": boundary = mini(boundary, int(warning.due_ms))
	return maxi(int(world.elapsed_ms) + 1, boundary) if boundary != NEVER else NEVER


func settle_at_ms(now: int) -> void:
	for row: Dictionary in arrangements.values():
		if row.status != "active": continue
		world.synchronize_region(str(row.region))
		if now >= int(row.until_ms):
			_end_arrangement(row, "expired", int(row.until_ms))
			continue
		if not _authorized(row):
			_end_arrangement(row, "authority_lost", now)
			continue
		var person: Dictionary = _body(str(row.guard))
		if not _own_visit(row) and not str(row.visit_action).is_empty():
			row.visit_action = ""
		if _own_visit(row) and (not _needs_met(row) or not _no_other_duty(row, now) or not _healthy_to_watch(row)):
			world.regions[row.region].cancel_action(str(row.guard), "care_personal_need")
			row.visit_action = ""
			row.next_visit_ms = now + int(definitions.revisit_ms)
		var observation_due: bool = int(row.next_observation_ms) >= 0 and now >= int(row.next_observation_ms)
		for warning: Dictionary in warnings.values():
			if warning.arrangement != row.id or warning.status != "active": continue
			if not observation_due and now < int(warning.due_ms): continue
			if not _watching(row):
				_close(warning, "cancelled", "guard_unavailable")
			elif not _visible_job(row, _source_job(str(warning.source_job))):
				_close(warning, "cancelled", "lost_sight")
			elif now >= int(warning.due_ms):
				if not due_conflict(str(warning.id)).is_empty():
					world.conflicts.begin_source_care(str(warning.id))
				if warning.status == "active": _close(warning, "cancelled", "unable_to_drive_off")
		if _has_source(row) and (_watching(row) or _has_warning(row)):
			if observation_due:
				_sample(row)
				row.next_observation_ms = now + int(definitions.observation_ms)
			elif int(row.next_observation_ms) < 0:
				row.next_observation_ms = now + int(definitions.observation_ms)
		else:
			row.next_observation_ms = -1
		if not person.is_empty() and person.active.is_empty() and bool(person.autonomous) and now >= int(row.next_visit_ms) and _needs_met(row) and _healthy_to_watch(row) and _no_other_duty(row, now) and world.native_action_allowed(str(row.guard)):
			if int(_handed_off.get(row.guard, -1)) != now:
				row.next_visit_ms = now + int(definitions.revisit_ms)
				person.retry_ms = mini(int(person.retry_ms), int(row.next_visit_ms))
				world.invalidate_region(str(row.region))


func source_started(job: Dictionary) -> void:
	if world.spirit_sources.active.get(job.get("actor", ""), {}).get("id") != job.get("id"): return
	for row: Dictionary in arrangements.values():
		if row.status == "active" and _source_matches(row, job):
			row.next_observation_ms = world.elapsed_ms + int(definitions.observation_ms)


func source_finished(record: Dictionary) -> void:
	if world.spirit_sources.records.get(record.get("id", ""), {}) != record: return
	for warning: Dictionary in warnings.values():
		if warning.status != "active" or warning.source_job != record.id: continue
		if warning.id == _committing:
			_interrupted_source = str(record.id)
		else:
			_close(warning, "cancelled", "source_ended")
	for row: Dictionary in arrangements.values():
		if not _has_source(row): row.next_observation_ms = -1


func due_conflict(id: String) -> Dictionary:
	var warning: Dictionary = warnings.get(id, {})
	if warning.is_empty() or warning.status != "active" or world.elapsed_ms < int(warning.due_ms): return {}
	var row: Dictionary = arrangements.get(warning.arrangement, {})
	var job: Dictionary = _source_job(str(warning.source_job))
	if row.is_empty() or row.status != "active" or world.elapsed_ms >= int(row.until_ms) or not _authorized(row) or not _watching(row) or not _visible_job(row, job) or not _talk(str(row.guard), str(warning.actor), row): return {}
	if not _accepted_explanation(row, str(warning.actor), job).is_empty() or not _can_drive(row): return {}
	return {"initiator": str(row.guard), "defender": str(warning.actor), "source_job": str(warning.source_job)}


func conflict_starting(id: String) -> bool:
	if not _committing.is_empty() or due_conflict(id).is_empty(): return false
	_committing = id
	_interrupted_source = ""
	return true


func conflict_started(id: String, encounter_id: String) -> void:
	if _committing != id: return
	var warning: Dictionary = warnings.get(id, {})
	var encounter: Dictionary = world.conflicts.conflicts.get(encounter_id, {})
	if not warning.is_empty() and _interrupted_source == warning.source_job and encounter.get("cause") == {"domain": "source_care", "id": id}:
		warning.conflict = encounter_id
		_close(warning, "escalated", "escalated")
		var row: Dictionary = arrangements[warning.arrangement]
		row.visit_action = ""
	_committing = ""
	_interrupted_source = ""


func conflict_failed(id: String) -> void:
	if _committing == id:
		_committing = ""
		_interrupted_source = ""


func occupation_interrupted(actor: String) -> void:
	var row: Dictionary = _arrangement_for(actor)
	if row.is_empty(): return
	if not _own_visit(row): row.visit_action = ""
	for warning: Dictionary in warnings.values():
		if warning.arrangement == row.id and warning.status == "active" and warning.id != _committing: _close(warning, "cancelled", "guard_unavailable")


func basis_for(actor: String, receiver: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var row: Dictionary = _arrangement_for(receiver)
	if row.is_empty() or not _talk(actor, receiver, row): return result
	var known_case: bool = _warning_for(row, actor) != ""
	for note: Dictionary in world.site_affairs.notes.values():
		if note.actor != actor or note.case != row.case: continue
		var basis: Dictionary = _known_basis(actor, str(note.id), row)
		if basis.is_empty(): continue
		result.append({"id": str(note.id), "label": "说明本人记得的借源签注：" + str(note.id)})
		known_case = true
	if not known_case:
		for entry: Dictionary in world.site_affairs.known_cases(actor):
			if entry.get("id", entry.get("case", "")) == row.case: known_case = true
	if known_case: result.append({"id": "unauthenticated", "label": str(definitions.labels.unauthenticated)})
	return result


func explain(actor: String, receiver: String, basis_id: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms: return _reply(false, "unavailable", "先等眼下事务接续完，再当面说明。")
	var row: Dictionary = _arrangement_for(receiver)
	if row.is_empty() or not _talk(actor, receiver, row): return _reply(false, "unheard", "先走到仍在照看此事的人面前，才能说明。")
	var listed: bool = false
	for option: Dictionary in basis_for(actor, receiver):
		if option.id == basis_id: listed = true
	if not listed: return _reply(false, "unheard", "本人没有这条可以当面转述的依据。")
	var job: Dictionary = _visible_source_for(row, actor)
	var source_id: String = str(job.get("id", ""))
	for old: Dictionary in explanations.values():
		if old.arrangement == row.id and old.actor == actor and old.receiver == receiver and old.basis == basis_id and (old.source_job == source_id or source_id.is_empty()): return _explanation_reply(old)
	if explanations.size() >= int(definitions.max_explanations): return _reply(false, "unavailable", "这段照看已有太多未整理的说法，暂不能再记新条。")
	var basis: Dictionary = _known_basis(actor, basis_id, row) if basis_id != "unauthenticated" else {}
	var until: int = int(basis.get("until_ms", row.until_ms))
	var text: String = str(definitions.labels.unauthenticated) if basis.is_empty() else "我记得管事签过这次借源；所述用途为" + str(basis.target) + "，最迟开始时刻为" + str(until) + "。"
	var source_event: String = str(basis.get("event", ""))
	var sim: VillageSimulation = world.regions[row.region]
	if not source_event.is_empty() and not sim.social.knowledge[receiver].has(source_event): sim.social.learn(receiver, source_event, actor)
	var context: Dictionary = _context(row, actor, basis_id, source_event, source_id)
	var decision: Dictionary = sim.social.evaluate_request(actor, receiver, "source_care:explain:" + str(row.id), context, definitions.policy, sim._rng, sim.tick_index)
	if not decision.has("id"): return _reply(false, "unavailable", "对方尚未形成可以保存的判断。")
	var id: String = "care:explanation:%d" % next_explanation_id
	next_explanation_id += 1
	var entry: Dictionary = {"id": id, "arrangement": row.id, "actor": actor, "receiver": receiver, "basis": basis_id, "source_event": source_event, "source_job": source_id, "binding_event": "", "claim_event": "", "decision": str(decision.id), "accepted": decision.status == "accepted" and world.elapsed_ms < until, "at_ms": int(world.elapsed_ms), "until_ms": until, "target": str(basis.get("target", ""))}
	entry.claim_event = _record(row, "source_care_explained", actor, receiver, {"explanation": id, "arrangement": row.id, "basis": basis_id, "source_event": source_event, "source_job": source_id, "decision": entry.decision, "accepted": entry.accepted, "until_ms": until, "target": entry.target, "text": text})
	explanations[id] = entry
	if bool(entry.accepted):
		var warning_id: String = _warning_for(row, actor)
		if not warning_id.is_empty() and (source_id.is_empty() or warnings[warning_id].source_job == source_id):
			warnings[warning_id].explanation = id
			_close(warnings[warning_id], "resolved", "explained", true)
	return _explanation_reply(entry)


func arrangements_for(actor: String, receiver: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in arrangements.values():
		if receiver in [row.guard, row.issuer] and _talk(actor, receiver, row): result.append({"id": str(row.id), "label": str(definitions.labels.arrangement)})
	return result


func inquire(actor: String, receiver: String, id: String) -> Dictionary:
	var row: Dictionary = arrangements.get(id, {})
	if world.elapsed_ms != world.target_ms or row.is_empty() or receiver not in [row.guard, row.issuer] or not _talk(actor, receiver, row): return _reply(false, "unheard", "需要向实际参与这项安排的人当面询问。")
	var social: SimSocialMemory = world.regions[row.region].social
	if not social.knowledge[actor].has(row.event): social.learn(actor, str(row.event), receiver)
	return _reply(true, "completed", "这段照看只涉及灶旁这处公源与原温石；本人仍要吃饭歇息，借用签发须找现任管事。", id, _process(row, id))


func withdraw(actor: String, receiver: String, id: String) -> Dictionary:
	var row: Dictionary = arrangements.get(id, {})
	if world.elapsed_ms != world.target_ms or row.is_empty() or actor not in [row.guard, row.issuer] or receiver not in [row.guard, row.issuer] or not _talk(actor, receiver, row): return _reply(false, "unheard", "本人不能远程撤掉别人的看护安排；须由参与者当面说明。")
	if row.status != "active": return _reply(false, "cancelled", "这段照看已经结束。", id, _process(row, id))
	if actor == row.issuer and not _authorized(row): return _reply(false, "unavailable", "原委托者眼下已无权代表此处撤回安排。")
	row.end_event = _record(row, "source_care_ended", actor, receiver, {"arrangement": id, "status": "withdrawn"})
	_end_arrangement(row, "withdrawn", int(world.elapsed_ms))
	return _reply(true, "completed", "已当面说明不再照看；原实物、旧记录和已付的代价都仍在。", id, _process(row, id))


func pending(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in arrangements.values():
		var social: SimSocialMemory = world.regions[row.region].social
		if social.knowledge.get(actor, {}).has(row.event): result.append(_process(row, str(row.id)))
	for warning: Dictionary in warnings.values():
		var row: Dictionary = arrangements[warning.arrangement]
		if world.regions[row.region].social.knowledge.get(actor, {}).has(warning.event): result.append(_process(row, str(warning.id)))
	for entry: Dictionary in explanations.values():
		var row: Dictionary = arrangements[entry.arrangement]
		if world.regions[row.region].social.knowledge.get(actor, {}).has(entry.claim_event): result.append(_process(row, str(entry.id)))
	return result


func observe(actor: String, process: Dictionary) -> Dictionary:
	var id: String = str(process.get("id", ""))
	var warning: Dictionary = warnings.get(id, {})
	var explanation: Dictionary = explanations.get(id, {})
	var row: Dictionary = arrangements.get(warning.get("arrangement", explanation.get("arrangement", id)), {})
	if row.is_empty() or process.get("domain") != "source_care" or process.get("performer") != world.embodiment.subject_for_actor(str(row.guard)): return SimInteractionRequests.result("unconfirmed", "本人没有这条照看记录。")
	var known: Dictionary = world.regions[row.region].social.knowledge.get(actor, {})
	if not explanation.is_empty():
		if not known.has(explanation.claim_event): return SimInteractionRequests.result("unconfirmed", "本人没有听到这次说明。")
		return SimInteractionRequests.result("completed" if bool(explanation.accepted) else "refused", str(definitions.labels.accepted if bool(explanation.accepted) else definitions.labels.refused), process)
	if not warning.is_empty():
		if not known.has(warning.event): return SimInteractionRequests.result("unconfirmed", "本人没有听到这次警告。")
		var line: String = str(definitions.labels.warning)
		var informed_end: bool = not str(warning.end_event).is_empty() and known.has(warning.end_event)
		var encounter: Dictionary = world.conflicts.conflicts.get(str(warning.conflict), {})
		var own_conflict: bool = not encounter.is_empty() and encounter.get("people", {}).has(actor)
		if warning.status == "resolved" and known.has(warning.end_event): line = str(definitions.labels.accepted)
		elif warning.status == "escalated" and own_conflict: line = "劝阻已经转成交锋；挫伤与已付代价都按原过程保留。"
		return SimInteractionRequests.result("completed" if informed_end or own_conflict else "pending", line, process)
	if not known.has(row.event): return SimInteractionRequests.result("unconfirmed", "本人还未得知这项看护安排。")
	return SimInteractionRequests.result("completed", "本人记得有人在一段时限内照看灶旁公源；当前远处状况须实际问人或到场查看。", process)


func alerts_for(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for warning: Dictionary in warnings.values():
		if warning.actor != actor or warning.status != "active": continue
		var row: Dictionary = arrangements[warning.arrangement]
		if world.regions[row.region].social.knowledge.get(actor, {}).has(warning.event): result.append({"id": str(warning.id), "line": str(definitions.labels.warning), "process": _process(row, str(warning.id)), "received_ms": int(warning.started_ms), "until_ms": int(warning.due_ms)})
	return result


func to_dict() -> Dictionary:
	return {"version": VERSION, "arrangements": arrangements.duplicate(true), "warnings": warnings.duplicate(true), "explanations": explanations.duplicate(true), "next_warning_id": next_warning_id, "next_explanation_id": next_explanation_id}


func restore(data: Variant) -> bool:
	if not _committing.is_empty() or not Schema.validate(data, self): return false
	arrangements = data.arrangements.duplicate(true)
	warnings = data.warnings.duplicate(true)
	explanations = data.explanations.duplicate(true)
	next_warning_id = int(data.next_warning_id)
	next_explanation_id = int(data.next_explanation_id)
	_handed_off.clear()
	return true


func cross_valid() -> bool:
	return _committing.is_empty() and Schema.cross_valid(self)


func _sample(row: Dictionary) -> void:
	if not _watching(row): return
	for job: Dictionary in world.spirit_sources.active.values():
		if job.actor == row.guard or not _visible_job(row, job) or _ever_warned(row, str(job.id)): continue
		var accepted: Dictionary = _accepted_explanation(row, str(job.actor), job)
		if not accepted.is_empty():
			if str(accepted.source_job).is_empty():
				accepted.source_job = str(job.id)
				accepted.binding_event = _record(row, "source_care_basis_applied", str(row.guard), "", {"explanation": accepted.id, "source_job": job.id, "observer_position": _body(str(row.guard)).position.duplicate(), "position": _body(str(job.actor)).position.duplicate(), "level": Space.level(world, SimRouteTravel.point(_body(str(row.guard))))})
			continue
		if not _talk(str(row.guard), str(job.actor), row) or warnings.size() >= int(definitions.max_warnings) or world.elapsed_ms > SimInventory.MAX_COUNT - int(definitions.grace_ms): continue
		var id: String = "care:warning:%d" % next_warning_id
		next_warning_id += 1
		var warning: Dictionary = {"id": id, "arrangement": row.id, "actor": str(job.actor), "source_job": str(job.id), "observed_ms": int(world.elapsed_ms), "observer_position": _body(str(row.guard)).position.duplicate(), "position": _body(str(job.actor)).position.duplicate(), "level": Space.level(world, SimRouteTravel.point(_body(str(row.guard)))), "event": "", "started_ms": int(world.elapsed_ms), "due_ms": int(world.elapsed_ms) + int(definitions.grace_ms), "status": "active", "reason": "", "ended_ms": -1, "end_event": "", "explanation": "", "conflict": ""}
		warning.event = _record(row, "source_care_warned", str(row.guard), str(job.actor), {"warning": id, "arrangement": row.id, "source_job": str(job.id), "observer_position": warning.observer_position, "position": warning.position, "level": warning.level, "due_ms": warning.due_ms, "text": definitions.labels.warning})
		warnings[id] = warning


func _close(warning: Dictionary, status: String, reason: String, spoken: bool = false) -> void:
	if warning.status != "active": return
	warning.status = status
	warning.reason = reason
	warning.ended_ms = int(world.elapsed_ms)
	if spoken:
		var row: Dictionary = arrangements[warning.arrangement]
		warning.end_event = _record(row, "source_care_warning_ended", str(row.guard), str(warning.actor), {"warning": warning.id, "status": status, "reason": reason, "explanation": warning.explanation, "conflict": warning.conflict})


func _end_arrangement(row: Dictionary, status: String, at_ms: int) -> void:
	row.status = status
	row.ended_ms = at_ms
	row.next_observation_ms = -1
	for warning: Dictionary in warnings.values():
		if warning.arrangement == row.id and warning.status == "active": _close(warning, "cancelled", "arrangement_closed")
		elif warning.arrangement == row.id and warning.status == "escalated":
			var encounter: Dictionary = world.conflicts.conflicts.get(warning.conflict, {})
			if encounter.get("ended_ms", 0) == -1: world.conflicts.cancel(str(row.guard))
	# Only this arrangement's own harmless native visit can be released here.
	if _own_visit(row):
		world.regions[row.region].cancel_action(str(row.guard), "care_ended")
		_body(str(row.guard)).retry_ms = mini(int(_body(str(row.guard)).retry_ms), int(world.elapsed_ms) + 1)
	row.visit_action = ""
	world.invalidate_region(str(row.region))


func _accepted_explanation(row: Dictionary, actor: String, job: Dictionary) -> Dictionary:
	if job.is_empty(): return {}
	for entry: Dictionary in explanations.values():
		if entry.arrangement != row.id or entry.actor != actor or not bool(entry.accepted): continue
		if entry.source_job == job.id: return entry
		if str(entry.source_job).is_empty() and int(entry.at_ms) <= int(job.started_ms) and world.elapsed_ms < int(entry.until_ms): return entry
	return {}


func _known_basis(actor: String, basis_id: String, row: Dictionary) -> Dictionary:
	var note: Dictionary = world.site_affairs.notes.get(basis_id, {})
	if note.get("actor") != actor or note.get("case") != row.case: return {}
	var memory: Dictionary = world.regions[row.region].social.knowledge.get(actor, {}).get(str(note.get("issue_event", "")), {})
	var details: Dictionary = memory.get("details", {})
	var offer: Dictionary = world.site_affairs.definitions.offers.get(str(details.get("offer", "")), {})
	if memory.get("kind") != "site_loan_issued" or details.get("note") != basis_id or details.get("case") != row.case or offer.get("case") != row.case or not Shape.count(details.get("start_until_ms"), 0): return {}
	return {"event": str(note.issue_event), "until_ms": int(details.start_until_ms), "target": str(offer.target)}


func _context(row: Dictionary, actor: String, basis: String, source_event: String, source_job: String) -> Dictionary:
	var sim: VillageSimulation = world.regions[row.region]
	var person: Dictionary = sim.actors[row.guard]
	return {"energy": floorf(float(person.energy) / 20.0) / 5.0, "risk": 1.0 if source_event.is_empty() else 0.0, "reliability": float(sim.social.relation(str(row.guard), actor).reliability), "affinity": float(sim.social.relation(str(row.guard), actor).affinity), "terms": {"arrangement": row.id, "basis": basis, "source_event": source_event, "source_job": source_job}}


func _explanation_reply(entry: Dictionary) -> Dictionary:
	var row: Dictionary = arrangements[entry.arrangement]
	return _reply(true, "completed" if bool(entry.accepted) else "refused", str(definitions.labels.accepted if bool(entry.accepted) else definitions.labels.refused), str(entry.id), _process(row, str(entry.id)))


func _source_matches(row: Dictionary, job: Dictionary) -> bool:
	var case_row: Dictionary = world.site_affairs.cases.get(row.case, {})
	return not case_row.is_empty() and job.get("region") == row.region and job.get("source") == case_row.source and job.get("object") == case_row.object


func _source_job(id: String) -> Dictionary:
	if world.spirit_sources.records.has(id): return world.spirit_sources.records[id]
	for job: Dictionary in world.spirit_sources.active.values():
		if job.id == id: return job
	return {}


func _has_source(row: Dictionary) -> bool:
	for job: Dictionary in world.spirit_sources.active.values():
		if job.actor != row.guard and _source_matches(row, job): return true
	return false


func _has_warning(row: Dictionary) -> bool:
	for warning: Dictionary in warnings.values():
		if warning.arrangement == row.id and warning.status == "active": return true
	return false


func _visible_source_for(row: Dictionary, actor: String) -> Dictionary:
	var job: Dictionary = world.spirit_sources.active.get(actor, {})
	return job if _visible_job(row, job) else {}


func _visible_job(row: Dictionary, job: Dictionary) -> bool:
	if job.is_empty() or job.has("result") or not _source_matches(row, job): return false
	var person: Dictionary = _body(str(job.actor))
	return not person.is_empty() and _sees(str(row.guard), SimRouteTravel.point(person)) and _sees(str(row.guard), TileGrid.cell_to_world(world.spirit_sources.source_cell(str(job.source))))


func _sees(actor: String, point: Vector2) -> bool:
	var person: Dictionary = _body(actor)
	if person.is_empty() or not bool(person.alive): return false
	var from: Vector2 = SimRouteTravel.point(person)
	return from.distance_to(point) <= float(definitions.interaction_px) and Space.level(world, from) == Space.level(world, point) and Space.clear_segment(world, from, point, Space.level(world, from))


func _talk(actor: String, receiver: String, row: Dictionary) -> bool:
	if actor == receiver or not world.regions[row.region].actors.has(actor) or not world.regions[row.region].actors.has(receiver) or not world.actor_controls(actor, "communication") or not world.actor_controls(receiver, "communication"): return false
	var from: Vector2 = SimRouteTravel.point(_body(actor))
	var to: Vector2 = SimRouteTravel.point(_body(receiver))
	return from.distance_to(to) <= float(definitions.interaction_px) and Space.level(world, from) == Space.level(world, to) and Space.clear_segment(world, from, to, Space.level(world, from))


func _authorized(row: Dictionary) -> bool:
	var case_row: Dictionary = world.site_affairs.cases.get(row.case, {})
	if case_row.is_empty() or not world.regions.has(row.region): return false
	var office: Dictionary = world.regions[row.region].institutions.institutions.get(case_row.institution, {}).get("offices", {}).get(row.office, {})
	return office.get("holder") == row.issuer and office.get("permissions", []).has(case_row.permission)


func _arrangement_for(guard: String) -> Dictionary:
	for row: Dictionary in arrangements.values():
		if row.guard == guard and row.status == "active": return row
	return {}


func _body(actor: String) -> Dictionary:
	for sim: VillageSimulation in world.regions.values():
		if sim.actors.has(actor): return sim.actors[actor]
	return {}


func _own_visit(row: Dictionary) -> bool:
	var person: Dictionary = _body(str(row.guard))
	return not person.is_empty() and not str(row.visit_action).is_empty() and person.active.get("id") == row.visit_action and person.active.get("action") == definitions.watch_action


func _needs_met(row: Dictionary) -> bool:
	var person: Dictionary = _body(str(row.guard))
	var needs: Dictionary = world.regions[row.region].config.needs
	return not person.is_empty() and float(person.hunger) > float(needs.eat_below) and float(person.energy) > float(needs.rest_below)


func _healthy_to_watch(row: Dictionary) -> bool:
	return world.health == null or not world.health.wants_decision(str(row.guard), int(world.elapsed_ms)) and world.health.can_fight(str(row.guard))


func _no_other_duty(row: Dictionary, at_ms: int) -> bool:
	var actor: String = str(row.guard)
	var person: Dictionary = _body(actor)
	if person.is_empty() or not person.receipts.is_empty(): return false
	return (world.standing_work == null or world.standing_work.duty_for(actor, at_ms).is_empty()) and (world.construction == null or world.construction.duty_for(actor).is_empty()) and (world.resting == null or world.resting.duty_for(actor).is_empty()) and not SimWorkplaces.has_desk_duty(world.regions[row.region], actor)


func _watching(row: Dictionary) -> bool:
	var actor: String = str(row.guard)
	var person: Dictionary = _body(actor)
	if row.status != "active" or person.is_empty() or not bool(person.alive) or not bool(person.autonomous) or not _needs_met(row) or not _healthy_to_watch(row) or not _no_other_duty(row, int(world.elapsed_ms)) or not world.actor_controls(actor, "communication") or not world.actor_controls(actor, "motion") or not world.native_action_allowed(actor): return false
	if not person.active.is_empty() and (not _own_visit(row) or person.active.get("phase") != "work"): return false
	var case_row: Dictionary = world.site_affairs.cases[row.case]
	return _sees(actor, TileGrid.cell_to_world(world.spirit_sources.source_cell(str(case_row.source))))


func _need_boundary(row: Dictionary) -> int:
	var sim: VillageSimulation = world.regions[row.region]
	var person: Dictionary = sim.actors[row.guard]
	var result: int = NEVER
	for need: String in ["hunger", "energy"]:
		var rate: int = roundi(float(sim.config.needs.hunger_per_minute) * VillageSimulation.NEED_SCALE) if need == "hunger" else roundi(float(sim.config.needs.energy_per_minute) * VillageSimulation.NEED_SCALE) + roundi(float(sim.config.needs.work_energy_per_minute) * VillageSimulation.NEED_SCALE)
		if need == "energy": rate += world.clothing.energy_rate(str(row.guard)) + world.environment.energy_rate(str(row.guard))
		var threshold: float = float(sim.config.needs.eat_below) if need == "hunger" else float(sim.config.needs.rest_below)
		var remaining: int = maxi(0, roundi(float(person[need]) * VillageSimulation.NEED_SCALE) - roundi(threshold * VillageSimulation.NEED_SCALE))
		# Use the native fixed-point carry, so fine and sparse advancement see
		# the same first millisecond at which this visit must yield to a need.
		if rate > 0: result = mini(result, int(world.elapsed_ms) + maxi(1, ceili(float(remaining * 60000 - int(person.need_carry[need])) / rate)))
	return result


func _can_drive(row: Dictionary) -> bool:
	var actor: String = str(row.guard)
	var person: Dictionary = _body(actor)
	if world.conflicts == null or world.conflicts.owns_actor(actor) or world.sparring != null and world.sparring.owns_actor(actor) or world.health != null and not world.health.can_fight(actor) or int(person.stamina) <= int(world.conflicts.rules.stop_stamina): return false
	for method: String in ["sword", "qi_bolt"]:
		if not world.conflicts.knows(actor, method): continue
		if method != "sword" and world.health != null and world.health.blocks_channeling(actor): continue
		var spec: Dictionary = world.conflicts.rules.methods[method]
		if int(person.stamina) < int(spec.stamina) or int(person.qi) < int(spec.qi): continue
		if method != "sword" or not world.artifacts.held_weapon(actor).is_empty(): return true
	return false


func _warning_for(row: Dictionary, actor: String) -> String:
	for warning: Dictionary in warnings.values():
		if warning.arrangement == row.id and warning.actor == actor and warning.status == "active": return str(warning.id)
	return ""


func _ever_warned(row: Dictionary, job: String) -> bool:
	for warning: Dictionary in warnings.values():
		if warning.arrangement == row.id and warning.source_job == job: return true
	return false


func _record(row: Dictionary, kind: String, actor: String, target: String, details: Dictionary) -> String:
	var payload: Dictionary = details.duplicate(true)
	payload["at_ms"] = int(world.elapsed_ms)
	var witnesses: Array[String] = []
	@warning_ignore("integer_division")
	var tick: int = int(world.elapsed_ms) / 60000
	return world.regions[row.region].social.record(kind, actor, target, {"participants": payload}, witnesses, tick)


func _process(row: Dictionary, id: String) -> Dictionary:
	return {"domain": "source_care", "id": id, "performer": world.embodiment.subject_for_actor(str(row.guard))}


static func _reply(ok: bool, code: String, line: String, id: String = "", process: Dictionary = {}) -> Dictionary:
	return {"ok": ok, "code": code, "line": line, "id": id, "process": process}
