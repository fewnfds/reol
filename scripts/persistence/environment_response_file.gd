class_name EnvironmentResponseFile
extends RefCounted
## Bounded streaming transport for a closed development environment snapshot.
## It owns no world or game-save schema; EnvironmentResponseSnapshot still
## validates the complete detached candidate before it can replace anything.
##
## Format 1: 8-byte magic, little-endian u32 version, a tagged plain-data tree,
## then SHA-256 of every preceding byte. No Object is deserialized. Arrays and
## dictionaries are written incrementally, including the original world, so no
## whole-archive JSON/string/byte buffer or general Variant decoder is needed.
## A reader never publishes a partial tree and rejects unbounded allocation,
## malformed values, duplicate keys, extra bytes and checksum mismatch.

const MAGIC: String = "REOLERF1"
const VERSION: int = 1
const BLOCK_BYTES: int = 65536
const MAX_STRING_BYTES: int = 1_048_576
const MAX_PACKED_BYTES: int = 134_217_728
const MAX_FILE_BYTES: int = 2_147_483_648
const MAX_NODES: int = 64_000_000
const MAX_DEPTH: int = 64
const HASH_BYTES: int = 32

const TAG_NIL: int = 0
const TAG_FALSE: int = 1
const TAG_TRUE: int = 2
const TAG_INT: int = 3
const TAG_FLOAT: int = 4
const TAG_STRING: int = 5
const TAG_STRING_NAME: int = 6
const TAG_ARRAY: int = 7
const TAG_DICTIONARY: int = 8
const TAG_BYTES: int = 9
const TAG_INT32: int = 10
const TAG_INT64: int = 11
const TAG_FLOAT32: int = 12
const TAG_FLOAT64: int = 13


static func write(path: String, snapshot: Dictionary) -> Dictionary:
	var target: String = _resolve(path)
	if target.is_empty():
		return _failure("invalid_path")
	var directory_error: Error = DirAccess.make_dir_recursive_absolute(target.get_base_dir())
	if directory_error != OK:
		return _failure("directory_unavailable", directory_error)
	# A distinct path, never a predictable .tmp that could belong to the user.
	var temporary: String = _unused_path(target + ".tmp")
	if temporary.is_empty():
		return _failure("temporary_name_exhausted")
	var writer := Writer.new()
	var created: Dictionary = writer.write_to(temporary, snapshot)
	if not bool(created.get("ok", false)):
		_remove_owned(temporary)
		return created
	# Re-read the complete plain-data archive before changing any prior file.
	var verified: Dictionary = _read_file(temporary, false)
	if not bool(verified.get("ok", false)):
		_remove_owned(temporary)
		return _failure("temporary_verification_failed")
	var prepared: Dictionary = _prepare_recovery(target)
	if not bool(prepared.get("ok", false)):
		_remove_owned(temporary)
		return prepared
	var backup: String = str(prepared.get("backup", ""))
	if bool(prepared.get("had_primary", false)):
		backup = _unused_path(target + ".bak")
		if backup.is_empty():
			_remove_owned(temporary)
			var failed: Dictionary = _failure("backup_name_exhausted")
			failed["rotated_recovery"] = str(prepared.get("rotated_recovery", ""))
			return failed
		var renamed: Error = DirAccess.rename_absolute(target, backup)
		if renamed != OK:
			_remove_owned(temporary)
			var failed: Dictionary = _failure("backup_failed", renamed)
			failed["rotated_recovery"] = str(prepared.get("rotated_recovery", ""))
			return failed
	var promoted: Error = DirAccess.rename_absolute(temporary, target)
	if promoted != OK:
		# A restoration is first copied and validated at a distinct path. A
		# partial direct copy to target would hide the usable recovery file.
		var restored: Error = OK
		if not backup.is_empty() and not _path_exists(target):
			restored = _restore_primary(target)
		_remove_owned(temporary)
		var failed: Dictionary = _failure("promotion_failed", promoted)
		if restored != OK:
			failed = _failure("promotion_and_recovery_failed", restored)
			failed["promotion_error"] = promoted
		failed["backup"] = backup
		failed["recovery"] = target + ".recovery"
		failed["rotated_recovery"] = str(prepared.get("rotated_recovery", ""))
		return failed
	return {"ok": true, "bytes": int(created.bytes), "backup": backup,
		"rotated_recovery": str(prepared.get("rotated_recovery", ""))}


