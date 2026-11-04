class_name ReolContentDB
extends RefCounted
## Loads and validates data packs under `res://data/`.
##
## JSON is used instead of hand-written .tres so new pawns/ranks/origins are a
## data-only change. `load_all()` returns false and fills `errors` on bad data.

const RANKS_PATH: String = "res://data/definitions/ranks.json"
const ORIGINS_PATH: String = "res://data/definitions/origins.json"
const PAWNS_PATH: String = "res://data/definitions/pawns.json"
const INFORMATION_POLICY_PATH: String = "res://data/definitions/stock_information_policy.json"
const BODY_FORMS_PATH: String = "res://data/definitions/body_forms.json"
const ARTIFACTS_PATH: String = "res://data/definitions/artifacts.json"
const AVIAN_LIFE_PATH: String = "res://data/definitions/avian_life.json"
const LAND_RESOURCES_PATH: String = "res://data/definitions/land_resources.json"
const SOUL_VESSELS_PATH: String = "res://data/definitions/soul_vessels.json"
const SOCIAL_ADMISSION_PATH: String = "res://data/definitions/social_admission.json"
const INTERACTION_REQUESTS_PATH: String = "res://data/definitions/interaction_requests.json"
const HEAT_METHODS_PATH: String = "res://data/definitions/heat_methods.json"
const CONSTRUCTION_PATH: String = "res://data/definitions/construction.json"
const RESTING_PATH: String = "res://data/definitions/resting.json"
const WEATHER_PATH: String = "res://data/definitions/weather.json"
const SERVICES_PATH: String = "res://data/definitions/settlement_services.json"
const PERSONAL_FORAGING_PATH: String = "res://data/definitions/personal_foraging.json"

# Format-v1 manifest. Adding a future document requires a new bundle version and
# an explicit migration; never silently enlarge the required v1 path set.
const DOCUMENT_PATHS: Array[String] = [
	"res://data/definitions/artifacts.json",
	"res://data/definitions/autonomous_livelihood.json",
	"res://data/definitions/avian_life.json",
	"res://data/definitions/body_forms.json",
	"res://data/definitions/budgeted_labor.json",
	"res://data/definitions/capability_conversation.json",
	"res://data/definitions/capability_network.json",
	"res://data/definitions/capability_practice.json",
	"res://data/definitions/climate.json",
	"res://data/definitions/clothing.json",
	"res://data/definitions/conflicts.json",
	"res://data/definitions/construction.json",
	"res://data/definitions/field_opportunities.json",
	"res://data/definitions/health.json",
	"res://data/definitions/heat_methods.json",
	"res://data/definitions/interaction_requests.json",
	"res://data/definitions/land_resources.json",
	"res://data/definitions/large_bodies.json",
	"res://data/definitions/local_heat.json",
	"res://data/definitions/method_records.json",
	"res://data/definitions/natural_environment.json",
	"res://data/definitions/origins.json",
	"res://data/definitions/pawns.json",
	"res://data/definitions/personal_foraging.json",
	"res://data/definitions/personal_production.json",
	"res://data/definitions/private_exchange.json",
	"res://data/definitions/ranks.json",
	"res://data/definitions/resting.json",
	"res://data/definitions/settlement_services.json",
	"res://data/definitions/site_affairs.json",
	"res://data/definitions/social_admission.json",
	"res://data/definitions/soul_vessels.json",
	"res://data/definitions/source_care.json",
	"res://data/definitions/spirit_sources.json",
	"res://data/definitions/standing_work.json",
	"res://data/definitions/stock_information_policy.json",
	"res://data/definitions/weather.json",
]

var origins: Dictionary[StringName, OriginDef] = {}
var ranks: Dictionary[StringName, RankDef] = {}
var pawns: Dictionary[StringName, PawnDef] = {}
var errors: Array[String] = []
var stock_information_policy: Dictionary = {}
var body_forms: Dictionary = {}
var artifacts: Dictionary = {}
var avian_life: Dictionary = {}
var land_resources: Dictionary = {}
var soul_vessels: Dictionary = {}
var social_admission: Dictionary = {}
var interaction_requests: Dictionary = {}
var heat_methods: Dictionary = {}
var construction: Dictionary = {}
var resting: Dictionary = {}
var weather: Dictionary = {}
var local_trade: Dictionary = {}
var settlement_services: Dictionary = {}
var personal_foraging: Dictionary = {}
var entrusted_returns: Dictionary = {}
var standing_work: Dictionary = {}
var method_records: Dictionary = {}
var large_bodies: Dictionary = {}
var personal_production: Dictionary = {}
var budgeted_labor: Dictionary = {}
var capability_conversation: Dictionary = {}
var autonomous_livelihood: Dictionary = {}
var clothing: Dictionary = {}
var health: Dictionary = {}
var climate: Dictionary = {}
var local_heat: Dictionary = {}
var spirit_sources: Dictionary = {}
var natural_environment: Dictionary = {}
var conflicts: Dictionary = {}
var site_affairs: Dictionary = {}
var source_care: Dictionary = {}
var capability_practice: Dictionary = {}
var capability_network: Dictionary = {}
var field_opportunities: Dictionary = {}
var private_exchange: Dictionary = {}


