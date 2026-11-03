extends RefCounted

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func directory_valid(data: Dictionary, domain: RefCounted) -> bool:
	if not Shape.keys(data, ["version", "methods", "next_id"]) or data.version != 1 or not data.methods is Dictionary or not Shape.count(data.next_id, 1) or data.methods.size() != int(data.next_id) - 1:
		return false
	var parameters: Dictionary = {}
	for index: int in range(1, int(data.next_id)):
		var id: String = "heat_method:%d" % index
		var method: Variant = data.methods.get(id)
		if not Shape.keys(method, ["creator", "title", "flow", "pulses", "parent", "revision", "created_ms"]) or not method.creator is String or not domain.world.embodiment._subjects.has(method.creator) or not method.title is String or method.title.strip_edges().is_empty() or method.title.length() > int(domain.definitions.title_length) or method.title.contains("\n"):
			return false
		if not Shape.count(method.flow, 1, 3) or not Shape.count(method.pulses, 1, 10) or not domain.definitions.pulses.has(int(method.pulses)) or not Shape.count(method.revision, 1) or not Shape.count(method.created_ms, 0, domain.world.elapsed_ms) or not method.parent is String:
			return false
		if method.parent.is_empty():
			if method.revision != 1:
				return false
		else:
			var parent: Variant = data.methods.get(method.parent)
			if not parent is Dictionary or method.parent == id or int(str(method.parent).get_slice(":", 1)) >= index or parent.creator != method.creator or method.revision != int(parent.revision) + 1 or parent.created_ms > method.created_ms:
				return false
		var fingerprint: String = str(method.creator) + ":%d:%d" % [int(method.flow), int(method.pulses)]
		if parameters.has(fingerprint):
			return false
		parameters[fingerprint] = true
	return true


static func metadata_valid(meta: Variant, job: Dictionary, domain: RefCounted, records: Array, objects: Dictionary) -> bool:
	var methods: RefCounted = domain.world.heat_methods
	if not Shape.keys(meta, ["id", "mode", "guide", "consent", "guide_was_autonomous", "guide_qi"]) or methods == null or not methods.methods.has(meta.id) or not meta.mode in ["trial", "use", "learn", "record"] or not meta.guide is String or not meta.consent is String or not meta.guide_was_autonomous is bool or not Shape.count(meta.guide_qi):
		return false
	if job.verb != "charge" or not str(job.recipient).is_empty():
		return false
	if objects[job.object].definition != methods.definitions.artifact_type or methods.methods[meta.id].created_ms > job.started_ms:
		return false
	if meta.mode != "learn":
		if not meta.guide.is_empty() or not meta.consent.is_empty() or meta.guide_was_autonomous or meta.guide_qi != 0:
			return false
		if meta.mode == "record":
			return domain.world.method_records != null and domain.world.method_records.has_read(str(job.actor), str(meta.id), int(job.started_ms))
		return methods.methods[meta.id].creator == domain.world.embodiment.subject_for_actor(str(job.actor)) if meta.mode == "trial" else methods.known_from(str(job.actor), str(meta.id), records, int(job.started_ms))
	var home: String = domain.actor_home(str(job.actor))
	if meta.guide == job.actor or domain.actor_home(meta.guide) != home or meta.guide_qi != methods.definitions.guide_qi or not methods.known_from(meta.guide, str(meta.id), records, int(job.started_ms)):
		return false
	# Candidate restoration binds the raw artifact owner before cross-validation.
	return methods.consent_valid(meta.guide, str(job.actor), str(job.object), str(meta.id), meta.consent)
