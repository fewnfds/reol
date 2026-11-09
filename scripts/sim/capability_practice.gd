class_name SimCapabilityPractice
extends RefCounted
## One paid practice process. Original bodies and old learning remain at source.

const VERSION: int = 1
const NEVER: int = 0x3fffffffffffffff
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/capability_practice_schema.gd")
const Space = preload("res://scripts/sim/conflict_space.gd")
var definitions: Dictionary = {}
var rules: Dictionary:
	get: return definitions
var active: Dictionary = {}
var records: Dictionary = {}
var next_id: int = 1
var _owner: WeakRef
var world: RefCounted:
	get: return _owner.get_ref() if _owner != null else null


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "max_records", "nodes"]) or not Shape.count(data.version, 1, 1) or not Shape.count(data.max_records, 1, 4096) or not Shape.keys(data.nodes, ["mobile_guard"]): return false
	var node: Variant = data.nodes.mobile_guard
	if not Shape.keys(node, ["label", "requires", "prepare_ms", "step_ms", "steps", "settle_ms", "qi", "stamina", "speed_fraction", "directions"]) or not SimInventory._nonempty(node.label) or node.requires != "qi_guard": return false
	for key: String in ["prepare_ms", "step_ms", "settle_ms"]:
		if not Shape.count(node[key], 1, 3600000): return false
	if not Shape.count(node.steps, 2, 16) or int(node.steps) % 2 != 0 or not Shape.count(node.qi, 1, 1000) or not Shape.count(node.stamina, 1, 1000) or not SimSnapshotSchema._number(node.speed_fraction) or float(node.speed_fraction) <= 0.0 or float(node.speed_fraction) > 1.0 or not node.directions is Array or node.directions.size() != 4: return false
	var seen: Dictionary = {}
	for direction: Variant in node.directions:
		if not direction is Array or direction.size() != 2 or not Shape.count(direction[0], -1, 1) or not Shape.count(direction[1], -1, 1) or absi(int(direction[0])) + absi(int(direction[1])) != 1: return false
		var key: String = str(int(direction[0])) + ":" + str(int(direction[1]))
		if seen.has(key): return false
		seen[key] = true
	return true


static func empty_state() -> Dictionary:
	return {"version": VERSION, "next_id": 1, "active": {}, "records": {}}


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules): return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func bind_world(authority: RefCounted) -> void:
	_owner = weakref(authority)


func home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].actors.has(actor): return region
	return ""


func body(actor: String) -> Dictionary:
	var region: String = home(actor)
	return world.regions[region].actors[actor] if not region.is_empty() else {}


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func previous_autonomy(actor: String) -> bool:
	return bool(active.get(actor, {}).get("previous_autonomous", false))


func prerequisite(actor: String, node: String, at_ms: int) -> bool:
	if not definitions.nodes.has(node) or world.conflicts == null or body(actor).is_empty(): return false
	var required: String = str(definitions.nodes[node].requires)
	if world.conflicts.rules.backgrounds.get(str(body(actor).definition_id), []).has(required): return true
	for lesson: Dictionary in world.conflicts.lessons.values():
		if lesson.pupil == actor and lesson.status == "completed" and int(lesson.finished_ms) <= at_ms and lesson.methods.has(required): return true
	return false


func learned_record(actor: String, node: String = "mobile_guard", at_ms: int = -1) -> Dictionary:
	var cutoff: int = int(world.elapsed_ms) if at_ms < 0 else at_ms
	var found: Dictionary = {}
	for row: Dictionary in records.values():
		if row.actor != actor or row.node != node or row.status != "completed" or int(row.finished_ms) > cutoff: continue
		if found.is_empty() or int(row.finished_ms) < int(found.finished_ms) or row.finished_ms == found.finished_ms and int(row.number) < int(found.number): found = row
	return found.duplicate(true)


func learned(actor: String, node: String = "mobile_guard", at_ms: int = -1) -> bool:
	return not learned_record(actor, node, at_ms).is_empty()


func learned_at(actor: String, node: String = "mobile_guard") -> int:
	return int(learned_record(actor, node).get("finished_ms", -1))


func duration(node: String = "mobile_guard") -> int:
	if not definitions.nodes.has(node): return 0
	var rule: Dictionary = definitions.nodes[node]
	return int(rule.prepare_ms) + int(rule.step_ms) * int(rule.steps) + int(rule.settle_ms)


