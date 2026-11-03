extends RefCounted
## Ordinary commands in the real main scene. No body/resource/ability/NPC-policy
## edits: the archive is earned by travel, taking the sword and paired study.

const ARCHIVE: String = "res://logs/conflict_inflight.json"
const FUTURE_DELTA_MS: int = 7200000
const FOLLOW_LIMIT_MS: int = 1800000
const TRAVEL_LIMIT_MS: int = 180000
const Space = preload("res://scripts/sim/conflict_space.gd")


func prepare(runtime: WorldContinuityRuntime) -> Dictionary:
	if runtime == null or runtime.world_sim == null:
		return {"error": "ordinary main scene is not ready"}
	var report: Dictionary = {"ordinary_commands": true, "started_ms": GameClock.elapsed_ms, "steps": []}
	var avatar: Node = runtime.avatar_adapter
	if avatar != null and avatar.opening.visible:
		if not avatar.choose("subject:player"):
			return _failure("normal opening choice failed", report)
	if not runtime.human_player_active():
		return _failure("prepare requires the ordinary human life", report)
	GameClock.cancel_wait()
	GameClock.set_speed(1.0)
	GameClock.set_paused(true)
	var domain: SimArtifacts = runtime.world_sim.artifacts
	if not domain.objects.has("training_sword"):
		return _failure("this scene has no genuine opening training sword", report)
	if domain.held_weapon("player") != "training_sword":
		if domain.objects.training_sword.container.begins_with("actor:"):
			return _failure("the original sword is actually in another person's custody", report)
		var storage: Vector2i = domain.object_cell("training_sword")
		if not _travel(runtime, str(domain.objects.training_sword.region), storage):
			return _failure("ordinary trip to the actual sword failed", report)
		var object_ui: WorldObjectsRuntime = runtime.object_adapter
		if not object_ui.select_object("training_sword"):
			return _failure("the actual stored sword is not visible after arrival", report)
		var taken: Dictionary = object_ui.submit("take")
		if not bool(taken.ok):
			return _failure("ordinary take refused: " + str(taken.line), report)
		if not _advance(runtime, int(domain.active.player.due_ms) - GameClock.elapsed_ms):
			return _failure("taking the actual sword did not reach its due time", report)
		if domain.held_weapon("player") != "training_sword":
			return _failure("finished take did not grant actual sword custody", report)
	_note(report, "actual_sword_taken", {"object": domain.held_weapon("player")})
	var teacher: String = _find_teacher(runtime, report)
	if teacher.is_empty():
		return _failure("no natural teacher accepted within the bounded follow period", report)
	_note(report, "actual_lesson_completed", {"teacher": teacher, "lessons": runtime.world_sim.conflicts.lessons.duplicate(true)})
	if not _separate(runtime, teacher):
		return _failure("no real same-height nearby route could separate the lesson participants", report)
	_note(report, "actual_short_separation", {"player": runtime.world_sim.conflicts.body("player").position.duplicate(), "teacher": runtime.world_sim.conflicts.body(teacher).position.duplicate()})
	_senses(runtime)
	runtime.home_runtime().select_actor(teacher)
	var started: Dictionary = runtime.conflict_adapter.engage_selected()
	if not bool(started.ok):
		return _failure("ordinary hostile intention refused: " + str(started.line), report)
	var cast: Dictionary = _cast(runtime, "qi_bolt")
	if not bool(cast.ok):
		return _failure("ordinary paid qi projectile refused: " + str(cast.line), report)
	var action: Dictionary = _last_player_action(runtime.world_sim)
	if action.is_empty() or not _advance(runtime, 200):
		return _failure("could not advance the original projectile preparation", report)
	if action.method != "qi_bolt" or bool(action.emitted) or runtime.world_sim.conflicts.phase("player", GameClock.elapsed_ms) != "prepare":
		return _failure("archive is not genuinely inside paid projectile preparation", report)
	GameClock.set_paused(true)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	if WorldSessionSnapshot.stage(runtime, snapshot).is_empty():
		return _failure("the actual earned preparation cannot stage as a complete joint candidate", report)
	var error: Error = runtime.save_game(ProjectSettings.globalize_path(ARCHIVE))
	if error != OK:
		return _failure("ordinary preparation save failed: " + str(error), report)
	report.merge({"ok": true, "archive": ARCHIVE, "archive_sha256": FileAccess.get_sha256(ARCHIVE),
		"source_ms": GameClock.elapsed_ms, "action": action.duplicate(true), "teacher": teacher,
		"qi": int(runtime.world_sim.conflicts.body("player").qi), "candidate_valid": true})
	_write_json("res://logs/conflict_prepare.json", report)
	return report


