class_name SimSpiritSources
extends RefCounted
## A finite local source. Original bodies own qi and original stones own charge.
## Active jobs reserve existing source stock and the actual medium, never output.

const VERSION: int = 3
const DEFINITIONS_VERSION: int = 1
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/spirit_source_schema.gd")
var definitions: Dictionary = {}
var activation_ms: int = 0
var last_ms: int = 0
var sources: Dictionary = {}
var active: Dictionary = {}
var records: Dictionary = {}
var qi_baselines: Dictionary = {}
var charge_baselines: Dictionary = {}
var next_id: int = 1
var _owner: WeakRef
var _decisions: Dictionary = {}
var world: RefCounted:
	get:
		return null if _owner == null else _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "interaction_cells", "duration_ms", "source_cost", "qi_gain", "charge_gain", "artifact_type", "sources"]) or not Shape.count(data.version, DEFINITIONS_VERSION, DEFINITIONS_VERSION) or data.artifact_type != "warm_stone" or not data.sources is Dictionary or data.sources.is_empty():
		return false
	if not Shape.count(data.interaction_cells, 1, 8) or not Shape.count(data.duration_ms, 1, 3600000):
		return false
	for key: String in ["source_cost", "qi_gain", "charge_gain"]:
		if not Shape.count(data[key], 1, 1000000):
			return false
	for id: Variant in data.sources:
		var row: Variant = data.sources[id]
		if not SimInventory._nonempty(id) or not Shape.keys(row, ["label", "region", "place", "phase", "capacity", "initial", "deep_supply", "refill_ms", "refill_amount", "description"]) or row.phase != "fire":
			return false
		for key: String in ["label", "region", "place", "description"]:
			if not SimInventory._nonempty(row[key]):
				return false
		if not Shape.count(row.capacity, int(data.source_cost), 1000000) or not Shape.count(row.initial, 0, int(row.capacity)) or not Shape.count(row.deep_supply, 0, 1000000000) or not Shape.count(row.refill_ms, 1, 86400000) or not Shape.count(row.refill_amount, 1, int(row.capacity)):
			return false
	return true


static func empty_state(at_ms: int, rules: Dictionary, authority: Variant = null) -> Dictionary:
	var seeded: Dictionary = {}
	var regions: Variant = authority if authority is Dictionary else (null if authority == null else authority.get("regions"))
	for id: String in rules.get("sources", {}):
		var rule: Dictionary = rules.sources[id]
		if regions is Dictionary and (not regions.has(rule.region) or not regions[rule.region].places.has(rule.place)):
			continue
		seeded[id] = {"amount": int(rule.initial), "released": 0, "spent": 0, "lost": 0}
	return {"version": VERSION, "rules_version": int(rules.get("version", DEFINITIONS_VERSION)), "activation_ms": at_ms, "last_ms": at_ms,
		"sources": seeded, "active": {}, "records": {}, "qi_baselines": {}, "charge_baselines": {}, "next_id": 1}


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules) or not Shape.count(authority.get("elapsed_ms")):
		return false
	for rule: Dictionary in rules.sources.values():
		if authority.regions.has(rule.region) and not authority.regions[rule.region].places.has(rule.place):
			return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	_assign(empty_state(int(authority.get("elapsed_ms")), definitions, authority))
	return true


func bind_world(authority: RefCounted) -> void:
	_owner = weakref(authority)
	_decisions.clear()


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func previous_autonomy(actor: String) -> bool:
	return bool(active.get(actor, {}).get("previous_autonomous", false))


func target_in_use(object_id: String) -> bool:
	for job: Dictionary in active.values():
		if job.object == object_id:
			return true
	return false


func actor_home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].actors.has(actor):
			return region
	return ""


func source_cell(id: String) -> Vector2i:
	if not sources.has(id):
		return Vector2i(-1, -1)
	var rule: Dictionary = definitions.sources[id]
	return SimRouteTravel.cell(world.regions[rule.region].places[rule.place].cell)


func reserved(id: String) -> int:
	var amount: int = 0
	for job: Dictionary in active.values():
		if job.source == id:
			amount += int(definitions.source_cost)
	return amount


func available(id: String) -> int:
	return 0 if not sources.has(id) else int(sources[id].amount) - reserved(id)


