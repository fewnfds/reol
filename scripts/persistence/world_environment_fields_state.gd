class_name WorldEnvironmentFieldsState
extends RefCounted
## JSON snapshot for the ordinary composed field authority. Restoration is for
## an independent regional candidate only: on any failure the caller discards
## that candidate and never replaces the live world.

const Values = preload("res://scripts/persistence/snapshot_values.gd")
const Shape = preload("res://scripts/sim/avian_schema.gd")
const Rules = preload("res://scripts/sim/environment_field_rules.gd")
const Response = preload("res://scripts/sim/environment_field_response.gd")
const Temperature = preload("res://scripts/sim/environment_temperature_state.gd")
const Phases = preload("res://scripts/sim/environment_phase_state.gd")
const SIZE: int = SimGroundPlacements.MAP_SIZE
const VERSION: int = 6
const MODEL: String = "composed_fields_v1"
const PULSE_DURATION_MS: int = 60000


static func capture(domain: RefCounted) -> Dictionary:
	if not domain is SimWorldEnvironmentFields or not domain._active or domain._busy or not domain._error.is_empty():
		return {}
	if domain.world == null or domain.world.elapsed_ms != domain.last_ms or domain._temperature._bulk != null or domain._phases._bulk != null:
		return {}
	if domain._temperature._issued_plan.get_ref() != null:
		return {}
	return {
		"version": VERSION, "model": MODEL,
		"settings_digest": _settings_digest(domain._settings),
		"source_digest": domain.world._content.environment_sources.digest(),
		"activation_ms": domain.activation_ms, "last_ms": domain.last_ms,
		"last_sample_ms": domain.last_sample_ms,
		"background": domain._background.snapshot(),
		"temperature": domain._temperature.snapshot(), "phases": domain._phases.snapshot(),
		"transient": domain._transient.duplicate(true), "receipts": domain.receipts.duplicate(true),
		"device_switches": domain.device_switches.duplicate(true), "samples": domain._samples.duplicate(true),
		"motion_samples": domain.capture_motion_samples(),
	}


