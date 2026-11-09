extends RefCounted
## Simulation fixture uses original domains and real actions. Repositioning and
## adversarial state changes below are controlled probes, not ordinary play.

const Fixtures = preload("res://tests/sim/test_settlement_services.gd")
const Field = preload("res://tests/sim/test_field_opportunities.gd")
const RING: String = "stele_drawing_ring"
const SWORD: String = "training_sword"
const PRIVATE_SWORD: String = "river_training_sword"
const CENTERS: Dictionary = {"home": Vector2i(100, 100), "river": Vector2i(150, 100)}
var _fixtures := Fixtures.new()


func run(runner: Object) -> void:
	_research_and_first_qi_checkpoint(runner)
	_individual_research_prerequisites(runner)
	_draw_exact_time_and_locks(runner)
	_draw_cancel_and_npc(runner)
	_geometry_and_changed_state(runner)
	_independent_candidates(runner)
	_custody_history(runner)
	_source_first_floor(runner)
	print("SCENARIO drawing: personal shape and paid research, one original loose sword, exact shared-time transfer, dual locks, bounded geometry, original qi ledger and independent candidate validation")


func _world(runner: Object) -> RegionalSimulation:
	var world: RegionalSimulation = _fixtures._make_world(runner)
	if world == null:
		return null
	world.bind_map_data(Field.FieldMap.new())
	var opening: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/scenarios/artifacts.json"))
	# These are the same two declarations made by the ordinary scene bootstrap;
	# no object is added after the original artifact assembler has run.
	opening.objects.append({"id": SWORD, "definition": "wooden_sword", "region": "home", "container": "dorm"})
	opening.objects.append({"id": PRIVATE_SWORD, "definition": "wooden_sword", "region": "river", "container": "actor:river_chen_shouzhuo"})
	if not world.artifacts.spawn_opening(opening) or not world.field_opportunities.spawn_opening(CENTERS):
		runner.assert_true(false, "fixture assembles the declared original swords, unique ring and real field site")
		return null
	return world


func _put(world: RegionalSimulation, actor: String, cell: Vector2i) -> void:
	var home: String = world.artifacts.actor_home(actor)
	world.regions[home].set_actor_cell(actor, cell)
	world.invalidate_region(home)


func _at_site(world: RegionalSimulation, actor: String) -> void:
	_put(world, actor, SimRouteTravel.cell(world.field_opportunities.sites.broken_stele.cell))


func _at_sword(world: RegionalSimulation, actor: String, distance: int = 4) -> void:
	_put(world, actor, world.artifacts.object_cell(SWORD) + Vector2i(distance, 0))


func _action(runner: Object, world: RegionalSimulation, actor: String, verb: String, object_id: String = RING) -> bool:
	var reply: Dictionary = world.artifacts.begin(actor, verb, object_id)
	runner.assert_true(bool(reply.ok), "real artifact action starts: " + actor + "/" + verb + " " + str(reply))
	if not bool(reply.ok):
		return false
	return _finish(runner, world, actor)


func _finish(runner: Object, world: RegionalSimulation, actor: String) -> bool:
	if not world.artifacts.active.has(actor):
		runner.assert_true(false, "a real active artifact process is required before completion")
		return false
	var reached: bool = world.advance_to_ms(int(world.artifacts.active[actor].due_ms))
	runner.assert_true(reached, "the original shared clock reaches the operation deadline")
	return reached


func _learn(runner: Object, world: RegionalSimulation, actor: String = "player") -> bool:
	_at_site(world, actor)
	if not _action(runner, world, actor, "study") or not _action(runner, world, actor, "take"):
		return false
	if not _action(runner, world, actor, "use_research"):
		return false
	var learned: bool = world.artifacts.learned_use(actor, RING)
	runner.assert_true(learned, actor + " personally learns use only from the completed research")
	return learned


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))


func _restore(runner: Object, world: RegionalSimulation, label: String) -> RegionalSimulation:
	var saved: String = _json(world.to_dict())
	# Restore reconstructs the saved site and objects. A new game's field-site
	# search is unrelated to this candidate and must not run before each load.
	var candidate: RegionalSimulation = _fixtures._make_world(runner)
	if candidate == null:
		return null
	candidate.bind_map_data(world.map_data.independent_copy())
	var accepted: bool = candidate.restore(JSON.parse_string(saved))
	runner.assert_true(accepted, label + " accepts an independently assembled whole-world candidate")
	if not accepted:
		return null
	runner.assert_eq(_json(candidate.to_dict()), saved, label + " preserves all bodies, unique objects, events and costs")
	return candidate


