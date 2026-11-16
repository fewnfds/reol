extends "res://tests/abilities_smoke.gd"
## Cross-domain state, legal handoffs and actual strategy outputs.
const Policy = preload("res://scripts/sim/definitions/decisions/policy_def.gd")
const Rule = preload("res://scripts/sim/definitions/decisions/rule_def.gd")

func advance(w: RefCounted, until: int, _passive: bool = false) -> void:
	while w.elapsed_ms < until: w.step(mini(16, until - w.elapsed_ms))

func setup_actor(w: RefCounted, actor: int, loadout: String, strategy: String) -> void:
	w.objects.records[actor]["ability_loadout"] = loadout
	w.objects.records[actor]["side"] = 1
	w.objects.records[actor]["combatant"] = true
	w.objects.records[actor]["base_stats"] = {"max_hp": 1000.0}
	w.Equipment.rebuild(w, actor)
	w.pages[0].health[actor - 1] = 1000
	check(w.decisions.bind(w, actor, strategy) == "bound", "Could not bind " + strategy)

func authoring() -> void:
	var w: RefCounted = fixture()
	check(w.decisions.Defs.ERRORS.is_empty() and w.decisions.Defs.POLICIES.size() == 7, "Strategy library failed compilation")
	check(w.decisions.Defs.POLICIES.is_read_only() and w.decisions.Defs.POLICIES.ranged.rules.is_read_only(), "Shared strategy definitions remain mutable")
	var rule := Rule.new()
	rule.action = "sequence"
	rule.sequence = PackedStringArray(["unknown"])
	check(not rule.errors().is_empty(), "Unknown sequence instruction accepted")
	var bad := Policy.new()
	bad.id = "bad"
	bad.title = "Bad"
	bad.preferred_min = 8.0
	bad.preferred_max = 4.0
	check(not bad.errors().is_empty(), "Inverted distance band accepted")
	check(w.decisions.bind(w, 2, "ranged", {"min": 9.0}) == "invalid_distance_band", "Invalid unit overrides accepted")
	check(w.decisions.bind(w, 2, "ranged", {"arbitrary_code": 1}) == "invalid_policy", "Arbitrary parameter accepted")

func living_handoff() -> void:
	var w: RefCounted = fixture()
	var page: RefCounted = w.pages[0]
	var source: int = w.source_objects[0]
	var point: Vector2 = w.Terrain.center(w.objects.records[source].tile)
	page.positions[1] = point
	page.positions[2] = point + Vector2(4, 0)
	w.objects.records[2].autonomous = true
	w.objects.records[3]["side"] = 1
	w.decisions.bind(w, 2, "cautious")
	w.adopt_work(2, 0)
	page.source_ids[1] = 0
	page.modes[1] = w.Units.Mode.HARVEST
	page.due_ms[1] = 500
	w.reservations[source] = 2
	w.objects.transfer(source, 2, "wood", 1)
	w._sync_inventory(2)
	var original: Dictionary = w.gate.current(2)
	check(w.combat.remember_contact(w, 2, 3, Vector2(-1, -1), false, 0) == "accepted", "Visible threat not remembered")
	check(w.gate.current(2) == original and w.reservations.get(source) == 2, "Observation preempted work before a decision")
	w.step(1)
	check(w.decisions.records[2].mode == "flee" and not w.reservations.has(source) and not w.work_runs.has(2), "Flee did not release the original work")
	check(w.objects.amount(2, "wood") == 1, "Task preemption rolled back delivered cargo")
	w.settle(2, 0, original)
	check(w.decisions.records[2].mode == "flee", "Old work callback overwrote a newer decision")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Flee/task candidate failed restore")
	if restored != null:
		advance(w, 201)
		advance(restored, 201)
		check(w.pages[0].positions == restored.pages[0].positions, "Saved autonomous movement was lost or re-decided early")
	w.objects.records[3]["combatant"] = false
	w.objects.records[3].side = 0
	w.combat.finish(w, 2, w.elapsed_ms)
	w.step(20)
	check(not w.decisions.in_combat(2) and (w.actions.has(2) or w.work_runs.has(2)), "Leaving danger did not reselect actual life work")

