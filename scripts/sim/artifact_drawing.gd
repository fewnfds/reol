extends RefCounted
## Read-only readiness for the original body, tool and loose target.


static func research_readiness(domain: RefCounted, actor: String, tool: String, owned: bool = false, candidate_objects: Dictionary = {}) -> String:
	var source: Dictionary = domain.objects if candidate_objects.is_empty() else candidate_objects
	var home: String = domain.actor_home(actor)
	if home.is_empty() or not source.has(tool):
		return "找不到本人身体或引物环。"
	var item: Dictionary = source[tool]
	if not domain.definitions.types.has(item.definition) or not SimArtifacts.type_has_capability(domain.definitions.types[item.definition], "remote_draw"):
		return "这件器物没有可研究的引物纹路。"
	if item.region != home or item.container != "actor:" + actor:
		return "须由本人持环，才能循纹研究用法。"
	if not domain.shape_studied(actor, tool):
		return "先亲自辨认环身和外纹，再研究用法。"
	var reason: String = _body_readiness(domain, actor, owned)
	if not reason.is_empty():
		return reason
	if _locked(domain, tool, actor, owned):
		return "引物环正在其他过程中使用。"
	return ""


static func readiness(domain: RefCounted, actor: String, tool: String, target: String, candidate_objects: Dictionary = {}, owned: bool = false, draw: Dictionary = {}) -> String:
	var source: Dictionary = domain.objects if candidate_objects.is_empty() else candidate_objects
	var home: String = domain.actor_home(actor)
	if home.is_empty() or not source.has(tool) or not source.has(target) or tool == target:
		return "找不到引物环或选中的实物。"
	var ring: Dictionary = source[tool]
	if not domain.definitions.types.has(ring.definition):
		return "引物环的器形尚不能核清。"
	var definition: Dictionary = domain.definitions.types[ring.definition]
	if not SimArtifacts.type_has_capability(definition, "remote_draw") or not definition.has("drawing"):
		return "这件器物不能引取目标。"
	if ring.region != home or ring.container != "actor:" + actor:
		return "须由本人持环，才能引取实物。"
	if not domain.learned_use(actor, tool):
		return "须先亲自循纹研究，学会引物手法。"
	var item: Dictionary = source[target]
	if not definition.drawing.target_definitions.has(item.definition) or str(item.container).begins_with("actor:") or not domain.valid_location(item.region, item.container):
		return "只能引取眼前松置、可移动的练习木剑。"
	var reason: String = _body_readiness(domain, actor, owned)
	if not reason.is_empty():
		return reason
	if _locked(domain, tool, actor, owned) or _locked(domain, target, actor, owned):
		return "环或目标正在其他过程中使用。"
	if not domain._clear_reach(actor, str(item.region), str(item.container), float(definition.drawing.range_cells) * TileGrid.TILE_SIZE):
		return "目标须在同高、无遮挡的短距内。"
	if not draw.is_empty():
		var cell: Vector2i = domain._location_cell(str(item.region), str(item.container))
		var point: Vector2 = SimRouteTravel.point(domain.world.regions[home].actor_state(actor))
		if draw.get("target") != target or draw.get("from_region") != item.region or draw.get("from_container") != item.container or not draw.get("from_cell") is Array or draw.from_cell.size() != 2 or SimRouteTravel.cell(draw.from_cell) != cell or not draw.get("caster_position") is Array or draw.caster_position.size() != 2:
			return "目标原位置已变化，引物未能接续。"
		if point != Vector2(float(draw.caster_position[0]), float(draw.caster_position[1])):
			return "本人位置已变化，引物未能接续。"
	return ""


static func _body_readiness(domain: RefCounted, actor: String, owned: bool) -> String:
	var world: RefCounted = domain.world
	var home: String = domain.actor_home(actor)
	if home.is_empty():
		return "找不到本人身体。"
	var person: Dictionary = world.regions[home].actor_state(actor)
	if not bool(person.alive) or not world.actor_controls(actor, "action") or not world.actor_controls(actor, "motion") or not person.active.is_empty():
		return "须由本人支配活身体，并先完成手头的事情。"
	if world.body_action_owns(actor, &"artifacts") or not owned and domain.owns_actor(actor):
		return "先完成或中断手头的事情。"
	if (world.construction != null and not world.construction.duty_for(actor).is_empty()) or (world.resting != null and not world.resting.duty_for(actor).is_empty()):
		return "先完成或中断手头的事情。"
	if world.health != null and (world.health.blocks_channeling(actor) or not world.health.can_fight(actor)):
		return "身体眼下不适合稳定运气，先休养。"
	return ""


static func _locked(domain: RefCounted, id: String, actor: String, owned: bool) -> bool:
	for job: Dictionary in domain.active.values():
		if owned and job.actor == actor:
			continue
		if job.object == id or job.get("draw", {}).get("target") == id:
			return true
	var world: RefCounted = domain.world
	if world.get("private_exchange") != null and world.get("private_exchange").target_in_use(id):
		return true
	return (world.soul_vessels != null and world.soul_vessels.target_in_use(id)) or (world.spirit_sources != null and world.spirit_sources.target_in_use(id))