static func read(path: String) -> Dictionary:
	var target: String = _resolve(path)
	if target.is_empty():
		return _failure("invalid_path")
	# Never turn a corrupt, unsupported, unreadable, directory or dangling-link
	# primary into an apparently successful load from an older history.
	if _path_exists(target):
		var primary: Dictionary = _read_file(target, true)
		if bool(primary.get("ok", false)):
			primary["recovered"] = false
		return primary
	var recovery: String = target + ".recovery"
	if not _path_exists(recovery):
		return _read_file(target, true)
	if not FileAccess.file_exists(recovery) or _is_link(recovery):
		return _failure("recovery_path_occupied")
	var recovered: Dictionary = _read_file(recovery, true)
	if bool(recovered.get("ok", false)):
		recovered["recovered"] = true
		recovered["recovery_path"] = recovery
	return recovered


# Call only after the new temporary archive is complete and validated. The
# fixed recovery path is readable if a process stops between the two renames.
# Operations on the same target require a single writer and no external edits.
static func _prepare_recovery(target: String) -> Dictionary:
	var recovery: String = target + ".recovery"
	var rotated: String = ""
	if _path_exists(target):
		if not FileAccess.file_exists(target) or _is_link(target):
			return _failure("existing_file_invalid")
		var previous: Dictionary = _read_file(target, false)
		if not bool(previous.get("ok", false)):
			return _failure("existing_file_invalid")
		if _path_exists(recovery):
			# Preserve even an incomplete copy from a stopped process or an
			# unrelated pre-existing file. Never overwrite a directory/link.
			if not FileAccess.file_exists(recovery) or _is_link(recovery):
				return _failure("recovery_path_occupied")
			rotated = _unused_path(recovery + ".bak")
			if rotated.is_empty():
				return _failure("recovery_backup_name_exhausted")
			var rotated_error: Error = DirAccess.rename_absolute(recovery, rotated)
			if rotated_error != OK:
				return _failure("recovery_backup_failed", rotated_error)
		var copied: Error = DirAccess.copy_absolute(target, recovery)
		if copied != OK:
			var failed: Dictionary = _failure("recovery_copy_failed", copied)
			failed["rotated_recovery"] = rotated
			return failed
		if not bool(_read_file(recovery, false).get("ok", false)):
			var failed: Dictionary = _failure("recovery_verification_failed")
			failed["rotated_recovery"] = rotated
			return failed
		return {"ok": true, "had_primary": true, "backup": "", "rotated_recovery": rotated}
	# If a former promotion stopped, the fixed recovery is the only known good
	# copy. Do not rotate or overwrite it before the new primary is installed.
	if _path_exists(recovery):
		if not FileAccess.file_exists(recovery) or _is_link(recovery):
			return _failure("recovery_path_occupied")
		if not bool(_read_file(recovery, false).get("ok", false)):
			return _failure("recovery_file_invalid")
		var backup: String = _unused_path(target + ".bak")
		if backup.is_empty():
			return _failure("backup_name_exhausted")
		var copied: Error = DirAccess.copy_absolute(recovery, backup)
		if copied != OK:
			_remove_owned(backup)
			return _failure("backup_failed", copied)
		if not bool(_read_file(backup, false).get("ok", false)):
			_remove_owned(backup)
			return _failure("backup_verification_failed")
		return {"ok": true, "had_primary": false, "backup": backup, "rotated_recovery": ""}
	return {"ok": true, "had_primary": false, "backup": "", "rotated_recovery": ""}


