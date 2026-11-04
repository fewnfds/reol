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
	print("SCENARIO thermal devices: personal study, interrupted and restored switches, custody, same-cell finite source/sink costs, frozen mid-segment JSON, arbitrary split future and atomic malformed-candidate rejection")


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


func _conserved(runner: Object, world: RegionalSimulation, label: String, opening_q: int = CAPACITY) -> void:
	var heat: RefCounted = world.local_heat
	var sum_q: int = 0
	for row: Dictionary in heat.cells.values():
		sum_q += int(row.energy)
	runner.assert_eq(sum_q + int(heat.loss_energy) + int(heat.absorbed_energy), int(heat.input_energy) + int(heat.continuous_input) + int(heat.ambient_in), label)
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q) + int(heat.device_input.get(FIRE, 0)), opening_q, "source stock and the field's cumulative debit refer to one original balance")
	runner.assert_eq(int(world.artifacts.objects[COLD].stored_q), int(heat.device_absorbed.get(COLD, 0)), "sink stock is exactly the field's cumulative absorption")


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
	runner.assert_true(not bool(domain.objects[FIRE].enabled) and int(world.local_heat.continuous_input) == 0, "an unfinished enable emits no earlier heat")
	if not _advance(runner, world, due):
		return
	runner.assert_true(bool(domain.objects[FIRE].enabled), "the successful action enables the original stone at its deadline")
	runner.assert_eq(int(domain.objects[FIRE].stored_q), CAPACITY, "enable itself does not prepay an invented elapsed interval")
	var enabled_event: Dictionary = domain.events[-1]
	runner.assert_eq(str(enabled_event.kind), "enabled", "successful activation records its real artifact outcome")
	var change: Dictionary = world.local_heat.device_switches[enabled_event.action]
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
	var emitted: int = int(world.local_heat.continuous_input)
	var stored: int = int(domain.objects[FIRE].stored_q)
	if not _advance(runner, world, due):
		return
	runner.assert_true(not bool(domain.objects[FIRE].enabled), "the real disable finishes at its own deadline")
	runner.assert_eq(int(world.local_heat.continuous_input) - emitted, 1000, "the last millisecond settles the old enabled source before closing")
	runner.assert_eq(stored - int(domain.objects[FIRE].stored_q), 1000, "that final old interval debits the same original stone")
	runner.assert_true(not world.local_heat.cells.is_empty(), "closing retains the real heat already left in physical cells")
	emitted = int(world.local_heat.continuous_input)
	stored = int(domain.objects[FIRE].stored_q)
	if not _action(runner, world, "player", "take", FIRE):
		return
	runner.assert_eq(domain.objects[FIRE].container, "actor:player", "taking moves the same disabled object into original custody")
	runner.assert_true(not bool(domain.begin("player", "enable", FIRE).ok), "a known device must be set down at a fixed location before enabling")
	if not _action(runner, world, "player", "place", FIRE):
		return
	runner.assert_eq(domain.objects[FIRE].container, "kitchen", "placing returns the same object to its declared real location")
	runner.assert_eq(int(domain.objects[FIRE].stored_q), stored, "carrying and placing do not refill the original reservoir")
	runner.assert_eq(int(world.local_heat.continuous_input), emitted, "disabled carrying emits no extra heat")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", FIRE), 0, "the unique device is not duplicated in a stack inventory")
	_conserved(runner, world, "closed and moved source preserves all old field heat and external exchanges")
	if not _action(runner, world, "player", "enable", FIRE):
		return
	var restarted: int = world.elapsed_ms
	runner.assert_eq(int(domain.objects[FIRE].stored_q), stored, "re-enabling after custody changes keeps the original remaining reservoir")
	runner.assert_eq(int(world.local_heat.continuous_input), emitted, "re-enabling adds a receipt without replaying the previous enabled interval")
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
	runner.assert_eq(int(world.local_heat.continuous_input), CAPACITY, "an exhausted re-enabled source cannot emit again in later intervals")
	runner.assert_eq(int(world.local_heat.absorbed_energy), 0, "the separated source-only case has no cancelling sink ledger")
	_conserved(runner, world, "closing, carrying and re-enabling never duplicates source stock or its finite tail")


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
	runner.assert_true(not bool(world.artifacts.objects[FIRE].enabled) and world.local_heat.device_switches.is_empty() and world.local_heat.receipts.is_empty(), "an unfinished enable publishes neither a switch nor a heat source")
	var saved: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var resumed: RegionalSimulation = _world(runner)
	if resumed == null:
		return
	var loaded: bool = resumed.restore(saved)
	runner.assert_true(loaded, "an independent candidate restores a paid unfinished enable and its qi provenance")
	if not loaded:
		return
	runner.assert_true(resumed.artifacts != world.artifacts and resumed.local_heat != world.local_heat and resumed.spirit_sources != world.spirit_sources and resumed.regions.home != world.regions.home, "unfinished enable restore uses independent original owners")
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
	runner.assert_true(world.local_heat.device_switches.is_empty() and world.local_heat.receipts.is_empty() and world.local_heat.cells.is_empty(), "cancellation creates neither thermal receipts nor a physical field")
	runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "original and restored cancellation commit the same complete world")
	var cancelled_save: Dictionary = JSON.parse_string(_json(resumed.to_dict()))
	var reloaded: bool = resumed.restore(cancelled_save)
	runner.assert_true(reloaded, "the cancelled paid enable remains independently valid on a second JSON restore")
	if not reloaded:
		return
	if not _advance(runner, world, due + 1001) or not _advance(runner, resumed, due - 1) or not _advance(runner, resumed, due + 1001):
		return
	runner.assert_true(not bool(world.artifacts.objects[FIRE].enabled) and world.local_heat.device_switches.is_empty() and world.local_heat.receipts.is_empty() and world.local_heat.cells.is_empty(), "passing the cancelled deadline never starts the device or fabricates thermal evidence")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), CAPACITY, "the cancelled source never spends the original reservoir")
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi_after, "passing the cancelled deadline never refunds the original qi debit")
	_conserved(runner, world, "a cancelled enable leaves the original thermal balance conserved")
	_conserved(runner, resumed, "the reloaded cancelled enable leaves the original thermal balance conserved")
	runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "a cancelled and reloaded enable has the same future across its old deadline")


