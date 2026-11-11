class_name SimEntrustedGoods
extends RefCounted
## Authority/provenance for original inventory encumbrances. No second stock.

const Shape = preload("res://scripts/sim/avian_schema.gd")


static func native_basis(config: Dictionary, purpose: String, origin: String, legacy: bool = false) -> Dictionary:
	var terms: Dictionary = config.actions[purpose]
	var source: String = SimLandResources.container_id(str(terms.resource)) if terms.kind == "gather" else str(terms.get("source", terms.target))
	return {"domain": "native", "purpose": purpose, "origin": origin,
		"institution": config.institution.id, "source_region": "", "source": source,
		"return_region": "", "return_place": terms.target if terms.kind == "gather" else source,
		"target_region": "", "target": terms.target, "legacy": legacy}


static func service_basis(world: RefCounted, job: Dictionary, legacy: bool = false) -> Dictionary:
	if job.kind == "carry_stock":
		var source: Dictionary = job.options.source
		var target: Dictionary = job.options.target
		return {"domain": "service", "purpose": "carry_stock", "origin": job.id,
			"institution": world.regions[source.region].config.institution.id,
			"source_region": source.region, "source": source.container, "return_region": source.region, "return_place": source.container,
			"target_region": target.region, "target": target.container, "legacy": false}
	var route: Dictionary = world.settings.routes[job.route]
	return {"domain": "service", "purpose": "haul_grain", "origin": job.id,
		"institution": world.regions[route.from].config.institution.id,
		"source_region": route.from, "source": route.source,
		"return_region": route.from, "return_place": route.source,
		"target_region": route.to, "target": route.target, "legacy": legacy}


static func find(inventory: SimInventory, actor: String, purpose: String, item: String, amount: int, domain: String = "native") -> String:
	var ids: Array = inventory.custody.keys()
	ids.sort()
	for id: String in ids:
		var note: Dictionary = inventory.custody[id]
		if note.container == "actor:" + actor and note.basis.domain == domain and note.basis.purpose == purpose and note.item == item and int(note.amount) == amount and note.settled_by.is_empty():
			return id
	return ""


static func first_held(inventory: SimInventory, actor: String) -> String:
	var ids: Array = inventory.custody.keys()
	ids.sort()
	for id: String in ids:
		if inventory.custody[id].container == "actor:" + actor and inventory.custody[id].settled_by.is_empty():
			return id
	return ""


static func record_native(sim: RefCounted, actor: String, action: Dictionary, item: String, amount: int, pickup: String) -> bool:
	return sim.inventory.entrust(pickup, "actor:" + actor, item, amount, native_basis(sim.config, str(action.action), str(action.id)))


static func valid_native(data: Dictionary, inventory: SimInventory, allow_services: bool = false) -> bool:
	if not data.inventory.get("custody") is Dictionary:
		return false
	var config: Dictionary = data.config
	var holdings: Dictionary = {}
	for id: String in inventory.custody:
		var note: Dictionary = inventory.custody[id]
		var basis: Dictionary = note.basis
		if not Shape.keys(basis, ["domain", "purpose", "origin", "institution", "source_region", "source", "return_region", "return_place", "target_region", "target", "legacy"]) or not basis.legacy is bool or not basis.domain in ["native", "service"] or not note.container.begins_with("actor:") or not data.actors.has(note.container.trim_prefix("actor:")):
			return false
		if basis.domain == "service":
			if not allow_services:
				return false
			continue # Parent service domain checks its own real pickup/delivery.
		if not config.actions.has(basis.purpose) or not config.actions[basis.purpose].kind in ["haul", "gather", "recipe"] or not Shape.same_record(basis, native_basis(config, basis.purpose, basis.origin, basis.legacy)):
			return false
		var terms: Dictionary = config.actions[basis.purpose]
		var parts: PackedStringArray = str(basis.origin).split(":")
		if parts.size() != 2 or parts[0] != "action" or not parts[1].is_valid_int() or int(parts[1]) < 1 or int(parts[1]) >= int(data.next_id):
			return false
		var amount: int = int(terms.inputs.get(note.item, 0)) if terms.kind == "recipe" else (int(terms.amount) if note.item == terms.item else 0)
		var suffix: String = ":input:" + str(note.item) if terms.kind == "recipe" else (":harvest" if terms.kind == "gather" else ":pickup")
		if int(note.amount) != amount or id != ("legacy:" + str(basis.origin) + ":" + str(note.item) if basis.legacy else str(basis.origin) + suffix):
			return false
		if not basis.legacy:
			var pickup: Dictionary = inventory.operations.get(id, {})
			if pickup.get("kind") != "transfer" or pickup.get("custody_origin") != id or pickup.get("source") != basis.source or pickup.get("target") != note.container or pickup.get("item") != note.item or pickup.get("amount") != note.amount:
				return false
		if note.settled_by.is_empty():
			var key: String = note.container + ":" + str(basis.purpose) + ":" + str(note.item)
			if holdings.has(key):
				return false
			holdings[key] = true
		elif note.settled_by.domain == "inventory":
			var operation: Dictionary = inventory.operations[note.settled_by.operation]
			if terms.kind == "recipe":
				if operation.kind != "consume" or not str(note.settled_by.operation).ends_with(":recipe:" + str(note.item)):
					return false
			elif operation.kind != "transfer" or operation.target != basis.target or not str(note.settled_by.operation).ends_with(":delivery"):
				return false
	return true


