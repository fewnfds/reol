class_name SuccessionResolver
extends RefCounted
## Pure succession resolver. No scene tree, no clock, no randomness.
##
## Stage A ranks office candidates and produces the winner's legitimacy.
## Stage B scores five ways of treating each old claim:
## honor / discount / freeze / bargain / repudiate.
##
## All factors are normalized to 0..1 by the caller. Weights live here as
## replaceable defaults; a data-driven policy can override them later.
## Callers must pass what the successor believes/perceives, not omniscient truth.
## The resolver returns reason tags so the UI can explain the outcome in words.

const ACTIONS: Array[StringName] = [
	&"honor",
	&"discount",
	&"freeze",
	&"bargain",
	&"repudiate",
]

const CANDIDATE_WEIGHTS: Dictionary = {
	&"mandate": 0.25,
	&"backing": 0.20,
	&"power": 0.18,
	&"control": 0.14,
	&"standing": 0.08,
	&"purse": 0.06,
	&"predecessor": 0.05,
	&"outside": 0.04,
}

const CLAIM_WEIGHTS: Dictionary = {
	&"honor": {
		&"validity": 0.32,
		&"burden": -0.30,
		&"continuity": 0.18,
		&"affinity": 0.08,
		&"bond": 0.08,
		&"leverage": -0.08,
		&"visibility": 0.06,
		&"precedent": -0.10,
		&"need": 0.05,
		&"old_regime": -0.10,
		&"insecurity": -0.08,
		&"legitimacy": 0.10,
	},
	&"discount": {
		&"validity": 0.22,
		&"burden": 0.12,
		&"continuity": 0.10,
		&"affinity": 0.04,
		&"bond": 0.03,
		&"leverage": -0.03,
		&"visibility": -0.03,
		&"precedent": -0.04,
		&"need": 0.02,
		&"old_regime": -0.10,
		&"insecurity": -0.04,
		&"legitimacy": 0.02,
	},
	&"freeze": {
		&"validity": 0.03,
		&"burden": 0.18,
		&"continuity": -0.06,
		&"affinity": -0.05,
		&"bond": -0.04,
		&"leverage": -0.10,
		&"visibility": -0.04,
		&"precedent": -0.05,
		&"need": 0.04,
		&"old_regime": 0.14,
		&"insecurity": 0.18,
		&"legitimacy": -0.06,
	},
	&"bargain": {
		&"validity": 0.14,
		&"burden": -0.06,
		&"continuity": 0.08,
		&"affinity": 0.06,
		&"bond": 0.04,
		&"leverage": 0.16,
		&"visibility": 0.03,
		&"precedent": 0.00,
		&"need": 0.12,
		&"old_regime": -0.02,
		&"insecurity": 0.04,
		&"legitimacy": 0.04,
	},
	&"repudiate": {
		&"validity": -0.40,
		&"burden": 0.30,
		&"continuity": -0.20,
		&"affinity": -0.10,
		&"bond": -0.09,
		&"leverage": -0.24,
		&"visibility": -0.16,
		&"precedent": 0.08,
		&"need": -0.10,
		&"old_regime": 0.08,
		&"insecurity": -0.10,
		&"legitimacy": 0.12,
	},
}

const TRAIT_BIAS: Dictionary = {
	&"honorable": {&"honor": 0.10, &"repudiate": -0.10},
	&"paranoid": {&"freeze": 0.08, &"repudiate": 0.05, &"honor": -0.04},
	&"pragmatic": {&"bargain": 0.08, &"discount": 0.04},
	&"greedy": {&"repudiate": 0.06, &"honor": -0.05},
	&"populist": {&"honor": 0.05, &"repudiate": -0.08},
	&"vindictive": {&"repudiate": 0.08, &"freeze": 0.02},
	&"weak": {&"freeze": 0.08, &"repudiate": -0.12},
	&"decisive": {&"repudiate": 0.04, &"freeze": -0.04},
}

