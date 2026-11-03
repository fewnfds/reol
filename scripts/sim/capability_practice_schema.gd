extends RefCounted
## Proof of one real paid practice. Old techniques remain with their owners.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
const TOP: Array[String] = ["version", "next_id", "active", "records"]
const JOB: Array[String] = ["id", "number", "actor", "region", "node", "origin", "anchor", "direction", "started_ms", "complete_ms", "last_ms", "phase", "step_index", "path", "segment_started_ms", "segment_from", "due_ms", "qi_spent", "stamina_spent", "previous_autonomous", "status", "reason", "finished_ms", "stopped_ms", "stopped_position", "start_event", "finish_event", "milestones"]
const REASONS: Array[String] = ["cancelled", "control_lost", "occupied", "personal_need", "health", "displaced", "blocked", "hostile_warning", "struck", "manual_override", "completed"]


static func validate(data: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(data, TOP) or not Shape.count(data.version, 1, 1) or not Shape.count(data.next_id, 1, int(domain.definitions.max_records) + 1) or not data.active is Dictionary or not data.records is Dictionary or data.active.size() + data.records.size() != int(data.next_id) - 1: return false
	var allocated: Dictionary = {}
	for actor: Variant in data.active:
		var row: Variant = data.active[actor]
		if not _job(row, domain) or row.actor != actor or row.status != "active" or allocated.has(row.id): return false
		allocated[row.id] = row
	for id: Variant in data.records:
		var row: Variant = data.records[id]
		if not _job(row, domain) or row.id != id or row.status == "active" or allocated.has(id): return false
		allocated[id] = row
	var prior_start: int = 0
	var intervals: Dictionary = {}
	var successes: Dictionary = {}
	for number: int in range(1, int(data.next_id)):
		var id: String = "practice:%d" % number
		var row: Dictionary = allocated.get(id, {})
		if row.is_empty() or row.number != number or int(row.started_ms) < prior_start: return false
		prior_start = int(row.started_ms)
		var actor_node: String = str(row.actor) + ":" + str(row.node)
		if successes.has(actor_node): return false
		if row.status == "completed": successes[actor_node] = row.id
		var end: int = int(domain.world.elapsed_ms) + 1 if row.status == "active" else int(row.finished_ms)
		if intervals.has(row.actor) and int(row.started_ms) < int(intervals[row.actor]): return false
		intervals[row.actor] = end
	return true


static func _job(row: Variant, domain: RefCounted) -> bool:
	if not Shape.keys(row, JOB) or not SimInventory._nonempty(row.id) or not Shape.count(row.number, 1) or row.id != "practice:%d" % int(row.number) or not SimInventory._nonempty(row.actor) or not SimInventory._nonempty(row.region) or not domain.definitions.nodes.has(row.node) or row.status not in ["active", "completed", "cancelled"] or not row.previous_autonomous is bool: return false
	var rule: Dictionary = domain.definitions.nodes[row.node]
	if not Shape.position_valid(row.origin) or not Shape.cell_valid(row.anchor) or TileGrid.world_to_cell(_point(row.origin)) != SimRouteTravel.cell(row.anchor) or not _direction(row.direction, rule) or not Shape.position_valid(row.segment_from): return false
	if not Shape.count(row.started_ms, 0, int(domain.world.elapsed_ms)) or not Shape.count(row.complete_ms, int(row.started_ms) + domain.duration(str(row.node)), int(row.started_ms) + domain.duration(str(row.node))) or not Shape.count(row.last_ms, int(row.started_ms), int(domain.world.elapsed_ms)) or not Shape.count(row.segment_started_ms, int(row.started_ms), int(row.last_ms)) or not Shape.count(row.due_ms, int(row.started_ms) + 1) or not Shape.count(row.finished_ms, -1, int(domain.world.elapsed_ms)): return false
	if row.qi_spent != rule.qi or row.stamina_spent != rule.stamina or not Shape.count(row.qi_spent, 1) or not Shape.count(row.stamina_spent, 1) or not SimInventory._nonempty(row.start_event) or not row.finish_event is String or not row.reason is String or row.phase not in ["prepare", "walk", "settle"] or not Shape.count(row.step_index, 0, int(rule.steps)) or not row.path is Array or not row.milestones is Array: return false
	if row.status == "active":
		if row.reason != "" or row.finished_ms != -1 or row.stopped_ms != -1 or row.stopped_position != [] or row.finish_event != "" or row.last_ms != domain.world.elapsed_ms or int(row.complete_ms) <= int(domain.world.elapsed_ms) or int(row.due_ms) <= int(domain.world.elapsed_ms): return false
	else:
		if row.finished_ms != row.last_ms or int(row.finished_ms) < int(row.started_ms) or int(row.finished_ms) > int(row.complete_ms) or row.finish_event == "" or row.reason not in REASONS or not Shape.count(row.stopped_ms, int(row.started_ms), int(row.finished_ms)) or not Shape.position_valid(row.stopped_position): return false
		if row.status == "completed" and (row.reason != "completed" or row.finished_ms != row.complete_ms or row.phase != "settle" or row.step_index != rule.steps): return false
		if row.status == "cancelled" and row.reason == "completed": return false
	if row.path.size() != int(rule.steps) - int(row.step_index): return false
	for index: int in row.path.size():
		if not Shape.cell_valid(row.path[index]) or SimRouteTravel.cell(row.path[index]) != SimRouteTravel.cell(domain._target_cell(row, int(row.step_index) + index)): return false
	var walk_start: int = int(row.started_ms) + int(rule.prepare_ms)
	var walk_end: int = walk_start + int(rule.steps) * int(rule.step_ms)
	if row.phase == "prepare":
		if row.step_index != 0 or row.segment_started_ms != row.started_ms or _point(row.segment_from).distance_to(_point(row.origin)) > 0.01 or row.due_ms != walk_start or not row.milestones.is_empty(): return false
	elif row.phase == "walk":
		var index: int = int(row.step_index)
		var expected_start: int = walk_start + index * int(rule.step_ms)
		var expected_from: Vector2 = _point(row.origin) if index == 0 else TileGrid.cell_to_world(SimRouteTravel.cell(domain._target_cell(row, index - 1)))
		if index >= int(rule.steps) or row.segment_started_ms != expected_start or row.due_ms != expected_start + int(rule.step_ms) or _point(row.segment_from).distance_to(expected_from) > 0.01 or row.milestones.size() != index + 1: return false
	else:
		if row.step_index != rule.steps or row.segment_started_ms != walk_end or row.due_ms != row.complete_ms or _point(row.segment_from).distance_to(TileGrid.cell_to_world(SimRouteTravel.cell(row.anchor))) > 0.01 or row.milestones.size() != int(rule.steps) + 1: return false
	# A cancelled process may retain its last valid phase if cancellation won
	# a boundary. An active process must already have crossed every due stage.
	if row.status == "active" and int(row.last_ms) < int(row.segment_started_ms): return false
	if row.status != "active":
		if row.phase == "prepare" and row.stopped_ms != row.started_ms: return false
		if row.phase == "settle" and row.stopped_ms != walk_end: return false
		if row.phase == "walk" and not Shape.count(row.stopped_ms, int(row.segment_started_ms), mini(int(row.finished_ms), int(row.due_ms))): return false
	for index: int in row.milestones.size():
		var step: Variant = row.milestones[index]
		if not Shape.keys(step, ["phase", "step_index", "at_ms", "position", "event"]) or step.step_index != index or step.phase != ("settle" if index == int(rule.steps) else "walk") or step.at_ms != walk_start + index * int(rule.step_ms) or not Shape.position_valid(step.position) or not SimInventory._nonempty(step.event) or int(step.at_ms) > int(row.last_ms): return false
		if _point(step.position).distance_to(domain.expected_position(row, int(step.at_ms))) > 0.01: return false
	return true


static func cross_valid(domain: RefCounted) -> bool:
	if not validate(domain.to_dict(), domain): return false
	if domain.world.conflicts == null or domain.world.spirit_sources == null: return domain.active.is_empty() and domain.records.is_empty()
	var jobs: Array[Dictionary] = []
	for row: Dictionary in domain.records.values(): jobs.append(row)
	for row: Dictionary in domain.active.values(): jobs.append(row)
	var events: Dictionary = {}
	for row: Dictionary in jobs:
		if not _cross_job(row, domain, events): return false
	for region: String in domain.world.regions:
		var sim: VillageSimulation = domain.world.regions[region]
		for event: Dictionary in sim.social.events:
			if event.kind in ["capability_practice_started", "capability_practice_progressed", "capability_practice_finished"] and not events.has(region + ":" + str(event.id)): return false
	return _historical_exclusion(jobs, domain)


static func _cross_job(row: Dictionary, domain: RefCounted, used: Dictionary) -> bool:
	if domain.home(str(row.actor)) != row.region or not domain.prerequisite(str(row.actor), str(row.node), int(row.started_ms)): return false
	var sim: VillageSimulation = domain.world.regions[row.region]
	var person: Dictionary = sim.actors[row.actor]
	var definition: PawnDef = sim._content.get_pawn(StringName(person.definition_id))
	if definition == null or int(row.stamina_spent) > definition.max_stamina or int(row.qi_spent) > definition.max_qi: return false
	var neighbor: Vector2i = SimRouteTravel.cell(row.anchor) + SimRouteTravel.cell(row.direction)
	if not Shape.cell_valid([neighbor.x, neighbor.y]): return false
	if domain.world.map_data != null and (Space.level(domain.world, _point(row.origin)) != Space.level(domain.world, TileGrid.cell_to_world(neighbor))): return false
	if not _event(domain, row, str(row.start_event), "capability_practice_started", int(row.started_ms), {"practice": row.id, "node": row.node, "origin": row.origin, "anchor": row.anchor, "direction": row.direction, "complete_ms": row.complete_ms, "qi_spent": row.qi_spent, "stamina_spent": row.stamina_spent}, used): return false
	for step: Dictionary in row.milestones:
		if not _event(domain, row, str(step.event), "capability_practice_progressed", int(step.at_ms), {"practice": row.id, "node": row.node, "phase": step.phase, "step_index": step.step_index, "position": step.position}, used): return false
	if row.status == "active":
		if bool(person.autonomous) or not person.active.is_empty() or not domain.world.actor_controls(str(row.actor), "action") or not domain.world.actor_controls(str(row.actor), "motion") or domain.world.body_action_owns(str(row.actor), &"capability_practice") or not domain._at_expected_position(row) or not domain._continuation_reason(row).is_empty(): return false
	else:
		var ended: Dictionary = sim.social._event_by_id.get(str(row.finish_event), {})
		var position: Variant = ended.get("details", {}).get("participants", {}).get("position")
		if not Shape.position_valid(position) or SnapshotValues.normalized(position) != SnapshotValues.normalized(row.stopped_position) or not _event(domain, row, str(row.finish_event), "capability_practice_finished", int(row.finished_ms), {"practice": row.id, "node": row.node, "status": row.status, "reason": row.reason, "step_index": row.step_index, "stopped_ms": row.stopped_ms, "position": position}, used): return false
		if row.status == "completed" and _point(position).distance_to(domain.expected_position(row, int(row.complete_ms))) > 0.01: return false
		if row.reason != "displaced" and _point(position).distance_to(domain.expected_position(row, int(row.stopped_ms))) > 0.01: return false
	var baseline: Dictionary = domain.world.spirit_sources.qi_baselines.get(row.actor, {})
	if baseline.is_empty() or int(baseline.get("at_ms", SimInventory.MAX_COUNT)) > int(row.started_ms) or int(baseline.get("practice_floor", SimInventory.MAX_COUNT)) > int(row.number): return false
	return true


static func _historical_exclusion(jobs: Array[Dictionary], domain: RefCounted) -> bool:
	var intervals: Array[Dictionary] = []
	var sources: Array = domain.world.spirit_sources.records.values()
	sources.append_array(domain.world.spirit_sources.active.values())
	for row: Dictionary in sources: intervals.append({"actor": row.actor, "start": int(row.started_ms), "end": int(row.get("finished_ms", int(domain.world.elapsed_ms) + 1))})
	for row: Dictionary in domain.world.conflicts.conflicts.values():
		for actor: String in row.people: intervals.append({"actor": actor, "start": int(row.started_ms), "end": int(row.ended_ms) if int(row.ended_ms) >= 0 else int(domain.world.elapsed_ms) + 1})
		var withdrawal: Dictionary = row.withdrawal
		if not withdrawal.is_empty(): intervals.append({"actor": withdrawal.actor, "start": int(row.ended_ms), "end": int(withdrawal.finished_ms) if withdrawal.status == "completed" else int(domain.world.elapsed_ms) + 1})
	for row: Dictionary in domain.world.conflicts.lessons.values():
		for actor: String in [str(row.teacher), str(row.pupil)]: intervals.append({"actor": actor, "start": int(row.started_ms), "end": int(row.finished_ms) if row.status != "active" else int(domain.world.elapsed_ms) + 1})
	var artifact_jobs: Array = domain.world.artifacts.events.duplicate()
	artifact_jobs.append_array(domain.world.artifacts.active.values())
	for row: Dictionary in artifact_jobs:
		var end: int = int(row.get("at_ms", row.get("due_ms", 0)))
		intervals.append({"actor": row.actor, "start": int(row.started_ms), "end": end})
		if not str(row.get("method", {}).get("guide", "")).is_empty(): intervals.append({"actor": row.method.guide, "start": int(row.started_ms), "end": end})
	for row: Dictionary in jobs:
		var end: int = int(row.finished_ms) if row.status != "active" else int(domain.world.elapsed_ms) + 1
		for interval: Dictionary in intervals:
			if interval.actor == row.actor and int(row.started_ms) < int(interval.end) and int(interval.start) < end: return false
	return true


static func _event(domain: RefCounted, row: Dictionary, id: String, kind: String, at_ms: int, details: Dictionary, used: Dictionary) -> bool:
	var sim: VillageSimulation = domain.world.regions[row.region]
	var event: Dictionary = sim.social._event_by_id.get(id, {})
	var key: String = str(row.region) + ":" + id
	var payload: Dictionary = details.duplicate(true)
	payload["at_ms"] = at_ms
	if used.has(key) or event.get("kind") != kind or event.get("actor") != row.actor or event.get("target") != "" or event.get("witnesses") != [] or event.get("tick") != floori(float(at_ms) / 60000.0) or SnapshotValues.normalized(event.get("details")) != SnapshotValues.normalized({"participants": payload}) or not sim.social.knowledge.get(row.actor, {}).get(id, {}).get("direct", false): return false
	used[key] = row.id
	return true


static func _direction(value: Variant, rule: Dictionary) -> bool:
	if not value is Array or value.size() != 2 or not Shape.count(value[0], -1, 1) or not Shape.count(value[1], -1, 1): return false
	for direction: Array in rule.directions:
		if int(value[0]) == int(direction[0]) and int(value[1]) == int(direction[1]): return true
	return false


static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
