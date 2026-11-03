extends RefCounted
## Whole-world continuations, saved-present migration and ordinary UI intent.

const Support = preload("res://tests/sim/spirit_source_test_support.gd")
const Fixtures = preload("res://tests/runtime/test_world_continuity_runtime.gd")
const ARCHIVE: String = "res://tests/fixtures/session_v33.json"
const SOURCE_SHA: String = "d1a4e0f5fbaa4b87728f34723fe75876647ccd114f3622ef830fd17f7822c9e2"


class ControlledFog extends FogOfWar:
	var source_visible: bool = true


	func is_cell_visible(_cell: Vector2i) -> bool:
		return source_visible


	func is_explored(_cell: Vector2i) -> bool:
		return true


func run(runner: Object) -> void:
	_coarse_fine_and_budget(runner)
	_old_archives(runner)
	_real_runtime_source_and_save(runner)
	_local_read_only_projection(runner)
	_original_page_and_stale_intents(runner)
	_nonhuman_previous_autonomy(runner)
	print("SCENARIO spirit continuity: off-lattice real initialization, fine/remote/budget same future, read-only old archives, ordinary UI timed work, joint in-flight save and local knowledge")


func _coarse_fine_and_budget(runner: Object) -> void:
	var options: Dictionary = {"at_ms": 7331, "qi": {"player": 10}, "opening_charge": 0, "second_stone": true}
	var coarse: RegionalSimulation = Support.make(runner, options)
	if coarse == null:
		return
	runner.assert_eq(coarse.spirit_sources.activation_ms, 7331, "new source activates at the same genuine nonzero world opening as existing processes")
	runner.assert_true(coarse.spirit_sources.begin("player", "hearth_seam", "body", "hearth_stone").ok, "nonzero continuation starts actual bodily restoration")
	runner.assert_true(coarse.spirit_sources.begin("chen_shouzhuo", "hearth_seam", "stone", "second_stone").ok, "nonzero continuation simultaneously reserves another original stone")
	runner.assert_true(coarse.advance_to_ms(19676), "both actual source processes advance partway before serialization")
	var fine: RegionalSimulation = Support.valid_restore(runner, coarse, options)
	var bounded: RegionalSimulation = Support.valid_restore(runner, coarse, options)
	if fine == null or bounded == null:
		return
	var target: int = 1207331
	runner.assert_true(coarse.advance_to_ms(target), "coarse absence completes the requested real future")
	var cursor: int = fine.elapsed_ms
	while cursor < target:
		cursor = mini(target, cursor + 13717)
		runner.assert_true(fine.set_active_region("home" if posmod(cursor, 2) == 0 else "river"), "view precision changes reuse existing regional owners")
		runner.assert_true(fine.advance_to_ms(cursor), "fine presentation advances the same real source/body/artifact interval")
	var complete: bool = bounded.advance_to_ms(target, 1)
	runner.assert_true(not complete and bounded.elapsed_ms < target and bounded.target_ms == target, "one-event budget retains unprocessed original target time")
	var attempts: int = 0
	while not complete and attempts < 2000:
		complete = bounded.advance_to_ms(target, 1)
		attempts += 1
	runner.assert_true(complete, "source work and finite refill resume after original simulation yields")
	for world: RegionalSimulation in [coarse, fine, bounded]:
		runner.assert_true(world.set_active_region(""), "final comparison shares the same view-independent active-region marker")
		runner.assert_true(world.synchronize_regions(), "final comparison flushes each original regional owner at its shared time")
	runner.assert_eq(Support.canonical(fine.to_dict()), Support.canonical(coarse.to_dict()), "fine nearby views, remote work and JSON resume have one whole-world future")
	runner.assert_eq(Support.canonical(bounded.to_dict()), Support.canonical(coarse.to_dict()), "budget splitting loses neither original source cost nor finite refills")
	runner.assert_eq(coarse.spirit_sources.sources.hearth_seam.spent, 12, "two restored actual reservations complete once each")
	runner.assert_eq(coarse.spirit_sources.sources.hearth_seam.released, 2, "source retains activation-relative refill phase after complete absence")
	runner.assert_eq(coarse.spirit_sources.sources.hearth_seam.amount, 2, "only the two actual later refills remain after joint consumption")


