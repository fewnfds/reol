extends RefCounted
## Appointment-bound policy, without a second personal goal or stock balance.
const Defs = preload("res://scripts/sim/kernel/institution_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")

static func scope_valid(world: RefCounted, role: String, scope: Variant, targets: Array, active: bool) -> bool:
	if not scope is Dictionary: return false
	var duty: Dictionary = Defs.ROLES[role].duty
	if duty.is_empty(): return scope.is_empty()
	if scope.size() != 3 or not scope.get("target") is int or not scope.get("channel") is int or not scope.get("sources") is Array or scope.sources.size() > 32: return false
	for id: Variant in [scope.target, scope.channel] + scope.sources:
		if not id is int or id < 1 or id >= world.objects.next_id or (active and id not in targets): return false
	for source: int in scope.sources:
		if scope.sources.count(source) != 1 or source == scope.target: return false
	if not active: return true
	var target: Dictionary = world.objects.records.get(scope.target, {})
	var channel: Dictionary = world.objects.records.get(scope.channel, {})
	if target.is_empty() or target.kind == "blueprint" or channel.is_empty() or channel.kind == "blueprint" or not world.facilities.definitions.get(channel.definition, {}).get("capabilities", {}).has("records"): return false
	if duty.kind == "delivery": return target.kind == "chest" and not scope.sources.is_empty()
	var recipe: Dictionary = Operations.OPERATIONS[duty.operation].recipe
	return not scope.sources.is_empty() and recipe.id in world.facilities.definitions.get(target.definition, {}).get("capabilities", {}).get(recipe.facility_capability, {}).get("recipes", [])

static func views(owner: RefCounted, actor: int) -> Dictionary:
	var result: Dictionary = {}
	for appointment: Dictionary in owner.appointments.values():
		if not appointment.active or appointment.actor != actor or Defs.ROLES[appointment.role].duty.is_empty(): continue
		var value: Dictionary = Defs.ROLES[appointment.role].duty.duplicate(true)
		value.merge(appointment.duty_scope.duplicate(true), true)
		value.merge({"appointment": appointment.id, "organization": appointment.organization, "title": Defs.ROLES[appointment.role].title}, true)
		result[appointment.id] = value
	return result

static func sources_ready(duty: Dictionary, actor: Dictionary, clues: Dictionary) -> bool:
	var required: Dictionary = {str(duty.item): 1} if duty.kind == "delivery" else Operations.OPERATIONS[duty.operation].required_items
	for item: String in required:
		var count: int = 0
		for source: int in duty.sources:
			var place: Dictionary = clues.get(source, {})
			if int(place.get("tile", -1)) >= 0: count += Stock.known_quantity(actor, place, item, "take", int(duty.organization))
		if count < int(required[item]): return false
	return true