# Keep target absent until a complete recovery copy has been verified.
static func _restore_primary(target: String) -> Error:
	var restoration: String = _unused_path(target + ".restore")
	if restoration.is_empty():
		return ERR_CANT_CREATE
	var copied: Error = DirAccess.copy_absolute(target + ".recovery", restoration)
	if copied != OK:
		_remove_owned(restoration)
		return copied
	if not bool(_read_file(restoration, false).get("ok", false)):
		_remove_owned(restoration)
		return ERR_INVALID_DATA
	if _path_exists(target):
		_remove_owned(restoration)
		return ERR_ALREADY_IN_USE
	var renamed: Error = DirAccess.rename_absolute(restoration, target)
	if renamed != OK:
		_remove_owned(restoration)
	return renamed


static func _read_file(path: String, materialize: bool) -> Dictionary:
	var reader := Reader.new()
	return reader.read_from(path, materialize)


static func _resolve(path: String) -> String:
	if path.strip_edges().is_empty() or path.begins_with("res://"):
		return ""
	if path.begins_with("user://"):
		return ProjectSettings.globalize_path(path).simplify_path()
	if path.is_absolute_path():
		return path.simplify_path()
	return ""


# Include directories and links (including dangling links) when checking a
# destination. A parent directory that cannot be inspected fails closed.
static func _path_exists(path: String) -> bool:
	var parent: DirAccess = DirAccess.open(path.get_base_dir())
	return parent == null or parent.is_link(path) or parent.file_exists(path) or DirAccess.dir_exists_absolute(path)


static func _is_link(path: String) -> bool:
	var parent: DirAccess = DirAccess.open(path.get_base_dir())
	return parent == null or parent.is_link(path)


static func _unused_path(prefix: String) -> String:
	var stem: String = prefix + ".%d.%d" % [OS.get_process_id(), Time.get_ticks_usec()]
	for attempt: int in 32:
		var candidate: String = stem + "." + str(attempt)
		if not _path_exists(candidate):
			return candidate
	return ""


static func _remove_owned(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)


static func _failure(reason: String, error: int = ERR_INVALID_DATA) -> Dictionary:
	return {"ok": false, "reason": reason, "error": error}


