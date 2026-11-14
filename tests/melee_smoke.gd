extends SceneTree
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
var errors: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)

func fixture() -> RefCounted:
	var w := World.new()
	w.initialize(4, 0)
	for id: int in w.actor_slots:
		w.release(id)
		w.objects.records[id].autonomous = false
		w.pages[0].positions[id - 1] = Vector2(120.5 + (id - 1) * 8, 120.5)
		w.pages[0].modes[id - 1] = w.Units.Mode.IDLE
	return w

func advance(w: RefCounted, until: int) -> void:
	while w.elapsed_ms < until: w.step(mini(16, until - w.elapsed_ms))

func combo() -> void:
	var w: RefCounted = fixture()
	w.pages[0].positions[1] = w.pages[0].positions[0] + Vector2(1.1, 0)
	w.objects.records[2]["base_stats"] = {"max_hp": 1000.0}
	w.Equipment.rebuild(w, 2)
	w.pages[0].health[1] = 1000
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 71)
	check(w.combat.states[1].confirmed, "Real hit did not confirm")
	check(w.combat.request(w, 1, "primary", Vector2.RIGHT) == "buffered", "Next slash could not buffer")
	advance(w, 191)
	check(w.combat.states[1].kind == "slash_2" and w.combat.states[1].started_ms == 190, "Second slash ignored explicit cancel time")
	advance(w, 291)
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 551)
	check(w.combat.states[1].kind == "slash_3" and w.pages[0].health[1] < 900, "Finisher did not reach its target")
	advance(w, 641)
	check(w.combat.request(w, 1, "primary", Vector2.RIGHT) == "action_committed" and w.combat.states[1].kind == "slash_3", "Finisher freely skipped recovery")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "P2 committed swing did not restore")
	if restored != null:
		advance(w, 1100)
		advance(restored, 1100)
		check(w.pages[0].health == restored.pages[0].health and w.pages[0].positions == restored.pages[0].positions, "Restored swing repeated damage or changed displacement")

func defense() -> void:
	var w: RefCounted = fixture()
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 50)
	check(w.combat.request(w, 1, "step", Vector2.RIGHT, Vector2.UP) == "buffered", "Early defensive press was swallowed")
	advance(w, 151)
	check(w.combat.states[1].kind == "slash_1" and not w.combat.intents.has(1), "Whiff retained an expired dash")
	check(w.combat.request(w, 1, "step", Vector2.RIGHT) == "buffered", "Near cancel dash did not buffer")
	advance(w, 161)
	check(w.combat.states[1].kind == "step" and not w.combat.chains.has(1), "Dash did not reset combo")
	w.combat.damage(w, 2, 1, 10, w.elapsed_ms, Vector2.LEFT, 12, 90, 0.1, {"evadable": true})
	check(w.pages[0].health[0] == 100, "Dash failed its leading evade window")
	advance(w, 250)
	w.combat.damage(w, 2, 1, 10, w.elapsed_ms, Vector2.LEFT, 13, 90, 0.1, {"evadable": true})
	check(w.pages[0].health[0] == 90, "Dash evade interval included its exclusive endpoint")
	advance(w, 300)
	check(w.command({"kind": "action", "button": "step", "aim": Vector2.LEFT}).reason == "cooldown", "Hit-stun tail accepted a dash with unreachable cooldown")
	check(not w.combat.intents.has(1), "Cooldown queued a delayed dash")
	var fresh: RefCounted = fixture()
	fresh.combat.damage(fresh, 2, 1, 1, 0, Vector2.LEFT, 1, 90, 0.0)
	advance(fresh, 20)
	check(fresh.command({"kind": "action", "button": "step", "aim": Vector2.RIGHT, "move": Vector2.UP}).reason == "buffered", "Stun-tail action was rejected by world adapter")
	advance(fresh, 91)
	check(fresh.combat.states[1].kind == "step" and fresh.combat.states[1].direction == Vector2.UP, "Buffered escape lost its pressed direction")
	var pushed: RefCounted = fixture()
	pushed.combat.damage(pushed, 2, 1, 1, 0, Vector2.LEFT, 1, 40, 0.45)
	advance(pushed, 41)
	var before: Vector2 = pushed.pages[0].positions[0]
	pushed.combat.request(pushed, 1, "step", Vector2.RIGHT, Vector2.UP)
	advance(pushed, 90)
	check(absf(pushed.pages[0].positions[0].x - before.x) < 0.001 and pushed.pages[0].positions[0].y < before.y, "Residual knockback hijacked a legal dash")

