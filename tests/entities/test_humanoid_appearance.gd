extends RefCounted
## Eight real facings share phase without exchanging anatomical equipment.

const Appearance = preload("res://scripts/entities/humanoid_appearance.gd")


func run(runner: Object) -> void:
	var manifest: Variant = JSON.parse_string(FileAccess.get_file_as_string(Appearance.MANIFEST_PATH))
	runner.assert_true(manifest is Dictionary, "the eight-facing family has a concrete content manifest")
	if not manifest is Dictionary:
		return
	var errors: Array[String] = Appearance.validate_manifest(manifest)
	runner.assert_true(errors.is_empty(), "the complete generated family validates: " + str(errors))
	if not errors.is_empty():
		return
	var sampler := Appearance.new()
	runner.assert_true(sampler.configure(manifest, {}, false), "pure sampling can configure without loading GPU resources")
	_directions(runner)
	_phase(runner, sampler)
	_layer_selection(runner, sampler)
	_anatomical_sides(runner, sampler)
	_invalid_content(runner, manifest, sampler)
	_shared_resources(runner, manifest)
	print("SCENARIO eight-facing appearance: all independent directions, shared phase and action time, stable foot origin, anatomical attachments, real outer-use projection and explicit technical-only accessories")


func _directions(runner: Object) -> void:
	var vectors: Array[Vector2] = [Vector2.UP, Vector2(1, -1), Vector2.RIGHT, Vector2(1, 1), Vector2.DOWN, Vector2(-1, 1), Vector2.LEFT, Vector2(-1, -1)]
	for index: int in vectors.size():
		runner.assert_eq(Appearance.direction_index(vectors[index]), index, "screen movement selects its independent eight-way facing: " + Appearance.DIRECTIONS[index])
	runner.assert_eq(Appearance.direction_index(Vector2.ZERO, 6), 6, "an actual stop keeps the last westward facing")
	runner.assert_eq(Appearance.direction_index(Vector2.ZERO), 4, "a view with no prior facing has a deterministic southward default")
	runner.assert_eq(Appearance.direction_index(Vector2(NAN, 0), 2), 2, "an invalid transient direction cannot corrupt the previous eastward view")
	var near_border: Vector2 = Vector2.UP.rotated(deg_to_rad(24.0))
	runner.assert_eq(Appearance.direction_index(near_border), 1, "a direction beyond the exact sector boundary belongs to northeast")
	runner.assert_eq(Appearance.direction_index(near_border, 0, 5.0), 0, "a small boundary movement does not make the previous northward view flicker")
	var beyond_margin: Vector2 = Vector2.UP.rotated(deg_to_rad(29.0))
	runner.assert_eq(Appearance.direction_index(beyond_margin, 0, 5.0), 1, "a deliberate turn beyond the margin responds as northeast")
	var wrap_border: Vector2 = Vector2.UP.rotated(deg_to_rad(-24.0))
	runner.assert_eq(Appearance.direction_index(wrap_border, 0, 5.0), 0, "hysteresis works across the north/northwest angle wrap")


func _phase(runner: Object, sampler: RefCounted) -> void:
	var pose: Dictionary = {"direction": Vector2.RIGHT, "moving": true, "time_ms": 347}
	var source: Dictionary = pose.duplicate(true)
	var reference: Dictionary = sampler.sample(pose)
	var seen_rects: Dictionary = {}
	for index: int in Appearance.DIRECTIONS.size():
		var changed: Dictionary = pose.duplicate(true)
		changed.direction_index = index
		var sample: Dictionary = sampler.sample(changed)
		runner.assert_eq(sample.action, "walk", "actual movement uses the shared walk action in " + sample.direction_id)
		runner.assert_eq(sample.frame, reference.frame, "turning retains the identical gait frame in " + sample.direction_id)
		runner.assert_eq(sample.phase, reference.phase, "turning retains continuous action phase in " + sample.direction_id)
		runner.assert_eq(sample.origin, Vector2(48, 65), "changing direction never shifts the documented foot origin")
		runner.assert_true(not seen_rects.has(sample.rect), "every direction addresses independent atlas content: " + sample.direction_id)
		seen_rects[sample.rect] = true
		runner.assert_true(not sample.has("flip_h") and not sample.has("flip_v"), "the facing sample does not mirror the whole person")
	var route_change: Dictionary = pose.duplicate(true)
	route_change.started_ms = 340
	runner.assert_eq(sampler.sample(route_change).frame, reference.frame, "a route segment's new start cannot restart a shared walking gait")
	var next_cycle: Dictionary = pose.duplicate(true)
	next_cycle.time_ms += int(sampler.definition.actions.walk.cycle_ms)
	runner.assert_eq(sampler.sample(next_cycle).frame, reference.frame, "the same world-time cycle samples the same walk frame")
	var gesture: Dictionary = {"direction": Vector2.LEFT, "time_ms": 15347, "started_ms": 15000, "action": "gesture"}
	var action: Dictionary = sampler.sample(gesture)
	var shifted: Dictionary = gesture.duplicate(true)
	shifted.time_ms += 100000
	shifted.started_ms += 100000
	runner.assert_eq(sampler.sample(shifted).frame, action.frame, "a real action samples its own elapsed phase rather than global idle time")
	runner.assert_eq(sampler.sample(shifted).phase, action.phase, "the same actual action phase survives view reconstruction")
	var stopped: Dictionary = pose.duplicate(true)
	stopped.moving = false
	stopped.previous_direction = reference.direction
	stopped.direction = Vector2.ZERO
	var idle: Dictionary = sampler.sample(stopped)
	runner.assert_true(idle.action == "idle" and idle.direction == reference.direction, "stopping selects breathing while keeping the actual final facing")
	runner.assert_eq(sampler.sample(pose), reference, "sampling the same paused world time never advances an independent animation clock")
	runner.assert_eq(pose, source, "sampling never changes its input intent or action state")


