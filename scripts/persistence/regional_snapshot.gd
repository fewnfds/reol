class_name RegionalSnapshot
extends RefCounted
## Capture and independent candidate restore for RegionalSimulation. Runtime
## stepping stays with the executor; each saved domain stays with its owner.

const SaveDomains = preload("res://scripts/persistence/world_save_domains.gd")
const SCHEMA_VERSION: int = RegionalSimulation.SCHEMA_VERSION
const MINUTE_MS: int = RegionalSimulation.MINUTE_MS


static func capture(world: RegionalSimulation) -> Dictionary:
	if world.services != null and world.services._handling_stock:
		return {}
	if world._publishing_boundary or world.has_pending_boundary() or world.construction != null and world.construction._changing or world.environment_boundary_active() or (world.object_lifecycle != null and world.object_lifecycle._committing):
		return {}
	if not world.synchronize_regions() or not world.environment_fields.settle_at_ms(world.elapsed_ms):
		return {}
	var regional_states: Dictionary = {}
	for region_id: String in RegionalSimulation._sorted_keys(world.regions):
		regional_states[region_id] = world.regions[region_id].to_dict()
	var snapshot: Dictionary = {
		"version": SCHEMA_VERSION, "settings": world.settings.duplicate(true),
		"current_time": world.current_time, "target_time": world.target_time, "elapsed_ms": world.elapsed_ms, "target_ms": world.target_ms,
		"active_region": world.active_region, "regions": regional_states,
		"routes": world.routes.duplicate(true), "shipments": world.shipments.duplicate(true),
		"couriers": world.couriers.duplicate(true), "events": world.events.duplicate(true),
		"messages": world.messages.duplicate(true), "local_news": world.local_news.duplicate(true),
		"operations": world.operations.duplicate(true), "in_transit": world.in_transit.to_dict(),
		"next_id": world._next_id,
	}
	var domains := SaveDomains.registry(world.services != null)
	var captured: Dictionary = domains.capture(world)
	if captured.is_empty():
		return {}
	snapshot.merge(captured)
	return SnapshotValues.for_save(snapshot)


static func restore(world: RegionalSimulation, data: Dictionary) -> bool:
	if world._publishing_boundary or world.has_pending_boundary() or world.object_lifecycle != null and world.object_lifecycle._committing:
		return false
	# Earlier schemas lack authoritative field-response history.
	if data.get("version") != SCHEMA_VERSION:
		return false
	if world.construction != null and world.construction._changing or world.environment_boundary_active():
		return false
	# Validation constructs an entirely separate world. Failed loads preserve
	# existing regional objects, inventory and pending deliveries.
	# Earlier regional and thermal versions are rejected before validation.
	if world._content == null or not _valid_world_shape(world, data):
		return false
	if (world.services != null) != data.has("services"):
		return false
	var allowed_subjects: Dictionary = {}
	for saved_region: Variant in data.regions.values():
		if not saved_region is Dictionary or not saved_region.get("actors") is Dictionary:
			return false
		for actor_id: Variant in saved_region.actors:
			if not actor_id is String or allowed_subjects.has(actor_id):
				return false
			allowed_subjects[actor_id] = true
	var domains := SaveDomains.registry(world.services != null)
	var next_regions: Dictionary = {}
	var subject_scope: Dictionary = allowed_subjects if world.services != null else {}
	for region_id: String in RegionalSimulation._sorted_keys(world.regions):
		var saved: Dictionary = data.regions[region_id]
		if not saved.get("actors") is Dictionary or not saved.get("places") is Dictionary or not saved.get("config") is Dictionary:
			return false
		if not SimLandResources.opening_matches(RegionalSimulation._base_workplace_config(saved.config), RegionalSimulation._base_workplace_config(world.opening_config(region_id))):
			return false
		var inventory_scope: Dictionary = domains.inventory_scope(data, region_id, world._content)
		if inventory_scope.is_empty():
			return false
		inventory_scope["service_custody"] = world.services != null
		inventory_scope["rainfall_limit"] = SimWeather.rain_budget(data.weather, world._content.weather, region_id, int(data.elapsed_ms))
		var simulation: VillageSimulation = VillageSimulation.from_snapshot(world._content, saved, subject_scope, inventory_scope)
		if simulation == null:
			return false
		if simulation.elapsed_ms != int(data.elapsed_ms):
			return false
		# Navigation is an adapter, never serialized. Keep the caller's provider.
		simulation.set_navigation(world.regions[region_id]._navigation, world.regions[region_id]._step_validator)
		next_regions[region_id] = simulation
	# A restore-only factory has no initialized opening instances to validate.
	# Check actual restored owners, route endpoints and clocks before any commit.
	if not world._valid_settings(world.settings, next_regions):
		return false
	var next_transit := SimInventory.new()
	if not next_transit.restore(data.in_transit) or not _valid_cross_state(world, data, next_regions, next_transit):
		return false
	var candidate_world := RegionalSimulation.new()
	candidate_world.map_data = world.map_data
	candidate_world.regions = next_regions
	candidate_world.settings = world.settings
	candidate_world.elapsed_ms = int(data.elapsed_ms)
	candidate_world.target_ms = int(data.target_ms)
	candidate_world.routes = data.routes.duplicate(true)
	candidate_world.shipments = data.shipments.duplicate(true)
	candidate_world.couriers = data.couriers.duplicate(true)
	candidate_world.operations = data.operations.duplicate(true)
	candidate_world.in_transit = next_transit
	candidate_world._content = world._content
	var context: Dictionary = {"world": candidate_world, "source": world, "content": world._content, "data": data}
	if not domains.stage(data, context):
		return false
	# Candidate checks use only candidate geometry. Reattach live adapter
	# callbacks after every domain has passed validation, before old owners go.
	if world.map_data != null:
		if world.large_bodies != null:
			context["large_incoming"] = world.large_bodies._incoming
		if world.construction != null:
			context["construction_incoming"] = world.construction._incoming
		if world.avian_life != null:
			context["avian_landing"] = world.avian_life._landing
	world.regions = next_regions
	world.elapsed_ms = int(data.elapsed_ms)
	world.target_ms = int(data.target_ms)
	world.active_region = data.active_region
	world.routes = data.routes.duplicate(true)
	world.shipments = data.shipments.duplicate(true)
	world.couriers = data.couriers.duplicate(true)
	world.events = data.events.duplicate(true)
	world.messages = data.messages.duplicate(true)
	world.local_news = data.local_news.duplicate(true)
	world.operations = data.operations.duplicate(true)
	world.in_transit = next_transit
	world._next_id = int(data.next_id)
	if world.plants != null:
		world.plants.retire_bindings()
	var installed: bool = domains.install(world, context)
	assert(installed, "validated saved-world participants must install")
	world._bind_service_guards()
	world._region_boundaries = {}
	world._dirty_region_boundaries.clear()
	for region_id: String in world.regions:
		world._region_boundaries[region_id] = world.regions[region_id].next_boundary_ms()
	world._replace_space()
	return world._bind_settlement()


