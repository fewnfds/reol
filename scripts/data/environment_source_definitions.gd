class_name EnvironmentSourceDefinitions
extends RefCounted
## Immutable intrinsic profiles for the ground-source query. Current content
## bundles carry this document; a v1 bundle has no such definitions and cannot
## supply a new environment owner without an explicit migration.
## The owning session must keep the digest with any persisted candidate result.

const VERSION: int = 1
const GRADE_LIMIT: int = 10_000
const MAX_PROFILES: int = 4096
const MAX_BINDINGS: int = 16384
const MAX_IDENTIFIER: int = 128
const ELEMENTS: Array[String] = ["wood", "fire", "earth", "metal", "water"]
const RADII: Array[int] = [2, 4, 8, 16]

var _document: Dictionary = {}
var _profiles: Dictionary = {}
var _bindings: Dictionary = {}
var _digest: String = ""
var _maximum_radius: int = 0


func configure(raw: Dictionary) -> bool:
	# Never replace a live set, or publish part of an invalid candidate.
	if is_configured() or not _keys(raw, ["version", "profiles", "bindings"]):
		return false
	if not _whole(raw.version, VERSION, VERSION) or not raw.profiles is Dictionary:
		return false
	if raw.profiles.is_empty() or raw.profiles.size() > MAX_PROFILES:
		return false
	if not _keys(raw.bindings, ["artifacts", "materials"]):
		return false
	var next_profiles: Dictionary = {}
	var normalized_profiles: Dictionary = {}
	var next_radius: int = 0
	for profile_id: Variant in raw.profiles:
		if not _identifier(profile_id):
			return false
		var entry: Variant = raw.profiles[profile_id]
		if not _keys(entry, ["elements", "thermal_grade", "radius_cells", "activation", "origin"]):
			return false
		if not _keys(entry.elements, ELEMENTS):
			return false
		if not _whole(entry.thermal_grade, -GRADE_LIMIT, GRADE_LIMIT):
			return false
		if not _whole(entry.radius_cells, 1, 16) or int(entry.radius_cells) not in RADII:
			return false
		if not entry.activation is String or entry.activation != "intrinsic":
			return false
		if not entry.origin is String or entry.origin != "footprint_anchor":
			return false
		var channels: Array[int] = []
		var normalized_elements: Dictionary = {}
		for name: String in ELEMENTS:
			if not _whole(entry.elements[name], 0, GRADE_LIMIT):
				return false
			var amount: int = int(entry.elements[name])
			channels.append(amount)
			normalized_elements[name] = amount
		# A profile named none has a fixed explicit meaning; omission is distinct.
		if profile_id == "none" and (int(entry.thermal_grade) != 0 or channels != [0, 0, 0, 0, 0]):
			return false
		var radius: int = int(entry.radius_cells)
		next_radius = maxi(next_radius, radius)
		next_profiles[profile_id] = {
			"profile_id": profile_id, "elements": channels,
			"thermal_grade": int(entry.thermal_grade), "radius_cells": radius,
			"activation": "intrinsic", "origin": "footprint_anchor"
		}
		normalized_profiles[profile_id] = {
			"elements": normalized_elements, "thermal_grade": int(entry.thermal_grade),
			"radius_cells": radius, "activation": "intrinsic", "origin": "footprint_anchor"
		}
	var next_bindings: Dictionary = {"artifacts": {}, "materials": {}}
	for kind: String in ["artifacts", "materials"]:
		var source: Variant = raw.bindings[kind]
		if not source is Dictionary or source.size() > MAX_BINDINGS:
			return false
		for definition: Variant in source:
			var target: Variant = source[definition]
			if not _identifier(definition) or not _identifier(target) or not next_profiles.has(target):
				return false
			next_bindings[kind][definition] = target
	var normalized: Dictionary = {"version": VERSION, "profiles": normalized_profiles, "bindings": next_bindings}
	# Canonicalized integers and sorted keys give identical digests for equivalent
	# JSON/in-memory documents, independent of input dictionary order.
	var next_digest: String = JSON.stringify(normalized, "", true).sha256_text()
	_document = normalized
	_profiles = next_profiles
	_bindings = next_bindings
	_digest = next_digest
	_maximum_radius = next_radius
	return true


func is_configured() -> bool:
	return not _digest.is_empty()


func profile(kind: String, definition: String) -> Dictionary:
	if not is_configured():
		return {"ok": false, "reason": "not_configured"}
	var key: String
	match kind:
		"artifact":
			key = "artifacts"
		"material":
			key = "materials"
		_:
			return {"ok": false, "reason": "unsupported_kind"}
	if not _identifier(definition):
		return {"ok": false, "reason": "invalid_definition"}
	if not _bindings[key].has(definition):
		return {"ok": false, "reason": "profile_missing"}
	var result: Dictionary = _profiles[_bindings[key][definition]].duplicate(true)
	result["ok"] = true
	return result


func validate_artifacts(types: Dictionary) -> bool:
	if not is_configured():
		return false
	for definition: String in _bindings.artifacts:
		if not types.has(definition):
			return false
	return true


func digest() -> String:
	return _digest


func max_radius() -> int:
	return _maximum_radius


func to_dict() -> Dictionary:
	return _document.duplicate(true)


static func _identifier(value: Variant) -> bool:
	return value is String and not value.is_empty() and value.length() <= MAX_IDENTIFIER and value == value.strip_edges()


static func _whole(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum and float(value) == floorf(float(value))


static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true