func _inflight_disable_restore(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _action(runner, world, "player", "study", FIRE) or not _action(runner, world, "player", "enable", FIRE):
		return
	var started_ms: int = int(world.elapsed_ms)
	var stored_at_start: int = int(world.artifacts.objects[FIRE].stored_q)
	var emitted_at_start: int = int(world.local_heat.continuous_input)
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
	runner.assert_eq(int(world.local_heat.continuous_input) - emitted_at_start, half_spent, "the old source really emits through the first half of the disable action")
	runner.assert_eq(stored_at_start - int(world.artifacts.objects[FIRE].stored_q), half_spent, "that first-half emission debits the same finite original stone")
	_conserved(runner, world, "the unfinished disable preserves its original active-source energy")
	var saved: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var resumed: RegionalSimulation = _world(runner)
	if resumed == null:
		return
	var loaded: bool = resumed.restore(saved)
	runner.assert_true(loaded, "an independent candidate restores an unfinished disable and its frozen active source")
	if not loaded:
		return
	runner.assert_true(resumed.artifacts != world.artifacts and resumed.local_heat != world.local_heat and resumed.regions.home != world.regions.home, "unfinished disable restore owns an independent body, stone and thermal field")
	runner.assert_eq(_json(resumed.to_dict()), _json(saved), "the unfinished disable and complete original energy ledger survive JSON")
	_conserved(runner, resumed, "the restored unfinished disable preserves its original active-source energy")
	var before_switch: String = _json(world.to_dict())
	var heat_owner: RefCounted = world.local_heat
	var stone_owner: SimArtifacts = world.artifacts
	var body_owner: VillageSimulation = world.regions.home
	var near: bool = world.set_active_region("home")
	var far: bool = resumed.set_active_region("river")
	runner.assert_true(near and far, "the same pending disable can be scheduled in near and distant regions")
	if not near or not far:
		return
	runner.assert_true(world.local_heat == heat_owner and world.artifacts == stone_owner and world.regions.home == body_owner and int(world.elapsed_ms) == midpoint, "changing the active region preserves original owners and the shared time")
	var near_snapshot: Dictionary = world.to_dict()
	var far_snapshot: Dictionary = resumed.to_dict()
	near_snapshot.active_region = ""
	far_snapshot.active_region = ""
	runner.assert_eq(_json(near_snapshot), before_switch, "selecting the nearby region changes only scheduling at the saved instant")
	runner.assert_eq(_json(far_snapshot), before_switch, "selecting the distant region changes only scheduling at the saved instant")
	if not _advance(runner, world, due - 1) or not _advance(runner, resumed, midpoint + 173) or not _advance(runner, resumed, due - 1):
		return
	runner.assert_true(bool(world.artifacts.objects[FIRE].enabled) and bool(resumed.artifacts.objects[FIRE].enabled), "the source remains enabled until its real disable deadline in both schedules")
	var before_final_input: int = int(world.local_heat.continuous_input)
	var before_final_stock: int = int(world.artifacts.objects[FIRE].stored_q)
	var spent_before_due: int = (due - 1 - started_ms) * rate
	runner.assert_eq(before_final_input - emitted_at_start, spent_before_due, "the original source continues emitting through the penultimate millisecond")
	runner.assert_eq(stored_at_start - before_final_stock, spent_before_due, "the penultimate emission is charged to the same original reservoir")
	runner.assert_eq(_json(resumed.local_heat.to_dict()), _json(world.local_heat.to_dict()), "near and far schedules preserve the same old thermal interval")
	if not _advance(runner, world, due) or not _advance(runner, resumed, due):
		return
	runner.assert_true(not bool(world.artifacts.objects[FIRE].enabled) and not bool(resumed.artifacts.objects[FIRE].enabled), "the original disable actually completes at its common deadline")
	runner.assert_eq(int(world.local_heat.continuous_input) - before_final_input, rate, "the last old-source millisecond is settled before disabling")
	runner.assert_eq(before_final_stock - int(world.artifacts.objects[FIRE].stored_q), rate, "the final interval debits the original stock exactly once")
	var event: Dictionary = world.artifacts.events.back()
	runner.assert_true(event.kind == "disabled" and event.action == job.id and int(event.at_ms) == due, "the completed disable records its real action and deadline")
	runner.assert_true(world.local_heat.device_switches.has(job.id), "the completed disable has exactly its own thermal switch evidence")
	runner.assert_eq(world.local_heat.device_switches.size(), 2, "one enable and one disable produce exactly two device switch receipts")
	if not world.local_heat.device_switches.has(job.id):
		return
	var receipt: Dictionary = world.local_heat.device_switches[job.id]
	runner.assert_true(not bool(receipt.enabled) and int(receipt.at_ms) == due and receipt.object == FIRE, "the thermal switch matches the actual completed disable")
	var stopped_input: int = int(world.local_heat.continuous_input)
	var stopped_stock: int = int(world.artifacts.objects[FIRE].stored_q)
	if not _advance(runner, world, due + 1001) or not _advance(runner, resumed, due + 337) or not _advance(runner, resumed, due + 1001):
		return
	runner.assert_eq(int(world.local_heat.continuous_input), stopped_input, "later time cannot repeat a completed disable or emit more source energy")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), stopped_stock, "later time cannot debit the disabled original stone")
	_conserved(runner, world, "the completed near disable preserves the original thermal balance")
	_conserved(runner, resumed, "the completed far disable preserves the original thermal balance")
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
	if world == null or not _enable_pair(runner, world):
		return
	var activated: int = world.elapsed_ms
	if not _advance(runner, world, activated + 173):
		return
	var heat: RefCounted = world.local_heat
	runner.assert_eq(world.artifacts.object_cell(FIRE), world.artifacts.object_cell(COLD), "the source and sink genuinely occupy the same fixed physical cell")
	runner.assert_true(int(heat.continuous_input) > 0 and int(heat.absorbed_energy) > 0, "both opposing endpoints make real nonzero transfers")
	runner.assert_eq(int(heat.continuous_input), int(heat.absorbed_energy), "equal same-cell rates can have zero net field change while both device costs remain")
	runner.assert_true(int(world.artifacts.objects[FIRE].stored_q) < CAPACITY and int(world.artifacts.objects[COLD].stored_q) > 0, "net cancellation never refunds the source or erases actual absorption")
	var source_edge: bool = false
	var sink_edge: bool = false
	for flow: Dictionary in heat.flows:
		source_edge = source_edge or flow.from == "@artifact/" + FIRE
		sink_edge = sink_edge or flow.to == "@artifact/" + COLD
	runner.assert_true(source_edge and sink_edge, "the frozen field retains each original artifact endpoint separately")
	_conserved(runner, world, "same-cell source and sink retain complete physical energy accounting")
	var saved: Dictionary = JSON.parse_string(_json(world.to_dict()))
	runner.assert_true(int(saved.local_heat.segment_started_ms) < world.elapsed_ms and int(saved.local_heat.segment_until_ms) > world.elapsed_ms, "the checkpoint lies inside an actual frozen device segment")
	var resumed: RegionalSimulation = _world(runner)
	if resumed == null:
		return
	var loaded: bool = resumed.restore(saved)
	runner.assert_true(loaded, "independent regional JSON restore accepts the actual running source and sink")
	if not loaded:
		return
	runner.assert_true(resumed.local_heat != world.local_heat and resumed.artifacts != world.artifacts, "restoration constructs independent heat and original artifact owners")
	runner.assert_eq(_json(resumed.to_dict()), _json(saved), "mid-segment restoration preserves the complete original world")
	_reject_mutations(runner, world, saved)
	var horizon: int = activated + 199999
	if not _advance(runner, world, horizon):
		return
	for offset: int in [997, 9999, 10000, 37653, 179999, 180000, 199999]:
		if not _advance(runner, resumed, activated + offset):
			return
	runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "one whole interval and arbitrary restarted slices yield the same complete future")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), 0, "the finite emitter reaches exact exhaustion")
	runner.assert_eq(int(world.artifacts.objects[COLD].stored_q), CAPACITY, "the finite absorber reaches its exact original capacity")
	runner.assert_eq(int(heat.device_input[FIRE]), CAPACITY, "longer elapsed time cannot debit more than original source stock")
	runner.assert_eq(int(heat.device_absorbed[COLD]), CAPACITY, "longer elapsed time cannot overfill the original sink")
	runner.assert_eq(int(heat.last_sample_continuous_input), CAPACITY, "the committed historical sample retains actual continuous source spending")
	runner.assert_eq(int(heat.last_sample_absorbed), CAPACITY, "the same historical sample retains its separate actual sink spending")
	_conserved(runner, world, "exhausted source and full sink keep their original field and ledger")


