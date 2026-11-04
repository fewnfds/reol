class_name LegacyHeatV2
extends RefCounted
## Read-only v2 input. The current fixed-reference kernel proves its frozen
## segment and projections; this adapter owns no advancing legacy solver.

const Shape = preload("res://scripts/sim/avian_schema.gd")
const RULE_KEYS: Array[String] = ["version", "step_ms", "sample_ms", "world_size", "capacity_per_tenth", "pulse_energy", "coefficient_scale", "conductance", "bath_loss", "source_radius", "max_cells", "max_cell_energy", "max_total_input", "reference_tenths", "max_exchange_energy"]

var _definitions: Dictionary = {}
var _state: Dictionary = {}
var _kernel: SimLocalHeat

var definitions: Dictionary:
	get:
		return _definitions.duplicate(true)
var cells: Dictionary:
	get:
		return _state.get("cells", {}).duplicate(true)
var last_sample_cells: Dictionary:
	get:
		return _state.get("last_sample_cells", {}).duplicate(true)
var legacy_limits: Dictionary:
	get:
		return _state.get("legacy_limits", {}).duplicate(true)
var activation_ms: int:
	get:
		return int(_state.get("activation_ms", 0))
var model_started_ms: int:
	get:
		return int(_state.get("model_started_ms", 0))
var last_sample_ms: int:
	get:
		return int(_state.get("last_sample_ms", 0))
var input_energy: int:
	get:
		return int(_state.get("input_energy", 0))


static func current_definitions(rules: Variant) -> Dictionary:
	if not Shape.keys(rules, RULE_KEYS) or rules.version != 2:
		return {}
	var current: Dictionary = rules.duplicate(true)
	current.version = SimLocalHeat.VERSION
	return current if SimLocalHeat.valid_definitions(current) else {}


static func valid_definitions(rules: Variant) -> bool:
	return not current_definitions(rules).is_empty()


func configure(authority: RefCounted, rules: Dictionary) -> bool:
	var current: Dictionary = current_definitions(rules)
	if authority == null or current.is_empty():
		return false
	var kernel := SimLocalHeat.new()
	if not kernel.initialize(authority, current):
		return false
	_definitions = rules.duplicate(true)
	_state.clear()
	_kernel = kernel
	return true


func bind_world(authority: RefCounted) -> void:
	if _kernel != null:
		_kernel.bind_world(authority)


func set_geometry(roofed: Callable, barrier: Callable) -> void:
	_state.clear()
	if _kernel != null:
		_kernel.set_geometry(roofed, barrier)


func restore(data: Variant) -> bool:
	if _kernel == null:
		return false
	# upgrade_v2 accepts only the exact old shape, rejects device evidence and
	# validates the original anchor through the same current flux mathematics.
	var current: Dictionary = SimThermalSchema.upgrade_v2(_kernel, data)
	if current.is_empty() or not _kernel.restore(current):
		return false
	_state = data.duplicate(true)
	return true


func to_dict() -> Dictionary:
	return _state.duplicate(true)


func current_state() -> Dictionary:
	return {} if _state.is_empty() else _kernel.to_dict()


func current_tenths(cell: Vector2i) -> int:
	return 0 if _state.is_empty() else _kernel.current_tenths(cell)


func sample_tenths(cell: Vector2i, at_ms: int) -> int:
	return 0 if _state.is_empty() else _kernel.sample_tenths(cell, at_ms)


func project_tenths(cell: Vector2i, at_ms: int) -> Dictionary:
	return {"supported": false, "reason": "uninitialized"} if _state.is_empty() else _kernel.project_tenths(cell, at_ms)


func minimum_offset_tenths() -> int:
	return 0 if _kernel == null else _kernel.minimum_offset_tenths()


func maximum_offset_tenths() -> int:
	return 0 if _kernel == null else _kernel.maximum_offset_tenths()


func has_visible_offsets(historical: bool = false) -> bool:
	return not _state.is_empty() and _kernel.has_visible_offsets(historical)
