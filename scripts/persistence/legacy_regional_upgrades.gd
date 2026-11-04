class_name LegacyRegionalUpgrades
extends RefCounted
## Pure historical regional shape conversions for root save migration.


static func upgrade_conflicts(source: Dictionary) -> Dictionary:
	if source.get("version") != 30 or source.has("conflicts") or not source.get("health") is Dictionary or not source.get("spirit_sources") is Dictionary:
		return {}
	var result: Dictionary = source.duplicate(true)
	result.health = SimHealth.upgrade_legacy(source.health)
	result.spirit_sources = SimSpiritSources.upgrade_legacy(source.spirit_sources)
	if result.health.is_empty() or result.spirit_sources.is_empty():
		return {}
	# Preserve the historical v30 -> v31 shape. The next explicit migration
	# activates perception at the saved present rather than inventing history.
	result["conflicts"] = {"version": 1, "next_id": 1, "next_cost_id": 1, "next_hit_id": 1, "next_lesson_id": 1, "conflicts": {}, "actions": {}, "hits": {}, "projectiles": {}, "barriers": {}, "lessons": {}}
	result.version = 31
	return result


static func upgrade_conflict_perception(source: Dictionary) -> Dictionary:
	if source.get("version") != 31 or not RegionalSimulation._integer(source.get("elapsed_ms"), 0):
		return {}
	var legacy: Variant = source.get("conflicts")
	var legacy_fields: Array[String] = ["version", "next_id", "next_cost_id", "next_hit_id", "next_lesson_id", "conflicts", "actions", "hits", "projectiles", "barriers", "lessons"]
	if not SimConflicts.Shape.keys(legacy, legacy_fields) or not SimConflicts.Shape.count(legacy.version, 1, 1) or not legacy.conflicts is Dictionary:
		return {}
	# A modern/forged record must not be relabelled as old and repaired. The
	# complete original history is checked after this shape-only conversion.
	var encounter_fields: Array[String] = ["id", "region", "initiator", "defender", "intent", "started_ms", "last_ms", "next_step_ms", "ended_ms", "reason", "yielded", "people", "withdrawal"]
	for row: Variant in legacy.conflicts.values():
		if not SimConflicts.Shape.keys(row, encounter_fields) or not row.people is Dictionary:
			return {}
		for person: Variant in row.people.values():
			if not SimConflicts.Shape.keys(person, ["previous_autonomous", "action", "ready_ms"]):
				return {}
	var result: Dictionary = source.duplicate(true)
	var upgraded: Dictionary = result.conflicts
	upgraded.version = 2
	upgraded["perception_since_ms"] = int(source.elapsed_ms)
	for row: Dictionary in upgraded.conflicts.values():
		for person: Dictionary in row.people.values():
			person["sight"] = {}
	result.version = 32
	return result


static func upgrade_site_affairs(source: Dictionary) -> Dictionary:
	if source.get("version") != 32 or source.has("site_affairs"):
		return {}
	var result: Dictionary = source.duplicate(true)
	result["site_affairs"] = SimSiteAffairs.empty_state()
	result.version = 33
	return result


static func upgrade_source_care(source: Dictionary) -> Dictionary:
	if source.get("version") != 33 or source.has("source_care") or not source.get("conflicts") is Dictionary:
		return {}
	var next_conflicts: Dictionary = SimConflicts.upgrade_source_care(source.conflicts)
	if next_conflicts.is_empty():
		return {}
	var result: Dictionary = source.duplicate(true)
	result["source_care"] = SimSourceCare.empty_state()
	result.conflicts = next_conflicts
	result.version = 34
	return result


static func upgrade_field_opportunities(source: Dictionary) -> Dictionary:
	if source.get("version") != 35 or source.has("field_opportunities"):
		return {}
	var result: Dictionary = source.duplicate(true)
	# Previously unplayed worlds have no invented site, visitors or treasure.
	result["field_opportunities"] = SimFieldOpportunities.empty_state()
	result.version = 36
	return result