static func _valid_world_shape(world: RegionalSimulation, data: Dictionary) -> bool:
	if data.get("version") != SCHEMA_VERSION or SnapshotValues.normalized(data.get("settings")) != SnapshotValues.normalized(world.settings):
		return false
	for field: String in ["regions", "routes", "shipments", "couriers", "local_news", "operations", "in_transit"]:
		if not data.get(field) is Dictionary:
			return false
	if not SaveDomains.registry(world.services != null).valid_shape(data):
		return false
	if data.spirit_sources.get("version") != SimSpiritSources.VERSION:
		return false
	for field: String in ["events", "messages"]:
		if not data.get(field) is Array:
			return false
	if not RegionalSimulation._integer(data.get("current_time"), 0) or not RegionalSimulation._integer(data.get("target_time"), int(data.current_time)) or not RegionalSimulation._integer(data.get("next_id"), 1):
		return false
	if not RegionalSimulation._integer(data.get("elapsed_ms"), 0) or not RegionalSimulation._integer(data.get("target_ms"), int(data.elapsed_ms)):
		return false
	if int(data.current_time) != floori(float(data.elapsed_ms) / MINUTE_MS) or int(data.target_time) != floori(float(data.target_ms) / MINUTE_MS):
		return false
	if not data.get("active_region") is String or (not str(data.active_region).is_empty() and not world.regions.has(data.active_region)):
		return false
	return RegionalSimulation._sorted_keys(data.regions) == RegionalSimulation._sorted_keys(world.regions) and RegionalSimulation._sorted_keys(data.routes) == RegionalSimulation._sorted_keys(world.routes) and RegionalSimulation._sorted_keys(data.couriers) == RegionalSimulation._sorted_keys(world.couriers) and RegionalSimulation._sorted_keys(data.local_news) == RegionalSimulation._sorted_keys(world.regions)


