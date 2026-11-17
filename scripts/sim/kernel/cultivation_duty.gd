extends RefCounted
## Stateless field methods over a person's own knowledge. No work queue or
## simulated stock here: Planner resolves one step into the ordinary host.
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Plants = preload("res://scripts/sim/kernel/nature_defs.gd")
const Stock = preload("res://scripts/sim/kernel/stock_rules.gd")
const Duties = preload("res://scripts/sim/kernel/institution_duties.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")

static func _alive(place: Dictionary) -> bool:
	return int(place.get("tile", -1)) >= 0

static func _cares(crop: Dictionary, policy: Dictionary) -> bool:
	var band: int = int(crop.get("water_band", -1))
	return int(crop.get("stage", -1)) in [1, 2, 3] and band != 4 and (crop.get("injured", false) or (band >= 0 and band <= int(policy.tend_band)))

static func _free(place: Dictionary) -> int:
	if not place.has("inventory") or not _alive(place): return 0
	return maxi(0, int(place.get("capacity", 0)) - int(place.inventory.values().reduce(func(a: int, b: int): return a + b, 0)))

static func _field_origin(policy: Dictionary, clues: Dictionary, origin: int) -> bool:
	var crop: Dictionary = clues.get(origin, {})
	return crop.get("kind") == "plant" and int(crop.get("host", 0)) in policy.sites and int(crop.get("organization", 0)) == int(policy.organization) and int(crop.get("owner", 0)) == 0

static func _public_crop(crop: Dictionary, policy: Dictionary) -> bool:
	return int(crop.get("owner", 0)) == 0 and int(crop.get("organization", 0)) == int(policy.organization)

