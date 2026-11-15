extends RefCounted
## Pure bounded selection. Observations are detached values, not a World facade.
## A trusted project strategy can replace this evaluator using the same contract.

static func choose(observation: Dictionary, policy: Dictionary, ready: Dictionary, rule_due: Dictionary, now: int) -> Dictionary:
	var distance: float = observation.distance
	for index: int in policy.rules.size():
		if now < int(rule_due.get(index, 0)): continue
		var rule: Dictionary = policy.rules[index]
		var passes: bool = false
		match rule.condition:
			"always": passes = true
			"near": passes = distance < float(rule.threshold)
			"far": passes = distance > float(rule.threshold)
			"hurt": passes = float(observation.health) < float(rule.threshold)
			"recent_hit": passes = observation.hit_ms >= 0 and now - int(observation.hit_ms) < int(float(rule.threshold) * 1000)
		if not passes: continue
		if rule.action in ["cast", "sequence"]:
			if not observation.visible or not observation.clear: continue
			var maximum: float = float(rule.max) if rule.max > 0 else float(observation.range)
			if distance < float(rule.min) or distance > maximum: continue
			var button: String = rule.button if rule.action == "cast" else str(rule.sequence[0])
			if not ready.get(button, false): continue
		return {"rule": index, "action": rule.action, "button": rule.button, "sequence": rule.sequence, "interval": rule.interval}
	return {"rule": -1, "action": "keep_range", "button": "", "sequence": [], "interval": 0}
