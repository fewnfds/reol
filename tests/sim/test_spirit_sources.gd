extends RefCounted
## One finite source, two destinations, original bodies and unique stones.

const Support = preload("res://tests/sim/spirit_source_test_support.gd")


class QuietRegion extends RefCounted:
	var places: Dictionary = {"kitchen": {"cell": [10, 10]}}


class EmptyProcessOwner extends RefCounted:
	var events: Array[Dictionary] = []
	var active: Dictionary = {}


class QuietClock extends RefCounted:
	var elapsed_ms: int = 0
	var target_ms: int = 0
	var regions: Dictionary = {"home": QuietRegion.new()}
	var artifacts := EmptyProcessOwner.new()
	var soul_vessels := EmptyProcessOwner.new()


func run(runner: Object) -> void:
	_definitions(runner)
	_last_reserve_and_unique_tool(runner)
	_completion_and_capacity(runner)
	_actual_prerequisites(runner)
	_interruption(runner)
	_supply_and_limits(runner)
	_read_only_knowledge(runner)
	_autonomous_original_choice(runner)
	print("SCENARIO spiritual source: shared last reserve, exclusive original stone, capacity losses, actual capability/custody/health, cancellation and bounded independent replenishment")


func _definitions(runner: Object) -> void:
	runner.assert_true(SimSpiritSources.valid_definitions(Support.rules()), "default finite fire-source definitions validate")
	for fault: String in ["zero_cost", "zero_duration", "tiny_capacity", "too_much_initial", "negative_deep", "fractional_refill", "unknown_phase", "zero_qi", "unknown_field"]:
		var rules: Dictionary = Support.rules()
		match fault:
			"zero_cost": rules.source_cost = 0
			"zero_duration": rules.duration_ms = 0
			"tiny_capacity": rules.sources.hearth_seam.capacity = 5
			"too_much_initial": rules.sources.hearth_seam.initial = 25
			"negative_deep": rules.sources.hearth_seam.deep_supply = -1
			"fractional_refill": rules.sources.hearth_seam.refill_ms = 1.5
			"unknown_phase": rules.sources.hearth_seam.phase = "universal"
			"zero_qi": rules.qi_gain = 0
			"unknown_field": rules["infinite_luck"] = 1
		runner.assert_true(not SimSpiritSources.valid_definitions(rules), "malformed source rule is rejected: " + fault)


