extends RefCounted
## Real artifact actions and the original regional clock own these scenarios.
## Actor placement is fixture setup; no running device balance is injected.

const Artifacts = preload("res://tests/sim/test_artifacts.gd")
const FIRE: String = "fire_stone"
const COLD: String = "cold_stone"
const CAPACITY: int = 180000000
var _artifacts := Artifacts.new()


func run(runner: Object) -> void:
	_lifecycle(runner)
	_inflight_switches(runner)
	_finite_and_restore(runner)
	_sink_only(runner)
	_sub_rate_tail(runner)
	_quiet_devices(runner)
	print("SCENARIO thermal devices: personal study, paid and interrupted switches, custody, finite original stocks, field response, independent restore and malformed-candidate rejection")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _artifacts._world(runner)
	if world == null:
		return null
	world.regions.home.set_actor_cell("chen_shouzhuo", world.artifacts.object_cell(FIRE))
	world.invalidate_region("home")
	return world


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _start(runner: Object, world: RegionalSimulation, actor: String, verb: String, id: String) -> bool:
	var result: Dictionary = world.artifacts.begin(actor, verb, id)
	runner.assert_true(bool(result.ok), "original artifact action begins: %s/%s/%s %s" % [actor, verb, id, result])
	return bool(result.ok)


func _finish(runner: Object, world: RegionalSimulation, actor: String) -> bool:
	if not world.artifacts.active.has(actor):
		runner.assert_true(false, "completion requires an actual in-flight artifact action")
		return false
	var reached: bool = world.advance_to_ms(int(world.artifacts.active[actor].due_ms))
	runner.assert_true(reached, "the shared regional clock reaches the actual artifact deadline")
	return reached


func _action(runner: Object, world: RegionalSimulation, actor: String, verb: String, id: String) -> bool:
	return _start(runner, world, actor, verb, id) and _finish(runner, world, actor)


func _advance(runner: Object, world: RegionalSimulation, at_ms: int) -> bool:
	var reached: bool = world.advance_to_ms(at_ms)
	runner.assert_true(reached, "regional device simulation reaches %dms" % at_ms)
	return reached


