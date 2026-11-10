extends RefCounted
## Spirit restoration and casting share original qi. These focused source
## accounting probes separate exact allocation order; real shared bodies also
## prove the first cast/source checkpoint and independent joint continuation.

const Ledger = preload("res://scripts/sim/spirit_source_schema.gd")
const Sources = preload("res://scripts/sim/spirit_sources.gd")
const Support = preload("res://tests/sim/spirit_source_test_support.gd")
const ConflictFixtures = preload("res://tests/sim/test_conflicts.gd")


class Costs extends RefCounted:
	var next_cost_id: int = 1
	var rows: Array[Dictionary] = []

	func qi_spending(_actor: String) -> Array[Dictionary]:
		return rows.duplicate(true)


class OriginalJobs extends RefCounted:
	var next_id: int = 1
	var active: Dictionary = {}
	var events: Array[Dictionary] = []


class Region extends RefCounted:
	var actors: Dictionary = {"player": {"qi": 0}}

	func synchronize_actors() -> Dictionary:
		return actors


class Authority extends RefCounted:
	var elapsed_ms: int = 1000
	var conflicts: Costs = Costs.new()
	var artifacts: OriginalJobs = OriginalJobs.new()
	var soul_vessels: OriginalJobs = OriginalJobs.new()
	var regions: Dictionary = {"home": Region.new()}


class Context extends RefCounted:
	var world: Authority = Authority.new()

	func actor_home(_actor: String) -> String:
		return "home"

	func number(id: String) -> int:
		return SimSpiritSources.number(id)

	func conflict_cost_floor() -> int:
		return world.conflicts.next_cost_id

	func practice_cost_floor() -> int:
		return 1


func run(runner: Object) -> void:
	_same_millisecond_order(runner)
	_baseline_boundary(runner)
	_rejected_spending(runner)
	_legacy_state(runner)
	_actual_cast_first(runner)
	_actual_source_first(runner)
	_actual_zero_qi_weapon(runner)
	_same_ms_source_first(runner)
	print("SCENARIO combat qi ledger: actual cast/source-first checkpoints, zero-qi weapons, independent conversion/cast continuation, same-ms allocation order, explicit legacy floors and rejected forged reserve/spending")


func _learn(runner: Object, world: RegionalSimulation) -> bool:
	var result: Dictionary = world.conflicts.teach("chen_shouzhuo", "player")
	runner.assert_true(result.ok, "original experienced person actually demonstrates the unknown martial methods")
	if not result.ok:
		return false
	return world.advance_to_ms(int(world.conflicts.lessons["conflict:lesson:1"].due_ms))


func _restore_joint(runner: Object, world: RegionalSimulation, label: String) -> RegionalSimulation:
	var before: String = Support.canonical(world.to_dict())
	var restored: RegionalSimulation = Support.valid_restore(runner, world)
	if restored != null:
		runner.assert_eq(Support.canonical(restored.to_dict()), before, label + " retains every original domain through independent JSON restore")
	runner.assert_eq(Support.canonical(world.to_dict()), before, label + " leaves the source world unchanged")
	return restored


func _reject_joint(runner: Object, world: RegionalSimulation, bad: Dictionary, label: String) -> void:
	var candidate: RegionalSimulation = Support.make(runner)
	if candidate == null:
		return
	var before: String = Support.canonical(candidate.to_dict())
	var input: String = Support.canonical(bad)
	var original: String = Support.canonical(world.to_dict())
	runner.assert_true(not candidate.restore(bad), "joint source/casting history rejects " + label)
	runner.assert_eq(Support.canonical(candidate.to_dict()), before, "rejected " + label + " commits no candidate domain")
	runner.assert_eq(Support.canonical(bad), input, "rejected " + label + " is not silently repaired")
	runner.assert_eq(Support.canonical(world.to_dict()), original, "rejected " + label + " changes no original owner")