func _reject(runner: Object, world: RegionalSimulation, bad: Dictionary, label: String) -> void:
	var candidate: RegionalSimulation = _fixtures._make_world(runner)
	if candidate == null:
		return
	candidate.bind_map_data(world.map_data.independent_copy())
	var before: String = _json(candidate.to_dict())
	var input: String = _json(bad)
	runner.assert_true(not candidate.restore(bad), label + " is rejected by an independent whole-world candidate")
	runner.assert_eq(_json(candidate.to_dict()), before, label + " leaves the target world unchanged")
	runner.assert_eq(_json(bad), input, label + " never repairs the supplied data")


func _research_and_first_qi_checkpoint(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	var domain: SimArtifacts = world.artifacts
	_at_site(world, "player")
	runner.assert_true(not domain.learned_use("player", RING), "seeing the ring gives no personal use")
	runner.assert_true(not domain.begin("player", "use_research", RING).ok, "research requires prior personal shape study and custody")
	if not _action(runner, world, "player", "study"):
		return
	runner.assert_true(domain.shape_studied("player", RING) and not domain.learned_use("player", RING), "the old studied shape is preserved without teaching use")
	runner.assert_true(not domain.begin("player", "use_research", RING).ok, "shape knowledge cannot research another person's or a loose ring")
	runner.assert_true(not domain.begin_draw("player", RING, SWORD).ok, "shape knowledge alone cannot draw")
	if not _action(runner, world, "player", "take"):
		return
	runner.assert_true(not domain.learned_use("chen_shouzhuo", RING), "another person's inspection does not transfer mastery")
	var qi: int = int(world.regions.home.actors.player.qi)
	var first: int = int(domain.next_id)
	var started_ms: int = int(world.elapsed_ms)
	runner.assert_true(world.spirit_sources.qi_baselines.is_empty(), "old zero-qi ring shape and taking did not create a source checkpoint")
	var reply: Dictionary = domain.begin("player", "use_research", RING)
	runner.assert_true(bool(reply.ok), "holder starts actual personal use research")
	if not bool(reply.ok):
		return
	runner.assert_eq(int(domain.active.player.due_ms), started_ms + 120000, "use research spends two actual minutes")
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi - 2, "research commits exactly two original qi at start")
	var baseline: Dictionary = world.spirit_sources.qi_baselines.get("player", {})
	runner.assert_true(not baseline.is_empty(), "first positive ring consumption establishes the original source checkpoint")
	if not baseline.is_empty():
		runner.assert_eq(int(baseline.at_ms), started_ms, "first paid ring action checkpoints at its actual start")
		runner.assert_eq(int(baseline.qi), qi, "checkpoint sees original qi before the debit")
		runner.assert_eq(int(baseline.artifact_floor), first, "original artifact floor includes this first paid allocation")
	runner.assert_true(world.advance_to_ms(started_ms + 119999), "research reaches one millisecond before completion")
	runner.assert_true(not domain.learned_use("player", RING), "unfinished research grants no use")
	var resumed: RegionalSimulation = _restore(runner, world, "paid unfinished research")
	if resumed != null:
		runner.assert_true(world.advance_to_ms(started_ms + 120000) and resumed.advance_to_ms(started_ms + 120000), "both actual research timelines reach the deadline")
		runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "restored research reaches the identical complete future")
	else:
		world.advance_to_ms(started_ms + 120000)
	runner.assert_true(domain.learned_use("player", RING) and not domain.learned_use("chen_shouzhuo", RING), "only the personally completed research grants use")
	runner.assert_eq(domain.events.back().kind, "use_learned", "actual completed research keeps its distinct evidence")
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi - 2, "completion does not repeat the original qi debit")
	_restore(runner, world, "completed personal research and first consumption")
	var cancelled: RegionalSimulation = _world(runner)
	if cancelled == null:
		return
	_at_site(cancelled, "player")
	if not _action(runner, cancelled, "player", "study") or not _action(runner, cancelled, "player", "take"):
		return
	var before_qi: int = int(cancelled.regions.home.actors.player.qi)
	var start: int = int(cancelled.elapsed_ms)
	runner.assert_true(cancelled.artifacts.begin("player", "use_research", RING).ok, "separate research truly starts before cancellation")
	runner.assert_true(cancelled.advance_to_ms(start + 60000) and cancelled.artifacts.cancel("player"), "research is interrupted after an actual minute")
	runner.assert_true(cancelled.advance_to_ms(start + 120000), "the abandoned deadline passes")
	runner.assert_true(not cancelled.artifacts.learned_use("player", RING), "cancelled research never produces use knowledge")
	runner.assert_eq(int(cancelled.regions.home.actors.player.qi), before_qi - 2, "cancelled research does not refund committed qi")
	runner.assert_eq(cancelled.artifacts.events.back().kind, "cancelled", "cancelled research records its actual outcome")
	_restore(runner, cancelled, "cancelled paid research")