static func _valid_cross_state(world: RegionalSimulation, data: Dictionary, candidates: Dictionary, cargo: SimInventory) -> bool:
	var time: int = int(data.current_time)
	var ids: Dictionary = {}
	for route_id: String in data.routes:
		var route: Variant = data.routes[route_id]
		if not route is Dictionary or route.has("next_assessment") or not route.get("blocked") is bool or not RegionalSimulation._integer(route.get("demand"), 0) or not RegionalSimulation._integer(route.get("request_time"), -1, time):
			return false
	for shipment_id: Variant in data.shipments:
		var shipment: Variant = data.shipments[shipment_id]
		if not shipment_id is String or not shipment is Dictionary or shipment.get("id") != shipment_id or not _unique_id(shipment_id, ids, int(data.next_id)):
			return false
		if not data.routes.has(shipment.get("route")) or not shipment.get("status") in ["outbound", "blocked", "delivered"] or not RegionalSimulation._integer(shipment.get("amount"), 1) or not RegionalSimulation._integer(shipment.get("departed_at"), 0, time):
			return false
		var definition: Dictionary = world.settings.routes[shipment.route]
		if shipment.get("item") != definition.item or shipment.get("container") != "cargo:" + String(shipment_id) or not cargo.containers.has(shipment.container):
			return false
		var delivered: bool = shipment.status == "delivered"
		if not RegionalSimulation._integer(shipment.get("delivered_at"), int(shipment.departed_at) if delivered else -1, time if delivered else -1):
			return false
		if cargo.containers[shipment.container].size() != 1 or cargo.quantity(shipment.container, shipment.item) != (0 if delivered else int(shipment.amount)):
			return false
		if not RegionalSimulation._valid_transfer_receipt(data.operations.get(shipment_id + ":pickup"), definition.from, "transit", definition.source, shipment.container, shipment.item, int(shipment.amount)):
			return false
		if delivered and not RegionalSimulation._valid_transfer_receipt(data.operations.get(shipment_id + ":delivery"), "transit", definition.to, shipment.container, definition.target, shipment.item, int(shipment.amount)):
			return false
		if not delivered and data.operations.has(shipment_id + ":delivery"):
			return false
	for courier_id: String in data.couriers:
		var courier: Variant = data.couriers[courier_id]
		if not courier is Dictionary or courier.get("id") != courier_id or not data.routes.has(courier.get("route")):
			return false
		var definition: Dictionary = world.settings.routes[courier.route]
		if definition.courier != courier_id or courier.get("name") != definition.courier_name or not courier.get("phase") in ["idle", "outbound", "returning", "resting", "waiting_delivery"]:
			return false
		var maximum_progress: int = int(definition.travel_minutes) if courier.phase == "waiting_delivery" else int(definition.travel_minutes) - 1
		if not RegionalSimulation._number(courier.get("energy"), 0.0, 100.0) or not RegionalSimulation._integer(courier.get("progress"), 0, maximum_progress) or not RegionalSimulation._integer(courier.get("rest_remaining"), 0, int(world.settings.courier_needs.rest_minutes)) or not courier.get("shipment") is String:
			return false
		if courier.phase in ["outbound", "returning", "waiting_delivery"]:
			if not data.shipments.has(courier.shipment) or data.shipments[courier.shipment].route != courier.route:
				return false
			if (courier.phase == "returning") != (data.shipments[courier.shipment].status == "delivered"):
				return false
			if courier.phase == "outbound" and ((data.shipments[courier.shipment].status == "blocked") != bool(data.routes[courier.route].blocked)):
				return false
			if courier.phase == "waiting_delivery" and (not RegionalSimulation._integer(courier.get("retry_at"), time + 1) or int(courier.progress) != int(definition.travel_minutes)):
				return false
		elif courier.shipment != "" or int(courier.progress) != 0:
			return false
	for shipment: Dictionary in data.shipments.values():
		if shipment.status != "delivered" and data.couriers[world.settings.routes[shipment.route].courier].shipment != shipment.id:
			return false
	if not cargo.reservations.is_empty() or not cargo.operations.is_empty() or not cargo.custody.is_empty() or cargo.containers.size() != data.shipments.size():
		return false
	for region_id: String in data.local_news:
		if not data.local_news[region_id] is Array:
			return false
		for news: Variant in data.local_news[region_id]:
			if not news is Dictionary or not news.get("id") is String or not candidates.has(news.get("source")) or not news.get("line") is String or not RegionalSimulation._integer(news.get("occurred_at"), 0, time) or not RegionalSimulation._integer(news.get("heard_at"), int(news.occurred_at), time):
				return false
	for event: Variant in data.events:
		if not event is Dictionary or not event.get("kind") is String or not event.get("line") is String or not candidates.has(event.get("region")) or not data.routes.has(event.get("route")) or not RegionalSimulation._integer(event.get("at"), 0, time) or not _unique_id(event.get("id"), ids, int(data.next_id)):
			return false
	for message: Variant in data.messages:
		if not message is Dictionary or not message.get("kind") in ["stock_request", "news"] or not candidates.has(message.get("from")) or not candidates.has(message.get("to")) or message.from == message.to or not data.routes.has(message.get("route")):
			return false
		if not RegionalSimulation._integer(message.get("sent_at"), 0, time) or not RegionalSimulation._integer(message.get("due"), time + 1) or not message.get("details") is Dictionary or not message.details.get("line") is String or not _unique_id(message.get("id"), ids, int(data.next_id)):
			return false
		if message.kind == "stock_request" and (not RegionalSimulation._integer(message.details.get("amount"), 0) or not RegionalSimulation._integer(message.details.get("observed_at"), 0, int(message.sent_at))):
			return false
	var expected_operations: int = 0
	for shipment: Dictionary in data.shipments.values():
		expected_operations += 2 if shipment.status == "delivered" else 1
	return data.operations.size() == expected_operations


static func _unique_id(value: Variant, used: Dictionary, next_id: int) -> bool:
	if not value is String or not String(value).begins_with("world:") or used.has(value):
		return false
	var tail: String = String(value).get_slice(":", 2)
	if not tail.is_valid_int() or int(tail) < 1 or int(tail) >= next_id:
		return false
	used[value] = true
	return true