class Writer:
	extends RefCounted
	var file: FileAccess
	var hash: HashingContext
	var buffer := PackedByteArray()
	var failure: String = ""
	var nodes: int = 0

	func write_to(path: String, data: Dictionary) -> Dictionary:
		file = FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			return EnvironmentResponseFile._failure("temporary_open_failed", FileAccess.get_open_error())
		hash = HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256) != OK:
			file.close()
			return EnvironmentResponseFile._failure("hash_unavailable")
		_append(MAGIC.to_utf8_buffer())
		_u32(VERSION)
		_value(data, 0)
		_flush_buffer()
		if failure.is_empty():
			var digest: PackedByteArray = hash.finish()
			if digest.size() != HASH_BYTES or file.get_position() > MAX_FILE_BYTES - HASH_BYTES or not file.store_buffer(digest):
				failure = "write_failed"
		file.flush()
		if file.get_error() != OK and failure.is_empty():
			failure = "write_failed"
		var bytes: int = file.get_position()
		file.close()
		if not failure.is_empty():
			return EnvironmentResponseFile._failure(failure)
		return {"ok": true, "bytes": bytes}

	func _value(value: Variant, depth: int) -> void:
		if not failure.is_empty():
			return
		if depth > MAX_DEPTH or nodes >= MAX_NODES:
			failure = "tree_limit"
			return
		nodes += 1
		match typeof(value):
			TYPE_NIL: _u8(TAG_NIL)
			TYPE_BOOL: _u8(TAG_TRUE if value else TAG_FALSE)
			TYPE_INT:
				_u8(TAG_INT)
				_s64(int(value))
			TYPE_FLOAT:
				if not is_finite(float(value)):
					failure = "nonfinite_number"
					return
				_u8(TAG_FLOAT)
				_f64(float(value))
			TYPE_STRING, TYPE_STRING_NAME:
				_u8(TAG_STRING_NAME if value is StringName else TAG_STRING)
				_string(str(value))
			TYPE_ARRAY:
				if value.size() > MAX_NODES - nodes:
					failure = "tree_limit"
					return
				_u8(TAG_ARRAY)
				_u32(value.size())
				for child: Variant in value:
					_value(child, depth + 1)
					if not failure.is_empty():
						return
			TYPE_DICTIONARY:
				if value.size() > (MAX_NODES - nodes) / 2:
					failure = "tree_limit"
					return
				_u8(TAG_DICTIONARY)
				_u32(value.size())
				for key: Variant in value:
					if not key is String:
						failure = "dictionary_key_type"
						return
					_value(key, depth + 1)
					_value(value[key], depth + 1)
					if not failure.is_empty():
						return
			TYPE_PACKED_BYTE_ARRAY, TYPE_PACKED_INT32_ARRAY, TYPE_PACKED_INT64_ARRAY, TYPE_PACKED_FLOAT32_ARRAY, TYPE_PACKED_FLOAT64_ARRAY:
				_packed(value)
			_:
				failure = "unsupported_type"

	func _packed(value: Variant) -> void:
		var tag: int
		var width: int
		match typeof(value):
			TYPE_PACKED_BYTE_ARRAY: tag = TAG_BYTES; width = 1
			TYPE_PACKED_INT32_ARRAY: tag = TAG_INT32; width = 4
			TYPE_PACKED_INT64_ARRAY: tag = TAG_INT64; width = 8
			TYPE_PACKED_FLOAT32_ARRAY: tag = TAG_FLOAT32; width = 4
			TYPE_PACKED_FLOAT64_ARRAY: tag = TAG_FLOAT64; width = 8
		if value.size() > MAX_PACKED_BYTES / width:
			failure = "packed_limit"
			return
		if tag == TAG_FLOAT32 or tag == TAG_FLOAT64:
			for item: float in value:
				if not is_finite(item):
					failure = "nonfinite_number"
					return
		_u8(tag)
		_u32(value.size())
		var per_block: int = BLOCK_BYTES / width
		for first: int in range(0, value.size(), per_block):
			var last: int = mini(value.size(), first + per_block)
			var part: Variant = value.slice(first, last)
			var bytes: PackedByteArray = part if tag == TAG_BYTES else part.to_byte_array()
			_append(bytes)
			if not failure.is_empty():
				return

	func _string(value: String) -> void:
		var bytes: PackedByteArray = value.to_utf8_buffer()
		if bytes.size() > MAX_STRING_BYTES:
			failure = "string_limit"
			return
		_u32(bytes.size())
		_append(bytes)

	func _u8(value: int) -> void:
		buffer.append(value)
		_if_full()

	func _u32(value: int) -> void:
		var offset: int = buffer.size()
		buffer.resize(offset + 4)
		buffer.encode_u32(offset, value)
		_if_full()

	func _s64(value: int) -> void:
		var offset: int = buffer.size()
		buffer.resize(offset + 8)
		buffer.encode_s64(offset, value)
		_if_full()

	func _f64(value: float) -> void:
		var offset: int = buffer.size()
		buffer.resize(offset + 8)
		buffer.encode_double(offset, value)
		_if_full()

	func _append(bytes: PackedByteArray) -> void:
		buffer.append_array(bytes)
		_if_full()

	func _if_full() -> void:
		if buffer.size() >= BLOCK_BYTES:
			_flush_buffer()

	func _flush_buffer() -> void:
		if not failure.is_empty() or buffer.is_empty():
			return
		if file.get_position() > MAX_FILE_BYTES - HASH_BYTES - buffer.size() or hash.update(buffer) != OK or not file.store_buffer(buffer):
			failure = "write_failed"
		buffer.clear()


