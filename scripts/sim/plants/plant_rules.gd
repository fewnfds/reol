class_name SimPlantRules
extends RefCounted
## Species rules and integer interval arithmetic, independent of scene nodes.
const Shape = preload("res://scripts/sim/avian_schema.gd")
const WATER_UNIT: int = 60000


static func valid_definitions(raw: Variant) -> bool:
	if not Shape.keys(raw, ["version", "sample_ms", "action_ms", "types"]) or raw.version != 1 or not Shape.count(raw.sample_ms, 1000, 3600000) or not Shape.count(raw.action_ms, 1, 600000) or not raw.types is Dictionary or raw.types.is_empty():
		return false
	for id: Variant in raw.types:
		var row: Variant = raw.types[id]
		if not SimInventory._nonempty(id) or not Shape.keys(row, ["label", "life", "mature_ms", "flower_ms", "fruit_ms", "lifespan_ms", "regrow", "substrates", "temperature", "seasons", "water_min", "water_max", "light_min", "max_hp", "injury_ms", "product", "body_product", "source", "blocks", "canopy", "sapient"]):
			return false
		if not SimInventory._nonempty(row.label) or row.life not in ["annual", "perennial"] or not row.regrow is bool or not row.blocks is bool or not row.sapient is bool or not Shape.count(row.canopy, 0, 10000):
			return false
		for field: String in ["mature_ms", "flower_ms", "fruit_ms", "lifespan_ms", "max_hp", "injury_ms"]:
			if not Shape.count(row[field], 1):
				return false
		if row.flower_ms < row.mature_ms or row.fruit_ms < row.flower_ms or not Shape.count(row.water_min, 0, 100) or not Shape.count(row.water_max, int(row.water_min), 100) or not Shape.count(row.light_min, 0, 40000):
			return false
		if not SimEmbodiment._unique_texts(row.substrates) or row.substrates.is_empty() or not SimEmbodiment._unique_texts(row.seasons) or row.seasons.is_empty() or not row.temperature is Array or row.temperature.size() != 4:
			return false
		for substrate: String in row.substrates:
			if substrate not in ["soil", "sand", "stone", "water"]:
				return false
		for season: String in row.seasons:
			if season not in ["春", "夏", "秋", "冬"]:
				return false
		for temperature: Variant in row.temperature:
			if not Shape.count(temperature, -20000, 20000):
				return false
		if row.temperature[2] > row.temperature[0] or row.temperature[0] > row.temperature[1] or row.temperature[1] > row.temperature[3]:
			return false
		if not Shape.keys(row.product, ["item", "capacity", "period_ms"]) or not SimInventory._nonempty(row.product.item) or not Shape.count(row.product.capacity, 1, 1000) or not Shape.count(row.product.period_ms, 1) or not Shape.keys(row.body_product, ["item", "amount"]) or not SimInventory._nonempty(row.body_product.item) or not Shape.count(row.body_product.amount, 1, 1000):
			return false
		if not SimInventory._nonempty(row.source):
			return false
	return true


static func valid_opening(raw: Variant, definitions: Dictionary) -> bool:
	if not Shape.keys(raw, ["version", "samples", "adopt_sources"]) or raw.version != 1 or not raw.samples is Array or not raw.adopt_sources is Dictionary:
		return false
	var ids: Dictionary = {}
	for sample: Variant in raw.samples:
		if not sample is Dictionary or not SimInventory._nonempty(sample.get("id")) or ids.has(sample.id) or not sample.get("definition") is String or not definitions.types.has(sample.definition):
			return false
		for field: Variant in sample:
			if field not in ["id", "definition", "natural", "age_ms", "growth_ms"]:
				return false
		var rule: Dictionary = definitions.types[sample.definition]
		if not sample.get("natural", false) is bool or not Shape.count(sample.get("age_ms", 0)) or not Shape.count(sample.get("growth_ms", 0), 0, int(rule.fruit_ms)):
			return false
		if sample.get("growth_ms", 0) > sample.get("age_ms", 0) or rule.life == "annual" and sample.get("age_ms", 0) >= rule.lifespan_ms:
			return false
		ids[sample.id] = true
	for source: Variant in raw.adopt_sources:
		if not SimInventory._nonempty(source) or not raw.adopt_sources[source] is String or not definitions.types.has(raw.adopt_sources[source]):
			return false
	return true


static func stage(row: Dictionary, rule: Dictionary) -> String:
	if row.hp == 0:
		return "dead"
	if row.stage in ["removed", "root"]:
		return str(row.stage)
	if int(row.growth_ms) < int(rule.mature_ms):
		return "growing"
	if int(row.growth_ms) < int(rule.flower_ms):
		return "mature"
	return "flowering" if int(row.growth_ms) < int(rule.fruit_ms) else "fruiting"


static func growing(row: Dictionary, rule: Dictionary, conditions: Dictionary, water: int) -> bool:
	return row.hp > 0 and row.stage != "removed" and water >= int(rule.water_min) * WATER_UNIT and water <= int(rule.water_max) * WATER_UNIT and int(conditions.temperature) >= int(rule.temperature[0]) and int(conditions.temperature) <= int(rule.temperature[1]) and rule.seasons.has(conditions.season) and int(conditions.light) >= int(rule.light_min) and rule.substrates.has(conditions.substrate)
