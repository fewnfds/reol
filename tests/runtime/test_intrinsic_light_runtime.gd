extends RefCounted
## Real Main, original item actions, local movement, fog and session boundary.

const PEARL: String = "amber_pearl"
const SHARD: String = "glow_shard"
const LEGACY_PATH: String = "res://tests/fixtures/session_v49_thermal.json"
const LEGACY_SHA: String = "a6ae26fad7fff13394ec1a7c9831d5a1fdd85c191222b31213c7f9de138bf8bd"
const POST_ACTION_MS: int = 1234


func run(runner: Object) -> void:
	var previous_clock: Dictionary = GameClock.to_dict()
	var path: String = "user://tests/intrinsic_light_%d.json" % Time.get_ticks_usec()
	var first: Node = _new_main(runner)
	var expected: Dictionary = {}
	if first != null:
		expected = _opening_and_inflight(runner, first, path)
		first.free()
	if not expected.is_empty():
		var restarted: Node = _new_main(runner)
		if restarted != null:
			_resume_and_move(runner, restarted, path, expected)
			restarted.free()
	var spirit: Node = _new_main(runner)
	if spirit != null:
		_soul_and_genuine_old_archive(runner, spirit)
		spirit.free()
	for suffix: String in ["", ".tmp", ".bak", ".bak.tmp"]:
		if FileAccess.file_exists(path + suffix):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path + suffix))
	GameClock.restore_state(previous_clock)
	print("SCENARIO intrinsic light runtime: ordinary Main, original in-flight custody and restart, moving bearer, real placement, sight-limited presentation, soul and genuine root49")


func _new_main(runner: Object) -> Node:
	if not GameClock.restore_state({"tick_index": 0, "total_minutes": 480, "speed": 1.0, "paused": true}):
		runner.assert_true(false, "the original clock resets to a valid opening for this independent scene")
		return null
	var main: Node = load("res://scenes/main.tscn").instantiate()
	runner.root.add_child(main)
	if main._continuity == null or main._continuity.world_sim == null or main._avatar == null:
		runner.assert_true(false, "the ordinary game Main assembles its real world and avatar")
		main.free()
		return null
	return main