static func restore_into(domain: RefCounted, data: Variant) -> bool:
	# _configure_components and subsequent writes are confined to an isolated
	# candidate shell. The caller must discard this entire shell on any failure.
	if not domain is SimWorldEnvironmentFields or domain.world == null or domain._active or domain._busy or not domain._error.is_empty():
		return false
	var fields: Array[String] = ["version", "model", "settings_digest", "source_digest", "activation_ms", "last_ms", "last_sample_ms", "background", "temperature", "phases", "transient", "receipts", "device_switches", "samples", "motion_samples"]
	if not _keys(data, fields) or not Shape.count(data.version, VERSION, VERSION) or data.model != MODEL:
		return false
	if not Shape.count(data.activation_ms, 0, int(domain.world.elapsed_ms)) or not Shape.count(data.last_ms, int(domain.world.elapsed_ms), int(domain.world.elapsed_ms)):
		return false
	if not Shape.count(data.last_sample_ms, int(data.activation_ms), int(data.last_ms)):
		return false
	if not data.settings_digest is String or not data.source_digest is String or domain.world._content.environment_sources == null or data.source_digest != domain.world._content.environment_sources.digest():
		return false
	if not data.transient is Dictionary or not data.receipts is Dictionary or not data.device_switches is Dictionary or not data.samples is Dictionary:
		return false
	if not _valid_motion_samples(data.motion_samples, int(data.last_ms)):
		return false
	if not domain._configure_components(int(data.activation_ms)) or data.settings_digest != _settings_digest(domain._settings):
		return false
	if not domain._background.restore(data.background) or not domain._temperature.restore(data.temperature) or not domain._phases.restore(data.phases):
		return false
	if int(domain._background._at_ms) != int(data.last_ms) or not _owner_shapes(domain, data):
		return false
	# Device transforms read the same fixed model and the candidate's originals.
	# Assign only detached, already shape-checked data on this private shell.
	domain.activation_ms = int(data.activation_ms)
	domain.last_ms = int(data.last_ms)
	if not _validate_receipts(domain, data) or not _validate_switches(domain, data) or not _validate_samples(domain, data):
		return false
	var built: Dictionary = domain._sources.build_sources(data.motion_samples)
	if not bool(built.get("ok", false)):
		return false
	for key: String in data.transient:
		var record: Dictionary = data.transient[key]
		var point := Vector2i(int(record.cell[0]), int(record.cell[1]))
		var source: Dictionary = {"cell": point, "radius": 4, "channels": PackedInt32Array([0, 0, 0, 0, 0, 1000, 0])}
		if not domain._sources.add_transient_initial(key, source):
			return false
	# Actual residuals and current sources are independent participants. A phase-
	# only source need not create a temperature row, and a removed source can
	# leave saved residuals after its current coverage has disappeared.
	var chunks: Dictionary[Vector2i, bool] = {}
	for row: Dictionary in data.temperature.cells:
		var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
		chunks[Vector2i(cell.x >> 4, cell.y >> 4)] = true
	for row: Dictionary in data.phases.cells:
		var cell := Vector2i(int(row.cell[0]), int(row.cell[1]))
		chunks[Vector2i(cell.x >> 4, cell.y >> 4)] = true
	for key: Vector2i in domain._sources.affected_chunks():
		chunks[key] = true
	domain._chunks = chunks
	domain._add_room_chunks()
	if not domain._rebuild_base() or not _validate_current_targets(domain, data):
		return false
	domain.activation_ms = int(data.activation_ms)
	domain.last_ms = int(data.last_ms)
	domain.last_sample_ms = int(data.last_sample_ms)
	domain._transient = data.transient.duplicate(true)
	domain.receipts = data.receipts.duplicate(true)
	domain.device_switches = data.device_switches.duplicate(true)
	domain._samples = data.samples.duplicate(true)
	for row: Dictionary in data.motion_samples:
		domain._motion_changes.append({"keys": [row.key], "at_ms": int(row.at_ms),
			"changed_ms": int(row.changed_ms), "cell": Vector2i(int(row.cell[0]), int(row.cell[1]))})
	domain._active = true
	# Derived work and boundary indices never become another saved authority.
	domain._rebuild_participation()
	domain._connect_owners()
	return true


static func _valid_motion_samples(rows: Variant, now: int) -> bool:
	if not rows is Array:
		return false
	var seen: Dictionary = {}
	var previous_due: int = 0
	var previous_key: String = ""
	for row: Variant in rows:
		if not _keys(row, ["key", "at_ms", "changed_ms", "cell", "sampled_cell"]) or not row.key is String or row.key.is_empty() or seen.has(row.key):
			return false
		if not Shape.count(row.changed_ms, maxi(0, now - SimCadence.FIELD_MOTION_MS + 1), now) or not Shape.count(row.at_ms, now + 1, now + SimCadence.FIELD_MOTION_MS):
			return false
		if not Shape.cell_valid(row.cell) or not Shape.cell_valid(row.sampled_cell):
			return false
		if int(row.at_ms) < previous_due or int(row.at_ms) == previous_due and str(row.key) <= previous_key:
			return false
		seen[row.key] = true
		previous_due = int(row.at_ms)
		previous_key = str(row.key)
	return true


static func _owner_shapes(domain: RefCounted, data: Dictionary) -> bool:
	var thermal: Dictionary = data.temperature
	var elemental: Dictionary = data.phases
	if int(thermal.size[0]) != SIZE or int(thermal.size[1]) != SIZE or int(elemental.size[0]) != SIZE or int(elemental.size[1]) != SIZE or thermal.get("capacity") != SIZE * SIZE or elemental.get("capacity") != SIZE * SIZE:
		return false
	if thermal.get("activation_ms") != data.activation_ms or elemental.get("activation_ms") != data.activation_ms:
		return false
	if not thermal.get("cells") is Array or not elemental.get("cells") is Array:
		return false
	for t: Dictionary in thermal.cells:
		var cell := Vector2i(int(t.cell[0]), int(t.cell[1]))
		var tau: int = SimWorldEnvironmentFields.TAU_MS
		if domain._layout.room_of.has(cell):
			tau = int(domain._layout.rooms[domain._layout.room_of[cell]].tau_ms)
		if int(t.response.tau_ms) != tau:
			return false
		if int(t.response.start_ms) > int(data.last_ms) or int(t.response.until_ms) < int(data.last_ms):
			return false
		if not bool(domain._temperature.actual_at(cell, int(data.last_ms)).get("ok", false)):
			return false
	for p: Dictionary in elemental.cells:
		var cell := Vector2i(int(p.cell[0]), int(p.cell[1]))
		if int(p.tau_ms) != SimWorldEnvironmentFields.TAU_MS:
			return false
		if int(p.start_ms) > int(data.last_ms) or int(p.until_ms) < int(data.last_ms):
			return false
		if not bool(domain._phases.actual_at(cell, int(data.last_ms)).get("ok", false)):
			return false
	return true


