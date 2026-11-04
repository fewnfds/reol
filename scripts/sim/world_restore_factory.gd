class_name WorldRestoreFactory
extends RefCounted
## Builds a saved world without new-game issuance or a live scene baseline.
## Local motion/workplace/sparring code still has legacy disk-backed rules.


static func restore(content: ReolContentDB, saved: Dictionary, assembly: Dictionary, terrain: WorldMapData, legacy_heat_v1: bool = false) -> RegionalSimulation:
	if content == null or terrain == null or not ReolWorldAssemblyInputs.is_valid(assembly, true):
		return null
	var world := RegionalSimulation.new()
	world._content = content
	world.settings = assembly.settings.duplicate(true)
	world._opening_configs = assembly.region_configs.duplicate(true)
	# These empty shells describe expected owners/keys only. The existing strict
	# restore builds every real region/domain, validates cross-references, and then
	# publishes them. No opening inventory, knowledge, source or office is issued.
	for id: String in assembly.region_configs:
		world.regions[id] = VillageSimulation.new()
		world.local_news[id] = []
	if not world.settings.get("routes") is Dictionary:
		return null
	for id: Variant in world.settings.routes:
		var route: Variant = world.settings.routes[id]
		if not id is String or not route is Dictionary or not route.get("courier") is String:
			return null
		world.routes[id] = {}
		world.couriers[route.courier] = {}
	if saved.has("services"):
		world.services = RegionalSimulation.Services.new()
		world.services.definitions = content.settlement_services.duplicate(true)
	world.map_data = terrain
	return world if world.restore(saved, legacy_heat_v1) else null
