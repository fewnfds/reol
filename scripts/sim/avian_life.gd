class_name SimAvianLife
extends RefCounted
## Nonhuman bodies, finite habitat stock and personal routines on the world clock.
## Embodiment references these bodies; no Village actor or human inventory is made.

const VERSION: int = 1
const SCALE: int = 1000000
const MINUTE_MS: int = 60000
const Schema = preload("res://scripts/sim/avian_schema.gd")

var definitions: Dictionary = {}
var birds: Dictionary = {}
var sites: Dictionary = {}
var inventory: SimInventory = SimInventory.new()
var events: Array[Dictionary] = []
var exchanges: Dictionary = {}
var elapsed_ms: int = 0
var next_id: int = 1
var _owner: WeakRef
var _landing: Callable

var world: RefCounted:
	get:
		return _owner.get_ref() if _owner != null else null


static func valid_definitions(data: Variant) -> bool:
	return Schema.definitions_valid(data)


func bind_world(authority: RefCounted) -> void:
	# Rebind a validated candidate without resetting its saved process.
	_owner = weakref(authority)


func initialize(authority: RefCounted, content: Dictionary) -> bool:
	if authority == null or not valid_definitions(content):
		return false
	_owner = weakref(authority)
	definitions = content.duplicate(true)
	elapsed_ms = authority.elapsed_ms
	return true


func set_landing_check(provider: Callable) -> void:
	_landing = provider


func spawn_opening(scenario: Dictionary, centers: Dictionary) -> bool:
	if not birds.is_empty() or not sites.is_empty() or scenario.get("version") != VERSION or not scenario.get("regions") is Dictionary:
		return false
	var candidate := SimAvianLife.new()
	if not candidate.initialize(world, definitions):
		return false
	var registry := SimEmbodiment.new()
	if not registry.configure(world._content.body_forms) or not registry.restore(world.embodiment.to_dict()):
		return false
	for region: Variant in scenario.regions:
		var section: Variant = scenario.regions[region]
		if not region is String or not world.regions.has(region) or not centers.get(region) is Vector2i or not section is Dictionary or not section.get("sites") is Dictionary or not section.get("bird") is Dictionary:
			return false
		if section.has("flock") and not section.flock is Array:
			return false
		for key: Variant in section.sites:
			var row: Variant = section.sites[key]
			if not key is String or not row is Dictionary or not definitions.site_types.has(row.get("type")):
				return false
			var at: Vector2i = centers[region]
			if row.has("place"):
				if not world.regions[region].places.has(row.place):
					return false
				at = SimRouteTravel.cell(world.regions[region].places[row.place].cell)
			elif Schema.cell_valid(row.get("offset"), true):
				at += SimRouteTravel.cell(row.offset)
			else:
				return false
			if not Schema.cell_valid([at.x, at.y]):
				return false
			var type: Dictionary = definitions.site_types[row.type]
			var site_id: String = region + ":" + key
			candidate.sites[site_id] = {"region": region, "type": row.type, "cell": [at.x, at.y], "next_growth_ms": elapsed_ms + int(type.regrow_ms) if int(type.regrow_ms) > 0 else 0}
			candidate.inventory.create_container(site_id, {} if str(type.item).is_empty() else {str(type.item): int(type.initial)})
		var nest: String = region + ":roost"
		if not candidate.sites.has(nest) or candidate.sites[nest].type != "roost":
			return false
		var opening_birds: Array = [section.bird]
		opening_birds.append_array(section.get("flock", []))
		for bird: Variant in opening_birds:
			if not bird is Dictionary or not candidate._stage_opening_bird(registry, region, bird, nest):
				return false
	if not registry.matches_legacy_actors(world._actor_ids(world.regions), candidate.birds.keys(), world.soul_vessels.bindings(), world.large_bodies.bodies.keys()):
		return false
	# All references and physical containers are staged before either is replaced.
	world.embodiment = registry
	_assign(candidate.to_dict())
	return true


