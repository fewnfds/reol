extends "res://tests/abilities_smoke.gd"
const Status = preload("res://scripts/sim/definitions/actions/status_def.gd")

func decide(w: RefCounted, targets: Array) -> void:
	var person: Dictionary = w.objects.records[2]
	person.autonomous = true
	w.knowledge.record(2).subjects = {}
	w.knowledge.record(2).due_ms = 5000
	for target: int in targets: w.knowledge.seed(w, 2, w.operation_target(target), 0)
	w.decisions.resume(w, 2, 0)
	w.decisions.prepare(w, 0)

func known_sites_and_growth() -> void:
	var tree_world: RefCounted = fixture()
	var tree: int = 0
	for id: int in tree_world.nature.ids:
		if tree_world.objects.records[id].definition == "old_tree": tree = id; break
	var rec: Dictionary = tree_world.objects.records[tree]
	rec.stage = tree_world.nature.Stage.STUMP
	tree_world.nature._sync(tree_world, tree)
	tree_world.flush_topology()
	var low: Vector2i = tree_world.Terrain.cell(rec.tile)
	var body: Vector2 = Vector2(low) + Vector2(-0.1, 0.5)
	tree_world.pages[0].positions[0] = body
	rec.stage = tree_world.nature.Stage.MATURE
	rec.growth_ms = int(tree_world.nature.definitions.old_tree.mature_ms)
	tree_world.nature._sync(tree_world, tree)
	tree_world.flush_topology()
	check(tree_world.terrain.can_stand(body, 0.35), "Maturing tree trapped a ground body overlapping its edge")
	var storage: RefCounted = fixture()
	var full: int = storage.objects.create("chest", "wood_chest", storage.Terrain.index(Vector2i(124, 120)), 1)
	storage.objects.add(full, "wood", 1)
	var other: int = storage.objects.create("chest", "wood_chest", storage.Terrain.index(Vector2i(125, 120)), 20)
	storage.objects.add(2, "wood", 1)
	storage._sync_inventory(2)
	decide(storage, [full, other])
	check(storage.actions.get(2, {}).get("target") == other, "Resident selected a known full chest over usable storage")
	var seeded: RefCounted = fixture()
	var plant: int = seeded.nature.create(seeded, "perennial_herb", seeded.Terrain.index(Vector2i(124, 120)), true)
	check(plant > 0, "Seed fixture could not be planted")
	if plant > 0:
		seeded.objects.add(plant, "herb", 1)
		decide(seeded, [plant])
		check(seeded.actions.get(2, {}).get("kind", "") != "gather", "Resident mistook an unplanted seed for ripe produce")
	var commitment: RefCounted = fixture()
	commitment.pages[0].hunger[1] = 10000
	commitment.pages[0].energy[1] = 10000
	commitment.pages[0].positions[1] = commitment.pages[0].positions[0] + Vector2(0.8, 0)
	commitment.livelihood.forget(2)
	commitment.objects.claim(commitment.source_objects[0], 1, "wood", 4)
	var result: Dictionary = commitment.facilities.blueprint(commitment, 1, "wood_wall", commitment.Terrain.index(Vector2i(124, 121)))
	check(result.reason == "accepted", "Commitment blueprint fixture failed")
	if result.reason == "accepted":
		var offer: String = commitment.society.finish(commitment, 1, {"kind": "request_help", "target": 2, "task_target": result.target}, 0)
		check(offer == "accepted_share" and not commitment.institutions.Matters.shares_for(commitment.institutions, 2).is_empty(), "Real help request failed: " + offer)
		commitment.command({"kind": "interrupt", "actor": 2})
		commitment.facilities.demolish(commitment, result.target)
		commitment.command({"kind": "work", "actor": 2})
		check(commitment.objects.records[2].autonomous, "Stale help commitment overrode an explicit work command")