func _last_reserve_and_unique_tool(runner: Object) -> void:
	var rules: Dictionary = Support.rules()
	rules.sources.hearth_seam.initial = 6
	rules.sources.hearth_seam.deep_supply = 0
	var options: Dictionary = {"rules": rules, "second_stone": true, "qi": {"player": 0}}
	var world: RegionalSimulation = Support.make(runner, options)
	if world == null:
		return
	var source: Dictionary = world.spirit_sources.sources.hearth_seam
	var stone: Dictionary = world.artifacts.objects.hearth_stone
	var answer: Dictionary = world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone")
	runner.assert_true(answer.ok, "zero-qi person can reserve the actual last six source units")
	if not answer.ok:
		return
	runner.assert_eq(source.amount, 6, "starting work reserves source without spending it early")
	runner.assert_eq(world.regions.home.actors.player.qi, 0, "acceptance does not grant future personal qi")
	runner.assert_eq(stone.charge, 6, "using the stone as a medium does not grant it storage early")
	runner.assert_true(world.spirit_sources.owns_actor("player") and world.spirit_sources.target_in_use("hearth_stone"), "one source action owns its original body and the unique medium")
	var before: String = Support.canonical(world.to_dict())
	runner.assert_true(not world.spirit_sources.begin("chen_shouzhuo", "hearth_seam", "stone", "second_stone").ok, "a different stone and destination cannot overbook the same last source units")
	runner.assert_true(not world.artifacts.begin("chen_shouzhuo", "charge", "hearth_stone").ok, "original artifact work cannot seize another operator's source medium")
	runner.assert_true(not world.regions.home.submit_action("player", "rest"), "native work cannot overlap the source-owned body")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "refused competition does not reroll or partly mutate the world")
	world.spirit_sources.cancel("player")
	runner.assert_eq(source.amount, 6, "cancellation releases the unspent six units")
	runner.assert_true(not world.spirit_sources.owns_actor("player") and not world.spirit_sources.target_in_use("hearth_stone"), "cancellation releases both original owners")
	runner.assert_true(world.spirit_sources.begin("chen_shouzhuo", "hearth_seam", "stone", "second_stone").ok, "another purpose may now reserve the released source")
	var id: String = Support.finish(runner, world, "chen_shouzhuo")
	runner.assert_eq(source.amount, 0, "completed stone storage spends the one actual last batch")
	runner.assert_eq(source.spent, 6, "completed operation has one exact source debit")
	runner.assert_eq(world.artifacts.objects.second_stone.charge, 12, "the selected original second stone receives the output")
	runner.assert_eq(stone.charge, 6, "the unselected medium is not changed")
	runner.assert_eq(world.regions.home.actors.player.qi, 0, "cancelled personal restoration remains absent")
	runner.assert_eq(world.spirit_sources.records[id].output, 6, "record identifies actual accepted storage")
	before = Support.canonical(world.to_dict())
	world.spirit_sources.settle_at_ms(world.elapsed_ms)
	world.spirit_sources.cancel("chen_shouzhuo")
	runner.assert_eq(Support.canonical(world.to_dict()), before, "repeated settlement/cancellation cannot repeat a finished effect")
	runner.assert_true(not world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "depleted source cannot fund another destination")
	world = Support.make(runner, {"second_stone": true, "qi": {"player": 0}})
	if world == null:
		return
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "default source can reserve one bodily restoration")
	runner.assert_true(not world.spirit_sources.begin("chen_shouzhuo", "hearth_seam", "stone", "hearth_stone").ok, "available remaining source does not permit sharing one unique medium")
	runner.assert_true(world.spirit_sources.begin("chen_shouzhuo", "hearth_seam", "stone", "second_stone").ok, "two different original stones may reserve distinct actual batches")
	runner.assert_eq(world.spirit_sources.active.size(), 2, "source supports two genuinely independent bodily processes")
	runner.assert_true(world.advance_to_ms(120000), "both same-time source operations finish on the common clock")
	runner.assert_eq(world.spirit_sources.sources.hearth_seam.spent, 12, "same-time destinations have exactly the joint debit")
	runner.assert_eq(world.regions.home.actors.player.qi, 4, "first original person receives only bodily output")
	runner.assert_eq(world.artifacts.objects.second_stone.charge, 12, "second original destination receives only stored heat")


func _completion_and_capacity(runner: Object) -> void:
	for target: String in ["body", "stone"]:
		var options: Dictionary = {"qi": {"player": 19}, "opening_charge": 11}
		var world: RegionalSimulation = Support.make(runner, options)
		if world == null:
			return
		var answer: Dictionary = world.spirit_sources.begin("player", "hearth_seam", target, "hearth_stone")
		runner.assert_true(answer.ok, "a partially empty original destination accepts an actual batch: " + target)
		if not answer.ok:
			continue
		runner.assert_true(world.advance_to_ms(119999), "actual source process advances to one millisecond before completion")
		runner.assert_eq(world.spirit_sources.sources.hearth_seam.spent, 0, "unfinished labor cannot prepay a completed effect")
		runner.assert_eq(world.regions.home.actors.player.qi, 19, "unfinished source labor leaves original qi untouched")
		runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 11, "unfinished source labor leaves original storage untouched")
		var id: String = Support.finish(runner, world)
		var record: Dictionary = world.spirit_sources.records[id]
		runner.assert_eq(record.result, "success", "destination is accepted only at actual completion")
		runner.assert_eq(record.output, 1, "capacity-limited destination takes only its actual remaining unit")
		runner.assert_eq(record.loss, 3 if target == "body" else 5, "unaccepted conversion output is an explicit loss")
		runner.assert_eq(world.spirit_sources.sources.hearth_seam.spent, 6, "partial acceptance still spends the fixed reserved source batch")
		runner.assert_eq(world.regions.home.actors.player.qi, 20 if target == "body" else 19, "body capacity and unselected owner are respected")
		runner.assert_eq(world.artifacts.objects.hearth_stone.charge, 12 if target == "stone" else 11, "stone capacity and unselected owner are respected")
	var full: RegionalSimulation = Support.make(runner, {"opening_charge": 12})
	if full == null:
		return
	var original: String = Support.canonical(full.to_dict())
	for target: String in ["body", "stone"]:
		runner.assert_true(not full.spirit_sources.begin("player", "hearth_seam", target, "hearth_stone").ok, "a fully occupied destination refuses a new batch: " + target)
	runner.assert_eq(Support.canonical(full.to_dict()), original, "full-capacity refusal leaves source and original targets untouched")


