extends "res://tests/runtime/helpers/drawing_replay.gd"
## Genuine late arrival and a separately observed busy window. All movement,
## money, decisions and artifact operations use their original authorities.

const SELLER: String = "river_shi_tou"
const LATE_SOURCE: String = "res://tests/fixtures/session_v40_npc.json"
const LATE_SHA: String = "27186018991b78ee1201e2d1286e16af206c72d7d3e9289cdf328fc40acbf7c0"
const EXCHANGE_ARCHIVE: String = "res://logs/private_exchange_inflight.json"
const QUOTED_OBJECT: Dictionary = {"kind": "private_artifact", "id": RING}


func prepare_exchange(runtime: WorldContinuityRuntime, archive: String = EXCHANGE_ARCHIVE) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "source": LATE_SOURCE, "steps": [], "busy_observed": false}
	if FileAccess.get_sha256(LATE_SOURCE) != LATE_SHA or runtime.load_game(ProjectSettings.globalize_path(LATE_SOURCE)) != OK or not _choose(runtime):
		return _failure("the genuine NPC journey source could not be opened", report)
	if not _ask(runtime, report):
		return _failure("the player could not personally learn the old field clue", report)
	# A fixed, ordinary wait does not inspect the unseen NPC or ring to decide
	# when to depart. The subsequent site observation is the player's evidence.
	if not _advance(runtime, 120000) or not runtime.travel_to_site("broken_stele") or not _finish_trip(runtime):
		return _failure("the personally known old field destination could not be reached", report)
	var observation: Dictionary = runtime.world_sim.field_opportunities.observe_site("player", "broken_stele")
	_note(report, "personally_observed_site", observation)
	if not bool(observation.get("ok", false)) or str(observation.line) != str(runtime.world_sim.field_opportunities.definitions.labels["empty"]):
		return _failure("the actual late visitor did not observe an empty old slot", report)
	var subject: String = runtime.world_sim.embodiment.subject_for_actor(SELLER)
	if not _search_river(runtime, subject, report):
		return _failure("no visible, available and willing holder accepted within the bounded ordinary search", report)
	var process: Dictionary = report.get("accepted_process", {})
	var world: RegionalSimulation = runtime.world_sim
	var exchange: RefCounted = world.private_exchange
	var job: Dictionary = exchange.jobs.get(str(process.get("id", "")), {})
	if job.is_empty() or exchange.observe("player", process).status != "pending":
		return _failure("the accepted request did not create the actual pending handover", report)
	var price: int = int(exchange.definitions.price)
	var currency: String = str(exchange.definitions.currency)
	var buyer: SimInventory = world.regions[job.buyer_region].inventory
	var seller: SimInventory = world.regions[job.seller_region].inventory
	var buyer_coin: int = buyer.quantity("actor:player", currency)
	var seller_coin: int = seller.quantity("actor:" + SELLER, currency)
	var reserved: Dictionary = buyer.reservations.get(job.reservation, {})
	if reserved.get("container") != "actor:player" or reserved.get("item") != currency or int(reserved.get("amount", -1)) != price or reserved.get("owner_id") != "player" or world.artifacts.objects[RING].container != "actor:" + SELLER or world.artifacts.objects[RING].region != job.seller_region:
		return _failure("the quoted money was not reserved at its original owner while the ring stayed with the seller", report)
	if not _advance(runtime, 2000) or int(job.due_ms) <= GameClock.elapsed_ms or exchange.observe("player", process).status != "pending":
		return _failure("the real handover did not reach an unfinished shared-time midpoint", report)
	_note(report, "original_money_reserved_not_delivered", {"process": process, "price": price, "duration_ms": int(exchange.definitions.duration_ms),
		"buyer_coin": buyer_coin, "seller_coin": seller_coin, "ring": world.artifacts.objects[RING].duplicate(true)})
	return _archive(runtime, report, archive)


