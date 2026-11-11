class_name SimSiteAffairs
extends RefCounted
## Specific institutional promises reference original bodies, service work and
## source receipts. A return claim never proves who actually put an object down.

const VERSION: int = 1
const NEVER: int = 0x3fffffffffffffff
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const Schema = preload("res://scripts/sim/site_affair_schema.gd")
var definitions: Dictionary = {}
var cases: Dictionary = {}
var announcements: Dictionary = {}
var notes: Dictionary = {}
var checks: Dictionary = {}
var next_note_id: int = 1
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref() if _owner != null else null


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "max_notes", "max_checks", "max_announcements", "deadline_ms", "loan_minutes", "inspect_minutes", "register_minutes", "interaction_px", "offers", "labels", "policy"]) or data.version != 1:
		return false
	for field: String in ["max_notes", "max_checks", "max_announcements"]:
		if not Shape.count(data[field], 1, 4096): return false
	if not Shape.count(data.deadline_ms, 60000, 86400000) or not SimSnapshotSchema._range(data.interaction_px, 1, 1024):
		return false
	for field: String in ["loan_minutes", "inspect_minutes", "register_minutes"]:
		if not Shape.count(data[field], 1, 60): return false
	if not data.policy is Dictionary or SimSocialMemory.new()._normalized_policy(data.policy).is_empty() or not data.offers is Dictionary or data.offers.is_empty():
		return false
	for id: Variant in data.offers:
		var row: Variant = data.offers[id]
		if not SimInventory._nonempty(id) or not Shape.keys(row, ["label", "case", "target"]) or not SimInventory._nonempty(row.label) or not SimInventory._nonempty(row.case) or row.target not in ["body", "stone"]:
			return false
	if not Shape.keys(data.labels, ["inquiry", "loan", "inspect", "register", "claim", "registered"]): return false
	for label: Variant in data.labels.values():
		if not SimInventory._nonempty(label): return false
	return true


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules): return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func bind_world(authority: RefCounted) -> void:
	_owner = weakref(authority)


func spawn_opening(scenario: Dictionary) -> bool:
	if not cases.is_empty() or not notes.is_empty() or not checks.is_empty() or not announcements.is_empty() or not Shape.keys(scenario, ["version", "cases"]) or scenario.version != 1 or not scenario.cases is Array:
		return false
	var candidate: Dictionary = empty_state()
	for raw: Variant in scenario.cases:
		if not Shape.keys(raw, Schema.CASE_OPENING) or not SimInventory._nonempty(raw.id) or candidate.cases.has(raw.id): return false
		var row: Dictionary = raw.duplicate(true)
		row["activated_ms"] = int(world.elapsed_ms)
		if not world.regions.has(row.region): return false
		var sim: VillageSimulation = world.regions[row.region]
		row["carrier"] = str(sim.places.get(row.record_place, {}).get("workspace", {}).get("fixtures", {}).get("register", {}).get("id", ""))
		candidate.cases[row.id] = row
	if not Schema.validate(candidate, self): return false
	var previous: Dictionary = cases
	cases = candidate.cases
	if not Schema.case_references(self):
		cases = previous
		return false
	return true


