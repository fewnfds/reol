extends RefCounted
## Structural restoration is separate from original-owner causal validation.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const TOP: Array[String] = ["version", "arrangements", "warnings", "explanations", "next_warning_id", "next_explanation_id"]
const ARRANGEMENT: Array[String] = ["id", "case", "region", "guard", "issuer", "office", "started_ms", "until_ms", "status", "ended_ms", "event", "end_event", "next_observation_ms", "next_visit_ms", "visit_action"]
const WARNING: Array[String] = ["id", "arrangement", "actor", "source_job", "observed_ms", "observer_position", "position", "level", "event", "started_ms", "due_ms", "status", "reason", "ended_ms", "end_event", "explanation", "conflict"]
const EXPLANATION: Array[String] = ["id", "arrangement", "actor", "receiver", "basis", "source_event", "source_job", "binding_event", "claim_event", "decision", "accepted", "at_ms", "until_ms", "target"]
const REASONS: Array[String] = ["source_ended", "lost_sight", "guard_unavailable", "unable_to_drive_off", "arrangement_closed", "explained", "escalated"]


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, TOP) or not Shape.count(data.version, 1, 1): return false
	for key: String in ["arrangements", "warnings", "explanations"]:
		if not data[key] is Dictionary: return false
	if data.arrangements.size() > int(domain.definitions.max_arrangements) or not Shape.count(data.next_warning_id, 1, int(domain.definitions.max_warnings) + 1) or not Shape.count(data.next_explanation_id, 1, int(domain.definitions.max_explanations) + 1) or data.warnings.size() != int(data.next_warning_id) - 1 or data.explanations.size() != int(data.next_explanation_id) - 1: return false
	var guards: Dictionary = {}
	for id: Variant in data.arrangements:
		var row: Variant = data.arrangements[id]
		if not SimInventory._nonempty(id) or not Shape.keys(row, ARRANGEMENT) or row.id != id: return false
		for key: String in ["case", "region", "guard", "issuer", "office", "event"]:
			if not SimInventory._nonempty(row[key]): return false
		if row.guard == row.issuer or not row.end_event is String or not row.visit_action is String or row.status not in ["active", "withdrawn", "expired", "authority_lost"] or not Shape.count(row.started_ms, 0, int(domain.world.elapsed_ms)) or not Shape.count(row.until_ms, int(row.started_ms) + 1) or not Shape.count(row.ended_ms, -1, int(domain.world.elapsed_ms)) or not Shape.count(row.next_observation_ms, -1) or not Shape.count(row.next_visit_ms, int(row.started_ms)): return false
		if row.status == "active":
			if row.ended_ms != -1 or row.end_event != "" or guards.has(row.guard) or int(row.until_ms) <= int(domain.world.elapsed_ms): return false
			guards[row.guard] = id
			if row.next_observation_ms != -1 and int(row.next_observation_ms) <= int(domain.world.elapsed_ms): return false
		elif int(row.ended_ms) < int(row.started_ms) or row.next_observation_ms != -1 or row.visit_action != "": return false
		if row.status == "expired" and row.ended_ms != row.until_ms: return false
		if row.status == "withdrawn" and row.end_event == "": return false
	var warned_jobs: Dictionary = {}
	var prior: int = 0
	for number: int in range(1, int(data.next_warning_id)):
		var id: String = "care:warning:%d" % number
		var warning: Variant = data.warnings.get(id)
		if not Shape.keys(warning, WARNING) or warning.id != id or not data.arrangements.has(warning.arrangement): return false
		var row: Dictionary = data.arrangements[warning.arrangement]
		for key: String in ["actor", "source_job", "event"]:
			if not SimInventory._nonempty(warning[key]): return false
		for key: String in ["reason", "end_event", "explanation", "conflict"]:
			if not warning[key] is String: return false
		var job_key: String = str(warning.arrangement) + ":" + str(warning.source_job)
		if warned_jobs.has(job_key) or warning.actor == row.guard or not Shape.count(warning.started_ms, maxi(prior, int(row.started_ms)), int(domain.world.elapsed_ms)) or warning.observed_ms != warning.started_ms or not Shape.count(warning.due_ms, int(warning.started_ms) + int(domain.definitions.grace_ms), int(warning.started_ms) + int(domain.definitions.grace_ms)) or not Shape.count(warning.ended_ms, -1, int(domain.world.elapsed_ms)) or warning.status not in ["active", "resolved", "cancelled", "escalated"]: return false
		if not _observation(warning, domain): return false
		warned_jobs[job_key] = id
		prior = int(warning.started_ms)
		if warning.status == "active":
			if row.status != "active" or warning.ended_ms != -1 or warning.reason != "" or warning.end_event != "" or warning.conflict != "" or warning.explanation != "" or int(warning.due_ms) <= int(domain.world.elapsed_ms): return false
		elif int(warning.ended_ms) < int(warning.started_ms) or warning.reason not in REASONS: return false
		if warning.status == "resolved":
			if warning.reason != "explained" or warning.explanation == "" or warning.end_event == "" or warning.conflict != "": return false
		elif warning.explanation != "": return false
		if warning.status == "escalated":
			if warning.reason != "escalated" or warning.conflict == "" or int(warning.ended_ms) < int(warning.due_ms): return false
		elif warning.conflict != "": return false
	prior = 0
	for number: int in range(1, int(data.next_explanation_id)):
		var id: String = "care:explanation:%d" % number
		var entry: Variant = data.explanations.get(id)
		if not Shape.keys(entry, EXPLANATION) or entry.id != id or not data.arrangements.has(entry.arrangement): return false
		var row: Dictionary = data.arrangements[entry.arrangement]
		for key: String in ["actor", "basis", "claim_event", "decision"]:
			if not SimInventory._nonempty(entry[key]): return false
		for key: String in ["source_event", "source_job", "binding_event", "target"]:
			if not entry[key] is String: return false
		if entry.receiver != row.guard or entry.actor == row.guard or not entry.accepted is bool or not Shape.count(entry.at_ms, maxi(prior, int(row.started_ms)), int(domain.world.elapsed_ms)) or not Shape.count(entry.until_ms, 0) or entry.target not in ["", "body", "stone"]: return false
		if bool(entry.accepted) and int(entry.at_ms) >= int(entry.until_ms): return false
		if entry.basis == "unauthenticated":
			if entry.source_event != "" or entry.target != "" or entry.until_ms != row.until_ms: return false
		elif entry.source_event == "" or entry.target == "": return false
		if entry.source_job == "" and entry.binding_event != "": return false
		prior = int(entry.at_ms)
	return true