func _reject_mutations(runner: Object, world: RegionalSimulation, saved: Dictionary) -> void:
	var before: String = _json(world.to_dict())
	var live_heat: RefCounted = world.local_heat
	var live_artifacts: SimArtifacts = world.artifacts
	var live_body: VillageSimulation = world.regions.home
	for kind: String in ["stored_q", "continuous_input", "device_input", "switch_container", "segment_until_ms"]:
		var bad: Dictionary = saved.duplicate(true)
		match kind:
			"stored_q": bad.artifacts.objects[FIRE].stored_q += 1
			"continuous_input": bad.local_heat.continuous_input += 1
			"device_input": bad.local_heat.device_input[FIRE] += 1
			"switch_container":
				var action: String = str(bad.local_heat.device_switches.keys()[0])
				bad.local_heat.device_switches[action].container = "dorm"
			"segment_until_ms": bad.local_heat.segment_until_ms += 1
		var input: String = _json(bad)
		runner.assert_true(not world.restore(bad), "independent candidate rejects a one-field device forgery: " + kind)
		runner.assert_true(world.local_heat == live_heat and world.artifacts == live_artifacts and world.regions.home == live_body, "rejected device candidate retains the original live owners: " + kind)
		runner.assert_eq(_json(world.to_dict()), before, "rejected device candidate leaves the complete live world unchanged: " + kind)
		runner.assert_eq(_json(bad), input, "device validation never repairs the supplied malformed input: " + kind)