func _old_archives(runner: Object) -> void:
	var content := ReolContentDB.new()
	if not content.load_all():
		runner.assert_true(false, "source migration loads current original content")
		return
	runner.assert_eq(FileAccess.get_sha256(ARCHIVE), SOURCE_SHA, "actual unfinished v33 irrigation archive retains its independent source hash")
	for version: int in range(1, 34):
		var path: String = "res://tests/fixtures/session_v%d.json" % version
		var original: String = FileAccess.get_file_as_string(path)
		var prior: Dictionary = JSON.parse_string(original)
		var before: String = Support.canonical(prior)
		var current: Dictionary = SessionSaveSchema.upgrade(prior, content)
		runner.assert_true(not current.is_empty(), "real historical archive reaches finite-source migration: v%d" % version)
		if current.is_empty():
			continue
		runner.assert_eq(current.schema_version, SessionSaveSchema.VERSION, "finite-source migration reaches the current root contract: v%d" % version)
		if current.has("continuity"):
			var regional: Dictionary = current.continuity.world
			var source: Dictionary = regional.spirit_sources
			runner.assert_eq(source.version, SimSpiritSources.VERSION, "old source activation explicitly reaches current cost provenance: v%d" % version)
			runner.assert_eq(Support.canonical(regional.capability_practice), Support.canonical(SimCapabilityPractice.empty_state()), "old source activation adds no invented capability practice or spending: v%d" % version)
			runner.assert_eq(regional.health.version, 2, "old bodily history explicitly reaches current health schema: v%d" % version)
			runner.assert_eq(regional.health.conflict_source_floor, 1, "old body does not skip new committed combat sources: v%d" % version)
			var expected_conflicts: Dictionary = SimConflicts.empty_state()
			expected_conflicts.perception_since_ms = int(regional.elapsed_ms)
			runner.assert_eq(Support.canonical(regional.conflicts), Support.canonical(expected_conflicts), "old world gains only saved-present perception activation and no invented combat, spending or learning history: v%d" % version)
			runner.assert_eq(source.activation_ms, regional.elapsed_ms, "old-world spiritual supply starts at its actual saved present: v%d" % version)
			runner.assert_eq(source.last_ms, regional.elapsed_ms, "migration does not invent a prior unsettled source interval: v%d" % version)
			runner.assert_true(source.active.is_empty() and source.records.is_empty() and source.qi_baselines.is_empty() and source.charge_baselines.is_empty(), "migration grants no past restoration, work or ownership: v%d" % version)
			for row: Dictionary in source.sources.values():
				runner.assert_eq(row.released, 0, "migration never grants historical deep refills")
				runner.assert_eq(row.spent, 0, "migration never invents historical source consumption")
				runner.assert_eq(row.lost, 0, "migration never reconstructs fictitious old overflow")
			if version == 33:
				var projected: Dictionary = regional.duplicate(true)
				runner.assert_eq(SnapshotValues.normalized(projected.field_opportunities), SnapshotValues.normalized(SimFieldOpportunities.empty_state()), "historical world gains no invented field site, visitor or treasure")
				projected.erase("field_opportunities")
				projected.erase("spirit_sources")
				projected.erase("conflicts")
				runner.assert_eq(Support.canonical(projected.site_affairs), Support.canonical(SimSiteAffairs.empty_state()), "old source archive gains no retrospective borrowing arrangement")
				projected.erase("site_affairs")
				runner.assert_eq(Support.canonical(projected.source_care), Support.canonical(SimSourceCare.empty_state()), "old source archive gains no retrospective care")
				projected.erase("source_care")
				projected.erase("capability_practice")
				projected.health.version = prior.continuity.world.health.version
				projected.health.erase("conflict_source_floor")
				projected.version = prior.continuity.world.version
				projected.artifacts.version = prior.continuity.world.artifacts.version
				runner.assert_eq(Support.canonical(projected), Support.canonical(prior.continuity.world), "v33 retains every original ecological, bodily, artifact, stock and in-flight fact after explicit conflict schema projection")
				runner.assert_eq(Support.canonical(current.simulation), Support.canonical(prior.simulation), "v33 migration leaves the original root/home body and inventory unchanged")
		runner.assert_eq(Support.canonical(prior), before, "pure source migration leaves its caller's old dictionary unchanged: v%d" % version)
		runner.assert_eq(FileAccess.get_file_as_string(path), original, "source migration never rewrites a historical fixture: v%d" % version)
	var saved: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(ARCHIVE))
	for fault: String in ["already_domain", "already_regional", "future_version"]:
		var bad: Dictionary = saved.duplicate(true)
		match fault:
			"already_domain": bad.continuity.world["spirit_sources"] = {}
			"already_regional": bad.continuity.world.version = 30
			"future_version": bad.schema_version = SessionSaveSchema.VERSION + 1
		var before: String = Support.canonical(bad)
		runner.assert_true(SessionSaveSchema.upgrade(bad, content).is_empty(), "legacy source migration refuses inconsistent version ownership: " + fault)
		runner.assert_eq(Support.canonical(bad), before, "failed legacy source migration does not repair its input: " + fault)