static func _validate_current_targets(domain: RefCounted, data: Dictionary) -> bool:
	# Each response compiles at its own causal anchor, not the anchor of a
	# different domain which may have changed at another world millisecond.
	var room_targets: Dictionary = {}
	var room_responses: Dictionary = {}
	var room_counts: Dictionary = {}
	for t: Dictionary in data.temperature.cells:
		var point := Vector2i(int(t.cell[0]), int(t.cell[1]))
		var base: Dictionary = domain._field.read_base(point)
		if not bool(base.get("ok", false)) or bool(base.get("pending", true)):
			return false
		var channels: PackedInt32Array = base.channels
		var start: int = int(t.response.start_ms)
		var expected: Dictionary = domain._compiler.compile(point, start, channels[5], channels[6])
		if domain._layout.room_of.has(point):
			var anchor: Vector2i = domain._layout.room_of[point]
			if not room_targets.has(anchor):
				room_targets[anchor] = domain._layout.compile_room(domain, anchor, start)
				room_responses[anchor] = t.response
				room_counts[anchor] = 0
			if t.response != room_responses[anchor]:
				return false
			room_counts[anchor] += 1
			expected = room_targets[anchor]
		if not bool(expected.get("ok", false)):
			return false
		if float(t.response.target_value) != float(expected.target_c) or float(t.response.target_per_ms) != float(expected.target_per_ms) or int(t.response.until_ms) != int(expected.until_ms):
			return false
	for anchor: Vector2i in domain._layout.rooms:
		if int(room_counts.get(anchor, 0)) != domain._layout.rooms[anchor].cells.size():
			return false
	for p: Dictionary in data.phases.cells:
		var point := Vector2i(int(p.cell[0]), int(p.cell[1]))
		var base: Dictionary = domain._field.read_base(point)
		if not bool(base.get("ok", false)) or bool(base.get("pending", true)):
			return false
		var channels: PackedInt32Array = base.channels
		var start: int = int(p.start_ms)
		var expected: Dictionary = domain._compiler.compile(point, start, channels[5], channels[6])
		if not bool(expected.get("ok", false)):
			return false
		var next_grid: int = start + mini(SimWorldEnvironmentFields.TIDE_GRID_MS - posmod(start, SimWorldEnvironmentFields.TIDE_GRID_MS), Response.MAX_TIME - start)
		if int(p.until_ms) != mini(int(expected.until_ms), next_grid):
			return false
		for channel: int in 5:
			if float(p.target[channel]) != float(Rules.effective_grade(channels[channel], int(expected.multiplier))) or float(p.slope[channel]) != 0.0:
				return false
	# Saved anchors can be sparse, but a current, nonzero source cannot be made
	# to disappear by deleting its actual response from an otherwise valid save.
	# The bounds are source-covered chunks only; full validation is a low-frequency
	# restore operation, not a per-frame simulation query.
	for key: Vector2i in domain._sources.affected_chunks():
		var origin: Vector2i = key * 16
		for y: int in range(origin.y, mini(origin.y + 16, SIZE)):
			for x: int in range(origin.x, mini(origin.x + 16, SIZE)):
				var point := Vector2i(x, y)
				var base: Dictionary = domain._field.read_base(point)
				if not bool(base.get("ok", false)) or bool(base.get("pending", true)):
					return false
				var channels: PackedInt32Array = base.channels
				if (channels[5] != 0 or channels[6] != 0) and not bool(domain._temperature.actual_at(point, int(data.last_ms)).get("ok", false)):
					return false
				var has_elements: bool = false
				for channel: int in 5:
					has_elements = has_elements or channels[channel] != 0
				if has_elements and not bool(domain._phases.actual_at(point, int(data.last_ms)).get("ok", false)):
					return false
	return true