func _layer_selection(runner: Object, sampler: RefCounted) -> void:
	var pose: Dictionary = {"direction": Vector2.DOWN, "time_ms": 300, "moving": true}
	var ordinary: Array[String] = sampler.visible_layer_ids(pose, {})
	runner.assert_true(ordinary.has("body") and ordinary.has("robe") and ordinary.has("detail"), "the human family retains its baseline visual clothing without inventing a naked-body rules contract")
	for id: String in ["sword_far", "sword_near", "jade_far", "jade_near", "cape_far", "cape_near"]:
		runner.assert_true(not ordinary.has(id), "ordinary appearance does not invent an absent worn or technical object: " + id)
	var clothes: Dictionary = {"body": {"shape": "robe", "color": "#345b79", "wet": true}, "outer": {"shape": "cape", "color": "#99834e", "wet": false}}
	var original: Dictionary = clothes.duplicate(true)
	var clothed: Array[String] = sampler.visible_layer_ids(pose, clothes)
	runner.assert_true(clothed.has("cape_far") and clothed.has("cape_near"), "an actual outer-use projection enables its near/far visual parts")
	runner.assert_true(not clothed.has("sword_near") and not clothed.has("jade_near"), "a rain cape does not grant a sword or jade")
	var technical: Dictionary = pose.duplicate(true)
	technical.technical_accessories = true
	var preview: Array[String] = sampler.visible_layer_ids(technical, clothes)
	for id: String in ["sword_far", "sword_near", "jade_far", "jade_near"]:
		runner.assert_true(preview.has(id), "an explicitly technical sample can display the asymmetric test object: " + id)
	var sample: Dictionary = sampler.sample(technical)
	var count: int = int(sampler.definition.layers.size())
	runner.assert_eq(preview.size(), count, "all visible parts share exactly the one sampled frame and ordering")
	for layer: Dictionary in sampler.definition.layers:
		runner.assert_true(sample.layer_order.has(str(layer.id)), "the sampled ordering includes the original visual layer exactly once: " + str(layer.id))
	runner.assert_eq(clothes, original, "changing preview visibility cannot alter real worn use, wetness or custody")
	runner.assert_eq(sampler.sample(technical).frame, sampler.sample(pose).frame, "adding technical accessory layers never restarts the underlying human action")


