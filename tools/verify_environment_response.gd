extends SceneTree
## Real renderer + cross-process acceptance of the closed developer adapter.
## Explicit scripted game-time commands; the diagram never owns simulation.

const Session = preload("res://scripts/runtime/environment_response_session.gd")
const Archive = preload("res://scripts/persistence/environment_response_snapshot.gd")
var fixture: RefCounted
var failed: int = 0
var session: RefCounted
var canvas: Diagram
var _definitions: EnvironmentSourceDefinitions
var _settings: Dictionary
const A := Vector2i(22, 22)
const B := Vector2i(40, 22)


func _initialize() -> void:
	call_deferred("_run")


func assert_true(value: bool, label: String) -> void:
	if not value:
		failed += 1
		printerr("FAIL ", label)


func assert_eq(value: Variant, expected: Variant, label: String) -> void:
	assert_true(value == expected, label)


func _factory() -> RegionalSimulation:
	return fixture._world(self)


func _run() -> void:
	# Load fixtures after autoload registration (their existing runtime helpers
	# reference GameClock). A tool's boot-time preload precedes that registration.
	fixture = load("res://tests/sim/test_object_lifecycle.gd").new()
	root.size = Vector2i(1280, 720)
	canvas = Diagram.new()
	root.add_child(canvas)
	DirAccess.make_dir_recursive_absolute("res://logs/response-visual")
	var world: RegionalSimulation = _factory()
	_definitions = EnvironmentSourceDefinitions.new()
	var raw: Dictionary = load("res://tests/sim/test_environment_source_bindings.gd").new()._definitions()
	raw.bindings.artifacts.plain_slate = "hot"
	raw.bindings.artifacts.stone_slab = "cold"
	raw.profiles.hot.radius_cells = 8
	raw.profiles.cold.radius_cells = 4
	assert_true(_definitions.configure(raw), "visual definitions")
	_settings = {"climate": world.environment.definitions, "weather": world.weather.definitions,
		"weather_epoch_ms": world.weather.epoch_ms, "seed": 42, "tau_ms": 2000, "tide_grid_ms": 1000}
	if "--read" in OS.get_cmdline_user_args():
		var saved: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://logs/response-visual/checkpoint.json"))
		var expected: Variant = JSON.parse_string(FileAccess.get_file_as_string("res://logs/response-visual/expected.json"))
		var staged: Dictionary = Archive.stage(saved, Callable(self, "_factory"), _definitions, _settings)
		assert_true(bool(staged.get("ok", false)), "fresh process stages independent archive " + str(staged))
		if not bool(staged.get("ok", false)):
			quit(1)
			return
		session = staged.candidate
		await _ready()
		await _show("RESTORED: same original items and residual", "restored")
		session.advance_to_ms(9000)
		await _ready()
		var actual: Dictionary = _projection()
		assert_true(SnapshotValues.normalized(actual) == expected, "fresh process has identical future endpoint")
		await _show("RESTORED FUTURE: matches uninterrupted world", "restored-future")
	else:
		assert_true(bool(world.object_lifecycle.execute(fixture._spawn("preview_hot", "preview_hot", "plain_slate", [A.x, A.y])).get("ok", false)), "real hot prop")
		assert_true(bool(world.object_lifecycle.execute(fixture._spawn("preview_cold", "preview_cold", "stone_slab", [28, 28])).get("ok", false)), "real cold prop")
		session = Session.new()
		assert_true(session.configure(world, _definitions, _settings, Rect2i(0, 0, 64, 64)), "closed visual session")
		await _ready()
		session.advance_to_ms(3000)
		await _ready()
		await _show("BEFORE MOVE: temperature built at A", "before")
		var result: Dictionary = session.execute(fixture._move("preview_move", "preview_hot", fixture._location("ground:preview_hot"), fixture._ground(B.x, B.y)))
		assert_true(bool(result.get("ok", false)), "real source movement begins")
		await _ready()
		await _show("JUST MOVED: target changed; actual stays continuous", "just-moved")
		var captured: Dictionary = Archive.capture(session)
		assert_true(bool(captured.get("ok", false)), "capture residual checkpoint")
		if bool(captured.get("ok", false)):
			_write("checkpoint.json", SnapshotValues.normalized(captured.snapshot))
		session.advance_to_ms(9000)
		await _ready()
		_write("expected.json", SnapshotValues.normalized(_projection()))
		await _show("SIX SECONDS LATER: A dissipates; B builds", "after")
	print("VISUAL_CROSS_PROCESS failures=", failed, " state=", session.status())
	session.close()
	quit(1 if failed else 0)