func begin(actor: String, source: String, target: String, object_id: String, autonomous: bool = false) -> Dictionary:
	if autonomous and not world.autonomous_decision(actor):
		return reply(false, "眼下不是本人可以安排引息的闲暇。")
	if not autonomous and world.elapsed_ms != world.target_ms:
		return reply(false, "世界事务仍在接续，请稍后再引息。")
	var home: String = actor_home(actor)
	if home.is_empty() or not sources.has(source) or target not in ["body", "stone"]:
		return reply(false, "眼下没有可这样引取的源息。")
	world.synchronize_region(home)
	if not settle_at_ms(int(world.elapsed_ms)):
		return reply(false, "源息过程尚未结清。")
	var reason: String = readiness(actor, source, target, object_id)
	if not reason.is_empty():
		return reply(false, reason)
	if available(source) < int(definitions.source_cost):
		return reply(false, "眼前可引的暖息不足，须等地隙再透出些。")
	if world.elapsed_ms > SimInventory.MAX_COUNT - int(definitions.duration_ms) or next_id >= SimInventory.MAX_COUNT:
		return reply(false, "当前无法安排这次完整引息。")
	var person: Dictionary = world.regions[home].actors[actor]
	if not ensure_qi_baseline(actor):
		return reply(false, "当前无法核对本人已有的灵气。")
	if target == "stone" and not charge_baselines.has(object_id):
		var item: Dictionary = world.artifacts.objects[object_id]
		charge_baselines[object_id] = {"at_ms": int(world.elapsed_ms), "charge": int(item.charge), "damage": int(item.damage), "artifact_floor": int(world.artifacts.next_id)}
	var id: String = "spirit:%d" % next_id
	next_id += 1
	active[actor] = {"id": id, "actor": actor, "region": home, "source": source, "target": target, "object": object_id,
		"cell": person.cell.duplicate(), "position": person.position.duplicate(), "started_ms": int(world.elapsed_ms),
		"due_ms": int(world.elapsed_ms) + int(definitions.duration_ms), "previous_autonomous": bool(person.autonomous)}
	person.autonomous = false
	person.goal = "借温石引息归身" if target == "body" else "借地火温养石芯"
	world.invalidate_region(home)
	if world.site_affairs != null:
		world.site_affairs.source_started(active[actor])
	if world.source_care != null:
		world.source_care.source_started(active[actor])
	return reply(true, "已在地隙旁凝神引息；完成前不会恢复灵气或石中储热。", id)


func ensure_qi_baseline(actor: String) -> bool:
	# The first real source operation or positive-qi cast snapshots history;
	# the original body remains the sole balance. Call only after readiness
	# succeeds and immediately before allocating that operation's cost.
	if world == null or not Shape.count(world.elapsed_ms, activation_ms):
		return false
	var home: String = actor_home(actor)
	if home.is_empty():
		return false
	var person: Dictionary = world.regions[home].actors[actor]
	if not Shape.count(person.qi, 0, max_qi(actor)):
		return false
	if qi_baselines.has(actor):
		return true
	var artifact_floor: int = int(world.artifacts.next_id)
	var soul_floor: int = int(world.soul_vessels.next_id)
	var conflict_floor: int = conflict_cost_floor()
	var practice_floor: int = practice_cost_floor()
	if not Shape.count(artifact_floor, 1) or not Shape.count(soul_floor, 1) or not Shape.count(conflict_floor, 1) or not Shape.count(practice_floor, 1):
		return false
	qi_baselines[actor] = {"at_ms": int(world.elapsed_ms), "qi": int(person.qi), "artifact_floor": artifact_floor, "soul_floor": soul_floor, "conflict_floor": conflict_floor, "practice_floor": practice_floor}
	return true