var _documents: Dictionary = {}
var _legacy_heat_input: bool = false
var _legacy_heat_v2_input: bool = false
var _legacy_climate_input: bool = false
var _bundle: Dictionary = {}
var _loaded: bool = false


func load_all() -> bool:
	# A live session must never be reloaded in place. Build a fresh candidate DB.
	if _loaded:
		errors.assign(["ContentDB is already loaded; create an independent candidate"])
		return false
	errors.clear()
	var documents: Dictionary = {}
	for path: String in DOCUMENT_PATHS:
		var value: Variant = _read_file(path)
		if value == null:
			return false
		documents[path] = value
	return load_bundle(ReolContentBundle.from_documents(documents))


func load_bundle(bundle: Variant, legacy_heat_input: bool = false, legacy_heat_v2_input: bool = false, legacy_climate_input: bool = false) -> bool:
	if _loaded:
		errors.assign(["ContentDB is already loaded; create an independent candidate"])
		return false
	errors.clear()
	if legacy_heat_input and legacy_heat_v2_input:
		errors.append("Only one explicit historical heat definition format may be bound")
		return false
	if not ReolContentBundle.is_valid(bundle, DOCUMENT_PATHS):
		errors.append("Invalid or incomplete content bundle")
		return false
	_documents = bundle.documents.duplicate(true)
	_legacy_heat_input = legacy_heat_input
	_legacy_heat_v2_input = legacy_heat_v2_input
	# Both historical thermal formats predate the solar climate contract.
	# The v1 climate may otherwise be bound only by the explicit solar importer.
	_legacy_climate_input = legacy_climate_input or legacy_heat_input or legacy_heat_v2_input
	_loaded = _load_definitions()
	if not _loaded:
		_documents.clear()
	else:
		_bundle = bundle.duplicate(true)
	return _loaded


func content_bundle() -> Dictionary:
	return _bundle.duplicate(true)


static func legacy_v42() -> ReolContentDB:
	# Historical saves did not record their definitions. Bind them to the explicit
	# last v42 repository baseline, never to templates edited after that baseline.
	var path: String = "res://data/compatibility/content_db_v42.json"
	var source: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not source is Dictionary or source.get("version") != 1 or not source.get("documents") is Dictionary:
		return null
	var content := ReolContentDB.new()
	return content if content.load_bundle(ReolContentBundle.from_documents(source.documents), true) else null