func _stage_opening_bird(registry: SimEmbodiment, region: String, bird: Dictionary, nest: String) -> bool:
	if not SimInventory._nonempty(bird.get("id")) or birds.has(bird.id) or not SimInventory._nonempty(bird.get("label")) or not Schema.count(bird.get("fullness"), 0, 100) or not Schema.count(bird.get("energy"), 0, 100):
		return false
	if bird.has("understands_gestures") and not bird.understands_gestures is bool:
		return false
	var nest_point: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(sites[nest].cell))
	birds[bird.id] = {"label": bird.label, "region": region, "home": nest, "position": [nest_point.x, nest_point.y], "altitude": 1,
		"fullness": int(bird.fullness) * SCALE, "energy": int(bird.energy) * SCALE, "carry": {"fullness": 0, "energy": 0},
		"autonomous": true, "active": {}, "retry_ms": elapsed_ms + 1, "known_sites": {}, "errand": {}, "goal": "听风歇翅"}
	# Absent on historical bodies: their already established understanding stays valid.
	if bird.has("understands_gestures"):
		birds[bird.id].understands_gestures = bird.understands_gestures
	if not inventory.create_container("bird:" + str(bird.id), {}):
		return false
	var subject: String = subject_id(bird.id)
	var carrier: String = carrier_id(bird.id)
	if not registry.add_subject(subject) or not registry.add_carrier(carrier, "sparrow", {"kind": "avian_body", "id": bird.id}) or not registry.reside(subject, carrier):
		return false
	for channel: String in SimEmbodiment.CHANNELS:
		if not registry.grant_control(subject, carrier, channel):
			return false
	_observe(bird.id)
	return true


static func subject_id(id: String) -> String:
	return "subject:avian:" + id


static func carrier_id(id: String) -> String:
	return "body:avian:" + id


func controls(id: String, channel: String) -> bool:
	return birds.has(id) and world.embodiment.controls(subject_id(id), carrier_id(id), channel)


func body_cell(id: String) -> Vector2i:
	return TileGrid.world_to_cell(point(birds[id]))


static func point(body: Dictionary) -> Vector2:
	return Vector2(float(body.position[0]), float(body.position[1]))


func can_enter(carrier: String, site_id: String) -> bool:
	return sites.has(site_id) and world.embodiment.fits_opening(carrier, int(definitions.site_types[sites[site_id].type].opening_mm))


func can_carry(id: String, item: String, amount: int = 1) -> bool:
	if not birds.has(id) or not definitions.items_grams.has(item) or amount <= 0 or not world.embodiment.capable(carrier_id(id), "carry_in_beak"):
		return false
	var grams: int = 0
	for held: String in inventory.containers["bird:" + id]:
		grams += int(definitions.items_grams.get(held, int(rules().carry_grams) + 1)) * inventory.quantity("bird:" + id, held)
	@warning_ignore("integer_division")
	var maximum: int = (int(rules().carry_grams) - grams) / int(definitions.items_grams[item])
	return amount <= maximum


func rules() -> Dictionary:
	return definitions.species.sparrow


func next_boundary_ms() -> int:
	var next: int = SimInventory.MAX_COUNT
	for site: Dictionary in sites.values():
		if int(site.next_growth_ms) > 0:
			next = mini(next, int(site.next_growth_ms))
	for body: Dictionary in birds.values():
		if not body.active.is_empty():
			next = mini(next, int(body.active.due_ms))
		elif bool(body.autonomous):
			next = mini(next, int(body.retry_ms))
	return maxi(elapsed_ms + 1, next)


func settle_at_ms(now: int) -> void:
	var delta: int = now - elapsed_ms
	if delta < 0:
		return
	for id: String in sorted_keys(birds):
		var body: Dictionary = birds[id]
		if (not controls(id, "motion") or not controls(id, "action")) and not body.active.is_empty():
			cancel(id)
		_change_need(body, "fullness", -int(rules().hunger_per_minute), delta)
		var rate: int = -int(rules().energy_per_minute)
		if body.active.get("verb") == "fly":
			rate -= int(rules().flight_energy_per_minute)
		elif body.active.get("verb") == "rest":
			rate = int(definitions.manual.ground_rest_gain_per_minute) if body.active.get("purpose") == "recover" else int(rules().rest_gain_per_minute)
		_change_need(body, "energy", rate, delta)
		if body.active.get("verb") == "fly":
			project(body, now)
	elapsed_ms = now
	for site_id: String in sorted_keys(sites):
		var site: Dictionary = sites[site_id]
		if int(site.next_growth_ms) > 0 and int(site.next_growth_ms) <= now:
			var type: Dictionary = definitions.site_types[site.type]
			var amount: int = mini(int(type.regrow_amount), int(type.capacity) - inventory.quantity(site_id, type.item))
			if amount > 0:
				inventory.containers[site_id][type.item] = inventory.quantity(site_id, type.item) + amount
				_record("ripened", "", site_id, "枝草结出了新的可食种子或药芽。", {"item": type.item, "amount": amount})
			site.next_growth_ms = now + int(type.regrow_ms)
	for id: String in sorted_keys(birds):
		var body: Dictionary = birds[id]
		if not controls(id, "motion") or not controls(id, "action"):
			if not body.active.is_empty():
				cancel(id)
			body.retry_ms = now + int(definitions.actions_ms.idle)
			continue
		if not body.active.is_empty() and int(body.active.due_ms) <= now:
			_finish(id)
		if body.active.is_empty() and bool(body.autonomous) and int(body.retry_ms) <= now:
			_decide(id)