func readiness(actor: String, node: String = "mobile_guard") -> String:
	if not definitions.nodes.has(node) or home(actor).is_empty(): return "这种身体眼下还没有适配的行气练习。"
	if learned(actor, node): return "本人已实际练成这项用法，不必重复消耗。"
	if active.has(actor): return "本人已在练习，先接续或停下原过程。"
	var person: Dictionary = body(actor)
	if not bool(person.alive) or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not person.active.is_empty() or not world.native_action_allowed(actor): return "先完成手头的事，停稳后再练习。"
	if world.standing_work != null and not world.standing_work.duty_for(actor, int(world.elapsed_ms)).is_empty(): return "本人已答应另一项常备安排，先处理原承诺。"
	if world.conflicts != null and world.conflicts.owns_actor(actor) or world.sparring != null and world.sparring.owns_actor(actor): return "交锋或示范还没结束，眼下不宜另起练习。"
	if not _needs_met(actor): return "先吃饭或歇息，再凝神练气。"
	if world.health != null and (world.health.blocks_channeling(actor) or not world.health.can_fight(actor)): return "身体仍不适合稳定运气，先休养。"
	if not prerequisite(actor, node, int(world.elapsed_ms)): return "先亲自学会护身气障，才能尝试行步收束。"
	var rule: Dictionary = definitions.nodes[node]
	if int(person.qi) < int(rule.qi) or int(person.stamina) < int(rule.stamina): return "原灵气或体力不足，练习不会免费开始。"
	if _choose_direction(actor, node).is_empty(): return "身旁没有同高度且去回可行的一小段空地。"
	if records.size() + active.size() >= int(definitions.max_records) or world.elapsed_ms > SimInventory.MAX_COUNT - duration(node) or next_id >= SimInventory.MAX_COUNT: return "这次完整练习尚不能安排。"
	return ""


func begin(actor: String, node: String = "mobile_guard") -> Dictionary:
	if world.elapsed_ms != world.target_ms: return _reply(false, "unavailable", "先等世界事务接续到眼下，再开始练习。")
	var region: String = home(actor)
	if region.is_empty(): return _reply(false, "incapable", "这种身体还没有适配的练习。")
	world.synchronize_region(region)
	var reason: String = readiness(actor, node)
	if not reason.is_empty(): return _reply(false, "unavailable", reason)
	var direction: Array = _choose_direction(actor, node)
	if direction.is_empty() or world.spirit_sources == null or not world.spirit_sources.ensure_qi_baseline(actor): return _reply(false, "unavailable", "原身体、空地或灵气来源尚不能核清。")
	var person: Dictionary = body(actor)
	var rule: Dictionary = definitions.nodes[node]
	var id: String = "practice:%d" % next_id
	var row: Dictionary = {"id": id, "number": next_id, "actor": actor, "region": region, "node": node, "origin": person.position.duplicate(), "anchor": person.cell.duplicate(), "direction": direction, "started_ms": int(world.elapsed_ms), "complete_ms": int(world.elapsed_ms) + duration(node), "last_ms": int(world.elapsed_ms), "phase": "prepare", "step_index": 0, "path": [], "segment_started_ms": int(world.elapsed_ms), "segment_from": person.position.duplicate(), "due_ms": int(world.elapsed_ms) + int(rule.prepare_ms), "qi_spent": int(rule.qi), "stamina_spent": int(rule.stamina), "previous_autonomous": bool(person.autonomous), "status": "active", "reason": "", "finished_ms": -1, "stopped_ms": -1, "stopped_position": [], "start_event": "", "finish_event": "", "milestones": []}
	for step: int in int(rule.steps): row.path.append(_target_cell(row, step))
	# One synchronous cost allocation after all physical prerequisites succeed.
	person.qi = int(person.qi) - int(rule.qi)
	person.stamina = int(person.stamina) - int(rule.stamina)
	person.stamina_carry = 0
	person.exertion_until_ms = int(row.complete_ms) + mini(SimInventory.MAX_COUNT - int(row.complete_ms), int(world.regions[region].motion_rules.recovery.delay_ms))
	person.autonomous = false
	person.goal = "停稳调息，准备行步练气"
	row.start_event = _record(row, "capability_practice_started", {"practice": id, "node": node, "origin": row.origin, "anchor": row.anchor, "direction": direction, "complete_ms": row.complete_ms, "qi_spent": row.qi_spent, "stamina_spent": row.stamina_spent})
	active[actor] = row
	next_id += 1
	world.invalidate_region(region)
	return _reply(true, "started", "已付一次真实灵气与体力，开始调息、行步与收束；中断不退款，也不会提前学成。", id, actor)


