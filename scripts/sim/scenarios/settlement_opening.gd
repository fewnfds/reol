extends RefCounted
## Compile once, adopt through existing owners, then leave the running world.
## This module never schedules work or supplies goods after initialization.
const Operations = preload("res://scripts/sim/kernel/operation_defs.gd")
const Definition = preload("res://scripts/sim/definitions/openings/opening_def.gd")
const Terrain = preload("res://scripts/sim/kernel/terrain.gd")
const Query = preload("res://scripts/sim/kernel/operation_query.gd")
const Roles = preload("res://scripts/sim/kernel/institution_defs.gd")
const Items = preload("res://scripts/sim/kernel/items.gd")
const Growth = preload("res://scripts/sim/kernel/growth.gd")
const Plants = preload("res://scripts/sim/kernel/nature_defs.gd")
const Agency = preload("res://scripts/sim/kernel/agency_defs.gd")

static func _inside(point: Vector2i) -> bool:
	return point.x >= 1 and point.y >= 1 and point.x < Terrain.SIZE - 1 and point.y < Terrain.SIZE - 1

static func _accessible(world: RefCounted, target: int, origin: Vector2, handler: String) -> bool:
	# Assembly is not a simulation slice. Check each authored access claim with
	# a fresh ordinary search allowance; a deferred request is not a proven path.
	var navigation: RefCounted = world.lanes[0].navigation
	navigation.begin_step(); navigation.deferred = false
	var point: Vector2 = world.facilities.interaction_point(world, target, origin, 0.35, false, handler)
	return point.x >= 0 and not navigation.deferred

static func _acquaintance(world: RefCounted, actor: int, target: int, teachings: Array) -> void:
	var value: Dictionary = world.operation_target(target)
	value.tile = Terrain.index(Vector2i(world.combat.position(world, target).floor()))
	value["teaches"] = {}
	for method: String in teachings: value.teaches[method] = 0
	world.knowledge.seed(world, actor, value, 0)