func _quiet_fixture(runner: Object) -> Dictionary:
	var fixture: Dictionary = Fixtures.new()._fixture(runner)
	if fixture.is_empty():
		return fixture
	var runtime: WorldContinuityRuntime = fixture.continuity
	for region: String in runtime.world_sim.regions:
		var sim: VillageSimulation = runtime.world_sim.regions[region]
		for actor: String in sim.actors:
			sim.cancel_action(actor, "spirit_fixture_setup")
			sim.actors[actor].autonomous = false
		runtime.world_sim.invalidate_region(region)
	return fixture


func _approach(runner: Object, fixture: Dictionary) -> bool:
	var runtime: WorldContinuityRuntime = fixture.continuity
	var kitchen: Vector2i = SimRouteTravel.cell(runtime.world_sim.regions.home.places.kitchen.cell)
	if not runtime.travel_to("home", kitchen):
		runner.assert_true(false, "ordinary source fixture can walk to its actual kitchen anchor")
		return false
	var deadline: int = GameClock.elapsed_ms + 600000
	while not runtime.player_journey.is_empty() and GameClock.elapsed_ms < deadline:
		GameClock.advance_msec(1000)
	var arrived: bool = runtime.player_journey.is_empty() and fixture.player.cell == kitchen
	runner.assert_true(arrived, "ordinary source fixture physically reaches its actual anchor")
	return arrived