func _lifecycle(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	runner.assert_eq(int(domain.objects[FIRE].stored_q), CAPACITY, "the declared fire stone opens with one finite original reservoir")
	runner.assert_eq(int(domain.objects[COLD].stored_q), 0, "the declared cold stone opens empty")
	runner.assert_true(not bool(domain.objects[FIRE].enabled) and not bool(domain.objects[COLD].enabled), "scenario issuance enables neither device")
	var before: String = _json(world.to_dict())
	runner.assert_true(not bool(domain.begin("player", "enable", FIRE).ok), "appearance alone cannot enable a device")
	runner.assert_eq(_json(world.to_dict()), before, "unlearned enable spends no balance, time or receipt")
	if not _action(runner, world, "player", "study", FIRE):
		return
	runner.assert_true(domain.shape_studied("player", FIRE) and not domain.shape_studied("chen_shouzhuo", FIRE), "completed study belongs only to its original observer")
	runner.assert_true(not bool(domain.begin("chen_shouzhuo", "enable", FIRE).ok), "another person does not inherit the enabling method")
	if not _start(runner, world, "player", "enable", FIRE):
		return
	var due: int = int(domain.active.player.due_ms)
	runner.assert_eq(due - int(domain.active.player.started_ms), 60000, "enable takes its declared real minute")
	if not _advance(runner, world, due - 1):
		return
	runner.assert_true(not bool(domain.objects[FIRE].enabled) and world.environment_fields.device_switches.is_empty(), "an unfinished enable publishes no earlier source switch")
	if not _advance(runner, world, due):
		return
	runner.assert_true(bool(domain.objects[FIRE].enabled), "the successful action enables the original stone at its deadline")
	runner.assert_eq(int(domain.objects[FIRE].stored_q), CAPACITY, "enable itself does not prepay an invented elapsed interval")
	var enabled_event: Dictionary = domain.events[-1]
	runner.assert_eq(str(enabled_event.kind), "enabled", "successful activation records its real artifact outcome")
	var change: Dictionary = world.environment_fields.device_switches[enabled_event.action]
	runner.assert_eq(change.container, "kitchen", "activation receipt preserves the actual original container")
	runner.assert_eq(change.at_ms, enabled_event.at_ms, "artifact and thermal activation share one committed instant")
	runner.assert_eq(enabled_event.device_container, change.container, "the original event and thermal receipt agree on location")
	runner.assert_true(not bool(domain.begin("player", "take", FIRE).ok), "an enabled device must be closed before taking it")
	# Closing needs physical access, so this nearby person can stop an unsafe
	# device without having personally learned how to enable it.
	if not _start(runner, world, "chen_shouzhuo", "disable", FIRE):
		return
	due = int(domain.active.chen_shouzhuo.due_ms)
	if not _advance(runner, world, due - 1):
		return
	var stored: int = int(domain.objects[FIRE].stored_q)
	if not _advance(runner, world, due):
		return
	runner.assert_true(not bool(domain.objects[FIRE].enabled), "the real disable finishes at its own deadline")
	runner.assert_eq(stored - int(domain.objects[FIRE].stored_q), 1000, "that final old interval debits the same original stone")
	stored = int(domain.objects[FIRE].stored_q)
	var switch_count: int = world.environment_fields.device_switches.size()
	if not _action(runner, world, "player", "take", FIRE):
		return
	runner.assert_eq(domain.objects[FIRE].container, "actor:player", "taking moves the same disabled object into original custody")
	runner.assert_true(not bool(domain.begin("player", "enable", FIRE).ok), "a known device must be set down at a fixed location before enabling")
	if not _action(runner, world, "player", "place", FIRE):
		return
	runner.assert_eq(domain.objects[FIRE].container, "kitchen", "placing returns the same object to its declared real location")
	runner.assert_eq(int(domain.objects[FIRE].stored_q), stored, "carrying and placing do not refill the original reservoir")
	runner.assert_eq(world.environment_fields.device_switches.size(), switch_count, "disabled carrying creates no extra source switch")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", FIRE), 0, "the unique device is not duplicated in a stack inventory")
	if not _action(runner, world, "player", "enable", FIRE):
		return
	var restarted: int = world.elapsed_ms
	runner.assert_eq(int(domain.objects[FIRE].stored_q), stored, "re-enabling after custody changes keeps the original remaining reservoir")
	runner.assert_eq(world.environment_fields.device_switches.size(), switch_count + 1, "re-enabling records exactly one new source switch")
	@warning_ignore("integer_division")
	var exhausted_at: int = restarted + stored / 1000
	if not _advance(runner, world, exhausted_at - 1):
		return
	runner.assert_eq(int(domain.objects[FIRE].stored_q), 1000, "the independently running emitter retains its actual final millisecond of stock")
	if not _advance(runner, world, exhausted_at):
		return
	runner.assert_eq(int(domain.objects[FIRE].stored_q), 0, "the final real source interval consumes the finite tail exactly")
	if not _advance(runner, world, exhausted_at + 1001):
		return
	runner.assert_eq(int(domain.objects[FIRE].stored_q), 0, "an exhausted re-enabled source cannot spend stock again in later intervals")
	runner.assert_eq(int(domain.objects[COLD].stored_q), 0, "the disabled separate sink never changes stock")


func _inflight_switches(runner: Object) -> void:
	_inflight_enable_cancel(runner)
	_inflight_disable_restore(runner)


func _inflight_enable_cancel(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _action(runner, world, "player", "study", FIRE):
		return
	var qi_before: int = int(world.regions.home.actors.player.qi)
	var started_ms: int = int(world.elapsed_ms)
	var first_action: int = int(world.artifacts.next_id)
	var cost: int = int(world.artifacts.verbs_for(FIRE).enable.qi)
	runner.assert_true(cost > 0 and not world.spirit_sources.qi_baselines.has("player"), "first paid device switch starts without an earlier qi checkpoint")
	if not _start(runner, world, "player", "enable", FIRE):
		return
	var job: Dictionary = world.artifacts.active.player.duplicate(true)
	var due: int = int(job.due_ms)
	var midpoint: int = started_ms + int((due - started_ms) / 2.0)
	var qi_after: int = int(world.regions.home.actors.player.qi)
	runner.assert_eq(qi_after, qi_before - cost, "starting an actual enable charges the original body exactly once")
	runner.assert_eq(int(job.qi_spent), cost, "the unfinished enable records its committed qi cost")
	var baseline: Dictionary = world.spirit_sources.qi_baselines.get("player", {})
	runner.assert_true(not baseline.is_empty(), "the first paid enable creates its original qi checkpoint")
	if baseline.is_empty():
		return
	runner.assert_eq(int(baseline.at_ms), started_ms, "the qi checkpoint is established at the actual start")
	runner.assert_eq(int(baseline.qi), qi_before, "the qi checkpoint observes the original balance before the enable debit")
	runner.assert_eq(int(baseline.artifact_floor), first_action, "the qi checkpoint includes this first paid artifact action")
	if not _advance(runner, world, midpoint):
		return
	runner.assert_true(midpoint > started_ms and midpoint < due and world.artifacts.active.has("player"), "the saved enable is really in flight")
	runner.assert_true(not bool(world.artifacts.objects[FIRE].enabled) and world.environment_fields.device_switches.is_empty() and world.environment_fields.receipts.is_empty(), "an unfinished enable publishes neither a switch nor a heat source")
	var saved: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var resumed: RegionalSimulation = _world(runner)
	if resumed == null:
		return
	var loaded: bool = resumed.restore(saved)
	runner.assert_true(loaded, "an independent candidate restores a paid unfinished enable and its qi provenance")
	if not loaded:
		return
	runner.assert_true(resumed.artifacts != world.artifacts and resumed.environment_fields != world.environment_fields and resumed.spirit_sources != world.spirit_sources and resumed.regions.home != world.regions.home, "unfinished enable restore uses independent original owners")
	runner.assert_eq(_json(resumed.to_dict()), _json(saved), "the unfinished enable, body, qi checkpoint and full world survive JSON exactly")
	runner.assert_eq(_json(resumed.spirit_sources.qi_baselines.player), _json(baseline), "independent restore retains the pre-debit qi baseline")
	var cancelled: bool = world.artifacts.cancel("player")
	var resumed_cancelled: bool = resumed.artifacts.cancel("player")
	runner.assert_true(cancelled and resumed_cancelled, "both original and restored enables can actually be cancelled")
	if not cancelled or not resumed_cancelled:
		return
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi_after, "cancelling the enable does not refund its committed qi")
	runner.assert_eq(int(resumed.regions.home.actors.player.qi), qi_after, "cancelling the restored enable does not refund its committed qi")
	var event: Dictionary = world.artifacts.events.back()
	runner.assert_true(event.kind == "cancelled" and event.action == job.id and int(event.qi_spent) == cost, "the cancelled action retains its actual paid evidence")
	runner.assert_true(not event.has("device_container") and not event.has("heat_amount"), "a cancelled enable does not claim a thermal completion")
	runner.assert_true(not world.artifacts.active.has("player") and not bool(world.artifacts.objects[FIRE].enabled), "cancellation releases the action without enabling the original object")
	runner.assert_true(world.environment_fields.device_switches.is_empty() and world.environment_fields.receipts.is_empty(), "cancellation creates neither device switches nor warming receipts")
	runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "original and restored cancellation commit the same complete world")
	var cancelled_save: Dictionary = JSON.parse_string(_json(resumed.to_dict()))
	var reloaded: bool = resumed.restore(cancelled_save)
	runner.assert_true(reloaded, "the cancelled paid enable remains independently valid on a second JSON restore")
	if not reloaded:
		return
	if not _advance(runner, world, due + 1001) or not _advance(runner, resumed, due - 1) or not _advance(runner, resumed, due + 1001):
		return
	runner.assert_true(not bool(world.artifacts.objects[FIRE].enabled) and world.environment_fields.device_switches.is_empty() and world.environment_fields.receipts.is_empty(), "passing the cancelled deadline never starts the device or fabricates thermal evidence")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), CAPACITY, "the cancelled source never spends the original reservoir")
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi_after, "passing the cancelled deadline never refunds the original qi debit")
	runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "a cancelled and reloaded enable has the same future across its old deadline")