static func cross_valid(domain: RefCounted) -> bool:
	if not validate(domain.to_dict(), domain): return false
	if domain.world.site_affairs == null or domain.world.spirit_sources == null or domain.world.conflicts == null: return domain.arrangements.is_empty() and domain.warnings.is_empty() and domain.explanations.is_empty()
	for row: Dictionary in domain.arrangements.values():
		if not _arrangement(row, domain): return false
	for entry: Dictionary in domain.explanations.values():
		if not _explanation(entry, domain): return false
	var encounters: Dictionary = {}
	for warning: Dictionary in domain.warnings.values():
		if not _warning(warning, domain): return false
		if not str(warning.conflict).is_empty():
			if encounters.has(warning.conflict): return false
			encounters[warning.conflict] = warning.id
	for encounter: Dictionary in domain.world.conflicts.conflicts.values():
		var cause: Dictionary = encounter.get("cause", {})
		if cause.get("domain") == "source_care" and encounters.get(encounter.id) != cause.get("id"): return false
	return true


static func _arrangement(row: Dictionary, domain: RefCounted) -> bool:
	var case_row: Dictionary = domain.world.site_affairs.cases.get(row.case, {})
	if case_row.is_empty() or row.region != case_row.region or row.office != case_row.office or not domain.world.regions.has(row.region): return false
	var sim: VillageSimulation = domain.world.regions[row.region]
	if not sim.has_actor(row.guard) or not sim.has_actor(row.issuer): return false
	var action: Dictionary = sim.config.actions.get(domain.definitions.watch_action, {})
	if action.get("kind") != "visit" or action.get("target") != case_row.return_place: return false
	if not _event(domain, row, str(row.event), "source_care_opened", str(row.issuer), str(row.guard), int(row.started_ms), {"arrangement": row.id, "case": row.case, "office": row.office, "until_ms": row.until_ms, "basis": "opening_accepted"}): return false
	if not str(row.visit_action).is_empty():
		var native: Dictionary = sim.synchronize_actors()[row.guard].active
		if native.get("id") != row.visit_action or native.get("action") != domain.definitions.watch_action or native.get("destination") != case_row.return_place: return false
	if row.status == "withdrawn":
		var ended: Dictionary = sim.social._event_by_id.get(str(row.end_event), {})
		if ended.get("actor") not in [row.guard, row.issuer] or ended.get("target") not in [row.guard, row.issuer] or ended.get("actor") == ended.get("target") or not _event(domain, row, str(row.end_event), "source_care_ended", str(ended.actor), str(ended.target), int(row.ended_ms), {"arrangement": row.id, "status": "withdrawn"}): return false
	return true


