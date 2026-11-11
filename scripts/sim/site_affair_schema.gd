extends RefCounted
## Shape checks run before original services/sources exist in the candidate;
## cross_valid checks original evidence only after all owners are restored.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const CASE_OPENING: Array[String] = ["id", "label", "region", "institution", "office", "permission", "source", "object", "return_place", "record_place", "record_scope", "record_note"]
const CASE: Array[String] = ["id", "label", "region", "institution", "office", "permission", "source", "object", "return_place", "record_place", "record_scope", "record_note", "activated_ms", "carrier"]
const ANNOUNCEMENT: Array[String] = ["case", "actor", "issuer", "event", "at_ms"]
const NOTE: Array[String] = ["id", "case", "offer", "actor", "issuer", "office", "carrier", "target", "issued_ms", "start_until_ms", "issue_job", "decision", "issue_event", "attempts", "bound", "used", "closed_ms", "closure_job", "closure_event"]
const CHECK: Array[String] = ["job", "note", "requester", "issuer", "office", "claim_event", "decision", "requested_ms", "origin_check", "observation", "registered_ms", "register_event", "finished_ms", "status"]
const OBSERVATION: Array[String] = ["at_ms", "observer_position", "position", "level", "object", "container", "event"]


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "cases", "announcements", "notes", "checks", "next_note_id"]) or not Shape.count(data.version, 1, 1) or not Shape.count(data.next_note_id, 1, int(domain.definitions.max_notes) + 1): return false
	for field: String in ["cases", "announcements", "notes", "checks"]:
		if not data[field] is Dictionary: return false
	if data.cases.size() > domain.definitions.offers.size() or data.notes.size() != int(data.next_note_id) - 1 or data.checks.size() > int(domain.definitions.max_checks) or data.announcements.size() > int(domain.definitions.max_announcements): return false
	for id: Variant in data.cases:
		var row: Variant = data.cases[id]
		if not SimInventory._nonempty(id) or not Shape.keys(row, CASE) or row.id != id or not Shape.count(row.activated_ms, 0, int(domain.world.elapsed_ms)): return false
		var offered: bool = false
		for offer: Dictionary in domain.definitions.offers.values():
			if offer.case == id: offered = true
		if not offered: return false
		for field: String in CASE_OPENING + ["carrier"]:
			if not SimInventory._nonempty(row[field]): return false
		if not domain.world.regions.has(row.region): return false
		var sim: VillageSimulation = domain.world.regions[row.region]
		var office: Dictionary = sim.institutions.institutions.get(row.institution, {}).get("offices", {}).get(row.office, {})
		if row.record_scope != "source_loan" or row.permission != "authorize" or not office.get("permissions", []).has(row.permission) or not sim.places.has(row.return_place) or not sim.places.has(row.record_place): return false
	for id: Variant in data.announcements:
		var row: Variant = data.announcements[id]
		if not SimInventory._nonempty(id) or not Shape.keys(row, ANNOUNCEMENT) or row.event != id or not data.cases.has(row.case): return false
		var case_row: Dictionary = data.cases[row.case]
		if not _people(domain, case_row, row.actor, row.issuer) or not Shape.count(row.at_ms, int(case_row.activated_ms), int(domain.world.elapsed_ms)): return false
	var open_notes: Dictionary = {}
	for number: int in range(1, int(data.next_note_id)):
		var id: String = "site:note:%d" % number
		var note: Variant = data.notes.get(id)
		if not Shape.keys(note, NOTE) or note.id != id or not data.cases.has(note.case) or not domain.definitions.offers.has(note.offer): return false
		var row: Dictionary = data.cases[note.case]
		var offer: Dictionary = domain.definitions.offers[note.offer]
		if offer.case != note.case or note.target != offer.target or note.office != row.office or note.carrier != row.carrier or not _people(domain, row, note.actor, note.issuer): return false
		if not Shape.count(note.issued_ms, int(row.activated_ms), int(domain.world.elapsed_ms)) or not Shape.count(note.start_until_ms, int(note.issued_ms), SimInventory.MAX_COUNT) or int(note.start_until_ms) - int(note.issued_ms) != int(domain.definitions.deadline_ms): return false
		for key: String in ["issue_job", "decision", "issue_event"]:
			if not SimInventory._nonempty(note[key]): return false
		for key: String in ["bound", "used", "closure_job", "closure_event"]:
			if not note[key] is String: return false
		if not SimEmbodiment._unique_texts(note.attempts) or (not str(note.bound).is_empty() and not note.attempts.has(note.bound)) or (not str(note.used).is_empty() and not note.attempts.has(note.used)): return false
		if not str(note.bound).is_empty() and not str(note.used).is_empty(): return false
		if not Shape.count(note.closed_ms, -1, int(domain.world.elapsed_ms)): return false
		if note.closed_ms == -1:
			if note.closure_job != "" or note.closure_event != "": return false
			var key: String = str(note.case) + ":" + str(note.actor)
			if open_notes.has(key): return false
			open_notes[key] = id
		elif int(note.closed_ms) < int(note.issued_ms) or str(note.closure_job).is_empty() or str(note.closure_event).is_empty() or not str(note.bound).is_empty(): return false
	var active_checks: Dictionary = {}
	for id: Variant in data.checks:
		var check: Variant = data.checks[id]
		if not SimInventory._nonempty(id) or not Shape.keys(check, CHECK) or check.job != id or not data.notes.has(check.note) or check.status not in ["active", "completed", "failed", "cancelled"]: return false
		var note: Dictionary = data.notes[check.note]
		var row: Dictionary = data.cases[note.case]
		if check.requester != note.actor or check.office != row.office or not _people(domain, row, check.requester, check.issuer) or not Shape.count(check.requested_ms, int(note.issued_ms), int(domain.world.elapsed_ms)): return false
		if not SimInventory._nonempty(check.claim_event) or not SimInventory._nonempty(check.decision) or not check.register_event is String or not check.origin_check is String or not check.observation is Dictionary: return false
		if not Shape.count(check.finished_ms, -1, int(domain.world.elapsed_ms)) or not Shape.count(check.registered_ms, -1, int(domain.world.elapsed_ms)): return false
		if check.status == "active":
			if check.finished_ms != -1 or note.closed_ms != -1 or active_checks.has(check.note): return false
			active_checks[check.note] = id
		elif int(check.finished_ms) < int(check.requested_ms): return false
		if not str(check.origin_check).is_empty():
			var origin: Variant = data.checks.get(check.origin_check)
			if not origin is Dictionary or origin.get("note") != check.note or origin.get("issuer") != check.issuer or origin.get("status") not in ["failed", "cancelled"] or not Shape.count(origin.get("finished_ms"), 0, int(check.requested_ms)) or origin.get("registered_ms") != -1 or not origin.get("observation") is Dictionary or origin.observation.is_empty() or not Shape.same_record(origin.observation, check.observation): return false
		elif not check.observation.is_empty() and not _observation(check.observation, check, row, domain): return false
		if check.registered_ms == -1:
			if check.register_event != "" or check.status == "completed": return false
		elif check.observation.is_empty() or int(check.registered_ms) < int(check.observation.at_ms) or check.status != "completed" or check.finished_ms != check.registered_ms or check.register_event == "" or note.closed_ms != check.registered_ms or note.closure_job != id or note.closure_event != check.register_event: return false
	return true