func strategies() -> void:
	var pressure: RefCounted = fixture()
	setup_actor(pressure, 2, "sword", "pressure")
	pressure.pages[0].positions[1] = pressure.pages[0].positions[0] + Vector2(3.5, 0)
	pressure.pages[0].max_health[0] = 5000
	pressure.pages[0].health[0] = 5000
	pressure.objects.records[1]["base_stats"] = {"max_hp": 5000.0}
	pressure.combat.engage(pressure, 2, 1)
	advance(pressure, 301)
	check(pressure.decisions.records[2].task.get("kind", "") == "sequence", "Pressure policy did not create a multi-action task")
	var save: RefCounted = Persistence.candidate(Persistence.capture(pressure), 0)
	check(save != null, "Mid-sequence state was rejected")
	advance(pressure, 1601)
	if save != null:
		advance(save, 1601)
		check(pressure.pages[0].health == save.pages[0].health and pressure.combat.next_activation == save.combat.next_activation, "Sequence restore repeated costs or missed an action")
	var seen: Dictionary = {}
	for event: Dictionary in pressure.outcomes:
		if event.kind == "action_started" and event.actor == 2: seen[event.action] = true
	check(seen.has("step") and seen.has("slash_1") and seen.has("slash_2"), "Pressure sequence did not actually execute step/combination")
	var slash_start: int = -1
	for event: Dictionary in pressure.outcomes:
		if event.kind == "action_started" and event.actor == 2 and event.action == "slash_1": slash_start = event.at_ms
		if event.kind == "action_started" and event.actor == 2 and event.action == "slash_2":
			check(slash_start >= 0 and event.at_ms < slash_start + int(Defs.ACTIONS.slash_1.windup + Defs.ACTIONS.slash_1.active + Defs.ACTIONS.slash_1.recovery), "Sequence ignored the legal combination cancel window")
	var shooter: RefCounted = fixture()
	setup_actor(shooter, 2, "archer", "ranged")
	shooter.pages[0].positions[1] = shooter.pages[0].positions[0] + Vector2(5.5, 0)
	shooter.combat.engage(shooter, 2, 1)
	shooter.combat.cooldowns[2] = {"fan": 10000}
	advance(shooter, 501)
	check(shooter.combat.shots > 0, "Unavailable high-priority skill prevented primary fire")
	shooter.pages[0].positions[0] = shooter.pages[0].positions[1] + Vector2(2, 0)
	advance(shooter, 1401)
	check(shooter.pages[0].positions[0].distance_to(shooter.pages[0].positions[1]) > 2.5, "Ranged policy did not retreat when approached")
	var heavy: RefCounted = fixture()
	setup_actor(heavy, 2, "heavy", "heavy")
	heavy.pages[0].positions[1] = heavy.pages[0].positions[0] + Vector2(1.8, 0)
	heavy.combat.engage(heavy, 2, 1)
	advance(heavy, 501)
	check(heavy.combat.states.get(2, {}).get("kind") == "enemy_heavy" and heavy.combat.Defs.ACTIONS.enemy_heavy.punishable, "Heavy strategy lost its committed punishable attack")
	var scripted: RefCounted = fixture()
	setup_actor(scripted, 2, "archer", "precise")
	scripted.pages[0].positions[1] = scripted.pages[0].positions[0] + Vector2(6.0, 0)
	scripted.combat.engage(scripted, 2, 1)
	advance(scripted, 1501)
	check(scripted.combat.shots > 0 and scripted.decisions.latest[2].rule >= 0, "Registered strategy script did not drive the real executor")
	check(Persistence.candidate(Persistence.capture(scripted), 0) != null, "Legal single-action replacements lost their task identity")

