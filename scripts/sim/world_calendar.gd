class_name SimWorldCalendar
extends RefCounted
## A calendar projection of the original integer timeline. This owns no clock.

const MINUTE_MS: int = 60000
const DAY_MINUTES: int = 1440
const DAY_MS: int = DAY_MINUTES * MINUTE_MS
const MAX_TIMESTAMP: int = 9007199254740991


static func valid_definitions(data: Variant) -> bool:
	if not _keys(data, ["version", "days_per_month", "months_per_year", "seasons", "start_minutes"]) or not _integer(data.version, 1, 1):
		return false
	if not _integer(data.days_per_month, 1, 366) or not _integer(data.months_per_year, 1, 24) or not _integer(data.start_minutes, 0, DAY_MINUTES - 1):
		return false
	if not data.seasons is Array or data.seasons.is_empty() or data.seasons.size() > int(data.months_per_year) or int(data.months_per_year) % data.seasons.size() != 0:
		return false
	var found: Dictionary = {}
	for season: Variant in data.seasons:
		if not season is String or season.strip_edges().is_empty() or found.has(season):
			return false
		found[season] = true
	return true


@warning_ignore("integer_division")
static func date_at(rules: Dictionary, at_ms: int) -> Dictionary:
	if not valid_definitions(rules) or at_ms < 0 or at_ms > MAX_TIMESTAMP:
		return {}
	var minutes: int = at_ms / MINUTE_MS + int(rules.start_minutes)
	var day_index: int = minutes / DAY_MINUTES
	var year_days: int = days_per_year(rules)
	var day_of_year: int = posmod(day_index, year_days)
	var season_index: int = day_of_year / (year_days / rules.seasons.size())
	return {"year": day_index / year_days + 1, "month": day_of_year / int(rules.days_per_month) + 1,
		"day": day_of_year % int(rules.days_per_month) + 1, "day_index": day_index,
		"day_of_year": day_of_year, "season": str(rules.seasons[season_index]), "season_index": season_index,
		"hour": (minutes / 60) % 24, "minute": minutes % 60}


static func days_per_year(rules: Dictionary) -> int:
	return int(rules.days_per_month) * int(rules.months_per_year)


static func format_date(rules: Dictionary, at_ms: int) -> String:
	var date: Dictionary = date_at(rules, at_ms)
	if date.is_empty():
		return "时令不明"
	return "%d年%s · %02d月%02d日 %02d:%02d" % [int(date.year), str(date.season), int(date.month), int(date.day), int(date.hour), int(date.minute)]


static func _keys(data: Variant, expected: Array) -> bool:
	if not data is Dictionary or data.size() != expected.size():
		return false
	for key: Variant in expected:
		if not data.has(key):
			return false
	return true


static func _integer(value: Variant, minimum: int, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == int(value) and value >= minimum and value <= maximum
