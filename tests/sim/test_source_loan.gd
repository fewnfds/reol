extends RefCounted
## Specific public promises use the original service, source and object owners.

const Support = preload("res://tests/sim/spirit_source_test_support.gd")
const Rooms = preload("res://tests/sim/test_workplaces.gd")
const CASE: String = "hearth_loan"
const STONE: String = "hearth_stone"
const SOURCE: String = "hearth_seam"
const ISSUER: String = "chen_shouzhuo"
var _rooms := Rooms.new()


func run(runner: Object) -> void:
	_explicit_arrangement_and_requests(runner)
	_signature_rechecks_and_repeated_request(runner)
	_original_use_and_actual_return(runner)
	_last_batch_and_cancelled_attempt(runner)
	_deadline_is_a_start_deadline(runner)
	_communication_understanding_and_permission(runner)
	_false_claim_and_third_party_return(runner)
	_observation_survives_later_custody(runner)
	_interrupted_registration_reuses_observation(runner)
	_public_service_rejects_replayed_terms(runner)
	_premature_callbacks_cannot_write_evidence(runner)
	_strict_candidates(runner)
	_fine_sparse_and_inflight_restore(runner)
	print("SCENARIO source loan: explicit local arrangement and finite knowledge, timed signatures, actual last source batch, cancellation/deadline, claims versus observed return, strict candidates and identical saved futures")


