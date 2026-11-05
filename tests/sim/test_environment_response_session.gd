extends RefCounted
## A closed developer session uses the same original world and actions. This is
## separate from Main and intentionally uses a small declared response area.

const LifecycleFixture = preload("res://tests/sim/test_object_lifecycle.gd")
const SourceFixture = preload("res://tests/sim/test_environment_source_bindings.gd")
const Definitions = preload("res://scripts/data/environment_source_definitions.gd")
const Session = preload("res://scripts/runtime/environment_response_session.gd")
const Snapshot = preload("res://scripts/persistence/environment_response_snapshot.gd")
const Values = preload("res://scripts/persistence/snapshot_values.gd")

const AREA := Rect2i(96, 96, 64, 64)
const A := Vector2i(112, 112)
const B := Vector2i(132, 112)
var _fixture := LifecycleFixture.new()
var _sources := SourceFixture.new()
var _runner: Object


func run(runner: Object) -> void:
	_runner = runner
	_closed_loop_and_restore(runner)
	print("SCENARIO environment response session: original objects, continuous field, pending/cancel and isolated in-flight restore")


func _new_world() -> RegionalSimulation:
	return _fixture._world(_runner)


func _finish(runner: Object, session: RefCounted, label: String) -> bool:
	for _iteration: int in 100_000:
		var status: Dictionary = session.status()
		if status.state == "ready":
			return true
		if status.state == "error" or status.state == "closed":
			runner.assert_true(false, label + ": " + str(status))
			return false
		var progress: Dictionary = session.pump()
		if not bool(progress.get("ok", false)):
			runner.assert_true(false, label + ": " + str(progress))
			return false
	runner.assert_true(false, label + ": iteration limit")
	return false


func _advance(runner: Object, session: RefCounted, at_ms: int) -> bool:
	var result: Dictionary = session.advance_to_ms(at_ms)
	if not bool(result.get("ok", false)):
		runner.assert_true(false, "time advance begins: " + str(result))
		return false
	if not _finish(runner, session, "time advance completes"):
		return false
	runner.assert_eq(int(session.status().at_ms), at_ms, "the completed shared time is published")
	return true


func _near(runner: Object, actual: float, expected: float, label: String) -> void:
	runner.assert_true(is_finite(actual) and absf(actual - expected) <= 0.000_001, "%s: %s vs %s" % [label, actual, expected])