func feedback_and_boundaries() -> void:
	var w: RefCounted = fixture()
	var page: RefCounted = w.pages[0]
	var source: int = w.source_objects[0]
	w.objects.records[2].autonomous = true
	page.positions[1] = w.Terrain.center(w.objects.records[source].tile)
	check(w.command({"kind": "take", "actor": 2, "target": source, "item": "wood", "amount": 1}).ok, "Autonomous one-off order rejected")
	check(w.decisions.records[2].task.binding == w.gate.current(2), "One-off resident order lost execution feedback")
	w.end_run(2, 0, "failed")
	w.livelihood.after_action(w, 2, 0)
	check(w.decisions.records[2].next_ms == 600, "Execution wake swallowed life retry delay")
	advance(w, 501)
	check(w.decisions.evaluations == 0, "Life failure retried every frame")
	w.decisions.released(2)
	w.adopt_work(2, w.elapsed_ms)
	page.modes[1] = w.Units.Mode.HARVEST
	page.source_ids[1] = 0
	page.due_ms[1] = 5000
	w.reservations[source] = 2
	page.hunger[1] = 4000
	var original: Dictionary = w.gate.current(2)
	advance(w, 1001)
	check(page.hunger[1] < 4000 and w.decisions.evaluations > 0 and w.gate.current(2) != original, "Needs threshold did not wake and replace ongoing work")
	var tactical: RefCounted = fixture()
	setup_actor(tactical, 2, "archer", "ranged")
	tactical.pages[0].positions[1] = tactical.pages[0].positions[0] + Vector2(2.0, 0)
	tactical.combat.engage(tactical, 2, 1)
	advance(tactical, 51)
	tactical.decisions.records[2].repath_ms = tactical.elapsed_ms + 300
	tactical.decisions._steer(tactical, 2, Vector2.RIGHT)
	tactical.pages[0].direct_velocities[1] = Vector2.RIGHT * 3.0
	tactical.decisions._move(tactical, 2, tactical.decisions.records[2], Vector2(126, 122), tactical.elapsed_ms, false)
	check(tactical.pages[0].direct_velocities[1].is_zero_approx() and tactical.pages[0].modes[1] == tactical.Units.Mode.IDLE, "Path throttling retained stale direct movement")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(tactical), 0)
	check(restored != null, "Movement channel handoff rejected restore")
	if restored != null:
		advance(tactical, 201)
		advance(restored, 201)
		check(tactical.pages[0].positions == restored.pages[0].positions, "Movement handoff drifted across restore")
	# A trapped resident still recognizes danger; a blocked escape is not a
	# claim that the attacker itself is unreachable or no longer threatening.
	var corner: RefCounted = fixture()
	setup_actor(corner, 2, "sword", "cautious")
	corner.combat.engage(corner, 2, 1)
	var origin: Vector2 = corner.pages[0].positions[1]
	for offset: Vector2i in [Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, -1), Vector2i(0, 1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1)]: corner.terrain.blocked[corner.Terrain.index(Vector2i(origin) + offset)] = 1
	corner.decisions.records[2].mode = "flee"
	corner.decisions._combat(corner, 2, corner.decisions.records[2], corner.decisions.policy(corner, 2), 0)
	check(corner.combat.engagements.has(2) and not corner.combat.unreachable.has(2), "Failed escape incorrectly blacklisted the attacker")
	# Buffered feedback must close even when input is discarded before start.
	var buffer: RefCounted = fixture()
	buffer.decisions.bind(buffer, 2, "basic")
	buffer.combat.intents[2] = {"button": "primary"}
	buffer.decisions.records[2].task = {"id": buffer.decisions._id(), "kind": "host", "binding": {}, "waiting": "buffered", "button": "primary", "result": ""}
	buffer.clear_input(2)
	check(buffer.decisions.records[2].task.is_empty() and buffer.decisions.wakeups.has(2), "Discarded buffer left a task waiting forever")

func sleep_and_manual() -> void:
	var w: RefCounted = fixture()
	w.decisions.bind(w, 2, "basic", {"reaction_ms": 0})
	w.decisions.bind(w, 3, "basic", {"reaction_ms": 700})
	w.step(1)
	var before: int = w.decisions.evaluations
	advance(w, 401)
	check(before == w.decisions.evaluations, "Idle daily policies were reevaluated every frame")
	check(w.decisions.records[2].params.reaction_ms == 0 and w.decisions.records[3].params.reaction_ms == 700, "Individual overrides leaked through a shared definition")
	w.decisions.records[2].task = {"id": w.decisions._id(), "kind": "host", "binding": {}, "waiting": "running", "result": "completed"}
	check(w.decisions.records[3].task.is_empty(), "Unit task memory was shared")
	w.command({"kind": "move", "actor": 2, "position": w.pages[0].positions[1] + Vector2(0.2, 0)})
	advance(w, 801)
	check(w.decisions.records[2].manual and w.pages[0].modes[1] == w.Units.Mode.IDLE, "Manual completion unexpectedly restored AI control")
	var data: Dictionary = Persistence.capture(w)
	data.domains.decisions.records[3].policy = "missing"
	check(Persistence.candidate(data, 0) == null, "Unknown strategy restored")
	data = Persistence.capture(w)
	data.domains.decisions.movement[3] = Vector2(INF, 0)
	check(Persistence.candidate(data, 0) == null, "Non-finite tactical input restored")
	data = Persistence.capture(w)
	data.domains.decisions.records[3].next_ms = 10000
	check(Persistence.candidate(data, 0) == null, "Lost wakeup restored as a permanently sleeping task")
	data = Persistence.capture(w)
	data.domains.decisions.records[3]["arbitrary_state"] = {"unexpected": true}
	check(Persistence.candidate(data, 0) == null, "Unknown decision state bypassed schema validation")

