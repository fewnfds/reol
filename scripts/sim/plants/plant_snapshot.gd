extends RefCounted
## Candidate-only plant validation. Rebuild indexes only after original records
## and the complete world's cross-owner references have passed.
const Shape = preload("res://scripts/sim/avian_schema.gd")
const BODY_KEYS: Array[String] = ["initial_age_ms", "claimed_cells", "definition", "region", "location", "born_ms", "age_ms", "growth_ms", "fruit_ms", "last_ms", "next_ms", "hp", "injury_carry", "water", "water_carry", "stage", "dormant", "generation", "body_taken", "produced", "subject", "awakened_ms", "awakening_operation", "contacts", "legacy_source", "conditions"]


static func restore(owner: SimPlants, data: Dictionary) -> bool:
	if not Shape.keys(data, ["version", "elapsed_ms", "bodies", "damage_receipts", "jobs"]) or data.version != SimPlants.VERSION or data.elapsed_ms != owner.world.elapsed_ms or not data.bodies is Dictionary or not data.damage_receipts is Dictionary or not Shape.keys(data.jobs, ["active", "receipts", "next_id"]) or not data.jobs.active is Dictionary or not data.jobs.receipts is Dictionary or not Shape.count(data.jobs.next_id, 1):
		return false
	for id: Variant in data.bodies:
		if not SimInventory._nonempty(id) or not _body(owner, data.bodies[id]):
			return false
	for operation: Variant in data.damage_receipts:
		var receipt: Variant = data.damage_receipts[operation]
		if not SimInventory._nonempty(operation) or not Shape.keys(receipt, ["plant", "amount"]) or not data.bodies.has(receipt.plant) or not Shape.count(receipt.amount, 1):
			return false
	owner.damage_receipts = SnapshotValues.normalized(data.damage_receipts)
	owner.elapsed_ms = int(data.elapsed_ms)
	owner.bodies = SnapshotValues.normalized(data.bodies)
	owner.jobs.active = SnapshotValues.normalized(data.jobs.active)
	owner.jobs.receipts = SnapshotValues.normalized(data.jobs.receipts)
	owner.jobs.next_id = int(data.jobs.next_id)
	return true


static func _body(owner: SimPlants, row: Variant) -> bool:
	if not Shape.keys(row, BODY_KEYS) or not row.definition is String or not owner.definitions.types.has(row.definition) or not row.region is String or not owner.world.regions.has(row.region) or not Shape.keys(row.location, ["cell", "support"]) or not row.location.support is String:
		return false
	if row.location.support.is_empty() and not Shape.cell_valid(row.location.cell) or not row.location.support.is_empty() and row.location.cell != []:
		return false
	if not row.claimed_cells is Array or row.claimed_cells.is_empty():
		return false
	for cell: Variant in row.claimed_cells:
		if not Shape.cell_valid(cell):
			return false
	var rule: Dictionary = owner.definitions.types[row.definition]
	for field: String in ["initial_age_ms", "born_ms", "age_ms", "last_ms", "growth_ms", "fruit_ms", "next_ms", "hp", "injury_carry", "water", "generation"]:
		if not Shape.count(row[field]):
			return false
	if not Shape.count(row.water_carry, 0, 99) or row.last_ms > owner.world.elapsed_ms or row.born_ms > row.last_ms or row.age_ms != row.initial_age_ms + row.last_ms - row.born_ms or row.growth_ms > rule.fruit_ms or row.fruit_ms >= rule.product.period_ms or row.hp > rule.max_hp or row.water > 100 * SimPlantRules.WATER_UNIT or row.injury_carry >= rule.injury_ms:
		return false
	if row.stage not in ["growing", "mature", "flowering", "fruiting", "root", "dead", "removed"] or not row.dormant is bool or not row.body_taken is bool or not row.produced is Dictionary or not row.subject is String or not Shape.count(row.awakened_ms, -1, owner.world.elapsed_ms) or not row.contacts is Dictionary or not row.legacy_source is String:
		return false
	if row.stage == "dead" and row.hp != 0 or row.stage not in ["dead", "removed"] and (row.hp == 0 or row.next_ms <= owner.world.elapsed_ms) or row.stage in ["dead", "removed"] and row.next_ms != SimInventory.MAX_COUNT:
		return false
	if row.stage not in ["dead", "removed"] and rule.life == "annual" and row.next_ms > row.born_ms + rule.lifespan_ms - row.initial_age_ms:
		return false
	if not row.awakening_operation is String or row.subject.is_empty() != row.awakening_operation.is_empty() or row.subject.is_empty() != (int(row.awakened_ms) == -1) or not row.subject.is_empty() and row.awakened_ms < row.born_ms:
		return false
	if not Shape.keys(row.conditions, ["substrate", "moisture", "temperature", "rain", "season", "light"]) or not row.conditions.substrate is String or not row.conditions.season is String or not row.conditions.rain is bool or not Shape.count(row.conditions.moisture, 0, 100) or not Shape.count(row.conditions.temperature, -20000, int(SimEnvironmentTemperatureState.MAX_C * 10.0)) or not Shape.count(row.conditions.light, 0, SimLocalLight.MAX_RELATIVE + 10000):
		return false
	for item: Variant in row.produced:
		if item not in [rule.product.item, rule.body_product.item] or not Shape.count(row.produced[item]):
			return false
	for actor: Variant in row.contacts:
		if not actor is String or not owner.world.regions[row.region].actors.has(actor) or not Shape.keys(row.contacts[actor], ["at_ms", "consent"]) or not Shape.count(row.contacts[actor].at_ms, maxi(0, int(row.awakened_ms)), owner.world.elapsed_ms) or not row.contacts[actor].consent is bool or row.subject.is_empty():
			return false
	return true


