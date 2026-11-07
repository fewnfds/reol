extends RefCounted
## Source receipts must agree with actual original qi, storage and busy owners.

const Support = preload("res://tests/sim/spirit_source_test_support.gd")


func run(runner: Object) -> void:
	_actual_qi_loop(runner)
	_paid_inputs_already_in_flight(runner)
	_original_soul_and_teaching_costs(runner)
	_original_charge_changes(runner)
	_forged_candidates(runner)
	_cross_domain_ownership(runner)
	_historical_ownership_and_reservations(runner)
	print("SCENARIO spirit integrity: real depleted qi, original ongoing costs and guidance, actual stored heat use/fracture, strict receipt/baseline accounting and atomic cross-owner rejection")


func _restore(runner: Object, world: RegionalSimulation, options: Dictionary = {}) -> bool:
	var candidate: RegionalSimulation = Support.valid_restore(runner, world, options)
	if candidate == null:
		return false
	runner.assert_eq(Support.canonical(candidate.to_dict()), Support.canonical(world.to_dict()), "independent complete restore preserves source and original domain facts")
	return true


func _actual_qi_loop(runner: Object) -> void:
	var options: Dictionary = {"known": false, "max_qi": 5}
	var world: RegionalSimulation = Support.make(runner, options)
	if world == null:
		return
	Support.artifact(runner, world, "player", "study")
	Support.artifact(runner, world, "player", "charge")
	runner.assert_eq(world.regions.home.actors.player.qi, 0, "actual paid study and temperature storage deplete the original five-unit body")
	runner.assert_true(world.artifacts.describe("player", "hearth_stone").method, "the player's channeling foundation comes from real completed study")
	var before_rest: int = world.elapsed_ms
	runner.assert_true(world.regions.home.submit_action("player", "rest"), "the depleted original body can still perform ordinary rest")
	world.invalidate_region("home")
	runner.assert_true(world.advance_to_ms(before_rest + 60000), "ordinary real rest spends one actual minute")
	world.regions.home.cancel_action("player")
	world.regions.home.set_actor_cell("player", SimRouteTravel.cell(world.regions.home.places.kitchen.cell))
	world.invalidate_region("home")
	runner.assert_eq(world.regions.home.actors.player.qi, 0, "ordinary rest does not secretly refill original qi")
	var answer: Dictionary = world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone")
	runner.assert_true(answer.ok, "depleted but genuinely trained person starts finite external restoration")
	if not answer.ok:
		return
	var id: String = Support.finish(runner, world)
	runner.assert_eq(world.regions.home.actors.player.qi, 4, "actual completed source restores the same original qi field")
	runner.assert_eq(world.spirit_sources.records[id].before, 0, "source records the actual depleted reserve before conversion")
	runner.assert_eq(world.spirit_sources.qi_baselines.player.qi, 0, "the first baseline does not invent earlier passive recovery")
	runner.assert_true(_restore(runner, world, options), "restored original qi has actual source provenance")
	Support.artifact(runner, world, "player", "charge")
	runner.assert_eq(world.regions.home.actors.player.qi, 0, "new source energy can pay the real original temperature-storage cost")
	runner.assert_true(_restore(runner, world, options), "the source baseline also accounts for later genuine original qi spending")


func _paid_inputs_already_in_flight(runner: Object) -> void:
	var options: Dictionary = {"qi": {"player": 10}}
	var world: RegionalSimulation = Support.make(runner, options)
	if world == null:
		return
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "baseline fixture genuinely restores an incomplete original reserve")
	Support.finish(runner, world)
	runner.assert_true(world.artifacts.begin("player", "charge", "hearth_stone").ok, "subsequent actual artifact action pays its qi before completion")
	runner.assert_eq(world.regions.home.actors.player.qi, 10, "in-flight original action has already paid four qi")
	runner.assert_true(world.advance_to_ms(world.elapsed_ms + 12345), "genuine original paid input remains in flight at save time")
	var resumed: RegionalSimulation = Support.valid_restore(runner, world, options)
	if resumed == null:
		return
	var end: int = int(world.artifacts.active.player.due_ms) + 60000
	runner.assert_true(world.advance_to_ms(end) and resumed.advance_to_ms(end), "original paid action completes from both complete candidates")
	runner.assert_eq(Support.canonical(resumed.to_dict()), Support.canonical(world.to_dict()), "source baseline counts the allocated original action once across its future completion")
	# Establish another baseline while a *different* actor's old action is in
	# flight, proving floors are allocation positions rather than event counts.
	world = Support.make(runner, {"second_stone": true, "qi": {"player": 10, "chen_shouzhuo": 50}})
	if world == null:
		return
	runner.assert_true(world.artifacts.begin("chen_shouzhuo", "charge", "second_stone").ok, "another original action can already be in flight before the first source baseline")
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "source baseline starts alongside an independently allocated old artifact action")
	runner.assert_true(_restore(runner, world, {"second_stone": true, "qi": {"player": 10, "chen_shouzhuo": 50}}), "allocation floors do not confuse an already active unrelated paid action")


