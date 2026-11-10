class_name SimClothing
extends RefCounted
## Unique garments reference real containers. Wearing is a use of the same
## carried object, never a second inventory quantity or character stat set.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const Schema = preload("res://scripts/sim/clothing_schema.gd")
const VERBS: Array[String] = ["take", "place", "wear", "remove"]
var definitions: Dictionary = {}
var seeded: bool = false
var objects: Dictionary = {}
var active: Dictionary = {}
var events: Array[Dictionary] = []
var next_id: int = 1
var _owner: WeakRef
var _worn: Dictionary = {}
var _outer_holders: Dictionary[String, bool] = {}
var world: RefCounted:
	get:
		return _owner.get_ref()


static func valid_definitions(data: Variant) -> bool:
	if not Shape.keys(data, ["version", "change_ms", "handling_ms", "interaction_cells", "dry_per_pulse", "wet_threshold", "wet_energy_per_minute", "types", "opening"]) or data.version != 1 or not Shape.count(data.change_ms, 1, 60000) or not Shape.count(data.handling_ms, 1, 60000) or not Shape.count(data.interaction_cells, 1, 5) or not Shape.count(data.dry_per_pulse, 1, 100) or not Shape.count(data.wet_threshold, 1, 100) or not data.wet_energy_per_minute is float or not is_finite(data.wet_energy_per_minute) or data.wet_energy_per_minute < 0 or data.wet_energy_per_minute > 1 or not data.types is Dictionary or data.types.is_empty():
		return false
	for id: Variant in data.types:
		var entry: Variant = data.types[id]
		if not SimInventory._nonempty(id) or not Shape.keys(entry, ["label", "slot", "shape", "color", "rain_cover", "absorb_per_pulse", "cue"]) or not SimInventory._nonempty(entry.label) or not SimInventory._nonempty(entry.cue) or not _color(entry.color) or not entry.rain_cover is bool or not Shape.count(entry.absorb_per_pulse, 0, 100):
			return false
		if not (entry.slot == "body" and entry.shape == "robe" or entry.slot == "outer" and entry.shape == "cape") or entry.rain_cover and entry.slot != "outer":
			return false
	if not Shape.keys(data.opening, ["robe", "spares"]) or not data.types.has(data.opening.robe) or data.types[data.opening.robe].slot != "body" or not data.opening.spares is Array:
		return false
	for row: Variant in data.opening.spares:
		if not Shape.keys(row, ["region", "actor", "type", "container"]) or not data.types.has(row.type):
			return false
		for field: String in ["region", "actor", "container"]:
			if not SimInventory._nonempty(row[field]):
				return false
	return true


static func _color(value: Variant) -> bool:
	return value is String and value.length() == 7 and value.begins_with("#") and value.trim_prefix("#").is_valid_hex_number()


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)
	_rebuild_worn()


func initialize(authority: RefCounted, rules: Dictionary) -> bool:
	if authority == null or not valid_definitions(rules):
		return false
	_owner = weakref(authority)
	definitions = rules.duplicate(true)
	return true


func opening_objects() -> Dictionary:
	var result: Dictionary = {}
	for region: String in world._sorted_keys(world.regions):
		var sim: VillageSimulation = world.regions[region]
		for actor: String in world._sorted_keys(sim.actors):
			var definition: PawnDef = world._content.get_pawn(StringName(sim.actors[actor].definition_id))
			result["clothing:robe:" + actor] = _object(str(definitions.opening.robe), actor, region, "actor:" + actor, true, "#" + definition.color.to_html(false))
	for index: int in definitions.opening.spares.size():
		var row: Dictionary = definitions.opening.spares[index]
		if home(str(row.actor)) != row.region or not valid_location(str(row.region), str(row.container)):
			return {}
		result["clothing:spare:%d" % index] = _object(str(row.type), str(row.actor), str(row.region), str(row.container), false, str(definitions.types[row.type].color))
	return result


static func _object(type: String, owner: String, region: String, container: String, worn: bool, color: String) -> Dictionary:
	return {"type": type, "owner": owner, "region": region, "container": container, "worn": worn, "color": color, "wet": 0, "changed_ms": 0}


func spawn_opening() -> bool:
	if seeded or not objects.is_empty() or world.elapsed_ms != 0:
		return false
	var opening: Dictionary = opening_objects()
	if opening.is_empty():
		return false
	objects = opening
	_rebuild_worn()
	seeded = true
	return true


func home(actor: String) -> String:
	for region: String in world.regions:
		if world.regions[region].actors.has(actor):
			return region
	return ""