func _load_definitions() -> bool:
	origins.clear()
	ranks.clear()
	pawns.clear()
	errors.clear()
	stock_information_policy = {}
	body_forms = {}
	artifacts = {}
	avian_life = {}
	land_resources = {}
	soul_vessels = {}
	social_admission = {}
	interaction_requests = {}
	heat_methods = {}
	construction = {}
	resting = {}
	weather = {}
	local_trade = {}
	settlement_services = {}
	personal_foraging = {}
	entrusted_returns = {}
	standing_work = {}
	method_records = {}
	large_bodies = {}
	personal_production = {}
	budgeted_labor = {}
	capability_conversation = {}
	autonomous_livelihood = {}
	clothing = {}
	health = {}
	climate = {}
	local_heat = {}
	spirit_sources = {}
	natural_environment = {}
	conflicts = {}
	site_affairs = {}
	var site_rules: Variant = _read_json("res://data/definitions/site_affairs.json")
	if SimSiteAffairs.valid_definitions(site_rules):
		site_affairs = site_rules.duplicate(true)
	else:
		_error("site_affairs.json: invalid bounded source-loan rules")
	source_care = {}
	capability_practice = {}
	capability_network = {}
	field_opportunities = {}
	private_exchange = {}
	var exchange_rules: Variant = _read_json("res://data/definitions/private_exchange.json")
	if exchange_rules is Dictionary and SimPrivateExchange.valid_definitions(exchange_rules):
		private_exchange = exchange_rules.duplicate(true)
	else:
		_error("private_exchange.json: invalid bounded private exchange rules")
	var field_rules: Variant = _read_json("res://data/definitions/field_opportunities.json")
	if field_rules is Dictionary and SimFieldOpportunities.valid_definitions(field_rules):
		field_opportunities = field_rules.duplicate(true)
	else:
		_error("field_opportunities.json: invalid bounded field-site rules")
	var practice_rules: Variant = _read_json("res://data/definitions/capability_practice.json")
	if practice_rules is Dictionary and SimCapabilityPractice.valid_definitions(practice_rules):
		capability_practice = practice_rules.duplicate(true)
	else:
		_error("capability_practice.json: invalid bounded practice rules")
	var network_rules: Variant = _read_json("res://data/definitions/capability_network.json")
	if SimCapabilityQueries.valid_definitions(network_rules):
		capability_network = network_rules.duplicate(true)
	else:
		_error("capability_network.json: invalid sourced capability projection")
	var care_rules: Variant = _read_json("res://data/definitions/source_care.json")
	if care_rules is Dictionary and SimSourceCare.valid_definitions(care_rules):
		source_care = care_rules.duplicate(true)
	else:
		_error("source_care.json: invalid bounded source-care rules")
	var combat_rules: Variant = _read_json("res://data/definitions/conflicts.json")
	if SimConflicts.valid_rules(combat_rules):
		conflicts = combat_rules.duplicate(true)
	else:
		_error("conflicts.json: invalid embodied technique and conflict rules")
	var natural_rules: Variant = _read_json("res://data/definitions/natural_environment.json")
	if NaturalEnvironment.valid_definitions(natural_rules):
		natural_environment = natural_rules.duplicate(true)
	else:
		_error("natural_environment.json: invalid substrate, flora and five-phase definitions")
	var source_rules: Variant = _read_json("res://data/definitions/spirit_sources.json")
	if SimSpiritSources.valid_definitions(source_rules):
		spirit_sources = source_rules.duplicate(true)
	else:
		_error("spirit_sources.json: invalid finite spiritual source rules")

	var heat_rules: Variant = _read_json("res://data/definitions/local_heat.json")
	var valid_heat: bool = SimLocalHeat.valid_definitions(heat_rules)
	if _legacy_heat_input:
		valid_heat = LegacyHeatV1.valid_definitions(heat_rules)
	elif _legacy_heat_v2_input:
		valid_heat = load("res://scripts/persistence/legacy_heat_v2.gd").valid_definitions(heat_rules)
	if valid_heat:
		local_heat = heat_rules.duplicate(true)
	else:
		_error("local_heat.json: invalid finite local heat rules")
	var environment_rules: Variant = _read_json("res://data/definitions/climate.json")
	var valid_climate: bool = SimClimateRules.valid_legacy_definitions(environment_rules) if _legacy_climate_input else SimClimateRules.valid_definitions(environment_rules)
	if valid_climate:
		climate = environment_rules.duplicate(true)
	else:
		_error("climate.json: invalid calendar/local temperature rules")
	var medicine: Variant = _read_json("res://data/definitions/health.json")
	if SimHealth.valid_definitions(medicine):
		health = medicine.duplicate(true)
	else:
		_error("health.json: invalid specific bodily consequence rules")
	var garments: Variant = _read_json("res://data/definitions/clothing.json")
	if SimClothing.valid_definitions(garments):
		clothing = garments.duplicate(true)
	else:
		_error("clothing.json: invalid physical garment rules")
	_load_ranks()
	_load_origins()
	_load_pawns()
	var livelihood: Variant = _read_json("res://data/definitions/autonomous_livelihood.json")
	if SimAutonomousLivelihood.valid_definitions(livelihood):
		autonomous_livelihood = livelihood.duplicate(true)
	else:
		_error("autonomous_livelihood.json: invalid personal livelihood rules")
	var conversation: Variant = _read_json("res://data/definitions/capability_conversation.json")
	if SimCapabilityConversation.valid_definitions(conversation):
		capability_conversation = conversation.duplicate(true)
	else:
		_error("capability_conversation.json: invalid attributed conversation rules")
	var labor: Variant = _read_json("res://data/definitions/budgeted_labor.json")
	if SimBudgetedLabor.valid_definitions(labor):
		budgeted_labor = labor.duplicate(true)
	else:
		_error("budgeted_labor.json: invalid funded labor rules")
	var production: Variant = _read_json("res://data/definitions/personal_production.json")
	if SimPersonalProduction.valid_definitions(production):
		personal_production = production.duplicate(true)
	else:
		_error("personal_production.json: invalid batch production rules")
	var large: Variant = _read_json("res://data/definitions/large_bodies.json")
	if SimLargeBodies.valid_definitions(large):
		large_bodies = large.duplicate(true)
	else:
		_error("large_bodies.json: invalid large body rules")
	var records: Variant = _read_json("res://data/definitions/method_records.json")
	if SimMethodRecords.valid_definitions(records):
		method_records = records.duplicate(true)
	else:
		_error("method_records.json: invalid physical method record rules")
	var foraging: Variant = _read_json(PERSONAL_FORAGING_PATH)
	if SimPersonalForaging.valid_definitions(foraging):
		personal_foraging = foraging.duplicate(true)
	else:
		_error("%s: invalid personal foraging definitions" % PERSONAL_FORAGING_PATH)
	var service_rules: Variant = _read_json(SERVICES_PATH)
	var standing: Variant = _read_json("res://data/definitions/standing_work.json")
	if SimStandingWork.valid_definitions(standing):
		standing_work = standing.duplicate(true)
	else:
		_error("standing_work.json: invalid cooperative work plans")
	if service_rules is Dictionary and preload("res://scripts/sim/services/local_trade.gd").valid_definitions(service_rules.get("trade")):
		settlement_services = service_rules.duplicate(true)
		local_trade = service_rules.trade.duplicate(true)
		if service_rules.get("returns") is Dictionary:
			entrusted_returns = service_rules.returns.duplicate(true)
	else:
		_error("%s: invalid local trade policy" % SERVICES_PATH)
	var information: Variant = _read_json(INFORMATION_POLICY_PATH)
	if SimStockInformation.valid_policy(information):
		stock_information_policy = information.duplicate(true)
	else:
		_error("%s: invalid stock information policy" % INFORMATION_POLICY_PATH)
	var forms: Variant = _read_json(BODY_FORMS_PATH)
	if SimEmbodiment.valid_forms(forms):
		body_forms = forms.duplicate(true)
	else:
		_error("%s: invalid body forms" % BODY_FORMS_PATH)
	var objects: Variant = _read_json(ARTIFACTS_PATH)
	var valid_objects: bool = SimArtifacts.valid_definitions(objects)
	if valid_objects and (_legacy_heat_input or _legacy_heat_v2_input):
		for definition: Dictionary in objects.types.values():
			if SimArtifacts.type_has_capability(definition, "thermal_exchange"):
				valid_objects = false
				break
	if valid_objects:
		artifacts = objects.duplicate(true)
	else:
		_error("%s: invalid artifacts" % ARTIFACTS_PATH)
	var avians: Variant = _read_json(AVIAN_LIFE_PATH)
	if SimAvianLife.valid_definitions(avians):
		avian_life = avians.duplicate(true)
	else:
		_error("%s: invalid avian life" % AVIAN_LIFE_PATH)
	var land: Variant = _read_json(LAND_RESOURCES_PATH)
	if SimLandResources.valid_definitions(land):
		land_resources = land.duplicate(true)
	else:
		_error("%s: invalid land resources" % LAND_RESOURCES_PATH)
	var souls: Variant = _read_json(SOUL_VESSELS_PATH)
	if SimSoulVessels.valid_definitions(souls):
		soul_vessels = souls.duplicate(true)
	else:
		_error("%s: invalid soul vessels" % SOUL_VESSELS_PATH)
	var admissions: Variant = _read_json(SOCIAL_ADMISSION_PATH)
	if SimSocialAdmission.valid_definitions(admissions):
		social_admission = admissions.duplicate(true)
	else:
		_error("%s: invalid social admission rules" % SOCIAL_ADMISSION_PATH)
	var requests: Variant = _read_json(INTERACTION_REQUESTS_PATH)
	if SimInteractionRequests.valid_definitions(requests):
		interaction_requests = requests.duplicate(true)
	else:
		_error("%s: invalid interaction request rules" % INTERACTION_REQUESTS_PATH)
	var methods: Variant = _read_json(HEAT_METHODS_PATH)
	if SimHeatMethods.valid_definitions(methods):
		heat_methods = methods.duplicate(true)
	else:
		_error("%s: invalid heat method rules" % HEAT_METHODS_PATH)
	var building: Variant = _read_json(CONSTRUCTION_PATH)
	if SimConstruction.valid_definitions(building):
		construction = building.duplicate(true)
	else:
		_error("%s: invalid construction rules" % CONSTRUCTION_PATH)
	var beds: Variant = _read_json(RESTING_PATH)
	if SimResting.valid_definitions(beds):
		resting = beds.duplicate(true)
	else:
		_error("%s: invalid resting rules" % RESTING_PATH)
	var weather_rules: Variant = _read_json(WEATHER_PATH)
	if SimWeather.valid_definitions(weather_rules):
		weather = weather_rules.duplicate(true)
	else:
		_error("%s: invalid weather rules" % WEATHER_PATH)
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
	# No filesystem fallback: injected packs must be complete and self contained.
	return _documents.get(path)


func _read_file(path: String) -> Variant:
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