static func _explanation(entry: Dictionary, domain: RefCounted) -> bool:
	var row: Dictionary = domain.arrangements[entry.arrangement]
	var sim: VillageSimulation = domain.world.regions[row.region]
	if not sim.has_actor(entry.actor): return false
	var claim: Dictionary = sim.social._event_by_id.get(str(entry.claim_event), {})
	var details: Dictionary = claim.get("details", {}).get("participants", {})
	var original_source: String = str(details.get("source_job", ""))
	var text: String = str(domain.definitions.labels.unauthenticated) if entry.source_event == "" else "我记得管事签过这次借源；所述用途为" + str(entry.target) + "，最迟开始时刻为" + str(int(entry.until_ms)) + "。"
	if not _event(domain, row, str(entry.claim_event), "source_care_explained", str(entry.actor), str(entry.receiver), int(entry.at_ms), {"explanation": entry.id, "arrangement": row.id, "basis": entry.basis, "source_event": entry.source_event, "source_job": original_source, "decision": entry.decision, "accepted": entry.accepted, "until_ms": entry.until_ms, "target": entry.target, "text": text}): return false
	var decision: Dictionary = {}
	for saved: Dictionary in sim.social.requests.values():
		if saved.id == entry.decision: decision = saved
	if decision.is_empty() or decision.requester != entry.actor or decision.responder != entry.receiver or decision.task != "source_care:explain:" + str(row.id) or decision.tick != floori(float(entry.at_ms) / 60000.0) or not Shape.same_record(decision.context.get("terms"), {"arrangement": row.id, "basis": entry.basis, "source_event": entry.source_event, "source_job": original_source}) or SnapshotValues.normalized(decision.policy) != SnapshotValues.normalized(sim.social._normalized_policy(domain.definitions.policy)) or entry.accepted != (decision.status == "accepted" and int(entry.at_ms) < int(entry.until_ms)): return false
	if entry.source_event != "":
		var note: Dictionary = domain.world.site_affairs.notes.get(entry.basis, {})
		if note.get("actor") != entry.actor or note.get("case") != row.case or note.get("issue_event") != entry.source_event or int(note.get("issued_ms", SimInventory.MAX_COUNT)) > int(entry.at_ms): return false
		var spoken: Dictionary = sim.social.knowledge[entry.actor].get(str(entry.source_event), {})
		var heard: Dictionary = sim.social.knowledge[entry.receiver].get(str(entry.source_event), {})
		var known: Dictionary = spoken.get("details", {})
		if spoken.is_empty() or heard.is_empty() or known.get("start_until_ms") != entry.until_ms or domain.world.site_affairs.definitions.offers.get(known.get("offer", ""), {}).get("target") != entry.target: return false
		# The original social schema proves the attributed chain. A receiver
		# who already heard this event from someone else keeps that older source;
		# explaining it again must not overwrite the valid existing memory.
		if SnapshotValues.normalized(heard.get("details")) != SnapshotValues.normalized(known): return false
	var job: Dictionary = domain._source_job(str(entry.source_job))
	if entry.source_job != "" and (job.is_empty() or job.get("actor") != entry.actor or not domain._source_matches(row, job)): return false
	if entry.binding_event == "":
		if original_source != entry.source_job: return false
		if not job.is_empty() and (int(job.started_ms) > int(entry.at_ms) or int(job.get("finished_ms", SimInventory.MAX_COUNT)) <= int(entry.at_ms)): return false
	else:
		if original_source != "" or entry.source_job == "" or not bool(entry.accepted): return false
		var bound: Dictionary = sim.social._event_by_id.get(str(entry.binding_event), {})
		var observation: Dictionary = bound.get("details", {}).get("participants", {})
		if not Shape.keys(observation, ["explanation", "source_job", "observer_position", "position", "level", "at_ms"]) or observation.explanation != entry.id or observation.source_job != entry.source_job or not Shape.count(observation.at_ms, maxi(int(entry.at_ms), int(job.started_ms)), mini(int(domain.world.elapsed_ms), int(job.get("finished_ms", SimInventory.MAX_COUNT)) - 1)) or not _source_observation(observation, job, domain) or not _event(domain, row, str(entry.binding_event), "source_care_basis_applied", str(row.guard), "", int(observation.at_ms), {"explanation": entry.id, "source_job": entry.source_job, "observer_position": observation.observer_position, "position": observation.position, "level": observation.level}): return false
	return true


