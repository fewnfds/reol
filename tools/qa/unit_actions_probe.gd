extends SceneTree
## Ordinary Main, real stock handling, and an independent stopped-process resume.
## Writes only a dedicated QA slot. This is acceptance evidence, not a CI suite.
const REPORT: String = "res://logs/unit-actions-native.json"
var main: Node
var runtime
var clock
var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	create_timer(180.0, true, false, true).timeout.connect(func() -> void: quit(1))
	if DisplayServer.get_name() == "headless":
		push_error("Unit action acceptance requires native rendering")
		quit(1)
		return
	Engine.max_fps = 60
	clock = root.get_node("GameClock")
	clock.set_paused(true)
	main = load("res://scenes/main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	runtime = main.get("_continuity")
	if runtime == null:
		quit(1)
		return
	runtime.settlement_work_budget = 2147483647
	if "--resume" in OS.get_cmdline_user_args():
		await _resume()
		return
	_expect(runtime.avatar_adapter.choose("subject:player"), "ordinary human opening")
	clock.set_paused(true)
	runtime.settings.event_budget = 4096
	var world = runtime.world_sim
	var panel: SettlementServicesPanel = runtime.service_adapter.panel
	panel._select_page(8)
	_expect(panel._haul_source.item_count > 2, "haul tab lists original containers")
	panel._haul_amount.value = 2
	panel._submit_haul()
	_expect(world.services.owns_actor("player"), "ordinary haul button accepts the intent")
	if not world.services.owns_actor("player"):
		quit(1)
		return
	var id: String = world.services.active_jobs.player
	await _until_delivery(id)
	_expect(world.services.jobs[id].carrying and world.regions.home.inventory.entrusted("actor:player", "wood") == 2, "actual original public cargo and custody travel together")
	await _advance(137)
	for _frame: int in 3: await process_frame
	var form: ScrollContainer = panel._pages[8]
	_expect(panel.get_global_rect().position.y >= 130.0 and panel.get_global_rect().end.y <= 720.0, "haul form preserves the ordinary time controls and fits the viewport")
	form.scroll_vertical = 1000
	await _capture("res://logs/unit-actions-hauling.png")
	var path: String = "user://tests/unit_actions_native_%d.json" % Time.get_ticks_usec()
	_expect(runtime.save_game(path) == OK, "ordinary save preserves the moving consignment")
	var checkpoint: String = _hash()
	var checkpoint_ms: int = world.elapsed_ms
	await _finish_haul(id)
	_expect(world.services.jobs[id].status == "completed", "ordinary actor completes the delivery")
	var future_ms: int = world.elapsed_ms - checkpoint_ms
	var future: String = _hash()
	_expect(runtime.load_game(path) == OK and _hash() == checkpoint, "same-process exact checkpoint")
	await _advance(future_ms)
	_expect(_hash() == future, "same-process exact world future")
	var report: Dictionary = {"engine": Engine.get_version_info().string, "renderer": RenderingServer.get_video_adapter_name(), "save": path, "checkpoint": checkpoint, "future": future, "future_ms": future_ms, "failures": failures}
	await _combat()
	report["failures"] = failures
	var file: FileAccess = FileAccess.open(REPORT, FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t", true, true))
	file.close()
	print("UNIT_ACTIONS_NATIVE ", JSON.stringify(report))
	quit(0 if failures.is_empty() else 1)


func _combat() -> void:
	var world = runtime.world_sim
	var teacher: String = "shi_tou"
	var cell: Vector2i = SimRouteTravel.cell(world.regions.home.actors[teacher].cell)
	_expect(runtime.travel_to("home", cell), "ordinary travel approaches the actual resident")
	for _step: int in 128:
		if runtime.player_journey.is_empty(): break
		await _advance(maxi(1, int(runtime.player_journey.due_ms) - world.elapsed_ms))
	runtime.home_runtime().select_actor(teacher)
	var lesson: Dictionary = runtime.conflict_adapter.teach_selected()
	_expect(lesson.ok, "ordinary U panel requests a real personal demonstration: " + str(lesson.line))
	if not lesson.ok: return
	await _advance(int(world.conflicts.rules.lesson_ms))
	_expect(world.conflicts.knows("player", "qi_bolt"), "completed original lesson grants the practiced method")
	var companion: Dictionary = world.services.begin_haul(teacher, {"region": "home", "container": "store"}, {"region": "home", "container": "kitchen"}, "wood", 2)
	_expect(companion.ok, "NPC accepts the same stock-handling entry after the lesson")
	var haul: Dictionary = runtime.service_adapter.submit_haul({"region": "home", "container": "store"}, {"region": "home", "container": "kitchen"}, "wood", 2)
	_expect(haul.ok, "the trained player returns to the same ordinary work entry")
	if not haul.ok: return
	var id: String = world.services.active_jobs.player
	await _until_delivery(id)
	runtime.home_runtime().select_actor(teacher)
	var fight: Dictionary = runtime.conflict_adapter.engage_selected()
	_expect(fight.ok, "ordinary U panel hands work to an actual conflict: " + str(fight.line))
	if not fight.ok: return
	_expect(world.services.jobs[id].status == "cancelled" and world.regions.home.inventory.entrusted("actor:player", "wood") == 2, "combat releases work while preserving the same entrusted cargo")
	_expect(runtime.conflict_adapter.request_cast("qi_bolt"), "ordinary E entry accepts a learned projectile intention")
	await _advance(1)
	await _advance(500)
	_expect(not world.conflicts.projectiles.is_empty(), "the original combat owner creates an actual in-flight projectile")
	await _capture("res://logs/unit-actions-combat.png")
	runtime.conflict_adapter.yield_player()
	_expect(not world.regions.home.inventory.consume("qa:cannot_steal", "actor:player", "wood", 2), "yielding cannot privatize interrupted public cargo")


func _resume() -> void:
	var report: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(REPORT))
	_expect(runtime.load_game(str(report.save)) == OK, "independent process loads the hauling slot")
	_expect(_hash() == report.checkpoint, "independent process exact checkpoint")
	runtime.settings.event_budget = 4096
	await _advance(int(report.future_ms))
	_expect(_hash() == report.future, "independent process exact world future")
	runtime.service_adapter.panel._select_page(8)
	await _capture("res://logs/unit-actions-resumed.png")
	print("UNIT_ACTIONS_RESUME ", JSON.stringify({"future": _hash(), "failures": failures}))
	quit(0 if failures.is_empty() else 1)


func _until_delivery(id: String) -> void:
	for _step: int in 256:
		var world = runtime.world_sim
		if world.services.jobs[id].status != "active" or world.services.jobs[id].stage == "delivery": return
		await _advance(maxi(1, world.services.next_boundary_ms() - world.elapsed_ms))
	_expect(false, "bounded pickup")


func _finish_haul(id: String) -> void:
	for _step: int in 256:
		var world = runtime.world_sim
		if world.services.jobs[id].status != "active": return
		await _advance(maxi(1, world.services.next_boundary_ms() - world.elapsed_ms))
	_expect(false, "bounded delivery")


func _advance(duration: int) -> void:
	clock.advance_msec(duration)
	for _frame: int in 5000:
		if not clock.has_pending_advance(): return
		await process_frame
	_expect(false, "accepted shared time drains completely")


func _capture(path: String) -> void:
	for _frame: int in 60: await process_frame
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(path)


func _hash() -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized({"world": runtime.world_sim.to_dict(), "clock": clock.to_dict(), "motion": main.get("player").motion.to_dict()})).sha256_text()


func _expect(value: bool, message: String) -> void:
	if not value:
		failures.append(message)
		push_error(message)