func readiness(actor: String, source: String, target: String, object_id: String, owned: bool = false) -> String:
	var home: String = actor_home(actor)
	if home.is_empty() or not sources.has(source) or target not in ["body", "stone"]:
		return "没有找到可接续的源息。"
	var person: Dictionary = world.regions[home].actors[actor]
	if not bool(person.alive) or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not person.active.is_empty() or (not owned and owns_actor(actor)) or other_body_in_use(actor):
		return "先完成手头的事，眼下不能凝神引息。"
	if world.health != null and world.health.blocks_channeling(actor):
		return "经脉仍灼涩，引流不顺；先休养或求助。"
	if not near(actor, source):
		return "先实际走到灶旁地火隙附近。"
	if not medium_allowed(actor, source, object_id):
		return "须借本人持有或灶旁公用的完整温石，别人的器物须先协商。"
	if not bool(world.artifacts.describe(actor, object_id).get("method", false)):
		return "还未亲自学会温石循纹手法，暂不能稳妥引息。"
	for job: Dictionary in world.artifacts.active.values():
		if job.object == object_id:
			return "有人正在操作这块温石。"
	if world.soul_vessels != null and world.soul_vessels.target_in_use(object_id):
		return "有人正借这块温石练习，须先等他结束。"
	if not owned and target_in_use(object_id):
		return "有人正借这块温石引息。"
	if target == "body" and int(person.qi) >= max_qi(actor):
		return "眼下灵气已充足，不必再引息归身。"
	if target == "stone":
		var item: Dictionary = world.artifacts.objects[object_id]
		if int(item.charge) >= int(world.artifacts.definitions.types[item.definition].max_charge):
			return "石芯已经蓄足余热，再引只会逸散。"
	return ""


func other_body_in_use(actor: String) -> bool:
	return world.body_action_owns(actor, &"spirit_sources")


func medium_allowed(actor: String, source: String, object_id: String) -> bool:
	if not world.artifacts.objects.has(object_id):
		return false
	var rule: Dictionary = definitions.sources[source]
	var item: Dictionary = world.artifacts.objects[object_id]
	if item.definition != definitions.artifact_type or item.region != rule.region or int(item.damage) >= int(world.artifacts.definitions.types[item.definition].damage_max):
		return false
	return item.container == "actor:" + actor or item.container == rule.place


func max_qi(actor: String) -> int:
	var home: String = actor_home(actor)
	return int(world.regions[home]._content.get_pawn(StringName(world.regions[home].actors[actor].definition_id)).max_qi)


func near(actor: String, source: String) -> bool:
	if not sources.has(source) or actor_home(actor) != definitions.sources[source].region:
		return false
	var body: Dictionary = world.regions[definitions.sources[source].region].actors[actor]
	return SimRouteTravel.point(body).distance_to(TileGrid.cell_to_world(source_cell(source))) <= float(definitions.interaction_cells) * TileGrid.TILE_SIZE


func cancel(actor: String) -> bool:
	if not active.has(actor):
		return false
	_finish(active[actor], "cancelled", "引息中断；预约已释放，未耗源息，也未提前恢复。", 0, 0, 0, int(world.elapsed_ms))
	return true


func next_boundary_ms() -> int:
	var boundary: int = SimInventory.MAX_COUNT
	for id: String in sources:
		var rule: Dictionary = definitions.sources[id]
		if int(sources[id].released) < int(rule.deep_supply):
			var period: int = int(rule.refill_ms)
			var remainder: int = posmod(last_ms - activation_ms, period)
			if last_ms <= SimInventory.MAX_COUNT - (period - remainder):
				boundary = mini(boundary, last_ms + period - remainder)
	for actor: String in active:
		var job: Dictionary = active[actor]
		if not readiness(actor, str(job.source), str(job.target), str(job.object), true).is_empty() or not _same_position(job):
			return mini(SimInventory.MAX_COUNT, int(world.elapsed_ms) + 1)
		boundary = mini(boundary, int(job.due_ms))
	return boundary


func settle_at_ms(now: int) -> bool:
	if not Shape.count(now, last_ms):
		return false
	# Parent normally stops exactly at each completion. This also preserves
	# source order for direct coarse probes without advancing another clock.
	while not active.is_empty():
		var due: int = SimInventory.MAX_COUNT
		for job: Dictionary in active.values():
			due = mini(due, int(job.due_ms))
		if due > now:
			break
		_refill_to(due)
		var actors: Array = active.keys()
		actors.sort()
		for actor: String in actors:
			if int(active[actor].due_ms) <= due:
				_complete(active[actor], due)
	_refill_to(now)
	var actors: Array = active.keys()
	actors.sort()
	for actor: String in actors:
		var job: Dictionary = active[actor]
		if not readiness(actor, str(job.source), str(job.target), str(job.object), true).is_empty() or not _same_position(job):
			_finish(job, "cancelled", "身体、手法或器物条件已改变，引息停下；没有消耗源息。", 0, 0, 0, now)
	return true