static func case_references(domain: RefCounted) -> bool:
	for row: Dictionary in domain.cases.values():
		if domain.world.spirit_sources == null or not domain.world.spirit_sources.sources.has(row.source) or not domain.world.artifacts.objects.has(row.object): return false
		var source: Dictionary = domain.world.spirit_sources.definitions.sources[row.source]
		var item: Dictionary = domain.world.artifacts.objects[row.object]
		var sim: VillageSimulation = domain.world.regions[row.region]
		var carrier: Dictionary = sim.places[row.record_place].get("workspace", {}).get("fixtures", {}).get("register", {})
		if source.region != row.region or source.place != row.return_place or item.definition != domain.world.spirit_sources.definitions.artifact_type or carrier.get("id") != row.carrier or carrier.get("institution") != row.institution: return false
	return true


static func cross_valid(domain: RefCounted) -> bool:
	if not validate(domain.to_dict(), domain) or not case_references(domain): return false
	var services: RefCounted = domain.world.services
	if services == null: return domain.notes.is_empty() and domain.checks.is_empty() and domain.announcements.is_empty()
	for entry: Dictionary in domain.announcements.values():
		var row: Dictionary = domain.cases[entry.case]
		if not _event(domain, row, str(entry.event), "site_announced", str(entry.issuer), str(entry.actor), int(entry.at_ms), {"case": row.id, "source": row.source, "object": row.object, "text": domain._announcement_line(row)}): return false
	var jobs_used: Dictionary = {}
	var attempts_used: Dictionary = {}
	for note: Dictionary in domain.notes.values():
		var row: Dictionary = domain.cases[note.case]
		var job: Dictionary = services.jobs.get(note.issue_job, {})
		if job.get("kind") != "site_loan" or job.get("actor") != note.actor or job.get("region") != row.region or job.get("status") != "completed" or job.get("stage") != "service" or jobs_used.has(note.issue_job): return false
		var options: Dictionary = {"case": row.id, "offer": note.offer, "issuer": note.issuer, "office": note.office, "decision": note.decision}
		if not Shape.same_record(job.get("options"), options) or int(job.due_ms) != int(note.issued_ms) or not domain._decision_valid(row, str(note.decision), str(note.actor), str(note.issuer), "loan", str(note.offer)) or not _decision_time(domain, row, str(note.decision), int(job.started_ms)): return false
		if not _event(domain, row, str(note.issue_event), "site_loan_issued", str(note.issuer), str(note.actor), int(note.issued_ms), {"case": row.id, "note": note.id, "offer": note.offer, "job": job.id, "office": note.office, "carrier": note.carrier, "start_until_ms": note.start_until_ms}): return false
		jobs_used[note.issue_job] = note.id
		var prior: int = int(note.issued_ms)
		var success: String = ""
		var active: String = ""
		for attempt: String in note.attempts:
			if attempts_used.has(attempt): return false
			var original: Dictionary = _source_job(domain, attempt)
			if original.is_empty() or original.actor != note.actor or original.source != row.source or original.object != row.object or original.target != note.target or int(original.started_ms) < prior or int(original.started_ms) >= int(note.start_until_ms) or not success.is_empty(): return false
			if note.closed_ms != -1 and int(original.started_ms) >= int(note.closed_ms): return false
			prior = int(original.get("finished_ms", original.due_ms))
			if not original.has("result"):
				if not active.is_empty(): return false
				active = attempt
			elif original.result == "success": success = attempt
			attempts_used[attempt] = note.id
		if note.bound != active or note.used != success: return false
	for check: Dictionary in domain.checks.values():
		var note: Dictionary = domain.notes[check.note]
		var row: Dictionary = domain.cases[note.case]
		var job: Dictionary = services.jobs.get(check.job, {})
		if job.get("kind") != "site_return" or job.get("actor") != check.issuer or job.get("region") != row.region or job.get("status") != check.status or job.get("started_ms") != check.requested_ms or job.get("stage") not in ["inspect", "register"]: return false
		var options: Dictionary = {"note": check.note, "requester": check.requester, "issuer": check.issuer, "office": check.office, "claim_event": check.claim_event, "decision": check.decision}
		if not Shape.same_record(job.get("options"), options) or not domain._decision_valid(row, str(check.decision), str(check.requester), str(check.issuer), "return", str(check.note)) or not _decision_time(domain, row, str(check.decision), int(job.started_ms)): return false
		if not _event(domain, row, str(check.claim_event), "site_return_claimed", str(check.requester), str(check.issuer), int(check.requested_ms), {"case": row.id, "note": note.id, "text": domain.definitions.labels.claim}): return false
		if check.status != "active" and floori(float(check.finished_ms) / 60000.0) != int(job.finished_at): return false
		var check_end: int = int(check.finished_ms) if check.finished_ms != -1 else SimInventory.MAX_COUNT
		for attempt: String in note.attempts:
			var original: Dictionary = _source_job(domain, attempt)
			var end: int = int(original.get("finished_ms", original.due_ms))
			if int(original.started_ms) < check_end and int(check.requested_ms) < end: return false
		if job.stage == "register" and check.observation.is_empty(): return false
		if not check.observation.is_empty():
			if not domain._observation_after_use(str(note.id), int(check.observation.at_ms), int(check.requested_ms)): return false
			var observed: Dictionary = check.observation.duplicate(true)
			var event: String = str(observed.event)
			observed.erase("event")
			var observer_job: String = str(job.id)
			var prior_check: Dictionary = check
			var seen: Dictionary = {}
			while not str(prior_check.origin_check).is_empty():
				if seen.has(prior_check.origin_check): return false
				seen[prior_check.origin_check] = true
				prior_check = domain.checks[prior_check.origin_check]
				observer_job = str(prior_check.job)
			if not _event(domain, row, event, "site_return_observed", str(check.issuer), "", int(observed.at_ms), {"case": row.id, "note": note.id, "job": observer_job, "observation": observed}): return false
		if check.registered_ms != -1:
			if job.stage != "register" or int(job.due_ms) != int(check.registered_ms): return false
			if not _event(domain, row, str(check.register_event), "site_return_registered", str(check.issuer), "", int(check.registered_ms), {"case": row.id, "note": note.id, "job": job.id, "claim": check.claim_event, "observation": check.observation.event, "text": domain.definitions.labels.registered}): return false
	for job: Dictionary in services.jobs.values():
		if job.kind == "site_loan" and job.status == "completed" and not jobs_used.has(job.id): return false
		if job.kind == "site_return" and not domain.checks.has(job.id): return false
		if job.kind == "site_loan":
			var row: Dictionary = domain.cases.get(job.options.get("case", ""), {})
			if row.is_empty() or not domain._decision_valid(row, str(job.options.decision), str(job.actor), str(job.options.issuer), "loan", str(job.options.offer)) or not _decision_time(domain, row, str(job.options.decision), int(job.started_ms)): return false
	return _event_coverage(domain) and _source_coverage(domain, attempts_used)