static func _warning(warning: Dictionary, domain: RefCounted) -> bool:
	var row: Dictionary = domain.arrangements[warning.arrangement]
	var sim: VillageSimulation = domain.world.regions[row.region]
	var job: Dictionary = domain._source_job(str(warning.source_job))
	if not sim.has_actor(warning.actor) or job.is_empty() or job.get("actor") != warning.actor or not domain._source_matches(row, job) or int(job.started_ms) > int(warning.observed_ms) or int(job.get("finished_ms", SimInventory.MAX_COUNT)) <= int(warning.observed_ms): return false
	if not _source_observation(warning, job, domain): return false
	if not _event(domain, row, str(warning.event), "source_care_warned", str(row.guard), str(warning.actor), int(warning.started_ms), {"warning": warning.id, "arrangement": row.id, "source_job": job.id, "observer_position": warning.observer_position, "position": warning.position, "level": warning.level, "due_ms": warning.due_ms, "text": domain.definitions.labels.warning}): return false
	if warning.status == "active":
		if job.has("result"): return false
	elif warning.status == "resolved":
		var entry: Dictionary = domain.explanations.get(warning.explanation, {})
		if entry.get("arrangement") != row.id or entry.get("actor") != warning.actor or not bool(entry.get("accepted", false)) or entry.get("source_job") not in ["", warning.source_job] or int(entry.get("at_ms", -1)) != int(warning.ended_ms): return false
	elif warning.reason == "source_ended":
		if not job.has("result") or job.get("finished_ms") != warning.ended_ms: return false
	if warning.end_event != "" and not _event(domain, row, str(warning.end_event), "source_care_warning_ended", str(row.guard), str(warning.actor), int(warning.ended_ms), {"warning": warning.id, "status": warning.status, "reason": warning.reason, "explanation": warning.explanation, "conflict": warning.conflict}): return false
	if warning.status == "escalated":
		var encounter: Dictionary = domain.world.conflicts.conflicts.get(warning.conflict, {})
		if encounter.get("cause") != {"domain": "source_care", "id": warning.id} or encounter.get("initiator") != row.guard or encounter.get("defender") != warning.actor or encounter.get("started_ms") != warning.ended_ms or job.get("result") != "cancelled" or job.get("finished_ms") != warning.ended_ms or int(job.get("output", -1)) != 0: return false
	return true


static func _observation(data: Dictionary, domain: RefCounted) -> bool:
	if not Shape.position_valid(data.get("observer_position")) or not Shape.position_valid(data.get("position")) or not Shape.count(data.get("level"), 0, 3): return false
	var from: Vector2 = _point(data.observer_position)
	var to: Vector2 = _point(data.position)
	if from.distance_to(to) > float(domain.definitions.interaction_px) + 0.001: return false
	if domain.world.get("map_data") != null and (Space.level(domain.world, from) != int(data.level) or Space.level(domain.world, to) != int(data.level)): return false
	return true


static func _source_observation(data: Dictionary, job: Dictionary, domain: RefCounted) -> bool:
	if not _observation(data, domain) or data.position != job.get("position"): return false
	var source: Vector2 = TileGrid.cell_to_world(domain.world.spirit_sources.source_cell(str(job.source)))
	if _point(data.observer_position).distance_to(source) > float(domain.definitions.interaction_px) + 0.001: return false
	return domain.world.get("map_data") == null or Space.level(domain.world, source) == int(data.level)


static func _event(domain: RefCounted, row: Dictionary, id: String, kind: String, actor: String, target: String, at_ms: int, details: Dictionary) -> bool:
	var sim: VillageSimulation = domain.world.regions[row.region]
	var event: Dictionary = sim.social._event_by_id.get(id, {})
	var payload: Dictionary = details.duplicate(true)
	payload["at_ms"] = at_ms
	return event.get("kind") == kind and event.get("actor") == actor and event.get("target") == target and event.get("tick") == floori(float(at_ms) / 60000.0) and event.get("witnesses") == [] and SnapshotValues.normalized(event.get("details")) == SnapshotValues.normalized({"participants": payload}) and sim.social.knowledge.get(actor, {}).get(id, {}).get("direct") == true and (target == "" or sim.social.knowledge.get(target, {}).get(id, {}).get("direct") == true)


static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