const CLAIM_FACTOR_KEYS: Array[StringName] = [
	&"validity",
	&"burden",
	&"continuity",
	&"affinity",
	&"bond",
	&"leverage",
	&"visibility",
	&"precedent",
	&"need",
	&"old_regime",
	&"insecurity",
	&"legitimacy",
]

const CONTEST_MARGIN: float = 0.15
const TIE_MARGIN: float = 0.02
const EVIDENCE_GATE: float = 0.20
const RESERVE_GATE: float = 0.90
const RETALIATION_GATE: float = 0.75
const PUBLIC_GATE: float = 0.60
const WEAK_MANDATE_GATE: float = 0.65
const VISIBILITY_GATE: float = 0.70

## Mutable copies so a data-driven policy can override individual weights.
var candidate_weights: Dictionary = CANDIDATE_WEIGHTS.duplicate(true)
var claim_weights: Dictionary = CLAIM_WEIGHTS.duplicate(true)
var trait_bias: Dictionary = TRAIT_BIAS.duplicate(true)


## Override selected weights without replacing the whole table.
## Expected shape:
##   {"candidate_weights": {factor: float},
##    "claim_weights": {action: {factor: float}},
##    "trait_bias": {trait: {action: float}}}
func apply_policy(policy: Dictionary) -> void:
	if policy.has("candidate_weights"):
		_merge_weights(candidate_weights, policy["candidate_weights"])
	if policy.has("claim_weights"):
		_merge_weights(claim_weights, policy["claim_weights"])
	if policy.has("trait_bias"):
		_merge_weights(trait_bias, policy["trait_bias"])


class Candidate:
	var id: StringName = &""
	var factors: Dictionary = {}
	var traits: Array[StringName] = []
	var eligible: bool = true
	var ineligible_reason: String = ""

	func _init(
		p_id: StringName = &"",
		p_factors: Dictionary = {},
		p_traits: Array[StringName] = []
	) -> void:
		id = p_id
		factors = p_factors
		traits = p_traits


class ClaimCase:
	var id: StringName = &""
	var claim_type: StringName = &"contribution"
	var factors: Dictionary = {}
	var tags: Array[StringName] = []
	var amount: float = 0.0

	func _init(
		p_id: StringName = &"",
		p_claim_type: StringName = &"contribution",
		p_factors: Dictionary = {},
		p_tags: Array[StringName] = []
	) -> void:
		id = p_id
		claim_type = p_claim_type
		factors = p_factors
		tags = p_tags


## Stage A: rank eligible candidates and derive the winner's legitimacy.
func resolve_candidates(candidates: Array[Candidate]) -> Dictionary:
	var scored: Array[Dictionary] = []
	var excluded: Array[Dictionary] = []

	for candidate in candidates:
		if not candidate.eligible:
			excluded.append({
				"id": candidate.id,
				"reason": candidate.ineligible_reason,
			})
			continue
		var score: float = 0.0
		for key in candidate_weights:
			score += float(candidate_weights[key]) * _factor(candidate, key)
		scored.append({
			"id": candidate.id,
			"score": score,
			"candidate": candidate,
		})

	scored.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return float(a["score"]) > float(b["score"])
	)

	if scored.is_empty():
		return {
			"winner": &"",
			"traits": [],
			"scores": {},
			"legitimacy": 0.0,
			"insecurity": 1.0,
			"margin": 0.0,
			"contested": true,
			"interregnum": true,
			"unresolved_rivals": [],
			"excluded": excluded,
		}

	var winner: Candidate = scored[0]["candidate"]
	var top_score: float = float(scored[0]["score"])
	var second_score: float = float(scored[1]["score"]) if scored.size() > 1 else 0.0
	var margin: float = (top_score - second_score) / maxf(top_score, 0.001)
	var contested: bool = scored.size() > 1 and margin < CONTEST_MARGIN

	var backing: float = _factor(winner, &"backing")
	var predecessor: float = _factor(winner, &"predecessor")
	var legitimacy: float = clampf(
		0.60 * top_score + 0.25 * backing + 0.15 * predecessor,
		0.0,
		1.0
	)
	if contested:
		legitimacy *= 0.80

	var scores: Dictionary = {}
	var rivals: Array[StringName] = []
	for index in range(scored.size()):
		var entry: Dictionary = scored[index]
		var entry_score: float = float(entry["score"])
		scores[entry["id"]] = entry_score
		if index > 0 and (top_score - entry_score) / maxf(top_score, 0.001) < CONTEST_MARGIN:
			rivals.append(entry["id"])

	return {
		"winner": winner.id,
		"traits": winner.traits.duplicate(),
		"scores": scores,
		"legitimacy": legitimacy,
		"insecurity": 1.0 - legitimacy,
		"margin": margin,
		"contested": contested,
		"interregnum": false,
		"unresolved_rivals": rivals,
		"excluded": excluded,
	}