func _refill_to(now: int) -> void:
	for id: String in sources:
		var rule: Dictionary = definitions.sources[id]
		var row: Dictionary = sources[id]
		@warning_ignore("integer_division")
		var pulses: int = (now - activation_ms) / int(rule.refill_ms)
		# Clamp the pulse count before multiplying so even MAX_COUNT is safe.
		@warning_ignore("integer_division")
		var required: int = (int(rule.deep_supply) + int(rule.refill_amount) - 1) / int(rule.refill_amount)
		var total: int = mini(int(rule.deep_supply), mini(pulses, required) * int(rule.refill_amount))
		var gain: int = total - int(row.released)
		var accepted: int = mini(gain, int(rule.capacity) - int(row.amount))
		row.amount = int(row.amount) + accepted
		row.released = total
		row.lost = int(row.lost) + gain - accepted
	last_ms = now


func _complete(job: Dictionary, at_ms: int) -> void:
	world.synchronize_region(str(job.region))
	var reason: String = readiness(str(job.actor), str(job.source), str(job.target), str(job.object), true)
	if not reason.is_empty() or not _same_position(job) or int(sources[job.source].amount) < int(definitions.source_cost):
		_finish(job, "failed", reason if not reason.is_empty() else "引息条件已变，这次未能接续。", 0, 0, 0, at_ms)
		return
	var target: Dictionary = world.regions[job.region].actors[job.actor] if job.target == "body" else world.artifacts.objects[job.object]
	var field: String = "qi" if job.target == "body" else "charge"
	var maximum: int = max_qi(str(job.actor)) if job.target == "body" else int(world.artifacts.definitions.types[target.definition].max_charge)
	var before: int = int(target[field])
	var offered: int = int(definitions.qi_gain) if job.target == "body" else int(definitions.charge_gain)
	var output: int = mini(offered, maximum - before)
	# All checks precede this one synchronous source/target commit.
	sources[job.source].amount = int(sources[job.source].amount) - int(definitions.source_cost)
	sources[job.source].spent = int(sources[job.source].spent) + int(definitions.source_cost)
	target[field] = before + output
	_finish(job, "success", "循纹引息后，灵气确实回到本人；源中暖息已经耗去。" if job.target == "body" else "地火暖息已留在原温石中；仍可用于做饭、焙药或释热。", before, before + output, output, at_ms)


func _same_position(job: Dictionary) -> bool:
	var body: Dictionary = world.regions[job.region].actors[job.actor]
	return SimRouteTravel.cell(body.cell) == SimRouteTravel.cell(job.cell) and SimRouteTravel.point(body).is_equal_approx(Vector2(float(job.position[0]), float(job.position[1])))


func _finish(job: Dictionary, result: String, line: String, before: int, after: int, output: int, at_ms: int) -> void:
	var record: Dictionary = job.duplicate(true)
	record.merge({"finished_ms": at_ms, "result": result, "before": before, "after": after, "output": output,
		"loss": (int(definitions.qi_gain) if job.target == "body" else int(definitions.charge_gain)) - output if result == "success" else 0,
		"artifact_floor": int(world.artifacts.next_id), "soul_floor": int(world.soul_vessels.next_id), "conflict_floor": conflict_cost_floor(), "practice_floor": practice_cost_floor(), "line": line})
	records[job.id] = record
	active.erase(job.actor)
	if world.site_affairs != null:
		world.site_affairs.source_finished(record)
	if world.source_care != null:
		world.source_care.source_finished(record)
	var person: Dictionary = world.regions[job.region].actors[job.actor]
	person.autonomous = bool(job.previous_autonomous)
	person.goal = "刚结束引息"
	person.retry_ms = at_ms + mini(SimInventory.MAX_COUNT - at_ms, int(world.regions[job.region].config.decision_interval) * 60000)
	world.invalidate_region(str(job.region))