func _inflight_disable_restore(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _action(runner, world, "player", "study", FIRE) or not _action(runner, world, "player", "enable", FIRE):
		return
	var started_ms: int = int(world.elapsed_ms)
	var stored_at_start: int = int(world.artifacts.objects[FIRE].stored_q)
	var rate: int = int(world.artifacts.definitions.types.fire_stone.thermal.rate_q_per_ms)
	if not _start(runner, world, "player", "disable", FIRE):
		return
	var job: Dictionary = world.artifacts.active.player.duplicate(true)
	var due: int = int(job.due_ms)
	var midpoint: int = started_ms + int((due - started_ms) / 2.0)
	if not _advance(runner, world, midpoint):
		return
	runner.assert_true(midpoint > started_ms and midpoint < due and world.artifacts.active.has("player") and bool(world.artifacts.objects[FIRE].enabled), "the saved disable is unfinished while its actual source remains enabled")
	var half_spent: int = (midpoint - started_ms) * rate
	runner.assert_eq(stored_at_start - int(world.artifacts.objects[FIRE].stored_q), half_spent, "that first-half emission debits the same finite original stone")
	var saved: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var resumed: RegionalSimulation = _world(runner)
	if resumed == null:
		return
	var loaded: bool = resumed.restore(saved)
	runner.assert_true(loaded, "an independent candidate restores an unfinished disable and its frozen active source")
	if not loaded:
		return
	runner.assert_true(resumed.artifacts != world.artifacts and resumed.environment_fields != world.environment_fields and resumed.regions.home != world.regions.home, "unfinished disable restore owns an independent body, stone and thermal field")
	runner.assert_eq(_json(resumed.to_dict()), _json(saved), "the unfinished disable and complete original energy ledger survive JSON")
	var before_switch: String = _json(world.to_dict())
	var heat_owner: RefCounted = world.environment_fields
	var stone_owner: SimArtifacts = world.artifacts
	var body_owner: VillageSimulation = world.regions.home
	var near: bool = world.set_active_region("home")
	var far: bool = resumed.set_active_region("river")
	runner.assert_true(near and far, "the same pending disable can be scheduled in near and distant regions")
	if not near or not far:
		return
	runner.assert_true(world.environment_fields == heat_owner and world.artifacts == stone_owner and world.regions.home == body_owner and int(world.elapsed_ms) == midpoint, "changing the active region preserves original owners and the shared time")
	var near_snapshot: Dictionary = world.to_dict()
	var far_snapshot: Dictionary = resumed.to_dict()
	near_snapshot.active_region = ""
	far_snapshot.active_region = ""
	runner.assert_eq(_json(near_snapshot), before_switch, "selecting the nearby region changes only scheduling at the saved instant")
	runner.assert_eq(_json(far_snapshot), before_switch, "selecting the distant region changes only scheduling at the saved instant")
	if not _advance(runner, world, due - 1) or not _advance(runner, resumed, midpoint + 173) or not _advance(runner, resumed, due - 1):
		return
	runner.assert_true(bool(world.artifacts.objects[FIRE].enabled) and bool(resumed.artifacts.objects[FIRE].enabled), "the source remains enabled until its real disable deadline in both schedules")
	var before_final_stock: int = int(world.artifacts.objects[FIRE].stored_q)
	var spent_before_due: int = (due - 1 - started_ms) * rate
	runner.assert_eq(stored_at_start - before_final_stock, spent_before_due, "the penultimate emission is charged to the same original reservoir")
	runner.assert_eq(_json(resumed.environment_fields.to_dict()), _json(world.environment_fields.to_dict()), "near and far schedules preserve the same old thermal interval")
	if not _advance(runner, world, due) or not _advance(runner, resumed, due):
		return
	runner.assert_true(not bool(world.artifacts.objects[FIRE].enabled) and not bool(resumed.artifacts.objects[FIRE].enabled), "the original disable actually completes at its common deadline")
	runner.assert_eq(before_final_stock - int(world.artifacts.objects[FIRE].stored_q), rate, "the final interval debits the original stock exactly once")
	var event: Dictionary = world.artifacts.events.back()
	runner.assert_true(event.kind == "disabled" and event.action == job.id and int(event.at_ms) == due, "the completed disable records its real action and deadline")
	runner.assert_true(world.environment_fields.device_switches.has(job.id), "the completed disable has exactly its own thermal switch evidence")
	runner.assert_eq(world.environment_fields.device_switches.size(), 2, "one enable and one disable produce exactly two device switch receipts")
	if not world.environment_fields.device_switches.has(job.id):
		return
	var receipt: Dictionary = world.environment_fields.device_switches[job.id]
	runner.assert_true(not bool(receipt.enabled) and int(receipt.at_ms) == due and receipt.object == FIRE, "the thermal switch matches the actual completed disable")
	var stopped_stock: int = int(world.artifacts.objects[FIRE].stored_q)
	var disabled_state: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var before_rejection: String = _json(disabled_state)
	var refilled: Dictionary = disabled_state.duplicate(true)
	refilled.artifacts.objects[FIRE].stored_q = stopped_stock + 1
	runner.assert_true(not world.restore(refilled), "a disabled original device cannot gain one unrecorded unit within capacity")
	runner.assert_eq(_json(world.to_dict()), before_rejection, "rejecting a disabled-device refill preserves the complete live world")
	if not _advance(runner, world, due + 1001) or not _advance(runner, resumed, due + 337) or not _advance(runner, resumed, due + 1001):
		return
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), stopped_stock, "later time cannot debit the disabled original stone")
	var reset_near: bool = world.set_active_region("")
	var reset_far: bool = resumed.set_active_region("")
	runner.assert_true(reset_near and reset_far, "both complete schedules can return to the same active-region selector")
	if not reset_near or not reset_far:
		return
	runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "restored and split disable has the same complete future under near and far scheduling")