func cancel(actor: String, reason: String = "cancelled") -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if not active.has(actor): return false
	var cause: String = "struck" if reason == "struck_by_conflict" else reason
	_finish(active[actor], "cancelled", cause if cause in Schema.REASONS and cause != "completed" else "cancelled", int(world.elapsed_ms))
	return true


func next_boundary_ms() -> int:
	var boundary: int = NEVER
	for row: Dictionary in active.values():
		if not _continuation_reason(row).is_empty() or not _at_expected_position(row) or row.phase == "walk" and not _leg_open(row): return int(world.elapsed_ms) + 1
		boundary = mini(boundary, int(row.due_ms))
		boundary = mini(boundary, _need_boundary(row))
		if row.phase == "walk": boundary = mini(boundary, SimRouteTravel.crossing_ms(row, body(str(row.actor)), int(world.elapsed_ms)))
	return boundary


func settle_at_ms(now: int) -> void:
	for actor: String in world._sorted_keys(active):
		var row: Dictionary = active[actor]
		world.synchronize_region(str(row.region))
		var reason: String = _continuation_reason(row)
		if not reason.is_empty() or not _at_expected_position(row):
			_finish(row, "cancelled", "displaced" if not _at_expected_position(row) else reason, now)
			continue
		while active.has(actor) and int(row.due_ms) <= now:
			if row.phase == "prepare":
				row.phase = "walk"
				_milestone(row, "walk", int(row.due_ms))
				_begin_leg(row, int(row.due_ms))
			elif row.phase == "walk":
				if not _leg_open(row):
					_finish(row, "cancelled", "blocked", now)
					break
				world.regions[home(actor)].project_actor_route(actor, row, int(row.due_ms))
				row.last_ms = int(row.due_ms)
				row.path.pop_front()
				row.step_index = int(row.step_index) + 1
				if row.path.is_empty():
					row.phase = "settle"
					_milestone(row, "settle", int(row.due_ms))
					row.segment_started_ms = int(row.due_ms)
					row.segment_from = body(actor).position.duplicate()
					row.due_ms = int(row.complete_ms)
					body(actor).goal = "收束行气，复盘刚才的步法"
				else:
					_milestone(row, "walk", int(row.due_ms))
					_begin_leg(row, int(row.due_ms))
			else:
				_finish(row, "completed", "completed", int(row.complete_ms))
		if not active.has(actor): continue
		if row.phase == "walk":
			if not _leg_open(row):
				_finish(row, "cancelled", "blocked", now)
				continue
			world.regions[home(actor)].project_actor_route(actor, row, now)
		row.last_ms = now
		world.invalidate_region(str(row.region))