static func upgrade_ring_use(source: Dictionary) -> Dictionary:
	if source.get("version") != 36 or not source.get("artifacts") is Dictionary:
		return {}
	var artifacts: Dictionary = source.artifacts
	if not SimArtifacts.Schema._keys(artifacts, ["version", "objects", "active", "events", "experiences", "next_id"]) or artifacts.version != 4 or not artifacts.active is Dictionary or not artifacts.events is Array:
		return {}
	# These actions did not exist in v4. A version downgrade must not bypass
	# the new knowledge and cost checks, nor manufacture a prior draw.
	var old_actions: Array = artifacts.active.values()
	old_actions.append_array(artifacts.events)
	for row: Variant in old_actions:
		if not row is Dictionary or row.has("draw") or row.get("verb") in ["use_research", "draw"]:
			return {}
	var result: Dictionary = source.duplicate(true)
	result.artifacts.version = 5
	result.version = 37
	return result


static func upgrade_private_exchange(source: Dictionary) -> Dictionary:
	if source.get("version") != 37 or source.has("private_exchange") or not source.get("artifacts") is Dictionary:
		return {}
	var artifacts_state: Dictionary = source.artifacts
	if not SimArtifacts.Schema._keys(artifacts_state, ["version", "objects", "active", "events", "experiences", "next_id"]) or artifacts_state.version != 5 or not artifacts_state.active is Dictionary or not artifacts_state.events is Array:
		return {}
	var rows: Array = artifacts_state.active.values()
	rows.append_array(artifacts_state.events)
	for row: Variant in rows:
		if not row is Dictionary or row.has("exchange") or row.get("verb") == "private_exchange" or row.get("kind") == "exchanged":
			return {}
	# Activation adds no consent, cash, transfer, object or prior transaction.
	var result: Dictionary = source.duplicate(true)
	result["private_exchange"] = SimPrivateExchange.empty_state()
	result.artifacts.version = 6
	result.version = 38
	return result


static func upgrade_heat_amounts(source: Dictionary) -> Dictionary:
	if source.get("version") != 38 or not source.get("artifacts") is Dictionary or not source.get("local_heat") is Dictionary:
		return {}
	var artifacts_state: Dictionary = source.artifacts
	var heat: Dictionary = source.local_heat
	if not SimArtifacts.Schema._keys(artifacts_state, ["version", "objects", "active", "events", "experiences", "next_id"]) or artifacts_state.version != 6 or not artifacts_state.events is Array or heat.get("version") != 1 or not heat.get("receipts") is Dictionary:
		return {}
	# This conversion changes no physical state or heat rule. Existing receipts
	# are the only evidence of old transfers; never price a past event from a
	# current definition or invent a receipt. Full candidate validation follows.
	var result: Dictionary = source.duplicate(true)
	for row: Variant in result.artifacts.events:
		if not row is Dictionary or row.has("heat_amount"):
			return {}
		if row.get("kind") != "warmed":
			continue
		var receipt: Variant = heat.receipts.get(row.get("action"))
		if not receipt is Dictionary or not SimArtifacts.Schema._count(receipt.get("amount"), 1):
			return {}
		row["heat_amount"] = int(receipt.amount)
	result.artifacts.version = 7
	result.version = 39
	return result


static func upgrade_capability_practice(source: Dictionary) -> Dictionary:
	if source.get("version") != 34 or source.has("capability_practice") or not source.get("spirit_sources") is Dictionary:
		return {}
	var next_sources: Dictionary = SimSpiritSources.upgrade_practice(source.spirit_sources)
	if next_sources.is_empty():
		return {}
	var result: Dictionary = source.duplicate(true)
	result["capability_practice"] = SimCapabilityPractice.empty_state()
	result.spirit_sources = next_sources
	result.version = 35
	return result


