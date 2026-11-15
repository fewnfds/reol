extends RefCounted
## Numerical projection of a finite bundle, independent of action names.
const Effect = preload("res://scripts/sim/definitions/actions/effect_def.gd")
static func summary(bundle: Array, stage: String = "contact") -> Dictionary:
	var result: Dictionary = {"damage": 0.0, "stun": 0, "push": 0.0, "punish_ms": 0, "heavy_hit": false}
	for spec: Dictionary in bundle:
		if spec.get("stage", "contact") != stage: continue
		if spec.kind == "damage": result.damage += float(spec.magnitude)
		elif spec.kind == "control":
			result.stun = int(spec.duration_ms)
			result.push = float(spec.push)
			result.punish_ms = int(spec.punish_ms)
	result.heavy_hit = int(result.punish_ms) > 0
	return result

static func valid(bundle: Variant, required_stage: String = "") -> bool:
	if not bundle is Array or bundle.size() > 16: return false
	for spec: Variant in bundle:
		if not spec is Dictionary or not Effect.valid_values(spec, required_stage): return false
	return true