func _actual_cast_first(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner, {"qi": {"player": 12}})
	if world == null:
		return
	var empty: String = Support.canonical(world.spirit_sources.to_dict())
	runner.assert_true(not world.spirit_sources.ensure_qi_baseline("absent_actor"), "a historical checkpoint requires an actual original body")
	runner.assert_eq(Support.canonical(world.spirit_sources.to_dict()), empty, "invalid checkpoint cannot create a source, reserve or actor record")
	runner.assert_true(not world.conflicts.begin("player", "chen_shouzhuo").ok, "untrained encounter request is rejected before allocating a qi checkpoint")
	runner.assert_true(not world.conflicts.cast("player", "qi_guard", Vector2.RIGHT).ok, "untrained request is rejected before allocating a qi checkpoint")
	world.conflicts.cancel("player")
	runner.assert_true(world.spirit_sources.qi_baselines.is_empty(), "a refused spell creates no historical checkpoint")
	if not _learn(runner, world):
		return
	runner.assert_true(world.conflicts.begin("player", "chen_shouzhuo").ok, "trained player starts an actual encounter without ever drawing source qi")
	var at_ms: int = world.elapsed_ms
	var cost_number: int = world.conflicts.next_cost_id
	var answer: Dictionary = world.conflicts.cast("player", "qi_guard", Vector2.RIGHT)
	runner.assert_true(answer.ok, "first original spell actually pays body qi before any source process")
	if not answer.ok or not world.spirit_sources.qi_baselines.has("player"):
		runner.assert_true(false, "accepted positive-qi cast establishes the shared historical checkpoint")
		return
	var baseline: Dictionary = world.spirit_sources.qi_baselines.player.duplicate(true)
	runner.assert_eq(baseline.at_ms, at_ms, "cast-first checkpoint uses the real spell start")
	runner.assert_eq(baseline.qi, 12, "cast-first checkpoint captures original reserve before debit")
	runner.assert_eq(baseline.conflict_floor, cost_number, "cast-first checkpoint precedes the exact first positive cost allocation")
	runner.assert_eq(world.regions.home.actors.player.qi, 9, "first spell debits the same original twelve-unit reserve")
	runner.assert_true(world.spirit_sources.active.is_empty() and world.spirit_sources.records.is_empty() and world.spirit_sources.next_id == 1, "a casting checkpoint fabricates no source operation or source allocation")
	runner.assert_eq(world.spirit_sources.sources.hearth_seam.spent, 0, "a casting checkpoint consumes no source stock")
	runner.assert_true(world.spirit_sources.ensure_qi_baseline("player"), "original historical checkpoint is reusable")
	runner.assert_eq(Support.canonical(world.spirit_sources.qi_baselines.player), Support.canonical(baseline), "reuse never replaces pre-spend history with the current reserve")
	for fault: String in ["body_qi", "missing_checkpoint", "earlier_checkpoint", "later_checkpoint", "skipped_first_cost", "extra_actor", "boolean_reserve"]:
		var bad: Dictionary = JSON.parse_string(Support.canonical(world.to_dict()))
		match fault:
			"body_qi": bad.regions.home.actors.player.qi += 1
			"missing_checkpoint": bad.spirit_sources.qi_baselines.erase("player")
			"earlier_checkpoint": bad.spirit_sources.qi_baselines.player.at_ms -= 1
			"later_checkpoint": bad.spirit_sources.qi_baselines.player.at_ms += 1
			"skipped_first_cost":
				bad.spirit_sources.qi_baselines.player.conflict_floor = cost_number + 1
				bad.spirit_sources.qi_baselines.player.qi = bad.regions.home.actors.player.qi
			"extra_actor": bad.spirit_sources.qi_baselines.shi_tou = bad.spirit_sources.qi_baselines.player.duplicate(true)
			"boolean_reserve": bad.spirit_sources.qi_baselines.player.qi = true
		_reject_joint(runner, world, bad, "cast-first " + fault)
	_restore_joint(runner, world, "unemitted paid cast with no source history")
	world.conflicts.cancel("player")
	var resumed: RegionalSimulation = _restore_joint(runner, world, "interrupted paid cast with no source history")
	if resumed == null:
		return
	var source_start: int = world.elapsed_ms + 1
	runner.assert_true(world.advance_to_ms(source_start) and resumed.advance_to_ms(source_start), "both real worlds move beyond the initial casting checkpoint")
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "cast-first body subsequently draws from the original finite source")
	runner.assert_true(resumed.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "independently restored caster starts the same actual source operation")
	_restore_joint(runner, world, "cast-first subsequent source in flight")
	var due: int = int(world.spirit_sources.active.player.due_ms)
	runner.assert_true(world.advance_to_ms(due) and resumed.advance_to_ms(due), "both actual source conversions reach the same deadline")
	runner.assert_eq(world.regions.home.actors.player.qi, 13, "source output adds to the original post-cast reserve rather than resetting it")
	runner.assert_eq(Support.canonical(resumed.to_dict()), Support.canonical(world.to_dict()), "cast-first save and subsequent source conversion have exactly the same joint future")
	runner.assert_eq(Support.canonical(world.spirit_sources.qi_baselines.player), Support.canonical(baseline), "later source use preserves the first spell checkpoint")
	runner.assert_true(world.conflicts.begin("player", "chen_shouzhuo").ok, "source-restored body can enter another actual encounter")
	runner.assert_true(world.conflicts.cast("player", "qi_guard", Vector2.RIGHT).ok, "source-restored body pays another real spell cost")
	world.conflicts.cancel("player")
	runner.assert_eq(world.regions.home.actors.player.qi, 10, "original reserve contains one real source credit and two original spell costs")
	_restore_joint(runner, world, "cast then source then later interrupted cast")


