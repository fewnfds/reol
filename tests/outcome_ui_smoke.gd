extends "res://tests/abilities_ui_smoke.gd"
const World = preload("res://scripts/sim/kernel/world.gd")
const Outcome = preload("res://scripts/sim/kernel/outcome.gd")
const Impact = preload("res://scripts/presentation/impact.gd")
const Frame = preload("res://scripts/sim/kernel/frame.gd")
const ActionEffects = preload("res://scripts/presentation/action_effects.gd")

func shield_events() -> void:
	var w := World.new()
	w.initialize(4, 0)
	w.outcomes.clear()
	w.defense.shield(w, 2, 1, 20, 10, 0)
	w.defense.prepare(w, 10)
	w.defense.shield(w, 3, 1, 20, 100, 10)
	w.defense.absorb(w, 1, 25, Vector2.LEFT, 11)
	var ended: Array[Dictionary] = []
	for event: Dictionary in w.outcomes:
		if event.kind == "shield_removed": ended.append(event)
	check(ended.size() == 2 and ended[0].actor == 2 and ended[0].target == 1 and ended[0].reason == "expired", "Shield expiry lost its source/subject")
	check(ended.size() == 2 and ended[1].actor == 3 and ended[1].reason == "broken" and ended[0].shield != ended[1].shield, "Shield break lost its stable instance identity")
	w.emit({"kind": "world_notice", "target": 1})
	check(w.outcomes.back().actor == 0 and Outcome.subject(w.outcomes.back()) == 1, "World event invented a caster or lost its subject")

func transfer_feedback() -> void:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor)
		w.objects.records[actor].autonomous = false
		w.objects.records[actor]["side"] = 0
	w.pages[0].positions[0] = Vector2(120.5, 120.5)
	var pile: int = w.objects.create("pile", "grain", w.Terrain.index(Vector2i(120, 120)))
	w.objects.add(pile, "grain", 2)
	w.outcomes.clear()
	for operation: String in ["take", "put"]:
		check(w.begin_transfer(1, {"kind": operation, "target": pile, "item": "grain", "amount": 1}) == "accepted", "Transfer presentation fixture refused " + operation)
		w.step(400)
	var frame := Frame.new()
	frame.world_ms = w.elapsed_ms
	frame.actor_slots = w.actor_slots.duplicate()
	frame.positions = w.pages[0].positions.duplicate()
	frame.visible = PackedByteArray([1, 1, 1, 1])
	var events: Array[Dictionary] = []
	for event: Dictionary in w.outcomes:
		if event.kind == "transferred" and event.actor == 1:
			events.append(event)
			check(event.target == pile and not frame.actor_slots.has(event.target), "Transfer notification changed the actual inventory subject")
			check(Impact.subject(event) == 1 and Impact.visible(frame, event, true), "Static storage target hid the worker's transfer feedback")
	check(events.size() == 2 and w.objects.amount(pile, "grain") == 2, "Take/put fixture did not commit both real transfers")
	var effects := ActionEffects.new()
	effects.adopt(frame, events, true)
	check(effects._effects.size() == 2, "Actual take/put outcomes did not create transfer effects")
	for effect: Dictionary in effects._effects:
		check(effect.target == 1 and effect.position == frame.positions[frame.actor_slots[1]], "Transfer effect used a static inventory as its body anchor")
	effects.free()

func _run() -> void:
	shield_events()
	transfer_feedback()
	game = Game.new()
	game._combat_lab = true
	game._fps = 60
	game.controls.bindings.config_path = "user://outcome-ui-controls.cfg"
	game.feedback.config_path = "user://outcome-ui-feedback.cfg"
	root.add_child(game)
	current_scene = game
	if not await until(func(): return game.frame != null): check(false, "Outcome GUI not ready"); quit(1); return
	var epoch: int = game.frame.epoch
	game.runner.send({"kind": "combat_practice", "mode": "light", "loadout": "guardian"})
	check(await until(func(): return game.frame.epoch > epoch), "Shield practice failed")
	game.runner.send({"kind": "action", "button": "skill", "aim": Vector2.RIGHT})
	check(await until(func(): return not game.frame.shields.is_empty()), "Real shield never created")
	check(await until(func(): return game.frame.shields.is_empty() and game.frame.world_ms > 1300), "Real shield removal was not adopted")
	var frame: RefCounted = game.frame
	var anonymous: Dictionary = Outcome.envelope({"kind": "world_notice", "target": 1}, frame.world_ms)
	var departed: Dictionary = Outcome.envelope({"kind": "healed", "actor": 999999, "target": 1}, frame.world_ms)
	check(Impact.visible(frame, anonymous, true) and Impact.visible(frame, departed, true), "Affected player became invisible with an absent effect source")
	var ignored: Array = [anonymous, Outcome.envelope({"kind": "shield_removed", "actor": 999999, "target": 1, "reason": "expired"}, frame.world_ms)]
	game.action_effects.adopt(frame, ignored, true)
	game.combat_audio.adopt(frame, ignored, true)
	game.queue_free()
	await process_frame
	await process_frame
	for path: String in ["user://outcome-ui-controls.cfg", "user://outcome-ui-feedback.cfg"]:
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	print("OUTCOME_UI_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