func _original_soul_and_teaching_costs(runner: Object) -> void:
	var options: Dictionary = {"qi": {"player": 10, "chen_shouzhuo": 50}}
	var world: RegionalSimulation = Support.make(runner, options)
	if world == null:
		return
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "original soul-cost fixture first earns actual restored qi")
	Support.finish(runner, world)
	var soul_opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/soul_vessels.json"))
	runner.assert_true(world.soul_vessels.spawn_opening(soul_opening), "one actual old ring and resident are assembled through their owner")
	for verb: String in ["take", "wake"]:
		var answer: Dictionary = world.soul_vessels.begin("player", verb, "old_ring")
		runner.assert_true(answer.ok, "real old-ring contact begins after source restoration: " + verb)
		if not answer.ok:
			return
		if verb == "wake":
			runner.assert_eq(world.regions.home.actors.player.qi, 13, "actual in-flight ring wake pays original qi immediately")
			runner.assert_true(_restore(runner, world, options), "source accounting includes genuine allocated in-flight soul cost")
		runner.assert_true(world.advance_to_ms(int(world.soul_vessels.active.player.due_ms)), "real ring contact reaches its original deadline")
	runner.assert_true(_restore(runner, world, options), "completed original soul spending is not counted again")
	world = Support.make(runner, options)
	if world == null:
		return
	var draft: Dictionary = world.heat_methods.compose("chen_shouzhuo", "hearth_stone", "源后示教", 1, 1)
	runner.assert_true(draft.ok, "experienced original operator composes a concrete bounded method")
	if not draft.ok:
		return
	runner.assert_true(world.heat_methods.start("chen_shouzhuo", "hearth_stone", str(draft.method)).ok, "actual trial establishes a teachable original version")
	runner.assert_true(world.advance_to_ms(60000), "method trial completes with real qi and heat")
	runner.assert_true(world.spirit_sources.begin("chen_shouzhuo", "hearth_seam", "body", "hearth_stone").ok, "teacher establishes a genuine source qi baseline")
	Support.finish(runner, world, "chen_shouzhuo")
	var prior: int = int(world.regions.home.actors.chen_shouzhuo.qi)
	var taught: Dictionary = world.heat_methods.teach("chen_shouzhuo", "player", "hearth_stone", str(draft.method))
	runner.assert_true(taught.ok, "source-restored teacher offers actual two-body original practice")
	if not taught.ok:
		return
	runner.assert_eq(world.regions.home.actors.chen_shouzhuo.qi, prior - 1, "teacher's original guidance cost is a real post-baseline debit")
	runner.assert_true(_restore(runner, world, options), "source baseline counts another actor's actual active guide role")
	runner.assert_true(world.advance_to_ms(int(world.artifacts.active.player.due_ms)), "original lesson completes from its actual allocated inputs")
	runner.assert_true(_restore(runner, world, options), "completed guidance changes neither paid amount nor original source credit")


func _original_charge_changes(runner: Object) -> void:
	var options: Dictionary = {"opening_charge": 0}
	var world: RegionalSimulation = Support.make(runner, options)
	if world == null:
		return
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "stone", "hearth_stone").ok, "actual empty stone can receive finite external stored heat")
	Support.finish(runner, world)
	runner.assert_eq(world.spirit_sources.charge_baselines.hearth_stone.charge, 0, "first storage baseline refers to the original empty instance")
	Support.artifact(runner, world, "player", "charge")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 12, "original qi-funded storage still adds real charge after external storage")
	runner.assert_true(_restore(runner, world, options), "source storage baseline includes subsequent actual original charge gains")
	var meals: int = world.regions.home.inventory.quantity("kitchen", "meal")
	Support.artifact(runner, world, "player", "heat")
	runner.assert_eq(world.regions.home.inventory.quantity("kitchen", "meal"), meals + 6, "the same stored heat cooks actual grain and water in the original inventory")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 10, "real original cooking spends two stored units")
	runner.assert_true(_restore(runner, world, options), "source storage accounting accepts original material conversion and exact heat spending")
	Support.artifact(runner, world, "player", "take")
	Support.artifact(runner, world, "player", "warm")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 9, "real original warming spends the same stored heat")
	runner.assert_true(not world.local_heat.receipts.is_empty() and world.local_heat.diagnostics().transient_sources > 0, "spent original heat registers one time-bounded source at the real location")
	runner.assert_true(_restore(runner, world, options), "charge baseline agrees with original warming receipt and heat authority")
	Support.artifact(runner, world, "player", "force")
	runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 0, "original real fracture discards stored heat rather than preserving source credit as a second pool")
	runner.assert_eq(world.artifacts.objects.hearth_stone.damage, 4, "the original unique instance retains the actual fractured structure")
	runner.assert_true(_restore(runner, world, options), "source charge accounting follows original fracture to its exact zero reserve")


