class_name SimEmbodiment
extends RefCounted
## Identity, residence and exclusive control. Physical truth stays at source.
## Grant/release are authority operations, never a player avatar-switch command.

const VERSION: int = 1
const CHANNELS: Array[String] = ["motion", "action", "communication"]

var _forms: Dictionary = {}
var _subjects: Dictionary = {}
var _carriers: Dictionary = {}
var _residences: Dictionary = {}
var _controls: Dictionary = {}
var _actor_subjects: Dictionary = {}
var _source_carriers: Dictionary = {}
## Dependency epoch for native action/motion, not for unrelated carriers.
var native_motion_revision: int = 0
var _control_change_guard: Callable


static func valid_forms(data: Variant) -> bool:
	if not data is Dictionary or not _keys(data, ["version", "forms"]) or data.version != VERSION or not data.forms is Dictionary or data.forms.is_empty():
		return false
	for id: Variant in data.forms:
		var form: Variant = data.forms[id]
		if not _text(id) or not form is Dictionary or not _keys(form, ["label", "width_mm", "footprint", "channels", "capabilities"]) or not _text(form.label) or not SimInventory._valid_count(form.width_mm, false):
			return false
		if not form.footprint is Array or form.footprint.size() != 2:
			return false
		for size: Variant in form.footprint:
			if not (size is int or size is float) or not is_finite(float(size)) or size != int(size) or size < 1 or size > SimInventory.MAX_COUNT:
				return false
		if not _unique_texts(form.channels) or not _unique_texts(form.capabilities):
			return false
		for channel: String in form.channels:
			if not channel in CHANNELS:
				return false
	return data.forms.has("human") and data.forms.human.channels.size() == CHANNELS.size() and data.forms.human.capabilities.has("village_routine")


func configure(definitions: Dictionary) -> bool:
	if not valid_forms(definitions):
		return false
	_forms = definitions.forms.duplicate(true)
	_subjects = {}
	_carriers = {}
	_residences = {}
	_controls = {}
	_actor_subjects = {}
	_source_carriers = {}
	native_motion_revision += 1
	return true


func add_subject(id: String, legacy_actor: String = "") -> bool:
	if not _text(id) or _subjects.has(id) or (not legacy_actor.is_empty() and _actor_subjects.has(legacy_actor)):
		return false
	_subjects[id] = {"legacy_actor": legacy_actor}
	if not legacy_actor.is_empty():
		_actor_subjects[legacy_actor] = id
		native_motion_revision += 1
	return true


func add_carrier(id: String, form_id: String, source: Dictionary) -> bool:
	if not _text(id) or _carriers.has(id) or not _forms.has(form_id) or not _keys(source, ["kind", "id"]) or not _text(source.kind) or not _text(source.id):
		return false
	if not carrier_for_source(source.kind, source.id).is_empty():
		return false
	_insert_carrier(id, form_id, source)
	if source.kind == "village_actor":
		native_motion_revision += 1
	return true


func _insert_carrier(id: String, form_id: String, source: Dictionary) -> void:
	_carriers[id] = {"form": form_id, "source": source.duplicate(true)}
	if not _source_carriers.has(source.kind):
		_source_carriers[source.kind] = {}
	_source_carriers[source.kind][source.id] = id
	_controls[id] = {}


func bind_new_creature(subject: String, carrier: String, form_id: String, source: Dictionary, channels: Array[String]) -> bool:
	# A new non-village body has no prior holders or actions. Validate the
	# entire attachment before publishing any of its identity/control records.
	if not _text(subject) or _subjects.has(subject) or not _text(carrier) or _carriers.has(carrier) or not _forms.has(form_id):
		return false
	if not _keys(source, ["kind", "id"]) or not _text(source.kind) or not _text(source.id) or source.kind == "village_actor" or not carrier_for_source(source.kind, source.id).is_empty():
		return false
	if not _unique_texts(channels):
		return false
	for channel: String in channels:
		if not _forms[form_id].channels.has(channel):
			return false
	_subjects[subject] = {"legacy_actor": ""}
	_insert_carrier(carrier, form_id, source)
	_residences[subject] = carrier
	for channel: String in channels:
		_controls[carrier][channel] = subject
	return true


func reside(subject: String, carrier: String) -> bool:
	if not _subjects.has(subject) or not _carriers.has(carrier) or (_residences.has(subject) and _residences[subject] != carrier):
		return false
	_residences[subject] = carrier
	return true


func grant_control(subject: String, carrier: String, channel: String) -> bool:
	if not _subjects.has(subject) or not _carriers.has(carrier) or not _forms[_carriers[carrier].form].channels.has(channel):
		return false
	var holder: String = str(_controls[carrier].get(channel, ""))
	if not holder.is_empty() and holder != subject:
		return false
	if holder != subject and not _prepare_control_change(carrier):
		return false
	_controls[carrier][channel] = subject
	if holder != subject and _is_native_motion_control(carrier, channel):
		native_motion_revision += 1
	return true