func cooperation_and_control() -> void:
	var build: RefCounted = fixture()
	build.objects.claim(build.source_objects[0], 1, "wood", 20)
	var tile: int = build.Terrain.index(Vector2i(120, 120))
	var result: Dictionary = build.command({"kind": "construct", "definition": "wood_wall", "tile": tile})
	check(result.ok, "Build-on-self fixture was refused")
	if result.ok:
		build.objects.records[result.target].remaining_ms = 1000
		advance(build, 6000)
		check(build.objects.records[result.target].kind == "wall", "Builder stayed inside its own blueprint and blocked completion")
	var manual: RefCounted = fixture()
	manual.objects.records[2].autonomous = true
	manual.decisions.resume(manual, 2, 0)
	var chest: int = manual.objects.create("chest", "wood_chest", manual.Terrain.index(Vector2i(124, 120)))
	manual.objects.add(chest, "grain", 5)
	check(manual.begin_transfer(2, {"kind": "take", "target": chest, "item": "grain", "amount": 1}) == "accepted", "Manual transfer fixture refused")
	var binding: Dictionary = manual.gate.current(2)
	manual.decisions.wake(manual, 2, 0, "needs_changed")
	manual.decisions.prepare(manual, 0)
	check(manual.gate.current(2) == binding, "A need threshold preempted an explicit one-off transfer")
	var partner: RefCounted = fixture()
	partner.objects.records[2].autonomous = true
	partner.decisions.resume(partner, 2, 0)
	check(partner.begin_interaction(1, {"kind": "talk", "target": 2}) == "accepted", "Partner fixture refused")
	var social: Dictionary = partner.gate.current(1)
	check(partner.gate.current(2).get("domain") == "partner", "Partner never waited")
	partner.decisions.wake(partner, 2, 0, "needs_changed")
	partner.decisions.prepare(partner, 0)
	check(partner.gate.current(1) == social, "A routine need threshold made the invited partner abandon conversation")
	var help: RefCounted = fixture()
	help.pages[0].hunger[1] = 10000
	help.pages[0].energy[1] = 10000
	help.pages[0].positions[1] = help.pages[0].positions[0] + Vector2(0.8, 0)
	help.livelihood.forget(2)
	help.objects.claim(help.source_objects[0], 1, "wood", 20)
	var plan: Dictionary = help.facilities.blueprint(help, 1, "wood_wall", help.Terrain.index(Vector2i(124, 121)))
	var target: int = plan.target
	check(help.begin_interaction(1, {"kind": "construct", "target": target}) == "accepted", "Busy help fixture refused")
	var offered: String = help.society.finish(help, 1, {"kind": "request_help", "target": 2, "task_target": target}, 0)
	check(offered == "accepted_share", "Busy help offer failed: " + offered)
	help.livelihood.choose(help, 2, 0)
	check(help.gate.current(2).is_empty() and help.pages[0].modes[1] == help.Units.Mode.IDLE, "A busy help target sent a temporary helper into unrelated resident work")
	var distant: RefCounted = fixture()
	distant.pages[0].hunger[1] = 10000
	distant.pages[0].energy[1] = 10000
	distant.pages[0].positions[1] = distant.pages[0].positions[0] + Vector2(0.8, 0)
	distant.livelihood.forget(2)
	distant.objects.claim(distant.source_objects[0], 1, "wood", 20)
	var far: Dictionary = distant.facilities.blueprint(distant, 1, "wood_wall", distant.Terrain.index(Vector2i(160, 120)))
	var far_offer: String = distant.society.finish(distant, 1, {"kind": "request_help", "target": 2, "task_target": far.target}, 0)
	check(far_offer == "accepted_share", "The builder forgot its own blueprint when requesting distant help: " + far_offer)
	var rooted: RefCounted = fixture()
	var nearby: int = rooted.objects.create("pile", "grain", rooted.Terrain.index(Vector2i(120, 120)))
	rooted.objects.add(nearby, "grain", 1)
	var status := Status.new()
	status.id = "stationary_root"
	status.kind = "root"
	status.duration_ms = 1000
	rooted.effects.add(rooted, 1, 2, 0, "", status.values(), 0, 0)
	check(rooted.begin_transfer(1, {"kind": "take", "target": nearby, "item": "grain", "amount": 1}) == "accepted", "Rooted in-range transfer refused")
	advance(rooted, 400)
	check(rooted.objects.amount(nearby, "grain") == 0, "Root prevented arrival at the position already occupied by the actor")

func _run() -> void:
	known_sites_and_growth()
	cooperation_and_control()
	print("LIVELIHOOD_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)
