extends RefCounted
## Saved landmarks and finite journeys prove their own physical origin.
## Shape staging precedes artifacts; causal checks run after all original owners.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const TOP: Array[String] = ["version", "sites", "purposes", "trips", "next_id", "next_observation_ms"]
const SITE: Array[String] = ["id", "region", "container", "cell", "opened_ms", "source_events"]
const PURPOSE: Array[String] = ["actor", "region", "site", "clue_event", "phase", "goal", "retry_ms", "last_ms", "last_result", "trip", "artifact_action", "observed_event"]
const TRIP: Array[String] = ["id", "number", "actor", "region", "site", "leg", "started_ms", "last_ms", "origin", "destination", "waypoints", "step_index", "path", "segment_from", "segment_started_ms", "due_ms", "previous_autonomous", "status", "finished_ms", "reason", "stopped_ms", "stopped_position", "start_event", "finish_event"]
const REASONS: Array[String] = ["arrived", "cancelled", "control_lost", "occupied", "personal_need", "health", "duty", "displaced", "blocked", "interrupted", "struck_by_conflict", "hostile_warning", "manual_override"]
const RESULTS: Array[String] = ["pending", "travelling", "taking", "found", "empty", "unreachable", "interrupted", "arrived", "returned"]


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, TOP) or not Shape.count(data.version, 1, 1) or not data.sites is Dictionary or not data.purposes is Dictionary or not data.trips is Dictionary or not Shape.count(data.next_id, 1, int(domain.definitions.max_trips) + 1) or data.trips.size() != int(data.next_id) - 1: return false
	if not Shape.count(data.next_observation_ms): return false
	if data.sites.is_empty(): return data.purposes.is_empty() and data.trips.is_empty() and data.next_id == 1 and data.next_observation_ms == 0
	var rule: Dictionary = domain.definitions.site
	if not Shape.keys(data.sites, [rule.id]) or not Shape.keys(data.purposes, [domain.definitions.purpose.actor]): return false
	var site: Variant = data.sites[rule.id]
	if not Shape.keys(site, SITE) or site.id != rule.id or site.region != rule.region or site.container != rule.container or not domain.world.regions.has(site.region) or not Shape.cell_valid(site.cell) or not Shape.count(site.opened_ms, 0, int(domain.world.elapsed_ms)) or not Shape.keys(site.source_events, domain.definitions.opening_knowers): return false
	if domain.world.map_data == null or not domain.world.map_data.terrain_is_walkable(SimRouteTravel.cell(site.cell)): return false
	if not Shape.count(data.next_observation_ms, int(domain.world.elapsed_ms) + 1, int(domain.world.elapsed_ms) + int(domain.definitions.observation_ms)) or (int(data.next_observation_ms) - int(site.opened_ms)) % int(domain.definitions.observation_ms) != 0: return false
	for value: Variant in site.source_events.values():
		if not SimInventory._nonempty(value): return false
	var purpose: Variant = data.purposes[domain.definitions.purpose.actor]
	if not Shape.keys(purpose, PURPOSE) or purpose.actor != domain.definitions.purpose.actor or domain.home(str(purpose.actor)) != purpose.region or purpose.site != rule.id or purpose.clue_event != site.source_events[purpose.actor] or purpose.phase not in ["waiting", "outbound", "taking", "returning", "done"] or purpose.goal not in ["seek", "return"] or purpose.last_result not in RESULTS: return false
	if not Shape.count(purpose.last_ms, int(site.opened_ms), int(domain.world.elapsed_ms)) or not Shape.count(purpose.retry_ms, int(purpose.last_ms)) or not purpose.trip is String or not purpose.artifact_action is String or not purpose.observed_event is String: return false
	if not str(purpose.trip).is_empty() and not data.trips.has(purpose.trip): return false
	if purpose.phase == "taking" and (purpose.artifact_action == "" or purpose.observed_event == "" or purpose.goal != "seek"): return false
	if purpose.phase == "done" and (purpose.goal != "return" or purpose.last_result != "returned"): return false
	var last_end: int = int(site.opened_ms)
	for number: int in range(1, int(data.next_id)):
		var id: String = "field:trip:%d" % number
		var row: Variant = data.trips.get(id)
		if not _trip(row, domain) or row.id != id or row.number != number or row.actor != purpose.actor or row.region != purpose.region or row.site != purpose.site or int(row.started_ms) < last_end: return false
		last_end = int(domain.world.elapsed_ms) + 1 if row.status == "active" else int(row.finished_ms)
		if row.status == "active" and (purpose.trip != id or purpose.phase != row.leg): return false
	if purpose.phase in ["outbound", "returning"] and data.trips.get(purpose.trip, {}).get("status") != "active": return false
	return true