func replay(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	if runtime == null or not suffix.is_valid_identifier() or suffix.length() > 32:
		return {"error": "invalid ordinary runtime or evidence suffix"}
	var error: Error = runtime.load_game(ProjectSettings.globalize_path(ARCHIVE))
	if error != OK:
		return {"error": "ordinary preparation load failed", "load_error": error}
	GameClock.set_paused(true)
	var world: RegionalSimulation = runtime.world_sim
	var domain: SimConflicts = world.conflicts
	var action: Dictionary = _last_player_action(world)
	if action.is_empty() or action.method != "qi_bolt" or action.status != "active" or bool(action.emitted):
		return {"error": "archive lacks the genuine original paid preparation"}
	var encounter: String = str(action.conflict)
	var future_ms: int = GameClock.elapsed_ms + FUTURE_DELTA_MS
	var report: Dictionary = {"ordinary_commands": true, "archive": ARCHIVE, "archive_sha256": FileAccess.get_sha256(ARCHIVE),
		"source_ms": GameClock.elapsed_ms, "future_ms": future_ms, "original_action": action.duplicate(true),
		"source_qi": int(domain.body("player").qi), "steps": []}
	if not _advance(runtime, int(action.effect_ms) - GameClock.elapsed_ms):
		return _failure("original paid preparation failed to reach emission", report)
	if not domain.projectiles.has(str(action.id)):
		return _failure("original preparation produced no actual travelling projectile", report)
	_note(report, "original_projectile_emitted", {"action": action.id, "projectiles": domain.projectiles.duplicate(true)})
	var hurt_deadline: int = GameClock.elapsed_ms + 12000
	while world.health.combat_burden("player") <= 0 and not domain.conflict_for("player").is_empty() and GameClock.elapsed_ms < hurt_deadline:
		if not _advance(runtime, mini(50, hurt_deadline - GameClock.elapsed_ms)):
			return _failure("normal hostile response could not advance", report)
	var injured: bool = world.health.combat_burden("player") > 0
	_note(report, "natural_hostile_response", {"injured": injured, "burden": world.health.combat_burden("player"), "hits": domain.hits.duplicate(true)})
	for method: String in ["qi_guard", "sword"]:
		if domain.conflict_for("player").is_empty():
			_note(report, "method_not_attempted_after_actual_end", {"method": method})
			break
		if not _ready(runtime, 4000):
			_note(report, "method_not_ready", {"method": method})
			break
		var reply: Dictionary = _cast(runtime, method)
		if not bool(reply.ok):
			_note(report, "ordinary_method_refused", {"method": method, "line": reply.line})
			break
		var paid: Dictionary = _last_player_action(world)
		var due: int = int(paid.due_ms)
		if not _advance(runtime, int(paid.effect_ms) - GameClock.elapsed_ms):
			return _failure("paid follow-up preparation could not advance", report)
		_note(report, "follow_up_emitted", {"method": method, "action": paid.duplicate(true), "barriers": domain.barriers.duplicate(true)})
		if due > GameClock.elapsed_ms and not _advance(runtime, due - GameClock.elapsed_ms):
			return _failure("paid follow-up recovery could not advance", report)
	var before_yield: int = int(domain.body("player").qi)
	runtime.conflict_adapter.yield_player()
	if int(domain.body("player").qi) != before_yield or not domain.conflict_for("player").is_empty():
		return _failure("normal yield changed paid qi or failed to stop the exchange", report)
	var retreat_deadline: int = GameClock.elapsed_ms + 15000
	while domain.owns_actor("player") and GameClock.elapsed_ms < retreat_deadline:
		if not _advance(runtime, 50):
			return _failure("actual retreat could not advance", report)
	_note(report, "yield_and_retreat", {"encounter": domain.conflicts[encounter].duplicate(true), "qi": before_yield, "burden": world.health.combat_burden("player")})
	var dorm: Vector2i = SimRouteTravel.cell(world.regions.home.places.dorm.cell)
	if not _travel(runtime, "home", dorm):
		return _failure("ordinary retreat to the actual dorm failed", report)
	var rest: Dictionary = runtime.service_adapter.submit("rest")
	if not bool(rest.ok):
		return _failure("ordinary paid dorm rest refused: " + str(rest.line), report)
	var rest_deadline: int = GameClock.elapsed_ms + 4500000
	while world.services.owns_actor("player") and GameClock.elapsed_ms < rest_deadline:
		if not _advance(runtime, mini(60000, rest_deadline - GameClock.elapsed_ms)):
			return _failure("ordinary paid dorm rest could not advance", report)
	if world.services.owns_actor("player"):
		return _failure("ordinary dorm rest exceeded its bounded deadline", report)
	_note(report, "actual_rest_completed", {"qi": int(domain.body("player").qi), "burden": world.health.combat_burden("player"), "wounds": world.health.wounds.duplicate(true), "bag": runtime.player_inventory().containers["actor:player"].duplicate(true)})
	if not _travel(runtime, "river"):
		return _failure("actual departure to the river settlement failed", report)
	_note(report, "actual_other_settlement_arrival", {"region": runtime.current_region, "cell": domain.body("player").cell.duplicate()})
	if GameClock.elapsed_ms > future_ms or not _advance(runtime, future_ms - GameClock.elapsed_ms):
		return _failure("ordinary actions exceeded the shared replay horizon", report)
	_senses(runtime)
	var snapshot: Dictionary = WorldSessionSnapshot.capture(runtime)
	var canonical: String = SnapshotValues.canonical_json(SnapshotValues.normalized(snapshot))
	var path: String = "res://logs/conflict_future_%s.json" % suffix
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return _failure("cannot write full joint replay snapshot", report)
	file.store_string(canonical)
	file.close()
	var original_entries: int = 0
	var later_spent: int = 0
	for payment: Dictionary in domain.qi_spending("player"):
		if int(payment.number) == int(action.number) and int(payment.amount) == int(action.qi_spent):
			original_entries += 1
		elif int(payment.number) > int(action.number):
			later_spent += int(payment.amount)
	var paid_once: bool = original_entries == 1 and int(domain.body("player").qi) == int(report.source_qi) - later_spent
	var valid: bool = not WorldSessionSnapshot.stage(runtime, snapshot).is_empty()
	report.merge({"ok": true, "ms": GameClock.elapsed_ms, "region": runtime.current_region,
		"journey": runtime.player_journey.duplicate(true), "qi": int(domain.body("player").qi),
		"original_paid_once": paid_once, "later_qi_spent": later_spent,
		"actual_injury": injured, "full_snapshot": path, "bytes": canonical.to_utf8_buffer().size(),
		"sha256": FileAccess.get_sha256(path), "candidate_valid": valid})
	if not paid_once or not valid:
		return _failure("full future failed the real qi ledger or joint candidate verification", report)
	_write_json("res://logs/conflict_restart_%s.json" % suffix, report)
	return report


func run(runtime: WorldContinuityRuntime, suffix: String) -> Dictionary:
	return replay(runtime, suffix)


func _find_teacher(runtime: WorldContinuityRuntime, report: Dictionary) -> String:
	var deadline: int = GameClock.elapsed_ms + FOLLOW_LIMIT_MS
	var attempts: int = 0
	while GameClock.elapsed_ms < deadline and attempts < 100:
		for teacher: String in ["chen_shouzhuo", "shi_tou"]:
			attempts += 1
			_senses(runtime)
			var domain: SimConflicts = runtime.world_sim.conflicts
			if domain.body(teacher).is_empty():
				continue
			var target: Vector2 = SimRouteTravel.point(domain.body(teacher))
			var point: Vector2 = SimRouteTravel.point(domain.body("player"))
			if point.distance_to(target) > float(domain.rules.lesson_radius) or not runtime.conflict_adapter._visible(teacher):
				if not _travel(runtime, "home", SimRouteTravel.cell(domain.body(teacher).cell)):
					if not _advance(runtime, 5000):
						return ""
					continue
			_senses(runtime)
			runtime.home_runtime().select_actor(teacher)
			var reply: Dictionary = runtime.conflict_adapter.teach_selected()
			if bool(reply.ok):
				var lesson: Dictionary = {}
				for row: Dictionary in domain.lessons.values():
					if row.pupil == "player" and row.status == "active":
						lesson = row
				if lesson.is_empty() or not _advance(runtime, int(lesson.due_ms) - GameClock.elapsed_ms):
					return ""
				if lesson.status == "completed" and domain.knows("player", "qi_bolt"):
					return teacher
			elif attempts <= 12:
				_note(report, "natural_teaching_refusal", {"teacher": teacher, "line": str(reply.line)})
			if not _advance(runtime, 5000):
				return ""
	return ""


func _cast(runtime: WorldContinuityRuntime, method: String) -> Dictionary:
	var domain: SimConflicts = runtime.world_sim.conflicts
	var opponent: String = domain.opponent("player")
	if opponent.is_empty():
		return {"ok": false, "line": "the actual encounter has already ended"}
	var direction: Vector2 = SimRouteTravel.point(domain.body(opponent)) - SimRouteTravel.point(domain.body("player"))
	if direction.is_zero_approx():
		direction = SimRouteTravel.facing(domain.body("player"))
	var reply: Dictionary = domain.cast("player", method, direction)
	if bool(reply.ok):
		runtime.hold_player_motion(true)
	return reply


func _separate(runtime: WorldContinuityRuntime, teacher: String) -> bool:
	var domain: SimConflicts = runtime.world_sim.conflicts
	var world: ReolWorld = runtime.home_runtime()._world
	for _attempt: int in range(6):
		var other: Vector2 = SimRouteTravel.point(domain.body(teacher))
		var current: Vector2 = SimRouteTravel.point(domain.body("player"))
		var distance: float = current.distance_to(other)
		if distance >= 64.0 and distance <= 192.0 and Space.clear_segment(runtime.world_sim, current, other, Space.level(runtime.world_sim, current)):
			return true
		var center: Vector2i = TileGrid.world_to_cell(other)
		var cells: Array[Vector2i] = VillageRuntime.find_reachable_cells(world, runtime.home_runtime()._player.cell, 6, 1024)
		var candidates: Array[Vector2i] = []
		for cell: Vector2i in cells:
			var point: Vector2 = TileGrid.cell_to_world(cell)
			var gap: float = point.distance_to(other)
			if gap >= 64.0 and gap <= 192.0 and Space.level(runtime.world_sim, point) == Space.level(runtime.world_sim, other) and Space.clear_segment(runtime.world_sim, point, other, Space.level(runtime.world_sim, point)):
				candidates.append(cell)
		candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
			var da: int = (a - center).length_squared()
			var db: int = (b - center).length_squared()
			return da < db if da != db else a.x < b.x if a.x != b.x else a.y < b.y)
		var walked: bool = false
		for cell: Vector2i in candidates:
			if _travel(runtime, "home", cell):
				walked = true
				break
		if not walked:
			return false
	return false


