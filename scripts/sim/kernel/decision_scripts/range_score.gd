extends RefCounted
## Trusted stateless example: prefer a cast whose distance band fits the target.
## No World, arbitrary file loading, execution calls or mutable shared memory.
const LOGIC_VERSION: int = 1
const Rules = preload("res://scripts/sim/kernel/decision_rules.gd")

static func choose(observation: Dictionary, policy: Dictionary, ready: Dictionary, rule_due: Dictionary, now: int) -> Dictionary:
	var best: Dictionary = {}
	var score: float = -INF
	for index: int in policy.rules.size():
		var rule: Dictionary = policy.rules[index]
		if rule.action != "cast": continue
		var due: Dictionary = {0: rule_due.get(index, 0)}
		var found: Dictionary = Rules.choose(observation, {"rules": [rule]}, ready, due, now)
		if found.rule < 0: continue
		var maximum: float = rule.max if rule.max > 0 else observation.range
		var middle: float = (float(rule.min) + maximum) * 0.5
		var value: float = float(rule.weight) / (1.0 + absf(float(observation.distance) - middle))
		if value > score:
			score = value
			best = found
			best.rule = index
	return Rules.choose(observation, policy, ready, rule_due, now) if best.is_empty() else best
