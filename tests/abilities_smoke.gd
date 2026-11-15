extends SceneTree
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const Defs = preload("res://scripts/sim/kernel/action_defs.gd")
const Ability = preload("res://scripts/sim/definitions/combat/ability_def.gd")
var errors: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)
func fixture(profile: String = "fire") -> RefCounted:
	var w := World.new()
	w.initialize(4, 0)
	for id: int in w.actor_slots:
		w.release(id)
		w.objects.records[id].autonomous = false
		w.objects.records[id]["side"] = 0 if id == 1 else 1
		w.pages[0].positions[id - 1] = Vector2(120.5 + (id - 1) * 3, 120.5)
		w.pages[0].modes[id - 1] = w.Units.Mode.IDLE
		w.objects.records[id]["base_stats"] = {"max_hp": 2000.0}
		w.Equipment.rebuild(w, id)
		w.pages[0].health[id - 1] = 2000
	w.objects.records[1]["ability_loadout"] = profile
	w.Equipment.rebuild(w, 1)
	return w
func advance(w: RefCounted, until: int, passive: bool = true) -> void:
	while w.elapsed_ms < until:
		# Lifecycle fixtures suppress retaliation, independently of the production AI.
		if passive:
			for actor: int in w.combat.engagements.keys():
				w.combat.finish(w, actor, w.elapsed_ms)
		w.step(mini(16, until - w.elapsed_ms))
func same_after_restore(w: RefCounted, until: int, label: String) -> void:
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, label + ": candidate rejected")
	if restored == null: return
	advance(w, until)
	advance(restored, until)
	check(w.pages[0].health == restored.pages[0].health, label + ": changed damage")
	check(w.combat.bolts == restored.combat.bolts and w.areas.records == restored.areas.records and w.effects.records == restored.effects.records and w.implements.records == restored.implements.records, label + ": changed process state")

func catalog() -> void:
	check(Defs.ERRORS.is_empty() and Defs.ACTIONS.size() >= 22, "Catalog missing examples: " + str(Defs.ERRORS))
	check(Defs.ACTIONS.is_read_only() and Defs.ACTIONS.fire_bolt.delivery.is_read_only() and Defs.ACTIONS.fire_bolt.payload.is_read_only(), "Nested catalog is mutable")
	var original: Resource = load("res://data/definitions/combat/fire_bolt.tres")
	var copy: Resource = original.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	copy.id = "new_fire_variant"
	copy.delivery.count = 4
	copy.delivery.radius = 0.22
	check(copy.errors().is_empty() and copy.values().delivery.count == 4 and Defs.ACTIONS.fire_bolt.delivery.count == 1, "Independent resource variant corrupted original")
	copy.windup = -1
	check(not copy.errors().is_empty(), "Illegal timing accepted")
	var invalid_library: Resource = Defs.LIBRARY.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid_library.abilities[0].bundle.effects.append(null)
	invalid_library.abilities[0].delivery = null
	var rejected: Dictionary = invalid_library.compile()
	check(not rejected.errors.is_empty() and rejected.actions.is_empty(), "Missing nested resource crashed or compiled")
	invalid_library = Defs.LIBRARY.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	invalid_library.loadouts[0].reactions.append(null)
	rejected = invalid_library.compile()
	check(not rejected.errors.is_empty() and rejected.actions.is_empty(), "Missing loadout reaction crashed or compiled")
	invalid_library = Defs.LIBRARY.duplicate_deep(Resource.DEEP_DUPLICATE_ALL)
	for index: int in 2:
		var status: Resource = preload("res://scripts/sim/definitions/actions/status_def.gd").new()
		status.id = "nested_period_contract"
		status.kind = "dot"
		status.period_ms = 100 + index * 100
		var effect: Resource = preload("res://scripts/sim/definitions/actions/effect_def.gd").new()
		effect.kind = "status"
		effect.status = status
		invalid_library.abilities[index].bundle.effects.append(effect)
	check(str(invalid_library.compile().errors).contains("shared period"), "Native nested DoT definitions used incompatible periods")
	var w: RefCounted = fixture()
	var data: Dictionary = Persistence.capture(w)
	data.domains.combat.catalog_signature = "different-content"
	check(Persistence.candidate(data, 0) == null and w.pages[0].health[0] == 2000, "Foreign rule catalog adopted")