func _ready(runtime: WorldContinuityRuntime, limit: int) -> bool:
	var deadline: int = GameClock.elapsed_ms + limit
	while not runtime.world_sim.conflicts.conflict_for("player").is_empty() and runtime.world_sim.conflicts.action_blocks("player") and GameClock.elapsed_ms < deadline:
		if not _advance(runtime, mini(50, deadline - GameClock.elapsed_ms)):
			return false
	return not runtime.world_sim.conflicts.conflict_for("player").is_empty() and not runtime.world_sim.conflicts.action_blocks("player")


func _travel(runtime: WorldContinuityRuntime, region: String, destination: Variant = null) -> bool:
	if not runtime.travel_to(region, destination):
		return false
	var deadline: int = GameClock.elapsed_ms + TRAVEL_LIMIT_MS
	while not runtime.player_journey.is_empty() and GameClock.elapsed_ms < deadline:
		if not _advance(runtime, mini(250, deadline - GameClock.elapsed_ms)):
			return false
	return runtime.player_journey.is_empty() and runtime.current_region == region


func _advance(runtime: WorldContinuityRuntime, amount: int) -> bool:
	if amount < 0:
		return false
	GameClock.advance_msec(amount)
	_senses(runtime)
	return runtime.world_sim.elapsed_ms == GameClock.elapsed_ms and runtime.world_sim.target_ms == GameClock.elapsed_ms


