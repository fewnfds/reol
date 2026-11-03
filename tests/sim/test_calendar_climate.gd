extends RefCounted
## Pure date, geography and physical-exposure projections, without live worlds.

const Calendar = preload("res://scripts/sim/world_calendar.gd")
const Climate = preload("res://scripts/sim/climate_rules.gd")


func run(runner: Object) -> void:
	var rules: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/definitions/climate.json"))
	runner.assert_true(Climate.valid_definitions(rules), "finite outdoor climate definitions validate")
	_dates(runner, rules.calendar)
	_geography(runner, rules)
	_temperatures(runner, rules)
	_clothing_and_burden(runner, rules)
	_bad_definitions(runner, rules)
	print("SCENARIO calendar/climate: civil-time projection, finite geographic bounds, continuous deterministic seasonal/day curves and real garment comfort margins")


func _dates(runner: Object, calendar: Dictionary) -> void:
	var opening: Dictionary = Calendar.date_at(calendar, 0)
	runner.assert_eq(opening.year, 1, "elapsed zero begins the first calendar year")
	runner.assert_eq(opening.month, 1, "elapsed zero begins the first month")
	runner.assert_eq(opening.day, 1, "elapsed zero begins the first day")
	runner.assert_eq(opening.hour, 8, "civil start offset agrees with existing 08:00 game opening")
	runner.assert_eq(opening.season, "春", "opening season is spring")
	var midnight: int = (1440 - int(calendar.start_minutes)) * Calendar.MINUTE_MS
	runner.assert_eq(Calendar.date_at(calendar, midnight - 1).day, 1, "last millisecond before midnight remains in the same day")
	var next: Dictionary = Calendar.date_at(calendar, midnight)
	runner.assert_true(next.day == 2 and next.hour == 0 and next.minute == 0, "civil midnight changes day exactly once")
	var month_end: int = int(calendar.days_per_month) * Calendar.DAY_MS - int(calendar.start_minutes) * Calendar.MINUTE_MS
	runner.assert_true(Calendar.date_at(calendar, month_end - 1).month == 1 and Calendar.date_at(calendar, month_end).month == 2, "month transition has no lost or repeated civil day")
	var summer: int = 90 * Calendar.DAY_MS - int(calendar.start_minutes) * Calendar.MINUTE_MS
	runner.assert_eq(Calendar.date_at(calendar, summer).season, "夏", "one shared elapsed timestamp crosses into summer")
	var new_year: int = Calendar.days_per_year(calendar) * Calendar.DAY_MS - int(calendar.start_minutes) * Calendar.MINUTE_MS
	runner.assert_true(Calendar.date_at(calendar, new_year - 1).year == 1 and Calendar.date_at(calendar, new_year).year == 2, "year transition is derived without a second clock")
	runner.assert_eq(Calendar.date_at(calendar, new_year).day_of_year, 0, "year rollover resets only the derived annual day")
	runner.assert_true(Calendar.format_date(calendar, new_year).contains("2年春"), "calendar formatting exposes year and season")
	runner.assert_true(Calendar.date_at(calendar, -1).is_empty(), "negative world time has no fabricated date")
	runner.assert_true(not Calendar.date_at(calendar, Calendar.MAX_TIMESTAMP).is_empty(), "largest supported timestamp derives a finite date")


func _geography(runner: Object, rules: Dictionary) -> void:
	runner.assert_eq(Climate.region_at(rules, Vector2i(256, 256)), "home", "mountain opening belongs to explicit western climate bounds")
	runner.assert_eq(Climate.region_at(rules, Vector2i(284, 256)), "river", "river opening belongs to explicit eastern climate bounds")
	runner.assert_eq(Climate.region_at(rules, Vector2i(269, 400)), "home", "west side of geographic seam uses mountain climate")
	runner.assert_eq(Climate.region_at(rules, Vector2i(270, 400)), "river", "half-open geographic seam has exactly one owner")
	runner.assert_eq(Climate.region_at(rules, Vector2i(-1, -1)), rules.fallback_region, "outside defined finite geography uses the stated fallback")
	var reordered: Dictionary = rules.duplicate(true)
	reordered.regions = {"river": rules.regions.river.duplicate(true), "home": rules.regions.home.duplicate(true)}
	runner.assert_eq(Climate.region_at(reordered, Vector2i(270, 400)), "river", "region dictionary iteration order cannot change valid geography")