## Stage B: choose how the new officeholder treats one old claim.
func resolve_claim(
	claim: ClaimCase,
	context: Dictionary = {},
	traits: Array = []
) -> Dictionary:
	var factors: Dictionary = {}
	for key in CLAIM_FACTOR_KEYS:
		factors[key] = clampf(
			float(claim.factors.get(key, context.get(key, 0.5))),
			0.0,
			1.0
		)

	# Stage A outputs always win over any stale claim-level copy.
	factors[&"insecurity"] = clampf(
		float(context.get("insecurity", factors[&"insecurity"])), 0.0, 1.0
	)
	factors[&"legitimacy"] = clampf(
		float(context.get("legitimacy", factors[&"legitimacy"])), 0.0, 1.0
	)

	var unavailable: Dictionary = _gates(claim, factors)
	var scores: Dictionary = {}
	for action in ACTIONS:
		if unavailable.has(action):
			continue
		var weights: Dictionary = claim_weights.get(action, {})
		var score: float = 0.0
		for key in weights:
			score += float(weights[key]) * float(factors.get(key, 0.0))
		score += _trait_bonus(action, traits)
		scores[action] = score

	if scores.is_empty():
		# Freeze is never gated, but keep a deterministic fallback.
		scores[&"freeze"] = 0.0

	var ranked: Array = scores.keys()
	ranked.sort_custom(
		func(a: StringName, b: StringName) -> bool:
			return float(scores[a]) > float(scores[b])
	)

	var action: StringName = ranked[0]
	var top_score: float = float(scores[action])
	var second_score: float = float(scores[ranked[1]]) if ranked.size() > 1 else -INF
	var margin: float = top_score - second_score
	var uncertain: bool = margin < TIE_MARGIN

	# Indecision defaults to delay only when freeze is already close to the top.
	if uncertain and action != &"freeze" and scores.has(&"freeze"):
		if top_score - float(scores[&"freeze"]) < TIE_MARGIN:
			action = &"freeze"
			top_score = float(scores[action])
			margin = top_score - float(scores[ranked[1]])

	return {
		"claim_id": claim.id,
		"claim_type": claim.claim_type,
		"action": action,
		"scores": scores,
		"unavailable": unavailable,
		"margin": margin,
		"uncertain": uncertain,
		"discount_ratio": _discount_ratio(factors) if action == &"discount" else 1.0,
		"reasons": _reasons(action, factors),
		"factors": factors,
	}


## Convenience: run both stages over a batch of claims.
func resolve_succession(
	candidates: Array[Candidate],
	claims: Array[ClaimCase],
	context: Dictionary = {}
) -> Dictionary:
	var result: Dictionary = resolve_candidates(candidates)
	var winner_traits: Array = result.get("traits", [])
	var claim_results: Array[Dictionary] = []

	for claim in claims:
		var claim_context: Dictionary = context.duplicate(true)
		claim_context["insecurity"] = result["insecurity"]
		claim_context["legitimacy"] = result["legitimacy"]
		claim_results.append(resolve_claim(claim, claim_context, winner_traits))

	result["claims"] = claim_results
	return result


func _factor(candidate: Candidate, key: StringName) -> float:
	return clampf(float(candidate.factors.get(key, 0.0)), 0.0, 1.0)