func _make(runner: Object, options: Dictionary = {}) -> RegionalSimulation:
	var settings: Dictionary = {"services": true, "known": true, "qi": {"player": 10}}
	settings.merge(options, true)
	var world: RegionalSimulation = Support.make(runner, settings)
	if world == null:
		return null
	world.bind_map_data(Rooms.FlatMap.new())
	var areas: Array = []
	for sim: VillageSimulation in world.regions.values():
		if not SimWorkplaces.enable_opening(sim.config, sim.places, sim.actors, world.map_data, str(sim.config.institution.id)):
			runner.assert_true(false, "source-loan fixture installs actual existing public desks and rooms")
			return null
		areas.append(sim.places)
	for sim: VillageSimulation in world.regions.values():
		_rooms._bind_path(sim, areas)
	world.services.set_navigation(func(from: Vector2i, to: Vector2i) -> Array[Vector2i]: return _rooms._path(areas, from, to),
		func(from: Vector2i, direction: Vector2i) -> bool: return not _rooms._blocked(areas, from + direction))
	runner.assert_true(world.site_affairs.cases.is_empty(), "ordinary small fixture does not infer an arrangement from its source or office")
	if not world.site_affairs.spawn_opening(JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/source_loan.json"))):
		runner.assert_true(false, "source-loan fixture explicitly installs the bounded original-source arrangement")
		return null
	_desk(world)
	return world


func _at(world: RegionalSimulation, actor: String, place: String) -> void:
	var home: String = world.artifacts.actor_home(actor)
	world.regions[home].set_actor_cell(actor, SimRouteTravel.cell(world.regions.home.places[place].cell))
	world.invalidate_region(home)


func _desk(world: RegionalSimulation) -> void:
	_at(world, "player", "records")
	_at(world, ISSUER, "records")


func _intent(world: RegionalSimulation, verb: String, id: String, receiver: String = ISSUER, actor: String = "player") -> Dictionary:
	var kind: String = {"site_arrangement": "site_case", "borrow_source": "source_offer", "verify_return": "source_note"}[verb]
	return SimInteractionRequests.submit(world, {"sender": world.embodiment.subject_for_actor(actor), "receiver": world.embodiment.subject_for_actor(receiver), "verb": verb,
		"object": {"kind": kind, "id": id}, "medium": "spoken", "conditions": {}})


func _finish_service(world: RegionalSimulation, actor: String, runner: Object) -> void:
	var limit: int = world.elapsed_ms + 1800000
	while world.services.owns_actor(actor) and world.elapsed_ms < limit:
		var next: int = mini(limit, world.elapsed_ms + 10000)
		if not world.advance_to_ms(next):
			runner.assert_true(false, "source-loan service advances on the original scheduler")
			return
	runner.assert_true(not world.services.owns_actor(actor), "bounded source-loan service reaches an actual terminal result")


func _borrow(world: RegionalSimulation, runner: Object, offer: String = "source_once_body") -> String:
	_at(world, "player", "kitchen")
	if Support.artifact(runner, world, "player", "take").is_empty():
		return ""
	_desk(world)
	var announcement: Dictionary = _intent(world, "site_arrangement", CASE)
	runner.assert_eq(announcement.status, "completed", "actual issuer explains the specific original source arrangement")
	var reply: Dictionary = _intent(world, "borrow_source", offer)
	runner.assert_eq(reply.status, "started", "actual local request starts an original timed signature service")
	if not reply.ok:
		return ""
	runner.assert_true(world.site_affairs.notes.is_empty(), "accepting the request does not prematurely issue an official promise")
	_finish_service(world, "player", runner)
	for note: Dictionary in world.site_affairs.notes.values():
		if note.actor == "player":
			runner.assert_eq(note.issue_job, reply.process.id, "official note names the same actually completed service")
			return str(note.id)
	runner.assert_true(false, "completed actual signature service creates its one official note")
	return ""


func _use(world: RegionalSimulation, runner: Object, target: String = "body") -> String:
	_at(world, "player", "kitchen")
	var answer: Dictionary = world.spirit_sources.begin("player", SOURCE, target, STONE)
	runner.assert_true(answer.ok, "original source process begins using the original held medium: " + str(answer.line))
	return Support.finish(runner, world) if answer.ok else ""


func _place(world: RegionalSimulation, runner: Object, actor: String = "player") -> void:
	_at(world, actor, "kitchen")
	Support.artifact(runner, world, actor, "place")


func _check_to_stage(world: RegionalSimulation, id: String, stage: String, runner: Object) -> void:
	var limit: int = world.elapsed_ms + 1800000
	while world.services.jobs[id].status == "active" and world.services.jobs[id].stage != stage and world.elapsed_ms < limit:
		if not world.advance_to_ms(mini(limit, world.elapsed_ms + 100)):
			break
	runner.assert_eq(world.services.jobs[id].stage, stage, "original verifier physically reaches the next finite service stage")


func _explicit_arrangement_and_requests(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var affairs: SimSiteAffairs = world.site_affairs
	var before: String = Support.canonical(world.to_dict())
	runner.assert_true(affairs.known_cases("player").is_empty() and affairs.offers_for("player").is_empty(), "unannounced public source terms are not automatically everybody's knowledge")
	runner.assert_eq(affairs.inquiry_cases("player", ISSUER).size(), 1, "actual incumbent at the public desk offers one local inquiry")
	runner.assert_true(affairs.inquiry_cases("player", "shi_tou").is_empty(), "unappointed person at a desk cannot advertise signing authority")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "viewing choices changes no knowledge, resources, claims or random decision")
	runner.assert_eq(_intent(world, "borrow_source", "source_once_body").status, "unheard", "scripted unknown offer cannot bypass actually hearing its terms")
	var reply: Dictionary = _intent(world, "site_arrangement", CASE)
	runner.assert_eq(reply.status, "completed", "ordinary structured request obtains the actual explanation")
	runner.assert_eq(affairs.known_cases("player").size(), 1, "only actual hearer knows the local arrangement")
	runner.assert_true(affairs.known_cases("shi_tou").is_empty(), "another named resident does not automatically learn the private explanation")
	runner.assert_eq(affairs.offers_for("player").size(), 2, "same known source offers two fixed real destinations")
	runner.assert_true(not str(reply.line).contains("amount") and not str(reply.line).contains("预约"), "public terms expose neither live source amounts nor other people's reservations")
	var remembered: String = Support.canonical(world.to_dict())
	runner.assert_eq(_intent(world, "site_arrangement", CASE).process, reply.process, "repeat explanation reuses the same person's actual source event")
	runner.assert_eq(Support.canonical(world.to_dict()), remembered, "repeating the same explanation does not mint social history")
	runner.assert_true(not _intent(world, "borrow_source", "source_once_body").ok, "knowing the terms is insufficient while the original medium is still on its shelf")
	runner.assert_true(affairs.notes.is_empty(), "failed prerequisite produces no permit, energy or claim")


func _signature_rechecks_and_repeated_request(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	_at(world, "player", "kitchen")
	Support.artifact(runner, world, "player", "take")
	_desk(world)
	_intent(world, "site_arrangement", CASE)
	_at(world, "shi_tou", "records")
	var before: String = Support.canonical(world.to_dict())
	runner.assert_true(not _intent(world, "borrow_source", "source_once_body", "shi_tou").ok, "unappointed resident cannot replace the specifically designated incumbent")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "lack of specific authority creates no decision, source reservation or permit")
	var first: Dictionary = _intent(world, "borrow_source", "source_once_body")
	runner.assert_eq(first.status, "started", "actual designated incumbent accepts one finite signature job")
	if not first.ok:
		return
	var rng: String = str(world.regions.home._rng.state)
	var count: int = world.services.jobs.size()
	var repeated: Dictionary = _intent(world, "borrow_source", "source_once_body")
	runner.assert_eq(repeated.status, "pending", "same accepted request returns its original in-progress service")
	runner.assert_eq(repeated.process, first.process, "repeated request references the same original signature job")
	runner.assert_eq(world.services.jobs.size(), count, "repeat cannot create a second body executor or signature job")
	runner.assert_eq(str(world.regions.home._rng.state), rng, "repeat does not roll another social outcome")
	_at(world, ISSUER, "kitchen")
	_finish_service(world, "player", runner)
	runner.assert_eq(world.services.jobs[first.process.id].status, "failed", "actual issuer leaving the desk prevents final public signature")
	runner.assert_true(world.site_affairs.notes.is_empty(), "failed desk check leaves no official note")
	runner.assert_eq(world.artifacts.objects[STONE].container, "actor:player", "failed signature leaves original stone custody untouched")
	_desk(world)
	var retried: Dictionary = _intent(world, "borrow_source", "source_once_body")
	runner.assert_eq(retried.status, "started", "same actual issuer can process the request after actually returning to its desk")
	if retried.ok:
		_finish_service(world, "player", runner)
		runner.assert_eq(world.site_affairs.notes.size(), 1, "successful later processing creates exactly one scoped note")


func _original_use_and_actual_return(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var book: String = Support.canonical(world.regions.home.institutions.to_dict())
	var id: String = _borrow(world, runner)
	if id.is_empty():
		return
	var note: Dictionary = world.site_affairs.notes[id]
	runner.assert_eq(world.site_affairs.notes.size(), 1, "one actual completed signature creates one scoped note")
	runner.assert_eq(note.office, "steward", "note is issued under the specific original office rather than a person's permanent authority")
	runner.assert_eq(world.regions.home.actors.player.qi, 10, "signature grants no original body energy")
	runner.assert_eq(world.artifacts.objects[STONE].charge, 6, "signature grants no original stone charge")
	runner.assert_true(not _intent(world, "borrow_source", "source_once_body").ok, "unclosed original borrowing prevents a parallel replacement promise")
	var record: String = _use(world, runner)
	if record.is_empty():
		return
	runner.assert_eq(note.used, record, "official usage points to the same actual successful source receipt")
	runner.assert_eq(note.attempts, [record], "one original source job is associated once")
	runner.assert_eq(note.bound, "", "completed original source job releases the temporary association")
	runner.assert_eq(world.regions.home.actors.player.qi, 14, "actual source work restores only the original body's accepted output")
	runner.assert_eq(world.spirit_sources.sources[SOURCE].spent, 6, "actual source work spends one real reserved batch")
	_place(world, runner)
	_desk(world)
	var answer: Dictionary = _intent(world, "verify_return", id)
	runner.assert_eq(answer.status, "started", "actual in-person claim begins finite verification instead of immediate redemption")
	if not answer.ok:
		return
	var job: Dictionary = world.services.jobs[answer.process.id]
	runner.assert_eq(job.actor, ISSUER, "verification movement is owned by the actual office holder's original body")
	runner.assert_eq(job.options.requester, "player", "original applicant is separate from the travelling verifier")
	runner.assert_true(not world.services.owns_actor("player") and world.services.owns_actor(ISSUER), "applicant is free while the accepted verifier genuinely travels")
	runner.assert_eq(note.closed_ms, -1, "claiming return and accepting verification cannot close the record early")
	var before_position: Array = world.regions.home.actors[ISSUER].position.duplicate()
	world.advance_to_ms(world.elapsed_ms + 1000)
	runner.assert_true(world.regions.home.actors[ISSUER].position != before_position, "verifier actually walks toward the real kitchen")
	runner.assert_true(not world.site_affairs.checks[job.id].observation.has("event"), "travel alone supplies no premature site evidence")
	_finish_service(world, ISSUER, runner)
	runner.assert_eq(job.status, "completed", "verifier finishes actual inspection and actual return to the original desk")
	runner.assert_true(int(note.closed_ms) > int(world.site_affairs.checks[job.id].observation.at_ms), "official closure follows rather than precedes a real site observation")
	runner.assert_true(SimWorkplaces.at_desk(world.regions.home, ISSUER), "final registration is done at the original desk")
	runner.assert_eq(world.artifacts.objects[STONE].container, "kitchen", "return leaves the same original stone available at the original place")
	runner.assert_eq(Support.canonical(world.regions.home.institutions.to_dict()), book, "borrowed energy and return evidence mint neither contribution nor institutional balance")
	var before_query: String = Support.canonical(world.to_dict())
	var observed: Dictionary = SimInteractionRequests.observe(world, "subject:player", answer.process)
	runner.assert_eq(observed.status, "pending", "looking at accepted verification does not manufacture an unspoken outcome")
	runner.assert_eq(Support.canonical(world.to_dict()), before_query, "querying a receipt is a pure view rather than an implicit dialogue")
	var heard: Dictionary = _intent(world, "verify_return", id)
	runner.assert_eq(heard.status, "completed", "actual in-person follow-up hears the returned verifier's recorded result")
	observed = SimInteractionRequests.observe(world, "subject:player", answer.process)
	runner.assert_eq(observed.status, "completed", "receipt can recall the result after the applicant actually hears it")
	runner.assert_true(str(observed.line).contains("声称") and str(observed.line).contains("复位"), "official wording distinguishes a person's claim from actually seeing public equipment in place")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:shi_tou", answer.process).status, "unconfirmed", "knowing another person's process ID grants no private outcome")


func _last_batch_and_cancelled_attempt(runner: Object) -> void:
	var rules: Dictionary = Support.rules()
	rules.sources.hearth_seam.initial = 6
	rules.sources.hearth_seam.deep_supply = 0
	var world: RegionalSimulation = _make(runner, {"rules": rules, "second_stone": true})
	if world == null:
		return
	var id: String = _borrow(world, runner)
	if id.is_empty():
		return
	var note: Dictionary = world.site_affairs.notes[id]
	_at(world, "player", "kitchen")
	runner.assert_true(world.spirit_sources.begin("player", SOURCE, "body", STONE).ok, "one permit associates with an actually started last-batch operation")
	var first: String = str(world.spirit_sources.active.player.id)
	runner.assert_eq(note.bound, first, "only the original source job supplies the active association")
	world.spirit_sources.cancel("player")
	runner.assert_eq(note.bound, "", "cancelling the original source job releases its association")
	runner.assert_eq(note.used, "", "cancellation does not consume the scoped right")
	runner.assert_eq(world.spirit_sources.sources[SOURCE].spent, 0, "cancelled source labor spends no physical source reserve")
	runner.assert_true(world.spirit_sources.begin("player", SOURCE, "body", STONE).ok, "within-deadline cancellation may retry the same original promise")
	var second: String = Support.finish(runner, world)
	runner.assert_eq(note.used, second, "only the real successful retry consumes recognition")
	runner.assert_eq(note.attempts, [first, second], "failed and successful original attempts remain separately sourced")
	runner.assert_eq(world.spirit_sources.sources[SOURCE].spent, 6, "two attempts spend exactly the one completed actual batch")
	# A different clean world makes a signed promise before another original
	# body with its own real medium exhausts the same last batch.
	world = _make(runner, {"rules": rules, "second_stone": true})
	if world == null:
		return
	id = _borrow(world, runner)
	if id.is_empty():
		return
	note = world.site_affairs.notes[id]
	_at(world, ISSUER, "kitchen")
	Support.artifact(runner, world, ISSUER, "take", "second_stone")
	runner.assert_true(world.spirit_sources.begin(ISSUER, SOURCE, "stone", "second_stone").ok, "another actual body and unique medium may consume the public source first")
	Support.finish(runner, world, ISSUER)
	_at(world, "player", "kitchen")
	runner.assert_true(not world.spirit_sources.begin("player", SOURCE, "body", STONE).ok, "signed promise cannot manufacture missing source energy")
	runner.assert_eq(note.bound, "", "source shortage leaves no imaginary active permit lock")
	runner.assert_true(note.attempts.is_empty() and note.used == "", "source shortage consumes no use and records no fabricated source job")


func _deadline_is_a_start_deadline(runner: Object) -> void:
	for start_late: bool in [false, true]:
		var world: RegionalSimulation = _make(runner)
		if world == null:
			return
		var id: String = _borrow(world, runner)
		if id.is_empty():
			return
		var note: Dictionary = world.site_affairs.notes[id]
		_at(world, "player", "kitchen")
		world.advance_to_ms(int(note.start_until_ms) if start_late else int(note.start_until_ms) - 1)
		var answer: Dictionary = world.spirit_sources.begin("player", SOURCE, "body", STONE)
		runner.assert_true(answer.ok, "absence of valid recognition does not prohibit an otherwise possible physical source action")
		if not answer.ok:
			continue
		var original: String = str(world.spirit_sources.active.player.id)
		runner.assert_eq(note.bound, "" if start_late else original, "recognition uses the exact strict latest-start boundary")
		Support.finish(runner, world)
		runner.assert_eq(note.used, "" if start_late else original, "already-associated work may finish after the deadline while late work receives no retroactive recognition")
		runner.assert_eq(world.regions.home.actors.player.qi, 14, "actual physical energy comes from original work regardless of the institution's recognition")


func _communication_understanding_and_permission(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	_intent(world, "site_arrangement", CASE)
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/avian_life.json"))
	runner.assert_true(world.avian_life.spawn_opening(opening, {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}), "source request uses an actual ordinary bird body")
	var point: Vector2 = SimRouteTravel.point(world.regions.home.actors.player)
	world.avian_life.birds.moss_sparrow.position = [point.x, point.y]
	var before: String = Support.canonical(world.to_dict())
	var bird_intent: Dictionary = {"sender": "subject:player", "receiver": "subject:avian:moss_sparrow", "verb": "borrow_source", "object": {"kind": "source_offer", "id": "source_once_body"}, "medium": "gesture", "conditions": {}}
	runner.assert_eq(SimInteractionRequests.submit(world, bird_intent).status, "not_understood", "a real bird cannot understand or issue an institutional source promise")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "bird misunderstanding cannot create an official job, decision or note")
	var gesture: Dictionary = bird_intent.duplicate(true)
	gesture.receiver = "subject:" + ISSUER
	runner.assert_eq(SimInteractionRequests.submit(world, gesture).status, "not_understood", "gestures alone cannot silently accept fixed borrowing terms")
	var malformed: Dictionary = gesture.duplicate(true)
	malformed.medium = "spoken"
	malformed.conditions = {"unlimited_uses": true}
	runner.assert_eq(SimInteractionRequests.submit(world, malformed).status, "invalid", "specific promise cannot be extended with invented terms")
	runner.assert_true(world.site_affairs.notes.is_empty(), "rejected expressions mint no signed right")


func _false_claim_and_third_party_return(runner: Object) -> void:
	for third_party: bool in [false, true]:
		var world: RegionalSimulation = _make(runner)
		if world == null:
			return
		var id: String = _borrow(world, runner)
		if id.is_empty():
			return
		if third_party:
			# The applicant has genuinely held and used the stone, but this last
			# return is another body's original take/place, never rewritten.
			_place(world, runner)
			_at(world, "shi_tou", "kitchen")
			Support.artifact(runner, world, "shi_tou", "take")
			Support.artifact(runner, world, "shi_tou", "place")
		_desk(world)
		var reply: Dictionary = _intent(world, "verify_return", id)
		runner.assert_eq(reply.status, "started", "an in-person claim is considered without an omniscient placed-author lookup")
		if not reply.ok:
			continue
		_at(world, "player", "garden")
		var pending: Dictionary = SimInteractionRequests.observe(world, "subject:player", reply.process)
		runner.assert_eq(pending.status, "pending", "applicant knows that verification was accepted without tracking the verifier's remote route")
		runner.assert_true(not str(pending.line).contains("坐标") and not str(pending.line).contains("复位"), "remote pending view exposes no unreceived inspection result")
		_finish_service(world, ISSUER, runner)
		var note: Dictionary = world.site_affairs.notes[id]
		var check: Dictionary = world.site_affairs.checks[reply.process.id]
		runner.assert_eq(check.status, "completed" if third_party else "failed", "actual site evidence distinguishes a returned original stone from a false claim")
		runner.assert_eq(note.closed_ms != -1, third_party, "institution closes only actual public-equipment return, independent of the private placed author")
		var away: Dictionary = SimInteractionRequests.observe(world, "subject:player", reply.process)
		runner.assert_eq(away.status, "pending", "absent applicant does not receive a remote success or failure by reading the task state")
		_desk(world)
		var heard: Dictionary = SimInteractionRequests.observe(world, "subject:player", reply.process)
		runner.assert_eq(heard.status, "pending", "meeting the official without speaking does not itself grant private result knowledge")
		if third_party:
			runner.assert_eq(_intent(world, "verify_return", id).status, "completed", "actual in-person follow-up receives the already registered return result")
			heard = SimInteractionRequests.observe(world, "subject:player", reply.process)
			runner.assert_eq(heard.status, "completed", "previous actual process recalls the genuinely heard registered result")
			var placed_by: String = ""
			for event: Dictionary in world.artifacts.events:
				if event.kind == "placed" and event.object == STONE:
					placed_by = str(event.actor)
			runner.assert_eq(placed_by, "shi_tou", "original final placing author remains the third person rather than the claimant")
			runner.assert_true(str(heard.line).contains("声称"), "formal return record never upgrades a person's authorship claim into objective fact")


func _observation_survives_later_custody(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var id: String = _borrow(world, runner)
	if id.is_empty():
		return
	_place(world, runner)
	_desk(world)
	var answer: Dictionary = _intent(world, "verify_return", id)
	if not answer.ok:
		runner.assert_true(false, "later-custody fixture starts actual return verification")
		return
	_check_to_stage(world, str(answer.process.id), "register", runner)
	var observed: Dictionary = world.site_affairs.checks[answer.process.id].observation.duplicate(true)
	runner.assert_true(not observed.is_empty(), "verifier has already formed a real persistent site observation")
	_at(world, "shi_tou", "kitchen")
	Support.artifact(runner, world, "shi_tou", "take")
	_finish_service(world, ISSUER, runner)
	runner.assert_eq(world.services.jobs[answer.process.id].status, "completed", "later original custody change cannot invalidate an already witnessed past return")
	runner.assert_eq(world.site_affairs.checks[answer.process.id].observation, observed, "registration preserves the original actual site observation")
	runner.assert_true(world.site_affairs.notes[id].closed_ms != -1, "formal closure uses its actual earlier observation rather than current remote custody")
	runner.assert_eq(world.artifacts.objects[STONE].container, "actor:shi_tou", "recording the past does not teleport equipment out of its later actual custodian")


func _interrupted_registration_reuses_observation(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var id: String = _borrow(world, runner)
	if id.is_empty():
		return
	_place(world, runner)
	_desk(world)
	var first: Dictionary = _intent(world, "verify_return", id)
	if not first.ok:
		runner.assert_true(false, "interrupted-registration fixture begins an actual inspection")
		return
	_check_to_stage(world, str(first.process.id), "register", runner)
	var observed: Dictionary = world.site_affairs.checks[first.process.id].observation.duplicate(true)
	runner.assert_true(not observed.is_empty(), "cancelled registration already has a genuine earlier site observation")
	runner.assert_true(world.services.cancel(ISSUER, "fixture_registration_interrupted"), "original verifier can be interrupted during its return to the desk")
	runner.assert_eq(world.site_affairs.notes[id].closed_ms, -1, "cancelled registration preserves observation without falsely closing the public obligation")
	_at(world, "shi_tou", "kitchen")
	Support.artifact(runner, world, "shi_tou", "take")
	_desk(world)
	var resumed: Dictionary = _intent(world, "verify_return", id)
	runner.assert_eq(resumed.status, "started", "actual issuer may accept finite registration of its own already observed return")
	if not resumed.ok:
		return
	runner.assert_true(resumed.process.id != first.process.id, "resumed registration retains a new actual process instead of reviving a cancelled body's job")
	_finish_service(world, ISSUER, runner)
	var check: Dictionary = world.site_affairs.checks[resumed.process.id]
	runner.assert_eq(check.status, "completed", "registration can complete from actual earlier observation despite the original stone's later new custody")
	runner.assert_eq(check.origin_check, first.process.id, "later registration explicitly names the original observed-but-interrupted verification")
	runner.assert_eq(check.observation, observed, "resuming registration cannot invent a newer site observation or erase the earlier one")
	runner.assert_eq(world.artifacts.objects[STONE].container, "actor:shi_tou", "reusing historical evidence does not seize the later custodian's actual object")
	runner.assert_true(world.site_affairs.notes[id].closed_ms != -1, "one resumed actual registration closes the original obligation once")
	var snapshot: Dictionary = JSON.parse_string(Support.canonical(world.to_dict()))
	var restored: RegionalSimulation = _make(runner)
	if restored != null:
		runner.assert_true(restored.restore(snapshot), "explicit origin observation and cancelled service history independently validate together")


func _public_service_rejects_replayed_terms(runner: Object) -> void:
	# A wider initial source reach lets all legitimate talk/desk conditions
	# remain satisfied while the original source process owns the applicant.
	# The following refusal must come from the note's active association.
	var rules: Dictionary = Support.rules()
	rules.interaction_cells = 6
	var world: RegionalSimulation = _make(runner, {"rules": rules})
	if world == null:
		return
	var id: String = _borrow(world, runner)
	if id.is_empty():
		return
	var accepted: Dictionary = _intent(world, "verify_return", id)
	runner.assert_eq(accepted.status, "started", "public-entry regression begins from genuine accepted return terms")
	if not accepted.ok:
		return
	var options: Dictionary = world.services.jobs[accepted.process.id].options.duplicate(true)
	var before: String = Support.canonical(world.to_dict())
	var duplicate: Dictionary = world.services.begin(ISSUER, "home", "site_return", options)
	runner.assert_true(not duplicate.ok, "public service entry cannot duplicate an already accepted in-flight verifier")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "duplicate verification creates no body executor, check, event or random decision")
	runner.assert_true(world.services.cancel(ISSUER, "public_entry_regression"), "original accepted verifier is explicitly cancelled before testing another public entry")
	var forged: Dictionary = options.duplicate(true)
	forged.claim_event = "event_999999"
	before = Support.canonical(world.to_dict())
	var missing: Dictionary = world.services.begin(ISSUER, "home", "site_return", forged)
	runner.assert_true(not missing.ok and missing.reason == "missing_claim", "public service entry refuses invented personal return evidence before allocating a job")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "invented return evidence leaves the whole original world unchanged")
	runner.assert_true(world.spirit_sources.begin("player", SOURCE, "body", STONE).ok, "same original note genuinely associates while all desk and communication conditions remain valid")
	runner.assert_true(not str(world.site_affairs.notes[id].bound).is_empty(), "active source protection is exercised with an actual association")
	before = Support.canonical(world.to_dict())
	var bound: Dictionary = world.services.begin(ISSUER, "home", "site_return", options)
	runner.assert_true(not bound.ok and str(bound.line).contains("用源"), "old accepted options cannot start public verification while the applicant's original source operation is active")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "active-source refusal preserves original appointment, source reserve and bodily work")
	runner.assert_true(world.spirit_sources.cancel("player"), "test releases its actual source association through the original cancellation path")
	_place(world, runner)
	_desk(world)
	var fresh: Dictionary = _intent(world, "verify_return", id)
	runner.assert_eq(fresh.status, "started", "a fresh genuine return claim may still begin after the original source cancellation and actual placement")
	if not fresh.ok:
		return
	var closed_options: Dictionary = world.services.jobs[fresh.process.id].options.duplicate(true)
	_finish_service(world, ISSUER, runner)
	runner.assert_true(world.site_affairs.notes[id].closed_ms != -1, "fresh real verification actually closes its original note")
	before = Support.canonical(world.to_dict())
	var replayed: Dictionary = world.services.begin(ISSUER, "home", "site_return", closed_options)
	runner.assert_true(not replayed.ok and str(replayed.line).contains("结清"), "public service entry cannot reuse old terms to reopen an already closed public obligation")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "replayed closed terms cannot duplicate signature, observation, registration or resources")


