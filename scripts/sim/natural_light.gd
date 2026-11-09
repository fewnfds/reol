class_name SimNaturalLight
extends RefCounted
## Instantaneous natural light from the accepted world's bound geography,
## settled time, weather and original roof facts. No light balance or clock.


static func sky(world: RegionalSimulation, cell: Vector2i) -> Dictionary:
	if world == null or world.environment == null or world.weather == null or world.map_data == null:
		return {"supported": false, "reason": "missing_world"}
	if not world.map_data.in_bounds(cell):
		return {"supported": false, "reason": "outside_map"}
	var rules: Dictionary = world.environment.definitions
	if int(rules.get("version", 0)) != 2 or not rules.get("solar") is Dictionary:
		return {"supported": false, "reason": "unsupported_geography"}
	var region: String = SimClimateRules.region_at(rules, cell)
	if not world.weather.definitions.regions.has(region):
		return {"supported": false, "reason": "missing_weather"}
	var kind: String = SimWeather.kind_at(world.weather.definitions, region, world.weather.epoch_ms, world.elapsed_ms)
	var result: Dictionary = SimSolarRules.sample(rules.calendar, rules.solar, world.elapsed_ms, kind)
	if result.is_empty():
		return {"supported": false, "reason": "invalid_solar_input"}
	result["supported"] = true
	result["region"] = region
	return result


static func at_cell(world: RegionalSimulation, cell: Vector2i) -> Dictionary:
	var result: Dictionary = sky(world, cell)
	if not bool(result.supported):
		return result
	if world.construction == null:
		return {"supported": false, "reason": "missing_structure"}
	var roofed: bool = world.construction.roofed(cell)
	@warning_ignore("integer_division")
	var relative: int = int(result.total_relative) * (int(result.roof_transmission) if roofed else 10000) / 10000
	if world.plants != null:
		relative = relative * (10000 - world.plants.canopy_at(cell)) / 10000
	result["cell"] = [cell.x, cell.y]
	result["roofed"] = roofed
	result["local_relative"] = relative
	return result


static func description(light: Dictionary) -> String:
	if not bool(light.get("supported", false)):
		return "眼前天光尚难分辨。"
	var line: String
	match str(light.sky_phase):
		"dawn": line = "晨曦微明"
		"dusk": line = "暮色渐沉"
		"night": line = "夜色深沉"
		_: line = "天光明亮" if int(light.total_relative) * 4 >= int(light.relative_scale) else "日光低斜"
	if light.weather_kind == "rain" and int(light.total_relative) > 0:
		line += "，雨幕压低天光"
	if bool(light.get("roofed", false)) and int(light.total_relative) > int(light.local_relative):
		line += "，屋下更显昏暗"
	return line + "。"