static func cross_valid(owner: SimPlants) -> bool:
	var cells: Dictionary = {}
	var supports: Dictionary = {}
	for id: String in owner.bodies:
		var row: Dictionary = owner.bodies[id]
		var rule: Dictionary = owner.definitions.types[row.definition]
		var support: String = str(row.location.support)
		if not support.is_empty():
			if row.region != owner.world.construction.definitions.site.region or not owner.world.construction.has_capability(support, "cultivation") or not owner.world.construction.cultivation.has(support) or owner.world.construction.cultivation[support].plant != id or supports.has(support) or row.water != 0:
				return false
			supports[support] = id
		var cell: Vector2i = owner.cell_of(id)
		if owner.world.map_data != null and not owner.world.map_data.in_bounds(cell):
			return false
		if row.stage != "removed":
			var solid: bool = bool(rule.blocks)
			if cells.has(cell) and (solid or bool(cells[cell])):
				return false
			cells[cell] = solid
		var sim: VillageSimulation = owner.world.regions[row.region]
		var container: String = owner.container_id(id)
		if not sim.inventory.containers.has(container):
			return false
		if not str(row.legacy_source).is_empty():
			if not sim.land_resources.sources.has(row.legacy_source) or sim.land_resources.sources[row.legacy_source].plant_id != id or rule.product.item != sim.land_resources.terms_for(row.legacy_source).item:
				return false
		else:
			var totals: Dictionary = {}
			for operation: Dictionary in sim.inventory.operations.values():
				if operation.get("source") == container:
					if operation.kind != "transfer" or not str(operation.target).begins_with("actor:"):
						return false
					totals[operation.item] = int(totals.get(operation.item, 0)) + int(operation.amount)
			for item: String in row.produced:
				if sim.inventory.quantity(container, item) + int(totals.get(item, 0)) != int(row.produced[item]):
					return false
			for item: String in sim.inventory.containers[container]:
				if not row.produced.has(item):
					return false
		if not row.subject.is_empty():
			var event: Dictionary = owner.world.world_events.receipt(row.awakening_operation)
			if event.is_empty() or event.status != "completed" or event.request.rule != "plant_awakening" or event.request.payload != {"plant": id} or event.count != 1 or event.last_ms != row.awakened_ms:
				return false
			var carrier: String = owner.world.embodiment.carrier_for_source("plant", id)
			if not bool(rule.sapient) or row.subject != "subject:plant:" + id or carrier != "body:plant:" + id or owner.world.embodiment.residence_of(row.subject) != carrier or not owner.world.embodiment.controls(row.subject, carrier, "communication"):
				return false
	for sim: VillageSimulation in owner.world.regions.values():
		for source: String in sim.land_resources.sources:
			var id: String = str(sim.land_resources.sources[source].plant_id)
			if not id.is_empty() and (not owner.bodies.has(id) or owner.bodies[id].legacy_source != source or owner.world.regions[owner.bodies[id].region] != sim):
				return false
	for support: String in owner.world.construction.cultivation:
		var id: String = str(owner.world.construction.cultivation[support].plant)
		if not id.is_empty() and supports.get(support, "") != id:
			return false
	if not _jobs(owner):
		return false
	owner._rebuild()
	return true


