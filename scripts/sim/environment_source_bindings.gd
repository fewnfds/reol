class_name SimEnvironmentSourceBindings
extends RefCounted
## Read-only projection of an original ground slot into an environment source.
## Memoizes immutable profiles only; the world retains all objects and amounts.

var _owner: WeakRef
var _definitions: EnvironmentSourceDefinitions
var _profiles: Dictionary = {}


func configure(world: RegionalSimulation, definitions: EnvironmentSourceDefinitions) -> bool:
	if _owner != null or world == null or definitions == null or not definitions.is_configured():
		return false
	if world.artifacts == null or world.artifacts.world != world or world.object_lifecycle == null:
		return false
	if world.object_lifecycle.world != world or not world.object_lifecycle.ground.bound_to(world):
		return false
	if not definitions.validate_artifacts(world.artifacts.definitions.types):
		return false
	_definitions = definitions
	_owner = weakref(world)
	return true


func project_ground_slot(world: RegionalSimulation, slot: Dictionary, container: String) -> Dictionary:
	if _owner == null or _owner.get_ref() != world:
		return _failure("world_unavailable")
	var region: Variant = world.regions.get(slot.region)
	if not region is VillageSimulation:
		return _failure("invalid_source")
	if region.elapsed_ms != world.elapsed_ms:
		return _failure("stale_source")
	var reference: Dictionary = slot.reference
	var definition: String
	var kind: String
	var quantity: int = 1
	if reference.kind == "artifact":
		var item: Variant = world.artifacts.objects.get(reference.id)
		if not item is Dictionary or item.get("region") != slot.region or item.get("container") != container:
			return _failure("invalid_source")
		definition = str(item.get("definition", ""))
		if not world.artifacts.definitions.types.has(definition):
			return _failure("invalid_source")
		kind = "artifact"
		if not bool(slot.active):
			return _failure("invalid_location")
	else:
		if reference.kind != "stock" or reference.domain != "village":
			return _failure("unsupported_domain")
		if reference.region != slot.region or reference.container != container or not region.inventory.containers.has(reference.container):
			return _failure("invalid_source")
		definition = reference.item
		kind = "material"
		# Deliberately avoid available()/entrusted(): radiation is a property of
		# the real quantity, independent of reservations and custody bookkeeping.
		quantity = region.inventory.quantity(reference.container, definition)
		if bool(slot.active) != (quantity > 0):
			return _failure("invalid_source")
	var profile: Dictionary = _profile(kind, definition)
	if not bool(profile.ok):
		return profile
	var size := Vector2i(int(slot.size[0]), int(slot.size[1]))
	var cell := Vector2i(int(slot.cell[0]), int(slot.cell[1]))
	var origin := Vector2i((size.x - 1) / 2, (size.y - 1) / 2)
	var emitting: bool = quantity > 0 and (int(profile.thermal_grade) != 0 or profile.elements != [0, 0, 0, 0, 0])
	return {"ok": true, "status": "source" if emitting else "no_source",
		"cell": cell + origin, "size": size, "quantity": quantity,
		"profile_id": profile.profile_id, "elements": profile.elements,
		"thermal_grade": profile.thermal_grade, "radius_cells": profile.radius_cells}


func _profile(kind: String, definition: String) -> Dictionary:
	var key: String = kind + ":" + definition
	if _profiles.has(key):
		return _profiles[key]
	var profile: Dictionary = _definitions.profile(kind, definition)
	# Arbitrary inventory item IDs must not grow an unbounded negative cache.
	if bool(profile.ok):
		_profiles[key] = profile
	return profile


func _failure(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
