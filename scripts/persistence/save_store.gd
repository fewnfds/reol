class_name SimSaveStore
extends RefCounted
## JSON transport only. The runtime owns schema versions and state validation.
## A verified temporary file replaces the primary only after its backup exists.

const MAX_JSON_INTEGER: int = 9007199254740991
const MAX_JSON_DEPTH: int = 64


static func save_file(path: String, data: Dictionary) -> Error:
	var resolved: String = _resolve_path(path)
	if resolved.is_empty():
		return ERR_INVALID_PARAMETER
	if not _valid_json_value(data):
		return ERR_INVALID_DATA
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(resolved.get_base_dir())
	if directory_error != OK:
		return directory_error
	var temporary: String = resolved + ".tmp"
	var write_error: Error = _write_verified(temporary, data)
	if write_error != OK:
		return write_error
	var had_previous: bool = FileAccess.file_exists(resolved)
	var backup: String = resolved + ".bak"
	if had_previous:
		# Do not replace a potentially good backup with a corrupt primary.
		var previous: Dictionary = load_file(resolved)
		if not previous["ok"]:
			return previous["error"]
		var backup_temporary: String = backup + ".tmp"
		var backup_error: Error = DirAccess.copy_absolute(resolved, backup_temporary)
		if backup_error != OK:
			return backup_error
		var verified_backup: Dictionary = load_file(backup_temporary)
		if not verified_backup["ok"]:
			return verified_backup["error"]
		if (
			FileAccess.get_file_as_string(backup_temporary)
			!= FileAccess.get_file_as_string(resolved)
		):
			return ERR_FILE_CORRUPT
		backup_error = DirAccess.rename_absolute(backup_temporary, backup)
		if backup_error != OK:
			return backup_error
	var replace_error: Error = DirAccess.rename_absolute(temporary, resolved)
	if replace_error != OK and had_previous and not FileAccess.file_exists(resolved):
		# Some platforms can remove a destination before a failed replacement.
		# Keep the backup in place even if restoring the primary also fails.
		var recovery_error: Error = DirAccess.copy_absolute(backup, resolved)
		if recovery_error != OK:
			return recovery_error
	return replace_error


static func load_file(path: String) -> Dictionary:
	var resolved: String = _resolve_path(path)
	if resolved.is_empty():
		return _failure(ERR_INVALID_PARAMETER, "Expected a user:// or absolute save path.")
	var file: FileAccess = FileAccess.open(resolved, FileAccess.READ)
	if file == null:
		var open_error: Error = FileAccess.get_open_error()
		return _failure(open_error, "Cannot open save file: %s" % error_string(open_error))
	var contents: String = file.get_as_text()
	var read_error: Error = file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return _failure(read_error, "Cannot read save file: %s" % error_string(read_error))
	var parser := JSON.new()
	var parse_error: Error = parser.parse(contents)
	if parse_error != OK:
		return _failure(
			parse_error,
			"Invalid save JSON at line %d: %s"
			% [parser.get_error_line(), parser.get_error_message()]
		)
	if not parser.data is Dictionary:
		return _failure(ERR_INVALID_DATA, "Save JSON must contain an object at the top level.")
	var data: Dictionary = parser.data
	if not _valid_json_value(data):
		return _failure(ERR_INVALID_DATA, "Save JSON contains unsupported values or nesting.")
	return {"ok": true, "data": data, "error": OK, "message": ""}


static func _write_verified(path: String, data: Dictionary) -> Error:
	var contents: String = JSON.stringify(data, "\t", true, true)
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(contents)
	file.flush()
	var write_error: Error = file.get_error()
	file.close()
	if write_error != OK:
		return write_error
	var loaded: Dictionary = load_file(path)
	if not loaded["ok"]:
		return loaded["error"]
	if FileAccess.get_file_as_string(path) != contents:
		return ERR_FILE_CORRUPT
	return OK


static func _resolve_path(path: String) -> String:
	if path.strip_edges().is_empty() or path.begins_with("res://"):
		return ""
	if path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	return ""


static func _failure(error: Error, message: String) -> Dictionary:
	return {"ok": false, "data": {}, "error": error, "message": message}


static func _valid_json_value(value: Variant, depth: int = 0) -> bool:
	if depth > MAX_JSON_DEPTH:
		return false
	match typeof(value):
		TYPE_NIL, TYPE_BOOL, TYPE_STRING:
			return true
		TYPE_INT:
			return value >= -MAX_JSON_INTEGER and value <= MAX_JSON_INTEGER
		TYPE_FLOAT:
			return is_finite(float(value))
		TYPE_ARRAY:
			for child: Variant in value:
				if not _valid_json_value(child, depth + 1):
					return false
			return true
		TYPE_DICTIONARY:
			for key: Variant in value:
				if not key is String or not _valid_json_value(value[key], depth + 1):
					return false
			return true
	return false
