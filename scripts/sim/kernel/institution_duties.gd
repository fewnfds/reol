extends RefCounted
## Appointment-bound policy, without a second personal goal or stock balance.
const Defs = preload("res://scripts/sim/kernel/institution_defs.gd")
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Plants = preload("res://scripts/sim/kernel/nature_defs.gd")

static func targets(scope: Dictionary) -> Array:
	var result: Array = []
	var values: Array = scope.sites + scope.sources + [scope.destination] if scope.has("sites") else [scope.target, scope.channel] + scope.sources
	for target: int in values:
		if target not in result: result.append(target)
	return result

static func _references(world: RefCounted, values: Array, appointed: Array, active: bool) -> bool:
	for id: Variant in values:
		if not id is int or id < 1 or id >= world.objects.next_id or (active and id not in appointed): return false
	return true

static func scope_valid(world: RefCounted, role: String, scope: Variant, targets: Array, active: bool) -> bool:
	if not scope is Dictionary: return false
	var duty: Dictionary = Defs.ROLES[role].duty
	if duty.is_empty(): return scope.is_empty()
	if duty.kind == "cultivation":
		if scope.size() != 3 or not scope.get("sites") is Array or not scope.get("sources") is Array or not scope.get("destination") is int: return false
		if scope.sites.size() > 32 or scope.sources.size() > 32 or not _references(world, scope.sites + scope.sources + [scope.destination], targets, active): return false
		for id: int in scope.sites:
			if scope.sites.count(id) != 1 or id in scope.sources or id == scope.destination: return false
		for id: int in scope.sources:
			if scope.sources.count(id) != 1: return false
		if not active: return true
		if scope.sites.is_empty() or scope.sources.is_empty(): return false
		var plant: Dictionary = Plants.DEFINITIONS[Operations.OPERATIONS[duty.operation].plant_definition]
		for id: int in scope.sites:
			var record: Dictionary = world.objects.records.get(id, {})
			var cultivation: Dictionary = world.facilities.definitions.get(record.get("definition", ""), {}).get("capabilities", {}).get("cultivation", {})
			if record.get("kind") == "blueprint" or cultivation.is_empty() or plant.blocks or cultivation.substrate not in plant.substrates: return false
		for id: int in scope.sources:
			var record: Dictionary = world.objects.records.get(id, {})
			var capabilities: Dictionary = world.facilities.definitions.get(record.get("definition", ""), {}).get("capabilities", {})
			if record.get("kind") == "blueprint" or not (capabilities.has("storage") or capabilities.has("stock_source")): return false
		return world.objects.records.get(scope.destination, {}).get("kind") == "chest"
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
	var purpose: String = "supply" if duty.kind == "delivery" else Stock.input_purpose(Operations.OPERATIONS[duty.operation])
	for item: String in required:
		var count: int = 0
		for source: int in duty.sources:
			var place: Dictionary = clues.get(source, {})
			if int(place.get("tile", -1)) >= 0: count += source_quantity(actor, place, item, int(duty.organization), purpose)
		if count < int(required[item]): return false
	return true

static func source_quantity(actor: Dictionary, place: Dictionary, item: String, organization: int, purpose: String = "") -> int:
	var handler: String = "collect_source" if place.get("kind") == "source" else ("gather" if place.get("kind") == "plant" else "take")
	if handler == "gather" and (int(place.get("stage", -1)) != 2 or Plants.DEFINITIONS.get(place.get("definition", ""), {}).get("product", {}).get("item") != item): return 0
	if organization > 0 and not purpose.is_empty() and not Stock.permits_issue(actor, place, organization, purpose, item): return 0
	# A source's uncollected stock is physically unowned. Its facility title
	# decides the output's organization only at the actual collection.
	if handler == "collect_source":
		if int(place.get("organization", 0)) != organization or not Stock.access_reason(actor, place, handler, {"item": item, "purpose": purpose}).is_empty(): return 0
		return int(place.get("inventory", {}).get(item, 0))
	return Stock.known_quantity(actor, place, item, handler, organization)
