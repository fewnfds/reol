extends RefCounted
## Focused transport tests. Full original-world restart and scale are exercised
## by the primary agent; this file never alters fixtures or the normal save.

const Transport = preload("res://scripts/persistence/environment_response_file.gd")


func run(runner: Object) -> void:
	_round_trip_and_backups(runner)
	_corruption_and_plain_data(runner)
	print("SCENARIO environment response file: streaming plain-data format, checksum, limits and protected backups")


func _round_trip_and_backups(runner: Object) -> void:
	var base: String = _path("roundtrip")
	var vector64 := PackedFloat64Array()
	var vector32 := PackedInt32Array()
	for index: int in range(0, Transport.BLOCK_BYTES / 8 + 20):
		vector64.append(float(index) * 0.125 - 30.0)
		vector32.append(index - 10000)
	var first: Dictionary = {"name": "灵石 / Reol", "deep": {"nil": null, "yes": true, "no": false,
		"negative": -9007199254740993, "positive": 9007199254740993, "fraction": 1.2345678901234567},
		"array": [0, "", [], {}, ["天地", -42]], "phase": vector64, "integers": vector32,
		"bytes": PackedByteArray([0, 1, 2, 255]), "int64": PackedInt64Array([-9223372036854775807, 0, 9223372036854775807]),
		"float32": PackedFloat32Array([0.0, -12.5, 18.25]), "empty": PackedFloat64Array(), "label": &"known"}
	var result: Dictionary = Transport.write(base, first)
	runner.assert_true(bool(result.get("ok", false)), "plain data and multi-block packed arrays write")
	if not bool(result.get("ok", false)):
		return
	var loaded: Dictionary = Transport.read(base)
	runner.assert_true(bool(loaded.get("ok", false)) and loaded.get("data") == first, "all values including doubles and >2^53 integers round-trip exactly")
	var second: Dictionary = {"different": [20, 30, "new"]}
	var saved: Dictionary = Transport.write(base, second)
	runner.assert_true(bool(saved.get("ok", false)) and not str(saved.get("backup", "")).is_empty(), "replacing a verified archive retains a backup")
	if not bool(saved.get("ok", false)):
		_cleanup(base)
		return
	var backup: String = str(saved.backup)
	runner.assert_eq(Transport.read(backup).get("data"), first, "backup contains the exact first archive")
	runner.assert_eq(Transport.read(base).get("data"), second, "replacement is the complete second archive")
	var first_backup_bytes: PackedByteArray = FileAccess.get_file_as_bytes(backup)
	var third: Dictionary = {"newest": true}
	var next: Dictionary = Transport.write(base, third)
	runner.assert_true(bool(next.get("ok", false)) and next.get("backup") != backup, "a later replacement gets a distinct backup")
	runner.assert_eq(FileAccess.get_file_as_bytes(backup), first_backup_bytes, "an older backup is never overwritten")
	if bool(next.get("ok", false)):
		runner.assert_eq(Transport.read(str(next.backup)).get("data"), second, "new backup contains the previous complete archive")
		_cleanup(str(next.backup))
	_cleanup(backup)
	_cleanup(base)