func probe_busy(runtime: WorldContinuityRuntime) -> Dictionary:
	# This is a separate genuine early visit, not a claim about the late route.
	# Observe throughout the original journey and wait for actual visible
	# movement; an idle holder may accept and is not evidence of a busy window.
	var report: Dictionary = {"ordinary_commands": true, "source": LATE_SOURCE, "steps": []}
	if FileAccess.get_sha256(LATE_SOURCE) != LATE_SHA or runtime.load_game(ProjectSettings.globalize_path(LATE_SOURCE)) != OK or not _choose(runtime):
		return _failure("the genuine busy-window source could not be opened", report)
	if not _ask(runtime, report) or not runtime.travel_to_site("broken_stele"):
		return _failure("the personally known field journey could not be started for the independent busy probe", report)
	var subject: String = runtime.world_sim.embodiment.subject_for_actor(SELLER)
	var deadline: int = GameClock.elapsed_ms + 300000
	var previous_point: Vector2 = Vector2.INF
	var saw_holder: bool = false
	while GameClock.elapsed_ms < deadline:
		_senses(runtime)
		var choice: Dictionary = _ring_choice(runtime, subject) if _visible(runtime, subject) else {}
		if choice.is_empty():
			previous_point = Vector2.INF
		else:
			# Only read the point of the person whose body and exact held ring
			# the player can see now; it is never used as a remote destination.
			var point: Vector2 = SimRouteTravel.point(runtime.world_sim.regions.river.actors[SELLER])
			if not saw_holder:
				saw_holder = true
				_note(report, "personally_seen_holder", {"choice": choice, "visible_status": runtime.visible_actor_status(SELLER)})
			var moving: bool = previous_point.is_finite() and not point.is_equal_approx(previous_point)
			previous_point = point
			if not runtime.player_journey.is_empty() and _within_contact(runtime, subject):
				runtime.cancel_travel()
				_senses(runtime)
			if not runtime.player_journey.is_empty() or not _within_contact(runtime, subject) or not moving:
				if not _advance(runtime, 250):
					return _failure("the original shared clock could not reach the busy window", report)
				continue
			var before: Dictionary = _actual_activity(runtime.world_sim)
			var answer: Dictionary = runtime.interaction_adapter.submit(subject, "private_exchange", QUOTED_OBJECT)
			var after: Dictionary = _actual_activity(runtime.world_sim)
			_note(report, "visible_busy_offer", {"answer": answer, "before": before, "after": after, "visible_status": runtime.visible_actor_status(SELLER)})
			if answer.status != "unavailable" or not bool(before.busy):
				return _failure("the moving visible holder did not produce an actual busy response", report)
			if SnapshotValues.normalized(before) != SnapshotValues.normalized(after):
				return _failure("the declined request changed the seller's original occupation", report)
			report.merge({"ok": true, "busy_observed": true, "ms": GameClock.elapsed_ms})
			return report
		if not _advance(runtime, 250):
			return _failure("the original shared clock could not reach the busy window", report)
	report["saw_holder"] = saw_holder
	return _failure("no moving visible holder was reached within the bounded early visit", report)