func _closed_loop_and_restore(runner: Object) -> void:
	var world: RegionalSimulation = _new_world()
	if world == null:
		return
	var hot: Dictionary = world.object_lifecycle.execute(_fixture._spawn("session_hot", "session_hot_item", "plain_slate", [A.x, A.y]))
	var cold: Dictionary = world.object_lifecycle.execute(_fixture._spawn("session_cold", "session_cold_item", "stone_slab", [145, 139]))
	if not bool(hot.get("ok", false)) or not bool(cold.get("ok", false)):
		runner.assert_true(false, "real hot and cold physical objects are present")
		return
	var raw: Dictionary = _sources._definitions()
	raw.bindings.artifacts.plain_slate = "hot"
	raw.bindings.artifacts.stone_slab = "cold"
	var definitions := Definitions.new()
	if not definitions.configure(raw):
		runner.assert_true(false, "independent source profiles configure")
		return
	var settings: Dictionary = {"climate": world.environment.definitions.duplicate(true),
		"weather": world.weather.definitions.duplicate(true), "weather_epoch_ms": world.weather.epoch_ms,
		"seed": 42, "tau_ms": 1000, "tide_grid_ms": 10_000}
	var session := Session.new()
	session.field_work = 100_000
	session.cell_budget = 256
	if not session.configure(world, definitions, settings, AREA):
		runner.assert_true(false, "the closed session binds the original world")
		return
	if not _finish(runner, session, "source cache and response activation"):
		return
	if not _advance(runner, session, 1000):
		return
	var old: Dictionary = session.sample(A)
	var empty: Dictionary = session.sample(B)
	if not bool(old.get("ok", false)) or not bool(empty.get("ok", false)):
		runner.assert_true(false, "both old and future locations are observable")
		return
	runner.assert_true(int(old.thermal_grade) > 0 and old.actual_elements[3] > 0.0, "the original hot item controls the initial field")
	runner.assert_true(int(empty.thermal_grade) == 0, "the future location starts without heat")
	var move: Dictionary = _fixture._move("session_move", "session_hot_item", hot.to, _fixture._ground(B.x, B.y))
	var cells: Array[Vector2i] = [A, B]
	var ids: Array[String] = ["session_hot_item"]
	var previous_view: Dictionary = session.view(cells, ids)
	var pending: Dictionary = session.execute(move)
	runner.assert_true(bool(pending.get("pending", false)), "the physical change can prepare over multiple pumps")
	if not bool(pending.get("pending", false)):
		return
	runner.assert_eq(Snapshot.capture(session).get("reason"), "busy", "a private candidate cannot be saved halfway")
	runner.assert_eq(session.view(cells, ids), previous_view, "pending presentation retains the last completed view")
	runner.assert_eq(world.artifacts.objects.session_hot_item.container, hot.to.container, "pending does not move the original object")
	runner.assert_true(session.cancel(), "the pending direct move can be cancelled")
	runner.assert_true(not world.object_lifecycle.receipts.has("session_move"), "cancel writes no success receipt")
	_near(runner, float(session.sample(A).actual_c), float(old.actual_c), "cancellation retains the old actual state")
	pending = session.execute(move)
	if not bool(pending.get("pending", false)) or not _finish(runner, session, "direct source move"):
		return
	runner.assert_true(bool(session.status().result.get("ok", false)), "the original object and new field commit together")
	var after_old: Dictionary = session.sample(A)
	var after_new: Dictionary = session.sample(B)
	if not bool(after_old.get("ok", false)) or not bool(after_new.get("ok", false)):
		runner.assert_true(false, "both complete field samples remain available")
		return
	_near(runner, float(after_old.actual_c), float(old.actual_c), "old temperature is continuous at the move")
	_near(runner, float(after_new.actual_c), float(empty.actual_c), "new temperature does not jump at the move")
	runner.assert_eq(after_old.thermal_grade, 0, "the former position has no new heat source")
	runner.assert_true(int(after_new.thermal_grade) > 0, "the new position gains its target heat immediately")
	if not _advance(runner, session, 2000):
		return
	var fading: Dictionary = session.sample(A)
	var rising: Dictionary = session.sample(B)
	runner.assert_true(float(fading.actual_c) < float(after_old.actual_c), "the old hot spot cools over game time")
	runner.assert_true(float(rising.actual_c) > float(after_new.actual_c), "the new hot spot warms over game time")
	runner.assert_true(float(fading.actual_elements[3]) < float(after_old.actual_elements[3]) and float(rising.actual_elements[3]) > float(after_new.actual_elements[3]), "elemental influence fades and establishes as well")

	var pickup: Dictionary = _fixture._move("session_pickup", "session_hot_item", _fixture._location("ground:session_move"), _fixture._location("actor:player"))
	var scheduled: Dictionary = session.schedule(pickup, "player", 1000)
	runner.assert_true(bool(scheduled.get("ok", false)), "an original timed pickup is active when saving")
	if not bool(scheduled.get("ok", false)):
		return
	var captured: Dictionary = Snapshot.capture(session)
	runner.assert_true(bool(captured.get("ok", false)), "completed world and in-flight action can be captured")
	if not bool(captured.get("ok", false)):
		return
	var serialized: Variant = JSON.parse_string(Values.canonical_json(captured.snapshot))
	var staged: Dictionary = Snapshot.stage(serialized, Callable(self, "_new_world"), definitions, settings)
	runner.assert_true(bool(staged.get("ok", false)), "the JSON snapshot stages an independent world")
	if not bool(staged.get("ok", false)):
		return
	var restored: RefCounted = staged.candidate
	restored.field_work = 100_000
	restored.cell_budget = 256
	if not _finish(runner, restored, "candidate rebuild and anchor validation"):
		return
	runner.assert_true(restored._world != world, "the restored session has an independent original world")
	runner.assert_eq(restored._world.object_lifecycle.actions.session_pickup.status, "active", "the in-progress action survives restoration")
	var resumed: Dictionary = restored.sample(B)
	_near(runner, float(resumed.actual_c), float(rising.actual_c), "temperature restores without restarting its curve")
	_near(runner, float(resumed.actual_elements[3]), float(rising.actual_elements[3]), "elemental influence restores without restarting its curve")
	if not _advance(runner, session, 3500) or not _advance(runner, restored, 3500):
		return
	runner.assert_eq(world.object_lifecycle.actions.session_pickup.status, "completed", "the original timed action settles once")
	runner.assert_eq(restored._world.object_lifecycle.actions.session_pickup.status, "completed", "the restored timed action settles once")
	runner.assert_eq(restored._world.artifacts.objects.session_hot_item.container, "actor:player", "the restored original item reaches the same container")
	var original_future: Dictionary = session.sample(B)
	var restored_future: Dictionary = restored.sample(B)
	_near(runner, float(restored_future.actual_c), float(original_future.actual_c), "the restored future preserves temperature causality")
	_near(runner, float(restored_future.actual_elements[3]), float(original_future.actual_elements[3]), "the restored future preserves elemental causality")
	runner.assert_true(float(restored_future.actual_elements[3]) > 0.0 and int(restored_future.thermal_grade) == 0, "the picked-up object leaves a real residual without another source")
	# Real field preparation, not a mock guard: tiny work budgets must retain
	# the old published view and the exact original action deadline until cancel.
	var drop: Dictionary = _fixture._move("session_slow_drop", "session_hot_item", _fixture._location("actor:player"), _fixture._ground(B.x, B.y))
	var before_wait: Dictionary = session.view(cells, ids)
	var slow: Dictionary = session.schedule(drop, "player", 100)
	runner.assert_true(bool(slow.get("ok", false)), "real pending drop schedules")
	if not bool(slow.get("ok", false)):
		return
	session.field_work = 1
	session.cell_budget = 1
	session.advance_to_ms(5000)
	for _iteration: int in 5:
		session.pump()
	runner.assert_eq(world.elapsed_ms, 3600, "real source candidate blocks further world events at its due time")
	runner.assert_eq(int(session.status().at_ms), 3500, "the unfinished event does not publish its clock")
	runner.assert_eq(world.target_ms, 5000, "real pending retains all later requested time")
	runner.assert_eq(world.object_lifecycle.actions.session_slow_drop.status, "active", "real candidate is not prematurely failed")
	runner.assert_eq(session.view(cells, ids), before_wait, "real pending preserves the complete earlier view")
	runner.assert_eq(Snapshot.capture(session).get("reason"), "busy", "real half boundary cannot be saved")
	runner.assert_true(session.cancel("player"), "the real timed environment candidate can be cancelled")
	session.field_work = 100_000
	session.cell_budget = 256
	if not _finish(runner, session, "cancelled real boundary resumes") or not _advance(runner, restored, 5000):
		return
	runner.assert_eq(world.object_lifecycle.actions.session_slow_drop.status, "cancelled", "real pending cancellation retains its result")
	runner.assert_true(not world.object_lifecycle.receipts.has("session_slow_drop"), "cancelled real drop has no success receipt")
	_near(runner, float(session.sample(B).actual_c), float(restored.sample(B).actual_c), "cancelled event and differently sliced time preserve the same temperature")
	_near(runner, float(session.sample(B).actual_elements[3]), float(restored.sample(B).actual_elements[3]), "cancelled event preserves the same elemental history")

	var wrong_settings: Dictionary = settings.duplicate(true)
	wrong_settings.seed = 43
	runner.assert_eq(Snapshot.stage(serialized, Callable(self, "_new_world"), definitions, wrong_settings).get("reason"), "settings_digest", "different response rules are rejected before loading")
	var damaged: Dictionary = JSON.parse_string(Values.canonical_json(captured.snapshot))
	damaged.phases.cells[0].target[0] = float(damaged.phases.cells[0].target[0]) + 1.0
	var rejected: Dictionary = Snapshot.stage(damaged, Callable(self, "_new_world"), definitions, settings)
	runner.assert_true(bool(rejected.get("ok", false)), "a structurally valid modified target is staged only as a private candidate")
	if bool(rejected.get("ok", false)):
		var corrupt: RefCounted = rejected.candidate
		corrupt.field_work = 100_000
		corrupt.cell_budget = 256
		for _iteration: int in 100_000:
			var status: Dictionary = corrupt.status()
			if status.state in ["ready", "error"]:
				break
			corrupt.pump()
		runner.assert_eq(corrupt.status().state, "error", "target inconsistent with rebuilt original sources is never published")
		corrupt.close()
	runner.assert_eq(world.object_lifecycle.actions.session_pickup.status, "completed", "failed candidate validation does not alter the live world")
	restored.close()
	session.close()
