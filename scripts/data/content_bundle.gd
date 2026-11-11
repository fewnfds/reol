class_name ReolContentBundle
extends RefCounted
## Portable JSON definition input. The digest detects corruption, not authenticity.
## This format covers ReolContentDB documents, not all game code or scenario rules.

const VERSION: int = 3


static func from_documents(documents: Dictionary) -> Dictionary:
	if not _json_value(documents):
		return {}
	var copy: Dictionary = SnapshotValues.normalized(documents)
	return {"version": VERSION, "documents": copy, "digest": _digest(copy)}


static func is_valid(value: Variant, paths: Array[String]) -> bool:
	if not value is Dictionary or value.size() != 3 or not _version(value.get("version")):
		return false
	if not value.get("documents") is Dictionary or not value.get("digest") is String:
		return false
	var documents: Dictionary = value.documents
	var expected: Array[String] = paths.duplicate()
	if documents.size() != expected.size():
		return false
	for path: String in expected:
		if not documents.has(path):
			return false
	return _json_value(documents) and str(value.digest) == _digest(documents)


static func _version(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == VERSION


static func _digest(documents: Dictionary) -> String:
	# Normalize integral JSON numbers before hashing, including after file reload.
	return SnapshotValues.canonical_json(SnapshotValues.normalized(documents)).sha256_text()


static func _json_value(value: Variant, depth: int = 0) -> bool:
	if depth > 64:
		return false
	if value == null or value is bool or value is String:
		return true
	if value is int or value is float:
		return is_finite(float(value))
	if value is Array:
		for item: Variant in value:
			if not _json_value(item, depth + 1):
				return false
		return true
	if value is Dictionary:
		for key: Variant in value:
			if not key is String or not _json_value(value[key], depth + 1):
				return false
		return true
	return false
