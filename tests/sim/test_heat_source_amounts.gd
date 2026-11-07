extends RefCounted
## Real warm jobs publish one metadata receipt and a finite field source.

const RegionalFixtures = preload("res://tests/sim/test_regional_simulation.gd")
const HEAT_PATH: String = "res://data/definitions/local_heat.json"
const STONE: String = "hearth_stone"
## Original village navigation refers to this fixture; keep its owner alive.
var _fixtures := RegionalFixtures.new()


func run(runner: Object) -> void:
	_completed_source(runner)
	_cancel_and_capacity(runner)
	_event_shape_rejections(runner)
	_independent_resume(runner)
	print("SCENARIO explicit heat source amounts: real warm completion and original charge, cancelled/capacity failures, strict event fields, session-bound pulse value and independent in-flight/completed restoration")


func _world(runner: Object, pulse_energy: int = 0) -> RegionalSimulation:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "source amount fixture loads original content")
		return null
	if pulse_energy > 0:
		# Explicit new-world content, before any state or time exists. Its bundle
		# records the same metadata amount that the domains actually consume.
		var documents: Dictionary = content.content_bundle().documents
		documents[HEAT_PATH].pulse_energy = pulse_energy
		content = ReolContentDB.new()
		if not content.load_bundle(ReolContentBundle.from_documents(documents)):
			runner.assert_true(false, "source amount opening has a valid independent content bundle")
			return null
	var instances: Dictionary = {}
	for region: String in ["home", "river"]:
		var sim: VillageSimulation = _fixtures._make_village(content, region, false)
		if sim == null:
			runner.assert_true(false, "source amount fixture assembles original regional bodies")
			return null
		instances[region] = sim
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	var world := RegionalSimulation.new()
	if not world.initialize(settings, instances, content) or not world.configure_services(content.settlement_services):
		runner.assert_true(false, "source amount fixture uses the original regional authority")
		return null
	world.services.set_navigation(Callable(_fixtures, "_path"))
	world.set_active_region("")
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	if not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "source amount fixture spawns the original finite stone")
		return null
	world.regions.home.set_actor_cell("player", world.artifacts.object_cell(STONE))
	world.invalidate_region("home")
	return world


func _perform(runner: Object, world: RegionalSimulation, verb: String) -> bool:
	var response: Dictionary = world.artifacts.begin("player", verb, STONE)
	runner.assert_true(bool(response.ok), "ordinary source action starts: " + verb)
	if not bool(response.ok):
		return false
	var reached: bool = world.advance_to_ms(int(world.artifacts.active.player.due_ms))
	runner.assert_true(reached, "original common time completes the source action: " + verb)
	return reached


func _learn_and_hold(runner: Object, world: RegionalSimulation) -> bool:
	return _perform(runner, world, "study") and _perform(runner, world, "take")


func _completed_source(runner: Object) -> void:
	# Deliberately differs from the file default: the source must use the bound
	# session's heat authority, not a literal amount or today's disk value.
	const PULSE: int = 360000000
	var world: RegionalSimulation = _world(runner, PULSE)
	if world == null or not _learn_and_hold(runner, world):
		return
	var charge: int = int(world.artifacts.objects[STONE].charge)
	var cost: int = int(world.artifacts.definitions.types.warm_stone.warming_charge)
	var qi: int = int(world.regions.home.actors.player.qi)
	if not _perform(runner, world, "warm"):
		return
	var event: Dictionary = world.artifacts.events.back()
	runner.assert_eq(world.artifacts.to_dict().version, 8, "current artifact writer includes finite thermal devices")
	runner.assert_eq(event.kind, "warmed", "real successful job records a warmed source")
	runner.assert_eq(event.get("heat_amount"), PULSE, "completed event records the actual session-bound transfer amount")
	runner.assert_eq(world.artifacts.objects[STONE].charge, charge - cost, "the same completion spends original warming_charge once")
	runner.assert_eq(world.regions.home.actors.player.qi, qi, "explicit source metadata adds no second resource cost")
	runner.assert_eq(world.environment_fields.receipts.size(), 1, "one real action creates one thermal receipt")
	if not world.environment_fields.receipts.has(event.action):
		runner.assert_true(false, "the action owns its thermal receipt")
		return
	var receipt: Dictionary = world.environment_fields.receipts[event.action]
	runner.assert_eq(receipt, {"action": event.action, "actor": event.actor, "object": event.object, "at_ms": event.at_ms, "cell": event.cell, "amount": event.heat_amount}, "event and original receipt name the same action, source, time, location and amount")
	var key: String = "pulse:" + str(event.action)
	var source: Dictionary = world.environment_fields._sources.get_source(key)
	runner.assert_true(not source.is_empty(), "the accepted action owns one active temporary source")
	if not source.is_empty():
		runner.assert_eq(source.cell, Vector2i(int(event.cell[0]), int(event.cell[1])), "the field source uses the original completion cell")
		runner.assert_eq(source.channels[5], 1000, "session receipt amount is metadata; this prototype's source grade remains one")
		runner.assert_eq(source.channels[6], 0, "the warm source does not create a cold field")
	runner.assert_eq(world.environment_fields._transient.get(key), {"cell": event.cell, "until_ms": event.at_ms + 60000}, "the source remains active for its bounded real duration")
	for row: Dictionary in world.artifacts.events:
		if row.kind != "warmed":
			runner.assert_true(not row.has("heat_amount"), "ordinary study/take events do not claim thermal input")
	var before: String = _world_digest(world)
	runner.assert_true(not world.environment_fields.deposit(receipt), "replaying the original action cannot add another input")
	runner.assert_eq(_world_digest(world), before, "duplicate source leaves original charge and complete world unchanged")
	var other: RegionalSimulation = _world(runner, PULSE)
	if other == null:
		return
	var restored: bool = other.restore(_round_trip(world.to_dict()))
	runner.assert_true(restored, "completed explicit amount restores against the same independent content")
	if restored:
		runner.assert_eq(_world_digest(other), before, "independent completed restart preserves original charge and one matching source")