func _premature_callbacks_cannot_write_evidence(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	_at(world, "player", "kitchen")
	Support.artifact(runner, world, "player", "take")
	_desk(world)
	_intent(world, "site_arrangement", CASE)
	var accepted: Dictionary = _intent(world, "borrow_source", "source_once_body")
	if not accepted.ok:
		runner.assert_true(false, "early-callback regression starts a real timed signature")
		return
	var job: Dictionary = world.services.jobs[accepted.process.id]
	var before: String = Support.canonical(world.to_dict())
	var early: Dictionary = world.site_affairs.settle_service(job)
	runner.assert_true(not early.ok, "calling settlement directly before the original signature's work deadline does not issue a note")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "early original signature callback writes no promise, event or resource effect")
	var detached: Dictionary = job.duplicate(true)
	detached.phase = "work"
	detached.path = []
	detached.due_ms = world.elapsed_ms
	runner.assert_true(not world.site_affairs.settle_service(detached).ok, "forged due-time copy cannot stand in for the actual live service job")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "forged callback leaves the complete real service and world untouched")
	_finish_service(world, "player", runner)
	if world.site_affairs.notes.is_empty():
		runner.assert_true(false, "normal original deadline still issues its genuine note after rejected early callbacks")
		return
	var note: Dictionary = world.site_affairs.notes.values()[0]
	_place(world, runner)
	_desk(world)
	var answer: Dictionary = _intent(world, "verify_return", str(note.id))
	if not answer.ok:
		runner.assert_true(false, "early-return regression starts a genuine accepted verification")
		return
	job = world.services.jobs[answer.process.id]
	before = Support.canonical(world.to_dict())
	runner.assert_true(not world.site_affairs.settle_service(job).ok, "calling inspection settlement while the verifier is still travelling produces no sight")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "premature inspection cannot fabricate an actual site observation")
	_check_to_stage(world, str(job.id), "register", runner)
	var observation: Dictionary = world.site_affairs.checks[job.id].observation.duplicate(true)
	before = Support.canonical(world.to_dict())
	runner.assert_true(not world.site_affairs.settle_service(job).ok, "existing real site evidence does not allow registration before the original return journey and work deadline")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "premature registration preserves real observation and leaves the obligation open")
	runner.assert_eq(note.closed_ms, -1, "direct callback never closes the note before the genuine registration boundary")
	_finish_service(world, ISSUER, runner)
	runner.assert_eq(job.status, "completed", "normal finite service can still finish after rejected premature settlement calls")
	runner.assert_eq(world.site_affairs.checks[job.id].observation, observation, "actual final registration preserves the original site observation")
	before = Support.canonical(world.to_dict())
	runner.assert_true(not world.site_affairs.settle_service(job).ok, "terminal real service cannot be settled again through a direct callback")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "repeated terminal settlement cannot duplicate official events or closure")