func _actual_source_first(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner, {"qi": {"player": 12}})
	if world == null:
		return
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "source-first body begins an actual finite conversion before combat")
	Support.finish(runner, world)
	var baseline: String = Support.canonical(world.spirit_sources.qi_baselines.player)
	var state: Dictionary = world.spirit_sources.to_dict()
	var old: Dictionary = state.duplicate(true)
	old.version = 1
	for row: Dictionary in old.qi_baselines.values():
		runner.assert_eq(row.practice_floor, 1, "modern actual source-first baseline explicitly predates any practice allocation")
		row.erase("conflict_floor")
		row.erase("practice_floor")
	for row: Dictionary in old.records.values():
		runner.assert_eq(row.practice_floor, 1, "modern actual source-first receipt explicitly predates any practice allocation")
		row.erase("conflict_floor")
		row.erase("practice_floor")
	var untouched: String = Support.canonical(old)
	var mixed: Dictionary = state.duplicate(true)
	mixed.qi_baselines.player.erase("practice_floor")
	runner.assert_true(not world.spirit_sources.restore(mixed), "modern source version cannot silently fill a missing original practice floor")
	runner.assert_eq(Support.canonical(world.spirit_sources.to_dict()), Support.canonical(state), "rejected mixed-version modern state changes no live source or original reserve")
	mixed = old.duplicate(true)
	mixed.qi_baselines.player["practice_floor"] = 1
	runner.assert_true(not world.spirit_sources.restore(mixed), "legacy source envelope cannot smuggle a preexisting modern practice field")
	runner.assert_eq(Support.canonical(world.spirit_sources.to_dict()), Support.canonical(state), "rejected forged legacy floor changes no source history")
	runner.assert_true(world.spirit_sources.restore(old), "explicit v1 upgrade still restores an actual source-first history with no combat")
	runner.assert_eq(Support.canonical(world.spirit_sources.to_dict()), Support.canonical(state), "v1 upgrade preserves every original source/checkpoint/receipt value")
	runner.assert_eq(Support.canonical(old), untouched, "v1 restore leaves the original passed history untouched")
	if not _learn(runner, world):
		return
	runner.assert_true(world.conflicts.begin("player", "chen_shouzhuo").ok, "original source-restored person starts the later conflict")
	runner.assert_true(world.conflicts.cast("player", "qi_guard", Vector2.RIGHT).ok, "source-first person pays actual later casting qi")
	world.conflicts.cancel("player")
	runner.assert_eq(Support.canonical(world.spirit_sources.qi_baselines.player), baseline, "casting cannot overwrite the original source-first checkpoint")
	runner.assert_eq(world.regions.home.actors.player.qi, 13, "source-first balance includes its real source gain and later spell debit")
	_restore_joint(runner, world, "source-first then real casting")
	var bad: Dictionary = JSON.parse_string(Support.canonical(world.to_dict()))
	bad.regions.home.actors.player.qi += 1
	_reject_joint(runner, world, bad, "source-first free original qi")