func _anatomical_sides(runner: Object, sampler: RefCounted) -> void:
	var south: Dictionary = sampler.sample({"direction_index": 4, "time_ms": 0})
	var north: Dictionary = sampler.sample({"direction_index": 0, "time_ms": 0})
	runner.assert_true(south.anchors.left_hand.position.x > south.anchors.right_hand.position.x, "front view places anatomical left on the observer's right")
	runner.assert_true(north.anchors.left_hand.position.x < north.anchors.right_hand.position.x, "back view changes screen projection while retaining anatomical left")
	runner.assert_true(south.anchors.right_waist.position.x < south.anchors.left_waist.position.x, "the front-view right-waist jade stays on its bodily side")
	runner.assert_true(north.anchors.right_waist.position.x > north.anchors.left_waist.position.x, "the back-view right waist is projected independently instead of swapped")
	var side_positions: Dictionary = {}
	var gait_anchors: Dictionary = {}
	for direction: int in Appearance.DIRECTIONS.size():
		for phase: int in [0, 1, 2, 3]:
			@warning_ignore("integer_division")
			var at: int = phase * int(sampler.definition.actions.gesture.cycle_ms) / 4
			var sample: Dictionary = sampler.sample({"direction_index": direction, "time_ms": at, "action": "gesture", "started_ms": 0, "technical_accessories": true})
			var left: Dictionary = sample.anchors.left_hand
			var right: Dictionary = sample.anchors.right_waist
			runner.assert_true(left.position.is_finite() and right.position.is_finite(), "asymmetric anchors exist at the real direction/action phase %d/%d" % [direction, phase])
			runner.assert_true(left.position != sample.anchors.right_hand.position, "the sword hand cannot alias the other hand at %d/%d" % [direction, phase])
			runner.assert_true(right.position != sample.anchors.left_waist.position, "the jade waist cannot alias the other waist at %d/%d" % [direction, phase])
			runner.assert_eq(sample.origin, south.origin, "gesture phase cannot move the ground origin at %d/%d" % [direction, phase])
			if phase == 0:
				side_positions[direction] = left.position
			if direction == 4:
				gait_anchors[phase] = left.position
	runner.assert_true(side_positions[2] != side_positions[6], "east and west have independently projected anatomical hand positions")
	runner.assert_true(gait_anchors[0] != gait_anchors[1] or gait_anchors[1] != gait_anchors[2], "the short action moves its actual attachment rather than showing a static pasted-on sword")


func _invalid_content(runner: Object, manifest: Dictionary, sampler: RefCounted) -> void:
	var before: Dictionary = sampler.sample({"time_ms": 500, "moving": true})
	for kind: String in ["direction", "missing_frame", "same_row", "mirrored", "foot", "anchor", "duplicate_layer", "unknown_layer", "duration", "texture", "hysteresis"]:
		var broken: Dictionary = manifest.duplicate(true)
		match kind:
			"direction": broken.frames.erase("NW")
			"missing_frame": broken.frames.NE.walk.pop_back()
			"same_row": broken.frames.NE.walk[0].rect[1] = broken.frames.E.walk[0].rect[1]
			"mirrored": broken.frames.W.idle[0]["flip_h"] = true
			"foot": broken.frames.S.walk[1].origin[0] += 1
			"anchor": broken.frames.NE.gesture[2].anchors.erase("right_waist")
			"duplicate_layer": broken.frames.S.idle[0].layer_order[1] = broken.frames.S.idle[0].layer_order[0]
			"unknown_layer": broken.frames.S.idle[0].layer_order[0] = "unregistered_equipment"
			"duration": broken.actions.walk.cycle_ms = 0
			"texture": broken.layers[0].texture = "user://untracked_art.png"
			"hysteresis": broken.erase("turn_hysteresis_degrees")
		runner.assert_true(not Appearance.validate_manifest(broken).is_empty(), "invalid appearance content reports a concrete diagnosis: " + kind)
		runner.assert_true(not sampler.configure(broken, {}, false), "invalid appearance content cannot replace the active sampler: " + kind)
		runner.assert_eq(sampler.sample({"time_ms": 500, "moving": true}), before, "failed appearance reconfiguration preserves the previously valid projection: " + kind)


func _shared_resources(runner: Object, manifest: Dictionary) -> void:
	var cached: RefCounted = Appearance.shared()
	runner.assert_true(cached == Appearance.shared(), "all human views reuse the same immutable family sampler and texture cache")
	runner.assert_true(cached.diagnostics.is_empty(), "the actual family textures load once with explicit atlas-size validation: " + str(cached.diagnostics))
	var texture_ids: Dictionary = {}
	for layer: Dictionary in manifest.layers:
		var id: String = str(layer.id)
		runner.assert_true(cached.textures.has(id), "the cached family retains the layer resource: " + id)
		if cached.textures.has(id):
			texture_ids[id] = cached.textures[id].get_instance_id()
	for direction: int in Appearance.DIRECTIONS.size():
		cached.sample({"direction_index": direction, "moving": true, "time_ms": 1137})
	for id: String in texture_ids:
		runner.assert_eq(cached.textures[id].get_instance_id(), texture_ids[id], "turning reuses the original shared texture instead of loading another copy: " + id)