func _strict_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _make(runner)
	if world == null:
		return
	var id: String = _borrow(world, runner)
	if id.is_empty():
		return
	_use(world, runner)
	var snapshot: Dictionary = JSON.parse_string(Support.canonical(world.to_dict()))
	for fault: String in ["extra", "wrong_source", "wrong_actor", "wrong_issuer", "wrong_office", "wrong_job", "duplicate_attempt", "erase_use", "fake_closed"]:
		var forged: Dictionary = snapshot.duplicate(true)
		var note: Dictionary = forged.site_affairs.notes[id]
		match fault:
			"extra": note["global_access"] = true
			"wrong_source": forged.site_affairs.cases[CASE].source = "river_source"
			"wrong_actor": note.actor = "shi_tou"
			"wrong_issuer": note.issuer = "shi_tou"
			"wrong_office": note.office = "registrar"
			"wrong_job": note.issue_job = "service:job:99999"
			"duplicate_attempt": note.attempts.append(note.used)
			"erase_use": note.used = ""
			"fake_closed": note.closed_ms = int(forged.elapsed_ms)
		var before: String = Support.canonical(world.to_dict())
		runner.assert_true(not world.restore(forged), "independent affairs candidate rejects " + fault)
		runner.assert_eq(Support.canonical(world.to_dict()), before, "bad affairs candidate cannot partially replace original state: " + fault)
	var restored: RegionalSimulation = _make(runner)
	if restored == null:
		return
	runner.assert_true(restored.restore(snapshot), "genuine completed source borrowing independently restores with original source and service proof")
	runner.assert_eq(Support.canonical(restored.to_dict()), Support.canonical(world.to_dict()), "valid restore retains all original domains rather than only the new note")