func _actual_zero_qi_weapon(runner: Object) -> void:
	var fixtures: RefCounted = ConflictFixtures.new()
	var swords: Array[String] = ["chen_shouzhuo"]
	var world: RegionalSimulation = fixtures._world(runner, swords)
	if world == null:
		return
	fixtures._pair(world, "chen_shouzhuo", "shi_tou")
	var qi: int = int(world.conflicts.body("chen_shouzhuo").qi)
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok, "actual weapon holder begins a zero-qi encounter")
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "sword", Vector2.RIGHT).ok, "zero-qi method uses the real opening sword and stamina")
	runner.assert_eq(world.conflicts.body("chen_shouzhuo").qi, qi, "zero-qi sword never changes the original qi reserve")
	runner.assert_true(world.spirit_sources.qi_baselines.is_empty(), "zero-qi sword creates no unnecessary qi checkpoint")
	world.conflicts.cancel("chen_shouzhuo")
	_restore_joint(runner, world, "zero-qi sword without any qi checkpoint")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok, "original weapon user starts a later spell encounter")
	var first_positive: int = world.conflicts.next_cost_id
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_guard", Vector2.RIGHT).ok, "first later positive-qi method actually consumes original qi")
	world.conflicts.cancel("chen_shouzhuo")
	if not world.spirit_sources.qi_baselines.has("chen_shouzhuo"):
		runner.assert_true(false, "later positive cost establishes its first checkpoint after zero-qi weapon history")
		return
	runner.assert_eq(world.spirit_sources.qi_baselines.chen_shouzhuo.conflict_floor, first_positive, "first positive checkpoint excludes only the earlier zero-qi allocation")
	_restore_joint(runner, world, "zero-qi sword then first positive spell")


func _same_ms_source_first(runner: Object) -> void:
	var world: RegionalSimulation = Support.make(runner, {"qi": {"player": 12}})
	if world == null or not _learn(runner, world):
		return
	runner.assert_true(world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "same-ms source-first body records the original global cost floor")
	runner.assert_true(world.conflicts.begin("chen_shouzhuo", "shi_tou").ok, "another actual pair can begin conflict while the source body is busy")
	runner.assert_true(world.conflicts.cast("chen_shouzhuo", "qi_guard", Vector2.RIGHT).ok, "another actor allocates a real positive cost in the same millisecond")
	runner.assert_true(world.spirit_sources.cancel("player"), "source-first body actually cancels its unpaid conversion in the same millisecond")
	runner.assert_true(world.conflicts.begin("player", "su_zhi").ok, "released source body starts a separate actual encounter in the same millisecond")
	var own_number: int = world.conflicts.next_cost_id
	runner.assert_true(world.conflicts.cast("player", "qi_guard", Vector2.RIGHT).ok, "released body allocates its own first positive cost after the other actor")
	world.conflicts.cancel("player")
	world.conflicts.cancel("chen_shouzhuo")
	runner.assert_eq(world.spirit_sources.qi_baselines.player.conflict_floor, own_number - 1, "source-first global floor can precede another person's intervening allocation")
	_restore_joint(runner, world, "same-ms source checkpoint before other and own casting costs")
	var bad: Dictionary = JSON.parse_string(Support.canonical(world.to_dict()))
	bad.spirit_sources.qi_baselines.player.conflict_floor = own_number + 1
	bad.spirit_sources.qi_baselines.player.qi = bad.regions.home.actors.player.qi
	_reject_joint(runner, world, bad, "same-ms checkpoint that skips its first positive cost")