func edge_handoffs() -> void:
	var resident: RefCounted = fixture()
	resident.objects.records[2].autonomous = true
	var source: int = resident.source_objects[0]
	resident.pages[0].positions[1] = resident.Terrain.center(resident.objects.records[source].tile)
	resident.command({"kind": "take", "actor": 2, "target": source, "item": "wood", "amount": 1})
	resident.forget_target(source)
	check(resident.decisions.wakeups.has(2), "Removed one-off target permanently suspended an autonomous resident")
	resident.objects.transfer(source, 2, "wood", 1)
	check(resident.command({"kind": "drop", "actor": 2, "item": "wood", "amount": 1}).ok and resident.decisions.wakeups.has(2), "Immediate drop lost the autonomous wakeup")
	var manual: RefCounted = fixture()
	manual.command({"kind": "action", "actor": 2, "button": "primary", "aim": Vector2.LEFT})
	manual.combat.engage(manual, 2, 1)
	check(manual.decisions.records[2].manual and manual.decisions.records[2].mode == "manual" and Persistence.candidate(Persistence.capture(manual), 0) != null, "Focus changed manual control before admission")
	advance(manual, 801)
	manual.command({"kind": "talk", "actor": 3, "target": 2})
	check(not manual.society.waits.has(2), "Cooperation commandeered a manually stopped unit")
	var summon: RefCounted = fixture()
	setup_actor(summon, 2, "companions", "basic")
	check(summon.combat.request(summon, 2, "skill", Vector2.LEFT, Vector2.ZERO, -1, summon.pages[0].positions[1]) == "started", "Summon failure fixture could not start")
	advance(summon, 201)
	summon.release(2)
	summon.combat.cooldowns.erase(2)
	check(summon.decisions._ready_reason(summon, 2, "skill", summon.elapsed_ms) == "summon_limit", "Own summon limit was absent from readiness")
	summon.decisions.records[2].task = {"id": summon.decisions._id(), "kind": "sequence", "steps": ["skill", "primary"], "index": 0, "binding": {}, "waiting": "", "button": "", "result": "", "deadline_ms": 6000}
	summon.decisions._sequence(summon, 2, summon.decisions.records[2], summon.decisions.policy(summon, 2), summon.pages[0].positions[0], summon.elapsed_ms)
	check(summon.decisions.records[2].task.is_empty(), "Unavailable sequence step blocked fallback until deadline")
	var replace: RefCounted = fixture()
	setup_actor(replace, 2, "sword", "pressure")
	replace.pages[0].positions[1] = replace.pages[0].positions[0] + Vector2(3.5, 0)
	replace.combat.engage(replace, 2, 1)
	advance(replace, 301)
	check(replace.decisions.records[2].task.get("kind") == "sequence", "Replacement fixture has no sequence")
	replace.end_run(2, replace.elapsed_ms) # External executor replacement, not natural completion.
	check(replace.decisions.records[2].task.is_empty() and Persistence.candidate(Persistence.capture(replace), 0) != null, "External replacement left an invalid sequence result")
	var recovery: RefCounted = fixture()
	setup_actor(recovery, 2, "heavy", "heavy")
	recovery.combat.request(recovery, 2, "primary", Vector2.LEFT)
	check(recovery.decisions._ready_reason(recovery, 2, "step", Defs.cancel_ms(recovery.combat.states[2], "step")).is_empty(), "Future post-recovery blocked a legal action cancel")
	# A hit between host steps must cancel the sequence even with no live gate.
	replace.decisions.records[2].task = {"id": replace.decisions._id(), "kind": "sequence", "steps": ["primary", "primary"], "index": 0, "binding": {}, "waiting": "running", "button": "primary", "result": "completed", "deadline_ms": 6000}
	replace.combat.damage(replace, 1, 2, 1, replace.elapsed_ms, Vector2.RIGHT, 0, 90)
	check(replace.decisions.records[2].task.is_empty(), "Between-step interruption retained an old sequence")
	var memory: RefCounted = fixture()
	var stove: int = memory.objects.create("furniture", "cook_stove", memory.Terrain.index(Vector2i(122, 120)))
	memory.objects.add(stove, "meal", 1)
	memory.knowledge.seed(memory, 2, memory.operation_target(stove), 0)
	memory.knowledge.record(2).subjects = {stove: memory.knowledge.records[2].subjects[stove]}
	memory.objects.add(stove, "meal", -1)
	memory.pages[0].positions[1] = Vector2(180.5, 180.5)
	memory.pages[0].hunger[1] = 3000
	# The original teacher now carries food. This case needs remembered food
	# to be the only known meal, otherwise eating from one's bag is correct.
	memory.objects.add(2, "meal", -memory.objects.amount(2, "meal"))
	memory.objects.records[2].autonomous = true
	memory.knowledge.record(2).due_ms = 5000
	memory.decisions.resume(memory, 2, 0)
	memory.decisions.prepare(memory, 0)
	check(memory.pages[0].modes[1] == memory.Units.Mode.EXPLORE and memory.work_runs.has(2) and memory.knowledge.view(2, stove, memory.elapsed_ms).inventory.get("meal") == 1, "Unseen stale evidence queried live availability instead of approaching to observe")
	var dirty: RefCounted = fixture()
	dirty.objects.records[2].autonomous = true
	dirty.adopt_work(2, 0)
	dirty.pages[0].modes[1] = dirty.Units.Mode.HARVEST
	dirty.pages[0].due_ms[1] = 5000
	var old: Dictionary = dirty.gate.current(2)
	dirty.decisions.wake(dirty, 2, 0, "needs_changed")
	dirty.decisions.wake(dirty, 2, 0, "contact") # Coalescing must retain the owner fact.
	dirty.decisions.prepare(dirty, 0)
	check(dirty.gate.current(2) != old and not dirty.decisions.records[2].life_dirty, "A same-time wake reason swallowed pending life reconsideration")
	var follower: RefCounted = fixture()
	follower.decisions.bind(follower, 2, "basic")
	follower.combat.engage(follower, 2, 1)
	follower.combat.intents[2] = {"button": "primary"}
	follower.decisions.follow(follower, 2, follower.pages[0].positions[1] + Vector2(15, 0), 0)
	follower.decisions.prepare(follower, 0)
	check(not follower.combat.intents.has(2) and follower.decisions.records[2].mode == "follow", "Leash break retained a buffer or lost follow control")

