class_name SimWorldSettlement
extends RefCounted
## Assembly adapter. Original domain methods still own effects and their local
## simultaneous-effect/resource arbitration rules. No saved domain data here.

const Kernel = preload("res://scripts/sim/execution/settlement_kernel.gd")
const PHASES: Array[StringName] = [&"previous_interval", &"arrivals", &"environment_event", &"current_processes", &"sampling", &"decisions", &"messages", &"events", &"transport"]
var _owner: WeakRef
var kernel: SimSettlementKernel
var world: RegionalSimulation:
	get: return _owner.get_ref() if _owner != null else null


func initialize(authority: RegionalSimulation) -> bool:
	_owner = weakref(authority)
	kernel = Kernel.new(PHASES)
	# Explicit dependency chains retain the adopted same-millisecond rules.
	# New concepts register their methods and dependencies here, not in the loop.
	var previous: StringName = &""
	for domain: StringName in [&"environment_fields", &"health", &"weather", &"clothing", &"standing_work", &"budgeted_labor"]:
		var id := StringName("previous:" + String(domain))
		var callback: Callable = _environment_fields if domain == &"environment_fields" else _timed.bind(domain, &"settle_at_ms")
		var mode: int = Kernel.CallMode.BUDGETED if domain == &"environment_fields" else Kernel.CallMode.CHECKED
		if not kernel.add_step(id, &"previous_interval", callback, mode, [] if previous == &"" else [previous]):
			return false
		previous = id
	if not kernel.add_step(&"previous:plants", &"previous_interval", authority.plants.settle_budgeted, Kernel.CallMode.BUDGETED, [previous]):
		return false
	if not kernel.add_step(&"plant_actions", &"current_processes", authority.plants.jobs.settle_at_ms):
		return false
	if not kernel.add_step(&"arrivals", &"arrivals", _arrivals):
		return false
	if not kernel.add_step(&"prepare_environment_event", &"environment_event", _prepare_environment_event, Kernel.CallMode.CHECKED):
		return false
	previous = &"plant_actions"
	for domain: StringName in [&"object_lifecycle", &"services", &"artifacts", &"spirit_sources", &"capability_practice", &"method_records", &"sparring", &"conflicts", &"consider_reading", &"consider_methods", &"avian_life", &"soul_vessels", &"admissions", &"construction", &"facility_use", &"personal_production", &"resting", &"large_bodies", &"environment", &"source_care", &"private_exchange", &"field_opportunities"]:
		var mode: int = Kernel.CallMode.YIELDING if domain == &"object_lifecycle" else Kernel.CallMode.CHECKED
		var callback: Callable = _current.bind(domain)
		if domain == &"facility_use":
			mode = Kernel.CallMode.BUDGETED
			callback = _facilities
		if not kernel.add_step(domain, &"current_processes", callback, mode, [] if previous == &"" else [previous]):
			return false
		previous = domain
	if not kernel.add_step(&"herb_conditions", &"sampling", authority._sample_herb_conditions, Kernel.CallMode.CHECKED_UNTIMED):
		return false
	previous = &""
	for id: StringName in [&"health", &"clothing", &"artifacts", &"spirit_sources", &"autonomous_livelihood", &"source_care", &"field_opportunities"]:
		var step := StringName("consider:" + String(id))
		if not kernel.add_step(step, &"decisions", _consider.bind(id), Kernel.CallMode.UNTIMED, [] if previous == &"" else [previous]):
			return false
		previous = step
	if not kernel.add_step(&"messages", &"messages", authority._process_messages, Kernel.CallMode.UNTIMED) or not kernel.add_step(&"routes", &"transport", _routes):
		return false
	if not kernel.add_step(&"world_events", &"events", authority.world_events.settle_budgeted, Kernel.CallMode.BUDGETED):
		return false
	for domain: StringName in RegionalSimulation.BOUNDARY_DOMAINS:
		if not kernel.add_boundary(domain, _boundary.bind(domain), RegionalSimulation.RUNTIME_BOUNDARY_DOMAINS.has(domain)):
			return false
	return kernel.compile()


func _environment_fields(at_ms: int, budget: int) -> Vector2i:
	return world.environment_fields.settle_budgeted(at_ms, budget, kernel.should_yield_work)


func _timed(at_ms: int, domain: StringName, method: StringName) -> bool:
	var owner: Variant = world.get(domain)
	if owner == null:
		return domain in [&"services", &"source_care", &"field_opportunities"]
	var result: Variant = owner.call(method, at_ms)
	return result == true if domain == &"environment_fields" or domain == &"object_lifecycle" else true


func _current(at_ms: int, domain: StringName) -> bool:
	if domain == &"consider_reading":
		world.method_records.consider_reading()
		return true
	if domain == &"consider_methods":
		world.artifacts.consider_methods()
		return true
	var completed: bool = _timed(at_ms, domain, &"settle_at_ms")
	if domain == &"object_lifecycle" and completed:
		world._environment_event = null
	return completed


func _consider(domain: StringName) -> void:
	var owner: Variant = world.get(domain)
	if owner == null:
		return
	if domain == &"clothing":
		owner.consider_weather()
	elif domain == &"artifacts":
		owner.consider_warming()
	else:
		owner.consider()


func _facilities(at_ms: int, budget: int) -> Vector2i:
	return world.facility_use.settle_budgeted(at_ms, budget)


func _arrivals(_at_ms: int) -> void:
	@warning_ignore("integer_division")
	var old_minute: int = kernel.from_ms / RegionalSimulation.MINUTE_MS
	world._advance_journeys(world.current_time - old_minute)
	world._process_arrivals()


func _prepare_environment_event(at_ms: int) -> bool:
	var guard: RefCounted = world._environment_guard.get_ref() if world._environment_guard != null else null
	if guard != null and world.object_lifecycle.next_boundary_ms() <= at_ms:
		if not world.synchronize_regions():
			return false
		world._environment_event = RegionalSimulation.EnvironmentEventContext.new(world, guard, at_ms, true)
	return true


func _routes(_at_ms: int) -> void:
	for route_id: String in world._sorted_keys(world.routes):
		world._try_dispatch(route_id)


func _boundary(domain: StringName) -> int:
	var owner: Variant = world.get(domain)
	return int(owner.next_boundary_ms()) if owner != null else RegionalSimulation.MAX_COUNT