static func compile(spec: Definition) -> Dictionary:
	var errors := PackedStringArray()
	var patterns: Array = []
	var groups: Dictionary = {}
	if spec == null: return {"errors": PackedStringArray(["opening: missing resource"])}
	if spec.title.strip_edges().is_empty() or spec.title.length() > 80 or spec.district_origins.is_empty() or spec.district_origins.size() > 8 or spec.district_names.size() != spec.district_origins.size() or spec.residents_per_district < 2 or spec.residents_per_district > 128 or spec.population() > 1000: errors.append("opening: invalid title/districts/population")
	for name: String in spec.district_names:
		if name.strip_edges().is_empty(): errors.append("opening: empty district name")
	if spec.spawn_offsets.size() != spec.residents_per_district or spec.satiety_min < 0 or spec.satiety_span < 1 or spec.satiety_min + spec.satiety_span > 10001 or spec.energy_min < 0 or spec.energy_span < 1 or spec.energy_min + spec.energy_span > 10001: errors.append("opening: invalid initial personal conditions")
	if not Plants.DEFINITIONS.has(spec.qi_plant) or not Plants.DEFINITIONS.get(spec.qi_plant, {}).has("stored_qi") or spec.initial_source_qi < 0 or spec.initial_source_qi > int(Plants.DEFINITIONS.get(spec.qi_plant, {}).get("stored_qi", {}).get("capacity", 0)): errors.append("opening: invalid qi reservoir")
	for area: Rect2i in spec.soil_areas:
		if not area.has_area() or not Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE).encloses(area): errors.append("opening: invalid soil area")
	for layout: Resource in spec.layouts:
		if layout == null or not layout.id.is_valid_identifier() or layout.repeats < 1 or layout.repeats > 100: errors.append("opening: invalid layout"); continue
		for place: Resource in layout.placements:
			if place == null or not place.key.is_valid_identifier() or not Query.BUILDINGS.has(place.definition) or place.extent.x < 1 or place.extent.y < 1 or place.extent.x * place.extent.y > 512 or place.offsets.is_empty() or place.offsets.size() > 128 or place.spacing.x < 1 or place.spacing.y < 1 or place.facing < 0 or place.facing > 3: errors.append("opening: invalid placement"); continue
			for item: String in place.stock:
				if not Items.valid(item) or place.stock[item] < 1 or place.stock[item] > 100000: errors.append("opening: invalid initial stock")
			if not place.stock.is_empty() and not (Query.BUILDINGS[place.definition].capabilities.has("storage") or Query.BUILDINGS[place.definition].capabilities.has("workbench")): errors.append("opening: initial stock requires a container or workbench")
			var capacity: int = int(Query.BUILDINGS[place.definition].capabilities.get("storage", {}).get("capacity", -1))
			if capacity >= 0 and int(place.stock.values().reduce(func(sum: int, count: int): return sum + count, 0)) > capacity: errors.append("opening: initial stock exceeds container capacity")
			if place.member_food_service and not (Query.BUILDINGS[place.definition].capabilities.has("storage") or Query.BUILDINGS[place.definition].capabilities.has("workbench")): errors.append("opening: unsupported member food service")
			for repeat: int in layout.repeats:
				for point: Vector2i in place.points():
					var entry: Dictionary = {"key": place.key, "definition": place.definition, "offset": layout.origin + layout.stride * repeat + point, "facing": place.facing, "stock": place.stock.duplicate(), "food": place.member_food_service}
					patterns.append(entry)
					if patterns.size() * spec.district_origins.size() > 20000: return {"errors": PackedStringArray(["opening: too many initial placements"])}
					if not groups.has(place.key): groups[place.key] = []
					groups[place.key].append(entry)
	if groups.get(spec.bed_key, []).size() != spec.residents_per_district: errors.append("opening: exactly one bed per resident is required")
	for entry: Dictionary in groups.get(spec.bed_key, []):
		if not Query.BUILDINGS[entry.definition].capabilities.has("rest"): errors.append("opening: assigned residence is not a bed")
	for key: String in spec.familiar_keys:
		if not groups.has(key): errors.append("opening: unknown familiar place " + key)
	var residents: Dictionary = {}
	var teachings: Dictionary = {}
	for profile: Resource in spec.resident_profiles:
		if profile == null: errors.append("opening: null resident profile"); continue
		for slot: int in profile.slots:
			if slot < 0 or slot >= spec.residents_per_district or residents.has(slot): errors.append("opening: duplicate/out-of-range resident profile")
			residents[slot] = true
			teachings[slot] = profile.public_teachings.duplicate()
		for method: String in Array(profile.mastered) + Array(profile.introduced) + Array(profile.development):
			if not Growth.Defs.METHODS.has(method): errors.append("opening: unknown method " + method)
		for method: String in profile.mastered:
			if method in profile.introduced: errors.append("opening: repeated method seed")
			if Array(profile.mastered).count(method) != 1: errors.append("opening: duplicate mastered method")
		for method: String in profile.introduced:
			if Array(profile.introduced).count(method) != 1: errors.append("opening: duplicate introduced method")
		for method: String in profile.public_teachings:
			if method not in profile.mastered: errors.append("opening: public teaching is not mastered")
		if profile.mentor_slot < -1 or profile.mentor_slot >= spec.residents_per_district or profile.mentor_slot in profile.slots: errors.append("opening: invalid mentor")
		for peer: int in profile.instruction_targets:
			if peer < 0 or peer >= spec.residents_per_district or peer in profile.slots: errors.append("opening: invalid instruction partner")
		if not profile.instruction_targets.is_empty() and not Growth.Defs.METHODS.has(profile.instruction_method): errors.append("opening: unknown instruction method")
		for key: String in profile.dispositions:
			if key not in Agency.DISPOSITIONS or not is_finite(profile.dispositions[key]) or profile.dispositions[key] < 0.0 or profile.dispositions[key] > 2.0: errors.append("opening: invalid disposition")
	for appointment: Resource in spec.appointments:
		if appointment == null or appointment.actor_slot < 0 or appointment.actor_slot >= spec.residents_per_district or not Roles.ROLES.has(appointment.role): errors.append("opening: invalid appointment"); continue
		var duty: Dictionary = Roles.ROLES[appointment.role].duty
		for key: String in appointment.source_keys:
			if not groups.has(key): errors.append("opening: unknown duty source " + key)
		if duty.get("kind") == "cultivation":
			if appointment.sites_count < 1 or appointment.sites_count > 32 or appointment.sites_start < 0 or groups.get(appointment.sites_key, []).size() < appointment.sites_start + appointment.sites_count or groups.get(appointment.destination_key, []).size() != 1: errors.append("opening: invalid field range/destination")
		elif duty.get("kind", "") in ["produce", "delivery"]:
			if appointment.target_index < 0 or groups.get(appointment.target_key, []).size() <= appointment.target_index or groups.get(appointment.channel_key, []).size() != 1: errors.append("opening: invalid duty target/channel")
		else: errors.append("opening: appointment requires a defined duty")
	var occupied: Dictionary = {}
	var department_keys: Array[String] = []
	var managed_keys: Array[String] = []
	for department: Resource in spec.departments:
		if department == null or not department.key.is_valid_identifier() or department.key in department_keys or department.title.strip_edges().is_empty() or (not department.parent_key.is_empty() and department.parent_key not in department_keys): errors.append("opening: invalid department hierarchy"); continue
		department_keys.append(department.key)
		if not department.supplier_key.is_empty() and department.supplier_key not in department_keys: errors.append("opening: supplier must precede consuming department")
		if department.daily_target > 0 and (not Operations.OPERATIONS.get(department.production_operation, {}).get("recipe", {}).get("outputs", {}).has(department.production_item) or department.head_slot < 0): errors.append("opening: invalid production objective")
		for key: String in department.storage_items:
			if key not in department.facility_keys: errors.append("opening: stock filter outside department")
			for item: String in department.storage_items[key]:
				if not Items.valid(item): errors.append("opening: invalid stock filter")
		if department.head_slot < -1 or department.head_slot >= spec.residents_per_district: errors.append("opening: invalid department head")
		for key: String in department.facility_keys:
			if not groups.has(key) or key in managed_keys: errors.append("opening: invalid/duplicate managed facility group")
			managed_keys.append(key)
		for group: String in department.groups:
			if group.strip_edges().is_empty(): errors.append("opening: empty work group")
			for key: String in department.groups[group]:
				if key not in department.facility_keys: errors.append("opening: work group outside department")
		for assignment: Resource in department.assignments:
			if assignment == null: errors.append("opening: null work assignment"); continue
			for slot: int in assignment.actor_slots:
				if slot < 0 or slot >= spec.residents_per_district: errors.append("opening: invalid worker slot")
			for duty: String in assignment.duties:
				if duty not in preload("res://scripts/sim/kernel/department_rules.gd").DUTIES: errors.append("opening: invalid work duty")
			for capability: String in assignment.capabilities:
				if capability not in preload("res://scripts/sim/kernel/department_rules.gd").CAPABILITIES: errors.append("opening: invalid management capability")
			for group: String in assignment.groups:
				if not department.groups.has(group): errors.append("opening: unknown worker group")
			if not assignment.authority_group.is_empty() and not department.groups.has(assignment.authority_group): errors.append("opening: unknown authority group")
	var spawn: Dictionary = {}
	var reservoirs: Dictionary = {}
	for origin: Vector2i in spec.district_origins:
		for pattern: Dictionary in patterns:
			var point: Vector2i = origin + pattern.offset
			if not _inside(point): errors.append("opening: placement outside map"); continue
			var cells: PackedInt32Array = preload("res://scripts/sim/kernel/facilities.gd").placed_cells(Query.BUILDINGS[pattern.definition], Terrain.index(point), pattern.facing)
			if cells.is_empty(): errors.append("opening: invalid footprint"); continue
			var layer: String = Query.BUILDINGS[pattern.definition].layer
			for cell: int in cells:
				if not _inside(Terrain.cell(cell)): errors.append("opening: footprint outside map interior")
				var key: String = "%s:%d" % [layer, cell]
				if occupied.has(key): errors.append("opening: overlapping placements at " + key)
				occupied[key] = pattern.definition
		for offset: Vector2i in spec.spawn_offsets:
			var point: Vector2i = origin + offset
			var tile: int = Terrain.index(point)
			if not _inside(point) or spawn.has(tile): errors.append("opening: invalid/duplicate initial body position")
			spawn[tile] = true
		for offset: Vector2i in spec.qi_offsets:
			var point: Vector2i = origin + offset
			var tile: int = Terrain.index(point)
			if not _inside(point) or occupied.has("ground:%d" % tile) or reservoirs.has(tile): errors.append("opening: reservoir placement occupied/outside map")
			reservoirs[tile] = true
	for tile: int in spawn:
		var key: String = "ground:%d" % tile
		if occupied.has(key) and Query.BUILDINGS[occupied[key]].facts.get("movement_blocked", false): errors.append("opening: initial body inside a solid")
		if reservoirs.has(tile) and Plants.DEFINITIONS.get(spec.qi_plant, {}).get("blocks", false): errors.append("opening: initial body inside a reservoir")
	for tile: int in reservoirs:
		if occupied.has("ground:%d" % tile): errors.append("opening: reservoir overlaps another district")
	return {"errors": errors, "patterns": patterns, "groups": groups, "teachings": teachings}