func _actual_prerequisites(runner: Object) -> void:
	for fault: String in ["novice", "distant", "private", "broken", "action_control", "motion_control", "native_work", "artifact_work", "injury", "unknown_source", "unknown_target", "unknown_object"]:
		var world: RegionalSimulation = Support.make(runner, {"known": fault not in ["novice", "injury"], "qi": {"player": 10}})
		if world == null:
			return
		match fault:
			"distant": world.regions.home.set_actor_cell("player", Vector2i(130, 130))
			"private": Support.artifact(runner, world, "chen_shouzhuo", "take")
			"broken":
				world.artifacts.objects.hearth_stone.damage = 4
				world.artifacts.objects.hearth_stone.charge = 0
			"action_control": world.embodiment.release_control("subject:player", "body:player", "action")
			"motion_control": world.embodiment.release_control("subject:player", "body:player", "motion")
			"native_work": runner.assert_true(world.regions.home.submit_action("player", "rest"), "source refusal fixture has actual native work")
			"artifact_work": runner.assert_true(world.artifacts.begin("chen_shouzhuo", "charge", "hearth_stone").ok, "source refusal fixture has actual stone work")
			"injury":
				Support.artifact(runner, world, "player", "heat")
				Support.artifact(runner, world, "player", "study")
				runner.assert_true(world.health.blocks_channeling("player"), "actual original backlash persists despite subsequently learning control")
		world.invalidate_region("home")
		var before: String = Support.canonical(world.to_dict())
		var answer: Dictionary = world.spirit_sources.begin("player", "absent" if fault == "unknown_source" else "hearth_seam", "absent" if fault == "unknown_target" else "body", "absent" if fault == "unknown_object" else "hearth_stone")
		runner.assert_true(not answer.ok, "actual source prerequisites reject: " + fault)
		runner.assert_eq(Support.canonical(world.to_dict()), before, "rejected prerequisite cannot grant a partial effect: " + fault)


func _interruption(runner: Object) -> void:
	for reason: String in ["cancel", "left", "control", "private", "broken", "full"]:
		var world: RegionalSimulation = Support.make(runner, {"qi": {"player": 10}})
		if world == null:
			return
		var answer: Dictionary = world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone")
		runner.assert_true(answer.ok, "interruption fixture begins actual source work: " + reason)
		if not answer.ok:
			continue
		var id: String = str(answer.action)
		runner.assert_true(world.advance_to_ms(12345), "source labor genuinely runs before interruption")
		match reason:
			"cancel": world.spirit_sources.cancel("player")
			"left": world.regions.home.set_actor_cell("player", Vector2i(130, 130))
			"control": world.embodiment.release_control("subject:player", "body:player", "action")
			"private": world.artifacts.objects.hearth_stone.container = "actor:chen_shouzhuo"
			"broken":
				world.artifacts.objects.hearth_stone.damage = 4
				world.artifacts.objects.hearth_stone.charge = 0
			"full": world.regions.home.actors.player.qi = 20
		world.invalidate_region("home")
		runner.assert_true(world.advance_to_ms(120000), "original clock reaches source cancellation or failed completion: " + reason)
		runner.assert_true(not world.spirit_sources.owns_actor("player"), "interrupted source releases its original body: " + reason)
		runner.assert_eq(world.spirit_sources.sources.hearth_seam.spent, 0, "interrupted source spends no batch: " + reason)
		runner.assert_eq(world.spirit_sources.sources.hearth_seam.amount, 12, "interrupted reservation returns to the same finite pool: " + reason)
		runner.assert_eq(world.regions.home.actors.player.qi, 20 if reason == "full" else 10, "interruption does not supply future qi: " + reason)
		runner.assert_true(world.spirit_sources.records[id].result in ["cancelled", "failed"], "interruption retains a concrete unsuccessful process record: " + reason)