static func _trip(row: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(row, TRIP) or not SimInventory._nonempty(row.id) or not Shape.count(row.number, 1, int(domain.definitions.max_trips)) or not SimInventory._nonempty(row.actor) or not SimInventory._nonempty(row.region) or not SimInventory._nonempty(row.site) or row.leg not in ["outbound", "returning"] or row.status not in ["active", "completed", "cancelled"] or row.previous_autonomous != true or not row.previous_autonomous is bool: return false
	# Resolve untrusted references before speed/geometry queries can index them.
	if domain.home(str(row.actor)).is_empty() or domain.home(str(row.actor)) != row.region or row.actor != domain.definitions.purpose.actor or row.site != domain.definitions.site.id: return false
	if not Shape.count(row.started_ms, 0, int(domain.world.elapsed_ms)) or not Shape.count(row.last_ms, int(row.started_ms), int(domain.world.elapsed_ms)) or not Shape.position_valid(row.origin) or not Shape.cell_valid(row.destination) or not Shape.position_valid(row.segment_from) or not row.waypoints is Array or row.waypoints.is_empty() or row.waypoints.size() > int(domain.definitions.navigation_budget) or not row.path is Array or not Shape.count(row.step_index, 0, row.waypoints.size()) or not Shape.count(row.segment_started_ms, int(row.started_ms), int(row.last_ms)) or not Shape.count(row.due_ms, int(row.segment_started_ms) + 1): return false
	if SnapshotValues.normalized(row.path) != SnapshotValues.normalized(row.waypoints.slice(int(row.step_index))) or not SimInventory._nonempty(row.start_event) or not row.finish_event is String or not row.reason is String: return false
	var at: Vector2i = TileGrid.world_to_cell(_point(row.origin))
	for index: int in row.waypoints.size():
		var raw: Variant = row.waypoints[index]
		if not Shape.cell_valid(raw): return false
		var next: Vector2i = SimRouteTravel.cell(raw)
		var distance: int = absi(next.x - at.x) + absi(next.y - at.y)
		if distance != 1 and not (index == 0 and distance == 0 and not _point(row.origin).is_equal_approx(TileGrid.cell_to_world(at))): return false
		if domain.world.map_data != null and absi(domain.world.map_data.get_elevation(at) - domain.world.map_data.get_elevation(next)) > 1: return false
		at = next
	if at != SimRouteTravel.cell(row.destination): return false
	var index: int = mini(int(row.step_index), row.waypoints.size() - 1)
	var origin: Vector2 = _point(row.origin)
	var started: int = int(row.started_ms)
	for step: int in range(index):
		var end: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(row.waypoints[step]))
		started += maxi(1, ceili(origin.distance_to(end) / domain.speed(str(row.actor)) * 1000.0))
		origin = end
	var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(row.waypoints[index]))
	var due: int = started + maxi(1, ceili(origin.distance_to(target) / domain.speed(str(row.actor)) * 1000.0))
	if row.segment_started_ms != started or row.due_ms != due or not _point(row.segment_from).is_equal_approx(origin): return false
	if row.status == "active":
		return row.last_ms == domain.world.elapsed_ms and row.finished_ms == -1 and row.reason == "" and row.finish_event == "" and row.stopped_ms == -1 and row.stopped_position == [] and int(row.due_ms) > int(domain.world.elapsed_ms) and not row.path.is_empty()
	if not Shape.count(row.finished_ms, int(row.started_ms), int(domain.world.elapsed_ms)) or row.last_ms != row.finished_ms or not Shape.count(row.stopped_ms, int(row.segment_started_ms), mini(int(row.finished_ms), int(row.due_ms))) or not Shape.position_valid(row.stopped_position) or row.finish_event == "" or row.reason not in REASONS: return false
	if row.status == "completed": return row.reason == "arrived" and row.path.is_empty() and row.step_index == row.waypoints.size() and row.finished_ms == due and row.stopped_ms == due and _point(row.stopped_position).is_equal_approx(target)
	if row.reason == "arrived" or row.path.is_empty(): return false
	var ratio: float = float(int(row.stopped_ms) - started) / float(due - started)
	return row.reason == "displaced" or _point(row.stopped_position).is_equal_approx(origin.lerp(target, ratio))