func _corruption_and_plain_data(runner: Object) -> void:
	var good: String = _path("good")
	var bad: String = _path("bad")
	var written: Dictionary = Transport.write(good, {"stable": 1, "array": [1, 2, 3]})
	if not bool(written.get("ok", false)):
		runner.assert_true(false, "corruption fixture writes")
		return
	var original: PackedByteArray = FileAccess.get_file_as_bytes(good)
	var nonfinite: Dictionary = {"stable": INF}
	runner.assert_true(not bool(Transport.write(good, nonfinite).get("ok", true)), "nonfinite data is rejected before promotion")
	runner.assert_eq(FileAccess.get_file_as_bytes(good), original, "failed new data cannot alter the previous archive")
	var object: RefCounted = RefCounted.new()
	runner.assert_true(not bool(Transport.write(good, {"object": object}).get("ok", true)), "objects are never serialized")
	runner.assert_true(not bool(Transport.write(good, {1: "key"}).get("ok", true)), "dictionary keys must be strings")
	var cycle: Array = []
	cycle.append(cycle)
	runner.assert_true(not bool(Transport.write(good, {"cycle": cycle}).get("ok", true)), "cycles cannot bypass the bounded tree depth")
	cycle.clear()
	runner.assert_eq(FileAccess.get_file_as_bytes(good), original, "unsupported input still leaves the old file untouched")
	var corrupted: PackedByteArray = original.duplicate()
	corrupted[16] = corrupted[16] ^ 1
	_write_bytes(bad, corrupted)
	runner.assert_true(not bool(Transport.read(bad).get("ok", true)), "modified bytes are never returned as a valid snapshot")
	runner.assert_true(not bool(Transport.write(bad, {"replacement": true}).get("ok", true)), "a corrupt existing primary is not replaced or used as a good backup")
	runner.assert_eq(FileAccess.get_file_as_bytes(bad), corrupted, "failed promotion preserves the corrupt original for inspection")
	_write_bytes(bad, original.slice(0, original.size() - 1))
	runner.assert_true(not bool(Transport.read(bad).get("ok", true)), "a truncated digest or tree is rejected")
	var extra: PackedByteArray = original.duplicate()
	extra.append(42)
	_write_bytes(bad, extra)
	runner.assert_true(not bool(Transport.read(bad).get("ok", true)), "trailing bytes are rejected")
	# A syntactically complete tree with a valid hash still cannot contain a
	# duplicate dictionary key; it is not silently resolved last-write-wins.
	var duplicate: PackedByteArray = Transport.MAGIC.to_utf8_buffer()
	_append_u32(duplicate, Transport.VERSION)
	duplicate.append(Transport.TAG_DICTIONARY)
	_append_u32(duplicate, 2)
	for _index: int in 2:
		duplicate.append(Transport.TAG_STRING)
		_append_u32(duplicate, 1)
		duplicate.append(97)
		duplicate.append(Transport.TAG_NIL)
	_append_hash(duplicate)
	_write_bytes(bad, duplicate)
	runner.assert_eq(Transport.read(bad).get("reason"), "dictionary_key", "valid-checksum duplicate keys are rejected")
	var excessive: PackedByteArray = Transport.MAGIC.to_utf8_buffer()
	_append_u32(excessive, Transport.VERSION)
	excessive.append(Transport.TAG_ARRAY)
	_append_u32(excessive, 0xffffffff)
	_append_hash(excessive)
	_write_bytes(bad, excessive)
	runner.assert_eq(Transport.read(bad).get("reason"), "array_limit", "untrusted container count cannot cause unbounded allocation")
	var huge_packed: PackedByteArray = Transport.MAGIC.to_utf8_buffer()
	_append_u32(huge_packed, Transport.VERSION)
	huge_packed.append(Transport.TAG_DICTIONARY)
	_append_u32(huge_packed, 1)
	huge_packed.append(Transport.TAG_STRING)
	_append_u32(huge_packed, 1)
	huge_packed.append(120)
	huge_packed.append(Transport.TAG_FLOAT64)
	_append_u32(huge_packed, 0xffffffff)
	_append_hash(huge_packed)
	_write_bytes(bad, huge_packed)
	runner.assert_eq(Transport.read(bad).get("reason"), "packed_limit", "a forged packed-array length is rejected before allocation")
	var node: PackedByteArray = Transport.MAGIC.to_utf8_buffer()
	_append_u32(node, Transport.VERSION)
	node.append(255)
	_append_hash(node)
	_write_bytes(bad, node)
	runner.assert_eq(Transport.read(bad).get("reason"), "invalid_tag", "unknown/object tags are not instantiated")
	var utf8: PackedByteArray = Transport.MAGIC.to_utf8_buffer()
	_append_u32(utf8, Transport.VERSION)
	utf8.append(Transport.TAG_DICTIONARY)
	_append_u32(utf8, 1)
	utf8.append(Transport.TAG_STRING)
	_append_u32(utf8, 2)
	utf8.append(0xC0) # overlong encoding of zero
	utf8.append(0x80)
	utf8.append(Transport.TAG_NIL)
	_append_hash(utf8)
	_write_bytes(bad, utf8)
	runner.assert_eq(Transport.read(bad).get("reason"), "dictionary_key", "invalid UTF-8 keys are refused without an engine decoding error")
	_cleanup(bad)
	_cleanup(good)


func _path(label: String) -> String:
	return "user://response_file_test_%d_%d_%s.bin" % [OS.get_process_id(), Time.get_ticks_usec(), label]


func _write_bytes(path: String, bytes: PackedByteArray) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file != null:
		file.store_buffer(bytes)
		file.close()


func _append_u32(bytes: PackedByteArray, value: int) -> void:
	var offset: int = bytes.size()
	bytes.resize(offset + 4)
	bytes.encode_u32(offset, value)


func _append_hash(bytes: PackedByteArray) -> void:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	bytes.append_array(context.finish())


func _cleanup(path: String) -> void:
	var absolute: String = ProjectSettings.globalize_path(path) if path.begins_with("user://") else path
	if FileAccess.file_exists(absolute):
		DirAccess.remove_absolute(absolute)