func valid_location(region: String, container: String) -> bool:
	if not world.regions.has(region):
		return false
	var sim: VillageSimulation = world.regions[region]
	return sim.places.has(container) or container.begins_with("actor:") and sim.actors.has(container.trim_prefix("actor:"))


func cell(region: String, container: String) -> Vector2i:
	var sim: VillageSimulation = world.regions[region]
	return SimRouteTravel.cell(sim.actors[container.trim_prefix("actor:")].cell if container.begins_with("actor:") else sim.places[container].cell)


func held(actor: String, id: String) -> bool:
	return objects.has(id) and objects[id].region == home(actor) and objects[id].container == "actor:" + actor


func owns_actor(actor: String) -> bool:
	return active.has(actor)


func worn_at(actor: String, slot: String) -> String:
	return str(_worn.get(actor, {}).get(slot, ""))


func _rebuild_worn() -> void:
	# Disposable owner-local index; original objects retain custody/wetness.
	_worn.clear()
	_outer_holders.clear()
	for id: String in objects:
		var row: Dictionary = objects[id]
		if not str(row.container).begins_with("actor:"):
			continue
		var actor: String = str(row.container).trim_prefix("actor:")
		if not held(actor, id):
			continue
		if definitions.types[row.type].slot == "outer":
			_outer_holders[actor] = true
		if not bool(row.worn):
			continue
		if not _worn.has(actor):
			_worn[actor] = {}
		var slot: String = str(definitions.types[row.type].slot)
		if not _worn[actor].has(slot):
			_worn[actor][slot] = id


func duration(verb: String) -> int:
	return int(definitions.change_ms if verb in ["wear", "remove"] else definitions.handling_ms)


func begin(actor: String, verb: String, id: String, target: String = "", autonomous: bool = false) -> Dictionary:
	if home(actor).is_empty() or verb not in VERBS or not objects.has(id) or world.elapsed_ms > SimInventory.MAX_COUNT - duration(verb):
		return reply(false, "没有这件可供本人使用的衣物。")
	if world.elapsed_ms != world.target_ms and not autonomous or autonomous and not world.autonomous_decision(actor):
		return reply(false, "先等当前世界事务结算完，再安排穿脱。")
	var region: String = home(actor)
	world.synchronize_region(region)
	var person: Dictionary = world.regions[region].actors[actor]
	if not world.native_action_allowed(actor) or not person.active.is_empty() or not world.actor_controls(actor, "motion"):
		return reply(false, "先完成或停止手头的事，才能整理自己的衣物。")
	var object: Dictionary = objects[id]
	if object.owner != actor or _reserved(id) or not _allowed(actor, verb, id, target):
		return reply(false, "先靠近自己的衣物；穿法冲突要先脱下，别人的衣物不能直接取走。")
	var job: String = "clothing:action:%d" % next_id
	next_id += 1
	active[actor] = {"id": job, "actor": actor, "region": region, "verb": verb, "object": id, "target": target,
		"from_region": object.region, "from_container": object.container, "from_worn": object.worn,
		"started_ms": world.elapsed_ms, "due_ms": world.elapsed_ms + duration(verb), "previous_autonomous": bool(person.autonomous), "at": person.cell.duplicate(), "position": person.position.duplicate()}
	person.autonomous = false
	person.goal = {"take": "收起自己的衣物", "place": "放下自己的衣物", "wear": "穿上衣物", "remove": "脱下衣物"}[verb]
	world.invalidate_region(region)
	return reply(true, str(person.goal) + "需要片刻；完成后才改变穿戴或保管位置。", job)


func _reserved(id: String) -> bool:
	for job: Dictionary in active.values():
		if job.object == id:
			return true
	return false


func _allowed(actor: String, verb: String, id: String, target: String) -> bool:
	var object: Dictionary = objects[id]
	var region: String = home(actor)
	var at: Vector2i = cell(region, "actor:" + actor)
	var slot: String = str(definitions.types[object.type].slot)
	if verb == "take":
		return target.is_empty() and object.region == region and not held(actor, id) and not object.worn and not str(object.container).begins_with("actor:") and at.distance_to(cell(str(object.region), str(object.container))) <= float(definitions.interaction_cells)
	if not held(actor, id):
		return false
	if verb == "place":
		return not object.worn and world.regions[region].places.has(target) and at.distance_to(cell(region, target)) <= float(definitions.interaction_cells)
	if not target.is_empty():
		return false
	return not object.worn and worn_at(actor, slot).is_empty() if verb == "wear" else bool(object.worn)