func _real_runtime_source_and_save(runner: Object) -> void:
	var fixture: Dictionary = _quiet_fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	if not _approach(runner, fixture):
		Fixtures.new()._dispose(fixture)
		return
	for verb: String in ["study", "charge"]:
		var answer: Dictionary = runtime.world_sim.artifacts.begin("player", verb, "hearth_stone")
		runner.assert_true(answer.ok, "ordinary runtime personally learns/pays the original stone process: " + verb)
		if not answer.ok:
			Fixtures.new()._dispose(fixture)
			return
		GameClock.advance_msec(int(runtime.world_sim.artifacts.definitions.verbs[verb].minutes) * 60000)
	var qi: int = int(runtime.world_sim.regions.home.actors.player.qi)
	runner.assert_eq(qi, 15, "ordinary study and charge have spent original qi rather than editing a fixture reserve")
	var continuous: Vector2 = fixture.player.motion.position + Vector2(7.25, -3.5)
	runtime.world_sim.regions.home.set_actor_position("player", continuous)
	fixture.player.motion.relocate(continuous)
	fixture.player.global_position = continuous
	runtime.world_sim.invalidate_region("home")
	var view: SpiritSourceRuntime = runtime.spirit_adapter
	runner.assert_true(view.show_panel("hearth_stone"), "nearby visible source is reachable through the ordinary source UI")
	runner.assert_true(view.panel.target_choice.item_count == 2 and view.panel.selected_target() == "body", "one structured source action exposes two destination choices")
	var result: Dictionary = view.submit("begin")
	runner.assert_true(result.ok, "ordinary source UI routes to the same actual bodily source action")
	if not result.ok:
		Fixtures.new()._dispose(fixture)
		return
	runner.assert_eq(fixture.player.motion.position, continuous, "starting source work freezes the genuine continuous position without snapping to a tile center")
	runner.assert_eq(runtime.world_sim.regions.home.actor_position(runtime.world_sim.regions.home.actors.player), continuous, "source UI keeps the same original authoritative continuous body point")
	var id: String = str(runtime.world_sim.spirit_sources.active.player.id)
	GameClock.advance_msec(33333)
	runner.assert_eq(fixture.player.motion.position, continuous, "in-flight source work retains its noncentral original body position")
	runner.assert_eq(runtime.world_sim.regions.home.actors.player.qi, qi, "ordinary unfinished source process has no early body benefit")
	runner.assert_true(not runtime.travel_to("river"), "in-flight source body must first finish or stop before original travel")
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var before: String = Support.canonical(snapshot)
	var live: RegionalSimulation = runtime.world_sim
	runner.assert_eq(snapshot.continuity.world.spirit_sources.active.player.previous_autonomous, false, "genuine manual human source process returns its original body to manual control")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "whole session independently stages a genuine in-flight source")
	for fault: String in ["missing_source", "free_qi", "changed_reservation", "full_target", "body_motion", "future_due", "human_auto_return"]:
		var bad: Dictionary = snapshot.duplicate(true)
		match fault:
			"missing_source": bad.continuity.world.erase("spirit_sources")
			"free_qi":
				bad.continuity.world.regions.home.actors.player.qi = qi + 1
				bad.simulation.actors.player.qi = qi + 1
			"changed_reservation": bad.continuity.world.spirit_sources.sources.hearth_seam.amount = 5
			"full_target":
				bad.continuity.world.regions.home.actors.player.qi = 20
				bad.simulation.actors.player.qi = 20
			"body_motion": bad.player.motion.velocity = [1.0, 0.0]
			"future_due": bad.continuity.world.spirit_sources.active.player.due_ms = int(bad.clock.elapsed_ms) - 1
			"human_auto_return": bad.continuity.world.spirit_sources.active.player.previous_autonomous = true
		var bad_before: String = Support.canonical(bad)
		runner.assert_true(WorldSessionSnapshot.stage(runtime, bad).is_empty(), "whole candidate rejects source and original player conflict: " + fault)
		runner.assert_true(runtime.world_sim == live, "rejected source candidate never swaps the live regional authority")
		runner.assert_eq(Support.canonical(WorldSessionSnapshot.capture(runtime)), before, "rejected source candidate leaves complete live session unchanged: " + fault)
		runner.assert_eq(Support.canonical(bad), bad_before, "whole candidate does not repair malformed source inputs")
	runner.assert_eq(Support.canonical(snapshot), before, "rejecting a forged return-to-autonomy flag never changes the genuine original snapshot")
	runner.assert_true(not WorldSessionSnapshot.stage(runtime, snapshot).is_empty(), "the original manual-return source snapshot still stages after all rejected variants")
	var path: String = "user://tests/spirit_source_%d.json" % Time.get_ticks_usec()
	runner.assert_eq(runtime.save_game(path), OK, "ordinary in-flight source can save through the original atomic store")
	GameClock.advance_msec(500000)
	var expected: String = Support.canonical(WorldSessionSnapshot.capture(runtime))
	runner.assert_eq(runtime.world_sim.spirit_sources.records[id].result, "success", "ordinary common clock actually completes the source process")
	runner.assert_eq(runtime.world_sim.regions.home.actors.player.qi, qi + 4, "ordinary completed process restores exactly its original body's accepted qi")
	runner.assert_eq(runtime.load_game(path), OK, "ordinary loader restores the complete in-flight source candidate")
	runner.assert_eq(fixture.player.motion.position, continuous, "ordinary source restore retains the exact noncentral frozen body position")
	GameClock.advance_msec(500000)
	runner.assert_eq(Support.canonical(WorldSessionSnapshot.capture(runtime)), expected, "original atomic save/load resumes one byte-identical complete source/body/artifact future")
	# Stop routes through the existing native cancellation callback.
	runner.assert_true(view.show_panel("hearth_stone"), "source panel can be reopened after ordinary restore")
	runner.assert_true(view.submit("begin").ok, "a new source operation can be explicitly stopped")
	var spending: int = int(runtime.world_sim.spirit_sources.sources.hearth_seam.spent)
	view.submit("cancel")
	runner.assert_true(not runtime.world_sim.spirit_sources.owns_actor("player"), "ordinary stop releases the actual source-owned body")
	runner.assert_eq(runtime.world_sim.spirit_sources.sources.hearth_seam.spent, spending, "ordinary stop never grants or spends an unfinished source batch")
	for suffix: String in ["", ".bak", ".tmp", ".bak.tmp"]:
		var absolute: String = ProjectSettings.globalize_path(path + suffix)
		if FileAccess.file_exists(absolute):
			DirAccess.remove_absolute(absolute)
	Fixtures.new()._dispose(fixture)


