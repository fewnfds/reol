class_name SimFieldOpportunities
extends RefCounted
## One physical landmark and one person's finite intention. The original
## bodies, artifact custody, needs and attributed memories stay authoritative.

const VERSION: int = 1
const NEVER: int = 0x3fffffffffffffff
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/field_opportunity_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const TASK: String = "field_clue"
var definitions: Dictionary = {}
var sites: Dictionary = {}
var purposes: Dictionary = {}
var trips: Dictionary = {}
var next_id: int = 1
var next_observation_ms: int = 0
var _handed_off: Dictionary = {}
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref() if _owner != null else null


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "site", "purpose", "opening_knowers", "navigation_radius", "navigation_budget", "search_radius", "observation_cells", "observation_ms", "interaction_px", "max_trips", "policy", "labels"]) or not Shape.count(data.version, VERSION, VERSION): return false
	if not Shape.keys(data.site, ["id", "label", "region", "container", "object", "object_definition", "minimum_separation", "offsets"]) or not Shape.keys(data.purpose, ["actor", "return_place", "delay_ms", "retry_ms"]): return false
	for field: String in ["id", "label", "region", "container", "object", "object_definition"]:
		if not SimInventory._nonempty(data.site[field]): return false
	if data.site.container != "site:" + str(data.site.id) or not Shape.count(data.site.minimum_separation, 8, 64) or not data.site.offsets is Array or data.site.offsets.is_empty() or data.site.offsets.size() > 16: return false
	for offset: Variant in data.site.offsets:
		if not Shape.cell_valid(offset, true): return false
	if not SimInventory._nonempty(data.purpose.actor) or not SimInventory._nonempty(data.purpose.return_place) or not Shape.count(data.purpose.delay_ms, 1, 86400000) or not Shape.count(data.purpose.retry_ms, 1, 86400000): return false
	if not SimEmbodiment._unique_texts(data.opening_knowers) or data.opening_knowers.is_empty() or data.opening_knowers.size() > 8 or not data.opening_knowers.has(data.purpose.actor): return false
	if not Shape.count(data.navigation_radius, 16, 128) or not Shape.count(data.navigation_budget, 1024, 32768) or not Shape.count(data.search_radius, 0, 12) or not Shape.count(data.observation_cells, 1, 8) or not Shape.count(data.observation_ms, 1000, 60000) or not Shape.count(data.interaction_px, 1, TileGrid.TILE_SIZE * 8) or not Shape.count(data.max_trips, 2, 128) or not data.policy is Dictionary or SimSocialMemory.new()._normalized_policy(data.policy).is_empty(): return false
	if not Shape.keys(data.labels, ["clue", "depart", "return", "present", "empty"]): return false
	for label: Variant in data.labels.values():
		if not SimInventory._nonempty(label): return false
	return true


static func empty_state() -> Dictionary:
	return {"version": VERSION, "sites": {}, "purposes": {}, "trips": {}, "next_id": 1, "next_observation_ms": 0}


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules): return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func bind_world(authority: RefCounted) -> void:
	_owner = weakref(authority)
	_handed_off.clear()


func home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].has_actor(actor): return region
	return ""


func body(actor: String) -> Dictionary:
	var region: String = home(actor)
	return world.regions[region].synchronize_actor(actor) if not region.is_empty() else {}