func _individual_research_prerequisites(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_at_site(world, "player")
	_at_site(world, "chen_shouzhuo")
	if not _action(runner, world, "player", "study") or not _action(runner, world, "chen_shouzhuo", "take"):
		return
	runner.assert_true(world.artifacts.shape_studied("player", RING) and not world.artifacts.shape_studied("chen_shouzhuo", RING), "the real holder cannot inherit someone else's shape study")
	var qi: int = int(world.regions.home.actors.chen_shouzhuo.qi)
	var next_id: int = int(world.artifacts.next_id)
	runner.assert_true(not world.artifacts.begin("chen_shouzhuo", "use_research", RING).ok, "holding a ring studied only by someone else cannot start research")
	runner.assert_eq(int(world.regions.home.actors.chen_shouzhuo.qi), qi, "unqualified personal research spends no qi")
	runner.assert_eq(int(world.artifacts.next_id), next_id, "unqualified personal research creates no job")
	if not _action(runner, world, "chen_shouzhuo", "study"):
		return
	# Insufficient reserve is a controlled pre-checkpoint fixture condition.
	world.regions.home.actors.chen_shouzhuo.qi = 1
	world.invalidate_region("home")
	next_id = int(world.artifacts.next_id)
	runner.assert_true(not world.artifacts.begin("chen_shouzhuo", "use_research", RING).ok, "actual shape and custody do not bypass insufficient original qi")
	runner.assert_eq(int(world.regions.home.actors.chen_shouzhuo.qi), 1, "insufficient-qi refusal is atomic")
	runner.assert_eq(int(world.artifacts.next_id), next_id, "insufficient-qi refusal allocates no action")
	runner.assert_true(not world.spirit_sources.qi_baselines.has("chen_shouzhuo"), "refused research cannot create a source checkpoint")


func _draw_exact_time_and_locks(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn(runner, world):
		return
	_at_sword(world, "player", 4)
	_put(world, "chen_shouzhuo", world.artifacts.object_cell(SWORD))
	var domain: SimArtifacts = world.artifacts
	var original: Dictionary = domain.objects[SWORD].duplicate(true)
	var qi: int = int(world.regions.home.actors.player.qi)
	var start: int = int(world.elapsed_ms)
	var reply: Dictionary = domain.begin_draw("player", RING, SWORD)
	runner.assert_true(bool(reply.ok), "a learned holder starts drawing the real loose sword")
	if not bool(reply.ok):
		return
	var job: Dictionary = domain.active.player
	runner.assert_eq(int(job.due_ms), start + 2000, "drawing takes exactly two shared seconds")
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi - 2, "drawing commits exactly two original qi")
	runner.assert_eq(job.draw.target, SWORD, "job records the same unique target")
	runner.assert_eq(job.draw.from_region, original.region, "job records the target's original registrar")
	runner.assert_eq(job.draw.from_container, original.container, "job records the target's actual loose container")
	runner.assert_true(domain.target_in_use(RING) and domain.target_in_use(SWORD), "one draw locks both real objects")
	runner.assert_true(not domain.begin("chen_shouzhuo", "take", SWORD).ok, "another body cannot take the locked target")
	runner.assert_true(not domain.begin("chen_shouzhuo", "inspect", RING).ok, "another body cannot use the locked tool")
	runner.assert_eq(domain.objects[SWORD], original, "starting and contending never transfer the sword early")
	runner.assert_true(world.advance_to_ms(start + 1999), "actual draw reaches one millisecond before completion")
	runner.assert_eq(domain.objects[SWORD], original, "target remains in the same original container one millisecond early")
	var resumed: RegionalSimulation = _restore(runner, world, "two-object draw one millisecond before completion")
	if resumed != null:
		runner.assert_true(world.advance_to_ms(start + 2000) and resumed.advance_to_ms(start + 2000), "both actual draws reach the same deadline")
		runner.assert_eq(_json(resumed.to_dict()), _json(world.to_dict()), "restored draw produces the identical complete future")
	else:
		world.advance_to_ms(start + 2000)
	runner.assert_eq(domain.objects[SWORD], {"definition": "wooden_sword", "region": "home", "container": "actor:player"}, "only the original sword moves into the original holder's custody")
	runner.assert_eq(domain.events.back().kind, "drawn", "the real transfer creates one drawn event")
	runner.assert_eq(domain.events.back().draw, job.draw, "completed event retains exact actual source and caster metadata")
	runner.assert_true(not domain.target_in_use(RING) and not domain.target_in_use(SWORD), "completion releases both object locks")
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi - 2, "completion cannot charge twice")
	var done: String = _json(world.to_dict())
	world.advance_to_ms(start + 2000)
	runner.assert_eq(_json(world.to_dict()), done, "settling the same boundary cannot duplicate the transfer")
	_restore(runner, world, "completed draw and shared qi account")