func _temperatures(runner: Object, rules: Dictionary) -> void:
	var offset: int = int(rules.calendar.start_minutes) * Calendar.MINUTE_MS
	var morning: int = 300 * Calendar.MINUTE_MS - offset + Calendar.DAY_MS
	var afternoon: int = 840 * Calendar.MINUTE_MS - offset + Calendar.DAY_MS
	for region: String in rules.regions:
		var clear: int = Climate.temperature_at(rules, region, morning, "clear")
		var rain: int = Climate.temperature_at(rules, region, morning, "rain")
		runner.assert_true(Climate.temperature_at(rules, region, afternoon, "clear") > clear, "daily temperature curve warms after dawn: " + region)
		runner.assert_eq(rain - clear, int(rules.regions[region].weather_offsets.rain), "rain affects local background without inventing water: " + region)
		var summer: int = 90 * Calendar.DAY_MS + morning
		var winter: int = 270 * Calendar.DAY_MS + morning
		runner.assert_true(Climate.temperature_at(rules, region, winter, "clear") < Climate.temperature_at(rules, region, summer, "clear"), "annual curve has a real local seasonal difference: " + region)
		for day: int in [0, 90, 180, 270, 360]:
			var seam: int = day * Calendar.DAY_MS - offset
			if seam > 0:
				runner.assert_true(absi(Climate.temperature_at(rules, region, seam - 1, "clear") - Climate.temperature_at(rules, region, seam, "clear")) <= 2, "season/year boundaries remain continuous at integer precision: " + region + "/" + str(day))
		var annual: int = Calendar.days_per_year(rules.calendar) * Calendar.DAY_MS
		runner.assert_eq(Climate.temperature_at(rules, region, 123456789, "rain"), Climate.temperature_at(rules, region, 123456789 + annual, "rain"), "same annual phase is deterministic without RNG state: " + region)
		for minute: int in range(0, 3 * 1440, 17):
			var temperature: int = Climate.temperature_at(rules, region, minute * Calendar.MINUTE_MS, "rain")
			var wet_robe: int = Climate.insulation_at(rules, "plain_robe", 100)
			runner.assert_eq(Climate.burden(rules, temperature, wet_robe).energy_rate, 0, "ordinary clothed first days remain mild: " + region + "/" + str(minute))
	runner.assert_true(Climate.temperature_at(rules, "home", 0, "clear") != Climate.temperature_at(rules, "river", 0, "clear"), "two geographical regions differ at the same world time")
	var before: String = JSON.stringify(rules)
	Climate.temperature_at(rules, "home", Calendar.MAX_TIMESTAMP, "rain")
	runner.assert_eq(JSON.stringify(rules), before, "condition queries have no authority to alter original data or source quantities")


func _clothing_and_burden(runner: Object, rules: Dictionary) -> void:
	var dry: int = Climate.insulation_at(rules, "plain_robe", 0)
	var wet: int = Climate.insulation_at(rules, "plain_robe", 100)
	runner.assert_true(dry > wet and wet >= 0, "wet physical cloth loses some insulation without negative warmth")
	runner.assert_eq(Climate.insulation_at(rules, "unknown", 0), 0, "unknown garment gives no invented thermal function")
	runner.assert_eq(Climate.insulation_at(rules, "plain_robe", 150), wet, "wetness projection clamps to supported physical range")
	var cold: Dictionary = Climate.burden(rules, 80, 0)
	var protected: Dictionary = Climate.burden(rules, 80, dry)
	var damp: Dictionary = Climate.burden(rules, 80, wet)
	runner.assert_true(int(cold.energy_rate) > int(damp.energy_rate) and int(damp.energy_rate) > int(protected.energy_rate), "same cold weather distinguishes no insulation, wet cloth and dry cloth")
	runner.assert_eq(cold.cold_tenths, 100, "cold deficit has explicit tenths-degree units")
	runner.assert_eq(cold.energy_rate, 100000, "ten-degree deficit costs original fixed energy units per minute")
	runner.assert_true(int(Climate.burden(rules, 400, dry).energy_rate) > int(Climate.burden(rules, 400, 0).energy_rate), "extra insulation can worsen hot-weather body burden rather than acting as free refrigeration")
	runner.assert_eq(Climate.burden(rules, -1000, 0).energy_rate, rules.human.max_energy_rate, "prototype consequence is capped and does not silently add fatal hypothermia")
	runner.assert_eq(Climate.burden(rules, 240, 0).energy_rate, 0, "comfortable background does not add a generic season penalty")


func _bad_definitions(runner: Object, rules: Dictionary) -> void:
	var bad: Dictionary = rules.duplicate(true)
	bad.regions.river.bounds[0] = 269
	runner.assert_true(not Climate.valid_definitions(bad), "overlapping geographic climate ownership is rejected")
	bad = rules.duplicate(true)
	bad.regions.home.daily_curve[1][0] = 0
	runner.assert_true(not Climate.valid_definitions(bad), "curve timestamps must strictly advance")
	bad = rules.duplicate(true)
	bad.regions.home.seasonal_curve[-1][1] = 999
	runner.assert_true(not Climate.valid_definitions(bad), "annual curve must close rather than jumping at rollover")
	bad = rules.duplicate(true)
	bad.human.energy_rate_per_degree = -1
	runner.assert_true(not Climate.valid_definitions(bad), "cold cannot create energy through a negative exposure cost")
	bad = rules.duplicate(true)
	bad.garments.plain_robe.wet_loss_percent = 101
	runner.assert_true(not Climate.valid_definitions(bad), "wet insulation cannot lose more than its actual dry value")
	bad = rules.duplicate(true)
	bad.calendar.seasons = ["春", "春", "秋", "冬"]
	runner.assert_true(not Climate.valid_definitions(bad), "calendar season labels are unambiguous")
	bad = rules.duplicate(true)
	bad.calendar.version = true
	runner.assert_true(not Climate.valid_definitions(bad), "boolean cannot masquerade as a calendar version")