func _opening_and_inflight(runner: Object, main: Node, path: String) -> Dictionary:
	if not main._avatar.choose("subject:player"):
		runner.assert_true(false, "the ordinary opening chooses the original human life")
		return {}
	GameClock.set_paused(true)
	var adapter: WorldContinuityRuntime = main._continuity
	var world: RegionalSimulation = adapter.world_sim
	var domain: SimArtifacts = world.artifacts
	if not domain.objects.has(PEARL) or not domain.objects.has(SHARD):
		runner.assert_true(false, "ordinary Main issues both independently located intrinsic-light objects")
		return {}
	var ids: Array[String] = domain.intrinsic_light_ids()
	runner.assert_true(ids.is_read_only() and ids.has(PEARL) and ids.has(SHARD) and ids.size() == 2, "the derived immutable index refers to the two original opening objects")
	runner.assert_eq(domain.objects[PEARL].container, "dorm", "the home source starts at its declared original place")
	runner.assert_eq(domain.objects[PEARL].region, "home", "the home source belongs to its original regional owner")
	runner.assert_eq(domain.objects[SHARD].container, "dorm", "the remote source starts at its actual original place")
	runner.assert_eq(domain.objects[SHARD].region, "river", "the remote source belongs to its original regional owner")
	var dorm: Vector2i = domain.object_cell(PEARL)
	var far: Vector2i = domain.object_cell(SHARD)
	var initial: Dictionary = SimLocalLight.at_cell(world, dorm)
	runner.assert_true(bool(initial.get("supported", false)), "ordinary new-world light is queryable at the actual home source")
	if not bool(initial.get("supported", false)):
		return {}
	runner.assert_eq(int(initial.artificial_relative), 2000, "the original pearl shines at its declared peak without an enable action")
	runner.assert_true(not domain.objects[PEARL].has("stored_q") and not domain.objects[PEARL].has("enabled"), "the natural source owns neither a duplicate thermal balance nor a fictional switch")
	# Relocation arranges the test observer at the existing fixture's source;
	# the later movement is an actual shared-clock body integration.
	main.player.spawn_at(dorm)
	world.invalidate_region("home")
	main.fog.set_focus(dorm)
	main.fog.set_observer(0, 3)
	main.fog.update_now()
	var light: LocalLightRuntime = adapter.light_adapter
	var before: String = _canonical(adapter)
	light.refresh()
	runner.assert_true(light.light.enabled and int(light.last_projection.get("values", {}).get(dorm, -1)) == 2000, "the ordinary local-light view reads the actual pearl at the observer")
	runner.assert_true(not main.fog.is_cell_visible(far) and not adapter.object_adapter._visible(SHARD), "the remote actual object remains outside the player's current sight")
	runner.assert_true(not adapter.object_adapter.select_object(SHARD), "an unseen remote source cannot be selected through its real object panel")
	runner.assert_true(not adapter.natural_adapter.describe(far).contains("暖光"), "a hidden ground observation does not disclose remote live light")
	runner.assert_not_null(light.last_image, "the light adapter retains the current CPU image submitted to the renderer")
	runner.assert_not_null(light.light.texture, "a visible source has a texture for the scene light")
	if light.light.enabled and light.last_image != null:
		var image: Image = light.last_image
		var hidden_count: int = 0
		var revealed: bool = false
		for y: int in LocalLightRuntime.SIDE:
			for x: int in LocalLightRuntime.SIDE:
				var cell: Vector2i = dorm + Vector2i(x - LocalLightRuntime.RADIUS, y - LocalLightRuntime.RADIUS)
				if not main.fog.is_cell_visible(cell):
					hidden_count += 1
					revealed = revealed or image.get_pixel(x, y) != Color.BLACK
		runner.assert_true(hidden_count > 0 and not revealed, "all texels outside current sight stay black even when a nearby source glows")
		runner.assert_eq(light.light.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST, "light interpolation cannot bleed into a hidden cell")
	runner.assert_eq(_canonical(adapter), before, "view-only light, sight and hidden-object queries do not mutate the captured world")
	# Restore the ordinary human sight radius before saving so a future load
	# rebuilds the same exploration from the supported perspective.
	main.fog.set_observer(0, FogOfWar.VISION_RADIUS)
	main.fog.update_now()
	runner.assert_true(adapter.object_adapter.select_object(PEARL), "the human can select the actually visible pearl")
	var started: Dictionary = adapter.object_adapter.submit("take")
	runner.assert_true(bool(started.ok), "the ordinary object panel starts taking the real pearl")
	if not bool(started.ok) or not domain.active.has("player"):
		return {}
	var due: int = int(domain.active.player.due_ms)
	@warning_ignore("integer_division")
	var elapsed_half: int = (due - int(GameClock.elapsed_ms)) / 2
	if elapsed_half < 1:
		runner.assert_true(false, "taking has an actual nonzero in-flight interval")
		return {}
	GameClock.advance_msec(elapsed_half)
	runner.assert_true(domain.active.has("player") and domain.objects[PEARL].container == "dorm", "the unfinished action leaves the one pearl at its original place")
	var middle: Dictionary = SimLocalLight.at_cell(world, dorm)
	runner.assert_true(bool(middle.get("supported", false)) and int(middle.get("artificial_relative", -1)) == 2000, "the still-uncollected pearl remains a real source while taking is in flight")
	var saved: Error = adapter.save_game(path)
	runner.assert_eq(saved, OK, "the ordinary joint saver writes the unfinished take")
	if saved != OK:
		return {}
	var parsed: Dictionary = SimSaveStore.load_file(path)
	if not bool(parsed.get("ok", false)):
		runner.assert_true(false, "the just-written unfinished action is valid JSON")
		return {}
	var checkpoint: String = _json(parsed.data)
	runner.assert_eq(_canonical(adapter), checkpoint, "saved checkpoint contains the full original world, item, action and clock")
	var remaining: int = due - int(GameClock.elapsed_ms)
	GameClock.advance_msec(remaining + POST_ACTION_MS)
	runner.assert_true(not domain.active.has("player") and domain.objects[PEARL].container == "actor:player", "completion transfers the same pearl to the original player exactly once")
	return {"checkpoint": checkpoint, "future": _canonical(adapter), "remaining": remaining, "dorm": dorm}