func inquiry_cases(actor: String, issuer: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in cases:
		if _talk(actor, issuer, cases[id]) and _authority(issuer, cases[id], true).is_empty():
			result.append({"id": id, "label": str(cases[id].label)})
	return result


func known_cases(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in cases:
		if _known(actor, id): result.append({"id": id, "label": str(cases[id].label)})
	return result


func offers_for(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in definitions.offers:
		if _known(actor, str(definitions.offers[id].case)):
			result.append({"id": id, "label": str(definitions.offers[id].label)})
	return result


func notes_for(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for note: Dictionary in notes.values():
		if note.actor == actor and (note.closed_ms == -1 or not _knows_event(actor, cases[note.case], str(note.closure_event))):
			result.append({"id": str(note.id), "label": str(definitions.offers[note.offer].label) + " · 公器待验还"})
	return result


func announce(actor: String, issuer: String, case_id: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms or not cases.has(case_id): return _reply(false, "unavailable", "眼下没有可当面说明的公源安排。")
	var row: Dictionary = cases[case_id]
	if not _talk(actor, issuer, row): return _reply(false, "unheard", "先走到能当面说清此事的管事身边。")
	var reason: String = _authority(issuer, row, true)
	if not reason.is_empty(): return _reply(false, "unavailable", reason)
	for item: Dictionary in announcements.values():
		if item.actor == actor and item.case == case_id:
			return _reply(true, "completed", _announcement_line(row), str(item.event), _process(str(item.event), issuer))
	if announcements.size() >= int(definitions.max_announcements): return _reply(false, "unavailable", "已有说明记录已满，暂不能另记。")
	var event: String = _record(row, "site_announced", issuer, actor, {"case": case_id, "source": row.source, "object": row.object, "text": _announcement_line(row)})
	announcements[event] = {"case": case_id, "actor": actor, "issuer": issuer, "event": event, "at_ms": int(world.elapsed_ms)}
	return _reply(true, "completed", _announcement_line(row), event, _process(event, issuer))


func request_loan(actor: String, issuer: String, offer: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms or not definitions.offers.has(offer): return _reply(false, "unavailable", "眼下没有可签的这项借用。")
	var case_id: String = str(definitions.offers[offer].case)
	if not cases.has(case_id) or not _known(actor, case_id): return _reply(false, "unheard", "先当面问清这处公源的安排。")
	var row: Dictionary = cases[case_id]
	if not _talk(actor, issuer, row): return _reply(false, "unheard", "先当面向有权管事说明用途。")
	for job: Dictionary in world.services.jobs.values():
		if job.kind == "site_loan" and job.actor == actor and job.status == "active":
			if job.options.offer == offer and job.options.issuer == issuer: return _reply(true, "pending", "原借用仍在办理，重复请求不会多签。", str(job.id), _process(str(job.id), str(job.options.issuer)))
			return _reply(false, "unavailable", "本人已有另一笔在途借用，先处理原办理。")
	var reason: String = _loan_readiness(actor, issuer, row)
	if not reason.is_empty(): return _reply(false, "unavailable", reason)
	var decision: Dictionary = _decide(actor, issuer, row, "loan", offer)
	if decision.get("status") != "accepted": return _reply(false, "refused", "管事没有答应这次借用；还须顾及本人处境与已有安排。")
	var options: Dictionary = {"case": case_id, "offer": offer, "issuer": issuer, "office": row.office, "decision": decision.id}
	var reply: Dictionary = world.services.begin(actor, str(row.region), "site_loan", options)
	return _service_reply(reply, issuer)


func request_return(actor: String, issuer: String, note_id: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms or not notes.has(note_id) or notes[note_id].actor != actor: return _reply(false, "unavailable", "没有本人可提出验还的借用。")
	var note: Dictionary = notes[note_id]
	var row: Dictionary = cases[note.case]
	if not _talk(actor, issuer, row): return _reply(false, "unheard", "需要当面向现任管事提出验还。")
	if note.closed_ms != -1:
		if _knows_event(issuer, row, str(note.closure_event)):
			world.regions[row.region].social.learn(actor, str(note.closure_event), issuer)
			return _reply(true, "completed", str(definitions.labels.registered), note_id, _process(note_id, str(note.issuer)))
		return _reply(false, "unconfirmed", "对方尚不知道这次验还的登记结果。", note_id, _process(note_id, str(note.issuer)))
	for check: Dictionary in checks.values():
		if check.note == note_id and check.status == "active": return _reply(true, "pending", "对方已受理这次验还，仍需真实往返。", str(check.job), _process(str(check.job), str(check.issuer)))
	if not str(note.bound).is_empty(): return _reply(false, "unavailable", "原引息仍在进行，先完成或停下再谈验还。")
	var reason: String = _authority(issuer, row, true)
	if not reason.is_empty(): return _reply(false, "unavailable", reason)
	if checks.size() >= int(definitions.max_checks): return _reply(false, "unavailable", "已有核验记录已满，暂不能受理。")
	var decision: Dictionary = _decide(actor, issuer, row, "return", note_id)
	var claim: String = _record(row, "site_return_claimed", actor, issuer, {"case": row.id, "note": note_id, "text": definitions.labels.claim})
	if decision.get("status") != "accepted": return _reply(false, "refused", "对方听到了你的归还说法，但眼下没有答应出门核验。")
	var options: Dictionary = {"note": note_id, "requester": actor, "issuer": issuer, "office": row.office, "claim_event": claim, "decision": decision.id}
	var reply: Dictionary = world.services.begin(issuer, str(row.region), "site_return", options)
	return _service_reply(reply, issuer)


func service_spec(kind: String, region: String, options: Dictionary, stage: String = "service") -> Dictionary:
	var row: Dictionary = {}
	var label: String = ""
	var place: String = ""
	var minutes: int = 0
	if kind == "site_loan":
		if stage != "service" or not Shape.keys(options, ["case", "offer", "issuer", "office", "decision"]) or not cases.has(options.case) or not definitions.offers.has(options.offer): return {}
		row = cases[options.case]
		if definitions.offers[options.offer].case != options.case: return {}
		label = str(definitions.labels.loan)
		place = str(row.record_place)
		minutes = int(definitions.loan_minutes)
	elif kind == "site_return":
		if stage not in ["inspect", "register"] or not Shape.keys(options, ["note", "requester", "issuer", "office", "claim_event", "decision"]) or not notes.has(options.note): return {}
		var note: Dictionary = notes[options.note]
		if options.requester != note.actor: return {}
		row = cases[note.case]
		label = str(definitions.labels[stage])
		place = str(row.return_place if stage == "inspect" else row.record_place)
		minutes = int(definitions.inspect_minutes if stage == "inspect" else definitions.register_minutes)
	else: return {}
	if region != row.region or options.office != row.office or not _person(str(options.issuer), region) or not SimInventory._nonempty(options.decision): return {}
	return {"ok": true, "reason": "ready", "line": label, "place": place, "minutes": minutes, "label": label, "options": options.duplicate(true)}


func prepare_service(actor: String, region: String, kind: String, options: Dictionary) -> Dictionary:
	if world.elapsed_ms != world.target_ms: return {"ok": false, "reason": "unavailable", "line": "世界事务仍在接续，先等到眼下再办此事。"}
	var stage: String = "inspect" if kind == "site_return" else "service"
	var spec: Dictionary = service_spec(kind, region, options, stage)
	if spec.is_empty(): return {"ok": false, "reason": "invalid_site_terms", "line": "公源事项条款与原安排不符。"}
	var row: Dictionary = cases[options.case] if kind == "site_loan" else cases[notes[options.note].case]
	var requester: String = actor if kind == "site_loan" else str(options.requester)
	if (kind == "site_return" and actor != options.issuer) or not _talk(requester, str(options.issuer), row): return {"ok": false, "reason": "unheard", "line": "当事人尚未当面说清。"}
	var reason: String = _loan_readiness(actor, str(options.issuer), row) if kind == "site_loan" else _authority(str(options.issuer), row, true)
	if not reason.is_empty(): return {"ok": false, "reason": "unavailable", "line": reason}
	if kind == "site_loan" and not _known(actor, str(row.id)): return {"ok": false, "reason": "unknown_case", "line": "先实际问清这处公源安排。"}
	if kind == "site_return":
		var note: Dictionary = notes[options.note]
		if note.closed_ms != -1 or not str(note.bound).is_empty() or _checking(str(note.id)) or checks.size() >= int(definitions.max_checks): return {"ok": false, "reason": "unavailable", "line": "原借用正在用源、核验或已经结清，不能另开一笔。"}
		if not _claim_valid(row, options, int(world.elapsed_ms)): return {"ok": false, "reason": "missing_claim", "line": "没有本次当面具名说明归还的依据。"}
	if not _decision_valid(row, str(options.decision), requester, str(options.issuer), "loan" if kind == "site_loan" else "return", str(options.offer) if kind == "site_loan" else str(options.note)): return {"ok": false, "reason": "no_agreement", "line": "没有本次当面同意的依据。"}
	return spec


func service_started(job: Dictionary) -> void:
	if job.kind != "site_return" or checks.has(job.id) or world.services == null or world.services.active_jobs.get(job.get("actor", "")) != job.get("id") or not world.services.jobs.has(job.id): return
	var origin: String = ""
	var observation: Dictionary = {}
	for id: String in _sorted(checks):
		var prior: Dictionary = checks[id]
		if prior.note == job.options.note and prior.issuer == job.actor and prior.status != "active" and prior.registered_ms == -1 and not prior.observation.is_empty() and _observation_after_use(str(prior.note), int(prior.observation.at_ms)):
			origin = id
			observation = prior.observation.duplicate(true)
	checks[job.id] = {"job": job.id, "note": job.options.note, "requester": job.options.requester, "issuer": job.actor, "office": job.options.office, "claim_event": job.options.claim_event, "decision": job.options.decision, "requested_ms": int(job.started_ms), "origin_check": origin, "observation": observation, "registered_ms": -1, "register_event": "", "finished_ms": -1, "status": "active"}


func settle_service(job: Dictionary) -> Dictionary:
	if not _service_due(job): return {"ok": false, "line": "原办理尚未真实到达并完成工时，不能提前记账。", "next_stage": ""}
	if job.kind == "site_loan": return _issue(job)
	if job.kind != "site_return" or not checks.has(job.id): return {"ok": false, "line": "核验事项不存在。", "next_stage": ""}
	var check: Dictionary = checks[job.id]
	var note: Dictionary = notes[check.note]
	var row: Dictionary = cases[note.case]
	var reason: String = _authority(str(check.issuer), row, job.stage == "register", str(job.id))
	if not reason.is_empty(): return {"ok": false, "line": reason, "next_stage": ""}
	if job.stage == "inspect":
		if not check.observation.is_empty(): return {"ok": true, "line": "保留原亲见的复位事实，继续回桌登记。", "next_stage": "register"}
		var item: Dictionary = world.artifacts.objects[row.object]
		var point: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(world.regions[row.region].places[row.return_place].cell))
		if item.region != row.region or item.container != row.return_place or not _sees(str(check.issuer), point) or int(item.damage) >= int(world.artifacts.definitions.types[item.definition].damage_max):
			return {"ok": false, "line": "到场未能确认同一公器完好复位，尚不能结清。", "next_stage": ""}
		var observer: Vector2 = SimRouteTravel.point(world.regions[row.region].synchronize_actor(check.issuer))
		var observed: Dictionary = {"at_ms": int(world.elapsed_ms), "observer_position": _point(observer), "position": _point(point), "level": Space.level(world, observer), "object": row.object, "container": row.return_place}
		var event: String = _record(row, "site_return_observed", str(check.issuer), "", {"case": row.id, "note": note.id, "job": job.id, "observation": observed.duplicate(true)})
		observed["event"] = event
		check.observation = observed
		return {"ok": true, "line": "已亲见公器复位；还须回桌前登记，未证明是谁亲手放回。", "next_stage": "register"}
	if job.stage != "register" or check.observation.is_empty() or note.closed_ms != -1:
		return {"ok": false, "line": "没有本次可登记的现场观察。", "next_stage": ""}
	var event: String = _record(row, "site_return_registered", str(check.issuer), "", {"case": row.id, "note": note.id, "job": job.id, "claim": check.claim_event, "observation": check.observation.event, "text": definitions.labels.registered})
	check.registered_ms = int(world.elapsed_ms)
	check.register_event = event
	note.closed_ms = int(world.elapsed_ms)
	note.closure_job = job.id
	note.closure_event = event
	return {"ok": true, "line": str(definitions.labels.registered), "next_stage": ""}


func service_finished(job: Dictionary) -> void:
	if job.kind != "site_return" or not checks.has(job.id) or checks[job.id].status != "active" or world.services == null or not world.services.jobs.has(job.id) or SnapshotValues.normalized(world.services.jobs[job.id]) != SnapshotValues.normalized(job) or job.status not in ["completed", "failed", "cancelled"]: return
	checks[job.id].status = str(job.status)
	checks[job.id].finished_ms = int(world.elapsed_ms)


func source_started(job: Dictionary) -> void:
	if not world.spirit_sources.active.has(job.get("actor", "")) or SnapshotValues.normalized(world.spirit_sources.active[job.actor]) != SnapshotValues.normalized(job): return
	for id: String in _sorted(notes):
		var note: Dictionary = notes[id]
		var row: Dictionary = cases[note.case]
		if note.actor != job.actor or row.source != job.source or row.object != job.object or note.target != job.target or note.closed_ms != -1 or not str(note.used).is_empty() or not str(note.bound).is_empty() or _checking(id): continue
		if int(job.started_ms) < int(note.issued_ms) or int(job.started_ms) >= int(note.start_until_ms): continue
		note.bound = job.id
		note.attempts.append(str(job.id))
		return


func source_finished(record: Dictionary) -> void:
	if not world.spirit_sources.records.has(record.get("id", "")) or SnapshotValues.normalized(world.spirit_sources.records[record.id]) != SnapshotValues.normalized(record): return
	for note: Dictionary in notes.values():
		if note.bound != record.id: continue
		note.bound = ""
		if record.result == "success": note.used = record.id
		return


func pending(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world.services == null: return result
	for job: Dictionary in world.services.jobs.values():
		if job.kind == "site_loan" and job.actor == actor and job.status == "active": result.append(_process(str(job.id), str(job.options.issuer)))
	for note: Dictionary in notes.values():
		if note.actor == actor and (note.closed_ms == -1 or not _knows_event(actor, cases[note.case], str(note.closure_event))): result.append(_process(str(note.id), str(note.issuer)))
	for check: Dictionary in checks.values():
		if check.requester == actor and check.status == "active": result.append(_process(str(check.job), str(check.issuer)))
	return result


func observe(actor: String, process: Dictionary) -> Dictionary:
	if not Shape.keys(process, ["domain", "id", "performer"]) or process.domain != "site_affairs": return _reply(false, "unconfirmed", "没有可确认的公源事项。")
	var id: String = str(process.id)
	if announcements.has(id):
		var entry: Dictionary = announcements[id]
		if entry.actor == actor and process.performer == _subject(str(entry.issuer)): return _reply(true, "completed", _announcement_line(cases[entry.case]), id, process)
	if notes.has(id):
		var note: Dictionary = notes[id]
		if note.actor != actor or process.performer != _subject(str(note.issuer)): return _reply(false, "unconfirmed", "这不是本人获签的借用。")
		var row: Dictionary = cases[note.case]
		if note.closed_ms != -1 and _knows_event(actor, row, str(note.closure_event)): return _reply(true, "completed", str(definitions.labels.registered), id, process)
		var line: String = "记得一次具名借用；实际引息仍需到场、原温石和源息。"
		if not str(note.used).is_empty(): line = "本次借源已经实际完成，公器归位尚待当面核验。"
		elif world.elapsed_ms >= int(note.start_until_ms): line = "已过最迟开工时刻；不能再凭此签注开始，公器仍可验还。"
		return _reply(true, "pending", line, id, process)
	if checks.has(id):
		var check: Dictionary = checks[id]
		if check.requester != actor or process.performer != _subject(str(check.issuer)): return _reply(false, "unconfirmed", "这不是本人提出的验还。")
		var row: Dictionary = cases[notes[check.note].case]
		if check.registered_ms != -1 and _knows_event(actor, row, str(check.register_event)): return _reply(true, "completed", str(definitions.labels.registered), id, process)
		return _reply(true, "pending", "记得对方已经受理，尚未当面得到核验结果。", id, process)
	if world.services != null and world.services.jobs.has(id):
		var job: Dictionary = world.services.jobs[id]
		if job.kind == "site_loan" and job.actor == actor and process.performer == _subject(str(job.options.issuer)):
			for note: Dictionary in notes.values():
				if note.issue_job == id: return _reply(true, "completed", "管事已签一次借用；有证不保证眼下有源息。", str(note.id), _process(str(note.id), str(note.issuer)))
			return _reply(job.status == "active", "pending" if job.status == "active" else "cancelled", "仍在实际办理。" if job.status == "active" else str(job.outcome), id, process)
	return _reply(false, "unconfirmed", "本人没有这项可核对的依据。")


func next_boundary_ms() -> int:
	return NEVER


func settle_at_ms(_now: int) -> void:
	pass


func cross_valid() -> bool:
	return Schema.cross_valid(self)


func _issue(job: Dictionary) -> Dictionary:
	var row: Dictionary = cases[job.options.case]
	var reason: String = _loan_readiness(str(job.actor), str(job.options.issuer), row, str(job.id))
	if not reason.is_empty() or not _talk(str(job.actor), str(job.options.issuer), row): return {"ok": false, "line": reason if not reason.is_empty() else "已不能当面完成这次签发。", "next_stage": ""}
	if world.elapsed_ms > SimInventory.MAX_COUNT - int(definitions.deadline_ms): return {"ok": false, "line": "无法安排这次借用期限。", "next_stage": ""}
	var id: String = "site:note:%d" % next_note_id
	var note: Dictionary = {"id": id, "case": row.id, "offer": job.options.offer, "actor": job.actor, "issuer": job.options.issuer, "office": row.office, "carrier": row.carrier, "target": definitions.offers[job.options.offer].target, "issued_ms": int(world.elapsed_ms), "start_until_ms": int(world.elapsed_ms) + int(definitions.deadline_ms), "issue_job": job.id, "decision": job.options.decision, "issue_event": "", "attempts": [], "bound": "", "used": "", "closed_ms": -1, "closure_job": "", "closure_event": ""}
	note.issue_event = _record(row, "site_loan_issued", str(note.issuer), str(note.actor), {"case": row.id, "note": id, "offer": note.offer, "job": job.id, "office": note.office, "carrier": note.carrier, "start_until_ms": note.start_until_ms})
	notes[id] = note
	next_note_id += 1
	return {"ok": true, "line": "已签下一次借源；只许约定用途，源息与温石仍须真实可用。", "next_stage": ""}


func _loan_readiness(actor: String, issuer: String, row: Dictionary, own_job: String = "") -> String:
	var reason: String = _authority(issuer, row, true)
	if not reason.is_empty(): return reason
	if notes.size() >= int(definitions.max_notes): return "借用记录已满，暂不签新约。"
	if not _person(actor, str(row.region)): return "首版只办理当地本人的这处借用。"
	if not _body_available(actor, own_job): return "先处理手头事务，再申请借用。"
	for note: Dictionary in notes.values():
		if note.case == row.id and note.actor == actor and note.closed_ms == -1: return "本人尚有未结清的借用，先处理原公器。"
	var item: Dictionary = world.artifacts.objects.get(row.object, {})
	if item.get("region") != row.region or item.get("container") != "actor:" + actor: return "先实际持有这块公用温石，当面说明用途。"
	if not bool(world.artifacts.describe(actor, str(row.object)).get("method", false)): return "先亲自学会原循纹手法，签注不会授予本领。"
	return ""


func _authority(issuer: String, row: Dictionary, desk: bool, own_job: String = "") -> String:
	if not _person(issuer, str(row.region)): return "当地没有能签此事的在场人物。"
	var sim: VillageSimulation = world.regions[row.region]
	var office: Dictionary = sim.institutions.institutions.get(row.institution, {}).get("offices", {}).get(row.office, {})
	if office.get("holder") != issuer or not office.get("permissions", []).has(row.permission): return "对方不是此处当前有权的管事，交情不能代替任职。"
	if not _body_available(issuer, own_job): return "管事正忙于别事，尚不能分身办理。"
	if desk:
		var context: Dictionary = {"services": world.services, "id": own_job} if not own_job.is_empty() else {}
		var assessment: Dictionary = SimWorkplaces.assessment(sim, issuer, str(row.permission), context)
		if not bool(assessment.ok): return str(assessment.line)
	return ""


func _body_available(actor: String, own_job: String = "") -> bool:
	var home: String = world.artifacts.actor_home(actor)
	if home.is_empty(): return false
	var person: Dictionary = world.regions[home].synchronize_actor(actor)
	if not bool(person.alive) or not person.active.is_empty(): return false
	for channel: String in ["communication", "action", "motion"]:
		if not world.actor_controls(actor, channel): return false
	if own_job.is_empty(): return not world.body_action_owns(actor)
	return world.services != null and world.services.active_jobs.get(actor) == own_job and world.services.jobs.has(own_job) and world.services.jobs[own_job].actor == actor and not world.body_action_owns(actor, &"services")


func _person(actor: String, region: String) -> bool:
	return world.regions.has(region) and world.regions[region].has_actor(actor)


func _talk(actor: String, issuer: String, row: Dictionary) -> bool:
	if actor == issuer or not _person(actor, str(row.region)) or not _person(issuer, str(row.region)): return false
	for id: String in [actor, issuer]:
		if not world.actor_controls(id, "communication"): return false
	var sim: VillageSimulation = world.regions[row.region]
	var point: Vector2 = SimRouteTravel.point(sim.synchronize_actor(actor))
	var other: Vector2 = SimRouteTravel.point(sim.synchronize_actor(issuer))
	return point.distance_to(other) <= float(world._content.interaction_requests.communication_cells) * TileGrid.TILE_SIZE and Space.level(world, point) == Space.level(world, other) and Space.clear_segment(world, point, other, Space.level(world, point))


func _sees(actor: String, point: Vector2) -> bool:
	var home: String = world.artifacts.actor_home(actor)
	if home.is_empty(): return false
	var from: Vector2 = SimRouteTravel.point(world.regions[home].synchronize_actor(actor))
	return from.distance_to(point) <= float(definitions.interaction_px) and Space.level(world, from) == Space.level(world, point) and Space.clear_segment(world, from, point, Space.level(world, from))


func _service_due(job: Dictionary) -> bool:
	if world.services == null or not world.services.jobs.has(job.get("id", "")) or world.services.active_jobs.get(job.get("actor", "")) != job.get("id") or job.get("status") != "active" or job.get("phase") != "work" or not job.get("path") is Array or not job.path.is_empty() or not Shape.count(job.get("due_ms"), int(world.elapsed_ms), int(world.elapsed_ms)): return false
	var actual: Dictionary = world.services.jobs[job.id]
	if SnapshotValues.normalized(actual) != SnapshotValues.normalized(job): return false
	var spec: Dictionary = service_spec(str(job.kind), str(job.region), job.options, str(job.stage))
	if spec.is_empty() or SnapshotValues.normalized(spec) != SnapshotValues.normalized(job.spec): return false
	var home: String = world.artifacts.actor_home(str(job.actor))
	return not home.is_empty() and SimRouteTravel.cell(world.regions[home].synchronize_actor(job.actor).cell) == SimRouteTravel.cell(world.regions[job.region].places[spec.place].cell)


func _observation_after_use(note_id: String, at_ms: int, before_ms: int = SimInventory.MAX_COUNT) -> bool:
	for id: String in notes[note_id].attempts:
		var source: Dictionary = world.spirit_sources.records.get(id, {})
		if source.is_empty():
			for active: Dictionary in world.spirit_sources.active.values():
				if active.id == id: source = active
		if source.is_empty(): return false
		if int(source.started_ms) < before_ms and (not source.has("finished_ms") or int(source.finished_ms) > at_ms): return false
	return true


func _known(actor: String, case_id: String) -> bool:
	if not cases.has(case_id): return false
	for entry: Dictionary in announcements.values():
		if entry.case == case_id and entry.actor == actor: return true
	for note: Dictionary in notes.values():
		if note.actor == actor and note.case == case_id: return true
	return false


func _checking(note_id: String) -> bool:
	for check: Dictionary in checks.values():
		if check.note == note_id and check.status == "active": return true
	return false


func _decide(actor: String, issuer: String, row: Dictionary, purpose: String, value: String) -> Dictionary:
	var sim: VillageSimulation = world.regions[row.region]
	var person: Dictionary = sim.synchronize_actor(issuer)
	var context: Dictionary = {"energy": floorf(float(person.energy) / 20.0) / 5.0, "busy": 0.0, "duty": 1.0, "reliability": float(sim.social.relation(issuer, actor).reliability), "affinity": float(sim.social.relation(issuer, actor).affinity), "terms": {"case": row.id, "purpose": purpose, "value": value}}
	return sim.social.evaluate_request(actor, issuer, "site:" + purpose + ":" + str(row.id), context, definitions.policy, sim._rng, sim.tick_index)


func _decision_valid(row: Dictionary, id: String, actor: String, issuer: String, purpose: String, value: String) -> bool:
	for decision: Dictionary in world.regions[row.region].social.requests.values():
		if decision.id == id:
			return decision.requester == actor and decision.responder == issuer and decision.status == "accepted" and decision.task == "site:" + purpose + ":" + str(row.id) and SnapshotValues.normalized(decision.policy) == SnapshotValues.normalized(world.regions[row.region].social._normalized_policy(definitions.policy)) and Shape.same_record(decision.context.get("terms"), {"case": row.id, "purpose": purpose, "value": value})
	return false


func _claim_valid(row: Dictionary, options: Dictionary, at_ms: int) -> bool:
	var event: Dictionary = world.regions[row.region].social.objective_event(str(options.claim_event))
	return event.get("kind") == "site_return_claimed" and event.get("actor") == options.requester and event.get("target") == options.issuer and SnapshotValues.normalized(event.get("details")) == SnapshotValues.normalized({"participants": {"case": row.id, "note": options.note, "text": definitions.labels.claim, "at_ms": at_ms}})


func _record(row: Dictionary, kind: String, actor: String, target: String, details: Dictionary) -> String:
	@warning_ignore("integer_division")
	var tick: int = int(world.elapsed_ms) / 60000
	var payload: Dictionary = details.duplicate(true)
	payload["at_ms"] = int(world.elapsed_ms)
	var witnesses: Array[String] = []
	return world.regions[row.region].social.record(kind, actor, target, {"participants": payload}, witnesses, tick)


func _knows_event(actor: String, row: Dictionary, event: String) -> bool:
	return world.regions[row.region].social.knows(actor, event)


func _announcement_line(row: Dictionary) -> String:
	return str(row.label) + "：借原温石引息归身或温养一次，需当面签注；源息不足仍须等候。公器用后放回灶旁并请人验还。" + str(row.record_note)


func _subject(actor: String) -> String:
	return world.embodiment.subject_for_actor(actor)


func _process(id: String, issuer: String) -> Dictionary:
	return {"domain": "site_affairs", "id": id, "performer": _subject(issuer)}


func _service_reply(reply: Dictionary, issuer: String) -> Dictionary:
	var id: String = str(reply.get("id", ""))
	return _reply(bool(reply.get("ok", false)), "started" if bool(reply.get("ok", false)) else "unavailable", str(reply.get("line", "尚未开始办理。")), id, _process(id, issuer) if not id.is_empty() else {})


static func _reply(ok: bool, code: String, line: String, id: String = "", process: Dictionary = {}) -> Dictionary:
	return {"ok": ok, "code": code, "line": line, "id": id, "process": process}


static func _point(value: Vector2) -> Array:
	return [value.x, value.y]


static func _sorted(value: Dictionary) -> Array:
	var result: Array = value.keys()
	result.sort()
	return result


static func empty_state() -> Dictionary:
	return {"version": VERSION, "cases": {}, "announcements": {}, "notes": {}, "checks": {}, "next_note_id": 1}


func to_dict() -> Dictionary:
	return {"version": VERSION, "cases": cases.duplicate(true), "announcements": announcements.duplicate(true), "notes": notes.duplicate(true), "checks": checks.duplicate(true), "next_note_id": next_note_id}


func restore(data: Dictionary) -> bool:
	if not Schema.validate(data, self): return false
	for key: String in ["cases", "announcements", "notes", "checks"]: set(key, data[key].duplicate(true))
	next_note_id = int(data.next_note_id)
	return true