func replay_exchange(runtime: WorldContinuityRuntime, suffix: String, cancel: bool = false, archive: String = EXCHANGE_ARCHIVE) -> Dictionary:
	var report: Dictionary = {"ordinary_commands": true, "source": archive, "cancelled": cancel, "steps": []}
	if not suffix.is_valid_identifier() or runtime.load_game(ProjectSettings.globalize_path(archive)) != OK or not _choose(runtime):
		return _failure("the actual private handover midpoint could not be loaded", report)
	var world: RegionalSimulation = runtime.world_sim
	var exchange: RefCounted = world.private_exchange
	var pending: Array[Dictionary] = exchange.pending("player")
	if pending.is_empty():
		return _failure("the loaded midpoint has no participant's handover reference", report)
	var process: Dictionary = pending.back()
	var job: Dictionary = exchange.jobs.get(str(process.id), {})
	if job.is_empty() or exchange.observe("player", process).status != "pending" or int(job.due_ms) <= GameClock.elapsed_ms:
		return _failure("the loaded reference is not the original in-progress handover", report)
	runtime.interaction_adapter.show_panel()
	if runtime.interaction_adapter._receipt != process:
		return _failure("the reopened C panel did not reconstruct the actual pending reference", report)
	var price: int = int(exchange.definitions.price)
	var currency: String = str(exchange.definitions.currency)
	var buyer: SimInventory = world.regions[job.buyer_region].inventory
	var seller: SimInventory = world.regions[job.seller_region].inventory
	var buyer_before: int = buyer.quantity("actor:player", currency)
	var seller_before: int = seller.quantity("actor:" + SELLER, currency)
	var buyer_position: Array = job.buyer_position.duplicate()
	var seller_position: Array = job.seller_position.duplicate()
	if world.artifacts.objects[RING].container != "actor:" + SELLER or world.artifacts.objects[RING].region != job.seller_region or not buyer.reservations.has(job.reservation):
		return _failure("the restored midpoint lacks the original ring custody or reserved money", report)
	if cancel:
		runtime.stop_player_action()
		if exchange.observe("player", process).status != "cancelled" or buyer.reservations.has(job.reservation) or buyer.quantity("actor:player", currency) != buyer_before or seller.quantity("actor:" + SELLER, currency) != seller_before or world.artifacts.objects[RING].container != "actor:" + SELLER:
			return _failure("the actual stop did not release the reservation while leaving both original properties", report)
		if world.regions[job.buyer_region].actors.player.position != buyer_position or world.regions[job.seller_region].actors[SELLER].position != seller_position or bool(world.regions[job.buyer_region].actors.player.autonomous) != bool(job.buyer_autonomous) or bool(world.regions[job.seller_region].actors[SELLER].autonomous) != bool(job.seller_autonomous):
			return _failure("stopping changed a continuous position or failed to restore a participant's original autonomy", report)
		if not _advance(runtime, int(job.due_ms) - GameClock.elapsed_ms + 1) or world.artifacts.objects[RING].container != "actor:" + SELLER or buyer.quantity("actor:player", currency) != buyer_before:
			return _failure("the cancelled process transferred property after its former deadline", report)
	else:
		if not _advance(runtime, int(job.due_ms) - GameClock.elapsed_ms) or exchange.observe("player", process).status != "completed":
			return _failure("the original handover did not complete at its actual shared deadline", report)
		if buyer.quantity("actor:player", currency) != buyer_before - price or seller.quantity("actor:" + SELLER, currency) != seller_before + price or world.artifacts.objects[RING].container != "actor:player" or world.artifacts.objects[RING].region != job.buyer_region:
			return _failure("the original quote and same ring did not transfer exactly once", report)
		var payment: Dictionary = exchange.transfers.get(str(job.receipt), {})
		if payment.get("job") != job.id or payment.get("consent") != job.consent or payment.get("artifact_event") != job.artifact_event or int(payment.get("amount", -1)) != price:
			return _failure("the actual money receipt does not link the agreed handover and original artifact event", report)
	_note(report, "actual_money_and_ring_outcome", {"outcome": exchange.observe("player", process), "price": price, "consent": str(job.consent), "receipt": str(job.receipt), "artifact_event": str(job.artifact_event),
		"buyer_coin": buyer.quantity("actor:player", currency), "seller_coin": seller.quantity("actor:" + SELLER, currency),
		"ring": world.artifacts.objects[RING].duplicate(true)})
	if not cancel and not _research_and_draw(runtime, report):
		return _failure("the acquired original ring did not continue through personal research and the original drawing action", report)
	if not _travel(runtime, "home") or not _advance(runtime, 120000):
		return _failure("ordinary later travel and life after the handover failed", report)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var path: String = "res://logs/private_exchange_future_%s.json" % suffix
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty() or runtime.save_game(ProjectSettings.globalize_path(path)) != OK:
		return _failure("the complete joint future failed independent validation or ordinary saving", report)
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "full_snapshot": path,
		"candidate_valid": true, "sha256": FileAccess.get_sha256(path)})
	_write_json("res://logs/private_exchange_restart_%s.json" % suffix, report)
	return report


func _research_and_draw(runtime: WorldContinuityRuntime, report: Dictionary) -> bool:
	if not runtime.object_adapter.select_object(RING):
		return false
	for verb: String in ["study", "use_research"]:
		var answer: Dictionary = runtime.object_adapter.submit(verb)
		_note(report, "original_ring_" + verb, answer)
		if not bool(answer.get("ok", false)) or not _finish_artifact(runtime):
			return false
	if not runtime.world_sim.artifacts.learned_use("player", RING) or not _to_drawing_position(runtime, report):
		return false
	if not runtime.object_adapter.select_object(RING):
		return false
	var draw: Dictionary = runtime.object_adapter.submit_draw("training_sword")
	_note(report, "original_ring_draw", draw)
	if not bool(draw.get("ok", false)) or not _finish_artifact(runtime):
		return false
	var sword: Dictionary = runtime.world_sim.artifacts.objects.training_sword
	_note(report, "same_original_sword", sword.duplicate(true))
	return sword.container == "actor:player" and runtime.world_sim.artifacts.objects[RING].container == "actor:player"