static func _jobs(owner: SimPlants) -> bool:
	var targets: Dictionary = {}
	var operations: Dictionary = {}
	for actor: Variant in owner.jobs.active:
		var job: Variant = owner.jobs.active[actor]
		if not actor is String or not Shape.keys(job, ["id", "request", "actor", "plant", "kind", "region", "destination", "target_location", "stand", "started_ms", "work_started_ms", "due_ms", "phase", "path", "segment_from", "segment_started_ms", "previous_autonomous"]) or job.actor != actor or not SimInventory._nonempty(job.id) or not owner.bodies.has(job.plant) or targets.has(job.plant) or owner.jobs.receipts.has(job.id):
			return false
		if operations.has(job.id):
			return false
		operations[job.id] = true
		if job.region != owner.bodies[job.plant].region or not owner.world.regions[job.region].actors.has(actor) or job.kind not in owner.jobs.VERBS or not job.destination is Dictionary or job.target_location != owner.bodies[job.plant].location or not Shape.cell_valid(job.stand) or not job.previous_autonomous is bool or job.phase not in ["travel", "work"] or not Shape.count(job.started_ms, 0, owner.elapsed_ms) or not Shape.count(job.due_ms, owner.elapsed_ms + 1) or not Shape.count(job.work_started_ms, 0, owner.elapsed_ms) or not job.path is Array:
			return false
		var sim: VillageSimulation = owner.world.regions[job.region]
		if not sim.actors[actor].active.is_empty() or bool(sim.actors[actor].autonomous) or not SimActionContract.can_continue(owner.world, job.region, actor, &"plants"):
			return false
		if job.request != {"actor": actor, "plant": job.plant, "kind": job.kind, "destination": job.destination} or not owner.jobs._eligible(actor, job.plant, job.kind, job.destination):
			return false
		if job.phase == "travel":
			for cell: Variant in job.path:
				if not Shape.cell_valid(cell):
					return false
			if not SimRouteTravel.valid_segment(job, sim.actors[actor], owner.elapsed_ms, float(sim.motion_rules.motion.speed)):
				return false
		elif not job.path.is_empty() or job.due_ms != job.work_started_ms + owner.definitions.action_ms or not SimRouteTravel.point(sim.actors[actor]).is_equal_approx(TileGrid.cell_to_world(SimRouteTravel.cell(job.stand))):
			return false
		if job.kind in ["harvest", "water"]:
			var source: String = owner.container_id(job.plant) if job.kind == "harvest" else "actor:" + actor
			var item: String = owner.definitions.types[owner.bodies[job.plant].definition].product.item if job.kind == "harvest" else "water"
			if not Shape.same_record(sim.inventory.reservations.get(job.id), {"container": source, "item": item, "amount": 1, "owner_id": actor}):
				return false
		targets[job.plant] = true
	for id: Variant in owner.jobs.receipts:
		var receipt: Variant = owner.jobs.receipts[id]
		if not SimInventory._nonempty(id) or not Shape.keys(receipt, ["request", "result", "at_ms", "operations"]) or not Shape.keys(receipt.request, ["actor", "plant", "kind", "destination"]) or not owner.bodies.has(receipt.request.plant) or receipt.request.kind not in owner.jobs.VERBS or not receipt.request.destination is Dictionary or not receipt.operations is Dictionary or not Shape.count(receipt.at_ms, 0, owner.elapsed_ms) or not Shape.keys(receipt.result, ["ok", "id", "status", "reason"]) or not receipt.result.ok is bool or receipt.result.id != id or receipt.result.status not in ["completed", "cancelled", "failed"] or receipt.result.ok != (receipt.result.status == "completed") or not receipt.result.reason is String:
			return false
		var row: Dictionary = owner.bodies[receipt.request.plant]
		var sim: VillageSimulation = owner.world.regions[row.region]
		if not sim.actors.has(receipt.request.actor) or receipt.result.status != "completed" and not receipt.operations.is_empty():
			return false
		for operation: String in receipt.operations:
			if not sim.inventory.operations.has(operation) or not Shape.same_record(sim.inventory.operations[operation], receipt.operations[operation]):
				return false
		if receipt.result.status == "completed" and receipt.request.kind in ["harvest", "water"]:
			var operation: String = str(id) + (":harvest" if receipt.request.kind == "harvest" else ":water")
			if not receipt.operations.has(operation):
				return false
	return true


static func inventory_scope(data: Variant, region: String, _content: RefCounted) -> Dictionary:
	var result: Dictionary = {"containers": {}, "reservations": {}, "operations": {}}
	if not data is Dictionary or not data.get("bodies") is Dictionary or not data.get("jobs") is Dictionary:
		return result
	for id: Variant in data.bodies:
		var row: Variant = data.bodies[id]
		if id is String and row is Dictionary and row.get("region") == region and row.get("legacy_source") == "":
			result.containers["plant:" + id] = true
	for job: Variant in data.jobs.get("active", {}).values():
		if job is Dictionary and job.get("region") == region and job.get("kind") in ["harvest", "water"] and job.get("id") is String:
			result.reservations[job.id] = true
	for id: Variant in data.jobs.get("receipts", {}):
		var receipt: Variant = data.jobs.receipts[id]
		if id is String and receipt is Dictionary and receipt.get("request") is Dictionary and data.bodies.get(receipt.request.get("plant"), {}).get("region") == region:
			result.operations[id + ":harvest"] = true
			result.operations[id + ":water"] = true
			var definition: String = str(data.bodies[receipt.request.plant].get("definition", ""))
			if _content.plants.types.has(definition):
				var rule: Dictionary = _content.plants.types[definition]
				for item: String in [str(rule.product.item), str(rule.body_product.item)]:
					result.operations[id + ":remains:" + item] = true
	return result