func _merge_weights(target: Dictionary, source: Dictionary) -> void:
	for key in source:
		if source[key] is Dictionary and target.get(key) is Dictionary:
			var child: Dictionary = target[key]
			_merge_weights(child, source[key])
		else:
			target[key] = source[key]


func _gates(claim: ClaimCase, factors: Dictionary) -> Dictionary:
	var unavailable: Dictionary = {}

	if float(factors[&"validity"]) < EVIDENCE_GATE:
		unavailable[&"honor"] = &"insufficient_evidence"
		unavailable[&"discount"] = &"insufficient_evidence"
		unavailable[&"bargain"] = &"insufficient_evidence"

	if float(factors[&"burden"]) >= RESERVE_GATE:
		unavailable[&"honor"] = &"no_reserve"

	if (
		float(factors[&"leverage"]) >= RETALIATION_GATE
		and float(factors[&"visibility"]) >= PUBLIC_GATE
	):
		unavailable[&"repudiate"] = &"retaliation_risk"

	if (
		float(factors[&"insecurity"]) >= WEAK_MANDATE_GATE
		and float(factors[&"visibility"]) >= VISIBILITY_GATE
	):
		unavailable[&"repudiate"] = &"weak_mandate"

	if claim.tags.has(&"sealed_artifact") and float(factors[&"validity"]) >= 0.70:
		unavailable[&"repudiate"] = &"artifact_validated"

	if claim.tags.has(&"expired") and not claim.tags.has(&"renewal_clause"):
		unavailable[&"honor"] = &"expired"

	return unavailable


func _trait_bonus(action: StringName, traits: Array) -> float:
	var bonus: float = 0.0
	for trait_id in traits:
		var bias: Dictionary = trait_bias.get(trait_id, {})
		bonus += float(bias.get(action, 0.0))
	return bonus


func _discount_ratio(factors: Dictionary) -> float:
	var validity: float = float(factors.get(&"validity", 0.0))
	var continuity: float = float(factors.get(&"continuity", 0.0))
	var burden: float = float(factors.get(&"burden", 0.0))
	return clampf(
		0.20 + 0.45 * validity + 0.20 * continuity + 0.15 * (1.0 - burden),
		0.15,
		0.90
	)


func _reasons(action: StringName, factors: Dictionary) -> Array[Dictionary]:
	var weights: Dictionary = claim_weights.get(action, {})
	var ranked: Array[Dictionary] = []
	for key in weights:
		var contribution: float = float(weights[key]) * float(factors.get(key, 0.0))
		if absf(contribution) < 0.0001:
			continue
		ranked.append({
			"factor": key,
			"value": float(factors.get(key, 0.0)),
			"contribution": contribution,
			"tag": _reason_tag(key, float(factors.get(key, 0.0))),
		})
	ranked.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return absf(float(a["contribution"])) > absf(float(b["contribution"]))
	)
	return ranked.slice(0, 3)


func _reason_tag(factor: StringName, value: float) -> StringName:
	var high: bool = value >= 0.5
	match factor:
		&"validity":
			return &"claim_well_evidenced" if high else &"claim_dubious"
		&"burden":
			return &"treasury_strained" if high else &"treasury_healthy"
		&"continuity":
			return &"stability_matters" if high else &"marginal_claim"
		&"affinity":
			return &"claimant_ally" if high else &"claimant_rival"
		&"bond":
			return &"personal_gratitude" if high else &"personal_grudge"
		&"leverage":
			return &"retaliation_risk" if high else &"claimant_weak"
		&"visibility":
			return &"public_eye" if high else &"private_matter"
		&"precedent":
			return &"precedent_flood" if high else &"isolated_claim"
		&"need":
			return &"needs_support" if high else &"can_alienate"
		&"old_regime":
			return &"old_regime_loyalty" if high else &"clean_break"
		&"insecurity":
			return &"weak_mandate" if high else &"secure_mandate"
		&"legitimacy":
			return &"secure_mandate" if high else &"weak_mandate"
	return &"unknown"