static func _change_need(body: Dictionary, key: String, rate: int, delta: int) -> void:
	@warning_ignore("integer_division")
	var whole: int = delta / MINUTE_MS
	var tail: int = delta % MINUTE_MS
	var numerator: int = int(body.carry[key]) + rate * tail
	@warning_ignore("integer_division")
	var fraction: int = numerator / MINUTE_MS
	var remainder: int = numerator % MINUTE_MS
	if remainder < 0:
		fraction -= 1
		remainder += MINUTE_MS
	var amount: int = whole * rate + fraction
	body.carry[key] = remainder
	body[key] = clampi(int(body[key]) + amount, 0, 100 * SCALE)
	if int(body[key]) == 0 or int(body[key]) == 100 * SCALE:
		body.carry[key] = 0


static func project(body: Dictionary, now: int) -> void:
	var action: Dictionary = body.active
	var a: Vector2 = Vector2(float(action.from[0]), float(action.from[1]))
	var b: Vector2 = Vector2(float(action.to[0]), float(action.to[1]))
	var ratio: float = clampf(float(now - int(action.started_ms)) / float(int(action.due_ms) - int(action.started_ms)), 0, 1)
	var projected: Vector2 = a.lerp(b, ratio)
	body.position = [projected.x, projected.y]


func _observe(id: String) -> void:
	var body: Dictionary = birds[id]
	for site_id: String in sorted_keys(sites):
		var site: Dictionary = sites[site_id]
		if body_cell(id).distance_to(SimRouteTravel.cell(site.cell)) <= float(rules().observation_cells):
			var type: Dictionary = definitions.site_types[site.type]
			body.known_sites[site_id] = {"at_ms": elapsed_ms, "quantity": 0 if str(type.item).is_empty() else inventory.quantity(site_id, type.item)}


func _decide(id: String) -> void:
	var body: Dictionary = birds[id]
	_observe(id)
	if not body.errand.is_empty():
		var purpose: String = "drop" if inventory.quantity("bird:" + id, "herb") > 0 else "pickup"
		_go(id, str(body.errand.target) if purpose == "drop" else str(body.errand.source), purpose)
	elif int(body.energy) < int(rules().rest_below) * SCALE:
		_go(id, body.home, "rest")
	elif int(body.fullness) < int(rules().eat_below) * SCALE:
		var chosen: String = ""
		var best: float = INF
		for site_id: String in sorted_keys(body.known_sites):
			if sites[site_id].type != "seeds" or int(body.known_sites[site_id].quantity) <= 0:
				continue
			var distance: float = point(body).distance_to(TileGrid.cell_to_world(SimRouteTravel.cell(sites[site_id].cell)))
			if distance < best:
				chosen = site_id
				best = distance
		if chosen.is_empty():
			_wait(id, "附近没找到够吃的草籽，暂且听风歇翅。")
		else:
			_go(id, chosen, "forage")
	else:
		_go(id, body.home, "rest")