func _supply_and_limits(runner: Object) -> void:
	var rules: Dictionary = Support.rules()
	var clock := QuietClock.new()
	clock.elapsed_ms = 1234
	clock.target_ms = 1234
	var source := SimSpiritSources.new()
	runner.assert_true(source.initialize(clock, rules), "source supply initializes against an independent quiet authority")
	runner.assert_eq(source.next_boundary_ms(), 601234, "nonzero activation keeps its own first full refill interval")
	clock.elapsed_ms = 601233
	source.settle_at_ms(clock.elapsed_ms)
	runner.assert_eq(source.sources.hearth_seam.released, 0, "source does not receive a refill one millisecond early")
	clock.elapsed_ms += 1
	source.settle_at_ms(clock.elapsed_ms)
	runner.assert_eq(source.sources.hearth_seam.amount, 13, "one real activation-relative refill enters the finite reservoir")
	clock.elapsed_ms = 1234 + 120 * 600000
	source.settle_at_ms(clock.elapsed_ms)
	var state: Dictionary = source.sources.hearth_seam.duplicate(true)
	runner.assert_eq(state.released, 120, "deep release stops at the actual finite deep supply")
	runner.assert_eq(state.amount, 24, "finite reservoir never exceeds its capacity")
	runner.assert_eq(state.lost, 108, "refills arriving after full capacity are explicitly lost")
	runner.assert_eq(12 + int(state.released), int(state.amount) + int(state.spent) + int(state.lost), "source supply, current quantity, spending and loss have exact conservation")
	runner.assert_eq(source.next_boundary_ms(), SimInventory.MAX_COUNT, "depleted deep supply does not retain periodic wakeups")
	clock.elapsed_ms = SimInventory.MAX_COUNT
	source.settle_at_ms(clock.elapsed_ms)
	runner.assert_eq(source.sources.hearth_seam, state, "arbitrarily longer waiting cannot refill depleted deep supply")
	for offset: int in [30000, 600000, 600001]:
		clock = QuietClock.new()
		clock.elapsed_ms = SimInventory.MAX_COUNT - offset
		clock.target_ms = clock.elapsed_ms
		source = SimSpiritSources.new()
		runner.assert_true(source.initialize(clock, rules), "near-limit source initializes at its actual nonzero present")
		clock.elapsed_ms = SimInventory.MAX_COUNT
		source.settle_at_ms(clock.elapsed_ms)
		@warning_ignore("integer_division")
		var expected: int = offset / 600000
		runner.assert_eq(source.sources.hearth_seam.released, expected, "final maximum timestamp is not a fabricated early refill: %d" % offset)
		runner.assert_eq(source.last_ms, SimInventory.MAX_COUNT, "source accounts for its actual final elapsed interval")
		var snapshot: Dictionary = source.to_dict()
		for full_precision: bool in [false, true]:
			var decoded: Dictionary = JSON.parse_string(JSON.stringify(snapshot, "", true, full_precision))
			var restored := SimSpiritSources.new()
			runner.assert_true(restored.initialize(clock, rules) and restored.restore(decoded), "near-limit source roundtrips actual JSON without integer drift")
			runner.assert_eq(Support.canonical(restored.to_dict()), Support.canonical(snapshot), "restored maximum timestamps and count sentinels retain exact integers")
	var partial: Dictionary = Support.rules()
	partial.sources.hearth_seam.initial = 0
	partial.sources.hearth_seam.deep_supply = 5
	partial.sources.hearth_seam.refill_amount = 3
	clock = QuietClock.new()
	source = SimSpiritSources.new()
	runner.assert_true(source.initialize(clock, partial), "a nonmultiple finite deep supply has an explicit bounded definition")
	clock.elapsed_ms = 1200000
	source.settle_at_ms(clock.elapsed_ms)
	runner.assert_eq(source.sources.hearth_seam.released, 5, "the last partial deep release supplies only the genuinely remaining two units")
	runner.assert_eq(source.sources.hearth_seam.amount, 5, "partial final release cannot round up to an extra full batch")
	runner.assert_eq(source.next_boundary_ms(), SimInventory.MAX_COUNT, "partial final deep release exhausts periodic source work")
	var final_world: RegionalSimulation = Support.make(runner, {"at_ms": SimInventory.MAX_COUNT - 100000, "qi": {"player": 0}})
	if final_world != null:
		var before: String = Support.canonical(final_world.to_dict())
		runner.assert_true(not final_world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "near maximum time cannot schedule a complete duration beyond the supported world")
		runner.assert_eq(Support.canonical(final_world.to_dict()), before, "rejected final-time operation creates no source reservation, baseline or target benefit")