func _search_river(runtime: WorldContinuityRuntime, subject: String, report: Dictionary) -> bool:
	# Route toward a known settlement, watching only the same visible receiver
	# and object projections available to the player. No unseen position is used.
	if not _visible(runtime, subject) and not _travel_search(runtime, subject, null):
		return false
	var places: Array[String] = ["records", "garden", "store", "kitchen", "dorm"]
	for attempt: int in 60:
		_senses(runtime)
		if _visible(runtime, subject):
			var choice: Dictionary = _ring_choice(runtime, subject)
			if not choice.is_empty():
				var quote: String = str(choice.label)
				var price: int = int(runtime.world_sim.private_exchange.definitions.price)
				var duration: String = str(float(runtime.world_sim.private_exchange.definitions.duration_ms) / 1000.0)
				if not quote.contains("%d钱" % price) or not quote.contains("交割%s秒" % duration):
					return false
				var answer: Dictionary = runtime.interaction_adapter.submit(subject, "private_exchange", QUOTED_OBJECT)
				_note(report, "visible_face_to_face_offer", {"choice": choice, "answer": answer})
				if answer.status == "started":
					report["accepted_process"] = answer.process.duplicate(true)
					return true
				if answer.status == "refused":
					return false
				if answer.status == "unavailable":
					var activity: Dictionary = _actual_activity(runtime.world_sim)
					if bool(activity.busy):
						report.busy_observed = true
						_note(report, "actual_busy_window", activity)
				if answer.status == "unheard":
					if not _approach_visible(runtime, subject):
						return false
					continue
		else:
			var place: String = places[attempt % places.size()]
			var public_cell: Vector2i = SimRouteTravel.cell(runtime.world_sim.regions.river.places[place].cell)
			if not _travel_search(runtime, subject, public_cell):
				return false
		if not _advance(runtime, 5000):
			return false
	return false


func _travel_search(runtime: WorldContinuityRuntime, subject: String, destination: Variant) -> bool:
	if not runtime.travel_to("river", destination):
		return false
	var deadline: int = GameClock.elapsed_ms + TRAVEL_LIMIT_MS
	while not runtime.player_journey.is_empty() and GameClock.elapsed_ms < deadline:
		if not _advance(runtime, mini(250, deadline - GameClock.elapsed_ms)):
			return false
		if _within_contact(runtime, subject) and not _ring_choice(runtime, subject).is_empty():
			runtime.cancel_travel()
			_senses(runtime)
			return true
	return runtime.player_journey.is_empty()


func _approach_visible(runtime: WorldContinuityRuntime, subject: String) -> bool:
	if not _visible(runtime, subject):
		return false
	# Capture a point only while the original person is actually in sight.
	var last_seen: Vector2i = SimRouteTravel.cell(runtime.world_sim.regions.river.actors[SELLER].cell)
	return _travel_search(runtime, subject, last_seen)


func _visible(runtime: WorldContinuityRuntime, subject: String) -> bool:
	for receiver: Dictionary in runtime.interaction_adapter.receivers():
		if receiver.key == subject:
			return true
	return false


func _within_contact(runtime: WorldContinuityRuntime, subject: String) -> bool:
	if not _visible(runtime, subject):
		return false
	var world: RegionalSimulation = runtime.world_sim
	var person: Dictionary = world.regions.river.actors[SELLER]
	var player: Dictionary = world.regions.home.actors.player
	var distance: float = minf(float(world.private_exchange.definitions.interaction_cells), float(world._content.interaction_requests.communication_cells)) * TileGrid.TILE_SIZE
	return SimRouteTravel.point(player).distance_to(SimRouteTravel.point(person)) <= distance


func _ring_choice(runtime: WorldContinuityRuntime, subject: String) -> Dictionary:
	for choice: Dictionary in runtime.interaction_adapter.objects_for("private_exchange", subject):
		if choice.key == QUOTED_OBJECT:
			return choice
	return {}


func _actual_activity(world: RegionalSimulation) -> Dictionary:
	# Read after an observed person and response, as evidence, not navigation.
	var body: Dictionary = world.regions.river.actors[SELLER]
	var returning: Dictionary = world.field_opportunities.route_projection(SELLER)
	var artifact: Dictionary = world.artifacts.active.get(SELLER, {})
	var native: Dictionary = body.active
	return {"busy": not returning.is_empty() or not artifact.is_empty() or not native.is_empty(),
		"field_route": returning.duplicate(true), "artifact_action": artifact.duplicate(true), "native_action": native.duplicate(true)}