func _enable_pair(runner: Object, world: RegionalSimulation) -> bool:
	if not _start(runner, world, "player", "study", FIRE) or not _start(runner, world, "chen_shouzhuo", "study", COLD) or not _finish(runner, world, "player"):
		return false
	if not _start(runner, world, "player", "enable", FIRE) or not _start(runner, world, "chen_shouzhuo", "enable", COLD) or not _finish(runner, world, "player"):
		return false
	var enabled: bool = bool(world.artifacts.objects[FIRE].enabled) and bool(world.artifacts.objects[COLD].enabled)
	runner.assert_true(enabled, "two personally studied devices activate at the same genuine shared-time boundary")
	return enabled


func _finite_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var control: RegionalSimulation = _world(runner)
	if world == null or control == null or not _enable_pair(runner, world):
		return
	# Study the same objects in a second world but leave both devices off. Their
	# intrinsic elements still exist, so compare actual temperatures, not cells.
	if not _start(runner, control, "player", "study", FIRE) or not _start(runner, control, "chen_shouzhuo", "study", COLD) or not _finish(runner, control, "player"):
		return
	var activated: int = world.elapsed_ms
	if not _advance(runner, world, activated + 173) or not _advance(runner, control, activated + 173):
		return
	var point: Vector2i = world.artifacts.object_cell(FIRE)
	runner.assert_eq(point, world.artifacts.object_cell(COLD), "the emitter and absorber genuinely occupy the same fixed cell")
	var rate: int = int(world.artifacts.definitions.types.fire_stone.thermal.rate_q_per_ms)
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), CAPACITY - 173 * rate, "the original emitter spends its fixed-rate stock once")
	runner.assert_eq(int(world.artifacts.objects[COLD].stored_q), 173 * rate, "the original absorber gains its fixed-rate stock once")
	var both: Dictionary = world.environment_fields.actual_at(point, world.elapsed_ms)
	var neither: Dictionary = control.environment_fields.actual_at(point, control.elapsed_ms)
	runner.assert_true(bool(both.get("ok", false)) and bool(neither.get("ok", false)), "actual temperatures are available for equal opposing devices")
	if bool(both.get("ok", false)) and bool(neither.get("ok", false)):
		runner.assert_true(absf(float(both.value_c) - float(neither.value_c)) < 0.00001, "equal same-cell hot and cold grades cancel in actual temperature while both stocks change")
	var saved: Dictionary = JSON.parse_string(_json(world.to_dict()))
	runner.assert_eq(int(saved.local_heat.last_ms), world.elapsed_ms, "the checkpoint records the actual field instant")
	var resumed: RegionalSimulation = _world(runner)
	if resumed == null:
		return
	var loaded: bool = resumed.restore(saved)
	runner.assert_true(loaded, "independent regional JSON restore accepts the running devices")
	if not loaded:
		return
	runner.assert_true(resumed.environment_fields != world.environment_fields and resumed.artifacts != world.artifacts, "restoration constructs independent field and artifact owners")
	runner.assert_eq(_json(resumed.to_dict()), _json(saved), "restoration preserves the complete original world")
	_reject_mutations(runner, world, saved)
	var horizon: int = activated + 199999
	if not _advance(runner, world, horizon):
		return
	for offset: int in [997, 9999, 10000, 37653, 179999, 180000, 199999]:
		if not _advance(runner, resumed, activated + offset):
			return
	runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "whole and restored sliced execution reach the same complete future")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), 0, "the finite emitter reaches exact exhaustion")
	runner.assert_eq(int(world.artifacts.objects[COLD].stored_q), CAPACITY, "the finite absorber reaches its exact capacity")