func _forged_candidates(runner: Object) -> void:
	var options: Dictionary = {"qi": {"player": 10}, "opening_charge": 0}
	var world: RegionalSimulation = Support.make(runner, options)
	if world == null:
		return
	for target: String in ["body", "stone"]:
		runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", target, "hearth_stone").ok, "tamper fixture has genuine paid source effect: " + target)
		Support.finish(runner, world)
	var saved: Dictionary = JSON.parse_string(Support.canonical(world.to_dict()))
	var original: String = Support.canonical(world.to_dict())
	var body_record: String = ""
	var stone_record: String = ""
	for id: String in saved.spirit_sources.records:
		if saved.spirit_sources.records[id].target == "body":
			body_record = id
		else:
			stone_record = id
	for fault: String in ["free_source", "balanced_overspend", "unreleased_supply", "future_activation", "unknown_source", "free_qi", "free_charge", "missing_body_receipt", "missing_stone_receipt", "wrong_output", "wrong_loss", "future_effect", "duplicate_id", "changed_target", "qi_baseline", "charge_baseline", "bad_floor", "next_id"]:
		var bad: Dictionary = saved.duplicate(true)
		var domain: Dictionary = bad.spirit_sources
		match fault:
			"free_source": domain.sources.hearth_seam.amount = int(domain.sources.hearth_seam.amount) + 1
			"balanced_overspend":
				domain.sources.hearth_seam.amount = int(domain.sources.hearth_seam.amount) + 1
				domain.sources.hearth_seam.spent = int(domain.sources.hearth_seam.spent) - 1
			"unreleased_supply":
				domain.sources.hearth_seam.released = int(domain.sources.hearth_seam.released) + 1
				domain.sources.hearth_seam.amount = int(domain.sources.hearth_seam.amount) + 1
			"future_activation": domain.activation_ms = int(bad.elapsed_ms) + 1
			"unknown_source": domain.sources["invented"] = domain.sources.hearth_seam.duplicate(true)
			"free_qi": bad.regions.home.actors.player.qi = int(bad.regions.home.actors.player.qi) + 1
			"free_charge": bad.artifacts.objects.hearth_stone.charge = int(bad.artifacts.objects.hearth_stone.charge) + 1
			"missing_body_receipt": domain.records.erase(body_record)
			"missing_stone_receipt": domain.records.erase(stone_record)
			"wrong_output": domain.records[body_record].output = int(domain.records[body_record].output) + 1
			"wrong_loss": domain.records[body_record].loss = int(domain.records[body_record].loss) + 1
			"future_effect": domain.records[body_record].finished_ms = int(bad.elapsed_ms) + 1
			"duplicate_id": domain.records["spirit:999"] = domain.records[body_record].duplicate(true)
			"changed_target": domain.records[body_record].target = "stone"
			"qi_baseline": domain.qi_baselines.player.qi = int(domain.qi_baselines.player.qi) + 1
			"charge_baseline": domain.charge_baselines.hearth_stone.charge = int(domain.charge_baselines.hearth_stone.charge) + 1
			"bad_floor": domain.qi_baselines.player.artifact_floor = int(bad.artifacts.next_id) + 1
			"next_id": domain.next_id = 1
		var before_bad: String = Support.canonical(bad)
		runner.assert_true(not world.restore(bad), "complete independent candidate rejects forged source/body/storage: " + fault)
		runner.assert_eq(Support.canonical(world.to_dict()), original, "rejected source candidate leaves every live owner unchanged: " + fault)
		runner.assert_eq(Support.canonical(bad), before_bad, "candidate validation does not repair its malformed input: " + fault)
	runner.assert_true(_restore(runner, world, options), "unmodified genuine source history still independently restores after all rejected candidates")