static func _validate_receipts(domain: RefCounted, data: Dictionary) -> bool:
	var events: Dictionary = {}
	for event: Dictionary in domain.world.artifacts.events:
		if event.get("kind") == "warmed" and int(event.get("at_ms", -1)) >= int(data.activation_ms):
			var action: String = str(event.get("action", ""))
			if action.is_empty() or events.has(action) or int(event.get("at_ms", -1)) > int(data.last_ms):
				return false
			events[action] = event
	if events.size() != data.receipts.size() or data.transient.size() > SimWorldEnvironmentFields.MAX_TRANSIENT:
		return false
	for action: Variant in data.receipts:
		var receipt: Variant = data.receipts[action]
		if not action is String or not _keys(receipt, ["action", "actor", "object", "at_ms", "cell", "amount"]) or receipt.action != action:
			return false
		if not SimInventory._nonempty(receipt.actor) or not SimInventory._nonempty(receipt.object) or not Shape.count(receipt.at_ms, int(data.activation_ms), int(data.last_ms)) or not Shape.cell_valid(receipt.cell) or receipt.amount != domain.definitions.pulse_energy:
			return false
		var event: Variant = events.get(action)
		if not event is Dictionary or event.get("actor") != receipt.actor or event.get("object") != receipt.object or event.get("at_ms") != receipt.at_ms or not _same_cell(event.get("cell"), receipt.cell) or event.get("heat_amount") != receipt.amount or not domain.world.artifacts.objects.has(receipt.object) or not domain.world.artifacts.has_capability(receipt.object, "heat_storage"):
			return false
		var key: String = "pulse:" + action
		if int(receipt.at_ms) > Response.MAX_TIME - PULSE_DURATION_MS:
			return false
		var until: int = int(receipt.at_ms) + PULSE_DURATION_MS
		if until > int(data.last_ms):
			if not _keys(data.transient.get(key), ["cell", "until_ms"]) or data.transient[key].cell != receipt.cell or data.transient[key].until_ms != until:
				return false
		elif data.transient.has(key):
			return false
	for key: Variant in data.transient:
		if not key is String or not key.begins_with("pulse:") or not data.receipts.has(key.trim_prefix("pulse:")):
			return false
	return true