class Reader:
	extends RefCounted
	var file: FileAccess
	var hash: HashingContext
	var buffer := PackedByteArray()
	var cursor: int = 0
	var consumed: int = 0
	var body_end: int = 0
	var failure: String = ""
	var nodes: int = 0
	var materialize: bool = false

	func read_from(path: String, keep_data: bool) -> Dictionary:
		file = FileAccess.open(path, FileAccess.READ)
		if file == null:
			return EnvironmentResponseFile._failure("open_failed", FileAccess.get_open_error())
		var length: int = file.get_length()
		if length < MAGIC.length() + 4 + 1 + HASH_BYTES or length > MAX_FILE_BYTES:
			file.close()
			return EnvironmentResponseFile._failure("file_size")
		body_end = length - HASH_BYTES
		materialize = keep_data
		hash = HashingContext.new()
		if hash.start(HashingContext.HASH_SHA256) != OK:
			file.close()
			return EnvironmentResponseFile._failure("hash_unavailable")
		if _take(MAGIC.length()) != MAGIC.to_utf8_buffer() or _u32() != VERSION:
			file.close()
			return EnvironmentResponseFile._failure("format_version")
		var value: Variant = _value(0)
		if failure.is_empty() and not value is Dictionary:
			failure = "root_type"
		if failure.is_empty() and consumed != body_end:
			failure = "trailing_data"
		if failure.is_empty():
			var actual: PackedByteArray = hash.finish()
			var expected: PackedByteArray = file.get_buffer(HASH_BYTES)
			if expected.size() != HASH_BYTES or actual != expected:
				failure = "checksum"
		file.close()
		if not failure.is_empty():
			return EnvironmentResponseFile._failure(failure)
		return {"ok": true, "data": value if keep_data else {}, "bytes": length}

	func _value(depth: int) -> Variant:
		if not failure.is_empty():
			return null
		if depth > MAX_DEPTH or nodes >= MAX_NODES:
			failure = "tree_limit"
			return null
		nodes += 1
		var tag: int = _u8()
		match tag:
			TAG_NIL: return null
			TAG_FALSE: return false
			TAG_TRUE: return true
			TAG_INT: return _s64()
			TAG_FLOAT:
				var number: float = _f64()
				if not is_finite(number):
					failure = "nonfinite_number"
				return number
			TAG_STRING, TAG_STRING_NAME:
				var value: String = _string()
				return StringName(value) if tag == TAG_STRING_NAME else value
			TAG_ARRAY:
				var count: int = _u32()
				if count > MAX_NODES - nodes or count > body_end - consumed:
					failure = "array_limit"
					return null
				var array: Array = []
				for _index: int in count:
					var child: Variant = _value(depth + 1)
					if not failure.is_empty():
						return null
					if materialize:
						array.append(child)
				return array
			TAG_DICTIONARY:
				var count: int = _u32()
				if count > (MAX_NODES - nodes) / 2 or count > (body_end - consumed) / 2:
					failure = "dictionary_limit"
					return null
				var dictionary: Dictionary = {}
				for _index: int in count:
					var key: Variant = _value(depth + 1)
					if not failure.is_empty() or not key is String or dictionary.has(key):
						failure = "dictionary_key"
						return null
					var child: Variant = _value(depth + 1)
					if not failure.is_empty():
						return null
					# Validation mode stores only keys, not nested child trees.
					dictionary[key] = child if materialize else null
				return dictionary
			TAG_BYTES, TAG_INT32, TAG_INT64, TAG_FLOAT32, TAG_FLOAT64:
				return _packed(tag)
			_:
				failure = "invalid_tag"
				return null

	func _packed(tag: int) -> Variant:
		var width: int = 1 if tag == TAG_BYTES else (4 if tag in [TAG_INT32, TAG_FLOAT32] else 8)
		var count: int = _u32()
		if count > MAX_PACKED_BYTES / width or count > (body_end - consumed) / width:
			failure = "packed_limit"
			return null
		var result: Variant
		match tag:
			TAG_BYTES: result = PackedByteArray()
			TAG_INT32: result = PackedInt32Array()
			TAG_INT64: result = PackedInt64Array()
			TAG_FLOAT32: result = PackedFloat32Array()
			TAG_FLOAT64: result = PackedFloat64Array()
		var per_block: int = BLOCK_BYTES / width
		var remaining: int = count
		while remaining > 0:
			var n: int = mini(remaining, per_block)
			var bytes: PackedByteArray = _take(n * width)
			if not failure.is_empty():
				return null
			var part: Variant
			match tag:
				TAG_BYTES: part = bytes
				TAG_INT32: part = bytes.to_int32_array()
				TAG_INT64: part = bytes.to_int64_array()
				TAG_FLOAT32: part = bytes.to_float32_array()
				TAG_FLOAT64: part = bytes.to_float64_array()
			if tag == TAG_FLOAT32 or tag == TAG_FLOAT64:
				for item: float in part:
					if not is_finite(item):
						failure = "nonfinite_number"
						return null
			if materialize:
				result.append_array(part)
			remaining -= n
		return result

	func _string() -> String:
		var length: int = _u32()
		if length > MAX_STRING_BYTES or length > body_end - consumed:
			failure = "string_limit"
			return ""
		var bytes: PackedByteArray = _take(length)
		if not failure.is_empty():
			return ""
		if not _valid_utf8(bytes):
			failure = "invalid_utf8"
			return ""
		var value: String = bytes.get_string_from_utf8()
		if value.to_utf8_buffer() != bytes:
			failure = "invalid_utf8"
		return value

	func _valid_utf8(bytes: PackedByteArray) -> bool:
		# Validate malformed input without passing it into the engine's UTF-8
		# decoder, which can emit engine errors while rejecting a corrupt file.
		var index: int = 0
		while index < bytes.size():
			var first: int = bytes[index]
			if first < 0x80:
				index += 1
				continue
			var width: int = 0
			if first >= 0xC2 and first <= 0xDF:
				width = 2
			elif first >= 0xE0 and first <= 0xEF:
				width = 3
			elif first >= 0xF0 and first <= 0xF4:
				width = 4
			else:
				return false
			if index + width > bytes.size():
				return false
			var second: int = bytes[index + 1]
			if second < 0x80 or second > 0xBF:
				return false
			# Exclude overlong forms, UTF-16 surrogates and >U+10FFFF.
			if (first == 0xE0 and second < 0xA0) or (first == 0xED and second > 0x9F) or (first == 0xF0 and second < 0x90) or (first == 0xF4 and second > 0x8F):
				return false
			for offset: int in range(2, width):
				if bytes[index + offset] < 0x80 or bytes[index + offset] > 0xBF:
					return false
			index += width
		return true

	func _u8() -> int:
		if not _ensure(1): return 0
		var result: int = buffer[cursor]
		cursor += 1
		consumed += 1
		return result

	func _u32() -> int:
		if not _ensure(4): return 0
		var result: int = buffer.decode_u32(cursor)
		cursor += 4
		consumed += 4
		return result

	func _s64() -> int:
		if not _ensure(8): return 0
		var result: int = buffer.decode_s64(cursor)
		cursor += 8
		consumed += 8
		return result

	func _f64() -> float:
		if not _ensure(8): return 0.0
		var result: float = buffer.decode_double(cursor)
		cursor += 8
		consumed += 8
		return result

	func _take(length: int) -> PackedByteArray:
		var result := PackedByteArray()
		if length < 0 or length > body_end - consumed:
			failure = "truncated"
			return result
		var remaining: int = length
		while remaining > 0:
			if not _ensure(1):
				return PackedByteArray()
			var amount: int = mini(remaining, buffer.size() - cursor)
			result.append_array(buffer.slice(cursor, cursor + amount))
			cursor += amount
			consumed += amount
			remaining -= amount
		return result

	func _ensure(required: int) -> bool:
		if not failure.is_empty():
			return false
		if required > body_end - consumed:
			failure = "truncated"
			return false
		if buffer.size() - cursor >= required:
			return true
		buffer = buffer.slice(cursor)
		cursor = 0
		var unread: int = body_end - file.get_position()
		var read_size: int = mini(BLOCK_BYTES, unread)
		if read_size > 0:
			var next: PackedByteArray = file.get_buffer(read_size)
			if next.size() != read_size or hash.update(next) != OK:
				failure = "read_failed"
				return false
			buffer.append_array(next)
		if buffer.size() < required:
			failure = "truncated"
			return false
		return true