func _quiet_devices(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _advance(runner, world, 20037):
		return
	runner.assert_true(world.local_heat.cells.is_empty() and world.local_heat.flows.is_empty(), "merely declaring disabled devices creates no field or periodic flux")
	runner.assert_true(world.local_heat.device_switches.is_empty() and world.local_heat.receipts.is_empty(), "quiet devices invent neither activation nor old warm-source history")
	runner.assert_true(int(world.local_heat.continuous_input) == 0 and int(world.local_heat.absorbed_energy) == 0, "the old no-source world has no new energy inputs or sinks")
	_conserved(runner, world, "disabled devices preserve the prior quiet-world energy rule")


func _sink_only(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _action(runner, world, "player", "study", COLD) or not _action(runner, world, "player", "enable", COLD):
		return
	if not _advance(runner, world, world.elapsed_ms + 173):
		return
	runner.assert_true(int(world.local_heat.absorbed_energy) > 0, "a separate cold stone really absorbs the previously allocated physical background energy")
	runner.assert_eq(int(world.local_heat.continuous_input), 0, "a sink works without inventing a fire-source input")
	runner.assert_true(world.local_heat.current_tenths(world.artifacts.object_cell(COLD)) < 0, "the sink alone creates a real negative local thermal offset")
	runner.assert_eq(int(world.artifacts.objects[FIRE].stored_q), CAPACITY, "a disabled fire stone does not subsidize the separate sink")
	_conserved(runner, world, "the independent sink stores exactly the heat removed from the original field")


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
	runner.assert_eq(int(world.local_heat.continuous_input), 1001, "later time cannot turn a sub-rate remainder into a second full-rate debit")
	_conserved(runner, world, "the exact sub-rate tail keeps both unique stock and physical energy", 1001)