func _draw_cancel_and_npc(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn(runner, world):
		return
	_at_sword(world, "player")
	_put(world, "chen_shouzhuo", world.artifacts.object_cell(SWORD))
	var original: Dictionary = world.artifacts.objects[SWORD].duplicate(true)
	var qi: int = int(world.regions.home.actors.player.qi)
	var start: int = int(world.elapsed_ms)
	runner.assert_true(world.artifacts.begin_draw("player", RING, SWORD).ok, "separate draw really starts before cancellation")
	runner.assert_true(world.advance_to_ms(start + 1000) and world.artifacts.cancel("player"), "the original actor cancels after one real second")
	runner.assert_eq(world.artifacts.objects[SWORD], original, "cancelled drawing leaves the same loose target")
	runner.assert_eq(int(world.regions.home.actors.player.qi), qi - 2, "cancellation keeps the committed qi")
	runner.assert_true(not world.artifacts.target_in_use(RING) and not world.artifacts.target_in_use(SWORD), "cancellation releases both locks")
	runner.assert_true(world.artifacts.begin("chen_shouzhuo", "take", SWORD).ok, "another body can use the released actual target")
	world.artifacts.cancel("chen_shouzhuo")
	runner.assert_true(world.advance_to_ms(start + 2000), "cancelled draw's old deadline passes")
	runner.assert_eq(world.artifacts.objects[SWORD], original, "abandoned deadline cannot transfer the target")
	_restore(runner, world, "cancelled draw and released target")
	var npc: RegionalSimulation = _world(runner)
	if npc == null or not _learn(runner, npc, "chen_shouzhuo"):
		return
	_at_sword(npc, "chen_shouzhuo")
	var npc_qi: int = int(npc.regions.home.actors.chen_shouzhuo.qi)
	runner.assert_true(npc.artifacts.begin_draw("chen_shouzhuo", RING, SWORD).ok, "NPC uses the same public draw operation")
	if npc.artifacts.active.has("chen_shouzhuo"):
		_finish(runner, npc, "chen_shouzhuo")
		runner.assert_eq(npc.artifacts.objects[SWORD].container, "actor:chen_shouzhuo", "NPC receives the same original target only after completion")
		runner.assert_eq(int(npc.regions.home.actors.chen_shouzhuo.qi), npc_qi - 2, "NPC pays the same original qi cost")
		runner.assert_true(not npc.artifacts.learned_use("player", RING), "NPC research does not teach the player")
		_restore(runner, npc, "NPC personally researched and drew the original sword")


func _geometry_and_changed_state(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn(runner, world):
		return
	var domain: SimArtifacts = world.artifacts
	var map: Field.FieldMap = world.map_data as Field.FieldMap
	var target: Vector2i = domain.object_cell(SWORD)
	_at_sword(world, "player", 7)
	var before_qi: int = int(world.regions.home.actors.player.qi)
	var next_id: int = int(domain.next_id)
	runner.assert_true(not domain.begin_draw("player", RING, SWORD).ok, "seven tiles is outside the six-tile drawing range")
	_at_sword(world, "player", 6)
	map.cover[target + Vector2i(1, 0)] = true
	runner.assert_true(not domain.begin_draw("player", RING, SWORD).ok, "intervening solid terrain blocks drawing at the boundary")
	map.cover.clear()
	map.levels[target] = 1
	runner.assert_true(not domain.begin_draw("player", RING, SWORD).ok, "a target on a different height cannot be drawn")
	map.levels.clear()
	_put(world, "river_chen_shouzhuo", target + Vector2i(5, 0))
	runner.assert_true(not domain.begin_draw("player", RING, PRIVATE_SWORD).ok, "another person's held sword cannot be drawn")
	runner.assert_true(not domain.begin_draw("player", RING, "hearth_stone").ok, "the existing thermal artifact is not this loose small-sword target")
	runner.assert_eq(int(world.regions.home.actors.player.qi), before_qi, "invalid target or geometry spends no qi")
	runner.assert_eq(int(domain.next_id), next_id, "invalid target or geometry allocates no artifact job")
	runner.assert_true(domain.begin_draw("player", RING, SWORD).ok, "clear same-level target at exactly six tiles is reachable")
	if domain.active.has("player"):
		domain.cancel("player")
	for fault: String in ["cover", "height", "control", "moved", "target_changed"]:
		var probe: RegionalSimulation = _world(runner)
		if probe == null or not _learn(runner, probe):
			return
		_at_sword(probe, "player")
		var original: Dictionary = probe.artifacts.objects[SWORD].duplicate(true)
		var qi: int = int(probe.regions.home.actors.player.qi)
		var start: int = int(probe.elapsed_ms)
		if not probe.artifacts.begin_draw("player", RING, SWORD).ok:
			runner.assert_true(false, "changed-state probe starts a real draw: " + fault)
			continue
		match fault:
			"cover": (probe.map_data as Field.FieldMap).cover[probe.artifacts.object_cell(SWORD) + Vector2i(1, 0)] = true
			"height": (probe.map_data as Field.FieldMap).levels[probe.artifacts.object_cell(SWORD)] = 1
			"control": probe.embodiment.release_control("subject:player", "body:player", "action")
			"moved": _at_sword(probe, "player", 3)
			"target_changed": probe.artifacts.objects[SWORD].container = "actor:chen_shouzhuo"
		probe.invalidate_region("home")
		runner.assert_true(probe.advance_to_ms(start + 2000), "changed-state probe reaches cancellation or completion: " + fault)
		var expected: Dictionary = original.duplicate(true)
		if fault == "target_changed": expected.container = "actor:chen_shouzhuo"
		runner.assert_eq(probe.artifacts.objects[SWORD], expected, "changed " + fault + " cannot transfer or duplicate the target")
		runner.assert_eq(int(probe.regions.home.actors.player.qi), qi - 2, "changed " + fault + " retains the original committed cost")
		runner.assert_true(not probe.artifacts.active.has("player") and probe.artifacts.events.back().kind in ["failed", "cancelled"], "changed " + fault + " ends with a truthful failed or cancelled record")


func _independent_candidates(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn(runner, world):
		return
	_at_sword(world, "player")
	if not world.artifacts.begin_draw("player", RING, SWORD).ok:
		runner.assert_true(false, "candidate probes require a real paid in-flight draw")
		return
	var good: Dictionary = JSON.parse_string(_json(world.to_dict()))
	_restore(runner, world, "real draw candidate before adversarial edits")
	for fault: String in ["missing_draw", "extra_draw", "unknown_target", "same_object", "wrong_type", "source_region", "source_container", "source_cell", "caster_position", "free_qi", "duration", "missing_baseline", "refunded_qi", "skipped_floor"]:
		var bad: Dictionary = good.duplicate(true)
		match fault:
			"missing_draw": bad.artifacts.active.player.erase("draw")
			"extra_draw": bad.artifacts.active.player.draw["second_target"] = SWORD
			"unknown_target": bad.artifacts.active.player.draw.target = "missing_sword"
			"same_object": bad.artifacts.active.player.draw.target = RING
			"wrong_type": bad.artifacts.active.player.draw.target = "hearth_stone"
			"source_region": bad.artifacts.active.player.draw.from_region = "river"
			"source_container": bad.artifacts.active.player.draw.from_container = "actor:chen_shouzhuo"
			"source_cell": bad.artifacts.active.player.draw.from_cell = [0, 0]
			"caster_position": bad.artifacts.active.player.draw.caster_position = [0, 0]
			"free_qi": bad.artifacts.active.player.qi_spent = 0
			"duration": bad.artifacts.active.player.due_ms += 1
			"missing_baseline": bad.spirit_sources.qi_baselines.erase("player")
			"refunded_qi": bad.regions.home.actors.player.qi += 2
			"skipped_floor":
				bad.spirit_sources.qi_baselines.player.artifact_floor = int(bad.artifacts.next_id)
				bad.spirit_sources.qi_baselines.player.qi = int(bad.regions.home.actors.player.qi)
		_reject(runner, world, bad, "in-flight drawing " + fault)


func _custody_history(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null or not _learn(runner, world):
		return
	_at_sword(world, "player", 0)
	if not _action(runner, world, "player", "take", SWORD) or not _action(runner, world, "player", "place", SWORD):
		return
	var source_cell: Vector2i = world.artifacts.object_cell(SWORD)
	_at_sword(world, "player", 2)
	if not world.artifacts.begin_draw("player", RING, SWORD).ok:
		runner.assert_true(false, "custody history begins a real draw after taking and replacing the same sword")
		return
	_restore(runner, world, "actual take, place and in-flight draw custody history")
	var forged: Dictionary = JSON.parse_string(_json(world.to_dict()))
	var kitchen: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
	forged.artifacts.objects[SWORD].container = "kitchen"
	forged.artifacts.active.player.draw.from_container = "kitchen"
	forged.artifacts.active.player.draw.from_cell = [kitchen.x, kitchen.y]
	_reject(runner, world, forged, "invented origin contradicts the actual earlier sword placement despite matching current target and nearby geometry")
	if not _finish(runner, world, "player"):
		return
	var completed: Dictionary = JSON.parse_string(_json(world.to_dict()))
	_restore(runner, world, "actual completed draw after a prior sword placement")
	for fault: String in ["current_container", "historical_cell", "effect_region", "caster_cell"]:
		forged = completed.duplicate(true)
		var index: int = forged.artifacts.events.size() - 1
		match fault:
			"current_container": forged.artifacts.objects[SWORD].container = "kitchen"
			"historical_cell": forged.artifacts.events[index].draw.from_cell = [source_cell.x, source_cell.y - 1]
			"effect_region": forged.artifacts.events[index].effect_region = "river"
			"caster_cell": forged.artifacts.events[index].cell = [source_cell.x, source_cell.y]
		_reject(runner, world, forged, "completed draw custody " + fault)
	if not _action(runner, world, "player", "place", SWORD):
		return
	runner.assert_eq(world.artifacts.objects[SWORD].container, "dorm", "a later real placement legitimately changes current custody again")
	_restore(runner, world, "actual later placement follows and does not rewrite the earlier draw")
	# Past sight is historical evidence. A wall added only after the completed
	# transfer must not be used to retroactively cancel that earlier event.
	var added_wall: Vector2i = source_cell + Vector2i(1, 0)
	var changed_cells: Array[Vector2i] = [added_wall]
	runner.assert_true(world.environment_fields.before_topology_change(world.elapsed_ms, changed_cells), "later cover prepares the existing environment before terrain publication")
	(world.map_data as Field.FieldMap).cover[added_wall] = true
	world.map_data.terrain_changed.emit(changed_cells)
	_restore(runner, world, "later cover does not rejudge a completed draw's historical sight")


func _source_first_floor(runner: Object) -> void:
	var world: RegionalSimulation = _world(runner)
	if world == null:
		return
	_put(world, "player", world.artifacts.object_cell("hearth_stone"))
	if not _action(runner, world, "player", "study", "hearth_stone"):
		return
	var source: Dictionary = world.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone")
	runner.assert_true(bool(source.ok), "real original source operation establishes an earlier checkpoint")
	if not bool(source.ok):
		return
	var baseline: String = _json(world.spirit_sources.qi_baselines.player)
	runner.assert_true(world.spirit_sources.cancel("player"), "source work can release the original body without a conversion")
	if not _learn(runner, world):
		return
	_at_sword(world, "player")
	runner.assert_true(world.artifacts.begin_draw("player", RING, SWORD).ok, "source-first body subsequently pays for drawing")
	if world.artifacts.active.has("player"):
		_finish(runner, world, "player")
	runner.assert_eq(_json(world.spirit_sources.qi_baselines.player), baseline, "research and drawing preserve the preexisting artifact floor")
	_restore(runner, world, "original source first, later paid research and draw")