func _cross_domain_ownership(runner: Object) -> void:
	var options: Dictionary = {"qi": {"player": 10}, "second_stone": true}
	var base: RegionalSimulation = Support.make(runner, options)
	if base == null:
		return
	runner.assert_true(base.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "ownership fixture starts one real source-owned body and tool")
	runner.assert_true(base.advance_to_ms(12345), "ownership snapshot is a genuinely in-flight process")
	var source_snapshot: Dictionary = JSON.parse_string(Support.canonical(base.to_dict()))
	var original: String = Support.canonical(base.to_dict())
	runner.assert_true(_restore(runner, base, options), "nonconflicting in-flight source owners validate")
	for kind: String in ["same_body", "same_tool", "native_body", "duplicate_source_actor", "too_many_reservations"]:
		var other: RegionalSimulation = Support.make(runner, options)
		if other == null:
			return
		runner.assert_true(other.advance_to_ms(12345), "independent comparison domain reaches the exact same original time")
		var bad: Dictionary = source_snapshot.duplicate(true)
		match kind:
			"same_body", "same_tool":
				var actor: String = "player" if kind == "same_body" else "chen_shouzhuo"
				runner.assert_true(other.artifacts.begin(actor, "inspect", "hearth_stone").ok, "conflicting artifact process is itself genuinely allocated before composition")
				bad.artifacts = other.artifacts.to_dict()
			"native_body":
				runner.assert_true(other.regions.home.submit_action("player", "rest"), "conflicting native job is itself genuinely allocated before composition")
				bad.regions.home = other.regions.home.to_dict()
			"duplicate_source_actor":
				var duplicate: Dictionary = bad.spirit_sources.active.player.duplicate(true)
				duplicate.actor = "chen_shouzhuo"
				bad.spirit_sources.active["chen_shouzhuo"] = duplicate
			"too_many_reservations": bad.spirit_sources.sources.hearth_seam.amount = 5
		runner.assert_true(not base.restore(bad), "joint candidate rejects original source ownership conflict: " + kind)
		runner.assert_eq(Support.canonical(base.to_dict()), original, "cross-domain rejection never partly commits a live owner: " + kind)


func _historical_ownership_and_reservations(runner: Object) -> void:
	for conflict: String in ["same_body", "same_stone", "future_refill"]:
		var rules: Dictionary = Support.rules()
		if conflict == "future_refill":
			rules.sources.hearth_seam.initial = 6
			rules.sources.hearth_seam.refill_amount = 6
		var options: Dictionary = {"rules": rules, "second_stone": true, "qi": {"player": 10, "chen_shouzhuo": 50}}
		var world: RegionalSimulation = Support.make(runner, options)
		if world == null:
			return
		runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "history fixture allocates its actual first reservation: " + conflict)
		if conflict == "future_refill":
			Support.finish(runner, world)
			runner.assert_true(world.advance_to_ms(600000), "history fixture waits for a genuinely later replenishment")
		else:
			runner.assert_true(world.advance_to_ms(60000), "history fixture spends a real first partial work interval")
			world.spirit_sources.cancel("player")
		var second_actor: String = "player" if conflict == "same_body" else "chen_shouzhuo"
		var second_object: String = "second_stone" if conflict == "future_refill" else "hearth_stone"
		runner.assert_true(world.spirit_sources.begin(second_actor, "hearth_seam", "body", second_object).ok, "history fixture allocates a genuinely nonoverlapping second reservation: " + conflict)
		runner.assert_true(world.advance_to_ms(world.elapsed_ms + 10000), "history fixture retains an actual second partial work interval")
		world.spirit_sources.cancel(second_actor)
		runner.assert_true(_restore(runner, world, options), "real nonoverlapping/correctly funded cancellation history restores: " + conflict)
		var bad: Dictionary = JSON.parse_string(Support.canonical(world.to_dict()))
		var second: Dictionary = bad.spirit_sources.records["spirit:2"]
		second.started_ms = 10000
		second.due_ms = 130000
		second.finished_ms = 20000
		if second_actor != "player":
			bad.spirit_sources.qi_baselines[second_actor].at_ms = 10000
		var original: String = Support.canonical(world.to_dict())
		runner.assert_true(not world.restore(bad), "history cannot retroactively overlap an original body/tool or borrow later refill for a past reservation: " + conflict)
		runner.assert_eq(Support.canonical(world.to_dict()), original, "rejected forged past preserves actual source history: " + conflict)
	var world: RegionalSimulation = Support.make(runner, {"qi": {"player": 10}})
	if world == null:
		return
	Support.artifact(runner, world, "player", "inspect")
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "history fixture begins source only after its actual original tool action finishes")
	runner.assert_true(world.advance_to_ms(90000), "second original source interval runs after completed inspection")
	world.spirit_sources.cancel("player")
	var good: Dictionary = JSON.parse_string(Support.canonical(world.to_dict()))
	runner.assert_true(_restore(runner, world, {"qi": {"player": 10}}), "ordinary sequential original inspection and source history restores")
	good.spirit_sources.records["spirit:1"].started_ms = 30000
	good.spirit_sources.records["spirit:1"].due_ms = 150000
	good.spirit_sources.qi_baselines.player.at_ms = 30000
	var original: String = Support.canonical(world.to_dict())
	runner.assert_true(not world.restore(good), "completed original tool history still excludes retrospectively overlapping source work")
	runner.assert_eq(Support.canonical(world.to_dict()), original, "past original-tool overlap is atomically rejected")