static func cross_valid(domain: RefCounted) -> bool:
	if not validate(domain.to_dict(), domain): return false
	var ring: Dictionary = domain.world.artifacts.objects.get(str(domain.definitions.site.object), {})
	for id: String in domain.world.artifacts.objects:
		if domain.world.artifacts.objects[id].definition == domain.definitions.site.object_definition and (id != domain.definitions.site.object or domain.sites.is_empty()): return false
	if domain.sites.is_empty(): return ring.is_empty() and not _any_field_event(domain)
	if ring.get("definition") != domain.definitions.site.object_definition or domain.world.services == null: return false
	var site: Dictionary = domain.sites[domain.definitions.site.id]
	if not _custody_valid(domain): return false
	for actor: String in site.source_events:
		if domain.home(actor).is_empty() or not _event(domain, str(site.source_events[actor]), "field_origin_clue", actor, "", int(site.opened_ms), {"site": site.id, "cell": site.cell, "label": domain.definitions.site.label, "basis": "opening_testimony"}): return false
	var memory: SimSocialMemory = domain.world.services.social
	var shared: Dictionary = {}
	for event: Dictionary in memory.events:
		if event.kind == "field_site_observed":
			if not _observation(domain, event): return false
		elif event.kind == "field_clue_shared":
			if not _shared(domain, event, shared): return false
		elif event.kind == "field_origin_clue" and site.source_events.get(event.actor) != event.id: return false
		elif event.kind in ["field_departed", "field_journey_ended"]:
			var id: String = str(event.details.get("participants", {}).get("trip", ""))
			var row: Dictionary = domain.trips.get(id, {})
			if row.get("start_event" if event.kind == "field_departed" else "finish_event") != event.id: return false
	for decision: Dictionary in memory.requests.values():
		if decision.task == "field_clue" and decision.status == "accepted" and not shared.has(decision.id): return false
	var purpose: Dictionary = domain.purposes[domain.definitions.purpose.actor]
	if domain._known_event(str(purpose.actor), str(purpose.site)).is_empty(): return false
	if purpose.observed_event != "":
		var observed: Dictionary = memory.observation(str(purpose.actor), str(purpose.observed_event))
		if observed.get("kind") != "field_site_observed" or observed.actor != purpose.actor or observed.details.site != purpose.site: return false
	if purpose.artifact_action != "":
		var job: Dictionary = domain.world.artifacts.active.get(purpose.actor, {})
		if job.get("id") != purpose.artifact_action: job = domain._artifact_result(str(purpose.artifact_action))
		if job.get("object") != domain.definitions.site.object or job.get("actor") != purpose.actor or job.get("verb") != "take": return false
		if purpose.phase == "taking" and domain.world.artifacts.active.get(purpose.actor, {}).get("id") != purpose.artifact_action: return false
	for row: Dictionary in domain.trips.values():
		if not _cross_trip(domain, row): return false
	return _custody_at(domain, int(domain.world.elapsed_ms)) == {"region": ring.region, "container": ring.container}