func describe(actor: String, source: String = "hearth_seam") -> Dictionary:
	if not sources.has(source) or actor_home(actor).is_empty():
		return {"known": false, "near": false}
	var rule: Dictionary = definitions.sources[source]
	var home: String = actor_home(actor)
	var observed: bool = home == rule.region and SimRouteTravel.point(world.regions[home].actors[actor]).distance_to(TileGrid.cell_to_world(source_cell(source))) <= float(world.regions[home].config.observation_radius) * TileGrid.TILE_SIZE
	var remembered: bool = active.get(actor, {}).get("source") == source
	for record: Dictionary in records.values():
		remembered = remembered or record.actor == actor and record.source == source
	var known: bool = observed or remembered
	if not known:
		return {"known": false, "near": false}
	var close: bool = near(actor, source)
	var objects_seen: Array[Dictionary] = []
	if close:
		for id: String in world._sorted_keys(world.artifacts.objects):
			if medium_allowed(actor, source, id) and world.artifacts.can_see(actor, id):
				objects_seen.append({"id": id, "label": str(world.artifacts.describe(actor, id).get("label", "温石"))})
	var line: String = "记得灶旁有一道透出暖息的地隙；眼下看不清那里。"
	if close:
		line = "石隙间仍透着暖息，可借温石循纹导引。" if available(source) >= int(definitions.source_cost) else "石隙间暖息微弱，眼下难以引出一股。"
	return {"known": true, "remembered": remembered, "near": close, "label": str(rule.label), "line": line, "source": source, "region": str(rule.region), "place": str(rule.place), "cell": [source_cell(source).x, source_cell(source).y], "objects": objects_seen, "targets": ["body", "stone"]}


func status(actor: String) -> Dictionary:
	if active.has(actor):
		var job: Dictionary = active[actor]
		var seconds: int = ceili(float(maxi(0, int(job.due_ms) - int(world.elapsed_ms))) / 1000.0)
		return {"busy": true, "line": "正在引息归身" if job.target == "body" else "正在借地火温养原石", "remaining": seconds, "seconds": seconds, "event": str(job.id), "source": str(job.source), "target": str(job.target), "object": str(job.object)}
	var latest: Dictionary = {}
	for record: Dictionary in records.values():
		if record.actor == actor and (latest.is_empty() or int(record.finished_ms) > int(latest.finished_ms) or int(record.finished_ms) == int(latest.finished_ms) and number(str(record.id)) > number(str(latest.id))):
			latest = record
	return {"busy": false, "line": "须在源旁借温石引息。"} if latest.is_empty() else {"busy": false, "line": str(latest.line), "event": str(latest.id), "source": str(latest.source), "target": str(latest.target), "object": str(latest.object)}


func wants_decision(actor: String, at_ms: int) -> bool:
	var home: String = actor_home(actor)
	if home.is_empty():
		return false
	var sim: RefCounted = world.regions[home]
	var person: Dictionary = sim.actors[actor]
	if not person.autonomous or int(person.qi) >= int(world.artifacts.definitions.verbs.charge.qi) or not world.standing_work.duty_for(actor, at_ms).is_empty():
		return false
	var contract: String = world.budgeted_labor.latest_for(actor)
	if not contract.is_empty() and world.budgeted_labor.contracts[contract].status in ["working", "paused"]:
		return false
	var duty: String = str(sim.config.actor_profiles[actor].get("duty", ""))
	if not duty.is_empty() and sim.needs_action(actor, duty):
		return false
	return not _choice(actor).is_empty()


func _choice(actor: String) -> Dictionary:
	for id: String in world._sorted_keys(sources):
		if not near(actor, id):
			continue
		for object_id: String in world._sorted_keys(world.artifacts.objects):
			if readiness(actor, id, "body", object_id).is_empty():
				return {"source": id, "object": object_id}
	return {}


func note_decision(actor: String, at_ms: int) -> void:
	_decisions[actor] = at_ms


func consider() -> void:
	var handed_off: Dictionary = _decisions.duplicate()
	_decisions.clear()
	for actor: String in world._sorted_keys(handed_off):
		if int(handed_off[actor]) != int(world.elapsed_ms) or not world.autonomous_decision(actor):
			continue
		var started: bool = false
		if wants_decision(actor, int(world.elapsed_ms)):
			var choice: Dictionary = _choice(actor)
			if not choice.is_empty():
				started = bool(begin(actor, str(choice.source), "body", str(choice.object), true).ok)
		if not started:
			var home: String = actor_home(actor)
			world.regions[home]._choose_routine(actor, false)
			world.invalidate_region(home)