func _state(qi: int = 10, at_ms: int = 100, floor_value: int = 1) -> Dictionary:
	return {"qi_baselines": {"player": {"at_ms": at_ms, "qi": qi, "artifact_floor": 1, "soul_floor": 1, "conflict_floor": floor_value, "practice_floor": 1}}, "records": {}}


func _cost(number: int, at_ms: int, amount: int) -> Dictionary:
	return {"domain": "conflict", "number": number, "at_ms": at_ms, "amount": amount}


func _source(id: String, at_ms: int, before: int, output: int, floor_value: int) -> Dictionary:
	return {"id": id, "actor": "player", "target": "body", "result": "success", "finished_ms": at_ms, "before": before, "output": output, "artifact_floor": 1, "soul_floor": 1, "conflict_floor": floor_value, "practice_floor": 1}


func _same_millisecond_order(runner: Object) -> void:
	var context := Context.new()
	var state: Dictionary = _state()
	# Casting allocation 1 commits immediately before source conversion.
	# Allocation 2 at the exact same millisecond commits after conversion.
	context.world.conflicts.rows.assign([_cost(1, 200, 3), _cost(2, 200, 2)])
	context.world.conflicts.next_cost_id = 3
	context.world.regions.home.actors.player.qi = 9
	state.records["spirit:1"] = _source("spirit:1", 200, 7, 4, 2)
	runner.assert_true(Ledger._qi_ledger(state, context), "source receipt separates casts before and after its exact same millisecond by original allocation floor")
	var saved: String = Support.canonical(state)
	var costs: String = Support.canonical(context.world.conflicts.rows)
	runner.assert_true(Ledger._qi_ledger(JSON.parse_string(saved), context), "transport roundtrip retains same-ms source/casting accounting")
	runner.assert_eq(Support.canonical(state), saved, "source accounting does not repair or mutate a receipt")
	runner.assert_eq(Support.canonical(context.world.conflicts.rows), costs, "source accounting does not consume or alter original casting records")
	for changed_floor: int in [1, 3]:
		var bad: Dictionary = state.duplicate(true)
		bad.records["spirit:1"].conflict_floor = changed_floor
		runner.assert_true(not Ledger._qi_ledger(bad, context), "moving the source across a same-ms paid cast is rejected: " + str(changed_floor))
	context.world.regions.home.actors.player.qi = 11
	runner.assert_true(not Ledger._qi_ledger(state, context), "canceling a committed cast cannot refund its already recorded original qi cost")
	context.world.regions.home.actors.player.qi = 9
	state.records["spirit:2"] = _source("spirit:2", 700, 9, 4, 3)
	context.world.regions.home.actors.player.qi = 13
	runner.assert_true(Ledger._qi_ledger(state, context), "a later restoration begins from the reserve after both original casting costs")