func spawn_opening(centers: Dictionary) -> bool:
	if world == null or world.services == null or world.artifacts == null or world.map_data == null or not sites.is_empty() or not purposes.is_empty() or not trips.is_empty() or next_id != 1 or world.elapsed_ms != world.target_ms: return false
	var rule: Dictionary = definitions.site
	var actor: String = str(definitions.purpose.actor)
	if not centers.has(rule.region) or not world.regions.has(rule.region) or home(actor).is_empty() or world.artifacts.objects.has(rule.object) or not world.regions[home(actor)].places.has(definitions.purpose.return_place): return false
	for knower: String in definitions.opening_knowers:
		if home(knower).is_empty() or not world.services.social.has_actor(knower): return false
	var cell: Vector2i = _opening_cell(centers)
	if cell.x < 0 or world.elapsed_ms > SimInventory.MAX_COUNT - int(definitions.purpose.delay_ms): return false
	var site: Dictionary = {"id": str(rule.id), "region": str(rule.region), "container": str(rule.container), "cell": [cell.x, cell.y], "opened_ms": int(world.elapsed_ms), "source_events": {}}
	# The slot must be available to the artifact validator. Nothing is narrated
	# or remembered until the sole original artifact accepts the new origin.
	sites[str(rule.id)] = site
	if not world.artifacts.spawn_field_object(str(rule.object), str(rule.object_definition), str(rule.region), str(rule.container)):
		sites.clear()
		return false
	for knower: String in definitions.opening_knowers:
		site.source_events[knower] = _record("field_origin_clue", knower, "", {"site": rule.id, "cell": site.cell, "label": rule.label, "basis": "opening_testimony"})
	purposes[actor] = {"actor": actor, "region": home(actor), "site": str(rule.id), "clue_event": str(site.source_events[actor]), "phase": "waiting", "goal": "seek", "retry_ms": int(world.elapsed_ms) + int(definitions.purpose.delay_ms), "last_ms": int(world.elapsed_ms), "last_result": "pending", "trip": "", "artifact_action": "", "observed_event": ""}
	next_observation_ms = int(world.elapsed_ms) + int(definitions.observation_ms)
	return true


func valid_slot(region: Variant, container: Variant) -> bool:
	return region is String and container is String and sites.has(str(definitions.site.id)) and sites[str(definitions.site.id)].region == region and sites[str(definitions.site.id)].container == container


func slot_cell(region: String, container: String) -> Vector2i:
	return SimRouteTravel.cell(sites[str(definitions.site.id)].cell) if valid_slot(region, container) else Vector2i(-1, -1)