func _go(id: String, site_id: String, purpose: String) -> bool:
	var body: Dictionary = birds[id]
	if not sites.has(site_id) or not can_enter(carrier_id(id), site_id):
		_wait(id, "身形钻不过去，只能另找落脚处。")
		return false
	var type: Dictionary = definitions.site_types[sites[site_id].type]
	var target: Vector2 = TileGrid.cell_to_world(SimRouteTravel.cell(sites[site_id].cell))
	if point(body).distance_to(target) > 0.01:
		if not bool(body.autonomous) and int(body.energy) < int(definitions.manual.min_flight_energy) * SCALE:
			_wait(id, "双翅无力；先在能落脚的近处歇息。")
			return false
		var flight_duration: int = maxi(1, ceili(point(body).distance_to(target) / float(rules().flight_speed) * 1000))
		if flight_duration > SimInventory.MAX_COUNT - elapsed_ms:
			return false
		body.active = {"id": _allocate(), "verb": "fly", "site": site_id, "purpose": purpose, "started_ms": elapsed_ms,
			"due_ms": elapsed_ms + flight_duration, "from": body.position.duplicate(), "to": [target.x, target.y]}
		body.altitude = 1
		body.goal = "振翅飞向" + str(type.label)
		return true
	if int(type.altitude) == 0 and _landing.is_valid() and not bool(_landing.call(SimRouteTravel.cell(sites[site_id].cell))):
		_wait(id, "地面无法落脚，先回避风处。")
		return false
	body.altitude = int(type.altitude)
	var duration: int = int(definitions.actions_ms[purpose])
	if duration > SimInventory.MAX_COUNT - elapsed_ms:
		return false
	body.active = {"id": _allocate(), "verb": purpose, "site": site_id, "purpose": purpose, "started_ms": elapsed_ms,
		"due_ms": elapsed_ms + duration, "from": body.position.duplicate(), "to": body.position.duplicate()}
	body.goal = {"forage": "低头啄食草籽", "rest": "在树巢避风歇翅", "pickup": "从狭口衔起药枝", "drop": "在药圃放下药枝"}.get(purpose, "听风")
	return true


func _finish(id: String) -> void:
	var body: Dictionary = birds[id]
	var action: Dictionary = body.active
	body.active = {}
	_observe(id)
	if action.verb == "fly":
		if action.purpose == "explore":
			body.retry_ms = elapsed_ms + 1
			return
		_go(id, action.site, action.purpose)
		return
	if action.purpose == "recover":
		body.retry_ms = elapsed_ms + 1
		return
	var success: bool = true
	if action.verb == "forage":
		success = inventory.consume(str(action.id) + ":eat", action.site, "seed", 1)
		if success:
			body.fullness = mini(100 * SCALE, int(body.fullness) + int(rules().seed_nourishment) * SCALE)
	elif action.verb == "pickup":
		success = can_carry(id, "herb") and inventory.transfer(str(action.id) + ":pick", action.site, "bird:" + id, "herb", 1)
		if not success or not bool(body.autonomous):
			body.errand = {}
	elif action.verb == "drop":
		var destination: String = str(sites[action.site].region)
		var village: RefCounted = world.regions[destination]
		world.synchronize_region(destination)
		success = _exchange(str(action.id) + ":delivery", inventory, "bird:" + id, village.inventory, "garden", "herb", 1, "avian", destination)
		body.errand = {}
		world.invalidate_region(destination)
	_record(str(action.verb) if success else "failed", id, action.site,
		"啄到了草籽。" if action.verb == "forage" and success else "药枝已留在药圃。" if action.verb == "drop" and success else "歇翅后继续自己的生活。" if action.verb == "rest" else "衔起了一枝药。" if action.verb == "pickup" and success else "到了近处才发现这次没办成。", {"action": action.id})
	_observe(id)
	body.retry_ms = elapsed_ms + 1


func _wait(id: String, line: String) -> void:
	birds[id].active = {}
	birds[id].goal = line
	birds[id].retry_ms = elapsed_ms + int(definitions.actions_ms.idle)


func cancel(id: String) -> bool:
	if not birds.has(id) or birds[id].active.is_empty():
		return false
	var action: Dictionary = birds[id].active
	birds[id].active = {}
	birds[id].errand = {}
	birds[id].retry_ms = elapsed_ms + int(definitions.actions_ms.idle)
	birds[id].goal = "停在原处；嘴中实物仍在。"
	if not str(action.site).is_empty():
		_record("cancelled", id, action.site, "动作中断，没有退回时间或复制嘴中的东西。", {"action": action.id})
	return true