func ranged_statuses() -> void:
	var w: RefCounted = fixture()
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 110)
	check(w.combat.bolts.size() == 1, "Ordinary projectile missing")
	same_after_restore(w, 1500, "burning projectile and dot")
	check(w.pages[0].health[1] < 1986 and not w.effects.records.is_empty(), "Hit payload did not burn")
	var slow: RefCounted = fixture("frost")
	slow.combat.request(slow, 1, "primary", Vector2.RIGHT)
	advance(slow, 450)
	check(slow.effects.records.size() == 1 and slow.pages[0].move_scales[1] < 0.7, "Slow missing from body route multiplier")
	same_after_restore(slow, 1000, "homing and slow")
	var independent: RefCounted = fixture("fire")
	independent.objects.records[2]["ability_loadout"] = "fire"
	independent.combat.request(independent, 1, "skill", Vector2.RIGHT)
	independent.combat.request(independent, 2, "skill", Vector2.LEFT)
	check(independent.combat.states[1].activation != independent.combat.states[2].activation, "Shared activation")
	independent.combat.cooldowns[1].fire_fan += 700
	check(independent.combat.cooldowns[2].fire_fan == 2400, "Shared actor cooldown")
	advance(independent, 200)
	check(independent.combat.bolts.size() >= 8, "Scatter emission not configured")

func areas_and_implements() -> void:
	var w: RefCounted = fixture("thunder")
	check(w.combat.request(w, 1, "primary", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(123.5, 120.5)) == "started", "Point cast rejected")
	advance(w, 200)
	check(w.areas.records.size() == 1 and w.pages[0].health[1] == 2000 and w.combat.bolts.is_empty(), "Area created fake flight or hit before telegraph")
	same_after_restore(w, 700, "lightning telegraph")
	check(w.pages[0].health[1] < 2000, "Lightning never arrived")
	var sword: RefCounted = fixture("flying_sword")
	sword.combat.request(sword, 1, "primary", Vector2.RIGHT)
	advance(sword, 350)
	check(sword.implements.records.size() == 1, "Persistent implement missing")
	var id: int = sword.implements.owned(1)
	if id == 0: return
	sword.implements.hit(sword, id, 17, sword.elapsed_ms)
	advance(sword, 450)
	sword.combat.request(sword, 1, "skill", Vector2.RIGHT)
	same_after_restore(sword, 1500, "returning sword")
	check(sword.implements.records[id].phase == "stowed" and sword.implements.records[id].hp == 43 and sword.implements.records.size() == 1, "Recall copied or repaired implement")
	var dead: RefCounted = fixture("thunder")
	dead.combat.request(dead, 1, "primary", Vector2.RIGHT, Vector2.ZERO, -1, Vector2(123.5, 120.5))
	advance(dead, 200)
	dead.combat.damage(dead, 2, 1, 10000, dead.elapsed_ms)
	advance(dead, 700)
	check(dead.pages[0].health[1] < 2000, "Caster death deleted committed area")

func boundaries() -> void:
	var w: RefCounted = fixture("fire")
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 500)
	check(not w.effects.records.is_empty(), "No periodic lifetime to check")
	if w.effects.records.is_empty(): return
	var until: int = w.effects.records.values()[0].until_ms
	advance(w, until)
	var hp: int = w.pages[0].health[1]
	same_after_restore(w, until + 100, "exclusive periodic expiry")
	check(w.pages[0].health[1] == hp and w.effects.records.is_empty(), "Periodic expiry generated an extra endpoint tick")
	var removed: RefCounted = fixture("fire")
	removed.combat.request(removed, 1, "primary", Vector2.RIGHT)
	advance(removed, 500)
	check(removed.remove_actor(2) and removed.effects.records.is_empty() and Persistence.candidate(Persistence.capture(removed), 0) != null, "Removing an affected target left invalid lifetimes")
	var source: RefCounted = fixture("fire")
	source.combat.request(source, 1, "primary", Vector2.RIGHT)
	advance(source, 500)
	source.kill(1)
	hp = source.pages[0].health[1]
	same_after_restore(source, 1500, "periodic source death")
	check(source.pages[0].health[1] < hp, "Source death deleted committed periodic damage")
	var seeker: RefCounted = fixture("frost")
	seeker.objects.records[3].side = 0
	seeker.objects.records[4].side = 0
	seeker.pages[0].positions[1] = Vector2(126.5, 122.5)
	seeker.combat.request(seeker, 1, "primary", Vector2.RIGHT)
	advance(seeker, 130)
	var bolt: Dictionary = seeker.combat.bolts.values()[0]
	check(bolt.target == 2 and absf(bolt.velocity.y) > 0.01, "Homing did not acquire/steer to an observed target")
	seeker.pages[0].positions[1] = Vector2(150.5, 150.5)
	var velocity: Vector2 = bolt.velocity
	advance(seeker, 230)
	check(bolt.velocity.is_equal_approx(velocity), "Homing followed hidden live coordinates")
	var data: Dictionary = Persistence.capture(seeker)
	data.domains.combat.bolts.values()[0].turn = "bad"
	check(Persistence.candidate(data, 0) == null and seeker.combat.bolts.values()[0].turn is float, "Malformed projectile was adopted or mutated live rules")
	var implement: RefCounted = fixture("flying_sword")
	implement.combat.request(implement, 1, "primary", Vector2.RIGHT)
	advance(implement, 300)
	implement.kill(1)
	var sword: Dictionary = implement.implements.records.values()[0]
	check(sword.phase == "dropped", "Owner death left an autonomous deployed sword")
	var point: Vector2 = sword.position
	same_after_restore(implement, 800, "dropped implement")
	check(sword.position == point, "Dropped implement continued moving")
	implement.implements.hit(implement, sword.id, 999, implement.elapsed_ms)
	check(sword.hp == 0 and sword.phase == "broken" and implement.implements.readiness(1, "sword_dispatch") == "implement_broken", "Broken implement respawned through readiness")