func _local_read_only_projection(runner: Object) -> void:
	var fixture: Dictionary = _quiet_fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	if not _approach(runner, fixture):
		Fixtures.new()._dispose(fixture)
		return
	var source_view: SpiritSourceRuntime = runtime.spirit_adapter
	var fog := ControlledFog.new()
	fixture.home._fog = fog
	var original: String = Support.canonical(runtime.world_sim.to_dict())
	var local: Dictionary = source_view.perception("hearth_seam")
	runner.assert_true(bool(local.get("known", false)) and bool(local.get("near", false)), "visible nearby source gives actual qualitative local evidence")
	for hidden: String in ["amount", "released", "spent", "lost", "deep_supply", "capacity"]:
		runner.assert_true(not local.has(hidden), "runtime source projection does not publish hidden accounting: " + hidden)
	fog.source_visible = false
	var obscured: Dictionary = source_view.perception("hearth_seam")
	runner.assert_true(bool(obscured.get("known", false)) and not bool(obscured.get("near", false)), "previously seen source keeps position but loses current local truth behind fog")
	runner.assert_true(obscured.get("objects", []).is_empty(), "fog does not expose nearby usable stone candidates")
	var remembered: String = str(obscured.line)
	# This is deliberately a read-projection sensitivity probe, never saved as
	# valid world history: hidden quantity cannot alter its remote description.
	var amount: int = int(runtime.world_sim.spirit_sources.sources.hearth_seam.amount)
	runtime.world_sim.spirit_sources.sources.hearth_seam.amount = 0
	runner.assert_eq(source_view.perception("hearth_seam").line, remembered, "remembered remote description cannot leak later hidden source depletion")
	runtime.world_sim.spirit_sources.sources.hearth_seam.amount = amount
	runner.assert_eq(Support.canonical(runtime.world_sim.to_dict()), original, "source UI observation mutates no simulated source, ability, original object or RNG")
	source_view.reset_observation()
	runner.assert_true(not source_view.perception("hearth_seam").get("known", false), "a fresh UI timeline cannot discover an unseen nearby source through fog")
	fixture.home._fog = null
	fog.free()
	Fixtures.new()._dispose(fixture)