static func _validate_switches(domain: RefCounted, data: Dictionary) -> bool:
	var seen: Dictionary = {}
	var latest: Dictionary = {}
	var balances: Dictionary = {}
	for event: Dictionary in domain.world.artifacts.events:
		if event.get("kind") not in ["enabled", "disabled"] or int(event.get("at_ms", -1)) < int(data.activation_ms):
			continue
		var action: String = str(event.get("action", ""))
		var change: Variant = data.device_switches.get(action)
		if action.is_empty() or seen.has(action) or not _keys(change, ["action", "actor", "object", "at_ms", "region", "container", "cell", "enabled"]):
			return false
		var enabled: bool = event.kind == "enabled"
		if change.action != action or change.actor != event.get("actor") or change.object != event.get("object") or change.at_ms != event.get("at_ms") or change.region != event.get("effect_region") or change.container != event.get("device_container") or not _same_cell(change.cell, event.get("cell")) or change.enabled != enabled or event.get("verb") != ("enable" if enabled else "disable"):
			return false
		if not SimInventory._nonempty(change.actor) or not SimInventory._nonempty(change.object) or not SimInventory._nonempty(change.region) or not SimInventory._nonempty(change.container) or not change.enabled is bool or not Shape.count(change.at_ms, int(data.activation_ms), int(data.last_ms)) or not Shape.cell_valid(change.cell) or not domain.world.artifacts.objects.has(change.object) or not domain.world.artifacts.has_capability(change.object, "thermal_exchange"):
			return false
		var previous: Dictionary = latest.get(change.object, {})
		if bool(previous.get("enabled", false)) == enabled or not previous.is_empty() and int(previous.at_ms) > int(change.at_ms):
			return false
		if not enabled and (previous.get("region") != change.region or previous.get("container") != change.container or previous.get("cell") != change.cell):
			return false
		var rule: Dictionary = domain.world.artifacts.definitions.types[domain.world.artifacts.objects[change.object].definition].thermal
		var balance: int = int(balances.get(change.object, int(rule.opening_q)))
		if bool(previous.get("enabled", false)):
			balance = _device_balance(balance, rule, int(change.at_ms) - int(previous.at_ms))
		balances[change.object] = balance
		seen[action] = true
		latest[change.object] = change
	if seen.size() != data.device_switches.size():
		return false
	for id: String in domain.world.artifacts.legacy_object_ids():
		if not domain.world.artifacts.has_capability(id, "thermal_exchange"):
			continue
		var item: Dictionary = domain.world.artifacts.objects[id]
		var last: Dictionary = latest.get(id, {})
		var rule: Dictionary = domain.world.artifacts.definitions.types[item.definition].thermal
		var balance: int = int(balances.get(id, int(rule.opening_q)))
		if bool(last.get("enabled", false)):
			balance = _device_balance(balance, rule, int(data.last_ms) - int(last.at_ms))
		if int(item.stored_q) != balance:
			return false
		if bool(item.enabled) != bool(last.get("enabled", false)):
			return false
		if bool(item.enabled):
			if last.get("region") != item.region or last.get("container") != item.container or not domain.world.artifacts.thermal_fixed_location(item):
				return false
			var point: Vector2i = domain.world.artifacts.object_cell(id)
			if not _same_cell(last.get("cell"), [point.x, point.y]):
				return false
	return true


static func _device_balance(balance: int, rule: Dictionary, duration_ms: int) -> int:
	# A finite device spends its own reserve, not heat conserved by the outdoor
	# field. Bound before multiplying so a long saved interval cannot overflow.
	var available: int = balance if rule.mode == "emit" else int(rule.capacity_q) - balance
	var rate: int = int(rule.rate_q_per_ms)
	@warning_ignore("integer_division")
	var until_empty: int = available / rate + (1 if available % rate else 0)
	var spent: int = available if duration_ms >= until_empty else duration_ms * rate
	return balance + (-spent if rule.mode == "emit" else spent)


static func _validate_samples(domain: RefCounted, data: Dictionary) -> bool:
	var at_ms: int = int(data.last_sample_ms)
	if at_ms != int(data.activation_ms) and posmod(at_ms, int(domain.definitions.sample_ms)) != 0:
		return false
	var latest: int = int(data.last_ms) - posmod(int(data.last_ms), int(domain.definitions.sample_ms))
	var expected: int = int(data.activation_ms) if latest - int(data.activation_ms) < int(domain.definitions.sample_ms) else latest
	if at_ms != expected:
		return false
	if data.samples.size() > SIZE * SIZE:
		return false
	for key: Variant in data.samples:
		if not key is String or key.get_slice_count(",") != 2:
			return false
		var x: String = key.get_slice(",", 0)
		var y: String = key.get_slice(",", 1)
		if not x.is_valid_int() or not y.is_valid_int() or x != str(int(x)) or y != str(int(y)) or int(x) < 0 or int(y) < 0 or int(x) >= SIZE or int(y) >= SIZE:
			return false
		if not Shape.count(data.samples[key], -20000, 10000000010000):
			return false
	return true


static func _settings_digest(settings: Dictionary) -> String:
	return Values.canonical_json(Values.normalized(settings)).sha256_text()


static func _same_cell(a: Variant, b: Variant) -> bool:
	return Shape.cell_valid(a) and Shape.cell_valid(b) and int(a[0]) == int(b[0]) and int(a[1]) == int(b[1])


static func _keys(value: Variant, expected: Array) -> bool:
	if not value is Dictionary or value.size() != expected.size():
		return false
	for key: Variant in expected:
		if not value.has(key):
			return false
	return true