static func return_spec(service: RefCounted, actor: String, home: String, options: Dictionary) -> Dictionary:
	if not Shape.keys(options, ["custody"]) or not options.custody is String:
		return {}
	var inventory: SimInventory = service.world.regions[home].inventory
	if not inventory.custody.has(options.custody):
		return {}
	var note: Dictionary = inventory.custody[options.custody]
	if note.container != "actor:" + actor:
		return {}
	return {"label": service.definitions.returns.label, "place": note.basis.return_place, "minutes": service.definitions.returns.minutes}


static func valid_services(data: Dictionary, service: RefCounted) -> bool:
	var world: RefCounted = service.world
	for home: String in world.regions:
		var inventory: SimInventory = world.regions[home].inventory
		for id: String in inventory.custody:
			var note: Dictionary = inventory.custody[id]
			var basis: Dictionary = note.basis
			var actor: String = str(note.container).trim_prefix("actor:")
			if basis.domain == "service":
				var origin: Dictionary = data.jobs.get(basis.origin, {})
				if basis.purpose == "carry_stock":
					if origin.get("kind") != "carry_stock" or origin.get("home") != home or origin.get("actor") != actor or origin.options.get("custody") != id or id != str(origin.id) + ":pickup" or basis.legacy or not Shape.same_record(basis, service_basis(world, origin)) or note.item != origin.options.item or note.amount != origin.options.amount or not service.Schema._transfer_matches(data.operations.get(id), basis.source_region, basis.source, home, note.container, note.item, int(note.amount)):
						return false
				elif origin.get("kind") != "haul_grain" or origin.get("home") != home or origin.get("actor") != actor or origin.get("options", {}).get("custody") != id or not bool(origin.get("custody_required", false)) or not Shape.same_record(basis, service_basis(world, origin, basis.legacy)) or int(note.amount) != int(origin.amount):
					return false
				else:
					var route: Dictionary = world.settings.routes[origin.route]
					if note.item != route.item or id != ("legacy:" + str(origin.id) if basis.legacy else str(origin.id) + ":pickup"):
						return false
					if not basis.legacy and not service.Schema._transfer_matches(data.operations.get(id), str(route.from), str(route.source), home, str(note.container), str(route.item), int(note.amount)):
						return false
				if not note.settled_by.is_empty() and note.settled_by.domain != "service":
					return false
			if note.settled_by.is_empty() or note.settled_by.domain != "service":
				continue
			var op: String = str(note.settled_by.operation)
			var closer: Dictionary = data.jobs.get(op.trim_suffix(":return").trim_suffix(":delivery"), {})
			if closer.get("status") != "completed" or closer.get("home") != home or closer.get("actor") != actor or closer.get("options", {}).get("custody") != id:
				return false
			var region: String = ""
			var place: String = ""
			if closer.kind == "return_goods" and op == str(closer.id) + ":return":
				region = return_region(home, note)
				place = str(basis.return_place)
			elif closer.kind in ["haul_grain", "carry_stock"] and basis.domain == "service" and op == str(closer.id) + ":delivery":
				region = str(basis.target_region)
				place = str(basis.target)
			else:
				return false
			if not service.Schema._transfer_matches(data.operations.get(op), home, str(note.container), region, place, str(note.item), int(note.amount)):
				return false
	for job: Dictionary in data.jobs.values():
		if job.kind != "haul_grain" or not bool(job.get("custody_required", false)):
			continue
		var inventory: SimInventory = world.regions[job.home].inventory
		if (bool(job.carrying) or data.operations.has(str(job.id) + ":pickup")) and not inventory.custody.has(job.options.get("custody")):
			return false
	return true


static func return_region(home: String, note: Dictionary) -> String:
	return home if note.basis.domain == "native" else str(note.basis.return_region)