static func _cross_trip(domain: RefCounted, row: Dictionary) -> bool:
	if not _event(domain, str(row.start_event), "field_departed", str(row.actor), "", int(row.started_ms), {"site": row.site, "trip": row.id, "leg": row.leg, "origin": row.origin, "destination": row.destination, "waypoints": row.waypoints, "previous_autonomous": row.previous_autonomous}): return false
	var expected: Array = domain.sites[row.site].cell if row.leg == "outbound" else domain.world.regions[row.region].places[domain.definitions.purpose.return_place].cell
	if SnapshotValues.normalized(row.destination) != SnapshotValues.normalized(expected): return false
	if row.status == "active":
		var person: Dictionary = domain.body(str(row.actor))
		if person.is_empty() or bool(person.autonomous) or not person.active.is_empty() or not domain.world.actor_controls(str(row.actor), "action") or not domain.world.actor_controls(str(row.actor), "motion") or domain.world.body_action_owns(str(row.actor), &"field_opportunities") or not SimRouteTravel.valid_segment(row, person, int(domain.world.elapsed_ms), domain.speed(str(row.actor))) or not domain._continuation_reason(row).is_empty(): return false
	else:
		if not _event(domain, str(row.finish_event), "field_journey_ended", str(row.actor), "", int(row.finished_ms), {"site": row.site, "trip": row.id, "status": row.status, "reason": row.reason, "stopped_ms": row.stopped_ms, "position": row.stopped_position}): return false
	return true


static func _observation(domain: RefCounted, event: Dictionary) -> bool:
	var details: Dictionary = event.details.get("participants", {})
	if not Shape.keys(details, ["site", "cell", "label", "outcome", "observer_position", "level", "at_ms"]) or details.site != domain.definitions.site.id or details.label != domain.definitions.site.label or SnapshotValues.normalized(details.cell) != SnapshotValues.normalized(domain.sites[details.site].cell) or details.outcome not in ["present", "empty"] or not Shape.position_valid(details.observer_position) or not Shape.count(details.at_ms, int(domain.sites[details.site].opened_ms), int(domain.world.elapsed_ms)) or not Shape.count(details.level, 0, WorldMapData.ELEVATION_LEVELS - 1): return false
	var from: Vector2 = _point(details.observer_position)
	var to: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(details.cell))
	if from.distance_to(to) > float(domain.definitions.observation_cells) * TileGrid.TILE_SIZE + 0.001 or Space.level(domain.world, from) != details.level or Space.level(domain.world, to) != details.level: return false
	var custody: Dictionary = _custody_at(domain, int(details.at_ms))
	if custody.is_empty(): return false
	var present: bool = custody.region == domain.sites[details.site].region and custody.container == domain.sites[details.site].container
	if present != (details.outcome == "present"): return false
	var payload: Dictionary = details.duplicate(true)
	payload.erase("at_ms")
	return _event(domain, str(event.id), "field_site_observed", str(event.actor), "", int(details.at_ms), payload)