func to_dict() -> Dictionary:
	return {"version": VERSION, "rules_version": int(definitions.version), "activation_ms": activation_ms, "last_ms": last_ms, "sources": sources.duplicate(true), "active": active.duplicate(true), "records": records.duplicate(true), "qi_baselines": qi_baselines.duplicate(true), "charge_baselines": charge_baselines.duplicate(true), "next_id": next_id}


func conflict_cost_floor() -> int:
	var conflicts: Variant = world.get("conflicts")
	return 1 if conflicts == null else int(conflicts.get("next_cost_id"))


func practice_cost_floor() -> int:
	var practice: Variant = world.get("capability_practice")
	return 1 if practice == null else int(practice.get("next_id"))


static func upgrade_legacy(data: Dictionary) -> Dictionary:
	# Old worlds had no conflict casting. The explicit floor is the first
	# future allocation, never a reconstructed qi value or retroactive spend.
	if data.get("version") != 1:
		return data.duplicate(true)
	if not Shape.keys(data, ["version", "rules_version", "activation_ms", "last_ms", "sources", "active", "records", "qi_baselines", "charge_baselines", "next_id"]) or not data.records is Dictionary or not data.qi_baselines is Dictionary:
		return {}
	for row: Variant in data.qi_baselines.values():
		if not Shape.keys(row, ["at_ms", "qi", "artifact_floor", "soul_floor"]):
			return {}
	var old_keys: Array[String] = Schema.JOB_KEYS.duplicate()
	old_keys.append_array(Schema.RESULT_KEYS)
	old_keys.erase("conflict_floor")
	old_keys.erase("practice_floor")
	for row: Variant in data.records.values():
		if not Shape.keys(row, old_keys):
			return {}
	var upgraded: Dictionary = data.duplicate(true)
	upgraded.version = 2
	for row: Dictionary in upgraded.qi_baselines.values():
		row["conflict_floor"] = 1
	for row: Dictionary in upgraded.records.values():
		row["conflict_floor"] = 1
	return upgraded


static func upgrade_practice(data: Dictionary) -> Dictionary:
	if data.get("version") != 2 or not Shape.keys(data, ["version", "rules_version", "activation_ms", "last_ms", "sources", "active", "records", "qi_baselines", "charge_baselines", "next_id"]) or not data.records is Dictionary or not data.qi_baselines is Dictionary: return {}
	for row: Variant in data.qi_baselines.values():
		if not Shape.keys(row, ["at_ms", "qi", "artifact_floor", "soul_floor", "conflict_floor"]): return {}
	var old_keys: Array[String] = Schema.JOB_KEYS.duplicate()
	old_keys.append_array(Schema.RESULT_KEYS)
	old_keys.erase("practice_floor")
	for row: Variant in data.records.values():
		if not Shape.keys(row, old_keys): return {}
	var upgraded: Dictionary = data.duplicate(true)
	upgraded.version = VERSION
	for row: Dictionary in upgraded.qi_baselines.values(): row["practice_floor"] = 1
	for row: Dictionary in upgraded.records.values(): row["practice_floor"] = 1
	return upgraded


func restore(data: Dictionary) -> bool:
	var upgraded: Dictionary = upgrade_legacy(data)
	# Regional v34 -> v35 upgrades v2 explicitly. This older standalone entry
	# accepts only the complete historical v1 shape, never a modern v2 mix.
	if data.get("version") == 1 and not upgraded.is_empty():
		upgraded = upgrade_practice(upgraded)
	if not Schema.validate(upgraded, self):
		return false
	_assign(upgraded)
	return true


func _assign(data: Dictionary) -> void:
	activation_ms = int(data.activation_ms)
	last_ms = int(data.last_ms)
	next_id = int(data.next_id)
	sources = _integers(data.sources)
	active = _integers(data.active)
	records = _integers(data.records)
	qi_baselines = _integers(data.qi_baselines)
	charge_baselines = _integers(data.charge_baselines)
	_decisions.clear()


static func _integers(value: Variant) -> Variant:
	if value is Dictionary:
		var result: Dictionary = {}
		for key: String in value:
			result[key] = value[key].duplicate() if key == "position" else _integers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item: Variant in value:
			result.append(_integers(item))
		return result
	return int(value) if value is float else value


static func number(id: String) -> int:
	return int(id.get_slice(":", id.get_slice_count(":") - 1))


static func reply(ok: bool, line: String, action: String = "") -> Dictionary:
	return {"ok": ok, "line": line, "action": action}