func known_sites(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if world.services == null or not world.services.social.has_actor(actor): return result
	for id: String in world._sorted_keys(sites):
		if not _known_event(actor, id).is_empty(): result.append(_site_row(id))
	return result


func nearby_visible_sites(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id: String in world._sorted_keys(sites):
		if _sees(actor, TileGrid.cell_to_world(SimRouteTravel.cell(sites[id].cell))): result.append(_site_row(id))
	return result


func destination(actor: String, id: String) -> Dictionary:
	return _site_row(id) if sites.has(id) and not _known_event(actor, id).is_empty() else {}


func _site_row(id: String) -> Dictionary:
	return {"id": id, "label": str(definitions.site.label), "cell": sites[id].cell.duplicate()}


func learn_from(requester: String, responder: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms: return _reply(false, "unavailable", "先等手头的世界事务接续完。")
	if home(requester).is_empty() or home(responder).is_empty() or requester == responder: return _reply(false, "unheard", "须向眼前能够交流的人询问。")
	world.synchronize_region(home(requester))
	world.synchronize_region(home(responder))
	if not _talk(requester, responder): return _reply(false, "unheard", "距离、视线或这副身体的表达方式尚不允许当面交流。")
	if not body(requester).active.is_empty() or not body(responder).active.is_empty() or not world.native_action_allowed(requester) or not world.native_action_allowed(responder): return _reply(false, "unavailable", "先等双方停下手头的事，再谈野外旧闻。")
	var id: String = str(definitions.site.id)
	var known: Dictionary = _known_event(responder, id)
	if known.is_empty(): return _reply(false, "unheard", "对方没有自己确知来源的这处线索。")
	var sim: VillageSimulation = world.regions[home(responder)]
	var memory: SimSocialMemory = world.services.social
	var relation: Dictionary = memory.relation(responder, requester)
	var context: Dictionary = {"energy": float(body(responder).energy) / 100.0, "benevolence": float(sim.config.actor_profiles.get(responder, {}).get("benevolence", 0.5)), "affinity": relation.affinity, "reliability": relation.reliability, "terms": {"site": id, "source_event": str(known.id)}}
	var decision: Dictionary = memory.evaluate_request(requester, responder, TASK, context, definitions.policy, world.services._rng, world.current_time)
	if decision.get("status") != "accepted": return _reply(false, "refused", "对方眼下不愿分享这条旧闻。")
	for event: Dictionary in memory.events:
		if event.kind == "field_clue_shared" and event.details.get("private", {}).get("decision") == decision.id: return _reply(true, "completed", str(definitions.labels.clue))
	if not memory.knows(requester, str(known.id)): memory.learn(requester, str(known.id), responder)
	var details: Dictionary = {"site": id, "cell": sites[id].cell.duplicate(), "label": str(definitions.site.label), "source_event": str(known.id), "at_ms": int(world.elapsed_ms), "requester_position": body(requester).position.duplicate(), "responder_position": body(responder).position.duplicate(), "level": Space.level(world, SimRouteTravel.point(body(responder)))}
	var witnesses: Array[String] = []
	memory.record("field_clue_shared", responder, requester, {"participants": details, "private": {"decision": str(decision.id)}}, witnesses, world.current_time)
	world.invalidate_region(home(responder))
	return _reply(true, "completed", str(definitions.labels.clue))


func observe_site(actor: String, id: String) -> Dictionary:
	if world.elapsed_ms != world.target_ms: return _reply(false, "unavailable", "先等世界事务接续到眼下。")
	if home(actor).is_empty(): return _reply(false, "unheard", "这副身体尚不能看清这处旧址。")
	world.synchronize_region(home(actor))
	var event: String = _observe(actor, id)
	if event.is_empty(): return _reply(false, "unheard", "先实际走近同高度、无遮挡的旧址再查看。")
	var known: Dictionary = world.services.social.observation(actor, event)
	return _reply(true, "completed", str(definitions.labels["present" if known.details.outcome == "present" else "empty"]))


func owns_actor(actor: String) -> bool:
	var row: Dictionary = purposes.get(actor, {})
	return row.get("phase", "") in ["outbound", "returning"] and trips.get(row.get("trip", ""), {}).get("status") == "active"


func previous_autonomy(actor: String) -> bool:
	return owns_actor(actor) and bool(trips[purposes[actor].trip].previous_autonomous)


func route_projection(actor: String) -> Dictionary:
	if not owns_actor(actor): return {}
	var row: Dictionary = trips[purposes[actor].trip]
	return {"active": true, "id": str(row.id), "site": str(row.site), "phase": str(row.leg), "path": row.path.duplicate(true), "segment_from": row.segment_from.duplicate(), "segment_started_ms": int(row.segment_started_ms), "due_ms": int(row.due_ms), "previous_autonomous": bool(row.previous_autonomous)}


func wants_decision(actor: String, at_ms: int) -> bool:
	var row: Dictionary = purposes.get(actor, {})
	if row.is_empty() or row.phase != "waiting" or at_ms < int(row.retry_ms) or trips.size() >= int(definitions.max_trips) or _known_event(actor, str(row.site)).is_empty(): return false
	var person: Dictionary = body(actor)
	return not person.is_empty() and bool(person.autonomous) and person.active.is_empty() and _needs_met(actor) and _healthy(actor) and _no_duty(actor, at_ms) and world.native_action_allowed(actor)


func note_decision(actor: String, at_ms: int) -> void:
	if wants_decision(actor, at_ms): _handed_off[actor] = at_ms


func has_decision_work(_at_ms: int) -> bool:
	return not _handed_off.is_empty()


func consider() -> void:
	for actor: String in world._sorted_keys(_handed_off):
		if int(_handed_off[actor]) != world.elapsed_ms or not world.autonomous_decision(actor) or not wants_decision(actor, int(world.elapsed_ms)): continue
		var row: Dictionary = purposes[actor]
		if not _start_trip(row):
			row.retry_ms = int(world.elapsed_ms) + int(definitions.purpose.retry_ms)
			row.last_ms = int(world.elapsed_ms)
			row.last_result = "unreachable"
			world.regions[row.region]._choose_routine(actor, false)
	_handed_off.clear()


func next_boundary_ms() -> int:
	var boundary: int = next_observation_ms if not sites.is_empty() else NEVER
	for actor: String in purposes:
		if not owns_actor(actor): continue
		var row: Dictionary = trips[purposes[actor].trip]
		if not _continuation_reason(row).is_empty(): return int(world.elapsed_ms) + 1
		boundary = mini(boundary, SimRouteTravel.crossing_ms(row, body(actor), int(world.elapsed_ms)))
		boundary = mini(boundary, _need_boundary(actor))
	return maxi(int(world.elapsed_ms) + 1, boundary) if boundary != NEVER else NEVER


func settle_at_ms(now: int) -> void:
	for actor: String in world._sorted_keys(purposes):
		var purpose: Dictionary = purposes[actor]
		if owns_actor(actor):
			world.synchronize_region(str(purpose.region))
			var trip: Dictionary = trips[purpose.trip]
			var reason: String = _continuation_reason(trip)
			if not reason.is_empty():
				_finish_trip(trip, "cancelled", reason, now)
				continue
			world.regions[home(actor)].project_actor_route(actor, trip, now)
			trip.last_ms = now
			world.invalidate_region(str(purpose.region))
			if now >= int(trip.due_ms):
				trip.path.pop_front()
				trip.step_index = int(trip.step_index) + 1
				if trip.path.is_empty():
					_finish_trip(trip, "completed", "arrived", now)
					if trip.leg == "outbound": _arrive(purpose)
					else:
						purpose.phase = "done"
						purpose.last_result = "returned"
				else: SimRouteTravel.begin_segment(trip, body(actor), now, speed(actor))
		elif purpose.phase == "taking":
			var job: Dictionary = world.artifacts.active.get(actor, {})
			if job.get("id") == purpose.artifact_action: continue
			var result: Dictionary = _artifact_result(str(purpose.artifact_action))
			purpose.phase = "waiting"
			purpose.goal = "return" if result.get("kind") == "taken" else "seek"
			purpose.last_result = "found" if result.get("kind") == "taken" else "interrupted"
			purpose.retry_ms = now + (1 if purpose.goal == "return" else int(definitions.purpose.retry_ms))
			purpose.last_ms = now
	# Real arrival and an ordinary passer-by use the same bounded perception.
	# Query/UI methods only project the memories produced at these boundaries.
	if world.services != null and not sites.is_empty() and now >= next_observation_ms:
		# Due actions still settle first. Reject distant candidates from the
		# original accepted trajectories before integrating individual observers.
		for region: String in world.regions:
			if not world.advance_region_to_world(region): return
		_wake_idle_intentions(now)
		# Conservative padding avoids rejecting a boundary point before _sees()
		# applies the original distance/level/occlusion rules.
		var radius: float = float(definitions.observation_cells) * TileGrid.TILE_SIZE + 0.001
		var radius_squared: float = radius * radius
		for actor: String in world._actor_ids(world.regions):
			var sim: VillageSimulation = world.regions[home(actor)]
			var at: Vector2 = sim.projected_actor_position(actor)
			for id: String in sites:
				if at.distance_squared_to(TileGrid.cell_to_world(SimRouteTravel.cell(sites[id].cell))) <= radius_squared:
					_observe(actor, id)
		next_observation_ms = now + int(definitions.observation_ms)


func _wake_idle_intentions(now: int) -> void:
	# A personal intention may bring forward an otherwise distant idle poll.
	# The original chooser still decides, in the original priority order; no
	# accepted work, receipt, need or other body owner is interrupted here.
	for actor: String in world._sorted_keys(purposes):
		if int(_handed_off.get(actor, -1)) == now or not wants_decision(actor, now): continue
		var purpose: Dictionary = purposes[actor]
		purpose.retry_ms = now + int(definitions.purpose.retry_ms)
		purpose.last_ms = now
		var person: Dictionary = body(actor)
		person.retry_ms = mini(int(person.retry_ms), int(purpose.retry_ms))
		world.invalidate_region(str(purpose.region))


func cancel(actor: String, reason: String = "cancelled") -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if not owns_actor(actor): return false
	var row: Dictionary = trips[purposes[actor].trip]
	# Interruptions preserve the current authoritative point. The caller may
	# have just displaced or struck it; never project it back onto a stale leg.
	_finish_trip(row, "cancelled", _reason(reason), int(world.elapsed_ms))
	return true


func occupation_interrupted(actor: String) -> void:
	if owns_actor(actor): cancel(actor, "occupied")


func to_dict() -> Dictionary:
	return {"version": VERSION, "sites": sites.duplicate(true), "purposes": purposes.duplicate(true), "trips": trips.duplicate(true), "next_id": next_id, "next_observation_ms": next_observation_ms}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, self): return false
	sites = data.sites.duplicate(true)
	purposes = data.purposes.duplicate(true)
	trips = data.trips.duplicate(true)
	next_id = int(data.next_id)
	next_observation_ms = int(data.next_observation_ms)
	_handed_off.clear()
	return true


func cross_valid() -> bool:
	return Schema.cross_valid(self)


func speed(actor: String) -> float:
	return float(world.regions[home(actor)].motion_rules.motion.speed)


func _start_trip(purpose: Dictionary) -> bool:
	var actor: String = str(purpose.actor)
	var target: Vector2i = SimRouteTravel.cell(sites[purpose.site].cell) if purpose.goal == "seek" else SimRouteTravel.cell(world.regions[purpose.region].places[definitions.purpose.return_place].cell)
	var points: Array[Vector2i] = _find_path(SimRouteTravel.cell(body(actor).cell), target)
	if points.is_empty(): return false
	var path: Array = []
	for cell: Vector2i in points: path.append([cell.x, cell.y])
	if SimRouteTravel.point(body(actor)).is_equal_approx(TileGrid.cell_to_world(points[0])): path.pop_front()
	if path.is_empty():
		if purpose.goal == "seek": _arrive(purpose)
		else:
			purpose.phase = "done"
			purpose.last_result = "returned"
		return true
	var person: Dictionary = body(actor)
	var id: String = "field:trip:%d" % next_id
	var row: Dictionary = {"id": id, "number": next_id, "actor": actor, "region": str(purpose.region), "site": str(purpose.site), "leg": "outbound" if purpose.goal == "seek" else "returning", "started_ms": int(world.elapsed_ms), "last_ms": int(world.elapsed_ms), "origin": person.position.duplicate(), "destination": [target.x, target.y], "waypoints": path.duplicate(true), "step_index": 0, "path": path, "segment_from": person.position.duplicate(), "segment_started_ms": int(world.elapsed_ms), "due_ms": int(world.elapsed_ms), "previous_autonomous": bool(person.autonomous), "status": "active", "finished_ms": -1, "reason": "", "stopped_ms": -1, "stopped_position": [], "start_event": "", "finish_event": ""}
	SimRouteTravel.begin_segment(row, person, int(world.elapsed_ms), speed(actor))
	row.start_event = _record("field_departed", actor, "", {"site": row.site, "trip": id, "leg": row.leg, "origin": row.origin, "destination": row.destination, "waypoints": row.waypoints, "previous_autonomous": row.previous_autonomous})
	next_id += 1
	trips[id] = row
	purpose.trip = id
	purpose.phase = row.leg
	purpose.last_result = "travelling"
	purpose.last_ms = int(world.elapsed_ms)
	purpose.retry_ms = int(world.elapsed_ms) + int(definitions.purpose.retry_ms)
	person.autonomous = false
	person.goal = str(definitions.labels.depart if row.leg == "outbound" else definitions.labels["return"])
	world.invalidate_region(str(purpose.region))
	return true


func _finish_trip(row: Dictionary, status: String, reason: String, at_ms: int) -> void:
	row.status = status
	row.finished_ms = at_ms
	row.stopped_ms = int(row.last_ms)
	row.last_ms = at_ms
	row.reason = reason
	row.stopped_position = body(str(row.actor)).position.duplicate()
	row.finish_event = _record("field_journey_ended", str(row.actor), "", {"site": row.site, "trip": row.id, "status": status, "reason": reason, "stopped_ms": row.stopped_ms, "position": row.stopped_position})
	var purpose: Dictionary = purposes[row.actor]
	purpose.phase = "waiting"
	purpose.last_ms = at_ms
	purpose.last_result = "interrupted" if status == "cancelled" else "arrived"
	purpose.retry_ms = at_ms + int(definitions.purpose.retry_ms)
	var person: Dictionary = body(str(row.actor))
	person.autonomous = bool(row.previous_autonomous)
	person.retry_ms = mini(int(person.retry_ms), at_ms + 1)
	person.goal = "寻物途中暂歇，先顾眼前处境" if status == "cancelled" else "刚抵达野外寻物的去处"
	world.invalidate_region(str(row.region))
	SimActionContract.job_finished(world, "field_opportunities", row, row.actor, status, reason)


func _arrive(purpose: Dictionary) -> void:
	var actor: String = str(purpose.actor)
	var seen: String = _observe(actor, str(purpose.site))
	if seen.is_empty():
		purpose.last_result = "unreachable"
		purpose.retry_ms = int(world.elapsed_ms) + int(definitions.purpose.retry_ms)
		return
	purpose.observed_event = seen
	var known: Dictionary = world.services.social.observation(actor, seen)
	if known.details.outcome == "empty":
		purpose.goal = "return"
		purpose.last_result = "empty"
		purpose.retry_ms = int(world.elapsed_ms) + 1
		return
	if not _needs_met(actor) or not _healthy(actor) or not _no_duty(actor, int(world.elapsed_ms)):
		purpose.last_result = "interrupted"
		return
	# Same original operation as a player's take. The field route is finished
	# and releases the body first; taking belongs exclusively to artifacts.
	var result: Dictionary = world.artifacts._begin(actor, "take", str(definitions.site.object), true)
	if bool(result.get("ok", false)):
		purpose.phase = "taking"
		purpose.artifact_action = str(world.artifacts.active[actor].id)
		purpose.last_result = "taking"
	else:
		purpose.last_result = "interrupted"
		purpose.retry_ms = int(world.elapsed_ms) + int(definitions.purpose.retry_ms)
	world.invalidate_region(str(purpose.region))


func _observe(actor: String, id: String) -> String:
	if world.services == null or not sites.has(id) or not _sees(actor, TileGrid.cell_to_world(SimRouteTravel.cell(sites[id].cell))): return ""
	var item: Dictionary = world.artifacts.objects.get(str(definitions.site.object), {})
	# Only the physical slot in sight is read. An empty slot conveys neither
	# a distant holder's identity nor their present position.
	var outcome: String = "present" if item.get("region") == sites[id].region and item.get("container") == sites[id].container else "empty"
	var latest: Dictionary = {}
	for index: int in range(world.services.social.events.size() - 1, -1, -1):
		var event: Dictionary = world.services.social.events[index]
		var known: Dictionary = world.services.social.observation(actor, str(event.id))
		if known.get("kind") == "field_site_observed" and known.get("actor") == actor and known.details.get("site") == id:
			latest = known
			break
	if latest.get("details", {}).get("outcome") == outcome: return str(latest.id)
	return _record("field_site_observed", actor, "", {"site": id, "cell": sites[id].cell.duplicate(), "label": str(definitions.site.label), "outcome": outcome, "observer_position": body(actor).position.duplicate(), "level": Space.level(world, SimRouteTravel.point(body(actor)))})


func _known_event(actor: String, id: String) -> Dictionary:
	if world.services == null or not sites.has(id): return {}
	for event: Dictionary in world.services.social.events:
		var known: Dictionary = world.services.social.observation(actor, str(event.id))
		if known.get("kind") in ["field_origin_clue", "field_site_observed", "field_clue_shared"] and known.details.get("site") == id and SnapshotValues.normalized(known.details.get("cell")) == SnapshotValues.normalized(sites[id].cell): return known
	return {}


func _artifact_result(id: String) -> Dictionary:
	for event: Dictionary in world.artifacts.events:
		if event.action == id: return event
	return {}


func _sees(actor: String, point: Vector2) -> bool:
	var person: Dictionary = body(actor)
	if person.is_empty() or not bool(person.alive): return false
	var from: Vector2 = SimRouteTravel.point(person)
	return from.distance_to(point) <= float(definitions.observation_cells) * TileGrid.TILE_SIZE and world.actor_controls(actor, "action") and Space.level(world, from) == Space.level(world, point) and Space.clear_segment(world, from, point, Space.level(world, from))


func _talk(left: String, right: String) -> bool:
	if not world.actor_controls(left, "communication") or not world.actor_controls(right, "communication"): return false
	var from: Vector2 = SimRouteTravel.point(body(left))
	var to: Vector2 = SimRouteTravel.point(body(right))
	return from.distance_to(to) <= minf(float(definitions.interaction_px), float(world._content.interaction_requests.communication_cells) * TileGrid.TILE_SIZE) and Space.level(world, from) == Space.level(world, to) and Space.clear_segment(world, from, to, Space.level(world, from))


func _healthy(actor: String) -> bool:
	return world.health == null or world.health.can_fight(actor) and not world.health.blocks_channeling(actor) and not world.health.wants_decision(actor, int(world.elapsed_ms))


func _needs_met(actor: String) -> bool:
	var needs: Dictionary = world.regions[home(actor)].config.needs
	return float(body(actor).hunger) > float(needs.eat_below) and float(body(actor).energy) > float(needs.rest_below)


func _no_duty(actor: String, at_ms: int) -> bool:
	var person: Dictionary = body(actor)
	return person.receipts.is_empty() and (world.standing_work == null or world.standing_work.duty_for(actor, at_ms).is_empty()) and (world.construction == null or world.construction.duty_for(actor).is_empty()) and (world.resting == null or world.resting.duty_for(actor).is_empty()) and not SimWorkplaces.has_desk_duty(world.regions[home(actor)], actor)


func _continuation_reason(row: Dictionary) -> String:
	var actor: String = str(row.actor)
	var person: Dictionary = body(actor)
	if person.is_empty() or not bool(person.alive) or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion"): return "control_lost"
	if not person.active.is_empty() or bool(person.autonomous) or world.body_action_owns(actor, &"field_opportunities"): return "occupied"
	if not _needs_met(actor): return "personal_need"
	if not _healthy(actor): return "health"
	if not _no_duty(actor, int(world.elapsed_ms)): return "duty"
	if not SimRouteTravel.point(person).is_equal_approx(expected_position(row, int(row.last_ms))): return "displaced"
	if row.path.is_empty() or not Space.can_step(world, SimRouteTravel.cell(person.cell), SimRouteTravel.cell(row.path[0])): return "blocked"
	return ""


func expected_position(row: Dictionary, at_ms: int) -> Vector2:
	var from := Vector2(float(row.segment_from[0]), float(row.segment_from[1]))
	if row.path.is_empty(): return from
	var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(row.path[0]))
	var ratio: float = clampf(float(at_ms - int(row.segment_started_ms)) / float(maxi(1, int(row.due_ms) - int(row.segment_started_ms))), 0.0, 1.0)
	return from.lerp(target, ratio)


func _need_boundary(actor: String) -> int:
	var sim: VillageSimulation = world.regions[home(actor)]
	var person: Dictionary = body(actor)
	var result: int = NEVER
	for need: String in ["hunger", "energy"]:
		var rate: int = roundi(float(sim.config.needs.hunger_per_minute) * VillageSimulation.NEED_SCALE) if need == "hunger" else roundi(float(sim.config.needs.energy_per_minute) * VillageSimulation.NEED_SCALE) + roundi(float(sim.config.needs.work_energy_per_minute) * VillageSimulation.NEED_SCALE) + world.clothing.energy_rate(actor) + world.environment.energy_rate(actor)
		var threshold: float = float(sim.config.needs.eat_below) if need == "hunger" else float(sim.config.needs.rest_below)
		var remaining: int = maxi(0, roundi(float(person[need]) * VillageSimulation.NEED_SCALE) - roundi(threshold * VillageSimulation.NEED_SCALE))
		if rate > 0: result = mini(result, int(world.elapsed_ms) + maxi(1, ceili(float(remaining * 60000 - int(person.need_carry[need])) / rate)))
	return result


func _opening_cell(centers: Dictionary) -> Vector2i:
	var origin: Vector2i = _center(centers[definitions.site.region])
	var from_home: Dictionary = _reachable(origin)
	var from_actor: Dictionary = _reachable(SimRouteTravel.cell(body(str(definitions.purpose.actor)).cell))
	for offset: Array in definitions.site.offsets:
		var anchor: Vector2i = origin + SimRouteTravel.cell(offset)
		for radius: int in range(int(definitions.search_radius) + 1):
			for y: int in range(-radius, radius + 1):
				for x: int in range(-radius, radius + 1):
					if maxi(absi(x), absi(y)) != radius: continue
					var cell: Vector2i = anchor + Vector2i(x, y)
					if not _walkable(cell): continue
					var separated: bool = true
					for center: Variant in centers.values():
						if _center(center).distance_to(cell) < float(definitions.site.minimum_separation): separated = false
					if not separated or not from_home.has(cell) or not from_actor.has(cell): continue
					return cell
	return Vector2i(-1, -1)


func _reachable(origin: Vector2i) -> Dictionary:
	var seen: Dictionary = {}
	if not _walkable(origin): return seen
	var queue: Array[Vector2i] = [origin]
	seen[origin] = true
	var index: int = 0
	while index < queue.size() and index < int(definitions.navigation_budget):
		var at: Vector2i = queue[index]
		index += 1
		for direction: Vector2i in SimBodyGeometry.DIRECTIONS:
			var next: Vector2i = at + direction
			if seen.has(next) or seen.size() >= int(definitions.navigation_budget) or absi(next.x - origin.x) > int(definitions.navigation_radius) or absi(next.y - origin.y) > int(definitions.navigation_radius) or not SimBodyGeometry.can_step(at, direction, Vector2i.ONE, _walkable, _elevation): continue
			seen[next] = true
			queue.append(next)
	return seen


func _find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	return SimBodyGeometry.find_path(from, to, Vector2i.ONE, _walkable, _elevation, int(definitions.navigation_radius), int(definitions.navigation_budget))


func _walkable(cell: Vector2i) -> bool:
	return world.map_data != null and world.map_data.terrain_is_walkable(cell) and not Space.solid(world, cell, world.map_data.get_elevation(cell)) and (world.large_bodies == null or not world.large_bodies.blocked(cell))


func _elevation(cell: Vector2i) -> int:
	return world.map_data.get_elevation(cell) if world.map_data != null else 0


func _center(value: Variant) -> Vector2i:
	return value if value is Vector2i else SimRouteTravel.cell(value) if Shape.cell_valid(value) else Vector2i(-ReolWorld.WORLD_SIZE, -ReolWorld.WORLD_SIZE)


func _record(kind: String, actor: String, target: String, details: Dictionary) -> String:
	var payload: Dictionary = details.duplicate(true)
	payload["at_ms"] = int(world.elapsed_ms)
	var witnesses: Array[String] = []
	return world.services.social.record(kind, actor, target, {"participants": payload}, witnesses, world.current_time)


func _reason(reason: String) -> String:
	return reason if reason in Schema.REASONS else "interrupted"


func _reply(ok: bool, code: String, line: String) -> Dictionary:
	return {"ok": ok, "code": code, "line": line}