func _connected(job: Dictionary) -> bool:
	if not world.actor_controls(str(job.actor), "action") or not world.actor_controls(str(job.actor), "motion") or not objects.has(job.object):
		return false
	var object: Dictionary = objects[job.object]
	return object.region == job.from_region and object.container == job.from_container and object.worn == job.from_worn and world.regions[job.region].actors[job.actor].position == job.position and cell(str(job.region), "actor:" + str(job.actor)) == SimRouteTravel.cell(job.at) and _allowed(str(job.actor), str(job.verb), str(job.object), str(job.target))


func next_boundary_ms() -> int:
	var result: int = SimInventory.MAX_COUNT
	for job: Dictionary in active.values():
		if not _connected(job):
			return world.elapsed_ms + 1
		result = mini(result, int(job.due_ms))
	return result


func settle_at_ms(now: int) -> void:
	for actor: String in world._sorted_keys(active):
		var job: Dictionary = active[actor]
		world.synchronize_region(str(job.region))
		if not _connected(job):
			_finish(job, "failed")
		elif now >= int(job.due_ms):
			_finish(job, "completed")


func cancel(actor: String) -> bool:
	if _owner != null and world != null and world.has_method("accepts_commands") and not world.accepts_commands():
		return false
	if not active.has(actor):
		return false
	_finish(active[actor], "cancelled")
	return true


static func transition(object: Dictionary, job: Dictionary) -> void:
	match str(job.verb):
		"take":
			object.region = job.region
			object.container = "actor:" + str(job.actor)
		"place":
			object.region = job.region
			object.container = job.target
		"wear": object.worn = true
		"remove": object.worn = false
	object.changed_ms = job.due_ms


func _finish(job: Dictionary, outcome: String) -> void:
	if outcome == "completed":
		transition(objects[job.object], job)
		_rebuild_worn()
	var record: Dictionary = job.duplicate(true)
	record["outcome"] = outcome
	record["finished_ms"] = world.elapsed_ms
	events.append(record)
	var person: Dictionary = world.regions[job.region].actors[job.actor]
	person.autonomous = bool(job.previous_autonomous)
	person.retry_ms = world.elapsed_ms + int(world.regions[job.region].config.decision_interval) * 60000
	person.goal = "已整理好衣物" if outcome == "completed" else "衣物仍保留原处"
	active.erase(job.actor)
	world.invalidate_region(str(job.region))
	SimActionContract.job_finished(world, "clothing", job, job.actor, outcome)


func energy_rate(actor: String) -> int:
	var id: String = worn_at(actor, "body")
	return roundi(float(definitions.wet_energy_per_minute) * VillageSimulation.NEED_SCALE) if not id.is_empty() and int(objects[id].wet) >= int(definitions.wet_threshold) else 0


func weather_pulse(previous: int) -> void:
	var any_rain: bool = false
	for region: String in world.regions:
		any_rain = any_rain or world.weather.kind_at(world.weather.definitions, region, world.weather.epoch_ms, previous) == "rain"
	for id: String in world._sorted_keys(objects):
		var object: Dictionary = objects[id]
		if int(object.changed_ms) > previous:
			continue
		var wet: int = int(object.wet)
		var raining: bool = false
		if object.worn:
			var actor: String = str(object.container).trim_prefix("actor:")
			if _exposure_changed(actor, previous):
				continue
			var region: String = home(actor)
			# A dry garment under clear climate cannot change any physical rate.
			# Leave quiet far regions lazy rather than waking all bodies to redraw.
			if wet == 0 and (int(definitions.types[object.type].absorb_per_pulse) == 0 or not any_rain):
				continue
			world.synchronize_region(region)
			var physical_region: String = physical_region_for(actor)
			var roofed: bool = region_roofed(physical_region, cell(region, "actor:" + actor))
			var outer: String = worn_at(actor, "outer")
			var covered: bool = not outer.is_empty() and outer != id and definitions.types[objects[outer].type].rain_cover
			raining = not roofed and not covered and world.weather.kind_at(world.weather.definitions, physical_region, world.weather.epoch_ms, previous) == "rain"
		wet = mini(100, wet + int(definitions.types[object.type].absorb_per_pulse)) if raining else maxi(0, wet - int(definitions.dry_per_pulse))
		if wet != int(object.wet):
			object.wet = wet
			if object.worn:
				world.invalidate_region(home(str(object.owner)))