func _senses(runtime: WorldContinuityRuntime) -> void:
	# Refresh only presentation caches after a synchronous clock advance. These
	# are the same fog/view updates normally performed between rendered frames.
	var home: VillageRuntime = runtime.home_runtime()
	home._sync_actor_views(true)
	if home._fog != null:
		home._fog.set_focus(runtime.controlled_cell())
		home._fog.update_now()
	if runtime.object_adapter != null:
		runtime.object_adapter.refresh()
	if runtime.conflict_adapter != null:
		runtime.conflict_adapter.refresh()


func _last_player_action(world: RegionalSimulation) -> Dictionary:
	var result: Dictionary = {}
	for row: Dictionary in world.conflicts.actions.values():
		if row.actor == "player" and (result.is_empty() or int(row.number) > int(result.number)):
			result = row
	return result


func _note(report: Dictionary, kind: String, detail: Dictionary) -> void:
	var row: Dictionary = {"kind": kind, "at_ms": GameClock.elapsed_ms}
	row.merge(detail)
	report.steps.append(row)
	print("CONFLICT REPLAY %s at %d" % [kind, GameClock.elapsed_ms])


func _write_json(path: String, value: Dictionary) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(value, "\t", true, true))
	file.close()
	return true


func _failure(line: String, report: Dictionary) -> Dictionary:
	report["error"] = line
	report["ok"] = false
	return report