static func retained(policy: Dictionary, actor: Dictionary, clues: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var planting: bool = false
	var watering: bool = false
	for id: int in policy.sites:
		var site: Dictionary = clues.get(id, {})
		if not _alive(site): continue
		if not site.has("occupant") or int(site.occupant) == 0: planting = true
		var crop: Dictionary = clues.get(int(site.get("occupant", 0)), {})
		if int(site.get("occupant", 0)) > 0 and (not _alive(crop) or not crop.has("stage")): planting = true; watering = true
		if _alive(crop) and _public_crop(crop, policy) and _cares(crop, policy): watering = true
	var seed: String = str(Plants.DEFINITIONS[Operations.OPERATIONS[policy.operation].plant_definition].product.item)
	if planting: result["%d:cultivate:%s" % [policy.organization, seed]] = true
	if watering: result["%d:cultivate:water" % policy.organization] = true
	var destination: Dictionary = clues.get(int(policy.destination), {})
	if _free(destination) > 0:
		for bundle: Dictionary in actor.get("bundles", []):
			if bundle.purpose != "supply" or int(bundle.organization) != int(policy.organization) or not _field_origin(policy, clues, int(bundle.get("origin", 0))): continue
			for item: String in bundle.items: result["%d:supply:%s:%d" % [policy.organization, item, bundle.origin]] = true
	return result

static func _option(p: RefCounted, id: String, place: Dictionary, context: Dictionary = {}) -> Dictionary:
	var step: Dictionary = p._resolve(Operations.OPERATIONS[id], place, [], true, context)
	return p._option(step, id, int(place.id))

static func next(p: RefCounted, policy: Dictionary) -> Array:
	p.source_scope = policy.sources.duplicate()
	p.sources_restricted = true
	var destination: Dictionary = p.known.get(int(policy.destination), {})
	var free: int = 0 if p._denied("put", int(policy.destination)) else _free(destination)
	# Harvested public output keeps supply attribution until actual deposit.
	for bundle: Dictionary in p.actor.bundles:
		if int(bundle.organization) != int(policy.organization) or bundle.purpose != "supply" or not _field_origin(policy, p.known, int(bundle.get("origin", 0))): continue
		if not destination.has("inventory") and _alive(destination):
			var inspection: Dictionary = p._inspect(destination)
			if not inspection.is_empty(): return [p._option(inspection, "", int(destination.id))]
		if free <= 0: break
		for item: String in bundle.items:
			var step: Dictionary = p._deposit(item, mini(int(bundle.items[item]), free), int(policy.organization), int(policy.destination), [], "supply", [int(bundle.origin)])
			if not step.is_empty(): return [p._option(step, "put", int(policy.destination))]
	# Preselect by observed state before spending recursive planning work. One
	# blocked bed must not exhaust the whole method's allowance every review.
	var jobs: Array = []
	var inspections: Array = []
	for id: int in policy.sites:
		var site: Dictionary = p.known.get(id, {})
		if not _alive(site): continue
		if not site.has("occupant"):
			inspections.append(site); continue
		var crop: Dictionary = p.known.get(int(site.occupant), {})
		if int(site.occupant) > 0 and (not _alive(crop) or not crop.has("stage")):
			inspections.append(site); continue
		if not crop.is_empty() and not _public_crop(crop, policy): continue
		if int(site.occupant) == 0:
			jobs.append({"priority": 3, "operation": policy.operation, "place": site, "context": {}})
		elif int(crop.stage) == 4:
			jobs.append({"priority": 0, "operation": "uproot", "place": crop, "context": {}})
		elif _cares(crop, policy):
			jobs.append({"priority": 0 if int(crop.water_band) == 0 or crop.injured else 1, "operation": "tend", "place": crop, "context": {}})
		elif int(crop.stage) == 0:
			jobs.append({"priority": 3, "operation": "sow", "place": crop, "context": {}})
		if int(crop.get("stage", -1)) == 2:
			var item: String = str(Plants.DEFINITIONS[crop.definition].product.item)
			var amount: int = mini(free, Stock.known_quantity(p.actor, crop, item, "gather", int(policy.organization)))
			if amount > 0: jobs.append({"priority": 2, "operation": "gather", "place": crop, "context": {"item": item, "amount": amount, "purpose": "supply"}})
	jobs.sort_custom(func(a: Dictionary, b: Dictionary):
		if a.priority != b.priority: return a.priority < b.priority
		var left: float = p._distance(a.place); var right: float = p._distance(b.place)
		return left < right if not is_equal_approx(left, right) else int(a.place.id) < int(b.place.id))
	var missing_inputs: Dictionary = {}
	for job: Dictionary in jobs:
		if p._denied(job.operation, int(job.place.id)): continue
		if missing_inputs.has(job.operation): continue
		var operation: Dictionary = Operations.OPERATIONS[job.operation]
		if not operation.required_items.is_empty() and p.Institutions.source_shortfall(p, operation.required_items, int(policy.organization), Stock.input_purpose(operation), policy.sources):
			missing_inputs[job.operation] = true
			continue
		var query: Dictionary = Query.evaluate(operation, p.actor, job.place, job.context)
		var option: Dictionary = _option(p, job.operation, job.place, job.context)
		if not option.is_empty(): return [option]
		if int(p.budget.work) >= p.slice_limit: return []
		# A target-specific refusal is not a shared prerequisite failure. But
		# the same missing input cannot be sourced differently at the next bed.
		if query.reason == "missing_items": missing_inputs[job.operation] = true
	# No actual work is currently known. Revisit the oldest record rather than
	# demanding that an entire geographically spread circuit be fresh at once.
	for id: int in policy.sources + [int(policy.destination)] + policy.sites:
		var place: Dictionary = p.known.get(id, {})
		if not _alive(place): continue
		var observed: Dictionary = p.actor.observations.get(id, {})
		var missing_detail: bool = not place.has("occupant") if id in policy.sites else not place.has("inventory")
		if missing_detail or not observed.get("direct", false) or p.at_ms - int(observed.get("at_ms", -int(policy.review_ms))) >= int(policy.review_ms):
			if place not in inspections: inspections.append(place)
	inspections.sort_custom(func(a: Dictionary, b: Dictionary): return int(p.actor.observations.get(int(a.id), {}).get("at_ms", -1)) < int(p.actor.observations.get(int(b.id), {}).get("at_ms", -1)))
	for place: Dictionary in inspections:
		if p._denied("inspect", int(place.id)): continue
		if not p._spend(): return []
		var step: Dictionary = p._inspect(place)
		if not step.is_empty(): return [p._option(step, "", int(place.id))]
	return []

static func needs_review(actor: Dictionary, policy: Dictionary, at: int, clues: Dictionary = {}) -> bool:
	for id: int in policy.sites + policy.sources + [int(policy.destination)]:
		var observed: Dictionary = actor.get("observations", {}).get(id, {})
		if not observed.get("direct", false) or at >= int(observed.get("at_ms", 0)) + int(policy.review_ms): return true
	# Fresh observations can already establish work; freshness alone must not
	# make a person's current responsibility disappear during social consent.
	var destination: Dictionary = clues.get(int(policy.destination), {})
	if _free(destination) > 0:
		for bundle: Dictionary in actor.get("bundles", []):
			if bundle.purpose == "supply" and int(bundle.organization) == int(policy.organization) and _field_origin(policy, clues, int(bundle.get("origin", 0))): return true
	var inputs: Dictionary = {}
	for operation: String in [str(policy.operation), "tend"]:
		inputs[operation] = _inputs_available(actor, policy, clues, Operations.OPERATIONS[operation].required_items)
	for id: int in policy.sites:
		var site: Dictionary = clues.get(id, {})
		if not _alive(site): continue
		if site.get("occupant", -1) == 0 and inputs[policy.operation]: return true
		var crop: Dictionary = clues.get(int(site.get("occupant", 0)), {})
		if not _alive(crop) or not _public_crop(crop, policy): continue
		if (_cares(crop, policy) and inputs.tend) or int(crop.get("stage", -1)) in [0, 4]: return true
		if int(crop.get("stage", -1)) == 2 and _free(clues.get(int(policy.destination), {})) > 0:
			var item: String = str(Plants.DEFINITIONS[crop.definition].product.item)
			if Stock.known_quantity(actor, crop, item, "gather", int(policy.organization)) > 0: return true
	return false

static func _inputs_available(actor: Dictionary, policy: Dictionary, clues: Dictionary, required: Dictionary) -> bool:
	for item: String in required:
		var count: int = 0
		for bundle: Dictionary in actor.get("bundles", []):
			if int(bundle.organization) == int(policy.organization) and bundle.purpose == "cultivate": count += int(bundle.items.get(item, 0))
		for source: int in policy.sources:
			var place: Dictionary = clues.get(source, {})
			if not _alive(place): continue
			if not place.has("inventory"): return true # A real inspection is still work.
			count += Duties.source_quantity(actor, place, item, int(policy.organization), "cultivate")
		if count < int(required[item]): return false
	return true
