extends SceneTree
## Different bodies share the real host, costs, environment and restore boundary.
const World = preload("res://scripts/sim/kernel/world.gd")
const Persistence = preload("res://scripts/sim/kernel/persistence.gd")
const Costs = preload("res://scripts/sim/kernel/action_costs.gd")
const Beings = preload("res://scripts/sim/kernel/being_defs.gd")
var errors: int = 0

func _initialize() -> void: call_deferred("_run")
func check(ok: bool, message: String) -> void:
	if not ok: errors += 1; push_error(message)

func _run() -> void:
	check(Beings.ERRORS.is_empty() and Beings.FORMS.is_read_only() and Beings.FORMS.human.capabilities.is_read_only(), "Body catalog was not validated/frozen")
	var form: Resource = preload("res://data/definitions/beings/human.tres").duplicate(true)
	form.capabilities = 16
	check(not form.errors().is_empty(), "Unknown authored capability bits were accepted")
	var w := World.new()
	w.initialize(4, 0)
	for id: int in w.actor_slots:
		w.command({"kind": "interrupt", "actor": id})
		w.pages[0].positions[id - 1] = Vector2(145.5 + id, 145.5)
	var count: int = w.actor_count
	var worker: int = w.spawn_actor(w.Terrain.index(Vector2i(149, 146)), "clockwork")
	check(worker > 0 and w.actor_count == count + 1, "Independent nonhuman body was not counted")
	if worker == 0: quit(1); return
	var slot: int = w.actor_slots[worker]
	var page: RefCounted = w.pages[slot / 256]
	var row: int = slot % 256
	var chest: int = w.facilities.create_completed(w, "wood_chest", w.Terrain.index(Vector2i(150, 145)))
	w.objects.transfer(w.source_objects[0], chest, "wood", 5)
	check(w.begin_transfer(worker, {"kind": "take", "target": chest, "item": "wood", "amount": 2}) == "accepted", "Nonhuman labor was rejected")
	w.step(2500)
	check(w.objects.amount(worker, "wood") == 2 and w.objects.amount(chest, "wood") == 3, "Nonhuman labor did not move actual materials")
	var human_energy: int = page.energy[0]
	var construct_energy: int = page.energy[row]
	var construct_heat: float = page.body_heat[row]
	page.sample_environment(1.0)
	check(page.energy[0] < human_energy and page.energy[row] == construct_energy and page.body_heat[row] == construct_heat, "Independent metabolism/environment capabilities were ignored")
	check(w.begin_interaction(worker, {"kind": "eat", "target": chest}) == "body_has_no_metabolism_capability", "Body without metabolism was allowed to eat")
	check(not w.society.available(w, 1, {"kind": "talk", "target": worker}), "Noncommunicating body was offered as a partner")
	check(w.set_capability_overrides(worker, {"contact": true}) and w.society.available(w, 1, {"kind": "talk", "target": worker}), "Individual source difference did not grant contact")
	check(w.begin_transfer(worker, {"kind": "put", "target": chest, "item": "wood", "amount": 1}) == "accepted", "Second labor run failed")
	check(w.set_capability_overrides(worker, {"work": false, "contact": true}), "Legal capability change failed")
	check(not w.actions.has(worker) and w.gate.current(worker).is_empty() and w.objects.amount(worker, "wood") == 2, "Lost capability left an active or partially committed run")
	check(w.command({"kind": "move", "actor": worker, "position": Vector2(148.5, 146.5)}).ok, "Movement was incorrectly tied to labor")
	var saved: Dictionary = Persistence.capture(w)
	var loaded: RefCounted = Persistence.candidate(saved, 0)
	check(loaded != null, "Capability state/manual motion failed restore")
	if loaded != null:
		check(loaded.describe(worker).body_capabilities.contact and not loaded.describe(worker).body_capabilities.work and loaded.pages[slot / 256].needs_enabled[row] == 0, "Restore lost source differences")
	w.command({"kind": "interrupt", "actor": worker})
	check(w.set_capability_overrides(worker, {}), "Resetting source differences failed")
	check(w.begin_transfer(worker, {"kind": "put", "target": chest, "item": "wood", "amount": 1}) == "accepted", "Active save fixture failed")
	var illegal: Dictionary = Persistence.capture(w)
	illegal.domains.objects.records[worker]["capability_overrides"] = {"work": false}
	check(Persistence.candidate(illegal, 0) == null, "Restore accepted an active operation without its capability")
	saved.being_signature = "incorrect"
	check(Persistence.candidate(saved, 0) == null, "Restore accepted different body rules")
	var record: Dictionary = w.objects.records[worker].duplicate(true)
	record["capabilities"] = {"work": true}
	check(not Beings.valid_record(record), "Derived abilities became save truth")
	record.erase("capabilities")
	record["capability_overrides"] = {"work": 1}
	check(not Beings.valid_record(record), "Illegal source capability type accepted")
	var total: int = w.objects.audit_total("wood")
	check(w.remove_actor(worker), "Worker removal failed")
	var replacement: int = w.spawn_actor(w.Terrain.index(Vector2i(149, 146)))
	check(w.actor_slots[replacement] == slot and page.needs_enabled[row] == 1 and page.environment_enabled[row] == 1 and page.armor[row] == 0 and w.objects.audit_total("wood") == total, "Reused body inherited capabilities or lost belongings")
	var companion: int = w.spawn_actor(w.Terrain.index(Vector2i(149, 148)), "companion")
	check(companion > 0 and w.actor_count == count + 2 and w.counters().alive == count + 2, "Persistent companion form was mistaken for a temporary summon")
	check(w.describe(companion).body_capabilities == {"work": false, "contact": false, "metabolism": false, "environment": false} and not w.command({"kind": "work", "actor": companion}).ok, "Original companion abilities changed")
	check(Persistence.candidate(Persistence.capture(w), 0) != null, "Independent companion could not restore")
	var static_id: int = chest
	w.objects.records[static_id]["qi"] = 50
	check(Costs.pay(w, static_id, [{"kind": "qi", "id": "", "amount": 20}, {"kind": "item", "id": "wood", "amount": 1}]) and w.objects.records[static_id].qi == 30, "Static item/qi costs failed")
	check(not Costs.pay(w, static_id, [{"kind": "energy", "id": "", "amount": 1}]) and not Costs.pay(w, -1, []), "Unavailable carrier resource was fabricated")
	check(w.begin_interaction(static_id, {"kind": "take", "target": replacement}) == "unsupported_carrier" and w.gate.check(w, static_id, w.elapsed_ms) == "unsupported_carrier", "Static motion lacked an explicit boundary")
	contact_and_work()
	print("BEING_CAPABILITIES_SMOKE errors=", errors)
	quit(0 if errors == 0 else 1)