func _read_only_knowledge(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner)
	if world == null:
		return
	var before: String = Support.canonical(world.to_dict())
	for _index: int in 4:
		for actor: String in ["player", "chen_shouzhuo", "river_player"]:
			var description: Dictionary = world.spirit_sources.describe(actor, "hearth_seam")
			for hidden: String in ["amount", "released", "spent", "lost", "capacity", "deep_supply", "available"]:
				runner.assert_true(not description.has(hidden), "ordinary source projection omits hidden accounting: " + actor + "/" + hidden)
			world.spirit_sources.status(actor)
	runner.assert_eq(Support.canonical(world.to_dict()), before, "source observation does not advance time, reserve resources or teach ability")


func _autonomous_original_choice(runner: Object) -> void:
	var options: Dictionary = {"services": true, "qi": {"chen_shouzhuo": 0}, "profiles": {"chen_shouzhuo": {"autonomous": true, "duty": ""}}}
	var world: RegionalSimulation = Support.make(runner, options)
	if world == null:
		return
	runner.assert_true(world.advance_to_ms(50), "real autonomous decision reaches the original person's first idle boundary")
	runner.assert_true(world.spirit_sources.owns_actor("chen_shouzhuo"), "trained and idle original NPC independently chooses finite restoration near its actual source")
	if not world.spirit_sources.owns_actor("chen_shouzhuo"):
		return
	runner.assert_true(world.spirit_sources.previous_autonomy("chen_shouzhuo"), "source process remembers the original voluntary autonomy")
	var id: String = str(world.spirit_sources.active.chen_shouzhuo.id)
	runner.assert_eq(world.spirit_sources.active.chen_shouzhuo.target, "body", "autonomous restoration requests the same real bodily target")
	runner.assert_eq(world.regions.home.actors.chen_shouzhuo.qi, 0, "independent decision grants no unfinished benefit")
	var resumed: RegionalSimulation = Support.valid_restore(runner, world, options)
	if resumed == null:
		return
	runner.assert_true(world.advance_to_ms(120050) and resumed.advance_to_ms(120050), "autonomous source process continues while the player is absent")
	runner.assert_eq(world.spirit_sources.records[id].result, "success", "autonomous process pays the same original finite source cost")
	runner.assert_eq(world.regions.home.actors.chen_shouzhuo.qi, 4, "autonomous process restores the original NPC's body")
	runner.assert_true(world.regions.home.actors.chen_shouzhuo.autonomous, "actual completion restores voluntary daily behavior")
	runner.assert_eq(Support.canonical(world.to_dict()), Support.canonical(resumed.to_dict()), "autonomous source and original NPC have one whole restored future")
	for priority: String in ["hunger", "energy", "institution_duty", "distance"]:
		var setup: Dictionary = options.duplicate(true)
		if priority in ["hunger", "energy"]:
			setup.profiles.chen_shouzhuo[priority] = 10.0
		elif priority == "institution_duty":
			setup.profiles.chen_shouzhuo.duty = "inspect"
		world = Support.make(runner, setup)
		if world == null:
			return
		if priority == "distance":
			world.regions.home.set_actor_cell("chen_shouzhuo", Vector2i(130, 130))
			world.invalidate_region("home")
		runner.assert_true(world.advance_to_ms(50), "autonomous priority fixture reaches a genuine decision: " + priority)
		runner.assert_true(not world.spirit_sources.owns_actor("chen_shouzhuo"), "source intention cannot seize a higher original need/duty or remote body: " + priority)
		runner.assert_eq(world.regions.home.actors.chen_shouzhuo.qi, 0, "unselected source intention never restores original qi: " + priority)
		runner.assert_eq(world.spirit_sources.sources.hearth_seam.spent, 0, "unselected source intention has no source debit: " + priority)