func command_flight(id: String, direction: Vector2) -> bool:
	if not _manual_control(id) or not direction.is_finite():
		return false
	var body: Dictionary = birds[id]
	if direction.is_zero_approx():
		if body.active.get("purpose") == "explore":
			body.active = {}
			body.retry_ms = elapsed_ms + 1
			_observe(id)
		return true
	if int(body.energy) < int(definitions.manual.min_flight_energy) * SCALE:
		return false
	direction = direction.normalized()
	if body.active.get("purpose") == "explore":
		var from := Vector2(float(body.active.from[0]), float(body.active.from[1]))
		var to := Vector2(float(body.active.to[0]), float(body.active.to[1]))
		if (to - from).normalized().dot(direction) > 0.999:
			return true
	if not body.active.is_empty():
		cancel(id)
	var target: Vector2 = point(body) + direction * float(definitions.manual.leg_distance_px)
	var edge: float = float(ReolWorld.WORLD_SIZE * TileGrid.TILE_SIZE) - 1.0
	target = target.clamp(Vector2.ZERO, Vector2(edge, edge))
	if target.distance_to(point(body)) < 0.01:
		return false
	var duration: int = maxi(1, ceili(target.distance_to(point(body)) / float(rules().flight_speed) * 1000))
	if duration > SimInventory.MAX_COUNT - elapsed_ms:
		return false
	body.active = {"id": _allocate(), "verb": "fly", "site": "", "purpose": "explore", "started_ms": elapsed_ms,
		"due_ms": elapsed_ms + duration, "from": body.position.duplicate(), "to": [target.x, target.y]}
	body.altitude = 1
	body.goal = "随风振翅"
	return true


func command_land(id: String) -> Dictionary:
	if not _manual_control(id):
		return response(false, "眼下无法支配雀身。")
	if _landing.is_valid() and not bool(_landing.call(body_cell(id))):
		return response(false, "脚下没有能落足的地面；找一处空地或树巢。")
	if not birds[id].active.is_empty():
		cancel(id)
	birds[id].altitude = 0
	birds[id].goal = "落在近处听风"
	_observe(id)
	return response(true, "已经落地；振翅移动可再次起飞。")


func command_activity(id: String, verb: String) -> Dictionary:
	if not _manual_control(id) or not verb in ["forage", "rest", "pickup", "drop"]:
		return response(false, "这副身体暂时不能这样行动。")
	var body: Dictionary = birds[id]
	_observe(id)
	var target: String = body.home if verb == "rest" else _nearest_site(id, {"forage": "seeds", "pickup": "crevice", "drop": "garden"}.get(verb, ""), verb != "drop")
	if verb == "pickup" and not can_carry(id, "herb"):
		return response(false, "嘴里已装不下另一枝药。")
	if verb == "drop" and inventory.quantity("bird:" + id, "herb") < 1:
		return response(false, "嘴里还没有可放下的药枝。")
	var far_home: bool = verb == "rest" and body_cell(id).distance_to(SimRouteTravel.cell(sites[body.home].cell)) > float(rules().observation_cells)
	if verb == "rest" and (far_home or int(body.energy) < int(definitions.manual.min_flight_energy) * SCALE):
		var landed: Dictionary = command_land(id)
		if not bool(landed.ok):
			return landed
		var duration: int = int(definitions.manual.ground_rest_ms)
		if duration > SimInventory.MAX_COUNT - elapsed_ms:
			return response(false, "当前时刻已无法安排歇翅。")
		body.active = {"id": _allocate(), "verb": "rest", "site": "", "purpose": "recover", "started_ms": elapsed_ms,
			"due_ms": elapsed_ms + duration, "from": body.position.duplicate(), "to": body.position.duplicate()}
		body.goal = "在地面慢慢歇翅"
		return response(true, "在地面暂歇，恢复比避风树巢慢。")
	if target.is_empty():
		return response(false, "还不记得附近有这样的地方；先振翅观察。")
	if not body.active.is_empty():
		cancel(id)
	if verb in ["pickup", "drop"]:
		var source: String = target
		if verb == "drop":
			for event: Dictionary in events:
				if event.bird == id and event.kind == "pickup":
					source = event.site
		body.errand = {"source": source, "target": str(body.region) + ":garden" if verb == "pickup" else target, "requester": ""}
	var accepted: bool = _go(id, target, verb)
	return response(accepted, "已经动身；飞行与动手都会经过真实时间。" if accepted else "眼下没有合适的落脚或进入条件。")


func _manual_control(id: String) -> bool:
	return world.elapsed_ms == world.target_ms and birds.has(id) and not bool(birds[id].autonomous) and controls(id, "motion") and controls(id, "action")