func implement_contacts() -> void:
	var w: RefCounted = fixture("flying_sword")
	w.combat.request(w, 1, "primary", Vector2.RIGHT)
	advance(w, 200)
	w.release(1)
	var sword: Dictionary = w.implements.records.values()[0]
	sword.position = Vector2(124, 120.5)
	sword.hp = 5
	w.pages[0].positions[1] = Vector2(127.5, 120.5)
	w.pages[0].positions[2] = Vector2(123.2, 120.5)
	w.objects.records[3].side = 0
	w.combat.launch(2, Vector2(125.2, 120.5), Vector2(120, 120.5), 200, 7, 0, 60)
	w.combat.launch(2, Vector2(126, 120.5), Vector2(120, 120.5), 200, 9, 0, 60)
	var restored: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(restored != null, "Projectile/implement contact candidate rejected")
	w.step(50)
	if restored != null:
		restored.step(50)
		check(w.pages[0].health == restored.pages[0].health and w.implements.records == restored.implements.records, "Same-slice implement break changed after restore")
	check(sword.phase == "broken" and w.pages[0].health[2] == 1991, "Destroyed implement swallowed a later projectile in the same interval")
	var catching: RefCounted = fixture("flying_sword")
	catching.combat.request(catching, 1, "primary", Vector2.RIGHT)
	advance(catching, 200)
	catching.release(1)
	sword = catching.implements.records.values()[0]
	sword.phase = "returning"
	sword.position = Vector2(121.1, 120.5)
	catching.combat.launch(2, Vector2(121.3, 120.5), Vector2(120, 120.5), 200, 9)
	catching.step(50)
	check(sword.phase == "stowed" and sword.hp == 51, "End-of-slice catch erased an earlier in-flight contact")
	var wall: RefCounted = fixture("flying_sword")
	for id: int in [2, 3, 4]: wall.pages[0].positions[id - 1] = Vector2(140.5, 130.5 + id)
	wall.command({"kind": "build", "tile": wall.Terrain.index(Vector2i(124, 120)), "structure": 1})
	wall.flush_topology()
	wall.combat.request(wall, 1, "primary", Vector2.RIGHT)
	advance(wall, 1200)
	check(wall.implements.records.size() == 1 and wall.implements.records.values()[0].phase == "stowed", "Outbound wall turn immediately dropped or duplicated sword")
	var overlap: RefCounted = fixture("flying_sword")
	overlap.combat.request(overlap, 1, "primary", Vector2.RIGHT)
	advance(overlap, 200)
	sword = overlap.implements.records.values()[0]
	sword.phase = "returning"
	sword.position = overlap.combat.position(overlap, 1)
	overlap.step(16)
	check(sword.phase == "stowed" and Persistence.candidate(Persistence.capture(overlap), 0) != null, "Coincident catch left a zero-direction save")

func periodic_refresh() -> void:
	var w: RefCounted = fixture("fire")
	w.combat.next_activation = 2
	w.effects.apply(w, 2, 1, 1, "fire_bolt", 0, 20)
	advance(w, 2150)
	var hp: int = w.pages[0].health[1]
	w.combat.launch(1, Vector2(122.15, 120.5), Vector2(125, 120.5), 2150, 20, 1, 20)
	w.combat.bolts.values()[0].ability = "fire_bolt"
	w.combat.bolts.values()[0].payload = Defs.ACTIONS.fire_bolt.payload
	w.step(50) # Contact at 2195 renews the old excluded tick at 2200.
	check(w.pages[0].health[1] == hp - 22 and w.effects.records.values()[0].next_ms == 2750, "Expiry-slice refresh lost or delayed a periodic tick")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Refreshed endpoint rejected a valid save")

func _run() -> void:
	catalog()
	ranged_statuses()
	areas_and_implements()
	boundaries()
	implement_contacts()
	periodic_refresh()
	print("ABILITIES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