func _original_page_and_stale_intents(runner: Object) -> void:
	var fixture: Dictionary = _quiet_fixture(runner)
	if fixture.is_empty():
		return
	var runtime: WorldContinuityRuntime = fixture.continuity
	var view: SpiritSourceRuntime = runtime.spirit_adapter
	if not _approach(runner, fixture):
		Fixtures.new()._dispose(fixture)
		return
	runner.assert_true(runtime.object_adapter.select_object("hearth_stone"), "ordinary original object page selects its actual public stone")
	runner.assert_true(runtime.object_adapter.panel._buttons.spirit_source.visible, "ordinary original object page offers the observed source entry")
	runner.assert_true(runtime.object_adapter.submit("spirit_source").ok, "one object page entry opens the source page")
	runner.assert_true(view.panel.visible and not runtime.object_adapter.panel.visible, "opening source page does not stack the original object page")
	var body: Dictionary = runtime.world_sim.regions.home.actors.player
	var before_qi: int = int(body.qi)
	runner.assert_true(not view.submit("begin").ok, "source page cannot manufacture a personally unlearned method")
	runner.assert_eq(body.qi, before_qi, "refused source action changes no original qi")
	runner.assert_true(runtime.world_sim.artifacts.begin("player", "study", "hearth_stone").ok, "same original body actually studies the original stone")
	GameClock.advance_msec(int(runtime.world_sim.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
	runner.assert_true(view.show_panel("hearth_stone"), "source page reopens after genuine personal learning")
	runner.assert_true(view.submit("begin").ok, "learned original method enables actual source work")
	GameClock.advance_msec(1234)
	runner.assert_true(view.submit("cancel").ok, "source page stops its actual source process")
	var fog := ControlledFog.new()
	fog.source_visible = false
	fixture.home._fog = fog
	view.reset_observation()
	var memory: Dictionary = view.perception("hearth_seam")
	runner.assert_true(memory.get("known", false) and memory.get("remembered", false), "original personal source history preserves remembered position after UI reset behind fog")
	runner.assert_true(not memory.get("near", false) and memory.get("objects", []).is_empty(), "remembered position does not expose source access or stone candidates")
	fixture.home._fog = null
	fog.free()
	runner.assert_true(view.show_panel("hearth_stone"), "visible source reopens from personal remembered history")
	view.panel.target_choice.select(1)
	view.panel.choice_changed.emit()
	var charge: int = int(runtime.world_sim.artifacts.objects.hearth_stone.charge)
	runner.assert_true(view.submit("begin").ok, "single source intention routes the selected original stone destination")
	runner.assert_eq(runtime.world_sim.artifacts.objects.hearth_stone.charge, charge, "selected original stone is not recharged before actual completion")
	GameClock.advance_msec(int(runtime.world_sim.spirit_sources.active.player.due_ms) - GameClock.elapsed_ms)
	runner.assert_eq(runtime.world_sim.artifacts.objects.hearth_stone.charge, charge + 6, "completed selected source output reaches the original instance")
	runner.assert_true(runtime.world_sim.artifacts.begin("player", "inspect", "hearth_stone").ok, "unrelated original work can begin after source completion")
	runner.assert_true(not view.submit("cancel").ok, "a stale source stop refuses when no source process is active")
	runner.assert_true(runtime.world_sim.artifacts.owns_actor("player"), "a stale source stop cannot cancel unrelated original artifact work")
	GameClock.advance_msec(int(runtime.world_sim.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
	runner.assert_true(view.show_panel("hearth_stone"), "source page remains available after separate original work")
	view._selected_object = ""
	runner.assert_true(not view.submit("object").ok and view.panel.visible, "missing original object retains a visible explanation on the source page")
	Fixtures.new()._dispose(fixture)
	var distant: Dictionary = _quiet_fixture(runner)
	if distant.is_empty():
		return
	var remote_runtime: WorldContinuityRuntime = distant.continuity
	var remote_view: SpiritSourceRuntime = remote_runtime.spirit_adapter
	runner.assert_true(remote_runtime.travel_to("river"), "unobserved-source fixture follows the actual original route away from home")
	GameClock.advance_msec(600000)
	runner.assert_true(remote_runtime.current_region == "river" and remote_runtime.player_journey.is_empty(), "unobserved-source fixture genuinely arrives at the other settlement")
	var before: String = Support.canonical(remote_runtime.world_sim.to_dict())
	runner.assert_true(not remote_view.has_known_source(), "fresh distant timeline has no omniscient entry for the home source")
	runner.assert_true(not remote_view.show_panel(), "opening the page cannot select an unknown distant source")
	runner.assert_eq(Support.canonical(remote_runtime.world_sim.to_dict()), before, "asking about an unseen distant source changes no simulated fact")
	Fixtures.new()._dispose(distant)


func _nonhuman_previous_autonomy(runner: Object) -> void:
	for subject: String in ["subject:avian:moss_sparrow", "subject:soul:yan_heng"]:
		var fixture: Dictionary = _quiet_fixture(runner)
		if fixture.is_empty():
			return
		var runtime: WorldContinuityRuntime = fixture.continuity
		var world: RegionalSimulation = runtime.world_sim
		# An explicit spatial opening for this independent ownership case.
		# Learning, spending and restoration below use the original processes.
		var kitchen: Vector2i = SimRouteTravel.cell(world.regions.home.places.kitchen.cell)
		world.regions.home.set_actor_cell("player", kitchen)
		fixture.player.spawn_at(kitchen)
		world.invalidate_region("home")
		runtime._opening_selection_available = true
		runner.assert_true(runtime.select_starting_avatar(subject), "original one-time opening selects an existing nonhuman life: " + subject)
		runner.assert_true(world.regions.home.actors.player.autonomous, "the former human remains an autonomous world member after the actual opening choice")
		var completed: bool = true
		for verb: String in ["study", "charge", "charge", "charge", "charge"]:
			var answer: Dictionary = world.artifacts.begin("player", verb, "hearth_stone")
			runner.assert_true(answer.ok, "former human undertakes genuine original study/storage before autonomous restoration: " + subject + "/" + verb)
			if not answer.ok:
				completed = false
				break
			GameClock.advance_msec(int(world.artifacts.active.player.due_ms) - GameClock.elapsed_ms)
		if not completed:
			Fixtures.new()._dispose(fixture)
			continue
		runner.assert_eq(world.regions.home.actors.player.qi, 3, "former human's deficient qi comes from actual original paid operations")
		var until_decision: int = int(world.regions.home.actors.player.retry_ms) - GameClock.elapsed_ms
		runner.assert_true(until_decision > 0, "former human next decides at its actual original retry time")
		GameClock.advance_msec(maxi(0, until_decision))
		runner.assert_true(world.spirit_sources.owns_actor("player"), "the original former human independently chooses a real source operation while a nonhuman life is manual")
		if not world.spirit_sources.owns_actor("player"):
			Fixtures.new()._dispose(fixture)
			continue
		runner.assert_true(world.spirit_sources.previous_autonomy("player"), "nonhuman play legitimately preserves return-to-autonomy for the independently working former human")
		runner.assert_true(not world.regions.home.actors.player.autonomous, "the genuinely occupied former human is only temporarily nonautonomous")
		var saved: Dictionary = WorldSessionSnapshot.capture(runtime)
		var original: String = Support.canonical(saved)
		var candidate: Dictionary = WorldSessionSnapshot.stage(runtime, saved)
		runner.assert_true(not candidate.is_empty(), "whole candidate accepts legitimate previous autonomy under the actual nonhuman avatar: " + subject)
		runner.assert_eq(Support.canonical(saved), original, "valid nonhuman source candidate leaves its original snapshot untouched")
		if not candidate.is_empty():
			var restored: RegionalSimulation = candidate.world
			var end: int = int(world.spirit_sources.active.player.due_ms)
			runner.assert_true(restored.advance_to_ms(end), "independent nonhuman candidate completes the original former human source operation")
			GameClock.advance_msec(end - GameClock.elapsed_ms)
			runner.assert_true(world.regions.home.actors.player.autonomous and restored.regions.home.actors.player.autonomous, "completion returns the former human to autonomy in both original and restored worlds")
			runner.assert_eq(Support.canonical(world.to_dict()), Support.canonical(restored.to_dict()), "nonhuman original and independently restored source share the complete same future")
		Fixtures.new()._dispose(fixture)
