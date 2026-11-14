extends SceneTree
## Input lifetime, local preferences and direct-body geometry counterexamples.
const Bindings = preload("res://scripts/presentation/ui/input_bindings.gd")
const World = preload("res://scripts/sim/kernel/world.gd")
const Runner = preload("res://scripts/sim/kernel/runner.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const SessionIO = preload("res://scripts/sim/kernel/session_io.gd")
var errors: int = 0
var _seen: Dictionary = {}
var _frame: RefCounted

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)

func key(code: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = code
	event.keycode = code
	event.pressed = true
	return event

func fixture() -> RefCounted:
	var world := World.new()
	world.initialize(2, 0)
	for actor: int in world.actor_slots:
		world.release(actor)
		world.objects.records[actor].autonomous = false
		world.pages[0].modes[actor - 1] = world.Units.Mode.IDLE
		world.pages[0].positions[actor - 1] = Vector2(120.5 + actor * 10, 130.5)
	return world

func pump(runner: RefCounted) -> void:
	var packet: Dictionary = runner.poll()
	if packet.frame != null: _frame = packet.frame
	for receipt: Dictionary in packet.receipts: _seen[receipt.seq] = receipt

func reply(runner: RefCounted, seq: int) -> Dictionary:
	var deadline: int = Time.get_ticks_usec() + 3000000
	while not _seen.has(seq) and Time.get_ticks_usec() < deadline:
		await process_frame
		pump(runner)
	return _seen.get(seq, {})

func binding_cases() -> void:
	var source := Bindings.new()
	source.config_path = "user://p1-binding-smoke.cfg"
	DirAccess.remove_absolute(source.config_path)
	source.install()
	check(Bindings.validate(source.values).is_empty(), "Default action contexts conflict")
	var blocked: Dictionary = source.propose("game_heal", key(KEY_I))
	check(not blocked.ok and not blocked.has("swap"), "R/I swap introduced a third conflict with construction R")
	var swapped: Dictionary = source.propose("act_primary", key(KEY_F))
	check(not swapped.ok and not swapped.has("swap"), "Global F was swapped onto reserved interaction left click")
	var pair: Dictionary = source.propose("act_up", key(KEY_S))
	check(pair.has("swap") and Bindings.validate(pair.swap).is_empty(), "Safe two-key movement swap rejected")
	check(not source.propose("act_up", key(KEY_ESCAPE)).ok, "Escape exit was bindable")
	check(not source.propose("act_up", key(KEY_ALT)).ok, "System Alt could accidentally bind during task switching")
	var proposal: Dictionary = source.propose("act_primary", key(KEY_K))
	check(proposal.ok and source.commit(proposal.candidate) == OK, "Primary keyboard rebind did not save")
	var reloaded := Bindings.new()
	reloaded.config_path = source.config_path
	reloaded.install()
	check(reloaded.values.act_primary.code == KEY_K and InputMap.action_get_events("act_primary").size() == 1 and InputMap.action_has_event("act_primary", key(KEY_K)), "Preference reload reintroduced the default primary binding")
	var shift: Dictionary = reloaded.propose("act_step", key(KEY_SHIFT))
	check(shift.ok, "Single Shift could not bind to step")
	check(reloaded.commit(Bindings.defaults()) == OK and reloaded.values.game_heal.code == reloaded.values.game_rotate_take.code, "Reset lost legal cross-context R reuse")
	var invalid: Dictionary = reloaded.values.duplicate(true)
	invalid.act_up = {"kind": "key", "code": KEY_W | KEY_MASK_SHIFT}
	check(reloaded.commit(invalid) == ERR_INVALID_DATA, "Modifier bit mask was accepted as a physical key")
	invalid.act_up = {"kind": "mouse", "code": MOUSE_BUTTON_MIDDLE}
	check(reloaded.commit(invalid) == ERR_INVALID_DATA and reloaded.values.act_up.code == KEY_W, "Invalid candidate partially replaced live bindings")
	var config := ConfigFile.new()
	config.set_value("controls", "version", 1)
	config.set_value("actions", "act_up", "invalid")
	config.save(source.config_path)
	reloaded.install()
	check(not reloaded.notice.is_empty() and reloaded.values == Bindings.defaults(), "Corrupt preference did not fall back safely")
	DirAccess.remove_absolute(source.config_path)

func buffer_cases() -> RefCounted:
	var world: RefCounted = fixture()
	for actor: int in [1, 2]: world.combat.request(world, actor, "primary", Vector2.RIGHT)
	world.step(110)
	for actor: int in [1, 2]: check(world.combat.request(world, actor, "primary", Vector2.LEFT) == "buffered", "Fixture did not buffer next swing")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(world), 0)
	check(restored != null, "Buffered save candidate failed")
	if restored != null:
		world.combat.set_control(world, {"enabled": false})
		check(world.combat.states[1].buffer.is_empty() and not world.combat.states[2].buffer.is_empty(), "Input clear removed a committed action or NPC buffer")
		world.step(30)
		check(world.combat.states[1].kind == "slash_1" and world.combat.states[2].kind == "slash_2", "UI clear replayed player combo or canceled NPC combo")
	return restored