static func _decision_time(domain: RefCounted, row: Dictionary, id: String, started_ms: int) -> bool:
	for decision: Dictionary in domain.world.regions[row.region].social.requests.values():
		if decision.id == id: return Shape.count(decision.tick, floori(float(row.activated_ms) / 60000.0), floori(float(started_ms) / 60000.0))
	return false


static func _event_coverage(domain: RefCounted) -> bool:
	for sim: VillageSimulation in domain.world.regions.values():
		for event: Dictionary in sim.social.events:
			if event.kind == "site_announced" and not domain.announcements.has(event.id): return false
			if event.kind == "site_loan_issued":
				var note: Dictionary = domain.notes.get(event.details.get("participants", {}).get("note", ""), {})
				if note.get("issue_event") != event.id: return false
			if event.kind in ["site_return_observed", "site_return_registered"]:
				var check: Dictionary = domain.checks.get(event.details.get("participants", {}).get("job", ""), {})
				if event.kind == "site_return_observed" and (check.get("origin_check", "") != "" or check.get("observation", {}).get("event") != event.id): return false
				if event.kind == "site_return_registered" and check.get("register_event") != event.id: return false
	return true


static func _source_coverage(domain: RefCounted, used: Dictionary) -> bool:
	# If an original process began while a matching unused note was effective,
	# the synchronous source hook must have preserved its binding. Removing the
	# attempt cannot turn an already consumed note back into a fresh promise.
	var jobs: Array = domain.world.spirit_sources.records.values()
	jobs.append_array(domain.world.spirit_sources.active.values())
	for original: Dictionary in jobs:
		for note: Dictionary in domain.notes.values():
			var row: Dictionary = domain.cases[note.case]
			if original.actor != note.actor or original.source != row.source or original.object != row.object or original.target != note.target: continue
			if int(original.started_ms) < int(note.issued_ms) or int(original.started_ms) >= int(note.start_until_ms) or note.closed_ms != -1 and int(original.started_ms) >= int(note.closed_ms): continue
			var consumed_before: bool = false
			for attempt: String in note.attempts:
				var prior: Dictionary = _source_job(domain, attempt)
				if prior.get("result") == "success" and int(prior.finished_ms) <= int(original.started_ms): consumed_before = true
			var returning: bool = false
			for check: Dictionary in domain.checks.values():
				if check.note == note.id and int(check.requested_ms) <= int(original.started_ms) and (check.finished_ms == -1 or int(original.started_ms) < int(check.finished_ms)): returning = true
			if not consumed_before and not returning and used.get(original.id) != note.id: return false
	return true