func _exchange(operation: String, source: SimInventory, from: String, target: SimInventory, to: String, item: String, amount: int, origin: String, destination: String) -> bool:
	var signature: Dictionary = {"from": origin, "to": destination, "source": from, "target": to, "item": item, "amount": amount}
	if exchanges.has(operation):
		return Schema.same_record(exchanges[operation], signature)
	if not source.containers.has(from) or not target.containers.has(to) or amount <= 0 or source.available(from, item) < amount or amount > SimInventory.MAX_COUNT - target.quantity(to, item):
		return false
	source.containers[from][item] = source.quantity(from, item) - amount
	target.containers[to][item] = target.quantity(to, item) + amount
	exchanges[operation] = signature
	return true


func visible_to(actor: String, id: String) -> bool:
	if not birds.has(id) or not world.regions.has(birds[id].region):
		return false
	var home: String = actor_region(actor)
	if home.is_empty():
		return false
	var sim: RefCounted = world.regions[home]
	return bool(sim.actors[actor].alive) and SimRouteTravel.cell(sim.actors[actor].cell).distance_to(body_cell(id)) <= float(sim.config.observation_radius)


func actor_region(actor: String) -> String:
	for region: String in sorted_keys(world.regions):
		if world.regions[region].actors.has(actor):
			return region
	return ""


func describe(actor: String, id: String) -> Dictionary:
	if not visible_to(actor, id):
		return {"known": false}
	var body: Dictionary = birds[id]
	var sim: RefCounted = world.regions[actor_region(actor)]
	var near: bool = SimRouteTravel.cell(sim.actors[actor].cell).distance_to(body_cell(id)) <= float(rules().interaction_cells)
	var visible_action: String = {"fly": "正在振翅飞行", "forage": "正在低头啄食", "rest": "正在树巢歇翅", "pickup": "正从石隙衔取药枝", "drop": "正在落架放下药枝"}.get(str(body.active.get("verb", "")), "正停在近处听风")
	var line: String = ("一只已有灵性的麻雀，" if bool(body.get("understands_gestures", true)) else "一只普通山雀，") + visible_action + "。"
	if inventory.quantity("bird:" + id, "herb") > 0:
		line += "嘴中衔着一枝药。"
	return {"known": true, "label": body.label, "line": line, "near": near, "cell": [body_cell(id).x, body_cell(id).y], "region": body.region}


func offer_grain(actor: String, id: String) -> Dictionary:
	if not _can_talk(actor, id):
		return response(false, "先靠近看得见的小雀，再慢慢放下食物。")
	var home: String = actor_region(actor)
	world.synchronize_region(home)
	var village: RefCounted = world.regions[home]
	if not world.actor_controls(actor, "action") or not village.actors[actor].active.is_empty() or world.local_action_owns(actor) or world.artifacts.owns_actor(actor) or (world.services != null and world.services.owns_actor(actor)):
		return response(false, "双手还在忙，先结束手头的事情再投食。")
	var source: String = "actor:" + actor
	var food: String = ""
	for item: String in definitions.gift.foods:
		if village.inventory.available(source, item) >= int(definitions.gift.grain):
			food = item
			break
	if food.is_empty():
		return response(false, "身边没有可撒下的谷粮或饭食；可以先在生活页取饭。")
	var site_id: String = _nearest_site(id, "seeds", false)
	if site_id.is_empty():
		return response(false, "附近没有安全的投食处。")
	if SimRouteTravel.cell(village.actors[actor].cell).distance_to(SimRouteTravel.cell(sites[site_id].cell)) > float(rules().interaction_cells):
		return response(false, "先靠近结籽草丛，再在近处撒粮。")
	var maximum: int = SimInventory.MAX_COUNT
	if int(definitions.gift.seed) > maximum - inventory.quantity(site_id, "seed"):
		return response(false, "这处已放不下更多食物。")
	var action: String = _allocate()
	if not village.inventory.consume(action + ":grain", source, food, int(definitions.gift.grain)):
		return response(false, "谷粮已被别的事情占用。")
	inventory.containers[site_id]["seed"] = inventory.quantity(site_id, "seed") + int(definitions.gift.seed)
	_record("offered", id, site_id, "有人撒下一份粮饭，留下能啄食的碎粒。", {"actor": actor, "action": action, "food": food, "grain": int(definitions.gift.grain), "seed": int(definitions.gift.seed)})
	_observe(id)
	world.invalidate_region(home)
	return response(true, "你撒下谷粮；它看见了，但会先顾自己的饥饱与休息。")


