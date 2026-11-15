extends RefCounted
## Numerical projection of a finite bundle, independent of action names.
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

static func valid(bundle: Variant) -> bool:
	if not bundle is Array or bundle.size() > 16: return false
	for spec: Variant in bundle:
		if not spec is Dictionary or spec.get("stage") not in ["activation", "contact"] or spec.get("kind") not in ["damage", "control", "slow", "dot", "domain"]: return false
		if spec.kind == "domain" and spec.get("operation") != "tend": return false
		if not spec.get("id") is String or spec.id.length() > 64: return false
		for key: String in ["magnitude", "push"]:
			if not spec.get(key) is float or not is_finite(spec[key]): return false
		for key: String in ["duration_ms", "period_ms", "punish_ms"]:
			if not spec.get(key) is int or spec[key] < 0: return false
		if spec.magnitude < 0 or spec.magnitude > 20 or spec.push < 0 or spec.push > 1 or spec.duration_ms > 60000 or spec.period_ms > 10000 or spec.punish_ms > 1000: return false
		if spec.kind in ["slow", "dot"] and (spec.id.is_empty() or spec.duration_ms <= 0): return false
		if spec.kind == "slow" and (spec.magnitude <= 0 or spec.magnitude > 1): return false
		if spec.kind == "dot" and (spec.period_ms < 50 or spec.period_ms > spec.duration_ms): return false
	return true