static func _shared(domain: RefCounted, event: Dictionary, used: Dictionary) -> bool:
	var details: Dictionary = event.details.get("participants", {})
	if not Shape.keys(event.details, ["participants", "private"]) or not Shape.keys(event.details.private, ["decision"]) or not Shape.keys(details, ["site", "cell", "label", "source_event", "at_ms", "requester_position", "responder_position", "level"]) or details.site != domain.definitions.site.id or details.label != domain.definitions.site.label or SnapshotValues.normalized(details.cell) != SnapshotValues.normalized(domain.sites[details.site].cell) or not Shape.count(details.at_ms, int(domain.sites[details.site].opened_ms), int(domain.world.elapsed_ms)) or used.has(event.details.private.decision): return false
	if not Shape.position_valid(details.requester_position) or not Shape.position_valid(details.responder_position) or not Shape.count(details.level, 0, WorldMapData.ELEVATION_LEVELS - 1): return false
	var from: Vector2 = _point(details.requester_position)
	var to: Vector2 = _point(details.responder_position)
	if from.distance_to(to) > minf(float(domain.definitions.interaction_px), float(domain.world._content.interaction_requests.communication_cells) * TileGrid.TILE_SIZE) + 0.001 or Space.level(domain.world, from) != details.level or Space.level(domain.world, to) != details.level: return false
	var memory: SimSocialMemory = domain.world.services.social
	var source: Dictionary = memory.observation(str(event.actor), str(details.source_event))
	var heard: Dictionary = memory.observation(str(event.target), str(details.source_event))
	if source.is_empty() or heard.is_empty() or source.get("kind") not in ["field_origin_clue", "field_site_observed", "field_clue_shared"] or source.details.get("site") != details.site or SnapshotValues.normalized(source.details) != SnapshotValues.normalized(heard.details) or int(source.tick) > int(event.tick): return false
	if not Shape.count(source.details.get("at_ms"), int(domain.sites[details.site].opened_ms), int(details.at_ms)): return false
	var decision: Dictionary = {}
	for entry: Dictionary in memory.requests.values():
		if entry.id == event.details.private.decision: decision = entry
	if decision.get("task") != "field_clue" or decision.get("status") != "accepted" or decision.get("requester") != event.target or decision.get("responder") != event.actor or decision.get("tick") != event.tick or not Shape.same_record(decision.context.terms, {"site": details.site, "source_event": details.source_event}): return false
	if event.witnesses != [] or event.tick != floori(float(details.at_ms) / 60000.0): return false
	used[decision.id] = true
	return true


static func _custody_valid(domain: RefCounted) -> bool:
	var rule: Dictionary = domain.definitions.site
	var previous_ms: int = int(domain.sites[rule.id].opened_ms)
	for event: Dictionary in domain.world.artifacts.events:
		if event.object != rule.object: continue
		if int(event.started_ms) < int(domain.sites[rule.id].opened_ms) or int(event.at_ms) < previous_ms: return false
		previous_ms = int(event.at_ms)
	var custody: Dictionary = _custody_at(domain, int(domain.world.elapsed_ms))
	if custody.is_empty(): return false
	var item: Dictionary = domain.world.artifacts.objects[rule.object]
	return item.region == custody.region and item.container == custody.container


static func _custody_at(domain: RefCounted, at_ms: int) -> Dictionary:
	var state: Dictionary = SimArtifacts.Schema.field_custody(domain.world.artifacts, at_ms)
	return {} if state.is_empty() else {"region": state.region, "container": state.container}


static func _event(domain: RefCounted, id: String, kind: String, actor: String, target: String, at_ms: int, details: Dictionary) -> bool:
	if domain.world.services == null: return false
	var memory: SimSocialMemory = domain.world.services.social
	var event: Dictionary = memory.objective_event(id)
	var payload: Dictionary = details.duplicate(true)
	payload["at_ms"] = at_ms
	return event.get("kind") == kind and event.get("actor") == actor and event.get("target") == target and event.get("tick") == floori(float(at_ms) / 60000.0) and event.get("witnesses") == [] and SnapshotValues.normalized(event.get("details")) == SnapshotValues.normalized({"participants": payload}) and memory.saw(actor, id) and (target == "" or memory.saw(target, id))


static func _any_field_event(domain: RefCounted) -> bool:
	if domain.world.services == null: return false
	for event: Dictionary in domain.world.services.social.events:
		if str(event.kind).begins_with("field_"): return true
	return false


static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