func _ready() -> void:
	for frame: int in 60000:
		var started: int = Time.get_ticks_usec()
		while session.status().pending and Time.get_ticks_usec() - started < 2000:
			var result: Dictionary = session.pump()
			if not bool(result.get("ok", false)):
				assert_true(false, "visual session: " + str(result))
				return
		if not session.status().pending:
			return
		await process_frame
	assert_true(false, "visual session timeout")


func _projection() -> Dictionary:
	var cells: Array[Vector2i] = [A, B, Vector2i(28, 28)]
	var ids: Array[String] = ["preview_hot", "preview_cold"]
	return session.view(cells, ids)


func _show(title: String, filename: String) -> void:
	canvas.caption = title
	canvas.at_ms = int(session.status().at_ms)
	canvas.points.clear()
	for y: int in range(12, 38):
		for x: int in range(12, 52):
			canvas.points.append(session.sample(Vector2i(x, y)))
	canvas.readings = _projection()
	canvas.queue_redraw()
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	var path: String = "res://logs/response-visual/" + filename + ".png"
	assert_true(root.get_texture().get_image().save_png(path) == OK, "real rendered screenshot " + filename)
	print("FRAME ", filename, " ", SnapshotValues.canonical_json(SnapshotValues.normalized(canvas.readings)))


func _write(filename: String, value: Variant) -> void:
	var file: FileAccess = FileAccess.open("res://logs/response-visual/" + filename, FileAccess.WRITE)
	assert_true(file != null, "open acceptance artifact")
	if file != null:
		file.store_string(SnapshotValues.canonical_json(value))
		file.close()


class Diagram:
	extends Node2D
	var caption: String
	var at_ms: int
	var points: Array[Dictionary] = []
	var readings: Dictionary = {}
	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1280, 720), Color("101923"))
		var font: Font = ThemeDB.fallback_font
		draw_string(font, Vector2(24, 37), "REOL / ENVIRONMENT RESPONSE ACCEPTANCE", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color("d5e9dc"))
		draw_string(font, Vector2(24, 72), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, 21)
		draw_string(font, Vector2(24, 105), "Shared game time: %d ms | original objects + CPU field candidates" % at_ms, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color("8daba9"))
		for index: int in points.size():
			var sample: Dictionary = points[index]
			if not bool(sample.get("ok", false)):
				continue
			var color: Color = Color("49759b").lerp(Color("eea35c"), clampf((float(sample.actual_c) + 10.0) / 90.0, 0.0, 1.0))
			draw_rect(Rect2(24 + index % 40 * 18, 140 + (index / 40) * 18, 17, 17), color)
		for cell: Vector2i in [A, B, Vector2i(28, 28)]:
			var at := Vector2(24 + (cell.x - 12) * 18 + 9, 140 + (cell.y - 12) * 18 + 9)
			draw_circle(at, 8, Color.WHITE, false, 2)
			draw_string(font, at + Vector2(-4, 5), "A" if cell == A else ("B" if cell == B else "C"), HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.BLACK)
		if readings.get("ok", false):
			var y: int = 156
			for sample: Dictionary in readings.samples:
				draw_string(font, Vector2(775, y), "Cell %s" % str(sample.cell), HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
				draw_string(font, Vector2(775, y + 30), "Target %.3f C" % float(sample.target_c), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("ecaa73"))
				draw_string(font, Vector2(775, y + 57), "Actual %.3f C" % float(sample.actual_c), HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color("a8d4ee"))
				draw_string(font, Vector2(775, y + 84), "5 phases %s" % str(sample.actual_elements), HORIZONTAL_ALIGNMENT_LEFT, 480, 15)
				y += 130
		draw_string(font, Vector2(24, 662), "A / original heat location     B / new heat location     C / separate cold material", HORIZONTAL_ALIGNMENT_LEFT, -1, 17)
		draw_string(font, Vector2(24, 691), "Instant authority move; no walking trail. Diagnostic view only; ordinary Main unchanged.", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color("8daba9"))