func _cancel_and_capacity(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn_and_hold(runner, world):
		return
	var charge: int = int(world.artifacts.objects[STONE].charge)
	var began: Dictionary = world.artifacts.begin("player", "warm", STONE)
	runner.assert_true(bool(began.ok), "cancellation scenario starts a real warm job")
	if not bool(began.ok):
		return
	var due: int = int(world.artifacts.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 237), "cancellation occurs after an actual partial interval")
	runner.assert_true(world.artifacts.cancel("player"), "ordinary cancellation stops the original job")
	var cancelled: Dictionary = world.artifacts.events.back()
	runner.assert_eq(cancelled.kind, "cancelled", "cancelled job records its actual unfinished outcome")
	runner.assert_true(not cancelled.has("heat_amount"), "cancelled job has no successful source amount")
	runner.assert_eq(world.artifacts.objects[STONE].charge, charge, "cancellation preserves the original finite charge")
	runner.assert_true(world.environment_fields.receipts.is_empty() and world.environment_fields._transient.is_empty(), "cancellation emits no thermal receipt or active source")
	runner.assert_true(world.advance_to_ms(due + 1), "world genuinely passes the cancelled job's former completion instant")
	runner.assert_true(world.environment_fields.receipts.is_empty() and world.artifacts.events.back().kind == "cancelled", "cancelled completion cannot reappear later as a source")

	# Fault-inject a full disposable source index without inventing an object,
	# action, receipt or world fact. A real warm job must refuse atomically.
	var full: RegionalSimulation = _world(runner)
	if full == null or not _learn_and_hold(runner, full):
		return
	if not full.environment_fields.activate_sources():
		runner.assert_true(false, "capacity fixture activates its original source participant")
		return
	var participant: SimWorldEnvironmentSourceParticipant = full.environment_fields._sources
	var original_records: Dictionary = participant._records.duplicate(true)
	var original_capacity: int = participant._capacity
	var original_free: Array = participant._free.duplicate()
	participant._capacity = participant._next_slot
	participant._free.clear()
	var original_charge: int = int(full.artifacts.objects[STONE].charge)
	_perform(runner, full, "warm")
	var failure: Dictionary = full.artifacts.events.back()
	runner.assert_eq(failure.kind, "failed", "a real warm job reports the source-index capacity refusal")
	runner.assert_true(not failure.has("heat_amount"), "capacity failure has no claimed heat amount")
	runner.assert_eq(full.artifacts.objects[STONE].charge, original_charge, "rejected deposit spends none of the original charge")
	runner.assert_true(full.environment_fields.receipts.is_empty() and full.environment_fields._transient.is_empty(), "capacity refusal creates neither transient source nor receipt")
	runner.assert_eq(participant._records, original_records, "capacity refusal publishes no partial source-index entry")
	if failure.kind == "failed" and participant._records == original_records:
		participant._capacity = original_capacity
		participant._free.assign(original_free)
	var error: String = str(full.environment_fields.diagnostics().error)
	runner.assert_eq(error, "", "a recoverable capacity refusal does not poison the world's environmental authority")
	if error.is_empty() and failure.kind == "failed":
		var failed_copy: RegionalSimulation = _world(runner)
		if failed_copy != null:
			var restored: bool = failed_copy.restore(_round_trip(full.to_dict()))
			runner.assert_true(restored, "a failed warm event with no receipt remains a valid independent candidate")
			if restored:
				runner.assert_eq(_world_digest(failed_copy), _world_digest(full), "rejected capacity operation restores the same original world")


