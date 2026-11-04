extends RefCounted
## Controlled projection and continuation test. Deliberate placement and
## policy overrides here are not evidence of an ordinary playthrough.

const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const SELLER: String = "river_shi_tou"
const RING: String = "stele_drawing_ring"
const OBJECT: Dictionary = {"kind": "private_artifact", "id": RING}


func run(runner: Object) -> void:
	var fixtures := Fixtures.new()
	var fixture: Dictionary = _prepared(runner, fixtures, true)
	if not fixture.is_empty():
		_accept_and_restore(runner, fixture)
		fixtures._dispose(fixture)
	fixture = _prepared(runner, fixtures, false)
	if not fixture.is_empty():
		_refusal(runner, fixture)
		fixtures._dispose(fixture)
	print("SCENARIO controlled private exchange UI: visible holder and quote, busy and refusal, pending and cancellation, independent saved continuation")


func _prepared(runner: Object, fixtures: RefCounted, accept: bool) -> Dictionary:
	# The acceptance policy belongs to the world's frozen input, including the
	# independent restore path. Never edit only the running domain after boot.
	var defaults := ReolContentDB.new()
	if not defaults.load_all():
		runner.assert_true(false, "private exchange fixture reads its content inputs")
		return {}
	var documents: Dictionary = defaults.content_bundle().documents
	documents["res://data/definitions/private_exchange.json"].policy.accept_threshold = -10.0 if accept else 10.0
	var fixture: Dictionary = fixtures._fixture(runner, ReolContentBundle.from_documents(documents))
	if fixture.is_empty():
		return {}
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	# The fixture deliberately places people and sets their social policy.
	# The ring itself still goes through its original timed take and source event.
	for sim: VillageSimulation in world.regions.values():
		for actor: String in sim.actors:
			sim.cancel_action(actor, "fixture_setup")
			sim.actors[actor].autonomous = false
	var spawned: bool = world.field_opportunities.spawn_opening(runtime.centers)
	runner.assert_true(spawned, "controlled fixture opens the original unique field ring")
	if not spawned:
		fixtures._dispose(fixture)
		return {}
	var cell: Vector2i = world.artifacts.object_cell(RING)
	world.regions.river.set_actor_cell(SELLER, cell)
	world.invalidate_region("river")
	var take: Dictionary = world.artifacts.begin(SELLER, "take", RING)
	runner.assert_true(take.ok, "controlled holder begins an actual original take")
	if not take.ok:
		fixtures._dispose(fixture)
		return {}
	GameClock.advance_msec(int(world.artifacts.active[SELLER].due_ms) - GameClock.elapsed_ms)
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + SELLER, "original timed take supplies the real holder and source")
	if world.artifacts.objects[RING].container != "actor:" + SELLER:
		fixtures._dispose(fixture)
		return {}
	world.regions.river.actors[SELLER].autonomous = true
	world.invalidate_region("river")
	fixture.player.spawn_at(cell)
	runtime.prepare_player_command()
	return fixture


