extends SceneTree
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const Motion = preload("res://scripts/sim/kernel/motion.gd")
var errors: int = 0

func _initialize() -> void: call_deferred("_run")

func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)

func fixture() -> RefCounted:
	var w := World.new()
	w.initialize(4, 0)
	for actor: int in w.actor_slots:
		w.release(actor)
		w.objects.records[actor].autonomous = false
		w.pages[0].modes[actor - 1] = w.Units.Mode.IDLE
		w.pages[0].positions[actor - 1] = Vector2(120.5 + actor * 8, 120.5)
	return w

func _run() -> void:
	var w: RefCounted = fixture()
	var page: RefCounted = w.pages[0]
	page.positions[0] = Vector2(120.5, 120.5)
	page.positions[1] = Vector2(121.6, 120.5)
	page.positions[2] = Vector2(119.4, 120.5)
	check(not w.command({"kind": "attack_move", "position": Vector2(130, 130)}).ok and not w.command({"kind": "hold"}).ok and not w.command({"kind": "attack", "target": 2}).ok and not w.command({"kind": "stop"}).ok, "Retired RTS command still accepted")
	check(w.command({"kind": "action", "button": "primary", "aim": Vector2.RIGHT}).ok, "Primary action did not start")
	for kind: String in ["move", "equip", "interrupt", "work"]:
		check(w.command({"kind": kind, "position": Vector2(130, 130), "item": "short_bow"}).reason == "action_committed", "Lifecycle command bypassed action commitment: " + kind)
	check(w.command({"kind": "action", "button": "step", "aim": Vector2.RIGHT}).reason == "action_committed", "Unconfirmed opening was cancelled before contact")
	w.command({"kind": "talk", "actor": 2, "target": 1})
	check(w.combat.states.has(1), "A social invitation cancelled the target's committed strike")
	w.release(2)
	check(page.health[1] == 100, "Primary applied immediate damage without windup")
	w.step(69)
	check(page.health[1] == 100, "Melee hit before active phase")
	w.step(1)
	w.step(1)
	check(page.health[1] == 65 and page.health[2] == 100, "Directional melee shape or windup failed")
	w.step(50)
	check(page.health[1] == 65, "One swing hit same body twice")
	check(w.command({"kind": "action", "button": "primary", "aim": Vector2.LEFT}).reason == "buffered", "Combo input did not buffer")
	w.step(9)
	w.step(1)
	check(w.combat.states[1].kind == "slash_2" and w.combat.states[1].direction == Vector2.LEFT, "Combo did not consume the new direction once")
	var saved: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(saved != null, "Mid-action candidate rejected")
	if saved != null:
		w.step(120)
		saved.step(120)
		check(saved.pages[0].health == page.health and saved.combat.states[1].kind == w.combat.states[1].kind, "Mid-action restore repeated or lost a hit")
	var move_world: RefCounted = fixture()
	var start: Vector2 = move_world.pages[0].positions[0]
	move_world.combat.set_control(move_world, {"enabled": true, "move": Vector2(1, 1), "aim": Vector2.LEFT})
	for index: int in 60: move_world.step((index + 1) * 1000 / 60 - index * 1000 / 60)
	check(is_equal_approx(move_world.elapsed_ms, 1000) and absf(start.distance_to(move_world.pages[0].positions[0]) - 5.0) < 0.001, "60Hz movement drift or diagonal acceleration")
	check(move_world.pages[0].aims[0] == Vector2.LEFT and move_world.environment.updates == 2, "Aim followed movement or slow environment ran at heartbeat frequency")
	move_world.combat.set_control(move_world, {"enabled": false})
	var stopped: Vector2 = move_world.pages[0].positions[0]
	move_world.step(50)
	check(move_world.pages[0].positions[0] == stopped, "Clearing continuous intent did not stop movement")
	check(Motion.capsule_hit(Vector2(-1, 0), Vector2(2, 0), Vector2.ZERO, Vector2(1, 0), 0.1) >= 0, "Capsule sweep missed crossing")
	check(Motion.capsule_hit(Vector2(-1, 1), Vector2(2, 1), Vector2.ZERO, Vector2(1, 0), 0.1) < 0, "Capsule sweep hit a distant path")
	shapes(move_world)
	steps()
	archery()
	consequences()
	print("ACT_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)

func shapes(w: RefCounted) -> void:
	var polygon: PackedVector2Array = w.combat.Defs.sector(w.combat.Defs.ACTIONS.slash_1, Vector2.RIGHT)
	var before := Vector2(3, -3)
	var after := Vector2(3, 3)
	var knots := PackedVector3Array([Vector3(3, -3, 0), Vector3(1, 0, 0.5), Vector3(3, 3, 1)])
	check(Motion.polygon_hit(before, after, polygon, 0.35) < 0 and Motion.shape_hit(Vector2.ZERO, Vector2.ZERO, PackedVector3Array(), before, after, knots, polygon, 0.35) >= 0, "Melee missed a target that turned through its sector")
	check(Motion.shape_hit(-before, -after, PackedVector3Array([-knots[0] * Vector3(1, 1, -1), -knots[1] * Vector3(1, 1, -1), -knots[2] * Vector3(1, 1, -1)]), Vector2.ZERO, Vector2.ZERO, PackedVector3Array(), polygon, 0.35) >= 0, "Melee ignored the attacker's turning path")
	check(Motion.hit_fraction(Vector2(0, 0), Vector2(2, 0), before, after, 0.35, knots) >= 0, "Projectile missed a turning target")
	w.terrain.blocked[120 * 512 + 125] = 1
	var hit: Dictionary = Motion.wall_hit(w.terrain, Vector2(124, 119.95), Vector2(126, 119.95), 0.1)
	check(hit.fraction >= 0 and hit.tile == 120 * 512 + 125, "Projectile radius did not graze the wall volume")

func steps() -> void:
	var w: RefCounted = fixture()
	var page: RefCounted = w.pages[0]
	var start: Vector2 = page.positions[0]
	check(w.combat.request(w, 1, "step", Vector2.RIGHT) == "started", "Neutral step failed")
	w.step(160)
	check(absf(page.positions[0].x - start.x + 2.08) < 0.002, "Neutral step did not move backward for 160ms")
	var stop: Vector2 = page.positions[0]
	w.step(61)
	check(page.positions[0] == stop and w.combat.request(w, 1, "step", Vector2.UP) == "cooldown", "Step recovery moved or cooldown was bypassed")
	w.step(479)
	check(w.combat.request(w, 1, "step", Vector2.RIGHT, Vector2.UP) == "started", "Step did not refresh at its world-time cooldown")
	w.step(10)
	check(page.positions[0].y < stop.y, "Directional step ignored held movement")
	w.combat.damage(w, 2, 1, 10, w.elapsed_ms)
	check(page.health[0] == 90, "Step accidentally granted invulnerability")
	var slash: RefCounted = fixture()
	slash.pages[0].positions[1] = slash.pages[0].positions[0] + Vector2.RIGHT
	slash.combat.request(slash, 1, "primary", Vector2.RIGHT)
	slash.step(71)
	check(slash.combat.request(slash, 1, "step", Vector2.RIGHT) == "started", "Confirmed light strike could not cancel into step")

func archery() -> void:
	var w: RefCounted = fixture()
	for row: int in range(1, 4): w.pages[0].positions[row] = Vector2(250 + row * 8, 250)
	check(w.command({"kind": "equip", "item": "short_bow"}).ok, "Real bow did not equip")
	w.combat.set_control(w, {"enabled": true, "move": Vector2.ZERO, "aim": Vector2.RIGHT, "primary": true})
	w.step(159)
	check(w.combat.shots == 0, "Bow fired before its windup")
	w.step(2)
	check(w.combat.shots == 1 and w.combat.bolts[1].born_ms == 160, "Bow did not commit exactly at the active boundary")
	w.step(439)
	check(w.combat.shots == 2, "Held bow did not repeat after recovery")
	w.combat.set_control(w, {"enabled": false})
	w.step(600)
	check(w.combat.shots == 2, "Released bow continued firing")
	check(w.combat.request(w, 1, "skill", Vector2.RIGHT) == "started", "Bow skill failed")
	w.step(181)
	check(w.combat.shots == 7, "Bow skill did not launch a five-bolt fan")
	var captured: Dictionary = Persistence.capture(w)
	var restored: RefCounted = Persistence.candidate(captured, 0)
	check(restored != null, "Active fan/projectile/cooldown save rejected")
	if restored != null:
		check(restored.combat.controls.is_empty(), "Save restored held input")
		w.step(400)
		restored.step(400)
		check(restored.combat.bolts == w.combat.bolts and restored.combat.shots == w.combat.shots and restored.combat.cooldowns == w.combat.cooldowns, "Restored projectiles/cooldowns diverged")
		check(restored.combat.request(restored, 1, "skill", Vector2.RIGHT) == "cooldown", "Load bypassed skill cooldown")
	var invalid: Dictionary = captured.duplicate(true)
	invalid.domains.combat.unreachable[1] = {"targets": {2: -1}, "topology": 1, "flight": 0, "large": false}
	check(Persistence.candidate(invalid, 0) == null, "Malformed unreachable memory entered live state")
	invalid = captured.duplicate(true)
	invalid.domains.combat.states[1].buffer = {"aim": Vector2.ZERO, "until": w.elapsed_ms}
	check(Persistence.candidate(invalid, 0) == null, "Malformed combo buffer entered live state")
	invalid = captured.duplicate(true)
	invalid.domains.combat.bolts[1].radius = NAN
	check(Persistence.candidate(invalid, 0) == null, "Nonfinite projectile radius entered live state")

func consequences() -> void:
	var w: RefCounted = fixture()
	var page: RefCounted = w.pages[0]
	page.positions[1] = page.positions[0] + Vector2(2, 0)
	w.combat.next_activation = 2
	for index: int in 2: w.combat.launch(1, page.positions[0], page.positions[1], 0, 20, 1)
	w.step(100)
	check(page.health[1] == 80, "Same-volley bullets stacked damage within protection window")
	w.combat.engagements.clear()
	w.combat.launch(1, page.positions[0], page.positions[1], w.elapsed_ms, 20)
	w.combat.damage(w, 2, 1, 10000, w.elapsed_ms)
	w.step(100)
	check(page.health[1] == 60, "A committed projectile vanished with its shooter's death")
	var removed: int = 2
	var old_slot: int = w.actor_slots[removed]
	w.remove_actor(removed)
	var actor: int = w.spawn_actor(120 * 512 + 140)
	check(w.actor_slots[actor] == old_slot and not w.combat.status.has(actor) and not w.combat.cooldowns.has(actor) and page.aims[old_slot] == Vector2.RIGHT and page.direct_velocities[old_slot] == Vector2.ZERO, "Reused body slot inherited combat state")
	var life: RefCounted = fixture()
	var target: int = life.source_objects[life.pages[0].source_ids[0]]
	life.reservations[target] = 1
	life.pages[0].modes[0] = life.Units.Mode.HARVEST
	life.combat.request(life, 1, "primary", Vector2.RIGHT)
	check(not life.reservations.has(target), "Starting a strike leaked a harvest reservation")
	life.release(1)
	life.reservations[target] = 1
	life.pages[0].modes[0] = life.Units.Mode.HARVEST
	life.combat.damage(life, 2, 1, 5, 0)
	check(not life.reservations.has(target) and life.pages[0].modes[0] == life.Units.Mode.IDLE, "Ranged damage did not release the player's work reservation")
	life.command({"kind": "take", "target": target, "item": "wood", "amount": 1})
	check(life.actions.has(1), "Work interruption fixture did not start its real transfer")
	life.combat.damage(life, 2, 1, 5, 0)
	check(not life.actions.has(1), "Ranged damage left the player's lifecycle action pending")
	life.combat.damage(life, 2, 1, 5, 0, Vector2.LEFT, 0, 80, 2.0)
	check(life.command({"kind": "work"}).reason == "stunned", "Lifecycle command entered a stuck process during hit-stun")