func _event_shape_rejections(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn_and_hold(runner, world) or not _perform(runner, world, "warm"):
		return
	var current: Dictionary = _round_trip(world.artifacts.to_dict())
	var before: String = _artifact_digest(world.artifacts)
	var missing: Dictionary = current.duplicate(true)
	missing.events.back().erase("heat_amount")
	_reject_artifacts(runner, world, missing, before, "current warmed event must carry an explicit amount")
	var pulse: int = int(world.environment_fields.definitions.pulse_energy)
	for amount: Variant in [null, true, 0, -1, 1.5, pulse - 1, pulse + 1, INF]:
		var bad: Dictionary = current.duplicate(true)
		bad.events.back().heat_amount = amount
		_reject_artifacts(runner, world, bad, before, "invalid or mismatched warmed amount is refused")
	var non_source: Dictionary = current.duplicate(true)
	non_source.events[0]["heat_amount"] = pulse
	_reject_artifacts(runner, world, non_source, before, "non-warmed event cannot carry a source amount")
	var old: Dictionary = current.duplicate(true)
	old.version = 6
	old.events.back().erase("heat_amount")
	_reject_artifacts(runner, world, old, before, "current artifact restore does not silently upgrade version 6")
	var heat: SimWorldEnvironmentFields = world.environment_fields
	world.environment_fields = null
	_reject_artifacts(runner, world, current, before, "warmed validation requires the candidate's bound heat authority")
	world.environment_fields = heat
	var whole_json: Dictionary = current.duplicate(true)
	whole_json.events.back().heat_amount = float(pulse)
	runner.assert_true(world.artifacts.restore(whole_json), "whole JSON numeric amount is accepted by the explicit format")
	runner.assert_true(world.artifacts.events.back().heat_amount is int, "accepted heat amount is normalized to the original integer contract")
	runner.assert_eq(_artifact_digest(world.artifacts), before, "numeric normalization preserves all artifact facts")

	var saved: Dictionary = _round_trip(world.to_dict())
	var stable: String = _world_digest(world)
	var action: String = str(world.artifacts.events.back().action)
	var changed_event: Dictionary = saved.duplicate(true)
	changed_event.artifacts.events.back().heat_amount += 1
	_reject_world(runner, world, changed_event, stable, "joint candidate rejects a forged event amount")
	var changed_receipt: Dictionary = saved.duplicate(true)
	changed_receipt.local_heat.receipts[action].amount += 1
	_reject_world(runner, world, changed_receipt, stable, "joint candidate rejects a mismatched original receipt amount")
	var absent_receipt: Dictionary = saved.duplicate(true)
	absent_receipt.local_heat.receipts.erase(action)
	_reject_world(runner, world, absent_receipt, stable, "warmed event cannot survive without its unique thermal receipt")


func _independent_resume(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn_and_hold(runner, world):
		return
	var charge: int = int(world.artifacts.objects[STONE].charge)
	var began: Dictionary = world.artifacts.begin("player", "warm", STONE)
	runner.assert_true(bool(began.ok), "restart scenario begins the actual warming process")
	if not bool(began.ok):
		return
	var due: int = int(world.artifacts.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 17431), "save is taken during the original in-flight duration")
	runner.assert_true(world.environment_fields.receipts.is_empty() and int(world.artifacts.objects[STONE].charge) == charge, "in-flight save has no premature amount, receipt or debit")
	var saved: Dictionary = _round_trip(world.to_dict())
	var other: RegionalSimulation = _world(runner)
	if other == null:
		return
	var accepted: bool = other.restore(saved)
	runner.assert_true(accepted, "independent world restores the unfinished explicit-source action")
	if not accepted:
		return
	runner.assert_true(world.advance_to_ms(due) and other.advance_to_ms(due), "both real shared clocks finish their restored source")
	runner.assert_eq(_world_digest(other), _world_digest(world), "in-flight restart produces the same original charge, event amount and receipt")
	var event: Dictionary = other.artifacts.events.back()
	runner.assert_eq(event.get("heat_amount"), other.environment_fields.receipts[event.action].amount, "resumed completion records its actual accepted amount")
	runner.assert_eq(other.environment_fields.receipts.size(), 1, "resumed completion deposits exactly one source")
	var completed: Dictionary = _round_trip(other.to_dict())
	var restarted: RegionalSimulation = _world(runner)
	if restarted == null:
		return
	var loaded: bool = restarted.restore(completed)
	runner.assert_true(loaded, "a completed explicit source restores a second time")
	if not loaded:
		return
	var event_count: int = restarted.artifacts.events.size()
	var spent_charge: int = int(restarted.artifacts.objects[STONE].charge)
	runner.assert_true(restarted.advance_to_ms(due + 1234), "restarted world genuinely passes the completed source time")
	runner.assert_true(restarted.artifacts.events.size() == event_count and restarted.environment_fields.receipts.size() == 1 and int(restarted.artifacts.objects[STONE].charge) == spent_charge, "completed source is neither replayed nor charged a second time")


func _reject_artifacts(runner: Object, world: RegionalSimulation, candidate: Dictionary, before: String, label: String) -> void:
	runner.assert_true(not world.artifacts.restore(candidate), label)
	runner.assert_eq(_artifact_digest(world.artifacts), before, "artifact rejection leaves the original state unchanged")


func _reject_world(runner: Object, world: RegionalSimulation, candidate: Dictionary, before: String, label: String) -> void:
	runner.assert_true(not world.restore(candidate), label)
	runner.assert_eq(_world_digest(world), before, "invalid joint source candidate never partly replaces the live world")


func _artifact_digest(domain: SimArtifacts) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(domain.to_dict())).sha256_text()


func _world_digest(world: RegionalSimulation) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(world.to_dict())).sha256_text()


func _round_trip(value: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(value, "", true, true))