func _reject_mutations(runner: Object, world: RegionalSimulation, saved: Dictionary) -> void:
	var before: String = _json(world.to_dict())
	var live_heat: RefCounted = world.environment_fields
	var live_artifacts: SimArtifacts = world.artifacts
	var live_body: VillageSimulation = world.regions.home
	if saved.local_heat.device_switches.is_empty():
		runner.assert_true(false, "running devices retain their original switch events")
		return
	for kind: String in ["stored_q", "unexplained_refill", "unexplained_loss", "switch_container", "missing_switch", "wrong_model", "wrong_source_digest", "future_field", "forged_receipt"]:
		var bad: Dictionary = saved.duplicate(true)
		match kind:
			"stored_q": bad.artifacts.objects[FIRE].stored_q = CAPACITY + 1
			"unexplained_refill": bad.artifacts.objects[FIRE].stored_q = int(bad.artifacts.objects[FIRE].stored_q) + 1
			"unexplained_loss": bad.artifacts.objects[COLD].stored_q = int(bad.artifacts.objects[COLD].stored_q) - 1
			"switch_container":
				var action: String = str(bad.local_heat.device_switches.keys()[0])
				bad.local_heat.device_switches[action].container = "dorm"
			"missing_switch": bad.local_heat.device_switches.erase(bad.local_heat.device_switches.keys()[0])
			"wrong_model": bad.local_heat.model = "retired_heat_model"
			"wrong_source_digest": bad.local_heat.source_digest = "invalid"
			"future_field": bad.local_heat.last_ms = int(saved.elapsed_ms) + 1
			"forged_receipt": bad.local_heat.receipts["forged"] = {}
		var input: String = _json(bad)
		runner.assert_true(not world.restore(bad), "independent candidate rejects a one-field device forgery: " + kind)
		runner.assert_true(world.environment_fields == live_heat and world.artifacts == live_artifacts and world.regions.home == live_body, "rejected device candidate retains the original live owners: " + kind)
		runner.assert_eq(_json(world.to_dict()), before, "rejected device candidate leaves the complete live world unchanged: " + kind)
		runner.assert_eq(_json(bad), input, "device validation never repairs the supplied malformed input: " + kind)