func _resume_and_move(runner: Object, main: Node, path: String, expected: Dictionary) -> void:
	var adapter: WorldContinuityRuntime = main._continuity
	var loaded: Error = adapter.load_game(path)
	runner.assert_eq(loaded, OK, "a fresh ordinary Main independently loads the unfinished take")
	if loaded != OK:
		return
	var world: RegionalSimulation = adapter.world_sim
	runner.assert_true(world.artifacts.active.has("player") and world.artifacts.objects[PEARL].container == "dorm", "independent restart restores the real unfinished custody and action")
	runner.assert_eq(_canonical(adapter), str(expected.checkpoint), "independent restart restores the complete saved checkpoint")
	GameClock.advance_msec(int(expected.remaining) + POST_ACTION_MS)
	runner.assert_eq(_canonical(adapter), str(expected.future), "the independent restarted world reaches exactly the original complete future")
	runner.assert_true(not world.artifacts.active.has("player") and world.artifacts.objects[PEARL].container == "actor:player", "the restarted action leaves the same unique pearl held")
	var origin: Vector2i = main.player.cell
	var direction := Vector2i.ZERO
	for candidate: Vector2i in [Vector2i.RIGHT, Vector2i.DOWN, Vector2i.LEFT, Vector2i.UP]:
		if main.world.can_step(origin, candidate):
			direction = candidate
			break
	if direction == Vector2i.ZERO:
		runner.assert_true(false, "the real opening has a traversable neighboring cell for the bearer")
		return
	main.player._intent = Vector2(direction)
	GameClock.advance_msec(350)
	main.player._intent = Vector2.ZERO
	GameClock.advance_msec(100)
	var moved: Vector2i = main.player.cell
	runner.assert_eq(moved, origin + direction, "the original player moves into a neighboring cell through the shared clock")
	runner.assert_eq(world.artifacts.object_cell(PEARL), moved, "the source position follows the original carrier, not a copied or frozen anchor")
	var current: Dictionary = SimLocalLight.at_cell(world, moved)
	var old: Dictionary = SimLocalLight.at_cell(world, origin)
	runner.assert_true(bool(current.get("supported", false)) and bool(old.get("supported", false)), "both carrier and old-place light queries are valid at accepted time")
	if bool(current.get("supported", false)) and bool(old.get("supported", false)):
		runner.assert_eq(int(current.artificial_relative), 2000, "the moving carrier receives the source's original peak at its new cell")
		runner.assert_true(int(old.artificial_relative) < int(current.artificial_relative), "the old place is no longer the source center")
	main.fog.set_focus(moved)
	main.fog.update_now()
	adapter.light_adapter.refresh()
	runner.assert_eq(int(adapter.light_adapter.last_projection.get("values", {}).get(moved, -1)), 2000, "the visible light projection follows the current physical bearer")
	runner.assert_true(adapter.object_adapter.select_object(PEARL), "the original held object is still individually selectable")
	var placed: Dictionary = adapter.object_adapter.submit("place")
	runner.assert_true(bool(placed.ok), "the nearby human can start the real place action")
	if not bool(placed.ok) or not world.artifacts.active.has("player"):
		return
	GameClock.advance_msec(int(world.artifacts.active.player.due_ms) - int(GameClock.elapsed_ms))
	runner.assert_eq(world.artifacts.objects[PEARL].container, "dorm", "the actual completed action returns the same pearl to its original place")
	runner.assert_eq(world.artifacts.object_cell(PEARL), expected.dorm, "the original placement, not the former carrier, owns the final source position")
	var returned: Dictionary = SimLocalLight.at_cell(world, expected.dorm)
	runner.assert_true(bool(returned.get("supported", false)) and int(returned.get("artificial_relative", -1)) == 2000, "the placed pearl immediately shines from its actual original place")


func _soul_and_genuine_old_archive(runner: Object, main: Node) -> void:
	runner.assert_true(main._avatar.choose("subject:soul:yan_heng"), "a fresh opening selects the actual residual-soul life")
	GameClock.set_paused(true)
	var adapter: WorldContinuityRuntime = main._continuity
	adapter.light_adapter.refresh()
	runner.assert_true(not adapter.light_adapter.light.enabled and adapter.light_adapter.last_projection.is_empty(), "a soul cannot borrow the human's physical light view")
	runner.assert_true(not adapter.object_adapter._visible(PEARL), "a soul cannot borrow the human's object selection sight")
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(LEGACY_PATH)
	var parsed: Variant = JSON.parse_string(bytes.get_string_from_utf8())
	runner.assert_eq(FileAccess.get_sha256(LEGACY_PATH), LEGACY_SHA, "the genuine pre-light fixture retains its recorded hash")
	if bytes.is_empty() or not parsed is Dictionary:
		runner.assert_true(false, "the real old light archive is readable")
		return
	var source: Dictionary = parsed
	var input: String = _json(source)
	var live: RegionalSimulation = adapter.world_sim
	var terrain: WorldMapData = live.map_data
	var before: String = _canonical(adapter)
	runner.assert_eq(SessionSaveSchema.rejection_reason(source.get("schema_version")), SessionSaveSchema.REJECTION_LEGACY_ENVIRONMENT, "old light archive identifies the retired environment")
	runner.assert_true(SessionSaveSchema.upgrade(source).is_empty() and WorldSessionSnapshot.stage(adapter, source).is_empty(), "old light archive cannot stage into the current world")
	runner.assert_eq(adapter.load_game(ProjectSettings.globalize_path(LEGACY_PATH)), ERR_INVALID_DATA, "ordinary loading refuses the genuine old world")
	runner.assert_true(adapter.world_sim == live and live.map_data == terrain, "old loading refusal preserves original world and terrain owners")
	runner.assert_eq(_canonical(adapter), before, "old loading refusal preserves the complete current soul session")
	runner.assert_eq(_json(source), input, "refusal never edits the old input dictionary")
	runner.assert_eq(FileAccess.get_file_as_bytes(LEGACY_PATH), bytes, "refusal leaves the genuine archive byte-for-byte unchanged")
	runner.assert_eq(FileAccess.get_sha256(LEGACY_PATH), LEGACY_SHA, "the genuine archive retains its recorded hash")


func _canonical(adapter: WorldContinuityRuntime) -> String:
	return _json(WorldSessionSnapshot.capture(adapter))


func _json(value: Variant) -> String:
	return SnapshotValues.canonical_json(SnapshotValues.normalized(value))