static func _observation(observed: Dictionary, check: Dictionary, row: Dictionary, domain: RefCounted) -> bool:
	if not Shape.keys(observed, OBSERVATION) or not Shape.count(observed.at_ms, int(check.requested_ms), int(domain.world.elapsed_ms)) or not Shape.position_valid(observed.observer_position) or not Shape.position_valid(observed.position) or not Shape.count(observed.level, 0, 3) or observed.object != row.object or observed.container != row.return_place or not SimInventory._nonempty(observed.event): return false
	var from: Vector2 = Vector2(float(observed.observer_position[0]), float(observed.observer_position[1]))
	var to: Vector2 = Vector2(float(observed.position[0]), float(observed.position[1]))
	var expected: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(domain.world.regions[row.region].places[row.return_place].cell))
	if not to.is_equal_approx(expected) or from.distance_to(to) > float(domain.definitions.interaction_px) + 0.001: return false
	if domain.world.map_data != null and (Space.level(domain.world, from) != int(observed.level) or Space.level(domain.world, to) != int(observed.level)): return false
	return check.finished_ms == -1 or int(observed.at_ms) <= int(check.finished_ms)


static func _people(domain: RefCounted, row: Dictionary, actor: Variant, issuer: Variant) -> bool:
	return actor is String and issuer is String and actor != issuer and domain._person(actor, str(row.region)) and domain._person(issuer, str(row.region))


static func _event(domain: RefCounted, row: Dictionary, id: String, kind: String, actor: String, target: String, at_ms: int, details: Dictionary) -> bool:
	var social: SimSocialMemory = domain.world.regions[row.region].social
	var event: Dictionary = social.objective_event(id)
	var payload: Dictionary = details.duplicate(true)
	payload["at_ms"] = at_ms
	return event.get("kind") == kind and event.get("actor") == actor and event.get("target") == target and event.get("tick") == floori(float(at_ms) / 60000.0) and SnapshotValues.normalized(event.get("details")) == SnapshotValues.normalized({"participants": payload})


static func _source_job(domain: RefCounted, id: String) -> Dictionary:
	if domain.world.spirit_sources.records.has(id): return domain.world.spirit_sources.records[id]
	for job: Dictionary in domain.world.spirit_sources.active.values():
		if job.id == id: return job
	return {}