func _quiet_devices(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _advance(runner, world, 20037):
		return
	runner.assert_true(not bool(world.artifacts.objects[FIRE].enabled) and not bool(world.artifacts.objects[COLD].enabled), "scenario devices remain disabled")
	runner.assert_true(world.environment_fields.device_switches.is_empty() and world.environment_fields.receipts.is_empty(), "quiet devices invent neither switches nor warming receipts")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), CAPACITY, "a disabled emitter spends no original stock")
	runner.assert_eq(int(world.artifacts.objects[COLD].stored_q), 0, "a disabled absorber gains no original stock")


func _sink_only(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	var control: RegionalSimulation = _world(runner)
	if world == null or control == null or not _action(runner, world, "player", "study", COLD) or not _action(runner, control, "player", "study", COLD) or not _action(runner, world, "player", "enable", COLD):
		return
	var enabled_at: int = world.elapsed_ms
	if not _advance(runner, control, enabled_at):
		return
	var point: Vector2i = world.artifacts.object_cell(COLD)
	var switched: Dictionary = world.environment_fields.actual_at(point, enabled_at)
	var baseline: Dictionary = control.environment_fields.actual_at(point, enabled_at)
	runner.assert_true(bool(switched.get("ok", false)) and bool(baseline.get("ok", false)), "both real field temperatures are available at the switch")
	if not bool(switched.get("ok", false)) or not bool(baseline.get("ok", false)):
		return
	runner.assert_true(absf(float(switched.value_c) - float(baseline.value_c)) < 0.00001, "enabling a cold source does not make temperature jump")
	if not _advance(runner, world, enabled_at + 1000) or not _advance(runner, control, enabled_at + 1000):
		return
	var early: Dictionary = world.environment_fields.actual_at(point, world.elapsed_ms)
	var early_control: Dictionary = control.environment_fields.actual_at(point, control.elapsed_ms)
	if not _advance(runner, world, enabled_at + 30000) or not _advance(runner, control, enabled_at + 30000):
		return
	var later: Dictionary = world.environment_fields.actual_at(point, world.elapsed_ms)
	var later_control: Dictionary = control.environment_fields.actual_at(point, control.elapsed_ms)
	var valid: bool = bool(early.get("ok", false)) and bool(early_control.get("ok", false)) and bool(later.get("ok", false)) and bool(later_control.get("ok", false))
	runner.assert_true(valid, "actual cold-source temperatures remain available over time")
	if valid:
		var first_delta: float = float(early.value_c) - float(early_control.value_c)
		var later_delta: float = float(later.value_c) - float(later_control.value_c)
		runner.assert_true(later_delta < first_delta and first_delta < 0.0, "the cold source gradually lowers actual temperature relative to the same background")
	var rate: int = int(world.artifacts.definitions.types.cold_stone.thermal.rate_q_per_ms)
	runner.assert_eq(int(world.artifacts.objects[COLD].stored_q), rate * 30000, "the sink's original stock changes at its declared finite rate")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), CAPACITY, "a disabled fire stone never spends stock for the separate sink")
	runner.assert_eq(int(control.artifacts.objects[COLD].stored_q), 0, "the disabled control does not accumulate stock")