func projectiles() -> void:
	var w: RefCounted = fixture()
	w.pages[0].positions[1] = Vector2(121.0, 120.5)
	w.pages[0].positions[2] = Vector2(123.5, 120.5)
	w.combat.request(w, 2, "step", Vector2.LEFT, Vector2.RIGHT)
	w.combat.launch(1, w.pages[0].positions[0], w.pages[0].positions[2], 0)
	advance(w, 20)
	check(w.pages[0].health[1] == 100 and w.combat.bolts[1].passed.has(2), "Arrow did not pass a dodging body")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "In-flight evade history did not save")
	advance(w, 150)
	check(w.pages[0].health[2] == 80 and w.pages[0].health[1] == 100, "Evaded arrow vanished or hit its tail twice")
	if restored != null:
		advance(restored, 150)
		check(restored.pages[0].health == w.pages[0].health, "Restored arrow forgot passed identity")
	var blade: RefCounted = fixture()
	blade.pages[0].positions[1] = blade.pages[0].positions[0] + Vector2(0.6, 0)
	blade.combat.request(blade, 2, "step", Vector2.LEFT)
	blade.combat.request(blade, 1, "primary", Vector2.RIGHT)
	advance(blade, 131)
	check(blade.pages[0].health[1] == 100 and not blade.combat.states[1].confirmed and blade.combat.states[1].hit.has(2), "Evaded single slash gave false confirm or tail damage")

func reactions() -> void:
	var w: RefCounted = fixture()
	w.objects.records[2]["combat_style"] = "trained"
	w.objects.records[2]["ability_loadout"] = "heavy"
	w.combat.request(w, 2, "primary", Vector2.LEFT)
	var ready: int = w.combat.status[2].ready_ms
	var hit: Dictionary = w.combat.damage(w, 1, 2, 1, 0, Vector2.LEFT, 1, 200, 0.35, {"heavy_hit": true, "action": "slash_3"})
	check(hit.armored and w.combat.states[2].kind == "enemy_heavy", "Heavy opening was interrupted by a finisher")
	advance(w, 651)
	w.combat.damage(w, 1, 2, 1, 651, Vector2.LEFT, 2, 90, 0.12)
	check(not w.combat.states.has(2) and w.combat.status[2].ready_ms >= ready, "Light hit washed away committed recovery")
	var punish: Dictionary = w.combat.damage(w, 1, 2, 1, 651, Vector2.LEFT, 3, 240, 0.45, {"heavy_hit": true, "action": "cleave"})
	check(punish.off_balance and w.combat.status[2].punished, "Recovery punish was lost after an earlier light hit")
	var second: Dictionary = w.combat.damage(w, 1, 2, 1, 651, Vector2.LEFT, 4, 240, 0.45, {"heavy_hit": true, "action": "cleave"})
	check(not second.off_balance, "Same enemy action granted repeated recovery punishes")
	var light: RefCounted = fixture()
	for index: int in 5: light.combat.damage(light, 2, 1, 1, 0, Vector2.LEFT, index + 1, 110, 0.10)
	check(light.combat.status[1].stun_until <= Defs.CONTROL_BUDGET_MS, "Overlapping control exceeded its budget")
	advance(light, 120)
	for index: int in 4: light.combat.damage(light, 2, 1, 1, light.elapsed_ms, Vector2.LEFT, index + 10, 110, 0.10); advance(light, light.elapsed_ms + 115)
	var protected: Dictionary = light.combat.damage(light, 2, 1, 1, light.elapsed_ms, Vector2.LEFT, 30, 110, 0.10)
	check(protected.armored and protected.damage == 1, "Anti-control protection incorrectly blocked HP damage")