func geometry_cases() -> void:
	var world: RefCounted = fixture()
	var page: RefCounted = world.pages[0]
	# Thin wall with a real one-cell opening, checked from both directions.
	for x: int in range(116, 127): world.terrain.blocked[120 * 512 + x] = int(x != 121)
	for direction: int in [-1, 1]:
		page.positions[0] = Vector2(121.5, 123.0 if direction < 0 else 118.0)
		page.direct_velocities[0] = Vector2(0, direction * 5)
		for tick: int in 60:
			page.delta_ms = (tick + 1) * 1000 / 60 - tick * 1000 / 60
			page.advance_direct(0)
		check(world.terrain.can_stand(page.positions[0], page.radii[0]) and (page.positions[0].y < 120 if direction < 0 else page.positions[0].y > 121), "One-cell doorway could not be crossed")
	for x: int in range(116, 127): world.terrain.blocked[120 * 512 + x] = 0
	for y: int in range(118, 130): world.terrain.blocked[y * 512 + 122] = 1
	page.positions[0] = Vector2(121.5, 122.5)
	page.direct_velocities[0] = Vector2(1, 1).normalized() * 5
	for tick: int in 60:
		page.delta_ms = (tick + 1) * 1000 / 60 - tick * 1000 / 60
		page.advance_direct(0)
	check(page.positions[0].x < 121.651 and page.positions[0].y > 125.5 and world.terrain.can_stand(page.positions[0], page.radii[0]), "Diagonal wall slide stuck or crossed the wall")
	page.positions[0] = Vector2(120.5, 122.5)
	page.direct_velocities[0] = Vector2.RIGHT * 13
	page.delta_ms = 160
	page.advance_direct(0)
	check(page.positions[0].x < 121.651 and page.positions[0].x > 121.3, "Fast direct sweep crossed a wall")
	for y: int in range(118, 130): world.terrain.blocked[y * 512 + 122] = 0
	for offset: int in 6:
		world.terrain.blocked[120 * 512 + 120 + offset] = 1
		world.terrain.blocked[(120 + offset) * 512 + 120] = 1
	page.positions[0] = Vector2(123, 123)
	page.direct_velocities[0] = Vector2(-1, -1).normalized() * 5
	for tick: int in 60:
		page.delta_ms = 17
		page.advance_direct(0)
	check(page.positions[0].x >= 121.349 and page.positions[0].y >= 121.349 and world.terrain.can_stand(page.positions[0], page.radii[0]), "L corner admitted the body into a blocker")

func runner_cases(saved: RefCounted) -> void:
	var runner := Runner.new()
	var stale: int = runner.send({"kind": "action", "button": "primary", "aim": Vector2.UP})
	var ordinary: int = runner.send({"kind": "heal"})
	runner.invalidate_control()
	runner.drive({"enabled": true, "move": Vector2.ZERO, "aim": Vector2.RIGHT})
	runner.start(2, 0)
	var canceled: Dictionary = await reply(runner, stale)
	var ordinary_reply: Dictionary = await reply(runner, ordinary)
	check(canceled.get("reason") == "input_canceled", "Overwritten disable lost queued action invalidation")
	check(ordinary_reply.get("reason") == "no_potion_or_full", "Input lifetime canceled an ordinary world command")
	var fresh: Dictionary = await reply(runner, runner.send({"kind": "action", "button": "primary", "aim": Vector2.RIGHT}))
	check(fresh.get("reason") == "started", "Fresh action was rejected after input invalidation")
	runner.control(true, 1)
	runner.invalidate_control()
	if saved != null:
		var path: String = "user://p1-control-smoke.reol"
		var file := FileAccess.open(path, FileAccess.WRITE)
		file.store_var({"format": SessionIO.FORMAT, "state": Persistence.capture(saved)}, false)
		file.close()
		var loaded: Dictionary = await reply(runner, runner.send({"kind": "load", "path": path}))
		check(loaded.get("reason") == "loaded" and _frame.epoch > 1, "Buffered candidate did not load")
		runner.control(false, 1)
		var deadline: int = Time.get_ticks_usec() + 1000000
		while _frame.world_ms < 150 and Time.get_ticks_usec() < deadline:
			await process_frame
			pump(runner)
		check(_frame.combat.get(1, {}).get("kind") == "slash_1" and _frame.combat.get(2, {}).get("kind") == "slash_2", "Load replayed player buffer or erased NPC committed state")
		DirAccess.remove_absolute(path)
	runner.close()

func _run() -> void:
	binding_cases()
	var saved: RefCounted = buffer_cases()
	geometry_cases()
	await runner_cases(saved)
	print("CONTROL_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