func ask_herb(actor: String, id: String, source_id: String = "") -> Dictionary:
	if not _can_talk(actor, id):
		return response(false, "先靠近雀妖，才能比划出请求。", "unheard")
	var body: Dictionary = birds[id]
	if not bool(body.get("understands_gestures", true)):
		return response(false, "它只认得散落的食物，没听懂你比划的取药请求。", "uncomprehended")
	if not body.errand.is_empty() or int(body.fullness) < int(rules().help_min_fullness) * SCALE or int(body.energy) < int(rules().help_min_energy) * SCALE:
		return response(false, "它正有自己的事，或还需要吃东西、歇翅。", "unavailable")
	var remembers: bool = false
	for event: Dictionary in events:
		if event.kind == "offered" and event.bird == id and event.details.get("actor") == actor:
			remembers = true
		elif event.kind == "agreed" and event.bird == id and event.details.get("actor") == actor:
			remembers = false
	if not remembers:
		return response(false, "它偏头看你，还不愿为陌生人来回奔波。", "refused")
	_observe(id)
	var source: String = _nearest_site(id, "crevice", true) if source_id.is_empty() else source_id
	var target: String = str(body.region) + ":garden"
	if source.is_empty() or not sites.has(source) or sites[source].type != "crevice" or sites[source].region != body.region or not body.known_sites.has(source) or int(body.known_sites[source].quantity) <= 0 or not sites.has(target) or not can_carry(id, "herb"):
		return response(false, "它想不起那处有合适的轻药枝，或眼下衔不动。", "incapable")
	if not body.active.is_empty():
		cancel(id)
	body.errand = {"source": source, "target": target, "requester": actor}
	_record("agreed", id, source, "它记得你的投食，答应去衔一枝药。", {"actor": actor})
	_decide(id)
	return response(true, "它答应了，会从自己记得的石隙取药，再放到药圃。")


func _can_talk(actor: String, id: String) -> bool:
	return world.elapsed_ms == world.target_ms and bool(describe(actor, id).get("near", false)) and world.actor_controls(actor, "communication") and controls(id, "communication")


func _nearest_site(id: String, type: String, known_stock: bool) -> String:
	var result: String = ""
	var distance: float = INF
	for site: String in sorted_keys(birds[id].known_sites):
		if sites[site].type != type or (known_stock and int(birds[id].known_sites[site].quantity) <= 0):
			continue
		var current: float = point(birds[id]).distance_to(TileGrid.cell_to_world(SimRouteTravel.cell(sites[site].cell)))
		if current < distance:
			result = site
			distance = current
	return result


func _record(kind: String, bird: String, site: String, line: String, details: Dictionary = {}) -> void:
	events.append({"id": _allocate(), "kind": kind, "bird": bird, "site": site, "at_ms": elapsed_ms, "line": line, "details": details.duplicate(true)})


func _allocate() -> String:
	var id: String = "avian:%d" % next_id
	next_id += 1
	return id


func to_dict() -> Dictionary:
	return {"version": VERSION, "elapsed_ms": elapsed_ms, "birds": birds.duplicate(true), "sites": sites.duplicate(true), "inventory": inventory.to_dict(), "events": events.duplicate(true), "exchanges": exchanges.duplicate(true), "next_id": next_id}


static func empty_state(now: int = 0) -> Dictionary:
	return {"version": VERSION, "elapsed_ms": now, "birds": {}, "sites": {}, "inventory": {"containers": {}, "reservations": {}, "operations": {}}, "events": [], "exchanges": {}, "next_id": 1}


func restore(data: Variant) -> bool:
	if not Schema.validate(data, self):
		return false
	_assign(data)
	return true


func _assign(data: Dictionary) -> void:
	elapsed_ms = int(data.elapsed_ms)
	birds = data.birds.duplicate(true)
	sites = data.sites.duplicate(true)
	inventory = SimInventory.new()
	inventory.restore(data.inventory)
	events.assign(data.events.duplicate(true))
	exchanges = data.exchanges.duplicate(true)
	next_id = int(data.next_id)


static func sorted_keys(data: Dictionary) -> Array:
	var keys: Array = data.keys()
	keys.sort()
	return keys


static func response(ok: bool, line: String, code: String = "") -> Dictionary:
	var answer: Dictionary = {"ok": ok, "line": line}
	if not code.is_empty():
		answer.code = code
	return answer
