extends RefCounted
## Pure attribution rules. Quantity/location belong to Objects; mandates to Institutions.
const FIELDS: Array[String] = ["owner", "organization", "entrust", "phase"]
const MAX_COUNT: int = 1000000000
const MAX_GROUPS: int = 256

static func right(owner: int = 0, organization: int = 0, entrust: int = 0, phase: String = "") -> Dictionary:
	return {"owner": owner, "organization": organization, "entrust": entrust, "phase": ("free" if entrust == 0 else "issued") if phase.is_empty() else phase}

static func attribution(value: Dictionary) -> Dictionary:
	return right(int(value.get("owner", 0)), int(value.get("organization", 0)), int(value.get("entrust", 0)), str(value.get("phase", "")))

static func key(value: Dictionary) -> String:
	return "%012d:%012d:%012d:%s" % [value.owner, value.organization, value.entrust, value.phase]

static func matches(value: Dictionary, filter: Dictionary) -> bool:
	for field: String in FIELDS:
		if filter.has(field) and value[field] != filter[field]: return false
	return true

static func count(contents: Dictionary, item: String, filter: Dictionary = {}) -> int:
	var result: int = 0
	for batch: Dictionary in contents.get(item, []):
		if matches(batch, filter): result += int(batch.count)
	return result

static func summary(contents: Dictionary, filter: Dictionary = {}) -> Dictionary:
	var result: Dictionary = {}
	for item: String in contents:
		var amount: int = count(contents, item, filter)
		if amount > 0: result[item] = amount
	return result

static func valid_right(value: Variant, next_id: int) -> bool:
	if not value is Dictionary: return false
	for field: String in ["owner", "organization", "entrust"]:
		if not value.get(field) is int or value[field] < 0: return false
	return value.owner < next_id and (value.owner == 0 or value.organization == 0) and ((value.entrust == 0 and value.get("phase") == "free") or (value.entrust > 0 and (value.owner > 0 or value.organization > 0) and value.get("phase") in ["issued", "produced"]))

static func valid(contents: Variant, next_id: int) -> bool:
	if not contents is Dictionary or contents.size() > 256: return false
	for item: Variant in contents:
		if not item is String or not preload("res://scripts/sim/kernel/items.gd").valid(item) or not contents[item] is Array or contents[item].is_empty() or contents[item].size() > MAX_GROUPS: return false
		var previous: String = ""
		var total: int = 0
		for batch: Variant in contents[item]:
			if not valid_right(batch, next_id) or batch.size() != 5 or not batch.get("count") is int or batch.count <= 0 or batch.count > MAX_COUNT: return false
			var current: String = key(batch)
			if current <= previous: return false
			previous = current
			total += batch.count
		if total > MAX_COUNT: return false
	return true

static func access_reason(actor: Dictionary, target: Dictionary, handler: String) -> String:
	if handler not in ["take", "put", "eat", "craft", "collect_source", "rest", "construct", "demolish", "sow", "tend", "gather", "cut", "uproot", "harvest"]: return ""
	for dependency: Dictionary in target.get("access_dependencies", {}).get(handler, []):
		var reason: String = access_reason(actor, dependency, dependency.operation)
		if not reason.is_empty(): return reason
	var owner: int = int(target.get("owner", 0))
	var organization: int = int(target.get("organization", 0))
	# An open private worksite accepts donated labor; modifying/dismantling or
	# consuming somebody's property still needs their own recognized permission.
	if owner > 0 and owner != actor.get("id", 0) and handler != "construct" and handler not in actor.get("task_access", {}).get(int(target.get("id", 0)), []): return "not_authorized"
	if organization > 0:
		var purpose: String = "cultivate" if handler in ["sow", "tend", "gather", "cut", "uproot", "harvest"] else (str(target.get("processing_purpose", "")) if handler == "craft" else ("supply" if handler == "collect_source" else handler))
		if handler == "put" and organization in actor.get("returns", []): return ""
		if purpose not in actor.get("permissions", {}).get(organization, []): return "not_authorized"
	return ""

static func input_group(actor: Dictionary, required: Dictionary, purpose: String, organization: int = 0) -> Dictionary:
	var available: Array = actor.get("bundles", [])
	if not actor.has("bundles"):
		var personal: Dictionary = right(int(actor.get("id", 0)))
		personal["items"] = actor.get("usable_inventory", actor.get("inventory", {}))
		available = [personal]
	for bundle: Dictionary in available:
		if int(bundle.organization) != organization or (organization > 0 and bundle.get("purpose", "") != purpose): continue
		var enough: bool = true
		for item: String in required:
			if int(bundle.items.get(item, 0)) < int(required[item]): enough = false; break
		if enough: return attribution(bundle)
	return {}

static func input_purpose(operation: Dictionary) -> String:
	if not operation.get("recipe", {}).is_empty(): return str(operation.recipe.purpose)
	if operation.handler in ["sow", "tend"]: return "cultivate"
	return "construct" if operation.handler == "construct" else ""

static func known_quantity(actor: Dictionary, target: Dictionary, item: String, handler: String, organization: int = -1) -> int:
	if not target.has("contents"): return int(target.get("inventory", {}).get(item, 0)) if organization < 0 or int(target.get("organization", 0)) == organization else 0
	var result: int = 0
	for group: Dictionary in target.contents.get(item, []):
		if organization >= 0 and int(group.organization) != organization: continue
		if group.owner == int(actor.get("id", 0)) and not group.entrusted: result += int(group.count)
		elif group.owner == 0 and group.organization == 0 and not group.entrusted: result += int(group.count)
		elif group.organization > 0 and not group.entrusted and ("take" if handler == "take" else handler) in actor.get("permissions", {}).get(int(group.organization), []): result += int(group.count)
	return result
