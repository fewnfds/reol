extends RefCounted
## Read-only projection from a subject's experience and personally received notes.


static func has_personal_event(domain: RefCounted, actor: String, id: String, kind: String) -> bool:
	if domain.actor_home(actor).is_empty() or not domain.objects.has(id):
		return false
	var subject: String = domain.world.embodiment.subject_for_actor(actor)
	for event: Dictionary in domain.events:
		if event.object == id and event.subject == subject and event.kind == kind:
			return true
	return false


static func practiced(domain: RefCounted, actor: String, practice: String) -> bool:
	var subject: String = domain.world.embodiment.subject_for_actor(actor)
	for background: String in domain.experiences.get(subject, []):
		if domain.definitions.backgrounds[background].practice == practice:
			return true
	return false


static func describe(domain: RefCounted, actor: String, id: String) -> Dictionary:
	var home: String = domain.actor_home(actor)
	if home.is_empty() or not domain.objects.has(id):
		return {"known": false}
	var subject: String = domain.world.embodiment.subject_for_actor(actor)
	var item: Dictionary = domain.objects[id]
	var definition: Dictionary = domain.definitions.types[item.definition]
	var thermal: bool = SimArtifacts.type_has_capability(definition, "heat_storage")
	var device: bool = SimArtifacts.type_has_capability(definition, "thermal_exchange")
	var field_ring: bool = SimArtifacts.type_has_capability(definition, "remote_draw")
	var shape_studied: bool = false
	var last: Dictionary = {}
	var material: Dictionary = {}
	var method: bool = thermal and practiced(domain, actor, "warm_stone_control")
	if thermal and domain.world.heat_methods != null:
		method = method or domain.world.heat_methods.learned_base(actor, id)
	if thermal and domain.world.soul_vessels != null:
		method = method or domain.world.soul_vessels.learned(actor, id)
	var reported: Array[String] = []
	for event: Dictionary in domain.events:
		if event.object != id:
			continue
		if event.subject == subject:
			last = event
			shape_studied = shape_studied or event.kind == "studied"
			method = method or (event.kind == "use_learned" if field_ring else event.kind == "studied")
			if event.kind == "examined":
				material = event
		elif event.recipient == actor and event.kind in ["examined", "studied"]:
			last = event
			var pawn: PawnDef = domain.world._content.get_pawn(StringName(domain.world.regions[event.region].actors[event.actor].definition_id))
			var name: String = pawn.display_name if pawn != null else str(event.actor)
			reported.append("%s曾告诉你：%s" % [name, str(event.line)])
	var seeing: bool = domain.can_see(actor, id)
	if not seeing and last.is_empty():
		return {"known": false}
	var held: bool = item.region == home and item.container == "actor:" + actor
	var line: String = str(definition.appearance)
	var instruction: String = str(definition.method)
	if field_ring:
		instruction = "你已亲自学会循纹引取同高、无遮挡的短距松置木剑。" if method else str(definition.method) if shape_studied else "只能先辨看环身与外纹；真正引动物件的用法尚未掌握。"
	elif device and not method:
		instruction = "可以先循纹探查；亲自弄懂后才能启用它。"
	elif not method:
		instruction = "你还不懂它的纹路与用法。" if thermal else "它的握持与收放可以试着熟悉；能否使出剑招，仍取决于本人实际学过什么。"
	line += "\n" + instruction
	if device and seeing:
		line += "\n石上的纹路正舒展着；它已启用。" if bool(item.enabled) else "\n石上的纹路收敛着；它已关闭。"
	if thermal and held and method:
		line += "\n可将石中已有余热缓缓释在身边；这次释出的余热留在原处，石头剩余储热仍随携带者移动。"
		if domain.world.environment != null:
			var conditions: Dictionary = domain.world.environment.local_conditions(actor)
			if not conditions.is_empty():
				line += "\n此处体感：" + str(conditions.feeling) + "。"
	if thermal and seeing and int(item.damage) >= int(definition.damage_max):
		line += "\n石芯已明显崩裂，细纹断开。"
	if not material.is_empty():
		line += "\n你的辨材记录：" + str(material.line)
	if not reported.is_empty():
		line += "\n" + reported.back()
	if domain.world.soul_vessels != null:
		var lesson: String = domain.world.soul_vessels.lesson_line(actor, id)
		if not lesson.is_empty():
			line += "\n" + lesson
	if not last.is_empty() and last.subject == subject:
		line += "\n你的经历：" + str(last.line)
	var result: Dictionary = {"known": true, "label": str(definition.name) if method or field_ring and shape_studied else str(definition.unknown_name), "line": line,
		"method": method, "held": held, "near": seeing and domain._near(actor, id),
		"cell": [domain.object_cell(id).x, domain.object_cell(id).y] if seeing else last.cell.duplicate()}
	if device and seeing:
		# This qualitative switch state is only observed while seeing the object;
		# no storage amount or hidden remote state is exposed to the view.
		result["enabled"] = bool(item.enabled)
	return result


static func remembered(domain: RefCounted, actor: String, id: String) -> Dictionary:
	if not domain.objects.has(id):
		return {"known": false}
	var subject: String = domain.world.embodiment.subject_for_actor(actor)
	var last: Dictionary = {}
	var method: bool = false
	var shape_studied: bool = false
	var field_ring: bool = domain.has_capability(id, "remote_draw")
	for event: Dictionary in domain.events:
		if event.object != id:
			continue
		if event.subject == subject:
			last = event
			shape_studied = shape_studied or event.kind == "studied"
			method = method or (event.kind == "use_learned" if field_ring else event.kind == "studied")
		elif event.recipient == actor and event.kind in ["examined", "studied"]:
			last = event
	if last.is_empty():
		return {"known": false}
	var definition: Dictionary = domain.definitions.types[domain.objects[id].definition]
	return {"known": true, "label": str(definition.name) if method or field_ring and shape_studied else str(definition.unknown_name),
		"line": "你记得：%s\n眼下看不清它；这里只是上次留下的记录。" % str(last.line),
		"method": method, "held": false, "near": false, "cell": last.cell.duplicate(),
		"region": str(last.get("effect_region", last.region))}


static func material_line(domain: RefCounted, actor: String, item: Dictionary) -> String:
	var definition: Dictionary = domain.definitions.types[item.definition]
	if not SimArtifacts.type_has_capability(definition, "heat_storage"):
		return str(definition.material_cue)
	if not practiced(domain, actor, "stonecraft"):
		return "细纹与接缝互相交错；以你目前的阅历，还辨不清它能承受怎样的催动。"
	if int(item.damage) >= int(definition.damage_max):
		return "石芯的承热接缝已经崩断，继续灌注也不能恢复完整结构。"
	if int(item.damage) >= int(definition.unsafe_damage):
		return "承热接缝里有细裂；细流仍可导热，强注灵气可能把石芯撑开。"
	return "承热接缝尚完整；这能说明眼下的材料状况，不能保证反复强注无事。"
