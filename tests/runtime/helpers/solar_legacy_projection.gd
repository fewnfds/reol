extends RefCounted
## Test-only projection of the explicit root49-to-root50 solar addition.
## No historical samples or other climate values are discarded.

const CLIMATE_PATH: String = "res://data/definitions/climate.json"
const IMPORT_SOLAR: Dictionary = {
	"latitude_mdeg": 30000, "longitude_mdeg": 0,
	"meridian_mdeg": 0, "axial_tilt_mdeg": 23500,
	"vernal_day": 0, "relative_scale": 10000,
	"clear_transmission": 10000, "rain_transmission": 4500,
	"roof_transmission": 1000
}


static func prior_climate(snapshot: Dictionary) -> Dictionary:
	var bundle: Variant = snapshot.get("content_bundle")
	if not bundle is Dictionary or not bundle.get("documents") is Dictionary:
		return {}
	var climate: Variant = bundle.documents.get(CLIMATE_PATH)
	if not climate is Dictionary or climate.get("version") != 2 or SnapshotValues.normalized(climate.get("solar")) != SnapshotValues.normalized(IMPORT_SOLAR):
		return {}
	var result: Dictionary = climate.duplicate(true)
	result.erase("solar")
	result.version = 1
	return result


static func prior_environment(current: Dictionary, prior: Dictionary, snapshot: Dictionary) -> Dictionary:
	# The sampled environmental shape is still v3; only its bound definition
	# version changes. Callers project older shape revisions separately.
	if current.get("version") != 3 or current.get("rules_version") != 2 or not SnapshotValues.valid_integer(prior.get("version"), 1) or int(prior.version) > 3 or prior.get("rules_version") != 1 or prior_climate(snapshot).is_empty():
		return {}
	var result: Dictionary = current.duplicate(true)
	result.rules_version = 1
	return result
