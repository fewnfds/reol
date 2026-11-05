extends SceneTree
## Two independent headless processes, -- write then -- read, with an external
## 30s / 1 GiB owned-process guard. This is an isolated field/temperature QA,
## not a Main save or an item transaction. A source declaration is only the
## input from which the disposable field projection is reconstructed.
## Checkpoint only after a completed commit: pending handles/proofs are not
## serialized. An existing artifact is never overwritten.

const Cache = preload("res://scripts/sim/environment_field_cache.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Coordinator = preload("res://scripts/sim/environment_source_change.gd")
const Scenario = preload("res://tests/sim/test_environment_source_change.gd")
const Definitions = preload("res://tests/sim/test_environment_temperature_segments.gd")
const Codec = preload("res://scripts/persistence/snapshot_values.gd")

const PATH: String = "res://logs/environment_source_change_restart.json"
const SIZE := Vector2i(20, 1)
const A := Vector2i(1, 0)
const B := Vector2i(17, 0)
const HOT := [0, 0, 0, 0, 0, 1000, 0]
const COLD := [0, 0, 0, 0, 0, 0, 1000]
const ZERO := [0, 0, 0, 0, 0, 0, 0]
var failed: int = 0
var checks: int = 0
var scenario: RefCounted = Scenario.new()


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() != 1 or args[0] not in ["write", "read"]:
		_fail("expected exactly one argument: write or read")
		quit(1)
		return
	var result: Variant = _write() if args[0] == "write" else _read()
	if not result is Dictionary or result.is_empty() or failed != 0:
		if failed == 0:
			_fail("scenario did not finish")
		quit(1)
		return
	result["phase"] = args[0]
	result["checks"] = checks
	print("SOURCE_CHANGE_RESTART_JSON:", JSON.stringify(result, "", true, true))
	quit(0)


func assert_true(condition: bool, label: String) -> void:
	checks += 1
	if not condition:
		_fail(label)


func assert_eq(actual: Variant, expected: Variant, label: String) -> void:
	checks += 1
	if actual != expected:
		_fail(label + ": expected " + str(expected) + ", got " + str(actual))


func _fail(reason: String) -> void:
	failed += 1
	printerr("SOURCE_CHANGE_RESTART_ERROR: ", reason)


func _write() -> Dictionary:
	if FileAccess.file_exists(PATH):
		_fail("QA artifact already exists; refusing to overwrite " + PATH)
		return {}
	var definitions := Definitions.new()
	var settings: Dictionary = {"climate": definitions._climate(), "weather": definitions._weather(),
		"weather_epoch_ms": 0, "seed": 42, "tau_ms": 1000, "tide_grid_ms": 10_000}
	var context: Dictionary = _new_context(settings)
	if context.is_empty():
		return {}
	if not _publish(context, 0, "set", A, HOT, 0):
		return {}
	if not _publish(context, 0, "set", B, HOT, 1000):
		return {}
	if not _publish(context, 1, "set", B, COLD, 2000):
		return {}
	if not _publish(context, 1, "remove", B, COLD, 3000):
		return {}
	var declaration: Array = _declaration()
	var checkpoint: Dictionary = _checkpoint(context, settings, declaration)
	if checkpoint.is_empty() or failed != 0:
		return {}
	var checkpoint_hash: String = _hash(checkpoint)
	# The checkpoint dictionary is detached from both owners before the same
	# live writer performs the 5000ms move and produces its expected future.
	var future: Dictionary = _future(context)
	if future.is_empty() or failed != 0:
		return {}
	var future_hash: String = _hash(future)
	var document: Dictionary = {"version": 1, "checkpoint": checkpoint,
		"checkpoint_hash": checkpoint_hash, "future_hash": future_hash}
	var dir_error: Error = DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://logs"))
	if dir_error != OK:
		_fail("create ignored logs directory: " + str(dir_error))
		return {}
	# The existence check avoids overwriting a pre-existing artifact. This QA
	# path is used by one externally managed writer, not concurrent writers.
	if FileAccess.file_exists(PATH):
		_fail("QA artifact appeared before writing; refusing to overwrite")
		return {}
	var file: FileAccess = FileAccess.open(PATH, FileAccess.WRITE)
	if file == null:
		_fail("open QA artifact for writing")
		return {}
	file.store_string(Codec.canonical_json(document))
	file.flush()
	var file_error: Error = file.get_error()
	file.close()
	if file_error != OK:
		_fail("write QA artifact: " + str(file_error))
		return {}
	return {"checkpoint": checkpoint_hash, "future": future_hash, "artifact": PATH,
		"meaning": "isolated completed transaction; no Main save or item instance"}


func _read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		_fail("QA artifact does not exist; run write first")
		return {}
	var document: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not document is Dictionary or document.get("version") != 1 or not document.get("checkpoint") is Dictionary or not document.get("checkpoint_hash") is String or not document.get("future_hash") is String:
		_fail("invalid QA document shape")
		return {}
	var saved: Dictionary = document.checkpoint
	if not saved.get("settings") is Dictionary or not saved.get("temperature") is Dictionary or not saved.get("source_projection") is Array:
		_fail("missing checkpoint data")
		return {}
	if saved.temperature.is_empty():
		_fail("the actual-temperature checkpoint is empty")
		return {}
	if saved.get("at_ms") != 3000 or _hash(saved.get("size")) != _hash([SIZE.x, SIZE.y]) or saved.get("source_capacity") != 4 or saved.get("initial_c") != 20.0:
		_fail("checkpoint metadata is not this isolated scenario")
		return {}
	if _hash(saved.source_projection) != _hash(_declaration()):
		_fail("unexpected source declaration")
		return {}
	if _hash(saved) != document.checkpoint_hash:
		_fail("stored checkpoint hash does not match its data")
		return {}
	var settings: Dictionary = saved.settings.duplicate(true)
	# JSON numbers can be integral floats. The coordinator's seed contract is
	# explicitly an int, so reject other values before conversion.
	if settings.get("seed") != 42:
		_fail("unexpected seed")
		return {}
	settings.seed = 42
	var context: Dictionary = _new_context(settings, saved.temperature, saved.source_projection)
	if context.is_empty():
		return {}
	var restored: Dictionary = _checkpoint(context, settings, saved.source_projection)
	if restored.is_empty() or failed != 0:
		return {}
	var checkpoint_hash: String = _hash(restored)
	assert_eq(checkpoint_hash, document.checkpoint_hash, "independent candidate reproduces the committed checkpoint")
	if failed != 0:
		return {}
	var future: Dictionary = _future(context)
	if future.is_empty() or failed != 0:
		return {}
	var future_hash: String = _hash(future)
	assert_eq(future_hash, document.future_hash, "independent source move reproduces the canonical future")
	if failed != 0:
		return {}
	return {"checkpoint": checkpoint_hash, "future": future_hash, "artifact": PATH,
		"meaning": "isolated completed transaction; no Main save or item instance"}


func _new_context(settings: Dictionary, snapshot: Dictionary = {}, source_projection: Array = []) -> Dictionary:
	var field := Cache.new()
	var temperature := Temperature.new()
	var coordinator := Coordinator.new()
	if not field.configure(SIZE, 4):
		_fail("configure isolated field")
		return {}
	if snapshot.is_empty():
		if not temperature.configure(SIZE, 20, 0):
			_fail("configure isolated actual temperature")
			return {}
	else:
		# restore builds/validates a candidate in a fresh owner; it never mutates
		# a live Main world or infers an initial temperature from the new source.
		if not temperature.restore(snapshot):
			_fail("restore actual temperature candidate")
			return {}
		if _hash(snapshot.get("size")) != _hash([SIZE.x, SIZE.y]) or snapshot.get("capacity") != 20 or snapshot.get("last_change_ms") != 3000:
			_fail("temperature snapshot does not describe the QA checkpoint")
			return {}
		if source_projection.size() != 1:
			_fail("source projection count")
			return {}
		var source: Dictionary = source_projection[0]
		var channels: Array[int] = []
		for value: Variant in source.channels:
			channels.append(int(value))
		var cell := Vector2i(int(source.cell[0]), int(source.cell[1]))
		var rebuilt: Dictionary = field.set_source(int(source.slot), cell, int(source.radius), channels)
		if not bool(rebuilt.get("ok", false)):
			_fail("rebuild disposable source projection: " + str(rebuilt))
			return {}
	if not coordinator.configure(field, temperature, settings, Callable(scenario, "_initial")):
		_fail("bind isolated coordinator settings")
		return {}
	return {"field": field, "temperature": temperature, "coordinator": coordinator}


func _declaration() -> Array:
	return [{"slot": 0, "cell": [B.x, B.y], "radius": 1, "channels": HOT.duplicate()}]


func _publish(context: Dictionary, slot: int, operation: String, cell: Vector2i, channels: Array, at_ms: int) -> bool:
	var source: Dictionary = {"cell": cell, "radius": 1, "channels": channels.duplicate()} if operation == "set" else {}
	var prior_failures: int = failed
	var result: Variant = scenario._publish(self, context, slot, operation, source, at_ms, 256)
	if not result is Dictionary or not bool(result.get("ok", false)) or failed != prior_failures:
		if failed == prior_failures:
			_fail("source publication did not complete at " + str(at_ms))
		return false
	return true


func _channels(context: Dictionary, cell: Vector2i) -> Array:
	var prior_failures: int = failed
	var result: Variant = scenario._read_field(self, context.field, cell)
	if not result is PackedInt32Array or result.size() != 7 or failed != prior_failures:
		if failed == prior_failures:
			_fail("seven source-field channels are unavailable at " + str(cell))
		return []
	return Array(result)


func _checkpoint(context: Dictionary, settings: Dictionary, source_projection: Array) -> Dictionary:
	var field: RefCounted = context.field
	var temperature: RefCounted = context.temperature
	var at_a: Array = _channels(context, A)
	var at_b: Array = _channels(context, B)
	if at_a.size() != 7 or at_b.size() != 7:
		return {}
	assert_eq(int(field.diagnostics().source_count), 1, "checkpoint has precisely one projected source")
	assert_eq(at_a, ZERO, "checkpoint has no active source at A")
	assert_eq(at_b, HOT, "checkpoint projects the declared source at B")
	var state: Dictionary = temperature.snapshot()
	assert_eq(state.get("last_change_ms"), 3000, "checkpoint follows the completed 3000ms transaction")
	if failed != 0:
		return {}
	return {"at_ms": 3000, "size": [SIZE.x, SIZE.y], "source_capacity": 4, "initial_c": 20.0,
		"settings": settings.duplicate(true), "source_projection": source_projection.duplicate(true),
		"temperature": state, "field_a": at_a, "field_b": at_b}


func _future(context: Dictionary) -> Dictionary:
	var temperature: RefCounted = context.temperature
	var before_a: Dictionary = temperature.actual_at(A, 5000)
	var before_b: Dictionary = temperature.actual_at(B, 5000)
	if not bool(before_a.get("ok", false)) or not bool(before_b.get("ok", false)):
		_fail("pre-move actual temperature unavailable")
		return {}
	if not _publish(context, 0, "set", A, HOT, 5000):
		return {}
	var after_a: Dictionary = temperature.actual_at(A, 5000)
	var after_b: Dictionary = temperature.actual_at(B, 5000)
	assert_eq(after_a.get("value_c"), before_a.get("value_c"), "future move preserves actual A at its event")
	assert_eq(after_b.get("value_c"), before_b.get("value_c"), "future move preserves actual B at its event")
	var field_a: Array = _channels(context, A)
	var field_b: Array = _channels(context, B)
	if field_a.size() != 7 or field_b.size() != 7:
		return {}
	assert_eq(field_a, HOT, "future field projects the source at A")
	assert_eq(field_b, ZERO, "future field removes the source from B")
	var samples: Array[Dictionary] = []
	for at_ms: int in [6000, 7000]:
		for cell: Vector2i in [A, B]:
			var sample: Dictionary = temperature.actual_at(cell, at_ms)
			if not bool(sample.get("ok", false)):
				_fail("future actual sample: " + str(sample))
				return {}
			samples.append({"at_ms": at_ms, "cell": [cell.x, cell.y], "value_c": sample.value_c})
	assert_true(float(samples[2].value_c) > float(samples[0].value_c), "A continues warming after the move")
	assert_true(float(samples[3].value_c) < float(samples[1].value_c), "B continues cooling after the move")
	if failed != 0:
		return {}
	return {"temperature": temperature.snapshot(), "field_a": field_a, "field_b": field_b, "samples": samples}


func _hash(value: Variant) -> String:
	return Codec.canonical_json(Codec.normalized(value)).sha256_text()