func qi_spending(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var jobs: Array = records.values()
	jobs.append_array(active.values())
	for row: Dictionary in jobs:
		if row.actor == actor: result.append({"domain": "practice", "number": int(row.number), "at_ms": int(row.started_ms), "amount": int(row.qi_spent)})
	return result


func status(actor: String) -> Dictionary:
	var row: Dictionary = active.get(actor, {})
	if row.is_empty(): return {"active": false, "id": "", "phase": "", "remaining_ms": 0, "line": "本人已经实际练成行气护身。" if learned(actor) else "先学会护障，再用原身体实际练习。"}
	return {"active": true, "id": str(row.id), "phase": str(row.phase), "remaining_ms": maxi(0, int(row.complete_ms) - int(world.elapsed_ms)), "line": str(body(actor).goal)}


func pending(actor: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for row: Dictionary in records.values():
		if row.actor == actor: result.append(_process(str(row.id), actor))
	if active.has(actor): result.append(_process(str(active[actor].id), actor))
	return result


func observe(actor: String, process: Dictionary) -> Dictionary:
	var row: Dictionary = records.get(str(process.get("id", "")), {})
	if row.is_empty() and active.get(actor, {}).get("id") == process.get("id"): row = active[actor]
	if row.is_empty() or row.actor != actor or process.get("domain") != "capability_practice" or process.get("performer") != world.embodiment.subject_for_actor(actor): return SimInteractionRequests.result("unconfirmed", "本人没有这次练习经历。")
	return SimInteractionRequests.result("pending" if row.status == "active" else "completed" if row.status == "completed" else "cancelled", str(body(actor).goal) if row.status == "active" else "亲身完成了行步收束，可在护障动作内有限缓步。" if row.status == "completed" else "练习已中断，原支出保留，没有提前获得本领。", process)


func to_dict() -> Dictionary:
	return {"version": VERSION, "next_id": next_id, "active": active.duplicate(true), "records": records.duplicate(true)}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, self): return false
	next_id = int(data.next_id)
	active = data.active.duplicate(true)
	records = data.records.duplicate(true)
	return true


func cross_valid() -> bool:
	return Schema.cross_valid(self)


func _choose_direction(actor: String, node: String) -> Array:
	var person: Dictionary = body(actor)
	var anchor: Vector2i = SimRouteTravel.cell(person.cell)
	var level_value: int = Space.level(world, SimRouteTravel.point(person))
	for direction: Array in definitions.nodes[node].directions:
		var target: Vector2i = anchor + SimRouteTravel.cell(direction)
		if _step_open(anchor, target) and _step_open(target, anchor) and Space.level(world, TileGrid.cell_to_world(target)) == level_value and Space.clear_segment(world, SimRouteTravel.point(person), TileGrid.cell_to_world(target), level_value): return direction.duplicate()
	return []


func _step_open(from: Vector2i, target: Vector2i) -> bool:
	return not Space.solid(world, target, Space.level(world, TileGrid.cell_to_world(target))) if from == target else Space.can_step(world, from, target)


func _target_cell(row: Dictionary, index: int) -> Array:
	var anchor: Vector2i = SimRouteTravel.cell(row.anchor)
	var target: Vector2i = anchor + SimRouteTravel.cell(row.direction) if index % 2 == 0 else anchor
	return [target.x, target.y]


func _begin_leg(row: Dictionary, at_ms: int) -> void:
	row.segment_started_ms = at_ms
	row.segment_from = body(str(row.actor)).position.duplicate()
	row.due_ms = at_ms + int(definitions.nodes[row.node].step_ms)
	row.last_ms = at_ms
	body(str(row.actor)).goal = "沿身旁一小段空地缓步，保持行气收束"


func _leg_open(row: Dictionary) -> bool:
	if row.path.is_empty(): return false
	var person: Dictionary = body(str(row.actor))
	var current: Vector2i = SimRouteTravel.cell(person.cell)
	var target: Vector2i = SimRouteTravel.cell(row.path[0])
	var from: Vector2 = SimRouteTravel.point(person)
	var to: Vector2 = TileGrid.cell_to_world(target)
	return _step_open(current, target) and Space.level(world, from) == Space.level(world, to) and Space.clear_segment(world, from, to, Space.level(world, from))


func expected_position(row: Dictionary, at_ms: int) -> Vector2:
	var rule: Dictionary = definitions.nodes[row.node]
	var walk_start: int = int(row.started_ms) + int(rule.prepare_ms)
	if at_ms <= walk_start: return _point(row.origin)
	var walk_end: int = walk_start + int(rule.step_ms) * int(rule.steps)
	if at_ms >= walk_end: return TileGrid.cell_to_world(SimRouteTravel.cell(row.anchor))
	@warning_ignore("integer_division")
	var index: int = mini(int(rule.steps) - 1, (at_ms - walk_start) / int(rule.step_ms))
	var from: Vector2 = _point(row.origin) if index == 0 else TileGrid.cell_to_world(SimRouteTravel.cell(_target_cell(row, index - 1)))
	var to: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(_target_cell(row, index)))
	return from.lerp(to, float(at_ms - walk_start - index * int(rule.step_ms)) / float(rule.step_ms))


func _at_expected_position(row: Dictionary) -> bool:
	return SimRouteTravel.point(body(str(row.actor))).distance_to(expected_position(row, int(row.last_ms))) <= 0.01


func _continuation_reason(row: Dictionary) -> String:
	var actor: String = str(row.actor)
	var person: Dictionary = body(actor)
	if person.is_empty() or not bool(person.alive) or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion"): return "control_lost"
	if not person.active.is_empty() or world.body_action_owns(actor, &"capability_practice"): return "occupied"
	if not _needs_met(actor): return "personal_need"
	if world.health != null and (world.health.blocks_channeling(actor) or not world.health.can_fight(actor)): return "health"
	return ""


func _needs_met(actor: String) -> bool:
	var person: Dictionary = body(actor)
	var needs: Dictionary = world.regions[home(actor)].config.needs
	return float(person.hunger) > float(needs.eat_below) and float(person.energy) > float(needs.rest_below)