func _fine_sparse_and_inflight_restore(runner: Object) -> void:
	var sparse: RegionalSimulation = _make(runner)
	if sparse == null:
		return
	var id: String = _borrow(sparse, runner)
	if id.is_empty():
		return
	_at(sparse, "player", "kitchen")
	runner.assert_true(sparse.spirit_sources.begin("player", SOURCE, "body", STONE).ok, "in-flight permitted original source action begins")
	sparse.advance_to_ms(sparse.elapsed_ms + 23457)
	var fine: RegionalSimulation = _make(runner)
	if fine == null:
		return
	runner.assert_true(fine.restore(JSON.parse_string(Support.canonical(sparse.to_dict()))), "in-flight original source association has an independent saved candidate")
	var future: int = sparse.elapsed_ms + 150000
	sparse.advance_to_ms(future)
	var reached: bool = true
	while fine.elapsed_ms < future:
		reached = fine.advance_to_ms(mini(future, fine.elapsed_ms + 517)) and reached
	runner.assert_true(reached, "fine updates reach the same source future")
	runner.assert_eq(Support.canonical(fine.to_dict()), Support.canonical(sparse.to_dict()), "saved permission association and original source have exactly the same fine/sparse full future")
	_place(sparse, runner)
	_desk(sparse)
	var reply: Dictionary = _intent(sparse, "verify_return", id)
	if not reply.ok:
		runner.assert_true(false, "in-flight verification starts from genuine completed use and place")
		return
	sparse.advance_to_ms(sparse.elapsed_ms + 1000)
	fine = _make(runner)
	if fine == null:
		return
	runner.assert_true(fine.restore(JSON.parse_string(Support.canonical(sparse.to_dict()))), "original verifier travel and applicant reference independently restore mid-route")
	future = sparse.elapsed_ms + 240000
	sparse.advance_to_ms(future)
	reached = true
	while fine.elapsed_ms < future:
		reached = fine.advance_to_ms(mini(future, fine.elapsed_ms + 517)) and reached
	runner.assert_true(reached, "fine updates reach the same verification future")
	runner.assert_eq(Support.canonical(fine.to_dict()), Support.canonical(sparse.to_dict()), "original verifier body, two service stages, observation and official closure have identical saved futures")