func contact_and_work() -> void:
	var w := World.new()
	w.initialize(4, 0)
	var page: RefCounted = w.pages[0]
	for id: int in w.actor_slots:
		w.command({"kind": "interrupt", "actor": id})
		page.positions[id - 1] = Vector2(145.5 + id, 145.5)
	# Player/busy targets need not join the partner host; admission is rechecked
	# on arrival/completion, rather than broadcasting a remote capability edit.
	check(w.begin_interaction(3, {"kind": "talk", "target": 1}) == "accepted" and not w.society.waits.has(1), "Uninvited contact fixture failed")
	w.set_capability_overrides(1, {"contact": false})
	var mid_loaded: RefCounted = Persistence.candidate(Persistence.capture(w), 0)
	check(mid_loaded != null, "Legitimate in-flight contact was rejected before observing target changes")
	if mid_loaded != null:
		mid_loaded.step(2500)
		check(not mid_loaded.actions.has(3) and int(mid_loaded.society.completed.get("talk", 0)) == 0, "Restored in-flight contact ignored target qualification")
	w.step(2500)
	check(not w.actions.has(3) and w.society.waits.is_empty() and int(w.society.completed.get("talk", 0)) == 0 and Persistence.candidate(Persistence.capture(w), 0) != null, "Uninvited target lost contact but was still used or produced an unloadable save")
	w.set_capability_overrides(1, {})
	w.decisions.resume(w, 2, w.elapsed_ms)
	check(w.begin_interaction(3, {"kind": "talk", "target": 2}) == "accepted" and w.society.waits.has(2), "Joined contact fixture failed")
	w.set_capability_overrides(2, {"contact": false})
	check(not w.actions.has(3) and w.society.waits.is_empty() and not w.reservations.has(2), "Partner capability loss leaked the other participant")
	w.set_capability_overrides(2, {})
	page.hunger[1] = 10000
	page.energy[1] = 10000
	w.objects.claim(w.source_objects[0], 1, "wood", 4)
	var plan: Dictionary = w.facilities.blueprint(w, 1, "wood_wall", w.Terrain.index(Vector2i(152, 147)))
	check(plan.reason == "accepted", "Help fixture placement failed")
	if plan.reason == "accepted":
		var target: int = plan.target
		w.objects.records[target].remaining_ms = 1000 # Short work fixture, same real lifecycle.
		var delivered: Dictionary = w.society.deliver_request(w, 1, {"kind": "request_help", "target": 2, "task_target": target}, w.elapsed_ms)
		check(delivered.status == "completed", "Temporary help request could not reach the other actor")
		if delivered.status != "completed": return
		var accepted: Dictionary = w.society.respond(w, 2, int(delivered.facts.request), "accept", w.elapsed_ms)
		check(accepted.reason == "accepted_share", "Temporary helper could not explicitly accept: " + str(accepted.reason))
		page.positions[1] = Vector2(151.5, 147.5)
		check(w.begin_interaction(2, {"kind": "construct", "target": target, "autonomous": true}) == "accepted", "Temporary builder could not start")
		w.step(300)
		var material: int = w.objects.audit_total("wood")
		var remaining: int = w.objects.records[target].remaining_ms
		w.set_capability_overrides(2, {"work": false})
		check(not w.objects.records[2].has("commitment") and not w.institutions.Matters.shares_for(w.institutions, 2).is_empty() and not w.objects.records[2].autonomous and not w.actions.has(2) and w.objects.records[target].remaining_ms < remaining, "Capability loss did not stop temporary help while retaining its obligation and actual labor")
		page.positions[0] = Vector2(151.5, 147.5)
		check(w.begin_interaction(1, {"kind": "construct", "target": target}) == "accepted", "Replacement builder could not reuse the site")
		w.step(4500)
		check(w.objects.records[target].kind != "blueprint" and w.objects.audit_total("wood") == material, "Replacement builder repeated materials or lost committed labor")
	w.set_capability_overrides(2, {})
	var source: int = w.source_objects[0]
	page.positions[1] = w.Terrain.center(w.objects.records[source].tile)
	page.source_ids[1] = 0
	check(w.adopt_work(2, w.elapsed_ms), "Legacy harvest host failed")
	page.move_to(1, page.positions[1], w.Units.Mode.RESOURCE)
	w.step(50)
	check(page.modes[1] == w.Units.Mode.HARVEST and w.reservations.get(source, 0) == 2, "Real harvest did not claim its source")
	w.set_capability_overrides(2, {"work": false})
	check(not w.work_runs.has(2) and not w.reservations.has(source), "Harvest ability loss leaked its claim")
	w.objects.add(1, "breath_manual", 1)
	w.set_capability_overrides(1, {"contact": false})
	check(w.begin_interaction(1, {"kind": "study", "target": 1}) == "accepted", "Solitary reading was incorrectly tied to interpersonal contact")
	w.step(1500)
	check(w.objects.records[1].get("methods", {}).has("wood_breath"), "Solitary reading did not learn from its real book")
	w.set_capability_overrides(1, {"metabolism": false})
	check(w.begin_interaction(1, {"kind": "practice", "target": source}) == "body_has_no_metabolism_capability" and Costs.available(w, 1, "energy:") == -1, "Nonmetabolic body spent placeholder body resources")
	w.kill(2)
	check(not w.set_capability_overrides(2, {}), "A dead body was awakened by a capability edit")