func _accept_and_restore(runner: Object, fixture: Dictionary) -> void:
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var ui: InteractionRequestsRuntime = runtime.interaction_adapter
	var cell: Vector2i = fixture.player.cell
	var subject: String = world.embodiment.subject_for_actor(SELLER)
	world.regions.river.set_actor_cell(SELLER, cell + Vector2i(20, 20))
	world.invalidate_region("river")
	var before: String = _canonical(runtime)
	runner.assert_true(not _has_key(ui.receivers(), subject), "a distant holder is not a visible receiver")
	runner.assert_true(ui.objects_for("private_exchange", subject).is_empty(), "a known remote identifier reveals no held ring or quotation")
	runner.assert_eq(ui.submit(subject, "private_exchange", OBJECT).status, "unheard", "a stale remote choice cannot summon the holder")
	runner.assert_eq(_canonical(runtime), before, "remote projection and rejected request change no authority")
	world.regions.river.set_actor_cell(SELLER, cell)
	world.invalidate_region("river")
	ui.show_panel()
	var choices: Array[Dictionary] = ui.objects_for("private_exchange", subject)
	runner.assert_true(_has_key(ui.receivers(), subject) and _has_key(choices, OBJECT), "visible original holder offers the actual ring reference")
	if choices.is_empty():
		return
	runner.assert_true(str(choices[0].label).contains("4钱") and str(choices[0].label).contains("5.0秒"), "selection states the actual fixed price and shared-time duration")
	runner.assert_eq(ui.submit(subject, "private_exchange", OBJECT, "gesture").status, "not_understood", "a gesture does not establish the spoken terms")
	runner.assert_eq(ui.submit(subject, "private_exchange", OBJECT, "spoken", {"price": 1}).status, "invalid", "a caller cannot silently replace the displayed fixed price")
	var study: Dictionary = world.artifacts.begin(SELLER, "study", RING)
	runner.assert_true(study.ok, "controlled holder can be occupied by an original ring action")
	if not study.ok:
		return
	runner.assert_eq(ui.submit(subject, "private_exchange", OBJECT).status, "unavailable", "a busy holder is not forced to interrupt the original action")
	runner.assert_true(world.artifacts.active.has(SELLER), "the declined request preserves the holder's existing bodily process")
	world.artifacts.cancel(SELLER)
	var buyer_before: int = world.regions.home.inventory.quantity("actor:player", "coin")
	var seller_before: int = world.regions.river.inventory.quantity("actor:" + SELLER, "coin")
	var still: String = _canonical(runtime)
	fixture.player.motion.velocity = Vector2(0.0000001, 0.0)
	runner.assert_eq(ui.submit(subject, "private_exchange", OBJECT).status, "unavailable", "even a nonzero subpixel speed must stop before explicit handover consent")
	fixture.player.motion.velocity = Vector2.ZERO
	runner.assert_eq(_canonical(runtime), still, "rejected moving request creates no proposal, payment or process")
	var accepted: Dictionary = ui.submit(subject, "private_exchange", OBJECT)
	runner.assert_eq(accepted.status, "started", "controlled willing holder starts a real timed handover")
	if not accepted.ok:
		return
	var process: Dictionary = accepted.process
	var reservation: String = str(world.private_exchange.jobs[process.id].reservation)
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + SELLER, "acceptance alone leaves the original ring with the seller")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "coin"), buyer_before, "acceptance reserves rather than spends the original money")
	runner.assert_eq(world.regions.river.inventory.quantity("actor:" + SELLER, "coin"), seller_before, "acceptance does not credit the seller")
	runner.assert_eq(world.regions.home.inventory.available("actor:player", "coin"), buyer_before - 4, "the real buyer ledger reserves the displayed quote")
	runner.assert_eq(SimInteractionRequests.observe(world, runtime.avatar_subject, process).status, "pending", "the participant sees a process, not a completed sale")
	runner.assert_eq(SimInteractionRequests.observe(world, "subject:chen_shouzhuo", process).status, "unconfirmed", "a third party cannot learn this private process from its identifier")
	runner.assert_true(str(ui._progress.text).contains("仍在原处"), "the panel explains that neither money nor ring has transferred")
	var start_ms: int = GameClock.elapsed_ms
	GameClock.set_paused(true)
	GameClock._process(1.0)
	runner.assert_eq(GameClock.elapsed_ms, start_ms, "a paused frame cannot advance the handover")
	GameClock.set_paused(false)
	GameClock.advance_msec(2000)
	var path: String = "user://tests/private_exchange_runtime_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "ordinary save captures the controlled in-progress handover")
	var genuine: Dictionary = WorldSessionSnapshot.capture(runtime)
	for fault: String in ["altitude", "subpixel_speed"]:
		var bad: Dictionary = genuine.duplicate(true)
		if fault == "altitude":
			bad.player.altitude = 1
		else:
			bad.player.motion.velocity = [0.0000001, 0.0]
		var stable: String = _canonical(runtime)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "active handover rejects a nonstationary avatar candidate: " + fault)
		runner.assert_eq(_canonical(runtime), stable, "bad handover avatar candidate leaves the live world intact: " + fault)

	GameClock.advance_msec(2999)
	runner.assert_eq(SimInteractionRequests.observe(runtime.world_sim, runtime.avatar_subject, process).status, "pending", "one millisecond before the shared deadline still is not a sale")
	GameClock.advance_msec(1)
	world = runtime.world_sim
	runner.assert_eq(SimInteractionRequests.observe(world, runtime.avatar_subject, process).status, "completed", "the shared deadline yields the actual completed handover")
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:player", "the same ring reaches the original buyer")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "coin"), buyer_before - 4, "completion charges the stated price once")
	runner.assert_eq(world.regions.river.inventory.quantity("actor:" + SELLER, "coin"), seller_before + 4, "completion pays the real seller once")
	var future: String = _canonical(runtime)
	var loaded: Error = runtime.load_game(path)
	runner.assert_eq(loaded, OK, "independent joint load accepts the in-progress handover")
	if loaded == OK:
		ui.show_panel()
		runner.assert_eq(ui._receipt, process, "reopening after load reconstructs the actual participant's in-progress reference")
		runner.assert_eq(SimInteractionRequests.observe(runtime.world_sim, runtime.avatar_subject, process).status, "pending", "loading does not turn acceptance into completion")
		GameClock.advance_msec(3000)
		runner.assert_eq(_canonical(runtime), future, "restored shared time reaches the same complete joint future without a second transfer")
		loaded = runtime.load_game(path)
		runner.assert_eq(loaded, OK, "the same in-progress save may be independently restored for cancellation")
		if loaded == OK:
			world = runtime.world_sim
			runtime.stop_player_action()
			runner.assert_eq(SimInteractionRequests.observe(world, runtime.avatar_subject, process).status, "cancelled", "the player's actual stop interrupts the handover")
			runner.assert_true(not world.regions.home.inventory.reservations.has(reservation), "stopping releases the original money reservation")
			runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + SELLER, "stopping leaves the same ring with its seller")
			runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "coin"), buyer_before, "stopping leaves the original money with the buyer")
			GameClock.advance_msec(5000)
			runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + SELLER, "passing the old deadline cannot complete a cancelled handover")
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))


