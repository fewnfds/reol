extends RefCounted
## Real records form the controls; malformed histories never replace a world.

const Fixtures = preload("res://tests/sim/test_field_opportunities.gd")
const Schema = preload("res://scripts/sim/field_opportunity_schema.gd")
const RING: String = "stele_drawing_ring"
const SITE: String = "broken_stele"
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_transfer_chain(runner)
	_same_minute_future_source(runner)
	print("SCENARIO field causality: real take/place/take controls, reentrant take, another person's placement and reversed milliseconds rejected by custody replay, same-minute future testimony rejected, original JSON candidates remain atomic")


func _canonical(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _copy(runner: Object, world: RegionalSimulation, label: String) -> RegionalSimulation:
	var candidate: RegionalSimulation = _fixtures._world(runner)
	if candidate == null:
		return null
	candidate.bind_map_data(world.map_data.independent_copy())
	var saved: String = _canonical(world.to_dict())
	var accepted: bool = candidate.restore(JSON.parse_string(saved))
	runner.assert_true(accepted, label + " restores the real complete control world")
	if not accepted:
		return null
	runner.assert_eq(_canonical(candidate.to_dict()), saved, label + " preserves every original state owner")
	return candidate


func _reject_joint(runner: Object, world: RegionalSimulation, bad: Dictionary, label: String) -> void:
	var candidate: RegionalSimulation = _fixtures._world(runner)
	if candidate == null:
		return
	candidate.bind_map_data(world.map_data.independent_copy())
	var before: String = _canonical(candidate.to_dict())
	var original: String = _canonical(world.to_dict())
	var input: String = _canonical(bad)
	runner.assert_true(not candidate.restore(bad), label + " is rejected by the complete world candidate")
	runner.assert_eq(_canonical(candidate.to_dict()), before, label + " leaves the entire destination world intact")
	runner.assert_eq(_canonical(world.to_dict()), original, label + " changes no original body, object or memory")
	runner.assert_eq(_canonical(bad), input, label + " does not silently repair its supplied history")


func _finish(runner: Object, world: RegionalSimulation, verb: String) -> bool:
	var answer: Dictionary = world.artifacts.begin("player", verb, RING)
	runner.assert_true(answer.ok, "control starts the actual original ring operation: " + verb)
	if not answer.ok:
		return false
	var due: int = int(world.artifacts.active.player.due_ms)
	var advanced: bool = world.advance_to_ms(due)
	runner.assert_true(advanced, "control reaches the actual original ring deadline: " + verb)
	return advanced


func _transfer_chain(runner: Object) -> void:
	var world: RegionalSimulation = _fixtures._world(runner)
	if world == null:
		return
	_fixtures._put(world, "player", _fixtures._site(world))
	for verb: String in ["take", "place", "take"]:
		if not _finish(runner, world, verb):
			return
	var transfers: Array[Dictionary] = []
	for event: Dictionary in world.artifacts.events:
		if event.object == RING and event.kind in ["taken", "placed"]:
			transfers.append(event)
	runner.assert_eq(transfers.size(), 3, "control contains three real serial transfers of the same original ring")
	if transfers.size() != 3:
		return
	runner.assert_true(Schema._custody_valid(world.field_opportunities) and world.field_opportunities.cross_valid(), "real take/place/take passes exact custody and source checks")
	if _copy(runner, world, "actual serial handling") == null:
		return
	var saved: String = _canonical(world.to_dict())
	for fault: String in ["reentrant_taken", "other_actor_placed", "reversed_milliseconds"]:
		var bad: Dictionary = JSON.parse_string(saved)
		for event: Dictionary in bad.artifacts.events:
			if fault == "reentrant_taken" and event.id == transfers[1].id:
				event.verb = "take"
				event.kind = "taken"
			elif fault == "other_actor_placed" and event.id == transfers[1].id:
				event.actor = "shi_tou"
				event.subject = world.embodiment.subject_for_actor("shi_tou")
			elif fault == "reversed_milliseconds" and event.id == transfers[2].id:
				# Keep the original one-minute duration and the existing coarse
				# event tick, while placing this result before the prior result.
				event.at_ms = int(transfers[1].at_ms) - 1000
				event.started_ms = int(event.at_ms) - 60000
		var probe: RegionalSimulation = _copy(runner, world, fault)
		if probe == null:
			return
		# Old artifact shape proves each individual operation, but not the new
		# field ring's serial source custody. Check that added boundary directly
		# as well as the whole candidate, whose older observations may also fail.
		runner.assert_true(probe.artifacts.restore(bad.artifacts), fault + " remains an individually valid original artifact payload")
		runner.assert_true(not Schema._custody_valid(probe.field_opportunities), fault + " is rejected specifically by field custody replay")
		_reject_joint(runner, world, bad, fault)
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:player", "all rejected histories leave the real final holder unchanged")


func _same_minute_future_source(runner: Object) -> void:
	var world: RegionalSimulation = _fixtures._world(runner)
	if world == null:
		return
	var at: Vector2i = _fixtures._site(world)
	_fixtures._put(world, "su_zhi", at)
	_fixtures._put(world, "player", at + Vector2i(1, 0))
	runner.assert_true(world.advance_to_ms(1000), "observer reaches a real millisecond within the first minute")
	runner.assert_true(world.field_opportunities.observe_site("su_zhi", SITE).ok, "nonopening knower personally observes the real slot")
	var source: Dictionary = world.field_opportunities._known_event("su_zhi", SITE)
	runner.assert_true(source.get("kind") == "field_site_observed" and int(source.get("details", {}).get("at_ms", -1)) == 1000, "source is the actual personal observation rather than an opening rumor")
	if source.is_empty():
		return
	runner.assert_true(world.advance_to_ms(2000), "source observer and listener later meet within the same minute")
	var answer: Dictionary = world.field_opportunities.learn_from("player", "su_zhi")
	runner.assert_true(answer.ok, "actual idle observer agrees to share the personally sourced clue")
	if not answer.ok:
		return
	var shared: Dictionary = {}
	for event: Dictionary in world.services.social.events:
		if event.kind == "field_clue_shared" and event.actor == "su_zhi" and event.target == "player":
			shared = event
	runner.assert_true(not shared.is_empty(), "actual communication creates the original attributed sharing event")
	if shared.is_empty():
		return
	runner.assert_true(Schema._shared(world.field_opportunities, shared, {}), "earlier actual source satisfies the exact sharing boundary")
	runner.assert_true(world.advance_to_ms(4000), "control world reaches a later time in the same minute")
	runner.assert_true(world.field_opportunities.cross_valid(), "real same-minute observation then sharing remains causally valid")
	var bad: Dictionary = JSON.parse_string(_canonical(world.to_dict()))
	for event: Dictionary in bad.services.social.events:
		if event.id == source.id:
			event.details.participants.at_ms = 3000
	for knower: String in bad.services.social.knowledge:
		if bad.services.social.knowledge[knower].has(source.id):
			bad.services.social.knowledge[knower][source.id].details.at_ms = 3000
	var probe: RegionalSimulation = _copy(runner, world, "same-minute temporal source")
	if probe == null:
		return
	runner.assert_true(probe.services.social.restore(bad.services.social), "future-millisecond mutation retains valid original attributed social shapes")
	var moved_source: Dictionary = probe.services.social._event_by_id[source.id]
	var old_share: Dictionary = probe.services.social._event_by_id[shared.id]
	runner.assert_eq(moved_source.tick, old_share.tick, "coarse minute equality cannot establish the causal order")
	runner.assert_true(Schema._observation(probe.field_opportunities, moved_source), "moved observation remains individually possible at its later millisecond")
	runner.assert_true(not Schema._shared(probe.field_opportunities, old_share, {}), "sharing rejects a source that only occurs later in the same minute")
	_reject_joint(runner, world, bad, "same-minute future observation as an earlier source")