func _baseline_boundary(runner: Object) -> void:
	# Arithmetic-only floor probe. Whole-world _baselines separately proves
	# the first operation that was actually entitled to create a checkpoint.
	var context := Context.new()
	context.world.conflicts.rows.assign([_cost(1, 50, 2), _cost(2, 300, 1), _cost(3, 300, 5)])
	context.world.conflicts.next_cost_id = 4
	context.world.regions.home.actors.player.qi = 3
	var state: Dictionary = _state(8, 300, 3)
	runner.assert_true(Ledger._qi_ledger(state, context), "ledger arithmetic excludes only allocations already committed at its supplied checkpoint")
	var wrong: Dictionary = state.duplicate(true)
	wrong.qi_baselines.player.conflict_floor = 2
	runner.assert_true(not Ledger._qi_ledger(wrong, context), "same-ms spending before the first baseline cannot be counted twice")
	wrong = state.duplicate(true)
	wrong.qi_baselines.player.conflict_floor = 4
	runner.assert_true(not Ledger._qi_ledger(wrong, context), "same-ms spending after the first baseline cannot disappear")
	context.world.conflicts.rows[0].at_ms = 301
	runner.assert_true(not Ledger._qi_ledger(state, context), "an allocation claimed before baseline cannot actually have a later timestamp")


func _rejected_spending(runner: Object) -> void:
	for fault: String in ["future", "negative", "fractional", "unallocated", "duplicate", "unknown_domain", "extra_field"]:
		var context := Context.new()
		var state: Dictionary = _state()
		context.world.conflicts.rows.assign([_cost(1, 200, 3)])
		context.world.conflicts.next_cost_id = 2
		context.world.regions.home.actors.player.qi = 7
		match fault:
			"future": context.world.conflicts.rows[0].at_ms = 1001
			"negative": context.world.conflicts.rows[0].amount = -3
			"fractional": context.world.conflicts.rows[0].number = 1.5
			"unallocated": context.world.conflicts.rows[0].number = 2
			"duplicate":
				context.world.conflicts.rows.append(_cost(1, 200, 3))
				context.world.regions.home.actors.player.qi = 4
			"unknown_domain": context.world.conflicts.rows[0].domain = "invented"
			"extra_field": context.world.conflicts.rows[0]["refunded"] = true
		runner.assert_true(not Ledger._qi_ledger(state, context), "source accounting rejects invalid casting spending: " + fault)


func _legacy_state(runner: Object) -> void:
	var archive_path: String = "res://tests/fixtures/session_v34.json"
	var original: String = FileAccess.get_file_as_string(archive_path)
	var archive: Dictionary = JSON.parse_string(original)
	var legacy: Dictionary = archive.continuity.world.spirit_sources
	var before: String = Support.canonical(legacy)
	var upgraded: Dictionary = Sources.upgrade_legacy(legacy)
	runner.assert_eq(upgraded.version, 2, "real v34's finite source history upgrades to casting-aware state version")
	runner.assert_eq(upgraded.rules_version, 1, "casting accounting does not change the finite source content rules")
	for row: Dictionary in upgraded.qi_baselines.values():
		runner.assert_eq(row.conflict_floor, 1, "legacy source baseline starts before the first future conflict allocation")
	for row: Dictionary in upgraded.records.values():
		runner.assert_eq(row.conflict_floor, 1, "legacy conversion receipt predates all new casting allocation")
	var projected: Dictionary = upgraded.duplicate(true)
	projected.version = 1
	for row: Dictionary in projected.qi_baselines.values():
		row.erase("conflict_floor")
	for row: Dictionary in projected.records.values():
		row.erase("conflict_floor")
	runner.assert_eq(Support.canonical(projected), before, "legacy upgrade preserves every source, original reserve, thermal receipt and in-flight field")
	runner.assert_eq(Support.canonical(legacy), before, "legacy upgrade does not mutate the passed archive")
	runner.assert_eq(FileAccess.get_file_as_string(archive_path), original, "genuine v34 fixture remains byte-for-byte unchanged")
	if not legacy.qi_baselines.is_empty():
		var forged: Dictionary = legacy.duplicate(true)
		forged.qi_baselines.values()[0]["conflict_floor"] = 2
		runner.assert_true(Sources.upgrade_legacy(forged).is_empty(), "legacy migration refuses a preexisting forged casting floor instead of overwriting it")