func _refusal(runner: Object, fixture: Dictionary) -> void:
	var runtime: WorldContinuityRuntime = fixture.continuity
	var world: RegionalSimulation = runtime.world_sim
	var ui: InteractionRequestsRuntime = runtime.interaction_adapter
	var subject: String = world.embodiment.subject_for_actor(SELLER)
	var buyer_before: int = world.regions.home.inventory.quantity("actor:player", "coin")
	var answer: Dictionary = ui.submit(subject, "private_exchange", OBJECT)
	runner.assert_eq(answer.status, "refused", "controlled unwilling holder may refuse an otherwise visible real quote")
	runner.assert_true(answer.process.is_empty(), "refusal starts no handover")
	var decisions: int = world.private_exchange.proposals.size()
	world.regions.river.actors[SELLER].energy = maxf(0.0, float(world.regions.river.actors[SELLER].energy) - 1.0)
	runner.assert_eq(ui.submit(subject, "private_exchange", OBJECT).status, "refused", "unrelated energy fluctuation does not reroll the same proposal")
	runner.assert_eq(world.private_exchange.proposals.size(), decisions, "repeat request reuses the original proposal")
	runner.assert_eq(world.regions.home.inventory.quantity("actor:player", "coin"), buyer_before, "refusal spends no money")
	runner.assert_eq(world.artifacts.objects[RING].container, "actor:" + SELLER, "refusal moves no ring")


func _has_key(rows: Array[Dictionary], key: Variant) -> bool:
	for row: Dictionary in rows:
		if row.key == key:
			return true
	return false


func _canonical(runtime: WorldContinuityRuntime) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(WorldSessionSnapshot.capture(runtime)))