func _sub_rate_tail(runner: Object) -> void:
	# Bind this finite capacity before any body, object or thermal owner exists.
	# Both the world content and original artifact definitions see the same law.
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "finite-tail fixture loads original definitions")
		return
	content.artifacts.types.fire_stone.thermal.capacity_q = 1001
	content.artifacts.types.fire_stone.thermal.opening_q = 1001
	var instances: Dictionary = {}
	for region: String in ["home", "river"]:
		var village: VillageSimulation = _artifacts._fixtures._make_village(content, region, false)
		if village == null:
			runner.assert_true(false, "finite-tail fixture constructs the original village owners")
			return
		instances[region] = village
	var settings: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/world_continuity.json"))
	var world := RegionalSimulation.new()
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	if not world.initialize(settings, instances, content) or not world.artifacts.spawn_opening(opening):
		runner.assert_true(false, "finite-tail fixture issues the original 1001-Q source under its declared opening definition")
		return
	world.set_active_region("")
	world.regions.home.set_actor_cell("player", world.artifacts.object_cell(FIRE))
	world.invalidate_region("home")
	if not _action(runner, world, "player", "study", FIRE) or not _action(runner, world, "player", "enable", FIRE):
		return
	var activated: int = world.elapsed_ms
	if not _advance(runner, world, activated + 1):
		return
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), 1, "the first millisecond leaves the genuine sub-rate source tail")
	if not _advance(runner, world, activated + 2):
		return
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), 0, "the final one-Q tail is transferred rather than dropped or borrowed against")
	if not _advance(runner, world, activated + 1003):
		return
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), 0, "later time cannot spend the exhausted sub-rate tail again")
	runner.assert_eq(world.environment_fields.device_switches.size(), 1, "the finite-tail device retains exactly its one completed enable")