func _exposure_changed(actor: String, since: int) -> bool:
	for index: int in range(events.size() - 1, -1, -1):
		var event: Dictionary = events[index]
		if int(event.finished_ms) <= since:
			break
		if event.actor == actor and event.outcome == "completed" and event.verb in ["wear", "remove"]:
			return true
	return false


func physical_region_for(actor: String) -> String:
	if world.environment != null:
		return world.environment.region_for_actor(actor)
	var at: Vector2i = cell(home(actor), "actor:" + actor)
	var best: String = home(actor)
	var distance: float = INF
	for region: String in world._sorted_keys(world.regions):
		var next: float = at.distance_to(cell(region, "dorm"))
		if next < distance:
			distance = next
			best = region
	return best


func region_roofed(region: String, at: Vector2i) -> bool:
	if world.regions.has(region) and SimWorkplaces.roofed(world.regions[region].places, at):
		return true
	return world.construction != null and region == world.construction.definitions.site.region and world.construction.roofed(at)


func wants_decision(actor: String, at_ms: int) -> bool:
	return not _outer_choice(actor, at_ms).is_empty()


func _outer_choice(actor: String, at_ms: int) -> String:
	if home(actor).is_empty() or world.weather == null:
		return ""
	var region: String = physical_region_for(actor)
	var rain: bool = world.weather.kind_at(world.weather.definitions, region, world.weather.epoch_ms, at_ms) == "rain"
	var outer: String = worn_at(actor, "outer")
	if not outer.is_empty():
		return outer if not rain and world.environment != null and world.environment.cooler_without_outer(actor, str(objects[outer].type), int(objects[outer].wet), at_ms) else ""
	for id: String in world._sorted_keys(objects):
		if not held(actor, id) or objects[id].worn or definitions.types[objects[id].type].slot != "outer":
			continue
		if rain and definitions.types[objects[id].type].rain_cover or world.environment != null and world.environment.warmer_outer(actor, str(objects[id].type), int(objects[id].wet), at_ms):
			return id
	return ""


func consider_weather() -> void:
	# Only a holder of an actual outer garment can make this decision.
	for actor: String in world._sorted_keys(_outer_holders):
		if not world.autonomous_decision(actor) or not world.standing_work.duty_for(actor, world.elapsed_ms).is_empty():
			continue
		var id: String = _outer_choice(actor, world.elapsed_ms)
		if not id.is_empty():
			begin(actor, "remove" if objects[id].worn else "wear", id, "", true)


func appearance(actor: String) -> Dictionary:
	var result: Dictionary = {}
	for slot: String in ["body", "outer"]:
		var id: String = worn_at(actor, slot)
		if not id.is_empty():
			result[slot] = {"shape": definitions.types[objects[id].type].shape, "color": objects[id].color, "wet": int(objects[id].wet) >= int(definitions.wet_threshold)}
	return result


func seen_clothing(observer: String, target: String) -> String:
	if home(observer).is_empty() or home(target).is_empty() or cell(home(observer), "actor:" + observer).distance_to(cell(home(target), "actor:" + target)) > float(world.regions[home(observer)].config.observation_radius):
		return "已离开视线，看不清此时衣着。"
	var id: String = worn_at(target, "outer")
	if id.is_empty():
		id = worn_at(target, "body")
	return str(definitions.types[objects[id].type].cue) if not id.is_empty() else "朴素衣着，单凭外表看不出身份。"


func status(actor: String) -> String:
	if active.has(actor):
		return "%s，还需%.1f秒。" % [str(world.regions[home(actor)].actors[actor].goal), float(int(active[actor].due_ms) - world.elapsed_ms) / 1000.0]
	return "湿透的常服贴在身上，行动更容易疲惫。" if energy_rate(actor) > 0 else "衣物的外观、用途与身份凭据分别成立。"


static func reply(ok: bool, line: String, id: String = "") -> Dictionary:
	return {"ok": ok, "line": line, "id": id}


static func empty_state() -> Dictionary:
	return {"version": 1, "seeded": false, "objects": {}, "active": {}, "events": [], "next_id": 1}


func to_dict() -> Dictionary:
	return {"version": 1, "seeded": seeded, "objects": objects.duplicate(true), "active": active.duplicate(true), "events": events.duplicate(true), "next_id": next_id}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, self):
		return false
	seeded = bool(data.seeded)
	objects = data.objects.duplicate(true)
	_rebuild_worn()
	active = data.active.duplicate(true)
	events.assign(data.events.duplicate(true))
	next_id = int(data.next_id)
	return true