func release_control(subject: String, carrier: String, channel: String) -> bool:
	if not controls(subject, carrier, channel):
		return false
	if not _prepare_control_change(carrier):
		return false
	_controls[carrier].erase(channel)
	if _is_native_motion_control(carrier, channel):
		native_motion_revision += 1
	return true


func _is_native_motion_control(carrier: String, channel: String) -> bool:
	return channel in ["action", "motion"] and _carriers[carrier].source.kind == "village_actor"


func set_control_change_guard(provider: Callable) -> void:
	_control_change_guard = provider


func _prepare_control_change(carrier: String) -> bool:
	# A world-bound registry settles the original body's old interval before
	# changing control at the current world time. Pure candidate registries
	# remain independent and have no world execution hook.
	return not _control_change_guard.is_valid() or bool(_control_change_guard.call(_carriers[carrier].source.duplicate(true)))


func controls(subject: String, carrier: String, channel: String) -> bool:
	return _subjects.has(subject) and _carriers.has(carrier) and _controls[carrier].get(channel, "") == subject


func subject_for_actor(actor: String) -> String:
	return str(_actor_subjects.get(actor, ""))


func carrier_for_source(kind: String, id: String) -> String:
	# Source kind and ID already form a composite key. Runtime control/space
	# queries should not allocate dictionaries, arrays and JSON to look it up.
	return str(_source_carriers.get(kind, {}).get(id, ""))


func residence_of(subject: String) -> String:
	return str(_residences.get(subject, ""))


func capable(carrier: String, capability: String) -> bool:
	return _carriers.has(carrier) and _forms[_carriers[carrier].form].capabilities.has(capability)


func carrier_traits(carrier: String) -> Dictionary:
	# Authority-facing definition projection, never subject knowledge or control.
	if not _carriers.has(carrier):
		return {"ok": false, "reason": "not_found"}
	var record: Dictionary = _carriers[carrier]
	var form: Variant = _forms.get(record.get("form"))
	if not form is Dictionary or not _unique_texts(form.get("capabilities")) or not form.get("footprint") is Array or form.footprint.size() != 2:
		return {"ok": false, "reason": "invalid_source"}
	for dimension: Variant in form.footprint:
		if not SimInventory._valid_count(dimension, false):
			return {"ok": false, "reason": "invalid_source"}
		# Check the raw definition before Vector2i's signed 32-bit narrowing.
		# Large valid JSON integers can otherwise wrap back to a supported size.
		if dimension > 9 or int(dimension) % 2 == 0:
			return {"ok": false, "reason": "unsupported_geometry"}
	return {"ok": true, "form": record.form, "capabilities": form.capabilities.duplicate(), "footprint": footprint(carrier)}


func recognizes_capability(capability: String) -> bool:
	# Vocabulary comes from configured forms, including extensions, not names of
	# particular people. A missing declaration is distinct from an unknown term.
	for form: Dictionary in _forms.values():
		if form.capabilities.has(capability):
			return true
	return false


func footprint(carrier: String) -> Vector2i:
	if not _carriers.has(carrier):
		return Vector2i.ZERO
	var size: Array = _forms[_carriers[carrier].form].footprint
	return Vector2i(int(size[0]), int(size[1]))


func fits_opening(carrier: String, opening_mm: int) -> bool:
	return _carriers.has(carrier) and opening_mm >= 0 and (opening_mm == 0 or int(_forms[_carriers[carrier].form].width_mm) <= opening_mm)


func self_controls_actor(actor: String, channel: String) -> bool:
	return controls(subject_for_actor(actor), carrier_for_source("village_actor", actor), channel)


