class_name ReolContentDB
extends RefCounted
## Loads and validates data packs under `res://data/`.
##
## JSON is used instead of hand-written .tres so new pawns/ranks/origins are a
## data-only change. `load_all()` returns false and fills `errors` on bad data.

const RANKS_PATH: String = "res://data/ranks.json"
const ORIGINS_PATH: String = "res://data/origins.json"
const PAWNS_PATH: String = "res://data/pawns.json"

var origins: Dictionary[StringName, OriginDef] = {}
var ranks: Dictionary[StringName, RankDef] = {}
var pawns: Dictionary[StringName, PawnDef] = {}
var errors: Array[String] = []


func load_all() -> bool:
	origins.clear()
	ranks.clear()
	pawns.clear()
	errors.clear()

	_load_ranks()
	_load_origins()
	_load_pawns()
	return errors.is_empty()


func get_origin(id: StringName) -> OriginDef:
	return origins.get(id)


func get_rank(id: StringName) -> RankDef:
	return ranks.get(id)


func get_pawn(id: StringName) -> PawnDef:
	return pawns.get(id)


func _load_ranks() -> void:
	var data: Variant = _read_json(RANKS_PATH)
	var list: Variant = _list_field(data, "ranks", RANKS_PATH)
	if list == null:
		return

	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			_error("%s: rank entry is not an object" % RANKS_PATH)
			continue
		var row: Dictionary = entry
		var context: String = "%s: rank '%s'" % [RANKS_PATH, str(row.get("id", "?"))]
		var rank := RankDef.new()
		rank.id = StringName(_string_field(row, "id", context))
		if rank.id == &"":
			continue
		if ranks.has(rank.id):
			_error("%s: duplicate rank id '%s'" % [RANKS_PATH, rank.id])
			continue
		rank.display_name = _string_field(row, "name", context)
		rank.tier = _int_field(row, "tier", context, 0)
		rank.required_contribution = _int_field(
			row, "required_contribution", context, 0
		)
		rank.description = _string_field(row, "description", context, true)
		if rank.tier < 0:
			_error("%s: tier must be >= 0" % context)
		if rank.required_contribution < 0:
			_error("%s: required_contribution must be >= 0" % context)
		ranks[rank.id] = rank


func _load_origins() -> void:
	var data: Variant = _read_json(ORIGINS_PATH)
	var list: Variant = _list_field(data, "origins", ORIGINS_PATH)
	if list == null:
		return

	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			_error("%s: origin entry is not an object" % ORIGINS_PATH)
			continue
		var row: Dictionary = entry
		var context: String = "%s: origin '%s'" % [ORIGINS_PATH, str(row.get("id", "?"))]
		var origin := OriginDef.new()
		origin.id = StringName(_string_field(row, "id", context))
		if origin.id == &"":
			continue
		if origins.has(origin.id):
			_error("%s: duplicate origin id '%s'" % [ORIGINS_PATH, origin.id])
			continue
		origin.display_name = _string_field(row, "name", context)
		origin.description = _string_field(row, "description", context, true)
		origin.starting_rank_id = StringName(
			_string_field(row, "starting_rank", context)
		)
		origin.starting_contribution = _int_field(
			row, "starting_contribution", context, 0
		)
		if origin.starting_contribution < 0:
			_error("%s: starting_contribution must be >= 0" % context)
		if not ranks.has(origin.starting_rank_id):
			_error(
				"%s: unknown starting_rank '%s'"
				% [context, origin.starting_rank_id]
			)
		origins[origin.id] = origin


func _load_pawns() -> void:
	var data: Variant = _read_json(PAWNS_PATH)
	var list: Variant = _list_field(data, "pawns", PAWNS_PATH)
	if list == null:
		return

	for entry: Variant in list:
		if typeof(entry) != TYPE_DICTIONARY:
			_error("%s: pawn entry is not an object" % PAWNS_PATH)
			continue
		var row: Dictionary = entry
		var context: String = "%s: pawn '%s'" % [PAWNS_PATH, str(row.get("id", "?"))]
		var pawn := PawnDef.new()
		pawn.id = StringName(_string_field(row, "id", context))
		if pawn.id == &"":
			continue
		if pawns.has(pawn.id):
			_error("%s: duplicate pawn id '%s'" % [PAWNS_PATH, pawn.id])
			continue
		pawn.display_name = _string_field(row, "name", context)
		pawn.origin_id = StringName(_string_field(row, "origin", context))
		pawn.rank_id = StringName(_string_field(row, "rank", context))
		pawn.role = _string_field(row, "role", context)
		pawn.realm = _int_field(row, "realm", context, 0)
		pawn.max_qi = _int_field(row, "max_qi", context, 10)
		pawn.max_stamina = _int_field(row, "max_stamina", context, 100)
		pawn.bio = _string_field(row, "bio", context, true)

		if not origins.has(pawn.origin_id):
			_error("%s: unknown origin '%s'" % [context, pawn.origin_id])
		if not ranks.has(pawn.rank_id):
			_error("%s: unknown rank '%s'" % [context, pawn.rank_id])
		if pawn.realm < 0:
			_error("%s: realm must be >= 0" % context)
		if pawn.max_qi <= 0:
			_error("%s: max_qi must be > 0" % context)
		if pawn.max_stamina <= 0:
			_error("%s: max_stamina must be > 0" % context)

		var color_text: String = _string_field(row, "color", context, true)
		if Color.html_is_valid(color_text):
			pawn.color = Color.from_string(color_text, Color.WHITE)
		else:
			_error("%s: invalid color '%s'" % [context, color_text])
		pawns[pawn.id] = pawn


func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_error("missing data file: %s" % path)
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	var result: int = json.parse(text)
	if result != OK:
		_error(
			"%s:%d: %s"
			% [path, json.get_error_line(), json.get_error_message()]
		)
		return null
	return json.data


func _list_field(data: Variant, key: String, path: String) -> Variant:
	if typeof(data) != TYPE_DICTIONARY:
		_error("%s: root must be an object" % path)
		return null
	var value: Variant = (data as Dictionary).get(key)
	if typeof(value) != TYPE_ARRAY:
		_error("%s: missing array '%s'" % [path, key])
		return null
	return value


func _string_field(
	row: Dictionary, key: String, context: String, allow_empty: bool = false
) -> String:
	var value: Variant = row.get(key)
	if typeof(value) != TYPE_STRING:
		_error("%s: missing string field '%s'" % [context, key])
		return ""
	var text: String = (value as String).strip_edges()
	if text.is_empty() and not allow_empty:
		_error("%s: empty string field '%s'" % [context, key])
	return text


func _int_field(
	row: Dictionary, key: String, context: String, fallback: int
) -> int:
	var value: Variant = row.get(key, fallback)
	if typeof(value) != TYPE_INT and typeof(value) != TYPE_FLOAT:
		_error("%s: field '%s' must be a number" % [context, key])
		return fallback
	return int(value)


func _error(message: String) -> void:
	errors.append(message)