func late_contacts() -> void:
	var w: RefCounted = fixture()
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 40)
	w.combat.request(w, 1, "step", Vector2.RIGHT, Vector2.UP)
	advance(w, 112)
	w.pages[0].positions[1] = w.pages[0].positions[0] + Vector2(1.906, 0)
	w.pages[0].modes[1] = w.Units.Mode.DIRECT
	w.pages[0].direct_velocities[1] = Vector2(-2, 0)
	w.step(16)
	check(w.combat.states[1].kind == "step" and w.combat.states[1].started_ms == 120, "A late real confirm lost the final buffered dash boundary")
	var whiff: RefCounted = fixture()
	whiff.combat.request(whiff, 1, "primary", Vector2.RIGHT)
	advance(whiff, 120)
	whiff.combat.cooldowns[1] = {"step": 150}
	check(whiff.combat.request(whiff, 1, "step", Vector2.RIGHT) == "buffered", "Whiff cancel rejected a cooldown ready at the legal action boundary")
	advance(whiff, 161)
	check(whiff.combat.states[1].kind == "step" and whiff.combat.states[1].started_ms == 160, "Whiff cancel became a cooldown-only queue")
	var early: RefCounted = fixture()
	early.combat.request(early, 1, "primary", Vector2.RIGHT)
	advance(early, 120)
	early.combat.cooldowns[1] = {"step": 150}
	early.combat.request(early, 1, "step", Vector2.RIGHT)
	early.pages[0].positions[1] = early.pages[0].positions[0] + Vector2(1.0, 0)
	advance(early, 151)
	check(early.combat.states[1].kind == "slash_1" and not early.combat.intents.has(1), "An early confirm retained an action just to wait out its cooldown")
	var combo_late: RefCounted = fixture()
	combo_late.combat.request(combo_late, 1, "primary", Vector2.RIGHT)
	advance(combo_late, 80)
	check(combo_late.combat.request(combo_late, 1, "primary", Vector2.RIGHT) == "buffered", "A potential real hit could not admit a short next-slash intent")
	combo_late.pages[0].positions[1] = combo_late.pages[0].positions[0] + Vector2(1.0, 0)
	advance(combo_late, 191)
	check(combo_late.combat.states[1].kind == "slash_2" and combo_late.combat.states[1].started_ms == 190, "Late contact failed to unlock the buffered next slash")
	var miss: RefCounted = fixture()
	miss.combat.request(miss, 1, "primary", Vector2.RIGHT)
	advance(miss, 80)
	miss.combat.request(miss, 1, "primary", Vector2.RIGHT)
	advance(miss, 241)
	check(miss.combat.states[1].kind == "slash_1" and not miss.combat.intents.has(1), "A missed confirm extended the old next-slash intent")
	var brain: RefCounted = fixture()
	brain.pages[0].positions[1] = brain.pages[0].positions[0] + Vector2(1.5, 0)
	brain.objects.records[2]["combat_style"] = "trained"
	brain.combat.engage(brain, 2, 1)
	brain.combat.engagements[2].react_ms = 120
	advance(brain, 123)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(brain), 0)
	check(restored != null, "NPC decision phase did not restore")
	if restored != null:
		advance(brain, 140)
		advance(restored, 140)
		check(not brain.combat.states.has(2) and not restored.combat.states.has(2), "Restore advanced the next NPC decision before its original boundary")
	var dead: RefCounted = fixture()
	dead.pages[0].positions[1] = dead.pages[0].positions[0] + Vector2(1.0, 0)
	dead.pages[0].health[1] = 1
	dead.objects.records[2]["combat_style"] = "trained"
	dead.objects.records[2]["ability_loadout"] = "heavy"
	dead.combat.request(dead, 2, "primary", Vector2.LEFT)
	dead.combat.launch(1, dead.pages[0].positions[0], dead.pages[0].positions[1], 0)
	advance(dead, 32)
	check(dead.pages[0].health[1] == 0 and dead.combat.action_segments[0].until_ms < 32, "An unstaggered arrow death retained a future danger segment")

func _run() -> void:
	combo()
	defense()
	projectiles()
	reactions()
	late_contacts()
	print("MELEE_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