static func _scope(appointment: Resource, groups: Dictionary) -> Dictionary:
	var sources: Array = []
	for key: String in appointment.source_keys: sources.append_array(groups[key])
	if Roles.ROLES[appointment.role].duty.kind == "cultivation":
		return {"sites": groups[appointment.sites_key].slice(appointment.sites_start, appointment.sites_start + appointment.sites_count), "sources": sources, "destination": groups[appointment.destination_key][0]}
	return {"target": groups[appointment.target_key][appointment.target_index], "sources": sources, "channel": groups[appointment.channel_key][0]}

static func assemble(world: RefCounted, spec: Definition) -> PackedStringArray:
	var plan: Dictionary = compile(spec)
	if not plan.errors.is_empty(): return plan.errors
	if world.elapsed_ms != 0 or world.actor_count != spec.population() or world.objects.records.size() != spec.population() or not world.actor_slots.has(1) or not world.institutions.organizations.is_empty() or not world.knowledge.records.is_empty(): return PackedStringArray(["opening: requires a new empty world with the requested population"])
	var errors := PackedStringArray()
	var org: int = world.institutions.create(spec.title)
	var districts: Array = []
	for area: Rect2i in spec.soil_areas:
		if not Rect2i(0, 0, Terrain.SIZE, Terrain.SIZE).encloses(area): return PackedStringArray(["opening: invalid soil area"])
		for y: int in range(area.position.y, area.end.y):
			for x: int in range(area.position.x, area.end.x):
				var tile: int = Terrain.index(Vector2i(x, y))
				world.terrain.base[tile] = Terrain.Substrate.SOIL
				world.terrain.cover[tile] = Terrain.Cover.GRASS
	for district: int in spec.district_origins.size():
		var origin: Vector2i = spec.district_origins[district]
		var groups: Dictionary = {}
		var food_services: Array[int] = []
		var qi_sources: Array[int] = []
		for pattern: Dictionary in plan.patterns:
			var id: int = world.facilities.create_completed(world, pattern.definition, Terrain.index(origin + pattern.offset), pattern.facing)
			if id <= 0: return PackedStringArray(["opening: failed facility " + pattern.key])
			world.objects.records[id].organization = org
			if not groups.has(pattern.key): groups[pattern.key] = []
			groups[pattern.key].append(id)
			if pattern.food: food_services.append(id)
			var total: int = int(pattern.stock.values().reduce(func(sum: int, value: int): return sum + value, 0))
			if int(world.objects.records[id].capacity) >= 0 and total > int(world.objects.records[id].capacity): return PackedStringArray(["opening: initial container cannot hold declared stock"])
			for item: String in pattern.stock:
				world.objects.add(id, item, int(pattern.stock[item]), world.objects.Stock.right(0, org))
		for offset: Vector2i in spec.qi_offsets:
			var id: int = world.nature.create(world, spec.qi_plant, Terrain.index(origin + offset))
			if id <= 0: return PackedStringArray(["opening: failed natural reservoir"])
			var record: Dictionary = world.objects.records[id]
			record.stage = world.nature.Stage.MATURE; record.growth_ms = int(world.nature.definitions[spec.qi_plant].mature_ms)
			record.qi = spec.initial_source_qi; world.nature._sync(world, id)
			qi_sources.append(id)
		districts.append({"groups": groups, "food_services": food_services, "qi_sources": qi_sources, "entrypoint": Vector2(origin + spec.spawn_offsets[0]) + Vector2.ONE * 0.5})
		world.regions.create_landmark(world, spec.district_names[district], Terrain.index(origin + spec.spawn_offsets[0]))
	world.flush_topology()
	for district: Dictionary in districts:
		var groups: Dictionary = district.groups
		for ids: Array in groups.values():
			for target: int in ids:
				var record: Dictionary = world.objects.records[target]
				var capabilities: Dictionary = Query.BUILDINGS.get(record.definition, {}).get("capabilities", {})
				for capability: String in capabilities:
					var handler: String = str({"rest": "rest", "storage": "take", "workbench": "craft", "records": "read_channel", "cultivation": "sow", "stock_source": "collect_source"}.get(capability, ""))
					if not handler.is_empty() and not _accessible(world, target, district.entrypoint, handler): errors.append("opening: inaccessible work positions at " + record.definition + ":" + handler)
		for target: int in district.qi_sources:
			if not _accessible(world, target, district.entrypoint, "practice"): errors.append("opening: inaccessible reservoir")
	if not errors.is_empty(): return errors
	for district: int in districts.size():
		var groups: Dictionary = districts[district].groups
		for slot: int in spec.residents_per_district:
			var actor: int = district * spec.residents_per_district + slot + 1
			var body: int = world.actor_slots[actor]
			var page: RefCounted = world.pages[body / 256]
			var row: int = body % 256
			var person: Dictionary = world.objects.records[actor]
			person.autonomous = false; person["side"] = 0
			person["name"] = "%s弟子%02d" % [spec.district_names[district], slot + 1]
			page.positions[row] = Vector2(spec.district_origins[district] + spec.spawn_offsets[slot]) + Vector2.ONE * 0.5
			page.targets[row] = page.positions[row]
			page.hunger[row] = spec.satiety_min + (actor * 137) % spec.satiety_span
			page.energy[row] = spec.energy_min + (actor * 251) % spec.energy_span
			if not world.institutions.admit(world, org, actor, ["eat", "rest"]): errors.append("opening: resident membership refused")
			if not world.institutions.arrange_service(world, groups[spec.bed_key][slot], "rest", [actor]): errors.append("opening: residence assignment refused")
		for profile: Resource in spec.resident_profiles:
			for slot: int in profile.slots:
				var actor: int = district * spec.residents_per_district + slot + 1
				var person: Dictionary = world.objects.records[actor]
				person.name = "%s%s%02d" % [spec.district_names[district], profile.name_prefix, slot + 1]
				for method: String in profile.mastered: Growth.seed(person, method, 0)
				for method: String in profile.introduced: Growth.seed(person, method, 0, false)
				if not world.livelihood.set_dispositions(world, actor, profile.dispositions): errors.append("opening: dispositions refused")
				for method: String in profile.development:
					if world.livelihood.add_goal(world, actor, "development", {"method": method}) <= 0: errors.append("opening: personal learning purpose refused")
				for peer: int in profile.instruction_targets:
					var target: int = district * spec.residents_per_district + peer + 1
					if world.livelihood.add_goal(world, actor, "instruction", {"method": profile.instruction_method, "target": target}) <= 0: errors.append("opening: personal instruction purpose refused")
		for target: int in districts[district].food_services:
			if not world.institutions.arrange_service(world, target, "eat", [], true): errors.append("opening: member food service refused")
		for appointment: Resource in spec.appointments:
			var actor: int = district * spec.residents_per_district + appointment.actor_slot + 1
			var scope: Dictionary = _scope(appointment, groups)
			var targets: Array = world.institutions.Duties.targets(scope)
			if world.institutions.appoint(world, org, actor, appointment.role, targets, scope) <= 0: errors.append("opening: role assignment refused")
		var department_ids: Dictionary = {}
		for definition: Resource in spec.departments:
			var id: int = world.institutions.Departments.create(world.institutions, org, spec.district_names[district] + definition.title, int(department_ids.get(definition.parent_key, 0)))
			if id <= 0: errors.append("opening: department refused"); continue
			department_ids[definition.key] = id
			var department: Dictionary = world.institutions.departments[id]
			if definition.head_slot >= 0: department.head = district * spec.residents_per_district + definition.head_slot + 1
			for key: String in definition.facility_keys:
				for facility: int in groups[key]:
					if not world.institutions.Departments.attach(world.institutions, world, id, facility): errors.append("opening: managed facility refused")
			for group: String in definition.groups:
				var facilities: Array = []
				for key: String in definition.groups[group]: facilities.append_array(groups[key])
				department.groups[group] = {"facilities": facilities}
			for assignment: Resource in definition.assignments:
				for local_slot: int in assignment.actor_slots:
					var actor: int = district * spec.residents_per_district + local_slot + 1
					if not world.institutions.Departments.assign(world.institutions, id, actor, Array(assignment.duties), Array(assignment.groups), assignment.groups.is_empty()): errors.append("opening: work assignment refused")
					var issuer: int = district * spec.residents_per_district + 1 if local_slot != 0 else 0
					if not assignment.capabilities.is_empty() and not world.institutions.Departments.grant(world.institutions, id, actor, assignment.title, Array(assignment.capabilities), assignment.descendants, assignment.authority_group, issuer): errors.append("opening: management grant refused")
			department.supplier = int(department_ids.get(definition.supplier_key, 0))
			for key: String in definition.storage_items:
				for target: int in groups[key]: world.objects.records[target]["storage_policy"] = {"items": Array(definition.storage_items[key]), "min_tier": 1, "max_tier": 99, "destinations": []}
			if definition.daily_target > 0:
				var order: int = world.institutions.Orders.create(world.institutions, world, int(department.head), id, definition.production_operation, definition.production_item, definition.daily_target, "", 0, true)
				if order == 0: errors.append("opening: production target refused")
				else:
					for target: int in department.facilities:
						if world.objects.records[target].kind == "workbench":
							if world.institutions.management(world, int(department.head), {"op": "configure", "department": id, "facility": target, "order": order}) != "management_updated": errors.append("opening: workbench configuration refused")
	world.institutions.Workflow.rebuild(world.institutions, world)
	if not errors.is_empty(): return errors
	world.sight.sync(world)
	for district: int in districts.size():
		var groups: Dictionary = districts[district].groups
		for slot: int in spec.residents_per_district:
			var actor: int = district * spec.residents_per_district + slot + 1
			var known: Array = [groups[spec.bed_key][slot]] + districts[district].qi_sources
			for key: String in spec.familiar_keys: known.append_array(groups[key])
			for duty: Dictionary in world.institutions.Duties.views(world.institutions, actor).values(): known.append_array(world.institutions.Duties.targets(duty))
			for target: int in known:
				var value: Dictionary = world.operation_target(target)
				for field: String in ["inventory", "contents", "process"]: value.erase(field)
				world.knowledge.seed(world, actor, value, 0)
			for profile: Resource in spec.resident_profiles:
				# Explicit public instruction is local sect knowledge, including for
				# the player. It does not disclose a teacher's other methods.
				if not profile.public_teachings.is_empty():
					for teacher_slot: int in profile.slots:
						var teacher: int = district * spec.residents_per_district + teacher_slot + 1
						if teacher != actor: _acquaintance(world, actor, teacher, Array(profile.public_teachings))
				if slot not in profile.slots: continue
				var peers: Array = Array(profile.instruction_targets)
				if profile.mentor_slot >= 0: peers.append(profile.mentor_slot)
				for peer: int in peers:
					var target: int = district * spec.residents_per_district + peer + 1
					_acquaintance(world, actor, target, Array(plan.teachings.get(peer, [])))
					_acquaintance(world, target, actor, Array(plan.teachings.get(slot, [])))
					if not world.society.Contacts.acknowledge(world.society, world, actor, target, 0, true): errors.append("opening: acquaintance refused")
			world.knowledge.record(actor).due_ms = 0 # First observation joins the shared scheduled quota.
			world.objects.records[actor].autonomous = actor != 1
			if actor != 1: world.decisions.wake(world, actor, 0, "settled", 50 + actor % 20 * 50)
			var point: Vector2 = world.combat.position(world, actor)
			var bed: int = groups[spec.bed_key][slot]
			if not world.terrain.can_stand(point, 0.35) or not _accessible(world, bed, point, "rest"): errors.append("opening: initial body or residence is inaccessible")
	world.environment.update(0, world.pages, world.actor_slots)
	for page: RefCounted in world.pages: page.sample_environment(0.0)
	world.perception.update(world, 0, true)
	world.knowledge.observe(world, 1, 0)
	if not world.institutions.valid(world) or not world.knowledge.valid(world) or not world.nature.rebuild(world) or not world.livelihood.valid(world) or not world.society.valid(world) or not world.decisions.valid(world) or not world.regions.valid(world): errors.append("opening: adopted domain state is invalid")
	return errors