func _need_boundary(row: Dictionary) -> int:
	var sim: VillageSimulation = world.regions[row.region]
	var person: Dictionary = body(str(row.actor))
	var result: int = NEVER
	for need: String in ["hunger", "energy"]:
		var rate: int = roundi(float(sim.config.needs.hunger_per_minute) * VillageSimulation.NEED_SCALE) if need == "hunger" else roundi(float(sim.config.needs.energy_per_minute) * VillageSimulation.NEED_SCALE) + world.clothing.energy_rate(str(row.actor)) + world.environment.energy_rate(str(row.actor))
		var threshold: float = float(sim.config.needs.eat_below) if need == "hunger" else float(sim.config.needs.rest_below)
		var remaining: int = maxi(0, roundi(float(person[need]) * VillageSimulation.NEED_SCALE) - roundi(threshold * VillageSimulation.NEED_SCALE))
		if rate > 0: result = mini(result, int(world.elapsed_ms) + maxi(1, ceili(float(remaining * 60000 - int(person.need_carry[need])) / rate)))
	return result


func _milestone(row: Dictionary, phase_value: String, at_ms: int) -> void:
	var entry: Dictionary = {"phase": phase_value, "step_index": int(row.step_index), "at_ms": at_ms, "position": body(str(row.actor)).position.duplicate(), "event": ""}
	entry.event = _record_at(row, "capability_practice_progressed", {"practice": row.id, "node": row.node, "phase": phase_value, "step_index": row.step_index, "position": entry.position}, at_ms)
	row.milestones.append(entry)


func _finish(row: Dictionary, status_value: String, reason: String, at_ms: int) -> void:
	if not active.has(row.actor) or active[row.actor].id != row.id: return
	row.status = status_value
	row.reason = reason
	row.finished_ms = at_ms
	# last_ms also advances while standing still. Only actual motion determines
	# its stopping time, so an extra observation cannot rewrite a finished proof.
	# A blocked/interrupted walking leg stays at the last validated projection;
	# never extrapolate it through the new obstacle or lost movement authority.
	row.stopped_ms = _movement_stopped_ms(row)
	row.stopped_position = body(str(row.actor)).position.duplicate()
	row.last_ms = at_ms
	row.finish_event = _record_at(row, "capability_practice_finished", {"practice": row.id, "node": row.node, "status": status_value, "reason": reason, "step_index": row.step_index, "stopped_ms": row.stopped_ms, "position": row.stopped_position}, at_ms)
	records[row.id] = row
	active.erase(row.actor)
	var person: Dictionary = body(str(row.actor))
	person.autonomous = bool(row.previous_autonomous)
	person.goal = "亲身完成行气护身练习，保留原支出与经历" if status_value == "completed" else "练习中断，先处理眼下身体和事务"
	person.retry_ms = at_ms + mini(SimInventory.MAX_COUNT - at_ms, int(world.regions[row.region].config.decision_interval) * 60000)
	world.invalidate_region(str(row.region))
	SimActionContract.job_finished(world, "capability_practice", row, row.actor, status_value, reason)


func _movement_stopped_ms(row: Dictionary) -> int:
	if row.phase == "prepare": return int(row.started_ms)
	if row.phase == "settle":
		var rule: Dictionary = definitions.nodes[row.node]
		return int(row.started_ms) + int(rule.prepare_ms) + int(rule.step_ms) * int(rule.steps)
	return int(row.last_ms)


func _record(row: Dictionary, kind: String, details: Dictionary) -> String:
	return _record_at(row, kind, details, int(world.elapsed_ms))


func _record_at(row: Dictionary, kind: String, details: Dictionary, at_ms: int) -> String:
	var payload: Dictionary = details.duplicate(true)
	payload["at_ms"] = at_ms
	var witnesses: Array[String] = []
	@warning_ignore("integer_division")
	var tick: int = at_ms / 60000
	return world.regions[row.region].social.record(kind, str(row.actor), "", {"participants": payload}, witnesses, tick)


func _process(id: String, actor: String) -> Dictionary:
	return {"domain": "capability_practice", "id": id, "performer": world.embodiment.subject_for_actor(actor)}


func _reply(ok: bool, code: String, line: String, id: String = "", actor: String = "") -> Dictionary:
	return {"ok": ok, "code": code, "line": line, "id": id, "process": _process(id, actor) if not id.is_empty() else {}}


static func _point(value: Array) -> Vector2:
	return Vector2(float(value[0]), float(value[1]))
