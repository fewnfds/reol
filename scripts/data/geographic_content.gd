class_name ReolGeographicContent
extends RefCounted
## Isolated creation adapter. The returned validated bundle contains actual
## climate curves; restoring a saved world never calls this compiler.


static func build(bundle: Variant, profile: Variant) -> ReolContentDB:
	var source := ReolContentDB.new()
	if not source.load_bundle(bundle):
		return null
	var compiled: Dictionary = SimGeographicClimate.compile(source.climate, profile)
	if compiled.is_empty():
		return null
	var documents: Dictionary = source.content_bundle().documents.duplicate(true)
	documents["res://data/definitions/climate.json"] = compiled
	var candidate := ReolContentDB.new()
	return candidate if candidate.load_bundle(ReolContentBundle.from_documents(documents)) else null