func sequence_loses_target() -> void:
	var w: RefCounted = fixture()
	setup_actor(w, 2, "sword", "pressure")
	w.pages[0].positions[1] = w.pages[0].positions[0] + Vector2(3.5, 0)
	w.combat.engage(w, 2, 1)
	advance(w, 301)
	check(w.decisions.records[2].task.get("kind", "") == "sequence" and w.combat.states.has(2), "Lost-target fixture did not reach an admitted sequence action")
	var binding: Dictionary = w.gate.current(2).duplicate()
	var activation: int = w.combat.next_activation
	w.pages[0].positions[0] += Vector2(60, 0)
	advance(w, 351)
	check(w.decisions.records[2].task.is_empty(), "Lost visibility kept future sequence steps")
	check(w.gate.current(2) == binding, "Lost visibility cancelled an already admitted strike")
	advance(w, 1001)
	check(w.combat.next_activation == activation, "Lost target still triggered a later sequence attack")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Lost-target sequence cleanup broke restore")

func ordinary_world_restoration() -> void:
	# Keep the normal world fixture: its enemies actually finish paths before
	# switching to tactical steering, unlike stationary combat-only fixtures.
	var w := World.new()
	w.initialize(24, 0)
	while w.elapsed_ms < 1000: w.step(100)
	for page: RefCounted in w.pages:
		for row: int in page.ids.size():
			check(page.route_cursors[row] <= page.routes[row].size(), "Tactical steering retained a cursor beyond its cleared route")
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Ordinary world's route-to-steering handoff rejected its own save")
	if restored == null: return
	advance(w, 1200)
	advance(restored, 1200)
	check(w.pages[0].positions == restored.pages[0].positions and w.pages[0].health == restored.pages[0].health, "Ordinary world movement or damage changed after restore")
	check(w.decisions.records == restored.decisions.records, "Ordinary world task state changed after restore")

func _run() -> void:
	authoring()
	living_handoff()
	strategies()
	feedback_and_boundaries()
	sleep_and_manual()
	edge_handoffs()
	sequence_loses_target()
	ordinary_world_restoration()
	print("DECISIONS_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