func matches_body_roster(actor_ids: Array[String], avian_ids: Array = [], soul_bindings: Dictionary = {}, large_ids: Array = [], plant_ids: Array = []) -> bool:
	# Every extra carrier must resolve to an actual body in its owning domain.
	if _subjects.size() != actor_ids.size() + avian_ids.size() + soul_bindings.size() + large_ids.size() + plant_ids.size() or _carriers.size() != _subjects.size() or _actor_subjects.size() != actor_ids.size():
		return false
	for id: String in plant_ids:
		var carrier: String = carrier_for_source("plant", id)
		var subject: String = "subject:plant:" + id
		if carrier != "body:plant:" + id or not _subjects.has(subject) or _subjects[subject].legacy_actor != "" or residence_of(subject) != carrier or _carriers[carrier].form != "rooted_plant":
			return false
	for actor: String in actor_ids:
		var subject: String = subject_for_actor(actor)
		var carrier: String = carrier_for_source("village_actor", actor)
		if subject.is_empty() or carrier.is_empty() or residence_of(subject) != carrier or _carriers[carrier].form != "human":
			return false
	for id: String in avian_ids:
		var carrier: String = carrier_for_source("avian_body", id)
		var subject: String = "subject:avian:" + id
		if carrier != "body:avian:" + id or not _subjects.has(subject) or _subjects[subject].legacy_actor != "" or residence_of(subject) != carrier or _carriers[carrier].form != "sparrow":
			return false
	for subject: String in soul_bindings:
		var id: String = str(soul_bindings[subject])
		var carrier: String = carrier_for_source("soul_vessel", id)
		if not subject.begins_with("subject:soul:") or carrier != "vessel:" + id or not _subjects.has(subject) or _subjects[subject].legacy_actor != "" or residence_of(subject) != carrier or _carriers[carrier].form != "soul_ring":
			return false
	for id: String in large_ids:
		var carrier: String = carrier_for_source("large_body", id)
		var subject: String = "subject:large:" + id
		if carrier != "body:large:" + id or not _subjects.has(subject) or _subjects[subject].legacy_actor != "" or residence_of(subject) != carrier or _carriers[carrier].form != "ancient_beast":
			return false
	return true


func to_dict() -> Dictionary:
	return {"version": VERSION, "subjects": _subjects.duplicate(true), "carriers": _carriers.duplicate(true), "residences": _residences.duplicate(true), "controls": _controls.duplicate(true)}


func restore(data: Dictionary) -> bool:
	if not _keys(data, ["version", "subjects", "carriers", "residences", "controls"]) or data.version != VERSION:
		return false
	for field: String in ["subjects", "carriers", "residences", "controls"]:
		if not data[field] is Dictionary:
			return false
	var candidate := SimEmbodiment.new()
	candidate._forms = _forms
	for id: Variant in data.subjects:
		var subject: Variant = data.subjects[id]
		if not _text(id) or not subject is Dictionary or not _keys(subject, ["legacy_actor"]) or not subject.legacy_actor is String or not candidate.add_subject(id, subject.legacy_actor):
			return false
	for id: Variant in data.carriers:
		var carrier: Variant = data.carriers[id]
		if not _text(id) or not carrier is Dictionary or not _keys(carrier, ["form", "source"]) or not carrier.form is String or not carrier.source is Dictionary or not candidate.add_carrier(id, carrier.form, carrier.source):
			return false
	for subject: Variant in data.residences:
		if not subject is String or not data.residences[subject] is String or not candidate.reside(subject, data.residences[subject]):
			return false
	if data.controls.size() != data.carriers.size():
		return false
	for carrier: Variant in data.controls:
		if not carrier is String or not candidate._carriers.has(carrier) or not data.controls[carrier] is Dictionary:
			return false
		for channel: Variant in data.controls[carrier]:
			var subject: Variant = data.controls[carrier][channel]
			if not channel is String or not subject is String or not candidate.grant_control(subject, carrier, channel):
				return false
	_subjects = candidate._subjects
	_carriers = candidate._carriers
	_residences = candidate._residences
	_controls = candidate._controls
	_actor_subjects = candidate._actor_subjects
	_source_carriers = candidate._source_carriers
	native_motion_revision += 1
	return true


static func human_roster_state(actor_ids: Array[String]) -> Dictionary:
	var subjects: Dictionary = {}
	var carriers: Dictionary = {}
	var residences: Dictionary = {}
	var controls_map: Dictionary = {}
	for actor: String in actor_ids:
		if not _text(actor) or subjects.has("subject:" + actor):
			return {}
		var subject: String = "subject:" + actor
		var carrier: String = "body:" + actor
		subjects[subject] = {"legacy_actor": actor}
		carriers[carrier] = {"form": "human", "source": {"kind": "village_actor", "id": actor}}
		residences[subject] = carrier
		controls_map[carrier] = {}
		for channel: String in CHANNELS:
			controls_map[carrier][channel] = subject
	return {"version": VERSION, "subjects": subjects, "carriers": carriers, "residences": residences, "controls": controls_map}


static func _keys(data: Dictionary, expected: Array) -> bool:
	if data.size() != expected.size():
		return false
	for key: Variant in data:
		if not key is String or not expected.has(key):
			return false
	return true


static func _text(value: Variant) -> bool:
	return value is String and not value.strip_edges().is_empty()


static func _unique_texts(value: Variant) -> bool:
	if not value is Array:
		return false
	var seen: Dictionary = {}
	for entry: Variant in value:
		if not _text(entry) or seen.has(entry):
			return false
		seen[entry] = true
	return true
